;; CPC Lisp -- floats, through the firmware's maths package (library ROM).
;;
;; A float is a typed cell (HDR_FLOAT) whose data points into block space
;; at a firmware real: four bytes of mantissa, least significant first, the
;; top bit of the last one the sign, then an exponent byte (0 = zero). The
;; GC treats it as it treats a string. Arithmetic copies values into the
;; accumulators V_FA.. (fixed RAM: the firmware gets their addresses) and
;; the result back into a new float.
;;
;; The core keeps fixnum arithmetic; a numeric subr that meets a float, or
;; overflows, hands its whole call over (nums_v in src/subrs.asm), and its
;; reader and printer call ln_read and ln_print. They come in through the
;; four jumps at lib_numbers (the header's +20).
;;
;; The maths jumpblock is &BD3D on a 464 and &BD61 on a 664/6128, with the
;; routines used here at the same offsets in both (the 464's REAL
;; SUBTRACTION and the 6128's RND are where they differ): fmcall adds the
;; difference.

M_MOVE      equ #BD3D           ; (HL) = (DE)
M_INT2R     equ #BD40           ; HL = magnitude, A bit 7 = sign -> (DE)
M_BIN2R     equ #BD43           ; 4 bytes at HL, A bit 7 = sign -> real there
M_R2INT     equ #BD46           ; (HL) -> HL rounded, S = sign, C if it fit
M_R2BIN     equ #BD49           ; (HL) -> 4 bytes there, rounded; B bit 7 sign
M_FIX       equ #BD4C           ;   the same, truncated
M_INT       equ #BD4F           ;   the same, floored
M_EXP10     equ #BD55           ; (HL) *= 10^A
M_ADD       equ #BD58           ; (HL) += (DE)
M_RSUB      equ #BD5E           ; (HL) = (DE) - (HL)
M_MUL       equ #BD61           ; (HL) *= (DE)
M_DIV       equ #BD64           ; (HL) /= (DE)
M_CMP       equ #BD6A           ; A = 1, 0, &FF: (HL) >, =, < (DE)
M_NEG       equ #BD6D           ; (HL) = -(HL)
M_SGN       equ #BD70           ; A = 1, 0, &FF; Z if zero, C if negative
M_ANGLE     equ #BD73           ; A = 0: radians
M_PI        equ #BD76           ; (HL) = pi
M_SQR       equ #BD79           ; (HL) = sqrt (HL), and so on:
M_POW       equ #BD7C           ; (HL) = (HL) ^ (DE)
M_LOG       equ #BD7F
M_EXP       equ #BD85
M_SIN       equ #BD88
M_COS       equ #BD8B
M_TAN       equ #BD8E
M_ATN       equ #BD91

;; FM: call a maths routine by its 464 address (the byte after the call
;; says which)
macro FM addr
    call fmcall
    db {addr}-M_MOVE
mend

fl_m_ovf:     db "float overflow",0
fl_m_range:   db "argument out of range:",0

lib_numbers:
    jp ln_arith
    jp ln_read
    jp ln_print
    jp ln_int

;; ln_int: HL = a number -> NC, HL = it rounded, a plain 16-bit number (for
;; the core's num_int). BC, DE kept.
ln_int:
    push de
    ex de,hl
    call fl_plain
    pop de
    or a
    ret

;; fmcall: the byte after the call = a maths routine's offset in the 464's
;; jumpblock; A, BC, DE, HL go in. fmcall_ix: IX = its 464 address.
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
fmcall_ix:
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

;; f_get: DE = a number, HL = five bytes -> its value there. BC kept. An
;; error for anything else.
f_get:
    bit 0,e
    jr z,.notfix
    push bc
    push hl
    ex de,hl
    sra h
    rr l
    ld a,h                      ; bit 7: the sign
    bit 7,h
    jr z,.pos
    push af
    xor a
    sub l
    ld l,a
    sbc a,a
    sub h
    ld h,a
    pop af
.pos:
    pop de
    FM M_INT2R
    pop bc
    ret
.notfix:
    ex de,hl
    CORE is_float
    ex de,hl
    jr nz,.bad
    push bc
    ex de,hl
    LDHLI                       ; its block
    inc hl
    inc hl
    ld bc,5
    ldir
    pop bc
    ret
.bad:
    ld hl,m_notnum
    CORE error

;; f_new: HL = five bytes -> HL = a new float holding them
f_new:
    push hl
    ld bc,4
    add hl,bc
    ld a,(hl)
    pop hl
    or a
    jr nz,.ok
    push hl                     ; zero: one zero, whatever the rest says
    ld b,5
.z:
    ld (hl),a
    inc hl
    djnz .z
    pop hl
.ok:
    ld bc,5
    ld de,HDR_FLOAT
    CORE make_blob
    ret

;; fl_first: DE = a number -> FA. BC, HL kept
fl_first:
    push hl
    ld hl,V_FA
    call f_get
    pop hl
    ret

;; fl_arg: HL = a number -> FA, and HL = V_FA
fl_arg:
    ex de,hl
    ld hl,V_FA
    call f_get
    ld hl,V_FA
    ret

;; fl_result: FA -> HL = a new float
fl_result:
    ld hl,V_FA
    jp f_new

;; f_chk: after a maths routine: an error unless carry
f_chk:
    ret c
    ld hl,fl_m_ovf
    ld de,UNBOUND
    jp lib_error

;; FA op= FB, with errors
f_add:
    ld ix,M_ADD
    jr f_op
f_mul:
    ld ix,M_MUL
    jr f_op
f_div:
    ld hl,V_FB
    FM M_SGN
    jr z,f_div0
    ld ix,M_DIV
f_op:
    ld hl,V_FA
    ld de,V_FB
    call fmcall_ix
    jr f_chk
f_div0:
    ld hl,m_div0
    ld de,UNBOUND
    CORE error
f_sub:                          ; FB = FA - FB, then into FA
    ld hl,V_FB
    ld de,V_FA
    FM M_RSUB
    call f_chk
    ld hl,V_FA
    ld de,V_FB
    FM M_MOVE
    ret

;; fl_fold: HL = &arg, B = how many, DE = an op (FA op= FB) -> FA op each
fl_fold:
    ld (V_FOP),de
.l:
    ld a,b
    or a
    ret z
    NEXTARG
    push hl
    push bc
    ld hl,V_FB
    call f_get
    ld hl,(V_FOP)
    call lcall_hl
    pop bc
    pop hl
    dec b
    jr .l

lcall_hl:
    jp (hl)

;; ---------------------------------------------------------------------------
;; ARITHMETIC: the core's numeric subrs, given floats or overflowing. HL =
;; &arg 0, B = how many, C as the subr had it, DE = its NUM_ label.

ln_arith:
    push hl
    ld hl,ln_ops
.f:
    ld a,(hl)
    inc hl
    cp e
    jr nz,.n
    ld a,(hl)
    cp d
    jr z,.got
.n:
    inc hl
    inc hl
    inc hl
    jr .f
.got:
    inc hl
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ex (sp),hl
    ret

ln_ops:
    dw NUM_PLUS,fl_plus
    dw NUM_MINUS,fl_minus
    dw NUM_TIMES,fl_times
    dw NUM_COMPARE,fl_compare
    dw NUM_INC,fl_inc
    dw NUM_DEC,fl_dec
    dw NUM_ZEROP,fl_zerop
    dw NUM_PLUSP,fl_plusp
    dw NUM_MINUSP,fl_minusp
    dw NUM_ABS,fl_abs
    dw NUM_MAXMIN,fl_maxmin
    dw NUM_TRUNCATE,fl_truncate
    dw NUM_FLOOR,fl_floor
    dw NUM_MOD,fl_mod
    dw NUM_REM,fl_rem
    dw NUM_RANDOM,fl_random

fl_plus:
    ld de,1                     ; 0
    call fl_first
    ld de,f_add
    call fl_fold
    jp fl_result

fl_times:
    ld de,3                     ; 1
    call fl_first
    ld de,f_mul
    call fl_fold
    jp fl_result

fl_minus:
    ld de,1
    dec b
    jr nz,.many
    inc b                       ; (- x) is 0 - x
    jr .go
.many:
    NEXTARG
.go:
    call fl_first
    ld de,f_sub
    call fl_fold
    jp fl_result

;; fl_inc, fl_dec: (1+ x), (1- x)
fl_inc:
    ld de,f_add
    jr fl_incdec
fl_dec:
    ld de,f_sub
fl_incdec:
    push de
    NEXTARG
    call fl_first
    ld hl,V_FB
    ld de,3
    call f_get
    pop hl
    call lcall_hl
    jp fl_result

fl_abs:
    NEXTARG
    call fl_first
    ld hl,V_FA
    FM M_SGN
    jr nc,.pos
    ld hl,V_FA
    FM M_NEG
.pos:
    jp fl_result

;; fl_sgn: the argument's sign: A = 1, 0, &FF; Z if zero, C if negative
fl_sgn:
    NEXTARG
    call fl_first
    ld hl,V_FA
    FM M_SGN
    ret
fl_zerop:
    call fl_sgn
    jp z,lt
    jp lnil
fl_plusp:
    call fl_sgn
    dec a
    jp z,lt
    jp lnil
fl_minusp:
    call fl_sgn
    jp c,lt
    jp lnil

;; fl_compare: C = the outcomes of each x vs the next that pass: 1 less,
;; 2 equal, 4 greater
fl_compare:
    NEXTARG
    call fl_first
    dec b
    jp z,lt
.l:
    NEXTARG
    push hl
    push bc
    ld hl,V_FB
    call f_get
    ld hl,V_FA
    ld de,V_FB
    FM M_CMP
    pop bc
    ld e,4
    cp 1
    jr z,.got
    ld e,2
    or a
    jr z,.got
    ld e,1
.got:
    ld a,e
    and c
    pop hl
    jp z,lnil
    push hl
    ld hl,V_FA
    ld de,V_FB
    FM M_MOVE
    pop hl
    djnz .l
    jp lt

;; fl_maxmin: C = 0 max, 1 min. The argument itself is the answer.
fl_maxmin:
    NEXTARG
    push de                     ; the best so far
    call fl_first
    dec b
    jr z,.done
.l:
    NEXTARG
    push hl
    push bc
    push de
    ld hl,V_FB
    call f_get
    ld hl,V_FB
    ld de,V_FA
    FM M_CMP                    ; 1: this one is greater
    pop de
    pop bc
    bit 0,c
    jr nz,.min
    dec a
    jr .test
.min:
    inc a
.test:
    pop hl
    jr nz,.keep
    ex (sp),hl                  ; take it
    ld h,d
    ld l,e
    ex (sp),hl
    push hl
    ld hl,V_FA
    ld de,V_FB
    FM M_MOVE
    pop hl
.keep:
    djnz .l
.done:
    pop hl
    ret

;; fl_quot: (x [y]) -> FA = x, or x / y
fl_quot:
    NEXTARG
    call fl_first
    dec b
    ret z
    NEXTARG
    ld hl,V_FB
    call f_get
    jp f_div

fl_truncate:
    call fl_quot
    ld ix,M_FIX
    jr fl_toint
fl_floor:
    call fl_quot
    ld ix,M_INT
    jr fl_toint

;@ ROUND 1 2 lf_round
lf_round:
    call fl_quot
    ld ix,M_R2BIN
    jr fl_toint

;@ CEILING 1 2 lf_ceiling
lf_ceiling:
    call fl_quot
    ld hl,V_FA
    FM M_NEG
    ld ix,M_INT
    call fl_toint
    ex de,hl                    ; -(floor -x)
    ld hl,2
    or a
    sbc hl,de
    ret po
    jp fl_toobig

;; fl_toint: IX = M_FIX, M_INT or M_R2BIN -> FA made a whole number, as a
;; fixnum in HL. (Those routines say nothing about overflow: FA must be
;; well inside four bytes first.)
fl_toint:
    call fl_small
    ld hl,V_FA
    call fmcall_ix
    ld hl,V_FA
    call fl_bin2fix
    ret nc
fl_toobig:
    ld hl,m_toobig
    ld de,UNBOUND
    CORE error

;; fl_small: an error unless |FA| < 2^24
fl_small:
    ld a,(V_FA+4)
    cp 128+24+1
    ret c
    jr fl_toobig

;; fl_bin2fix: HL = a magnitude in four bytes, B bit 7 its sign -> NC and
;; HL = a fixnum, or C if it does not fit
fl_bin2fix:
    push hl
    inc hl
    inc hl
    ld a,(hl)
    inc hl
    or (hl)
    pop hl
    scf
    ret nz
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld a,h
    cp #40
    jr c,.ok
    scf
    ret nz
    ld a,l                      ; 16384 fits if negative
    or a
    scf
    ret nz
    bit 7,b
    scf
    ret z
.ok:
    bit 7,b
    jr z,.pos
    xor a
    sub l
    ld l,a
    sbc a,a
    sub h
    ld h,a
.pos:
    add hl,hl
    inc hl
    or a
    ret

;; fl_mod, fl_rem: x - y * floor (or truncate) of x / y
fl_mod:
    ld ix,M_INT
    jr fl_modrem
fl_rem:
    ld ix,M_FIX
fl_modrem:
    push ix
    NEXTARG
    push hl
    ld hl,V_FC
    call f_get                  ; FC = x
    pop hl
    NEXTARG
    ld hl,V_FB
    call f_get                  ; FB = y
    ld hl,V_FA
    ld de,V_FC
    FM M_MOVE
    call f_div                  ; FA = x / y
    call fl_small
    pop ix
    ld hl,V_FA
    call fmcall_ix              ; a whole number, four bytes
    ld a,b
    ld hl,V_FA
    FM M_BIN2R
    call f_mul                  ; * y
    ld hl,V_FA
    ld de,V_FC
    FM M_RSUB                   ; x - that
    call f_chk
    jp fl_result

;; (random x), x a float: [0, x)
fl_random:
    NEXTARG
    push de
    call fl_first
    ld hl,V_FA
    FM M_SGN
    pop de
    dec a
    jp nz,fl_range
    CORE rand16
    xor a
    ld de,V_FB
    FM M_INT2R                  ; 0..65535
    ld hl,V_FB+4                ; / 65536
    ld a,(hl)
    or a
    jr z,.zero
    sub 16
    ld (hl),a
.zero:
    call f_mul
    jp fl_result

;; fl_range: DE = an argument out of a function's range
fl_range:
    ld hl,fl_m_range
    jp lib_error

;; ---------------------------------------------------------------------------
;; FUNCTIONS

;@ FLOAT 1 1 lf_float
lf_float:
    CORE is_float
    ret z
    call fl_arg
    jp fl_result

;@ FLOATP 1 1 lf_floatp
lf_floatp:
    CORE is_float
    jp z,lt
    jp lnil

;; fl_fn1: IX = a maths routine, FA = its argument -> a new float
fl_fn1:
    ld hl,V_FA
    call fmcall_ix
    call f_chk
    jp fl_result

;; fl_pos: HL = a number -> FA; Z if zero, C if negative; DE = it
fl_pos:
    push hl
    call fl_arg
    FM M_SGN
    pop de
    ret

;@ SQRT 1 1 lf_sqrt
lf_sqrt:
    call fl_pos
    jp c,fl_range
    ld ix,M_SQR
    jr fl_fn1

;@ EXP 1 1 lf_exp
lf_exp:
    call fl_arg
    ld ix,M_EXP
    jr fl_fn1

;; fl_trig: radians, then IX
fl_trig:
    push ix
    call fl_arg
    xor a
    FM M_ANGLE
    pop ix
    jr fl_fn1

;@ SIN 1 1 lf_sin
lf_sin:
    ld ix,M_SIN
    jr fl_trig
;@ COS 1 1 lf_cos
lf_cos:
    ld ix,M_COS
    jr fl_trig
;@ TAN 1 1 lf_tan
lf_tan:
    ld ix,M_TAN
    jr fl_trig

;@ LOG 1 2 lf_log
lf_log:
    NEXTARG
    push hl
    push bc
    ex de,hl
    call fl_pos
    jp c,fl_range
    jp z,fl_range
    ld hl,V_FA
    FM M_LOG
    pop bc
    pop hl
    dec b
    jp z,fl_result              ; (log x)
    push hl                     ; (log x base): ln x / ln base
    ld de,V_FA
    ld hl,V_FC
    FM M_MOVE
    pop hl
    NEXTARG
    ex de,hl
    call fl_pos
    jp c,fl_range
    jp z,fl_range
    ld hl,V_FA
    FM M_LOG
    ld hl,V_FB
    ld de,V_FA
    FM M_MOVE
    ld hl,V_FA
    ld de,V_FC
    FM M_MOVE
    call f_div
    jp fl_result

;@ ATAN 1 2 lf_atan
;; (atan y [x]): with x, the angle of the point (x, y), -pi..pi
lf_atan:
    xor a
    FM M_ANGLE
    NEXTARG
    call fl_first               ; FA = y
    dec b
    ld ix,M_ATN
    jp z,fl_fn1
    NEXTARG
    ld hl,V_FB
    call f_get                  ; FB = x
    ld hl,V_FA
    FM M_SGN
    push af                     ; y's sign
    ld hl,V_FB
    FM M_SGN
    jr z,.xzero
    push af                     ; x's sign
    call f_div
    ld hl,V_FA
    FM M_ATN
    pop af
    jr nc,.done                 ; x > 0: that is it
    ld hl,V_FB                  ; x < 0: pi more if y >= 0, else pi less
    FM M_PI
    pop af
    ld de,f_add
    jr nc,.adj
    ld de,f_sub
.adj:
    ex de,hl
    call lcall_hl
    jp fl_result
.xzero:                         ; x = 0: pi/2 times y's sign
    ld hl,V_FA
    FM M_PI
    ld hl,V_FA+4
    dec (hl)
    pop af
    jp nc,.pz
    ld hl,V_FA
    FM M_NEG
    jp fl_result
.pz:
    jp nz,fl_result
    ld de,1                     ; y = 0 too
    ld hl,V_FA
    call f_get
    jp fl_result
.done:
    pop af
    jp fl_result

;@ %POW 2 2 lf_pow
lf_pow:
    push de
    call fl_arg
    pop de
    ld hl,V_FB
    call f_get
    ld hl,V_FA
    ld de,V_FB
    FM M_POW
    call f_chk
    jp fl_result

;@ %PI 0 0 lf_pi
lf_pi:
    ld hl,V_FA
    FM M_PI
    jp fl_result

;@ / 1 255 lf_divide
;; (/ x) is 1/x. Fixnums whose quotient is whole give a fixnum, anything
;; else a float.
lf_divide:
    push hl
    push bc
    ld de,3
    dec b
    jr nz,.many
    inc b                       ; (/ x) is 1 / x
    jr .go
.many:
    NEXTARG
.go:
    call fl_first
    ld de,f_div
    call fl_fold
    pop bc
    pop hl
.all:                           ; were they all fixnums?
    NEXTARG
    bit 0,e
    jp z,fl_result
    djnz .all
    ld a,(V_FA+4)               ; then a whole quotient is a fixnum
    cp 128+16
    jp nc,fl_result
    ld hl,V_FC
    ld de,V_FA
    FM M_MOVE
    ld hl,V_FC
    FM M_FIX
    ld hl,V_FC
    call fl_bin2fix
    jp c,fl_result
    push hl                     ; the fixnum: is it the same value?
    ex de,hl
    ld hl,V_FC
    call f_get
    ld hl,V_FA
    ld de,V_FC
    FM M_CMP
    pop hl
    or a
    ret z
    jp fl_result

;; fl_plain: DE = a number -> HL = it rounded, a plain 16-bit number. BC,
;; DE, IX kept (for lint_hl and lint_de)
fl_plain:
    push bc
    push de
    push ix
    ld hl,V_FD
    call f_get
    ld hl,V_FD
    FM M_R2INT
    jr nc,.big
    jp p,.pos
    ld a,h
    cp #80
    jr c,.neg
    jr nz,.big
    ld a,l
    or a
    jr nz,.big
.neg:
    xor a
    sub l
    ld l,a
    sbc a,a
    sub h
    ld h,a
    jr .done
.pos:
    bit 7,h
    jr nz,.big
.done:
    pop ix
    pop de
    pop bc
    ret
.big:
    pop ix
    pop de
    jp fl_range

;; ---------------------------------------------------------------------------
;; READING: TOKBUF holds B characters -> NC and HL = a float, or C if they
;; are not one. [sign] digits [. digits] [exponent], or with no digits
;; before the point; the exponent is E (or D, F, S, L), a sign and digits.
;; Also a whole number too big for a fixnum. Nine significant digits are
;; kept.
;;
;; C: bit 0 negative, 1 a point seen, 2 a digit seen. D = significant
;; digits taken, E = the decimal exponent so far. The digits gather in FA
;; as a four-byte binary number.

ln_read:
    ld hl,0
    ld (V_FA),hl
    ld (V_FA+2),hl
    ld hl,TOKBUF
    ld c,0
    ld de,0
    ld a,(hl)
    cp "-"
    jr nz,.plus
    set 0,c
    jr .sign
.plus:
    cp "+"
    jr nz,.body
.sign:
    inc hl
    dec b
    jr z,.no
.body:
    ld a,(hl)
    cp "."
    jr z,.point
    cp "E"
    jr z,.exp
    cp "D"
    jr z,.exp
    cp "F"
    jr z,.exp
    cp "S"
    jr z,.exp
    cp "L"
    jr z,.exp
    sub "0"
    jr c,.no
    cp 10
    jr nc,.no
    set 2,c
    push af
    ld a,d
    cp 9
    jr nc,.drop
    pop af
    push af
    call fl_m10
    pop af
    or d
    jr z,.lead                  ; leading zeros do not count
    inc d
.lead:
    bit 1,c
    jr z,.next
    dec e                       ; a digit after the point
    jr .next
.drop:
    pop af
    bit 1,c
    jr nz,.next
    inc e                       ; a tenth digit or more before the point
.next:
    inc hl
    djnz .body
    bit 2,c
    jr nz,.make
.no:
    scf
    ret
.point:
    bit 1,c
    jr nz,.no
    set 1,c
    jr .next
.exp:
    bit 2,c
    jr z,.no
    push de
    ld de,0                     ; E = the exponent, D = its sign
    inc hl
    dec b
    jr z,.nop
    ld a,(hl)
    cp "-"
    jr nz,.ep
    inc d
    jr .es
.ep:
    cp "+"
    jr nz,.ed
.es:
    inc hl
    dec b
    jr z,.nop
.ed:
    ld a,(hl)
    sub "0"
    jr c,.nop
    cp 10
    jr nc,.nop
    push af
    ld a,e
    cp 12
    jr c,.ten
    ld a,11                     ; far too big anyway
.ten:
    add a,a
    ld e,a
    add a,a
    add a,a
    add a,e
    ld e,a
    pop af
    add a,e
    ld e,a
    inc hl
    djnz .ed
    ld a,d
    or a
    ld a,e
    jr z,.epos
    neg
.epos:
    pop de
    add a,e
    ld e,a
.make:
    ld a,c
    rrca                        ; the sign to bit 7
    push de
    ld hl,V_FA
    FM M_BIN2R
    pop de
    ld a,e
    or a
    jr z,.made
    ld hl,V_FA
    FM M_EXP10
    call f_chk
.made:
    call fl_result
    or a
    ret
.nop:
    pop de
    jr .no

;; fl_m10: FA's four bytes = FA * 10 + A. BC, DE, HL kept
fl_m10:
    push bc
    push de
    push hl
    ld hl,(V_FA)
    ld de,(V_FA+2)
    add hl,hl
    ex de,hl
    adc hl,hl
    ex de,hl                    ; * 2
    push de
    push hl
    add hl,hl
    ex de,hl
    adc hl,hl
    ex de,hl
    add hl,hl
    ex de,hl
    adc hl,hl
    ex de,hl                    ; * 8
    pop bc
    add hl,bc
    ex de,hl
    pop bc
    adc hl,bc
    ex de,hl                    ; * 10
    ld c,a
    ld b,0
    add hl,bc
    jr nc,.nc
    inc de
.nc:
    ld (V_FA),hl
    ld (V_FA+2),de
    pop hl
    pop de
    pop bc
    ret

;; ---------------------------------------------------------------------------
;; PRINTING: HL = a float. Nine significant digits, the trailing zeros
;; dropped; written as 123.45 between 0.001 and 10^7, else as 1.2345e10.
;;
;; |x| times 10^(8-k), rounded, is a nine-digit whole number when k is x's
;; decimal exponent; k is guessed from the binary exponent (times log10 2,
;; 77/256) and put right by trying.

FL_K     equ V_FBUF+9           ; k
FL_LAST  equ V_FBUF+10          ; the last digit that is not 0
FL_TRIES equ V_FBUF+11

ln_print:
    call fl_arg
    ld a,(V_FA+4)
    or a
    jr nz,.nz
    ld hl,fl_s_zero
    jp fl_puts
.nz:
    ld hl,V_FA+3
    bit 7,(hl)
    jr z,.pos
    res 7,(hl)
    ld a,"-"
    call lputc
.pos:
    ld a,(V_FA+4)               ; k = (exponent - 129) * 77 / 256, rounded down
    sub 129
    ld e,a
    ld d,0
    bit 7,a
    jr z,.p
    dec d
.p:
    ld h,d
    ld l,e
    add hl,hl
    add hl,hl
    push hl                     ; 4x
    add hl,hl
    push hl                     ; 8x
    add hl,hl
    add hl,hl
    add hl,hl                   ; 64x
    pop bc
    add hl,bc
    pop bc
    add hl,bc
    add hl,de                   ; 77x
    ld a,4
    ld (FL_TRIES),a
    ld a,h
.scale:
    ld (FL_K),a
    ld hl,FL_TRIES
    dec (hl)
    jr z,.digits                ; (never, but no endless loop)
    ld hl,V_FB
    ld de,V_FA
    FM M_MOVE
    ld a,(FL_K)
    neg
    add a,8
    ld hl,V_FB
    FM M_EXP10
    ld hl,V_FB
    FM M_R2BIN
    ld de,fl_pow10-4            ; 10^9
    call fl_lt32
    jr c,.lt9
    ld a,(FL_K)
    inc a
    jr .scale
.lt9:
    ld de,fl_pow10              ; 10^8
    call fl_lt32
    jr nc,.digits
    ld a,(FL_K)
    dec a
    jr .scale
.digits:
    ld hl,V_FBUF
    ld de,fl_pow10
    ld a,9
.dg:
    push af
    ld (hl),"0"
.sub:
    call fl_sub32
    jr c,.over
    inc (hl)
    jr .sub
.over:
    call fl_add32
    inc hl
    inc de
    inc de
    inc de
    inc de
    pop af
    dec a
    jr nz,.dg
    ld hl,V_FBUF+8              ; the last digit that is not 0
    ld b,8
.last:
    ld a,(hl)
    cp "0"
    jr nz,.lastd
    dec hl
    djnz .last
.lastd:
    ld a,b
    ld (FL_LAST),a
    ld a,(FL_K)                 ; 10^-3 <= x < 10^7: plain
    add a,3
    cp 10
    jr nc,.sci
    ld a,(FL_K)
    bit 7,a
    jr nz,.small
    inc a                       ; k+1 digits, the point, the rest
    ld b,a
    ld hl,V_FBUF
    call fl_digs
    ld a,(FL_K)
    jr .frac
.small:                         ; 0.00ddd
    ld hl,fl_s_zero
    call fl_puts2
    ld a,(FL_K)
    cpl                         ; -k-1 zeros
    or a
    jr z,.z0
    ld b,a
.zl:
    ld a,"0"
    call lputc
    djnz .zl
.z0:
    ld a,(FL_LAST)
    inc a
    ld b,a
    ld hl,V_FBUF
    jp fl_digs
.sci:                           ; d.ddde-k
    ld a,(V_FBUF)
    call lputc
    xor a
    call .frac
    ld a,"e"
    call lputc
    ld a,(FL_K)
    ld l,a
    add a,a
    sbc a,a
    ld h,a
    add hl,hl
    inc hl
    CORE print_fixnum
    ret
;; .frac: A = the index of the last digit printed: the point, then the
;; digits after it up to the last that is not 0, or one 0
.frac:
    push af
    ld a,"."
    call lputc
    pop af
    ld b,a
    ld a,(FL_LAST)
    sub b
    jr z,.f0
    jr c,.f0
    ld e,b
    ld d,0
    ld hl,V_FBUF+1
    add hl,de
    ld b,a
    jr fl_digs
.f0:
    ld a,"0"
    jp lputc

;; fl_digs: B digits from HL
fl_digs:
    ld a,(hl)
    call lputc
    inc hl
    djnz fl_digs
    ret

;; fl_puts: the string at HL, fl_puts2: its first two characters
fl_puts:
    ld a,(hl)
    or a
    ret z
    call lputc
    inc hl
    jr fl_puts
fl_puts2:
    ld a,(hl)
    call lputc
    inc hl
    ld a,(hl)
    jp lputc
fl_s_zero:
    db "0.0",0

;; fl_lt32: DE = four bytes -> C if FB's first four are less. DE, HL kept
fl_lt32:
    push de
    push hl
    ld hl,V_FB
    ld b,4
    or a
.l:
    ld a,(de)
    ld c,a
    ld a,(hl)
    sbc a,c
    inc hl
    inc de
    djnz .l
    pop hl
    pop de
    ret

;; fl_sub32, fl_add32: FB -= or += the four bytes at DE; C if it went
;; below zero. DE, HL kept
fl_sub32:
    push de
    push hl
    ld hl,V_FB
    ld b,4
    or a
.l:
    ld a,(de)
    ld c,a
    ld a,(hl)
    sbc a,c
    ld (hl),a
    inc hl
    inc de
    djnz .l
    pop hl
    pop de
    ret
fl_add32:
    push de
    push hl
    ld hl,V_FB
    ld b,4
    or a
.l:
    ld a,(de)
    ld c,a
    ld a,(hl)
    adc a,c
    ld (hl),a
    inc hl
    inc de
    djnz .l
    pop hl
    pop de
    ret

    dw 1000000000 and #FFFF,1000000000 >> 16
fl_pow10:
    dw 100000000 and #FFFF,100000000 >> 16
    dw 10000000 and #FFFF,10000000 >> 16
    dw 1000000 and #FFFF,1000000 >> 16
    dw 100000 and #FFFF,100000 >> 16
    dw 10000,0,1000,0,100,0,10,0,1,0
