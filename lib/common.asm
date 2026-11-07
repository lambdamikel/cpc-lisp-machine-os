;; CPC Lisp -- what every library ROM has: the dispatcher and helpers.
;;
;; Included by each part's main file (lib/lib.asm, lib/lib2.asm) after its
;; header; each ROM gets its own copy, since a library ROM cannot call
;; another's code (only the core's, through CORE).

macro CORE routine
    ld ix,{routine}
    call CORECALL
mend

;; SCORE: CORE, keeping IX (for routines that keep a frame in it)
macro SCORE routine
    push ix
    ld ix,{routine}
    call CORECALL
    pop ix
mend

lib_init:
    scf
    ret

;; lib_dispatch: called through the trampoline for every library function,
;; with HL = &arg 0, B = count and V_LIBFN = the function object. Checks
;; the count, puts fixed arguments in registers, jumps to the code.
lib_dispatch:
    push hl
    ld hl,(V_LIBFN)
    LDHLI                       ; its entry, the part in the top bits
    set 7,h
    set 6,h                     ; -> in this ROM
    push hl
    pop ix
    pop hl
    ld a,b
    cp (ix+LE_MIN)
    jr c,.args
    ld a,(ix+LE_MAX)
    cp b
    jr c,.args
    ld e,(ix+LE_ADDR)
    ld d,(ix+LE_ADDR+1)
    push de                     ; ret goes to the code
    ld a,(ix+LE_MIN)
    cp (ix+LE_MAX)
    ret nz                      ; variadic: HL and B as they are
    cp 4
    ret nc
    or a
    ret z
    dec a
    jr z,.one
    dec a
    jr z,.two
    push hl
    dec hl
    dec hl
    dec hl
    dec hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    pop hl
.two:
    push hl
    dec hl
    dec hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    pop hl
.one:
    LDHLI
    ret
.args:
    ld de,(V_LIBFN)
    ld hl,m_nargs
    CORE error

;; ---------------------------------------------------------------------------
;; helpers

;; lfix_hl, lfix_de: error unless a fixnum. All kept.
lfix_hl:
    bit 0,l
    ret nz
    ex de,hl
lfix_de:
    bit 0,e
    ret nz
    ld hl,m_notnum
    CORE error

;; lint_hl: a number in HL -> the plain number in HL, a float rounded
;; (by the number routines, wherever they are). lint_de likewise. All else
;; kept.
lint_hl:
    bit 0,l
    jr z,.float
    sra h
    rr l
    ret
.float:
    push ix
    push bc                     ; (through the core and the number ROM:
    CORE num_int                ;   callers keep their argument count in B)
    pop bc
    pop ix
    ret
lint_de:
    ex de,hl
    call lint_hl
    ex de,hl
    ret

;; a plain number in HL -> a fixnum, assumed in range
ltag:
    add hl,hl
    inc hl
    ret

;; A -> a character object in HL
lchar:
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    inc hl
    inc hl
    ret

lnil:
    ld hl,NIL
    ret
lt:
    ld hl,S_T
    ret

lcall_ix:
    jp (ix)

;; lstring: HL = a string -> HL = its characters, BC = how many. An error
;; for anything else.
lstring:
    push hl
    CORE is_string
    pop hl
    jr nz,.bad
    LDHLI
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    ret
.bad:
    ex de,hl
    ld hl,m_notstr
    CORE error

;; ---------------------------------------------------------------------------
;; errors and printing

;; lib_error: HL = a message in this ROM, DE = an object or UNBOUND
lib_error:
    push de
    ld de,TOKBUF
.c:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    or a
    jr nz,.c
    pop de
    ld hl,TOKBUF
    CORE error

;; lputs: HL = text in this ROM, zero-terminated, through putc
lputs:
    ld a,(hl)
    or a
    ret z
    call lputc
    inc hl
    jr lputs

;; lputc: A through the core's putc. All registers kept.
lputc:
    push ix
    push de
    ld e,a
    CORE putc_e
    pop de
    pop ix
    ret

;; lstr_result: TOKBUF holds C characters -> a new string
lstr_result:
    ld b,0
    ld hl,TOKBUF
    CORE make_string
    ret

str_long:
    ld hl,m_toolong
    ld de,UNBOUND
    CORE error


;; to_string_ix: IX = a routine of this ROM, which prints -> HL = what it
;; printed, as a string (255 characters at most). HL goes to it.
to_string_ix:
    ld de,(V_OUTPTR)
    push de
    ld de,(V_OUTEND)
    push de
    ld de,(V_OUTCNT)
    push de
    ld a,(V_OUTCOL)
    ld d,a
    ld a,(V_OUTMODE)
    ld e,a
    push de
    ld a,1
    ld (V_OUTMODE),a
    ld de,TOKBUF
    ld (V_OUTPTR),de
    ld de,TOKBUF+255
    ld (V_OUTEND),de
    ld de,0
    ld (V_OUTCNT),de
    call lcall_ix
    ld hl,(V_OUTCNT)
    ld bc,(V_OUTPTR)
    pop de
    ld a,e
    ld (V_OUTMODE),a
    ld a,d
    ld (V_OUTCOL),a
    pop de
    ld (V_OUTCNT),de
    pop de
    ld (V_OUTEND),de
    pop de
    ld (V_OUTPTR),de
    ld de,256
    or a
    sbc hl,de
    jp nc,str_long
    ld a,c
    sub TOKBUF and #FF
    ld c,a
    jp lstr_result
