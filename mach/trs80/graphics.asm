;; CPC Lisp -- FLOOD-FILL on the TRS-80, in library part 0 (the end of
;; lib/gfx.asm includes this); the machine page does the work (M_FILL).
;; SYMBOL is not here: the characters are the ROM's.

;; (flood-fill x y [pen]): the area around (x, y) that is the colour of
;; (x, y), to where the other starts, painted with pen (the graphics pen)
;; -- a paint bucket, in the screen's blocks.
;@ FLOOD-FILL 2 3 lf_flood_fill
lf_flood_fill:
    ld c,2
    call gx_ints                ; x y
    ld a,b
    ld c,3
    call gx_pen
    pop hl
    pop de
    push ix
    call M_FILL
    pop ix
    jp lnil
