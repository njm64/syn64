//----------------------------------------------------------------------------
// Convert an ASCII character to PETSCII and print it
// Input:    ASCII character in A
// Modifies: A, Y
//----------------------------------------------------------------------------

print_asc: {
    and #$7f
    tay
    lda asc_map,y
    jmp chrout
asc_map:
    .encoding "petscii_mixed"
    .byte 0,0,0,0,0,0,0,0,0,0,13,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .text @" !'#$%&'()*+,-./0123456789:;<=>?"
    .text "@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_"
    .text "`abcdefghijklmnopqrstuvwxyz{|}~ "
}

//----------------------------------------------------------------------------
// Print a null terminated string
// Input:    Pointer to string in A/Y
// Modifies: A, Y
//----------------------------------------------------------------------------

print_sz: {
    sta T0
    sty T1
    ldy #$00
!:  lda (T0),y
    beq done
    jsr chrout
    iny
    bne !-
done:  
    rts
}

//----------------------------------------------------------------------------
// Print a byte as a 2 digit hex string
// Input:    Byte to print in A
// Modifies: A, X
//----------------------------------------------------------------------------

print_hex: {
    pha             // Save the value
    lsr             // Get the low nibble
    lsr            
    lsr            
    lsr            
    tax             // Print it
    lda hex,x
    jsr chrout
    pla             // Restore the original value
    and #$0f        // Get the high nibble
    tax
    lda hex,x       // Print it
    jsr chrout
    rts
hex: 
    .text "0123456789ABCDEF"
}

