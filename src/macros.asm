;; CPC Lisp -- assembler macros.

;; HL = (HL): car of a cons known not to be NIL, or any word through a pointer
macro LDHLI
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
mend

;; HL = cdr of a cons known not to be NIL
macro CDRHL
    inc hl
    inc hl
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
mend

;; DE = (HL), HL advanced by 2
macro LDDEI
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
mend

;; Variadic subr arguments: HL points at the next argument, and they run
;; downwards in memory. DE = argument, HL moved to the one after.
macro NEXTARG
    ld e,(hl)
    inc hl
    ld d,(hl)
    dec hl
    dec hl
    dec hl
mend

;; Z if HL is NIL
macro ISNIL
    ld a,h
    or l
mend

;; Error with a message and no object
macro ERR msg
    ld hl,{msg}
    ld de,UNBOUND
    jp error
mend
