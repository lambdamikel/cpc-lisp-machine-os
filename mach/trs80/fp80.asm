;; CPC Lisp -- floats on the TRS-80, in the machine page (page.asm
;; includes this).
;;
;; A real is the CPC's: five bytes, four of mantissa, least significant
;; first, the top bit of the last the sign, then the exponent (0 is zero,
;; &80 is 0.5's). That is Microsoft's binary form, with a 32-bit mantissa:
;; the Level II ROM has the same with 24 bits (single) and 56 (double),
;; so going between them is copying bytes and rounding.
;;
;; + - * / go to the ROM's double precision (WRA1 op WRA2) and come back
;; rounded to 32 bits -- as good as the CPC's. The functions go to its
;; single precision: about seven digits. Whatever would make the ROM stop
;; with a BASIC error (dividing by zero, overflow, the logarithm of 0) is
;; looked for first and answered with no carry, as the CPC's firmware
;; answers it. The rest -- comparing, the signs, the conversions to and
;; from whole numbers, powers of ten -- is done here, on the bytes.

VALTYP      equ #40AF           ; 4 single, 8 double
WRA1        equ #411D           ; the accumulator: a double from here,
WRA1S       equ #4121           ;   a single from here,
WRA1E       equ #4124           ;   the exponent of both
WRA2        equ #4127           ; a double operand
R_DADD      equ #0C77           ; WRA1 = WRA1 + WRA2
R_DSUB      equ #0C70           ; WRA1 = WRA1 - WRA2
R_DMUL      equ #0DA1           ; WRA1 = WRA1 * WRA2
R_DDIV      equ #0DE5           ; WRA1 = WRA1 / WRA2
R_SQR       equ #13E7           ; single: WRA1 = f(WRA1) -- the ROM's
R_LOG       equ #0809           ;   table of functions at &1608 has these
R_EXP       equ #1439
R_COS       equ #1541
R_SIN       equ #1547
R_TAN       equ #15A8
R_ATN       equ #15BD
R_DIVSUB    equ #18F7           ; the single divide's helper, which the
DIVSUB      equ #4080           ;   ROM copies to RAM when BASIC starts
DIVSUB_LEN  equ 14              ;   (f_init does it here)

fp_t:       defs 5,0            ; a real to work on
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
fp_ten:     db 0,0,0,#20,#84

;; f_init: the ROM's divide helper into RAM (m_init calls this)
f_init:
    ld hl,R_DIVSUB
    ld de,DIVSUB
    ld bc,DIVSUB_LEN
    ldir
    ret

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
;; f_jphl: call the routine at HL
f_jphl:
    jp (hl)

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

;; f_c2d: HL = a real, DE = a double's place (WRA1, WRA2) -> it there
f_c2d:
    xor a
    ld (de),a
    inc de
    ld (de),a
    inc de
    ld (de),a
    inc de
    ld bc,5
    ldir
    ret

;; f_d2c: WRA1, a double -> the real at HL, rounded to 32 bits. HL kept;
;; no carry if it got too big
f_d2c:
    ld a,(WRA1E)
    or a
    jp z,f_zero
    ld e,a
    ld a,(WRA1+6)
    ld d,a
    and #80
    ld c,a
    set 7,d
    push hl
    ld a,(WRA1+2)
    add a,a                     ; carry: the first bit cut off
    ld a,(WRA1+3)
    adc a,0
    ld (hl),a
    inc hl
    ld a,(WRA1+4)
    adc a,0
    ld (hl),a
    inc hl
    ld a,(WRA1+5)
    adc a,0
    ld (hl),a
    inc hl
    ld a,d
    adc a,0
    jr nc,f_top
    ld a,#80                    ; all ones and one more: twice as big
    inc e
    jr nz,f_top
    pop hl
    or a
    ret

;; f_c2s: HL = a real -> WRA1, single (rounded to 24 bits). HL kept.
f_c2s:
    ld a,4
    ld (VALTYP),a
    push hl
    inc hl
    inc hl
    inc hl
    ld a,(hl)
    and #80
    ld c,a                      ; the sign
    ld a,(hl)
    or #80
    ld d,a                      ; the top byte, its leading 1 back
    inc hl
    ld e,(hl)                   ; the exponent
    pop hl
    ld a,e
    or a
    jr nz,.nz
    ld (WRA1E),a
    ret
.nz:
    push hl
    ld a,(hl)
    add a,a
    inc hl
    ld a,(hl)
    adc a,0
    ld (WRA1S),a
    inc hl
    ld a,(hl)
    adc a,0
    ld (WRA1S+1),a
    ld a,d
    adc a,0
    jr nc,.n
    ld a,#80
    inc e
    jr nz,.n
    dec e
    ld a,#FF
.n:
    and #7F
    or c
    ld (WRA1S+2),a
    ld a,e
    ld (WRA1E),a
    pop hl
    ret

;; f_s2c: WRA1, single -> the real at HL. HL kept, carry.
f_s2c:
    push hl
    ld (hl),0
    inc hl
    ex de,hl
    ld hl,WRA1S
    ld bc,4
    ldir
    pop hl
    scf
    ret

;; f_op: HL = a real -> WRA1, DE = another -> WRA2, doubles. HL, DE kept.
f_op:
    push hl
    push de
    ld de,WRA1
    call f_c2d
    pop hl
    push hl
    ld de,WRA2
    call f_c2d
    pop de
    pop hl
    ld a,8
    ld (VALTYP),a
    ret

;; f_rom: BC = a double routine of the ROM's; WRA1, WRA2 ready -> it run,
;; WRA1 to the real at HL. HL kept.
f_rom:
    push hl
    ld h,b
    ld l,c
    call f_jphl
    pop hl
    jp f_d2c

;; f_huge: no carry if the real at HL or at DE is 2^126 or more
f_huge:
    call f_exp
    cp #FE
    ret nc
    ex de,hl
    call f_exp
    ex de,hl
    cp #FE
    ret

;; FP_MOVE: (HL) = (DE). BC, DE, HL kept (the callers count on it).
m_fp_move:
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
m_fp_pi:
    ld de,fp_pi
    jr m_fp_move

;; FP_ANGLE: A = 0, radians -- the only kind here
m_fp_angle:
    scf
    ret

;; FP_NEG: (HL) = -(HL)
m_fp_neg:
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
m_fp_sgn:
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
m_fp_cmp:
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
m_fp_int2r:
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
m_fp_bin2r:
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
m_fp_fix:
    call f_split
    ret nc
    xor a
    jr f_mout
;; FP_R2BIN: the same, rounded, a half away from zero
m_fp_r2bin:
    call f_split
    ret nc
    ld a,(fp_rnd)
    jr f_mout
;; FP_INT: the same, floored
m_fp_int:
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
m_fp_r2int:
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

;; FP_ADD: (HL) += (DE)
m_fp_add:
    call f_huge
    ret nc
    call f_op
    ld bc,R_DADD
    jp f_rom

;; FP_RSUB: (HL) = (DE) - (HL)
m_fp_rsub:
    call f_huge
    ret nc
    ex de,hl
    call f_op                   ; WRA1 = (DE), WRA2 = (HL)
    ex de,hl
    ld bc,R_DSUB
    jp f_rom

;; FP_MUL: (HL) *= (DE)
m_fp_mul:
    ex de,hl
    call f_exp
    ex de,hl
    or a
    jp z,f_zero                 ; times 0
    ld b,a
    call f_exp
    or a
    jp z,f_zero
    add a,b                     ; the exponents' sum, less 256 if carry
    jr c,.hi
    cp 130
    jp c,f_zero                 ; too small to see: 0
    jr .go
.hi:
    cp 127
    ret nc                      ; 2^127 or more: too big
.go:
    call f_op
    ld bc,R_DMUL
    jp f_rom

;; FP_DIV: (HL) /= (DE)
m_fp_div:
    ex de,hl
    call f_exp
    ex de,hl
    or a
    ret z                       ; by 0: no (and no carry, from or)
    ld b,a
    call f_exp
    or a
    jp z,f_zero
    sub b                       ; the exponents' difference
    jr c,.lo
    cp 127
    ret nc                      ; too big
    jr .go
.lo:
    cp 130
    jp c,f_zero                 ; too small: 0
.go:
    call f_op
    ld bc,R_DDIV
    jp f_rom

;; FP_EXP10: (HL) times 10 to the power A (from -128 to 127)
m_fp_exp10:
    ld (f_cnt),a
    ld (f_xp),hl
    ld de,WRA1
    call f_c2d
    ld a,8
    ld (VALTYP),a
.l:
    ld a,(WRA1E)
    or a
    jr z,.done                  ; zero stays zero
    ld a,(f_cnt)
    or a
    jr z,.done
    ld hl,fp_ten
    ld de,WRA2
    call f_c2d
    ld a,(f_cnt)
    bit 7,a
    jr nz,.down
    ld a,(WRA1E)
    cp #FB
    jr nc,.no
    ld hl,R_DMUL
    call f_jphl
    ld hl,f_cnt
    dec (hl)
    jr .l
.down:
    ld a,(WRA1E)
    cp 6
    jr c,.tiny
    ld hl,R_DDIV
    call f_jphl
    ld hl,f_cnt
    inc (hl)
    jr .l
.done:
    ld hl,(f_xp)
    jp f_d2c
.tiny:
    ld hl,(f_xp)
    jp f_zero
.no:
    ld hl,(f_xp)
    or a
    ret

;; f_fn1: HL = a real, BC = a single function of the ROM's -> (HL) = it of
;; (HL). HL kept, carry.
f_fn1:
    push hl
    push bc
    call f_c2s
    pop hl
    call f_jphl
    pop hl
    jp f_s2c

;; FP_SQR, FP_LOG, FP_EXP, FP_SIN, FP_COS, FP_TAN, FP_ATN: (HL) = f((HL))
m_fp_sqr:
    call f_exp
    or a
    scf
    ret z                       ; the root of 0
    call f_neg
    jp nz,f_no
    ld bc,R_SQR
    jr f_fn1
m_fp_log:
    call f_exp
    or a
    jp z,f_no
    call f_neg
    jp nz,f_no
    ld bc,R_LOG
    jr f_fn1
m_fp_exp:
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
    ld bc,R_EXP
    jr f_fn1
m_fp_sin:
    ld bc,R_SIN
    jr f_fn1
m_fp_cos:
    ld bc,R_COS
    jr f_fn1
m_fp_tan:
    ld bc,R_TAN
    jr f_fn1
m_fp_atn:
    ld bc,R_ATN
    jr f_fn1

;; FP_POW: (HL) = (HL) to the power (DE): e^(y ln |x|), a negative x only
;; to a whole power
m_fp_pow:
    ld (f_xp),hl
    ld (f_yp),de
    ex de,hl
    call f_exp
    ex de,hl
    or a
    jr nz,.y
    ld de,fp_one                ; to the power 0: 1
    jp m_fp_move
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
    ld bc,R_LOG
    call f_fn1                  ; ln |x|
    ld hl,fp_t
    ld de,(f_yp)
    call m_fp_mul               ; times y
    jp nc,f_no
    ld hl,fp_t
    call m_fp_exp
    jp nc,f_no
    ld hl,(f_xp)
    ld de,fp_t
    call m_fp_move
    ld a,(f_sign)
    or a
    scf
    ret z
    jp m_fp_neg
