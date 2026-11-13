;; CPC Lisp -- the function editor's screen, on the Model 4 (lib/lib.asm
;; includes this): characters straight into the screen memory, 80 by 24 at
;; &F800 -- there in memory map 2 only, so each character is a moment of
;; map 2 with the interrupts off (part 0 runs at &8000, which map 2 leaves
;; in view). The editor's cursor, a character drawn "inverse", is the top
;; two rows of a character's graphics blocks, as on the Model I/III.

VID_VARS    equ LIBSCR+224      ; the renderer's variables start here
VID_PAPER   equ LIBSCR+226      ; the paper, as VID_FILLBOX takes it (unused)
FR_P        equ LIBSCR+233      ; 0 normal, 1 inverse
VID_COLS    equ LIBSCR+234      ; columns on the screen
VID_FONTSIZE equ 0              ; no font to copy
VID_ROWS    equ 24              ; rows on the screen

;; VID_INIT: DE = VID_FONTSIZE bytes (none). The screen's size noted.
VID_INIT:
    ld a,80
    ld (VID_COLS),a
    xor a
    ld (VID_PAPER),a
    ld (FR_P),a
    ret

;; VID_CHAR: A = a character, B = column, C = row (from 0): written into
;; the screen, or a block if VID_INVERSE said so. BC, DE, HL kept.
VID_CHAR:
    push de
    push hl
    ld d,a
    ld a,(FR_P)
    or a
    jr z,.put
    ld d,#8F                    ; inverse: the upper two thirds lit
.put:
    push de                     ; the character, in D
    ld l,c
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl                   ; 16 * row
    ld d,h
    ld e,l
    add hl,hl
    add hl,hl                   ; 64 * row
    add hl,de                   ; 80 * row
    ld e,b
    ld d,0
    add hl,de
    ld de,VRAM
    add hl,de
    pop de                      ; D = the character
    di
    ld a,(RS_P84)
    and #FF-OP_MAP
    or 2
    out (OPREG),a
    ld (hl),d
    ld a,(RS_P84)
    out (OPREG),a
    ei
    pop hl
    pop de
    ret

;; VID_NORMAL, VID_INVERSE: what VID_CHAR draws from now on
VID_NORMAL:
    xor a
    ld (FR_P),a
    ret
VID_INVERSE:
    ld a,1
    ld (FR_P),a
    ret
