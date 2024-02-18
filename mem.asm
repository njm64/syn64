//----------------------------------------------------------------------------
// The virtual machine can address 32K words of memory, where each word 
// is 16 bits. We break this up into 256 byte pages, so each page stores 128
// words. Pages are stored in raw disk sectors, from track 1 to track 17,
// and are mapped into RAM on demand (from $1000 - $C7FF)
//----------------------------------------------------------------------------

.label page_min = $10       // Minimum physical page ($1000)
.label page_max = $C7       // Maximum physical page ($C700)

//----------------------------------------------------------------------------
// Each physical page has a state, stored in page_state_map
//----------------------------------------------------------------------------

.label ps_free      = 0     // This physical page is unused
.label ps_mapped    = 1     // This physical page is mapped
.label ps_modified  = 2     // This physical page has been modified

//----------------------------------------------------------------------------
// Keep track of the index of the most recent physical page mapped
//----------------------------------------------------------------------------

.segment ZeroPage
page_index: .byte $00       // Index of the most recent physical page mapped

//----------------------------------------------------------------------------
// Mapping tables
//----------------------------------------------------------------------------

.segment HighData
.align $100
page_map: .fill $100, 0         // Map from logical page to physical page
page_reverse_map: .fill $100, 0 // Map from physical page to logical page
page_state_map: .fill $100, 0   // State of each physical page

.segment Default

//----------------------------------------------------------------------------
// Initialisation
//----------------------------------------------------------------------------

mem_init: {
    lda #$00                // Clear memory maps
    ldx #$00
!:  sta page_map,x
    sta page_state_map,x
    sta page_reverse_map,x
    inx
    bne !-

    // Initialise the most recently mapped page index to page_max, so
    // it will immediately wrap around to page_min for the next allocation.
    lda #page_max
    sta page_index
    rts
}

//----------------------------------------------------------------------------
// Read a page from disk
// Input:
//   A: High byte of the destination buffer (physical page number)
//   X: Page index to load (logical page number)
//----------------------------------------------------------------------------

read_page: {
    sta tmp                 // Save A, X, and Y
    tya
    pha
    txa                     // As a side effect of this, move X to A
    pha

    // Convert the logical page index (in A) to track/sector numbers,
    // and encode them as PETSCII as part of the cmd_name string.

    ldy #'0'                // Set track/sector high bytes to zero
    sty sector
    sty track
    ldy #$01                // Use Y for the track index
set_track:
    cmp #$15                // Is the sector less than 21?
    bcc set_sector          // If so, we're done with the track
    sbc #$15                // Subtract 21 from the sector
    cpy #$09                // Is the track 9?
    beq !+                  // If so increment the high byte of the track
    iny                     // Increment the low byte of the track
    jmp set_track
!:  inc track               // Increment the high byte of the track
    ldy #$00                // And set the low byte to '0'
    jmp set_track
set_sector:
    cmp #10                 // Is the sector less than 10?
    bcc set_sector_done     // It so we're done, and can set it.
    sbc #10
    inc sector
    jmp set_sector
set_sector_done:
    adc #'0'                // Store the low byte of the sector
    sta sector+1
    tya
    adc #'0'                // Store the low byte of the track
    sta track+1

    /*
    lda track
    jsr chrout
    lda track+1
    jsr chrout
    lda #' '
    jsr chrout
    lda sector
    jsr chrout
    lda sector+1
    jsr chrout
    lda #'\n'
    jsr chrout
    */

    lda #data_len
    ldx #<data_name
    ldy #>data_name
    jsr setnam
    lda #$02                // File number 2
    ldx $BA                 // Last used device number
    bne !+
    ldx #$08                // Default to device 8
!:  ldy #$02                // Secondary address 2
    jsr setlfs
    jsr open                // Open the data channel
    bcs error

    lda #cmd_len
    ldx #<cmd_name
    ldy #>cmd_name
    jsr setnam
    lda #$0F
    ldx $BA
    ldy #$0F
    jsr setlfs
    jsr open                // Open the command channel
    bcs error

    ldx #$02                // Switch to file number 2 (data channel)
    jsr chkin

    ldy tmp                 // Set the buffer pointer (high byte)
    sty T1
    ldy #$00                // Set the buffer pointer (low byte)
    sty T0
!:  jsr chrin               // Transfer 256 bytes of data
    sta (T0),y
    iny
    bne !-

    lda #$0F
    jsr close               // Close the command channel
    lda #$02
    jsr close               // Close the data channel
    jsr clrchn              // Restore keyboard/screen IO

    pla                     // Restore X, Y, A
    tax
    pla
    tay
    lda tmp
    rts

error:
    lda #$02
    sta $d020
    jmp error

.encoding "petscii_upper"
data_name: .text '#'
.label data_len = *-data_name

cmd_name: .text "U1 2 0 "
track:    .text "01 "
sector:   .text "00"
.label cmd_len=*-cmd_name

tmp: .byte $00
}

//----------------------------------------------------------------------------
// Find the next physical page to map. Physical pages are allocated in
// round robin order (excluding modified pages). This is simpler than 
// maintaining timestamps and evicting the LRU page, and is good enough for 
// our purposes. 
// Output:   Physical page number in A
// Modifies: Y
//----------------------------------------------------------------------------

find_physical_page: {
    inc page_index          // Increment the most recently used page index
    lda page_index
    cmp #page_max+1         // Is it still in range?
    bcc !+
    lda #page_min           // If not, set it back to the minimum page
    sta page_index
!:  tay
    lda page_state_map,y    // Is it modified?  
    cmp #ps_modified
    beq find_physical_page  // If so, try the next page
    tya                     // Return the page index
    rts
}

//----------------------------------------------------------------------------
// Map a physical page to a logical page
// Input:    Logical page number in A
// Output:   Physical page number in A  
// Modifies: X, Y 
//----------------------------------------------------------------------------

map_page: {
    tax                     // Logical page is now in X
    lda page_map,x          // Get the physical page
    beq !+                  // If it's zero, need to map it
    rts

!:  jsr find_physical_page  // Find a page to map it into
    sta page_map,x          // Update the logical to physical map
    tay                     // Physical page is now in Y
    lda page_state_map,y    // Is it already mapped?
    beq !+                  // If not, skip ahead

    lda page_reverse_map,y  // Otherwise, we need to clear the previous mapping
    tay                     // Old logical page is now in Y
    lda #$00
    sta page_map,y          // Clear the old logical mapping

!:  lda page_map,x          // Physical page index in A
    jsr read_page           // Read logical page X
    tay                     // Physical page index in Y
    txa                     // Logical page index in A
    sta page_reverse_map,y  // Set the new reverse mapping
    lda #ps_mapped          // Mark this physical page as mapped
    sta page_state_map,y
    tya                     // Return the physical page
    rts
}

