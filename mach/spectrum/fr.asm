;; CPC Lisp -- the function editor's screen, on the Spectrum (lib/lib.asm
;; includes this): each character through the jumpblock to machine page A
;; (M_VIDCHAR), which draws it in its six by eight pixels -- some 2000
;; characters a second, ten times the CPC firmware's. Inverse is the cell's
;; pixels inverted.

VID_VARS    equ LIBSCR+224      ; the renderer's variables start here
VID_PAPER   equ LIBSCR+226      ; the paper, as VID_FILLBOX takes it (unused)
FR_P        equ LIBSCR+233      ; 0 normal, 1 inverse
VID_COLS    equ LIBSCR+234      ; columns on the screen
VID_FONTSIZE equ 0              ; no font to copy
VID_ROWS    equ 24              ; rows on the screen

;; the function editor's status line, on the last row (lib/fed.asm)
VID_STATUS: db " EDIT or GRAPH: done    BREAK: cancel",0

;; VID_INIT: DE = VID_FONTSIZE bytes (none). The screen's size noted.
VID_INIT:
    ld a,40
    ld (VID_COLS),a
    xor a
    ld (VID_PAPER),a
    ld (FR_P),a
    ret

;; VID_CHAR: A = a character, B = column, C = row (from 0): drawn, inverse
;; if VID_INVERSE said so. BC, DE, HL kept.
VID_CHAR:
    push de
    ld e,a
    ld a,(FR_P)
    ld d,a
    ld a,e
    call M_VIDCHAR
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
