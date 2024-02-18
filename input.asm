//----------------------------------------------------------------------------
// Line input
//----------------------------------------------------------------------------

.label line_max = 39        // 40 characters minus 1 for the prompt 

.segment ZeroPage
line_len: .byte $00         // Length of the current line  
line_pos: .byte $00         // Current read position

.segment HighData
line_buf: .fill line_max, 0 // Line buffer in high memory

.segment Default

//----------------------------------------------------------------------------
// Read a line of text
// Output:   Data in line_buf, length in line_len
// Modifies: A, Y
//----------------------------------------------------------------------------

readline: {
    ldy #$00                // Use Y for our offset into line_buf
    lda #$00                // Enable flashing cursor
    sta $CC
next:
    sty T0                  // Save the Y register
    jsr getin               // Try to get a character
    beq next                // If we didn't get one, try again.
    ldy T0                  // Restore Y
    cmp #$20                // If it's >= 20 and < 80, it's printable
    bcc chkdel
    cmp #$80
    bcs chkdel
    cpy #line_max-1         // Is there space in the buffer (-1 for the enter)
    beq next                // If not, ignore it
    jsr chrout              // Print it
    jsr toupper             // Convert to upper case
    sta line_buf,y          // Store it
    iny
    jmp next
chkdel:
    cmp #$14                // Is it a delete character?
    bne chkenter
    cpy #$00                // Make sure the buffer is not empty
    beq next
    dey
    jsr chrout
    jmp next
chkenter:
    cmp #$0d                // Is it an enter character?
    bne next                // If not, ignore it
    lda #$0a
    sta line_buf,y          // Store the enter character
    lda #$01                // Disable flashing cursor
    sta $CC
    lda #$20                // Write a space to hide any left over cursor
    jsr chrout
    lda #$0d                // Write the return
    jsr chrout
    iny                     // Add 1 for the enter character
    sty line_len
    rts
}

//----------------------------------------------------------------------------
// Convert a character to uppercase
// Input:  Mixed PETSCII character in A
// Output: Uppercase character in A
//----------------------------------------------------------------------------

toupper: {
    cmp #$41                // Is it < 'A'?
    bcc !+
    cmp #$5B                // Is it >= '[' (one after 'Z')?
    bcs !+
    ora #$20        
!:  rts
}

