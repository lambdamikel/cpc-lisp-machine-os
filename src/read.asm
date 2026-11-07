;; CPC Lisp -- the reader.
;;
;; Input comes a line at a time from the firmware's EDIT, the same editor
;; BASIC uses, so the copy cursor works. A line's end reads as a newline; an
;; expression may run over several lines, each prompted for when it is
;; needed. Symbols are upcased, as in Common Lisp.

;; getc -> A = the next character. BC, DE, HL kept.
getc:
    ld a,(V_PEEK)
    or a
    jr z,.buf
    push af
    xor a
    ld (V_PEEK),a
    pop af
    ret
.buf:
    push hl
    ld hl,(V_INPTR)
    ld a,h
    or l
    jr z,.refill
    ld a,(hl)
    or a
    jr z,.eol
    inc hl
    ld (V_INPTR),hl
    pop hl
    ret
.eol:
    ld hl,0
    ld (V_INPTR),hl
    ld a,10
    pop hl
    ret
.refill:
    push de
    push bc
    push ix
    ld hl,(V_PROMPT)
    call puts
    ld hl,prompt_cont
    ld (V_PROMPT),hl
    xor a
    ld (LINEBUF),a
    call edit_line
    push af
    call newline
    pop af
    jp nc,input_break
    ld hl,LINEBUF
    ld (V_INPTR),hl
    pop ix
    pop bc
    pop de
    pop hl
    jr getc

;; ungetc: A = a character to read again
ungetc:
    ld (V_PEEK),a
    ret

;; EDIT, the firmware's line editor: HL = buffer holding the text to start
;; from, zero-terminated. Carry set if the line ended with ENTER, clear for
;; ESC.
edit_line:
    ld hl,(V_EDITV)
    push hl
    ld hl,LINEBUF
    ret

;; is_delim: A -> Z if it ends a token
is_delim:
    cp " "+1
    jr c,.yes
    cp "("
    ret z
    cp ")"
    ret z
    cp #22                      ; "
    ret z
    cp "'"
    ret z
    cp ";"
    ret z
    cp "`"
    ret z
    cp ","
    ret
.yes:
    cp a
    ret

;; skipws -> A = the first character that is not blank or in a comment
skipws:
    call getc
    cp " "+1
    jr c,skipws
    cp ";"
    ret nz
.comment:
    call getc
    cp 10
    jr nz,.comment
    jr skipws

;; read -> HL = the next object. CLOSEMARK for ")" and DOTMARK for a lone
;; "." -- read_list is the only caller that expects them.
read:
    call check_stack
    call skipws
    cp "("
    jp z,read_list
    cp ")"
    jr nz,.r1
    ld hl,CLOSEMARK
    ret
.r1:
    cp "'"
    jr nz,.r2
    ld hl,S_QUOTE
    jr read_wrap
.r2:
    cp "`"
    jr nz,.r3
    ld hl,S_QUASIQUOTE
    jr read_wrap
.r3:
    cp ","
    jr nz,.r4
    call getc
    ld hl,S_UNQUOTE_SPLICING
    cp "@"
    jr z,read_wrap
    call ungetc
    ld hl,S_UNQUOTE
    jr read_wrap
.r4:
    cp #22
    jp z,read_string
    cp "#"
    jp z,read_hash
    jp read_token

;; read an object x -> HL = (symbol x), symbol in HL on entry
read_wrap:
    push hl
    call read_obj
    ld de,NIL
    call cons
    ex de,hl
    pop hl
    jp cons

;; read_obj: like read, but ")" and "." are errors
read_obj:
    call read
check_real:
    ld a,h
    cp 4
    ret nz
    ld a,l
    cp CLOSEMARK and #FF
    jr z,.bad
    cp DOTMARK and #FF
    ret nz
.bad:
    ERR m_syntax

read_list:
    ld hl,V_DEPTH
    inc (hl)
    ld hl,NIL
    push hl                     ; head
    push hl                     ; tail
.loop:
    call read
    ld a,h
    cp 4
    jr nz,.elem
    ld a,l
    cp CLOSEMARK and #FF
    jr z,.done
    cp DOTMARK and #FF
    jr z,.dot
.elem:
    ld de,NIL
    call cons
    pop de                      ; tail
    ld a,d
    or e
    jr z,.first
    ex de,hl
    inc hl
    inc hl
    ld (hl),e
    inc hl
    ld (hl),d
    ex de,hl
    push hl
    jr .loop
.first:
    pop de                      ; the empty head
    push hl
    push hl
    jr .loop
.dot:
    pop de
    push de
    ld a,d
    or e
    jr z,.baddot                ; ( . x)
    call read_obj
    pop de                      ; tail
    push de
    ex de,hl
    inc hl
    inc hl
    ld (hl),e
    inc hl
    ld (hl),d
    call read
    ld a,h
    cp CLOSEMARK >> 8
    jr nz,.baddot
    ld a,l
    cp CLOSEMARK and #FF
    jr nz,.baddot
.done:
    ld hl,V_DEPTH
    dec (hl)
    pop hl
    pop hl                      ; head
    ret
.baddot:
    ERR m_syntax

;; read_token: A = its first character, already read
read_token:
    ld hl,TOKBUF
    ld b,0
.loop:
    cp "a"
    jr c,.store
    cp "z"+1
    jr nc,.store
    sub #20
.store:
    ld (hl),a
    inc hl
    inc b
    jr z,.long
    call getc
    call is_delim
    jr nz,.loop
    call ungetc
    ; B = length; a number?
    call parse_int
    ret nc
    ; "." alone
    ld a,b
    dec a
    jr nz,.sym
    ld a,(TOKBUF)
    cp "."
    jr nz,.sym
    ld hl,DOTMARK
    ret
.sym:
    jp intern
.long:
    ERR m_toolong

;; parse_int: TOKBUF holds B characters -> NC and HL = a fixnum, or C if it
;; is not an integer. B kept. Too large is an error, not a symbol.
parse_int:
    ld de,TOKBUF
    ld c,b
    push bc
    ld b,0                      ; sign
    ld a,(de)
    cp "+"
    jr z,.sign
    cp "-"
    jr nz,.start
    inc b
.sign:
    inc de
    dec c
    jr z,.fail
.start:
    ld hl,0
.dig:
    ld a,(de)
    sub "0"
    jr c,.fail
    cp 10
    jr nc,.fail
    push de
    push bc
    ; HL < 1639, or HL*10 overflows the range
    ld de,1639
    or a
    sbc hl,de
    add hl,de
    jr nc,.big
    ld e,l
    ld d,h
    add hl,hl
    add hl,hl
    add hl,de
    add hl,hl
    ld e,a
    ld d,0
    add hl,de
    pop bc
    pop de
    inc de
    dec c
    jr nz,.dig
    ; range: 0..16383, or 16384 if negative
    ld a,b
    or a
    jr nz,.neg
    ld a,h
    cp #40
    jr nc,.big2
    jr .tag
.neg:
    ld de,16385
    or a
    sbc hl,de
    add hl,de
    jr nc,.big2
    ex de,hl
    ld hl,0
    or a
    sbc hl,de
.tag:
    add hl,hl
    inc hl
    pop bc
    or a
    ret
.fail:
    pop bc
    scf
    ret
.big:
    pop bc
    pop de
.big2:
    pop bc
    ERR m_toobig

;; read_string: the opening quote is read
read_string:
    ld hl,TOKBUF
    ld bc,0
.loop:
    call getc
    cp #22
    jr z,.done
    cp #5C                      ; backslash
    jr nz,.store
    call getc
.store:
    ld (hl),a
    inc hl
    inc c
    jr nz,.loop
    ERR m_toolong
.done:
    ld hl,TOKBUF
    jp make_string

;; read_hash: the # is read
read_hash:
    call getc
    cp "'"
    jr nz,.h1
    ld hl,S_FUNCTION
    jp read_wrap
.h1:
    cp #5C                      ; backslash
    jr z,read_char
    cp "|"
    jr z,.comment
    and #DF
    cp "X"
    ld c,16
    jp z,read_radix
    cp "B"
    ld c,2
    jp z,read_radix
    ERR m_syntax
.comment:
    call getc
.c2:
    cp "|"
    jr nz,.comment
    call getc
    cp "#"
    jr nz,.c2
    jp read

;; read_char: #\ is read
read_char:
    ld hl,TOKBUF
    ld b,0
    call getc                   ; the first is taken whatever it is
.loop:
    ld (hl),a
    inc hl
    inc b
    jr z,.bad
    call getc
    call is_delim
    jr nz,.loop
    call ungetc
    ld a,b
    dec a
    jr nz,.named
    ld a,(TOKBUF)
.code:
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    inc hl
    inc hl
    ret
.named:
    ; upcase the token and look it up
    ld hl,TOKBUF
    ld c,b
.up:
    ld a,(hl)
    cp "a"
    jr c,.u1
    cp "z"+1
    jr nc,.u1
    sub #20
    ld (hl),a
.u1:
    inc hl
    dec c
    jr nz,.up
    ld hl,charnames
.find:
    ld a,(hl)
    or a
    jr z,.bad
    cp b
    jr nz,.skip
    push hl
    push bc
    inc hl
    ld de,TOKBUF
.cmp:
    ld a,(de)
    cp (hl)
    jr nz,.ne
    inc hl
    inc de
    djnz .cmp
    ld a,(hl)                   ; the code follows the name
    pop bc
    pop de
    jr .code
.ne:
    pop bc
    pop hl
.skip:
    ld a,(hl)
    inc a
    inc a
    add a,l
    ld l,a
    jr nc,.find
    inc h
    jr .find
.bad:
    ERR m_badchar

;; read_radix: C = 16 or 2, after #x or #b. Reads [-]digits.
read_radix:
    ld hl,0
    ld b,0                      ; sign
    call getc
    cp "-"
    jr nz,.first
    inc b
    call getc
.first:
    call is_delim
    jr z,.bad
.dig:
    and #DF                     ; upcase a letter (and digits to &10-&19)
    sub #10
    jr c,.bad
    cp 10
    jr c,.ok
    sub #27                     ; "A" (&31 here) -> 10
    cp 10
    jr c,.bad
.ok:
    cp c
    jr nc,.bad
    ; HL = HL*C + A, up to &7FFF before tagging
    push bc
    ld e,a
    ld d,0
    push de
    ld b,c
    ld e,l
    ld d,h
    ld hl,0
.mul:
    add hl,de
    jr c,.big
    djnz .mul
    pop de
    add hl,de
    jr c,.big1
    pop bc
    bit 7,h
    jr nz,.big2
    call getc
    call is_delim
    jr nz,.dig
    call ungetc
    ; must fit 15 bits signed: 0..&3FFF, or negated
    ld a,h
    cp #40
    jr c,.fits
    jr .big2
.fits:
    ld a,b
    or a
    jr z,.pos
    ex de,hl
    ld hl,0
    or a
    sbc hl,de
.pos:
    add hl,hl
    inc hl
    ret
.big:
    pop de
.big1:
    pop bc
.big2:
    ERR m_toobig
.bad:
    ERR m_syntax

charnames:
    db 5,"SPACE",32
    db 7,"NEWLINE",10
    db 3,"TAB",9
    db 6,"RETURN",13
    db 8,"LINEFEED",10
    db 4,"PAGE",12
    db 9,"BACKSPACE",8
    db 6,"ESCAPE",27
    db 6,"RUBOUT",127
    db 3,"NUL",0
    db 0

;; ESC in EDIT: drop the line and go back to the REPL
input_break:
    call newline
    jp toplevel
