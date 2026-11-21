;; CPC Lisp -- + - * / on the CPC's reals, rounded to the nearest, in
;; machine page B (fpzx.asm includes this). The Spectrum's calculator
;; truncates its quotients (79 / 10 came out a bit low, and 7.9 - 7 printed
;; 0.899999999): these round as the CPC's firmware does, half away from
;; zero, on a mantissa of 32 bits with 8 more below it.
;;
;; A number unpacked: [0] those 8 bits, [1-4] the mantissa (its leading 1
;; set: bit 31), least significant first, [5] the exponent (0 is zero),
;; [6] the sign (bit 7).

UA          equ 0               ; the offsets
UX          equ 5
US          equ 6
fa:         defs 7,0            ; the operands unpacked
fb:         defs 7,0
fq:         defs 5,0            ; a quotient; a product's lower half
fr:         defs 5,0            ; a remainder
f_e16:      dw 0                ; an exponent while it is worked out
f_dst:      dw 0                ; the answer's place (the callers keep
                                ;   their own in f_xp)

;; f_unp: HL = a real, DE = a place -> it unpacked there. HL kept.
f_unp:
    push hl
    xor a
    ld (de),a
    inc de
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    ld a,(hl)
    ld c,a
    or #80
    ld (de),a
    inc hl
    inc de
    ld a,(hl)
    ld (de),a
    inc de
    ld a,c
    and #80
    ld (de),a
    pop hl
    ret

;; f_pk: fa -> the real at HL, rounded: the 8 bits below the mantissa
;; half or more, one more. HL kept; no carry if it got too big.
f_pk:
    ld a,(fa+UX)
    or a
    jp z,f_zero
    ld e,a
    push hl
    ld a,(fa+UA)
    add a,a                     ; carry: the first bit below
    ld a,(fa+1)
    adc a,0
    ld (hl),a
    inc hl
    ld a,(fa+2)
    adc a,0
    ld (hl),a
    inc hl
    ld a,(fa+3)
    adc a,0
    ld (hl),a
    inc hl
    ld a,(fa+4)
    adc a,0
    jr nc,.n
    ld a,#80                    ; all ones and one more: twice as big
    inc e
    jr nz,.n
    pop hl
    or a
    ret
.n:
    and #7F
    ld c,a
    ld a,(fa+US)
    or c
    ld (hl),a
    inc hl
    ld (hl),e
    pop hl
    scf
    ret

;; f_ops: HL, DE = two reals -> fa, fb unpacked; f_dst = HL
f_ops:
    ld (f_dst),hl
    push de
    ld de,fa
    call f_unp
    pop hl
    ld de,fb
    jp f_unp

;; FP_ADD: (HL) += (DE)
b_fp_add:
    call f_ops
    call f_addab
    ld hl,(f_dst)
    ret nc
    jp f_pk

;; FP_RSUB: (HL) = (DE) - (HL)
b_fp_rsub:
    push hl                     ; the place
    ex de,hl
    call f_ops                  ; fa = (DE), fb = (HL)
    pop hl
    ld (f_dst),hl
    ld a,(fb+US)
    xor #80
    ld (fb+US),a                ; fa + -fb
    call f_addab
    ld hl,(f_dst)
    ret nc
    jp f_pk

;; f_addab: fa = fa + fb -> carry, or none if it got too big
f_addab:
    ld a,(fb+UX)
    or a
    scf
    ret z                       ; + 0
    ld a,(fa+UX)
    or a
    jr nz,.both
    ld hl,fb                    ; 0 +
    ld de,fa
    ld bc,7
    ldir
    scf
    ret
.both:
    ld a,(fa+UX)                ; fa the one with the larger exponent
    ld b,a
    ld a,(fb+UX)
    cp b
    jr c,.ord
    jr z,.ord
    call f_swap
.ord:
    ld a,(fb+UX)
    ld c,a
    ld a,(fa+UX)
    sub c                       ; how far apart
    cp 41
    ccf
    ret c                       ; fb too small to count
    or a
    jr z,.al
    ld b,a                      ; fb shifted that far right
.sh:
    ld hl,fb+4
    srl (hl)
    dec hl
    rr (hl)
    dec hl
    rr (hl)
    dec hl
    rr (hl)
    dec hl
    rr (hl)
    djnz .sh
.al:
    ld a,(fa+US)
    ld b,a
    ld a,(fb+US)
    xor b
    jp m,.sub
    ld hl,fa                    ; the same sign: the sum
    ld de,fb
    ld b,5
    or a
.add:
    ld a,(de)
    adc a,(hl)
    ld (hl),a
    inc hl
    inc de
    djnz .add
    ccf
    ret c                       ; (no carry out of the top: done, carry)
    ld hl,fa+4                  ; carried: one place right, the carry in
    rr (hl)
    dec hl
    rr (hl)
    dec hl
    rr (hl)
    dec hl
    rr (hl)
    dec hl
    rr (hl)
    ld hl,fa+UX
    inc (hl)
    scf
    ret nz
    or a                        ; past the largest
    ret
.sub:                           ; signs differ: the difference
    ld hl,fa
    ld de,fb
    ld b,5
    or a
.s:
    ld a,(de)
    ld c,a
    ld a,(hl)
    sbc a,c
    ld (hl),a
    inc hl
    inc de
    djnz .s
    jr nc,.norm
    ld hl,fa                    ; below zero (the exponents were equal):
    ld b,5                      ;   negated, and fb's sign it is
    scf
.neg:
    ld a,(hl)
    cpl
    adc a,0
    ld (hl),a
    inc hl
    djnz .neg
    ld a,(fa+US)
    xor #80
    ld (fa+US),a
.norm:
    ld a,(fa)
    ld hl,fa+1
    or (hl)
    inc hl
    or (hl)
    inc hl
    or (hl)
    inc hl
    or (hl)
    jr nz,.l
    xor a                       ; nothing left: 0
    ld (fa+UX),a
    scf
    ret
.l:
    ld a,(fa+4)
    bit 7,a
    scf
    ret nz
    ld hl,fa                    ; one place left until the top bit is 1
    sla (hl)
    inc hl
    rl (hl)
    inc hl
    rl (hl)
    inc hl
    rl (hl)
    inc hl
    rl (hl)
    ld hl,fa+UX
    dec (hl)
    jr nz,.l
    scf                         ; (too small to be seen: 0)
    ret

;; f_swap: fa and fb change places
f_swap:
    ld hl,fa
    ld de,fb
    ld b,7
.l:
    ld a,(de)
    ld c,(hl)
    ld (hl),a
    ld a,c
    ld (de),a
    inc hl
    inc de
    djnz .l
    ret

;; f_sign2: fa's sign = fa's xor fb's
f_sign2:
    ld a,(fb+US)
    ld b,a
    ld a,(fa+US)
    xor b
    ld (fa+US),a
    ret

;; f_exps: A = fa's exponent made from f_e16 (signed, 16 bits): 0 if it is
;; at or below 0 (too small: zero), NC if above 255 (too big)
f_exps:
    ld hl,(f_e16)
    bit 7,h
    jr nz,.zero
    ld a,h
    or a
    jr nz,.big
    ld a,l
    or a
    jr z,.zero
    ld (fa+UX),a
    scf
    ret
.zero:
    xor a
    ld (fa+UX),a
    scf
    ret
.big:
    or a
    ret

;; FP_MUL: (HL) *= (DE): the 64-bit product of the mantissas, its top 40
;; bits kept
b_fp_mul:
    ex de,hl
    call f_exp
    ex de,hl
    or a
    jp z,f_zero                 ; times 0
    call f_exp
    or a
    jp z,f_zero
    call f_ops
    call f_sign2
    ld a,(fa+UX)                ; the exponent: ea + eb - 128
    ld l,a
    ld h,0
    ld a,(fb+UX)
    ld e,a
    ld d,0
    add hl,de
    ld de,-128
    add hl,de
    ld (f_e16),hl
    ; the product, in fq (low) and fa+1..4 (high): shifted right as fb's
    ; bits are taken from the bottom
    ld hl,fa+1                  ; fr = fa's mantissa, the multiplicand
    ld de,fr
    ld bc,4
    ldir
    xor a
    ld hl,fa+1
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    ld hl,fq
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    ld b,32
.bit:
    push bc
    ld hl,fb+4                  ; fb's next bit, from the bottom
    srl (hl)
    dec hl
    rr (hl)
    dec hl
    rr (hl)
    dec hl
    rr (hl)
    jr nc,.no
    ld hl,fa+1                  ; high += multiplicand
    ld de,fr
    ld b,4
    or a
.ad:
    ld a,(de)
    adc a,(hl)
    ld (hl),a
    inc hl
    inc de
    djnz .ad
.no:
    ld hl,fa+4                  ; the product one place right, the carry in
    rr (hl)
    dec hl
    rr (hl)
    dec hl
    rr (hl)
    dec hl
    rr (hl)
    ld hl,fq+3
    rr (hl)
    dec hl
    rr (hl)
    dec hl
    rr (hl)
    dec hl
    rr (hl)
    pop bc
    djnz .bit
    ld a,(fa+4)
    bit 7,a
    jr nz,.top
    ld hl,fq                    ; below 0.5: all of it one place left
    sla (hl)
    inc hl
    rl (hl)
    inc hl
    rl (hl)
    inc hl
    rl (hl)
    ld hl,fa+1
    rl (hl)
    inc hl
    rl (hl)
    inc hl
    rl (hl)
    inc hl
    rl (hl)
    ld hl,(f_e16)
    dec hl
    ld (f_e16),hl
.top:
    ld a,(fq+3)                 ; the 8 bits below the mantissa
    ld (fa+UA),a
    call f_exps
    ld hl,(f_dst)
    ret nc
    jp f_pk

;; FP_DIV: (HL) /= (DE): 40 bits of the mantissas' quotient
b_fp_div:
    ex de,hl
    call f_exp
    ex de,hl
    or a
    ret z                       ; by 0: no (and no carry, from or)
    call f_exp
    or a
    jp z,f_zero
    call f_ops
    call f_sign2
    ld a,(fa+UX)                ; the exponent: ea - eb + 128, + 1 if fa's
    ld l,a                      ;   mantissa is fb's or more
    ld h,0
    ld a,(fb+UX)
    ld e,a
    ld d,0
    or a
    sbc hl,de
    ld de,128
    add hl,de
    ld (f_e16),hl
    ld hl,fa+1                  ; fr = fa's mantissa, the remainder
    ld de,fr
    ld bc,4
    ldir
    xor a
    ld (fr+4),a
    call f_rge                  ; fa's mantissa fb's or more?
    jr nc,.big
    ld hl,fr                    ; less: twice it
    sla (hl)
    inc hl
    rl (hl)
    inc hl
    rl (hl)
    inc hl
    rl (hl)
    inc hl
    rl (hl)
    jr .go
.big:
    ld hl,(f_e16)
    inc hl
    ld (f_e16),hl
.go:
    xor a
    ld hl,fq
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a
    ld b,40
.bit:
    push bc
    ld hl,fq                    ; the quotient one place left
    sla (hl)
    inc hl
    rl (hl)
    inc hl
    rl (hl)
    inc hl
    rl (hl)
    inc hl
    rl (hl)
    call f_rge
    jr c,.zero
    ld hl,fr                    ; the remainder less fb, a 1 in
    ld de,fb+1
    ld b,4
    or a
.s:
    ld a,(de)
    ld c,a
    ld a,(hl)
    sbc a,c
    ld (hl),a
    inc hl
    inc de
    djnz .s
    ld a,(hl)
    sbc a,0
    ld (hl),a
    ld hl,fq
    set 0,(hl)
.zero:
    ld hl,fr                    ; the remainder one place left
    sla (hl)
    inc hl
    rl (hl)
    inc hl
    rl (hl)
    inc hl
    rl (hl)
    inc hl
    rl (hl)
    pop bc
    djnz .bit
    ld hl,fq
    ld de,fa
    ld bc,5
    ldir
    call f_exps
    ld hl,(f_dst)
    ret nc
    jp f_pk

;; f_rge: -> NC if the remainder (fr, 5 bytes) is fb's mantissa or more
;; (carry if less)
f_rge:
    ld a,(fr+4)
    or a
    ret nz                      ; (NC: more)
    ld hl,fr+3
    ld de,fb+4
    ld b,4
.c:
    ld a,(de)
    ld c,a
    ld a,(hl)
    cp c
    ret nz                      ; carry if less
    dec hl
    dec de
    djnz .c
    or a                        ; equal: NC
    ret
