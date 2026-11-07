;; CPC Lisp -- the pretty printer (library ROM).
;;
;; pp prints an object so that it fits the screen width where it can: what
;; fits on the rest of the line is printed as it is; a list that does not
;; is broken up the way Lisp is written --
;;
;;   (defun name (args)          forms with a body (the table in editor.asm,
;;     body...)                  ed_bodyform): their first arguments on the
;;                               first line, the body two in
;;   (f first                    a call: the rest under the first argument,
;;      second)                  or one in if that is too far right
;;   ((a b)                      a list that starts with a list: all under
;;    (c d))                     its first element
;;
;; It prints through the core's putc, so it goes wherever V_OUTMODE sends
;; it -- the function editor's buffer, for one -- and measures with
;; V_OUTMODE 2, which only counts.

PP_W      equ LIBSCR+10         ; the width to fit

;; pp_setw: fit to the window's width
pp_setw:
    call TXT_GET_WINDOW
    ld a,d
    sub h
    inc a
    ld (PP_W),a
    ret

;; pp_newline: C = the column to continue in
pp_newline:
    ld a,13
    call lputc
    ld a,10
    call lputc
    ld a,c
    or a
    ret z
    ld b,a
.sp:
    ld a," "
    call lputc
    djnz .sp
    ret

;; pp_fits: HL = an object -> Z if it prints on what is left of this line.
;; HL kept.
pp_fits:
    push hl
    ld de,(V_OUTCNT)
    push de
    ld a,(V_OUTCOL)
    push af
    ld a,(V_OUTMODE)
    push af
    ld a,2
    ld (V_OUTMODE),a
    ld de,0
    ld (V_OUTCNT),de
    CORE prin1
    ld de,(V_OUTCNT)
    pop af
    ld (V_OUTMODE),a
    pop af
    ld (V_OUTCOL),a
    pop hl
    ld (V_OUTCNT),hl
    ld b,a
    ld a,(PP_W)
    sub b
    dec a                       ; room for a ) after it
    jr nc,.r
    xor a
.r:
    ld l,a
    ld h,0
    or a
    sbc hl,de                   ; room - length
    pop hl
    jr c,.no
    cp a
    ret
.no:
    or 1
    ret

;; pp: HL = an object
pp:
    CORE check_stack
    call pp_fits
    jr z,.flat
    ld a,l
    and 3
    jr nz,.flat
    ld a,h
    or l
    jr nz,.list
.flat:
    CORE prin1
    ret
.list:
    call pp_prefix
    jr z,pp                     ; 'x: the prefix is out, now x
    ld a,(V_OUTCOL)
    push af                     ; the column of the "("
    ld a,"("
    call lputc
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI                       ; DE = the first element, HL = the rest
    push hl
    ex de,hl
    ld a,l
    and 3
    jr nz,.atomop
    ld a,h
    or l
    jr z,.atomop
    call pp                     ; a list first: everything under it
    pop hl
    pop af
    push af
    inc a
    ld c,a
    jr .lines
.atomop:
    push hl
    CORE prin1
    pop hl
    call pp_bodycount           ; A = arguments before the body, 255 if no body
    pop hl
    cp 255
    jr z,.call
    ld b,a
.hdr:
    ld a,b
    or a
    jr z,.body
    ld a,l
    and 3
    jr nz,.tail
    ld a,h
    or l
    jr z,.tail
    push bc
    push hl
    ld a," "
    call lputc
    LDHLI
    call pp
    pop hl
    CDRHL
    pop bc
    dec b
    jr .hdr
.body:
    pop af
    push af
    add a,2
    ld c,a
    jr .lines
.call:
    ld a,l
    and 3
    jr nz,.tail
    ld a,h
    or l
    jr z,.tail
    ld a,(PP_W)                 ; past half way: all of them one in
    srl a
    ld c,a
    ld a,(V_OUTCOL)
    cp c
    jr c,.first
    pop af
    push af
    inc a
    ld c,a
    jr .lines
.first:
    push hl
    ld a," "
    call lputc
    ld a,(V_OUTCOL)
    ld c,a
    pop hl
    push bc
    push hl
    LDHLI
    call pp
    pop hl
    CDRHL
    pop bc
;; the rest of the elements, each on its own line at column C
.lines:
    ld a,l
    and 3
    jr nz,.tail
    ld a,h
    or l
    jr z,.tail
    push bc
    push hl
    call pp_newline
    pop hl
    push hl
    LDHLI
    call pp
    pop hl
    CDRHL
    pop bc
    jr .lines
.tail:
    ld a,h
    or l
    jr z,.close
    push hl
    ld a," "
    call lputc
    ld a,"."
    call lputc
    ld a," "
    call lputc
    pop hl
    CORE prin1
.close:
    ld a,")"
    call lputc
    pop af
    ret

;; pp_prefix: HL = a list. (quote x), (function x) and the backquote forms
;; -> Z, the prefix printed, HL = x. Otherwise NZ, HL kept.
pp_prefix:
    push hl
    CDRHL
    ld a,l
    and 3
    jr nz,.no
    ld a,h
    or l
    jr z,.no
    push hl
    CDRHL
    ld a,h
    or l
    pop hl
    jr nz,.no
    LDHLI
    ex (sp),hl                  ; x on the stack
    push hl
    LDHLI                       ; the symbol in front
    ex de,hl
    ld hl,pp_prefixes
.f:
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    ld a,b
    or c
    jr z,.none
    ld a,c
    cp e
    jr nz,.nx
    ld a,b
    cp d
    jr z,.found
.nx:
    ld a,(hl)
    inc hl
    or a
    jr nz,.nx
    jr .f
.found:
    ld a,(hl)
    or a
    jr z,.done
    call lputc
    inc hl
    jr .found
.done:
    pop hl                      ; the list
    pop hl                      ; x
    cp a
    ret
.none:
    pop hl
    ex (sp),hl                  ; the list back
    pop hl
    push hl
.no:
    pop hl
    or 1
    ret

pp_prefixes:
    dw S_QUOTE
    db "'",0
    dw S_FUNCTION
    db "#'",0
    dw S_QUASIQUOTE
    db "`",0
    dw S_UNQUOTE
    db ",",0
    dw S_UNQUOTE_SPLICING
    db ",@",0
    dw 0

;; pp_bodycount: HL = the first element of a form -> A = how many of its
;; arguments stay on the first line, or 255 if it is not a form with a body
pp_bodycount:
    push hl
    CORE is_symbol
    pop hl
    ld a,255
    ret nz
    CORE sym_to_tokbuf
    ld a,b
    or a
    ld a,255
    ret nz
    ld de,TOKBUF
    call ed_bodyform
    ret z
    ld a,255
    ret

;; (pprint object): on a new line, broken up to fit the screen
;@ PPRINT 1 1 lf_pprint
lf_pprint:
    push hl
    call pp_setw
    CORE newline
    pop hl
    push hl
    call pp
    pop hl
    jp lnil

;; ---------------------------------------------------------------------------
;; printing into strings, reading from them

;; (prin1-to-string object), (princ-to-string object): up to 255 characters
;@ PRIN1-TO-STRING 1 1 lf_prin1_to_string
lf_prin1_to_string:
    ld ix,l_prin1
    jp to_string_ix
;@ PRINC-TO-STRING 1 1 lf_princ_to_string
lf_princ_to_string:
    ld ix,l_princ
    jp to_string_ix
l_prin1:
    ld ix,prin1
    jp CORECALL
l_princ:
    ld ix,princ
    jp CORECALL

;; (read-from-string string): the first object in it
;@ READ-FROM-STRING 1 1 lf_read_from_string
lf_read_from_string:
    push hl
    call lstring                ; an error if it is not a string
    pop hl
;; read_from: HL = a string -> HL = the first object in it. The reader's
;; own state is put back afterwards.
read_from:
    ld de,(V_SRCOBJ)
    push de
    ld de,(V_SRCPTR)
    push de
    ld a,(V_INSRC)
    ld d,a
    ld a,(V_PEEK)
    ld e,a
    push de
    ld (V_SRCOBJ),hl
    ld hl,0
    ld (V_SRCPTR),hl
    ld a,2
    ld (V_INSRC),a
    xor a
    ld (V_PEEK),a
    CORE read_obj
    pop de
    ld a,d
    ld (V_INSRC),a
    ld a,e
    ld (V_PEEK),a
    pop de
    ld (V_SRCPTR),de
    pop de
    ld (V_SRCOBJ),de
    ret
