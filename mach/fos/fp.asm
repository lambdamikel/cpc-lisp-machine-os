;; CPC Lisp on FutureOS itself -- calling the lower ROM's maths package
;; (library part 1: lib/float.asm includes this).
;;
;; There is no firmware jumpblock: LISP.64K builds one of its own, FM_JB
;; (jumps.asm), "jp address" for each maths routine in the 464's order,
;; from the lower ROM's table -- the one the firmware copies to &BD3D on a
;; 464, &BD61 on a 664/6128, where the routines lib/float.asm uses are in
;; the same order. RS_FM (resident.asm) calls one with the lower ROM in, the
;; interrupts off, and the maths' own RAM swapped in for FutureOS's.

;; fmcall: the byte after the call = a maths routine's offset in the 464's
;; jumpblock (FM); A, BC, DE, HL go in. fp_callix: IX = its M_ name.
fmcall:
    ld (V_FMA),a
    pop ix
    ld a,(ix+0)
    inc ix
    push ix
    jr fm_go
fp_callix:
    ld (V_FMA),a
    ld a,ixl
    sub M_MOVE and #FF
fm_go:
    add a,FM_JB and #FF
    ld ixl,a
    ld ixh,FM_JB >> 8
    ld a,(V_FMA)
    jp RS_FM
    assert (FM_JB and #FF) + 48*3 <= #100
