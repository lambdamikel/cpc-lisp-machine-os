;; CPC Lisp -- calling the firmware's maths package (library part 1:
;; lib/float.asm includes this).
;;
;; The maths jumpblock is &BD3D on a 464 and &BD61 on a 664/6128, with the
;; routines lib/float.asm uses at the same offsets in both (the 464's REAL
;; SUBTRACTION and the 6128's RND are where they differ): fmcall adds the
;; difference.

;; fmcall: the byte after the call = a maths routine's offset in the 464's
;; jumpblock; A, BC, DE, HL go in. fp_callix: IX = its 464 address.
fmcall:
    ld (V_FMA),a
    pop ix
    ld a,(ix+0)
    inc ix
    push ix
    add a,M_MOVE and #FF
    ld ixl,a
    ld ixh,M_MOVE >> 8
    jr fm_go
fp_callix:
    ld (V_FMA),a
fm_go:
    ld a,(FIRM_464_PROBE)
    cp #EF
    jr z,.go
    ld a,ixl
    add a,#24
    ld ixl,a
.go:
    ld a,(V_FMA)
    jp (ix)
