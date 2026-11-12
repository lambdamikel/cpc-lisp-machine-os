;; CPC Lisp -- characters drawn straight into screen memory: the 512K CPC's
;; copy of mach/cpc/fr.asm's renderer, in the resident part (resident.asm),
;; which calls it with the screen's RAM at &C000. Keep the two in step.
;;
;; The firmware's TXT WR CHAR manages about five characters a frame, and a
;; full-screen editor that redraws a line per key, or the screen per scroll,
;; is unusable at that speed. This draws a character in a tenth of the time:
;; its glyph from a copy of the font (taken with TXT GET MATRIX, so SYMBOL
;; redefinitions count), coloured with the text pen and paper as SCR INK
;; ENCODE gives them, written at the address the screen base and hardware
;; scroll offset (SCR GET LOCATION) put it -- in modes 0, 1 and 2.
;;
;; Inverse (pen and paper swapped) is the same byte xor (pen xor paper).
;; NEVER read the screen back from here: code in an upper ROM reads the ROM
;; at &C000-&FFFF, not the screen RAM under it. Writes do go to the screen.
;; So a cursor is the character drawn again in inverse, not a cell xored.
;;
;; Screen layout: character row r, column c starts at offset
;; off + 80 r + c * width (wrapping at &800), its eight pixel lines &800
;; apart; width is 4, 2 or 1 bytes in mode 0, 1, 2.


VID_VARS  equ LIBSCR+224        ; the renderer's variables start here
FR_MODE   equ LIBSCR+224        ; screen mode
FR_CW     equ LIBSCR+225        ; bytes a character row is wide: 4, 2, 1
VID_PAPER  equ LIBSCR+226        ; paper, encoded
FR_X      equ LIBSCR+227        ; pen xor paper, encoded
FR_BASE   equ LIBSCR+228        ; the screen's base, high byte
FR_OFF    equ LIBSCR+229        ; the hardware scroll offset (2)
FR_FONT   equ LIBSCR+231        ; the font copy, characters 32-127 (2)
FR_P      equ LIBSCR+233        ; paper for this character: VID_PAPER, or xor FR_X
VID_COLS   equ LIBSCR+234        ; columns on the screen: 20, 40, 80
VID_FONTSIZE equ 96*8
VID_ROWS   equ 25                ; rows on the screen

;; VID_INIT: DE = VID_FONTSIZE bytes for the font. Reads the mode, the inks
;; and where the screen is.
VID_INIT:
    ld (FR_FONT),de
    call SCR_GET_MODE
    and 3
    cp 3
    jr nz,.m
    ld a,1
.m:
    ld (FR_MODE),a
    ld bc,#0414                 ; mode 0: 4 bytes, 20 columns
    or a
    jr z,.cw
    ld bc,#0228
    dec a
    jr z,.cw
    ld bc,#0150
.cw:
    ld a,b
    ld (FR_CW),a
    ld a,c
    ld (VID_COLS),a
    call TXT_GET_PAPER
    call SCR_INK_ENCODE
    ld (VID_PAPER),a
    ld c,a
    push bc
    call TXT_GET_PEN
    call SCR_INK_ENCODE
    pop bc
    xor c
    ld (FR_X),a
    call SCR_GET_LOCATION       ; A = base, HL = offset
    ld (FR_BASE),a
    ld (FR_OFF),hl
    call KL_L_ROM_ENABLE        ; the font is in the lower ROM
    push af
    ld de,(FR_FONT)
    ld a,32
.f:
    push af
    push de
    call TXT_GET_MATRIX         ; HL = its eight bytes
    pop de
    ld bc,8
    ldir
    pop af
    inc a
    cp 128
    jr nz,.f
    pop af
    jp KL_ROM_RESTORE

;; fr_cell: B = column, C = row (from 0) -> HL = the address of the cell's
;; first byte on its top pixel line. BC, DE kept.
fr_cell:
    push de
    push bc
    ld l,c
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl                   ; 16 r
    ld d,h
    ld e,l
    add hl,hl
    add hl,hl
    add hl,de                   ; 80 r
    ld e,b
    ld d,0
    ld a,(FR_CW)
.sh:
    rra
    jr c,.shd
    sla e
    rl d
    jr .sh
.shd:
    add hl,de
    ld de,(FR_OFF)
    add hl,de
    ld a,h
    and 7
    ld h,a
    ld a,(FR_BASE)
    add a,h
    ld h,a
    pop bc
    pop de
    ret

;; fr_next: HL to the next byte along the pixel line, wrapping at &800
fr_next:
    inc l
    ret nz
    inc h
    ld a,h
    and 7
    ret nz
    ld a,h
    sub 8
    ld h,a
    ret

;; VID_CHAR: A = a character, B = column, C = row. Inverse if FR_P says so.
;; BC kept.
VID_CHAR:
    push bc
    sub 32
    jr c,.blank
    cp 96
    jr c,.glyph
.blank:
    xor a
.glyph:
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,(FR_FONT)
    add hl,de
    ex de,hl                    ; DE = the glyph
    call fr_cell                ; HL = the cell
    ld b,8
    ld a,(FR_MODE)              ; modes 1 and 2, when the cell does not
    or a                        ; straddle the screen's 2 KB wrap: fast
    jr z,.line
    ld a,(FR_X)
    ld ixh,a
    ld a,(FR_P)
    ld ixl,a
    ld a,(FR_MODE)
    dec a
    jr nz,.fast2
    ld a,l
    inc a
    jr nz,.fast1
    ld a,h
    and 7
    cp 7
    jr z,.line                  ; &7FF: the second byte wraps
.fast1:
    ld a,(de)                   ; the left four pixels
    and #F0
    ld c,a
    rrca
    rrca
    rrca
    rrca
    or c
    and ixh
    xor ixl
    ld (hl),a
    inc hl
    ld a,(de)                   ; the right four
    inc de
    and #0F
    ld c,a
    rlca
    rlca
    rlca
    rlca
    or c
    and ixh
    xor ixl
    ld (hl),a
    dec hl
    ld a,h
    add a,8
    ld h,a
    djnz .fast1
    pop bc
    ret
.fast2:
    ld a,(de)
    inc de
    and ixh
    xor ixl
    ld (hl),a
    ld a,h
    add a,8
    ld h,a
    djnz .fast2
    pop bc
    ret
.line:
    push hl
    ld a,(de)
    inc de
    ld c,a                      ; this pixel line of the glyph
    ld a,(FR_MODE)
    dec a
    jr z,.m1
    jp p,.m2
    ld a,4                      ; mode 0: two pixels a byte, left &AA, right &55
.m0:
    push af
    xor a
    rl c
    jr nc,.m0a
    or #AA
.m0a:
    rl c
    jr nc,.m0b
    or #55
.m0b:
    push bc
    call .put
    pop bc
    call fr_next
    pop af
    dec a
    jr nz,.m0
    jr .nl
.m1:                            ; mode 1: four pixels a byte, a nibble times &11
    push bc
    ld a,c
    and #F0
    ld c,a
    rrca
    rrca
    rrca
    rrca
    or c
    call .put
    call fr_next
    pop bc
    ld a,c
    and #0F
    ld c,a
    rlca
    rlca
    rlca
    rlca
    or c
    call .put
    jr .nl
.m2:                            ; mode 2: the glyph line is the mask
    ld a,c
    call .put
.nl:
    pop hl
    ld a,h                      ; the next pixel line, &800 on
    add a,8
    ld h,a
    djnz .line
    pop bc
    ret
;; A = a mask: pen where set, paper where not
.put:
    ld c,a
    ld a,(FR_X)
    and c
    ld c,a
    ld a,(FR_P)
    xor c
    ld (hl),a
    ret

;; VID_NORMAL, VID_INVERSE: what VID_CHAR draws in
VID_NORMAL:
    ld a,(VID_PAPER)
    ld (FR_P),a
    ret
VID_INVERSE:
    ld a,(VID_PAPER)
    ld hl,FR_X
    xor (hl)
    ld (FR_P),a
    ret
