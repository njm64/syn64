//----------------------------------------------------------------------------
// Segment definitions
//----------------------------------------------------------------------------

.label zp_start = $02
.segmentdef ZeroPage [start=zp_start, max=$FF, virtual]
.segmentdef HighData [start=$C800, max=$CFFF, virtual]

//----------------------------------------------------------------------------
// General purpose zero page temporary values (not preserved across calls)
//----------------------------------------------------------------------------

.segment ZeroPage
T0: .byte 0
T1: .byte 0
T2: .byte 0
T3: .byte 0

//----------------------------------------------------------------------------
// VM registers
//----------------------------------------------------------------------------

.segment ZeroPage
reg_base: .fillword 8, 0    // 8 general purpose VM registers
reg_ip:   .word 0           // VM Instruction pointer

//----------------------------------------------------------------------------
// VM Stack
//----------------------------------------------------------------------------

.segment HighData
.align $100
stack: .fill $100, 0        // Stack is 256 bytes in the high data section

.segment ZeroPage
stack_ptr: .byte $00        // Stack pointer in zero page

//----------------------------------------------------------------------------
// Main program starts here
//----------------------------------------------------------------------------

.segment Default
BasicUpstart2(start)
#import "kernal.asm"
#import "input.asm"
#import "print.asm"
#import "mem.asm"
#import "op.asm"

.segment ZeroPage
.label zp_end=*             // Mark the end of our ZP data so we know
.segment Default            // how much to clear

//----------------------------------------------------------------------------
// Main entry point
//----------------------------------------------------------------------------
 
start: {
    lda #$36                // Switch out BASIC ROM so we can use 
    sta $01                 // the RAM underneath from $A000-$C000

    lda #$93                // Clear the screen
    jsr chrout

    lda #$17                // Switch to the uppercase/lowercase
    sta $D018               // character set

    lda #$00                // Clear zero page data
    ldx #zp_start
!:  sta $00,x
    inx
    cpx #zp_end
    bne !-

    jsr mem_init            // Initialise the paging system
    jmp next                // Execute the first instruction
}

//----------------------------------------------------------------------------
// Execute the next instruction
//----------------------------------------------------------------------------

next: {
    jsr fetch_word          // Fetch the next instruction
    cmp #$16                // Make sure it's in range
    bcs invalid_op
    asl                     // Double it to get the jump table offset
    tay
    lda op_table,y          // Get the jump address low byte
    sta T0
    lda op_table+1,y        // Get the jump address high byte
    sta T1
    jmp (T0)                // Jump to the handler function
}

//----------------------------------------------------------------------------
// Print an invalid opcode error and halt the VM
// Input: Opcode in A
//----------------------------------------------------------------------------

invalid_op: {
    pha                     // Save the opcode
    lda reg_ip+1            // Print the current instruction pointer
    jsr print_hex
    lda reg_ip
    jsr print_hex
    lda #<message           // Print the error message
    ldy #>message
    jsr print_sz
    pla                     // Restore the saved opcode
    jsr print_hex           // Print it
    jmp *                   // Halt
message:
    .encoding "petscii_mixed"
    .text ": Invalid opcode "
    .byte 0
}

//----------------------------------------------------------------------------
// Fetch the word at the current instruction pointer, then increment the
// instruction pointer.
// Output:   Value in A (low byte) and X (high byte).
// Modifies: Y
//----------------------------------------------------------------------------

fetch_word: {
    lda reg_ip              // Load the low byte of IP
    asl                     // Shift left to double it
    pha                     // Save it on the stack
    lda reg_ip+1            // Load the high byte of the IP
    rol                     // Double it, with carry from the low byte
    jsr map_page            // Map logical page to physical page
    sta T1                  // High byte of physical address is now in T1
    pla                     // Restore low byte of physical address
    sta T0                  // Low byte of physical address is not in T0
    ldy #$01
    lda (T0),y              // Get the high byte of the word
    tax                     // Return it in X
    dey
    lda (T0),y              // Get the low byte and return in A
    inc reg_ip              // Increment the low byte of the IP
    bne !+
    inc reg_ip+1            // Increment the high byte if necessary
!:  rts   
}

//----------------------------------------------------------------------------
// Fetch an operand value. 
// Values < $8000 are literals. 
// Values from $8000-$8007 inclusive are register indices.
// Values greater than $8007 are invalid.
// Output:   Value in A (low byte) and X (high byte).
// Modifies: Y
//----------------------------------------------------------------------------

fetch_value: {
    jsr fetch_word          // Fetch the next word into A,X
    cpx #$80                // If the high byte is >= 0x80, it's a register
    bcs register
    rts                     // Return the literal value
register:
    and #$07                // Only need the bottom 3 bits
    asl                     // Shift left to get the register zp offset
    tay
    lda reg_base,Y          // Return the low byte of the register in A
    ldx reg_base+1,Y        // Return the high byte of the register in X
    rts
}

//----------------------------------------------------------------------------
// Fetch a register index, and return the offset from reg_base to the
// selected register.
// Output:   Register offset in A
// Modifies: Y
//----------------------------------------------------------------------------

fetch_reg: {
    jsr fetch_word
    and #$07
    asl
    rts
}

