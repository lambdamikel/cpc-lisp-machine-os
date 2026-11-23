;; CPC Lisp -- floats on the PCW, in machine page B (pageb.asm includes
;; this). The PCW has no ROM: everything here is our own.
;;
;; A real is the CPC's: five bytes, four of mantissa, least significant
;; first, the top bit of the last the sign, then the exponent (0 is zero,
;; &80 is 0.5's). + - * / are fparith.asm's (the Spectrum's), rounded to
;; the nearest as the CPC's firmware does it; comparing, the signs and the
;; conversions to and from whole numbers are the Spectrum's too (fpzx.asm,
;; whence this comes, by the TRS-80's). The functions are built on them: a
;; reduction to a small range, then a series (tools/pcw/mkfpconst.py's
;; coefficients, in fpconst.inc) -- some nine digits, the CPC's to the last
;; but one or so. Whatever would overflow (dividing by zero, e to a large
;; power, the logarithm of 0) is answered with no carry, as the CPC's
;; firmware answers it.

fp_t:       defs 5,0            ; a real to work on
fp_a:       defs 5,0            ;   and another
fp_b:       defs 5,0            ;   and another
f_n:        db 0                ; a whole power's magnitude
fp_m:       defs 4,0            ; a whole part's magnitude, four bytes
fp_rnd:     db 0                ; the first bit below it,
fp_stk:     db 0                ;   and whether any other below was set
f_cnt:      db 0
f_sign:     db 0
f_cs:       db 0
f_xp:       dw 0
f_yp:       dw 0
fp_pi:      db #A2,#DA,#0F,#49,#82
fp_one:     db 0,0,0,0,#81
fp_half:    db 0,0,0,0,#80
fp_ten:     db 0,0,0,#20,#84
fp_e9:      db #00,#CA,#9A,#3B  ; 10^9, a whole number

;; f_exp: HL = a real -> A = its exponent. All else kept.
f_exp:
    push hl
    inc hl
    inc hl
    inc hl
    inc hl
    ld a,(hl)
    pop hl
    ret
;; f_neg: HL = a real -> NZ if it is below zero. All but AF kept.
f_neg:
    call f_exp
    or a
    ret z
    push hl
    inc hl
    inc hl
    inc hl
    bit 7,(hl)
    pop hl
    ret
;; f_no: no carry: it cannot be done
f_no:
    or a
    ret

;; f_zero: the real at HL is 0. HL kept, carry.
f_zero:
    push hl
    xor a
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    pop hl
    scf
    ret

;; f_top: the end of making a real. A = the top byte with its leading 1,
;; C = the sign (bit 7), E = the exponent, HL at the top byte's place, the
;; real's start pushed -> HL = the start, carry
f_top:
    and #7F
    or c
    ld (hl),a
    inc hl
    ld (hl),e
    pop hl
    scf
    ret

;; ---------------------------------------------------------------------------
;; THE ROUTINES

;; FP_MOVE: (HL) = (DE). BC, DE, HL kept (the callers count on it).
b_fp_move:
    push bc
    push de
    push hl
    ex de,hl
    ld bc,5
    ldir
    pop hl
    pop de
    pop bc
    scf
    ret

;; FP_PI: (HL) = pi
b_fp_pi:
    ld de,fp_pi
    jr b_fp_move

;; FP_ANGLE: A = 0, radians -- the only kind here
b_fp_angle:
    scf
    ret

;; FP_NEG: (HL) = -(HL)
b_fp_neg:
    call f_exp
    or a
    scf
    ret z
    push hl
    inc hl
    inc hl
    inc hl
    ld a,(hl)
    xor #80
    ld (hl),a
    pop hl
    scf
    ret

;; FP_SGN: (HL) -> A = 1, 0, &FF; Z if it is zero, carry if below
b_fp_sgn:
    call f_exp
    or a
    ret z
    call f_neg
    ld a,1
    jr nz,.n
    or a
    ret
.n:
    ld a,#FF
    or a
    scf
    ret

;; f_sg3: HL = a real -> B = 1, 0 or -1 as it is above, at, below zero
f_sg3:
    ld b,0
    call f_exp
    or a
    ret z
    inc b
    call f_neg
    ret z
    ld b,-1
    ret

;; FP_CMP: A = 1, 0, &FF as (HL) is above, equal to, below (DE). BC, DE,
;; HL kept.
b_fp_cmp:
    push bc
    call .cmp
    pop bc
    ret
.cmp:
    push hl
    call f_sg3
    ld c,b
    ex de,hl
    call f_sg3
    ex de,hl
    ld a,c
    sub b
    jr z,.same
    ld a,c                      ; the signs differ: they say it
    cp b
    ld a,1
    jp p,.r
    ld a,#FF
    jr .r
.same:
    ld a,c
    or a
    jr z,.r                     ; both zero
    ld (f_cs),a
    push de
    push hl
    ld bc,4
    add hl,bc
    ex de,hl
    add hl,bc
    ex de,hl                    ; HL, DE at the exponents
    ld a,(de)
    ld b,a
    ld a,(hl)
    cp b
    jr nz,.mag
    dec hl
    dec de
    ld a,(de)
    and #7F
    ld b,a
    ld a,(hl)
    and #7F
    cp b
    jr nz,.mag
    ld c,3
.lo:
    dec hl
    dec de
    ld a,(de)
    ld b,a
    ld a,(hl)
    cp b
    jr nz,.mag
    dec c
    jr nz,.lo
    pop hl
    pop de
    xor a
    jr .r
.mag:                           ; carry: |HL| < |DE|
    pop hl
    pop de
    ld a,1
    jr nc,.big
    ld a,#FF
.big:
    ld b,a
    ld a,(f_cs)
    or a
    ld a,b
    jp p,.r
    neg
.r:
    pop hl
    ret

;; FP_INT2R: HL = a magnitude, A bit 7 its sign -> the real at (DE),
;; HL = its place
b_fp_int2r:
    and #80
    ld c,a
    ex de,hl                    ; HL = the place, DE = the magnitude
    ld a,d
    or e
    jp z,f_zero
    push hl
    ld b,#90                    ; as if 0.1... * 2^16
.n:
    bit 7,d
    jr nz,.done
    ex de,hl
    add hl,hl
    ex de,hl
    dec b
    jr .n
.done:
    xor a
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),e
    inc hl
    ld a,d
    ld e,b
    jp f_top

;; FP_BIN2R: four bytes at HL, a magnitude, A bit 7 its sign -> a real
;; there
b_fp_bin2r:
    and #80
    ld (f_sign),a
    push hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    pop hl
    ld a,b
    or c
    or d
    or e
    jp z,f_zero
    ld a,#A0                    ; as if 0.1... * 2^32
.n:
    bit 7,b
    jr nz,.done
    sla e
    rl d
    rl c
    rl b
    dec a
    jr .n
.done:
    push hl
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld (hl),c
    inc hl
    ld e,a
    ld a,(f_sign)
    ld c,a
    ld a,b
    jp f_top

;; f_split: HL = a real -> fp_m = its whole part's magnitude (four bytes),
;; fp_rnd = the first bit below, fp_stk = whether any other below is set.
;; HL kept; no carry if the whole part needs more than four bytes.
f_split:
    push hl
    xor a
    ld (fp_rnd),a
    ld (fp_stk),a
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld c,(hl)
    inc hl
    ld a,(hl)
    or #80
    ld b,a                      ; BCDE: the mantissa, with its leading 1
    inc hl
    ld a,(hl)
    or a
    jr z,.zero
    sub #80                     ; how many bits are whole
    jr z,.half
    jr c,.small
    cp 33
    jr nc,.big
    neg
    add a,32                    ; how many are not
    jr z,.store
.sh:
    push af
    ld a,(fp_rnd)
    ld h,a
    ld a,(fp_stk)
    or h
    ld (fp_stk),a
    srl b
    rr c
    rr d
    rr e
    ld a,0
    rla
    ld (fp_rnd),a
    pop af
    dec a
    jr nz,.sh
    jr .store
.half:                          ; 0.5 to 1: the first bit below is set
    ld a,1
    ld (fp_rnd),a
    ld a,b
    and #7F
    or c
    or d
    or e
    jr z,.zero
.small:                         ; (or below 0.5: some bit below is set)
    ld a,1
    ld (fp_stk),a
.zero:
    ld bc,0
    ld d,b
    ld e,b
.store:
    ld (fp_m),de
    ld (fp_m+2),bc
    pop hl
    scf
    ret
.big:
    pop hl
    or a
    ret

;; f_mout: fp_m plus A (0 or 1) -> the four bytes at HL; B bit 7 = the sign
;; of the real that was there. HL kept, carry.
f_mout:
    push af
    call f_neg
    ld b,0
    jr z,.p
    ld b,#80
.p:
    pop af
    push bc
    push hl
    ld hl,(fp_m)
    ld de,(fp_m+2)
    ld c,a
    ld b,0
    add hl,bc
    jr nc,.n
    inc de
.n:
    ld b,h
    ld c,l
    pop hl
    ld (hl),c
    inc hl
    ld (hl),b
    inc hl
    ld (hl),e
    inc hl
    ld (hl),d
    dec hl
    dec hl
    dec hl
    pop bc
    scf
    ret

;; FP_FIX: (HL) -> four bytes there, the whole part truncated; B bit 7
;; the sign
b_fp_fix:
    call f_split
    ret nc
    xor a
    jr f_mout
;; FP_R2BIN: the same, rounded, a half away from zero
b_fp_r2bin:
    call f_split
    ret nc
    ld a,(fp_rnd)
    jr f_mout
;; FP_INT: the same, floored
b_fp_int:
    call f_split
    ret nc
    call f_neg
    ld a,0
    jr z,f_mout
    ld a,(fp_rnd)
    ld b,a
    ld a,(fp_stk)
    or b
    jr z,f_mout
    ld a,1
    jr f_mout

;; FP_R2INT: (HL) -> HL = its magnitude, rounded, S = its sign; carry if
;; that fits in 16 bits
b_fp_r2int:
    call f_neg
    push af
    call f_split
    jr nc,.no
    ld hl,(fp_m+2)
    ld a,h
    or l
    jr nz,.no
    ld hl,(fp_m)
    ld a,(fp_rnd)
    ld c,a
    ld b,0
    add hl,bc
    jr c,.no
    pop af
    ld a,0
    jr z,.p
    ld a,#80
.p:
    or a
    scf
    ret
.no:
    pop af
    or a
    ret

    include "fparith.asm"       ; + - * /, rounded

;; FP_EXP10: (HL) times 10 to the power A (from -128 to 127): times or
;; divided by 10^9 -- exact as a real -- as often as it takes, then by the
;; rest, 10^0-10^8, also exact: five roundings at most for any real's range
b_fp_exp10:
    ld (f_xp),hl
    ld c,0                      ; C: 1 to divide
    bit 7,a
    jr z,.p
    neg
    inc c
.p:
    ld b,a                      ; B = the power's magnitude
.l:
    ld a,b
    or a
    jr z,.ok
    ld hl,(f_xp)
    call f_exp
    or a
    jr z,.ok                    ; zero stays zero
    ld a,b
    cp 9
    jr c,.rest
    sub 9
    ld b,a
    push bc
    ld hl,fp_e9                 ; 10^9
    jr .by
.rest:
    ld e,b
    ld b,0                      ; (the last)
    push bc
    ld hl,fp_pw10               ; 10^b
    ld d,0
    add hl,de
    add hl,de
    add hl,de
    add hl,de
.by:
    ld de,fp_b
    push bc
    ld bc,4
    ldir
    pop bc
    ld hl,fp_b
    xor a
    call b_fp_bin2r             ; fp_b = that, a real
    pop bc
    push bc
    ld hl,(f_xp)
    ld de,fp_b
    bit 0,c
    jr nz,.div
    call b_fp_mul
    jr .next
.div:
    call b_fp_div
.next:
    pop bc
    jr nc,.no
    jr .l
.ok:
    ld hl,(f_xp)
    scf
    ret
.no:
    ld hl,(f_xp)
    bit 0,c
    jp nz,f_zero                ; (divided away: as good as 0)
    or a
    ret
fp_pw10:    dw 1,0, 10,0, 100,0, 1000,0, 10000,0, #86A0,1, #4240,#F
            dw #9680,#98, #E100,#5F5   ; 10^0-10^8, four bytes each

    include "fpfun.asm"         ; sqrt log exp sin cos tan atan

;; FP_POW: (HL) = (HL) to the power (DE): e^(y ln |x|), a negative x only
;; to a whole power
b_fp_pow:
    ld (f_xp),hl
    ld (f_yp),de
    ex de,hl
    call f_exp
    ex de,hl
    or a
    jr nz,.y
    ld de,fp_one                ; to the power 0: 1
    jp b_fp_move
.y:
    call f_exp
    or a
    jr nz,.x
    ex de,hl                    ; 0 to a power: 0, if it is above zero
    call f_neg
    ex de,hl
    jp nz,f_no
    scf
    ret
.x:
    ld hl,(f_yp)                ; a whole power up to 255: multiplied out
    call f_split
    jr nc,.real
    ld a,(fp_rnd)
    ld b,a
    ld a,(fp_stk)
    or b
    jr nz,.real
    ld hl,(fp_m+1)
    ld a,h
    or l
    jr nz,.real
    ld a,(fp_m)
    ld (f_n),a
    jp f_whole
.real:
    ld hl,(f_yp)                ; to the power 0.5: the root
    ld de,fp_half
    call b_fp_cmp
    or a
    ld hl,(f_xp)
    jp z,b_fp_sqr
    xor a
    ld (f_sign),a
    call f_neg
    jr z,.abs
    ld hl,(f_yp)                ; below zero: only a whole power,
    call f_split
    jp nc,f_no
    ld a,(fp_rnd)
    ld b,a
    ld a,(fp_stk)
    or b
    jp nz,f_no
    ld a,(fp_m)
    and 1
    jr z,.abs                   ;   and an odd one is below zero again
    ld a,#80
    ld (f_sign),a
.abs:
    ld hl,(f_xp)
    ld de,fp_t
    ld bc,5
    ldir
    ld hl,fp_t+3
    res 7,(hl)                  ; |x|
    ld hl,fp_t
    call b_fp_log               ; ln |x|
    jp nc,f_no
    ld hl,fp_t
    ld de,(f_yp)
    call b_fp_mul               ; times y
    jp nc,f_no
    ld hl,fp_t
    call b_fp_exp
    jp nc,f_no
    ld hl,(f_xp)
    ld de,fp_t
    call b_fp_move
    ld a,(f_sign)
    or a
    scf
    ret z
    jp b_fp_neg

;; f_whole: (f_xp) to the power (f_yp), whole, its magnitude in f_n:
;; squaring and multiplying, a negative power the reciprocal of that
f_whole:
    ld hl,fp_b
    ld de,(f_xp)
    call b_fp_move              ; b = x
    ld hl,fp_a
    ld de,fp_one
    call b_fp_move              ; r = 1
.l:
    ld a,(f_n)
    or a
    jr z,.done
    srl a
    ld (f_n),a
    jr nc,.sq
    ld hl,fp_a
    ld de,fp_b
    call b_fp_mul               ; r = r * b
    jp nc,f_no
.sq:
    ld a,(f_n)
    or a
    jr z,.done
    ld hl,fp_b
    ld de,fp_b
    call b_fp_mul               ; b = b * b
    jp nc,f_no
    jr .l
.done:
    ld hl,(f_yp)
    call f_neg
    jr z,.pos
    ld hl,fp_b
    ld de,fp_one
    call b_fp_move
    ld hl,fp_b
    ld de,fp_a
    call b_fp_div               ; 1 / r
    jp nc,f_no
    ld hl,fp_a
    ld de,fp_b
    call b_fp_move
.pos:
    ld hl,(f_xp)
    ld de,fp_a
    jp b_fp_move
