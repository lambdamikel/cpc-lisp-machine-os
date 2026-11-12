;; CPC Lisp -- the function editor's screen, on the TRS-80 (lib/lib.asm
;; includes this): characters straight into the screen memory, 64 by 16 at
;; &3C00 -- which, unlike the CPC's, every page can always see. There is no
;; inverse video on a Model I: a character drawn "inverse", the editor's
;; cursor, is the Level II cursor, as the REPL's -- the bottom row of a
;; character's graphics blocks (a full block stood taller than the letters).

VID_VARS    equ LIBSCR+224      ; the renderer's variables start here
VID_PAPER   equ LIBSCR+226      ; the paper, as VID_FILLBOX takes it (unused)
FR_P        equ LIBSCR+233      ; 0 normal, 1 inverse
VID_COLS    equ LIBSCR+234      ; columns on the screen
VID_FONTSIZE equ 0              ; no font to copy
VID_ROWS    equ 16              ; rows on the screen

;; VID_INIT: DE = VID_FONTSIZE bytes (none). The screen's size noted.
VID_INIT:
    ld a,64
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
    ld d,#B0                    ; inverse: the Level II cursor
.put:
    ld l,c
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl                   ; 64 * row
    ld a,l
    add a,b
    ld l,a
    ld a,h
    add a,VRAM >> 8
    ld h,a
    ld (hl),d
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
