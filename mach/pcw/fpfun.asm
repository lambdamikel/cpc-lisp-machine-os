;; CPC Lisp -- the PCW's maths functions, our own (fppcw.asm includes this):
;; FP_SQR, FP_LOG, FP_EXP, FP_SIN, FP_COS, FP_TAN, FP_ATN -- (HL) = f((HL)),
;; HL kept, carry if it went. Each is a reduction of its argument to a
;; small range, then a series by Horner's rule (f_poly) on fparith.asm's
;; rounded + - * / -- the coefficients and constants are
;; tools/pcw/mkfpconst.py's (fpconst.inc). Radians only (FP_ANGLE).
;;
;;   sqrt x  Newton's s = (s + x/s) / 2, six times, from x's mantissa with
;;           half its exponent (within a factor of 1.5: six are plenty)
;;   log x   x = m 2^k, m in [sqrt(1/2), sqrt 2): ln m = 2t P(t^2) with
;;           t = (m-1)/(m+1) -- |t| <= 0.172, P to t^12 -- then + k ln 2
;;   exp x   n = round(x / ln 2), r = x - n ln 2 (ln 2 in two parts: n
;;           times the first is exact), e^r by its series to r^11, times
;;           2^n (n added to the exponent)
;;   sin x   k = round(2x / pi), r = x - k pi/2 (pi/2 in two parts), then
;;   cos x   sin r = r S(r^2) or cos r = C(r^2) as k's quadrant says, the
;;           sign too; cos is sin a quadrant on
;;   tan x   sin x / cos x
;;   atan x  |x| > 1: pi/2 - atan(1/x); past tan(pi/12): pi/6 +
;;           atan((x sqrt 3 - 1)/(x + sqrt 3)); then z A(z^2), to z^17

fx_x:       defs 5,0            ; the argument, reduced
fx_s:       defs 5,0            ; a series' sum
fx_u:       defs 5,0            ; its variable
fx_v:       defs 5,0
fx_w:       defs 5,0
fx_t:       defs 5,0            ; tan's cosine
fx_pz:      dw 0                ; f_poly's: the variable,
fx_pc:      dw 0                ;   the next coefficient,
fx_pn:      db 0                ;   how many to go
fx_q:       db 0                ; log: k; sin, cos: the quadrant; atan: what
                                ;   was done (1 inverted, 2 moved by pi/6)
fx_sgn:     db 0
fx_n:       dw 0
fx_hl:      dw 0                ; the caller's real
fx_tn:      dw 0                ;   (tan's)

    include "fpconst.inc"

;; f_poly: HL = a table of B+1 reals, the highest power's first, DE = the
;; variable -> fx_s = the polynomial there; carry if it went
f_poly:
    ld (fx_pz),de
    ld (fx_pc),hl
    ld a,b
    ld (fx_pn),a
    ex de,hl
    ld hl,fx_s
    call b_fp_move
.l:
    ld a,(fx_pn)
    or a
    scf
    ret z
    dec a
    ld (fx_pn),a
    ld hl,fx_s
    ld de,(fx_pz)
    call b_fp_mul
    ret nc
    ld hl,(fx_pc)
    ld de,5
    add hl,de
    ld (fx_pc),hl
    ex de,hl
    ld hl,fx_s
    call b_fp_add
    ret nc
    jr .l

;; fx_out: fx_s -> the caller's real; HL = it, carry
fx_out:
    ld hl,(fx_hl)
    ld de,fx_s
    jp b_fp_move

;; fx_sq: HL = a real -> fx_u = its square. HL kept.
fx_sq:
    push hl
    ex de,hl
    ld hl,fx_u
    call b_fp_move
    call b_fp_mul
    pop hl
    ret

;; ---------------------------------------------------------------------------

;; FP_SQR
b_fp_sqr:
    call f_exp
    or a
    scf
    ret z                       ; the root of 0
    call f_neg
    jp nz,f_no
    ld (f_xp),hl
    ld de,fp_a
    ex de,hl
    call b_fp_move              ; fp_a = a
    ex de,hl
    push hl                     ; the start: a's mantissa, half its exponent
    inc hl
    inc hl
    inc hl
    inc hl
    ld a,(hl)
    sub #80
    inc a
    sra a
    add a,#80
    ld (hl),a
    pop hl
    ld a,6
.newton:
    ld (f_cnt),a
    ld hl,fp_t
    ld de,fp_a
    call b_fp_move              ; t = a
    ld de,(f_xp)
    call b_fp_div               ; t = a / s
    jp nc,f_no
    ld hl,(f_xp)
    ld de,fp_t
    call b_fp_add               ; s = s + a / s
    jp nc,f_no
    inc hl
    inc hl
    inc hl
    inc hl
    dec (hl)                    ; s = s / 2
    ld hl,(f_xp)
    ld a,(f_cnt)
    dec a
    jr nz,.newton
    scf
    ret

;; FP_LOG
b_fp_log:
    call f_exp
    or a
    jp z,f_no                   ; the logarithm of 0
    call f_neg
    jp nz,f_no                  ;   or of a negative number
    ld (fx_hl),hl
    sub #80
    ld (fx_q),a                 ; k
    ex de,hl
    ld hl,fx_x
    call b_fp_move
    ld a,#80
    ld (fx_x+4),a               ; m, in [0.5, 1)
    ld hl,fx_x
    ld de,fc_rt2h
    call b_fp_cmp
    inc a
    jr nz,.m                    ; (not below sqrt(1/2))
    ld a,#81
    ld (fx_x+4),a               ; below: doubled, k one less
    ld hl,fx_q
    dec (hl)
.m:
    ld hl,fx_v                  ; t = (m - 1) / (m + 1)
    ld de,fc_one
    call b_fp_move
    ld de,fx_x
    call b_fp_rsub
    ld hl,fx_w
    ld de,fx_x
    call b_fp_move
    ld de,fc_one
    call b_fp_add
    ld hl,fx_v
    ld de,fx_w
    call b_fp_div
    ld hl,fx_v
    call fx_sq                  ; u = t^2
    ld hl,fc_log
    ld de,fx_u
    ld b,6
    call f_poly
    ld hl,fx_s
    ld de,fx_v
    call b_fp_mul               ; t P(t^2)
    ld hl,fx_s+4
    ld a,(hl)
    or a
    jr z,.k
    inc (hl)                    ; doubled: ln m
.k:
    ld a,(fx_q)                 ; + k ln 2
    or a
    jp z,fx_out
    ld c,0
    bit 7,a
    jr z,.p
    neg
    ld c,#80
.p:
    ld l,a
    ld h,0
    ld a,c
    ld de,fx_w
    call b_fp_int2r
    ld hl,fx_w
    ld de,fc_ln2
    call b_fp_mul
    ld hl,fx_s
    ld de,fx_w
    call b_fp_add
    jp nc,f_no
    jp fx_out

;; FP_EXP
b_fp_exp:
    call f_exp                  ; 88 or more (exponent &87, top &30): out
    cp #87
    jr c,.ok
    jr nz,.out
    push hl
    inc hl
    inc hl
    inc hl
    ld a,(hl)
    pop hl
    and #7F
    cp #30
    jr c,.ok
.out:
    call f_neg
    jp nz,f_zero                ; e to a large negative power: 0
    jp f_no                     ; to a large positive one: too big
.ok:
    ld (fx_hl),hl
    or a
    jr nz,.nz
    ld de,fc_one                ; e^0
    jp b_fp_move
.nz:
    ex de,hl
    ld hl,fx_v
    call b_fp_move
    ld de,fc_iln2
    call b_fp_mul               ; x / ln 2
    ld hl,fx_v
    call b_fp_r2int             ; HL = n's magnitude, A = its sign
    jp nc,f_no
    ld (fx_n),hl
    ld (fx_sgn),a
    ld de,fx_w
    call b_fp_int2r             ; w = n
    ld hl,fx_x
    ld de,(fx_hl)
    call b_fp_move
    ld hl,fx_v
    ld de,fx_w
    call b_fp_move
    ld de,fc_ln2h
    call b_fp_mul               ; n ln2's first part (exact)
    ld hl,fx_v
    ld de,fx_x
    call b_fp_rsub              ; x - that
    ld hl,fx_x
    ld de,fx_v
    call b_fp_move
    ld hl,fx_v
    ld de,fx_w
    call b_fp_move
    ld de,fc_ln2l
    call b_fp_mul               ; n ln2's rest
    ld hl,fx_v
    ld de,fx_x
    call b_fp_rsub              ; r
    ld hl,fc_exp
    ld de,fx_v
    ld b,11
    call f_poly                 ; e^r
    jp nc,f_no
    ld a,(fx_s+4)               ; times 2^n
    ld l,a
    ld h,0
    ld de,(fx_n)
    ld a,(fx_sgn)
    or a
    jr nz,.neg
    add hl,de
    jr .chk
.neg:
    or a
    sbc hl,de
.chk:
    bit 7,h
    jr nz,.tiny
    ld a,h
    or a
    jp nz,f_no                  ; too big
    ld a,l
    or a
    jr z,.tiny
    ld (fx_s+4),a
    jp fx_out
.tiny:
    ld hl,(fx_hl)
    jp f_zero

;; FP_SIN, FP_COS
b_fp_cos:
    ld a,1
    jr fx_sc
b_fp_sin:
    xor a
fx_sc:
    ld (fx_q),a                 ; cos: sin a quadrant on
    ld (fx_hl),hl
    call f_exp
    or a
    jr nz,.nz
    ld a,(fx_q)
    or a
    scf
    ret z                       ; sin 0
    ld de,fc_one                ; cos 0
    jp b_fp_move
.nz:
    ex de,hl
    ld hl,fx_v
    call b_fp_move
    ld de,fc_2opi
    call b_fp_mul               ; 2x / pi
    jp nc,f_no
    ld hl,fx_v
    call b_fp_r2bin             ; k, rounded: four bytes, B bit 7 its sign
    jp nc,f_no                  ; (far too big to reduce)
    ld a,(fx_v)                 ; the quadrant: k mod 4, + fx_q
    and 3
    bit 7,b
    jr z,.qp
    neg
    and 3
.qp:
    ld hl,fx_q
    add a,(hl)
    and 3
    ld (hl),a
    ld a,b
    ld hl,fx_v
    call b_fp_bin2r             ; v = k, a real
    ld hl,fx_w
    ld de,fx_v
    call b_fp_move              ; w = k
    ld hl,fx_x
    ld de,(fx_hl)
    call b_fp_move              ; x
    ld hl,fx_v
    ld de,fc_pio2h
    call b_fp_mul               ; k pi/2's first part
    ld hl,fx_v
    ld de,fx_x
    call b_fp_rsub              ; x - that
    ld hl,fx_x
    ld de,fx_v
    call b_fp_move
    ld hl,fx_w
    ld de,fc_pio2l
    call b_fp_mul               ; k pi/2's rest
    ld hl,fx_w
    ld de,fx_x
    call b_fp_rsub              ; r
    ld hl,fx_w
    call fx_sq                  ; u = r^2
    ld a,(fx_q)
    rrca
    jr c,.cos
    ld hl,fc_sin                ; sin r = r S(r^2)
    ld de,fx_u
    ld b,6
    call f_poly
    ld hl,fx_s
    ld de,fx_w
    call b_fp_mul
    jr .sign
.cos:
    ld hl,fc_cos                ; cos r = C(r^2)
    ld de,fx_u
    ld b,7
    call f_poly
.sign:
    ld a,(fx_q)
    and 2
    jp z,fx_out
    ld hl,fx_s
    call b_fp_neg
    jp fx_out

;; FP_TAN: sin x / cos x (cos 0: no carry)
b_fp_tan:
    ld (fx_tn),hl
    ex de,hl
    ld hl,fx_t
    call b_fp_move
    call b_fp_cos               ; t = cos x
    jp nc,f_no
    ld hl,(fx_tn)
    call b_fp_sin               ; x = sin x
    jp nc,f_no
    ld hl,(fx_tn)
    ld de,fx_t
    jp b_fp_div

;; FP_ATN
b_fp_atn:
    call f_exp
    or a
    scf
    ret z                       ; atan 0
    ld (fx_hl),hl
    call f_neg
    ld a,0
    jr z,.p
    ld a,1
.p:
    ld (fx_sgn),a
    ex de,hl
    ld hl,fx_x
    call b_fp_move
    ld hl,fx_x+3
    res 7,(hl)                  ; |x|
    xor a
    ld (fx_q),a
    ld hl,fx_x
    ld de,fc_one
    call b_fp_cmp
    dec a
    jr nz,.le1                  ; not above 1
    ld hl,fx_v                  ; above: 1 / x
    ld de,fc_one
    call b_fp_move
    ld de,fx_x
    call b_fp_div
    ld hl,fx_x
    ld de,fx_v
    call b_fp_move
    ld a,1
    ld (fx_q),a
.le1:
    ld hl,fx_x
    ld de,fc_t12
    call b_fp_cmp
    dec a
    jr nz,.small                ; not above tan(pi/12)
    ld hl,fx_v                  ; (x sqrt 3 - 1) / (x + sqrt 3)
    ld de,fx_x
    call b_fp_move
    ld de,fc_rt3
    call b_fp_mul
    ld hl,fx_w
    ld de,fc_one
    call b_fp_move
    ld de,fx_v
    call b_fp_rsub              ; w = x sqrt 3 - 1
    ld hl,fx_v
    ld de,fx_x
    call b_fp_move
    ld de,fc_rt3
    call b_fp_add
    ld hl,fx_w
    ld de,fx_v
    call b_fp_div
    ld hl,fx_x
    ld de,fx_w
    call b_fp_move
    ld hl,fx_q
    set 1,(hl)
.small:
    ld hl,fx_x
    call fx_sq                  ; u = z^2
    ld hl,fc_atn
    ld de,fx_u
    ld b,8
    call f_poly
    ld hl,fx_s
    ld de,fx_x
    call b_fp_mul               ; z A(z^2)
    ld a,(fx_q)
    bit 1,a
    jr z,.n6
    ld hl,fx_s
    ld de,fc_pio6
    call b_fp_add               ; + pi/6
.n6:
    ld a,(fx_q)
    bit 0,a
    jr z,.ninv
    ld hl,fx_s
    ld de,fc_pio2
    call b_fp_rsub              ; pi/2 - that
.ninv:
    ld a,(fx_sgn)
    or a
    jp z,fx_out
    ld hl,fx_s
    call b_fp_neg
    jp fx_out
