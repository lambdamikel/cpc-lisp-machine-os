;; CPC Lisp -- the function editor's renderer, seen from the library on the
;; 512K CPC: VID_INIT and VID_CHAR are in the resident part (frcode.asm,
;; resident.asm), which draws with the screen's RAM at &C000 -- where the
;; library's own code is, in its bank, while it runs.

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

VID_INIT  equ RS_VIDINIT        ; DE = VID_FONTSIZE bytes for the font
VID_CHAR  equ RS_VIDCHAR        ; A = a character, B = column, C = row

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
