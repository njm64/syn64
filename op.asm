//----------------------------------------------------------------------------
// Zero page storage for operand values, usually corresponding to 
// A, B, and C in the arch-spec
//----------------------------------------------------------------------------

.segment ZeroPage
A: .word 0
B: .word 0
C: .word 0

.segment Default

//----------------------------------------------------------------------------
// Jump table
//----------------------------------------------------------------------------

op_table:
  .word op_halt
  .word op_set
  .word op_push
  .word op_pop
  .word op_eq
  .word op_gt
  .word op_jmp
  .word op_jt
  .word op_jf
  .word op_add
  .word op_mult
  .word op_mod
  .word op_and
  .word op_or
  .word op_not
  .word op_rmem
  .word op_wmem
  .word op_call
  .word op_ret
  .word op_out
  .word op_in
  .word op_nop

//----------------------------------------------------------------------------
// Halt: 0
// Stop execution and terminate the program
//----------------------------------------------------------------------------

op_halt: 
    jmp op_halt

//----------------------------------------------------------------------------
// Set: 1 A B
// Set register <A> to the value of <B>
//----------------------------------------------------------------------------

op_set: {
    jsr fetch_reg           // Fetch A
    sta A
    jsr fetch_value         // Fetch B
    ldy A
    sta reg_base,y          // Store the low byte
    stx reg_base+1,y        // Store the high byte
    jmp next
}

//----------------------------------------------------------------------------
// Push: 2 A
// Push <A> onto the stack
//----------------------------------------------------------------------------

op_push: {
    jsr fetch_value         // Fetch A
    ldy stack_ptr
    sta stack,y             // Store the low byte
    iny
    txa
    sta stack,y             // Store the high byte
    iny
    sty stack_ptr           // Update the stack pointer
    jmp next
}

//----------------------------------------------------------------------------
// Pop: 3 A
// Remove the top element from the stack and write it into <A>
// Empty stack = error
//----------------------------------------------------------------------------

op_pop: {
    jsr fetch_reg           // Fetch A
    tax
    ldy stack_ptr
    dey
    lda stack,y             // Load the high byte from the stack
    sta reg_base+1,x        // Store it in the destination register
    dey
    lda stack,y             // Load the low byte from the stack
    sta reg_base,x          // Store it in the destination register
    sty stack_ptr           // Update the stack pointer
    jmp next
}

//----------------------------------------------------------------------------
// Eq: 4 A B C
// Set <A> to 1 if <B> is equal to <C>; set it to 0 otherwise
//----------------------------------------------------------------------------

op_eq: {
    jsr fetch_reg           // Fetch A
    sta A
    jsr fetch_value         // Fetch B
    sta B
    stx B+1
    jsr fetch_value         // Fetch C
    ldy A
    cmp B                   // Compare the low byte
    bne ret0                // If not equal, return 0
    cpx B+1                 // Compare the high byte
    bne ret0                // If not equal, return 0
ret1:
    lda #$01                // Return 1
    sta reg_base,y
    lda #$00
    sta reg_base+1,y
    jmp next
ret0:
    lda #$00                // Return 0
    sta reg_base,y
    sta reg_base+1,y
    jmp next
}

//----------------------------------------------------------------------------
// Gt: 5 A B C
// Set <A> to 1 if <B> is greater than <C>; set it to 0 otherwise
//----------------------------------------------------------------------------

op_gt: {
    jsr fetch_reg           // Fetch A
    sta A
    jsr fetch_value         // Fetch B
    sta B
    stx B+1
    jsr fetch_value         // Fetch C 
    ldy A
    cpx B+1                 // Compare the high byte
    beq !+                  // C == B -> compare the low byte
    bcc ret1                // C < B  -> return 1 
    jmp ret0                // C > B  -> so return 0.
!:  cmp B                   // Compare the low byte
    beq ret0                // C == B -> return 0
    bcc ret1                // C < B  -> return 1
ret0:                       // C > B  -> fall through, return 0
    lda #$00              
    sta reg_base,y
    sta reg_base+1,y
    jmp next
ret1:
    lda #$01
    sta reg_base,y
    lda #$00
    sta reg_base+1,y
    jmp next
}

//----------------------------------------------------------------------------
// Jmp: 6 A
// Jump to <A>
//----------------------------------------------------------------------------

op_jmp:
    jsr fetch_value         // Fetch A
    sta reg_ip              // Store it in the instruction pointer
    stx reg_ip+1
    jmp next

//----------------------------------------------------------------------------
// Jt: 7 A B
// If <A> is nonzero, jump to <B>
//----------------------------------------------------------------------------

op_jt: {
    jsr fetch_value         // Fetch A
    cpx #$00
    bne !+                  // If the high byte is non-zero, jump
    cmp #$00
    bne !+                  // If the low byte is non-zero, jump

    jsr fetch_value         // Fetch B and discard it
    jmp next

!:  jsr fetch_value         // Fetch B
    sta reg_ip              // Store it in the instruction pointer
    stx reg_ip+1
    jmp next
}
  
//----------------------------------------------------------------------------
// Jf: 8 A B
// If <A> is zero, jump to <B>
//----------------------------------------------------------------------------

op_jf: {
    jsr fetch_value         // Fetch A
    cpx #$00
    bne !+                  // If the high byte is non-zero, don't jump
    cmp #$00
    bne !+                  // If the low byte is non-zero, don't jump

    jsr fetch_value         // Fetch B
    sta reg_ip              // Store it in the instruction pointer
    stx reg_ip+1
    jmp next

!:  jsr fetch_value         // Fetch B and discard it
    jmp next
}
  
//----------------------------------------------------------------------------
// Add: 9 A B C
// Assign into <A> the sum of <B> and <C> (modulo 32768)
//----------------------------------------------------------------------------

op_add: {
    jsr fetch_reg           // Fetch A
    sta A
    jsr fetch_value         // Fetch B
    sta B
    stx B+1
    jsr fetch_value         // Fetch C
    ldy A
    clc                     // Clear carry
    adc B                   // Add the low byte
    sta reg_base,y          // Store the low byte
    txa
    adc B+1                 // Add the high byte with carry
    and #$7f                // Clear the high bit (for mod 32768)
    sta reg_base+1,y        // Store the high byte
    jmp next
}

//----------------------------------------------------------------------------
// Mult: 10 A B C
// Store into <A> the product of <B> and <C> (modulo 32768)
// Temporary 32 bit product is stored in T0-T3
//
// Adapted from:
// https://codebase64.org/doku.php?id=base:16bit_multiplication_32-bit_product
//----------------------------------------------------------------------------

op_mult: {
    jsr fetch_reg           // Fetch A
    sta A
    jsr fetch_value         // Fetch B
    sta B
    stx B+1
    jsr fetch_value         // Fetch C
    sta C
    stx C+1
    lda #$00                // Clear high 16 bits of product
    sta T2
    sta T3
    ldx	#$10		        // Count down from 16
shift_r:
    lsr B+1                 // Divide multiplier by 2
    ror B
    bcc rotate_r
    lda T2                  // Get upper half of product and add C
    clc
    adc C
    sta T2
    lda T3
    adc C+1
rotate_r:
    ror
    sta T3
    ror T2
    ror T1
    ror T0
    dex
    bne shift_r
    ldy A                   // Get the register memory offset
    lda T0                  // Store the low byte in the destination register
    sta reg_base,y
    lda T1
    and #$7f                // Clear the high bit (for mod 32768)
    sta reg_base+1,y        // And store the high byte
    jmp next
}

//----------------------------------------------------------------------------
// Mod: 11 A B C
// Store into <A> the remainder of <B> divided by <C>
//
// Adapted from:
// https://codebase64.org/doku.php?id=base:16bit_division_16-bit_result
//----------------------------------------------------------------------------

op_mod: {
    jsr fetch_reg           // Fetch A
    pha                     // Save it on the stack
    jsr fetch_value         // Fetch B (dividend)
    sta B
    stx B+1
    jsr fetch_value         // Fetch C (divisor)
    sta C
    stx C+1
    lda #0	                // Preset remainder to 0
	sta A
	sta A+1
	ldx #16	                // Repeat for each bit
div_loop:   
    asl B                   // Dividend lb & hb*2, msb -> Carry
	rol B+1	
	rol A	                // Remainder lb & hb * 2 + msb from carry
	rol A+1
	lda A
	sec
	sbc C	                // Subtract divisor to see if it fits in
	tay	                    // lb result -> Y, for we may need it later
	lda A+1
	sbc C+1
	bcc skip                // If carry=0 then divisor didn't fit in yet
	sta A+1	                // Else save substraction result as new remainder
	sty A	
skip:        
	dex
	bne div_loop	
    pla
    tay
    lda A
    sta reg_base,y          // Store the remainder low byte
    lda A+1
    sta reg_base+1,y        // Store the remainder high byte
	jmp next
}

//----------------------------------------------------------------------------
// And: 12 A B C
// Stores into <A> the bitwise and of <B> and <C>
//----------------------------------------------------------------------------

op_and: {
    jsr fetch_reg           // Fetch A
    sta A
    jsr fetch_value         // Fetch B
    sta B
    stx B+1
    jsr fetch_value         // Fetch C
    ldy A
    and B                   // And the low byte
    sta reg_base,y          // Store it
    txa
    and B+1                 // And the high byte
    sta reg_base+1,y        // Store it
    jmp next
}

//----------------------------------------------------------------------------
// Or: 13 A B C
// Stores into <A> the bitwise or of <B> and <C>
//----------------------------------------------------------------------------


op_or: {
    jsr fetch_reg           // Fetch A
    sta A
    jsr fetch_value         // Fetch B
    sta B
    stx B+1
    jsr fetch_value         // Fetch C
    ldy A
    ora B                   // Or the low byte
    sta reg_base,y          // Store it
    txa
    ora B+1                 // Or the high byte
    sta reg_base+1,y        // Store it
    jmp next
}

//----------------------------------------------------------------------------
// Not: 14 A B
// Stores 15-bit bitwise inverse of <B> in <A>
//----------------------------------------------------------------------------

op_not: {
    jsr fetch_reg        
    sta A
    jsr fetch_value         // Fetch B
    ldy A
    eor #$ff                // Invert the low byte
    sta reg_base,y
    txa
    eor #$7f                // Invert the top 7 bits
    sta reg_base+1,y        // Store it
    jmp next
}

//----------------------------------------------------------------------------
// Rmem: 15 A B
// Read memory at address <B> and write it to <A>
//----------------------------------------------------------------------------

op_rmem: {
    jsr fetch_reg           // Fetch A
    sta A
    jsr fetch_value         // Fetch B
    asl                     // Double the low byte to get the physical address
    sta B                   // Physical address (low byte) is now in B
    txa                     // Get the high byte of the logical address
    rol                     // Double it, with carry from the low byte
    jsr map_page            // Map logical page to physical page
    sta B+1                 // Physical address (high byte) is now in B+1
    ldx A
    ldy #$00
    lda (B),y               // Load the low byte
    sta reg_base,x          // Store it in the destination register
    iny
    lda (B),y               // Load the high byte
    and #$7f                // Clear the high bit 
    sta reg_base+1,x        // Store it in the destination register
    jmp next
}

//----------------------------------------------------------------------------
// Wmem: 16 A B
// Write the value from <B> into memory at address <A>
//----------------------------------------------------------------------------

op_wmem: {
    jsr fetch_value         // Fetch A
    asl                     // Double the low byte to get the physical address
    sta A                   // Physical address (low byte) is now in A
    txa                     // Get the high byte of the logical address
    rol                     // Double it, with carry from the low byte
    jsr map_page            // Map logical page to physical page
    sta A+1                 // Physical address (high byte) is now in A+1
    jsr fetch_value         // Fetch B
    ldy #$00
    sta (A),y               // Store the low byte
    iny
    txa
    sta (A), y              // Store the high byte
    ldx A+1                 // Get the physical page index
    lda #ps_modified        // Set the page state to modified
    sta page_state_map,x
    jmp next
}

//----------------------------------------------------------------------------
// Call: 17 A
// Write the address of the next instruction to the stack and jump to <A>
//----------------------------------------------------------------------------

op_call: {
    jsr fetch_value         // Fetch A
    pha                     // Save the low byte
    ldy stack_ptr                
    lda reg_ip              // Push low byte of return address
    sta stack,y
    iny
    lda reg_ip+1            // Push high byte of return address
    sta stack,y
    iny
    sty stack_ptr           // Save the new stack pointer
    pla                     // Restore the low byte of the call address
    sta reg_ip              // Set the new instruction pointer
    stx reg_ip+1
    jmp next
}

//----------------------------------------------------------------------------
// Ret: 18
// Remove the top element from the stack and jump to it; empty stack = halt
//----------------------------------------------------------------------------

op_ret: {
   ldy stack_ptr
   cpy #$00
   beq *                    // If the stack is empty, halt
   dey
   lda stack,y              // Pop the high byte of the return address
   sta reg_ip+1
   dey
   lda stack,y              // Pop the low byte of the return address
   sta reg_ip
   sty stack_ptr            // Save the stack pointer
   jmp next
}

//----------------------------------------------------------------------------
// Out: 19 a
// Write the character represented by ascii code <A> to the terminal
//----------------------------------------------------------------------------

op_out: {
    jsr fetch_value         // Fetch the operand 
    jsr print_asc           // Print it
    jmp next                // Done
}

//----------------------------------------------------------------------------
// In: 20 A
// Read a character from the terminal and write its ascii code to <A> 
// It can be assumed that once input starts, it will continue until a newline
// is encountered; this means that you can safely read whole lines from the 
// keyboard instead of having to figure out how to read individual characters
//----------------------------------------------------------------------------

op_in: {
    jsr fetch_reg           // Fetch the destination register
    sta A
    lda line_len            // Do we have an existing line?
    bne !+                  // If so, skip the call to readline

    lda #'>'                // Print a prompt
    jsr chrout
    jsr readline            // Read a line into line_buf/line_len
    ldy #$00                // Set our read position to zero       
    sty line_pos

!:  ldy line_pos            // Read the next character
    lda line_buf,y 
    ldx A                   // Write it to the destination register
    sta reg_base,x
    lda #$00                // Write the high byte (always zero)
    sta reg_base+1,x
    iny                     // Increment the read position
    sty line_pos
    cpy line_len            // Have we reached the end of the buffer yet?
    bne !+

    ldy #$00                // If so, clear the line length and position
    sty line_len
    sty line_pos
!:  jmp next
}

//----------------------------------------------------------------------------
// Noop: 21
// No operation
//----------------------------------------------------------------------------

.label op_nop = next


