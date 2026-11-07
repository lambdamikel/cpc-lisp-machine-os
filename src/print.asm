;; CPC Lisp -- the printer.

putc equ TXT_OUTPUT             ; preserves all registers

puts:
    ld a,(hl)
    or a
    ret z
    call putc
    inc hl
    jr puts

newline:
    ld a,13
    call putc
    ld a,10
    jp putc

;; fresh_line: a newline unless the cursor is already in column 1
fresh_line:
    push hl
    call TXT_GET_CURSOR         ; H = column, L = row
    ld a,h
    pop hl
    dec a
    ret z
    jr newline

;; prin1: HL = object, printed so that read gives it back. princ: without
;; quotes and escapes. Both keep HL.
prin1:
    ld a,1
    jr print_with
princ:
    xor a
print_with:
    ld (V_ESC),a
    push hl
    call print_obj
    pop hl
    ret

print_obj:
    call check_stack
    bit 0,l
    jp nz,print_fixnum
    ld a,h
    or l
    jr nz,.nn
    ld hl,NILSLOT
    jp print_symbol
.nn:
    bit 1,l
    jp z,print_list
    ld a,h
    cp 4
    jp c,print_char
    jp z,print_marker
    cp SYM_HI >> 8
    jp c,print_symbol
    cp #C0
    jp nc,print_rom
    push hl
    dec hl
    dec hl
    ld a,(hl)
    pop hl
    cp HDR_STRING and #FF
    jp z,print_string
    ld de,str_function
    cp HDR_CLOSURE and #FF
    jr z,.unread
    ld de,str_macro
    cp HDR_MACRO and #FF
    jr z,.unread
    cp HDR_LSUBR and #FF
    jp z,print_lsubr
    ld de,str_autoload
    cp HDR_AUTOLOAD and #FF
    jr z,.unread
    ld de,str_unknown
.unread:
    ex de,hl
    jp puts

print_symbol:
    call str_data
print_chars:
    ld a,b
    or c
    ret z
    ld a,(hl)
    call putc
    inc hl
    dec bc
    jr print_chars

print_string:
    call str_data
    ld a,(V_ESC)
    or a
    jr z,print_chars
    ld a,#22
    call putc
.l:
    ld a,b
    or c
    jr z,.end
    ld a,(hl)
    cp #22
    jr z,.esc
    cp #5C
    jr nz,.out
.esc:
    push af
    ld a,#5C
    call putc
    pop af
.out:
    call putc
    inc hl
    dec bc
    jr .l
.end:
    ld a,#22
    jp putc

print_char:
    srl h
    rr l
    srl h
    rr l                        ; L = the code
    ld a,(V_ESC)
    or a
    ld a,l
    jp z,putc
    push hl
    ld hl,str_hashbs
    call puts
    pop hl
    ld a,l
    cp " "+1
    jr c,.named
    cp 127
    jp nz,putc
.named:
    ld c,a
    ld hl,charnames
.find:
    ld a,(hl)
    or a
    ld a,c
    jp z,putc                   ; no name: the character itself
    ld a,(hl)
    inc a
    add a,l
    ld e,a
    ld d,h
    jr nc,.nc
    inc d
.nc:
    ld a,(de)                   ; its code
    cp c
    jr z,.found
    inc de
    ex de,hl
    jr .find
.found:
    ld b,(hl)                   ; length
    inc hl
    ld a,(hl)
    call putc                   ; Space, Newline...
    dec b
    ret z
.rest:
    inc hl
    ld a,(hl)
    or #20
    call putc
    djnz .rest
    ret

print_marker:
    ld de,UNBOUND
    or a
    sbc hl,de
    ld hl,str_unbound
    jp z,puts
    ld hl,str_marker
    jp puts

print_rom:
    push hl
    dec hl
    dec hl
    ld a,(hl)
    ld hl,str_subr
    cp HDR_SUBR and #FF
    jr z,.p
    ld hl,str_special
.p:
    call puts
    pop hl
    ld de,6
    add hl,de
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    call print_chars
    ld a,">"
    jp putc

print_list:
    push hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = car
    inc hl
    LDHLI                       ; HL = cdr
    ; (quote x) and friends print as 'x
    ld a,l
    and 3
    jr nz,.plain
    ld a,h
    or l
    jr z,.plain
    push hl
    CDRHL
    ld a,h
    or l
    pop hl
    jr nz,.plain
    push hl
    ld hl,abbrevs
.ab:
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    ld a,b
    or c
    jr z,.noab
    ld a,c
    cp e
    jr nz,.abn
    ld a,b
    cp d
    jr nz,.abn
    LDHLI
    call puts
    pop hl
    LDHLI                       ; the x
    pop de
    jp print_obj
.abn:
    inc hl
    inc hl
    jr .ab
.noab:
    pop hl
.plain:
    pop hl
    ld a,"("
    call putc
.loop:
    push hl
    LDHLI
    call print_obj
    pop hl
    CDRHL
    ld a,h
    or l
    jr z,.close
    ld a,l
    and 3
    jr nz,.dotted
    call poll_break
    ld a," "
    call putc
    jr .loop
.dotted:
    push hl
    ld hl,str_dot
    call puts
    pop hl
    call print_obj
.close:
    ld a,")"
    jp putc

abbrevs:
    dw S_QUOTE,str_quote
    dw S_FUNCTION,str_hashq
    dw S_QUASIQUOTE,str_bq
    dw S_UNQUOTE,str_comma
    dw S_UNQUOTE_SPLICING,str_commaat
    dw 0

;; print_fixnum: HL = a fixnum
print_fixnum:
    sra h
    rr l
    bit 7,h
    jr z,print_uint
    ld a,"-"
    call putc
    ex de,hl
    ld hl,0
    or a
    sbc hl,de
;; print_uint: HL = 0..65535 in decimal
print_uint:
    ld b,0
    ld de,-10000
    call .d
    ld de,-1000
    call .d
    ld de,-100
    call .d
    ld de,-10
    call .d
    ld a,l
    add a,"0"
    jp putc
.d:
    ld a,"0"-1
.l:
    inc a
    add hl,de
    jr c,.l
    sbc hl,de
    cp "0"
    jr nz,.out
    inc b
    dec b
    ret z
.out:
    ld b,1
    jp putc

str_function:  db "#<FUNCTION>",0
str_macro:     db "#<MACRO>",0
str_autoload:  db "#<AUTOLOAD>",0
str_unknown:   db "#<?>",0
str_unbound:   db "#<UNBOUND>",0
str_marker:    db "#<MARKER>",0
str_subr:      db "#<SUBR ",0
str_special:   db "#<SPECIAL ",0
str_hashbs:    db "#",#5C,0
str_dot:       db " . ",0
str_quote:     db "'",0
str_hashq:     db "#'",0
str_bq:        db "`",0
str_comma:     db ",",0
str_commaat:   db ",@",0
