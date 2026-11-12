;; CPC Lisp -- the reader.
;;
;; Input comes from V_INSRC: 0 the keyboard, a line at a time from the
;; library's line editor (V_LIBEDIT) or, without the library, the
;; firmware's EDIT; 1 Lisp text in a library ROM (autoload, boot forms);
;; 2 a string (the function editor, string streams); 3 the file open for
;; input. A line's end reads as a newline; an expression may run over
;; several lines, each prompted for when it is needed. Symbols are
;; upcased, as in Common Lisp.

;; getc -> A = the next character, 0 at the end of library text (and
;; again after that). BC, DE, HL kept.
getc:
    ld a,(V_PEEK)
    or a
    jr z,.src
    push af
    xor a
    ld (V_PEEK),a
    pop af
    ret
.src:
    ld a,(V_INSRC)
    or a
    jr z,.buf
    cp 2
    jr z,.str
    cp 3
    jr z,.file
    push hl
    ld hl,(V_SRCPTR)
    ld a,(V_SRCROM)
    call ROMPEEK
    or a
    jr z,.end
    inc hl
    ld (V_SRCPTR),hl
.end:
    pop hl
    ret
.str:                           ; from the string, by index: it can move
    push hl
    push de
    push bc
    ld hl,(V_SRCOBJ)
    call str_data               ; HL = characters, BC = how many
    ld de,(V_SRCPTR)
    ex de,hl
    or a
    sbc hl,bc
    jr nc,.strend
    add hl,bc
    inc hl
    ld (V_SRCPTR),hl
    dec hl
    add hl,de
    ld a,(hl)
    pop bc
    pop de
    pop hl
    or a
    ret nz
    ld a," "                    ; a NUL in a string reads as a blank
    ret
.strend:
    xor a
    pop bc
    pop de
    pop hl
    ret
.file:                          ; the file open for input
    ld a,(V_FILES)
    bit 2,a
    jr nz,.fend                 ; at its end already: it stays there (the
    push hl                     ;   disc ROM would go on past a CTRL-Z)
    push de
    push bc
    call FILE_GETC
    pop bc
    pop de
    pop hl
    jr c,.fchar
    jr z,.fesc                  ; ESC pressed
    jr .fend                    ; the end of the file
.fchar:
    push hl                     ; counted, for file-position (V_FPOS)
    ld hl,(V_FPOS)
    inc hl
    ld (V_FPOS),hl
    pop hl
    cp #1A                      ; CTRL-Z ends an ASCII file
    jr z,.fend
    or a
    ret nz
    ld a," "
    ret
.fend:
    ld a,(V_FILES)
    or 4
    ld (V_FILES),a
    xor a
    ret
.fesc:
    ERR m_break
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
    jp getc

;; ungetc: A = a character to read again
ungetc:
    ld (V_PEEK),a
    ret

;; edit_line: a line into LINEBUF, zero-terminated. Carry set if it ended
;; with ENTER, clear for ESC. The library's editor if there is one, else
;; EDIT, the firmware's (BASIC's).
edit_line:
    call EDHOOK
    ld hl,(V_LIBEDIT)
    ld a,h
    or l
    jr z,.firm
    push hl
    pop ix
    ld a,(V_EDROM)
    jp ROMCALL
.firm:
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

;; skipws -> A = the first character that is not blank or in a comment,
;; 0 at the end
skipws:
    call getc
    or a
    ret z
    cp " "+1
    jr c,skipws
    cp ";"
    ret nz
.comment:
    call getc
    or a
    ret z
    cp 13                       ; a line ends at CR (LDOS's text files)
    jr z,skipws
    cp 10                       ;   or LF
    jr nz,.comment
    jr skipws

;; read -> HL = the next object. CLOSEMARK for ")" and DOTMARK for a lone
;; "." -- read_list is the only caller that expects them.
read:
    call check_stack
    call skipws
    or a
    jr nz,.r0
    ld hl,EOFMARK
    ret
.r0:
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

;; read_obj: like read, but ")", "." and the end are errors
read_obj:
    call read
check_real:
    ld a,h
    cp 4
    ret nz
    bit 0,l
    ret nz                      ; a fixnum, 512-639 (&0401-&04FF)
    ld a,l
    cp EOFMARK and #FF
    jr z,.eof
    ERR m_syntax
.eof:
    ERR m_eof

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
    cp EOFMARK and #FF
    jr z,.eof
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
.eof:
    ERR m_eof

;; read_token: A = its first character, already read. Between bars, |a b|,
;; characters are taken as they are, blanks and lower case and all; \ takes
;; the next one so. Such a token is a symbol, never a number.
read_token:
    ld hl,TOKBUF
    ld bc,0                     ; B = length; C bit 0: in bars, bit 1: escaped
.loop:
    cp "|"
    jr z,.bar
    cp #5C
    jr z,.esc
    bit 0,c
    jr nz,.store
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
.next:
    call getc
    bit 0,c
    jr z,.out
    or a
    jr nz,.loop                 ; in bars: only the end of the text ends it
    ERR m_eof
.bar:
    ld a,c
    xor 1
    or 2
    ld c,a
    jr .next
.esc:
    set 1,c
    call getc
    jr .store
.out:
    call is_delim
    jr nz,.loop
    call ungetc
    bit 1,c
    jr nz,.sym                  ; escaped: a symbol
    ; B = length; a number?
    call parse_int
    ret nc
    push bc
    call lnum_read              ; a float?
    pop bc
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
    call lnum_read              ; too big: the library makes it a float
    ret nc
    ERR m_toobig

;; read_string: the opening quote is read
read_string:
    ld hl,TOKBUF
    ld bc,0
.loop:
    call getc
    or a
    jr z,.eof
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
.eof:
    ERR m_eof
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
    cp "("
    jr nz,.h2
    call read_list              ; #( ... ): a vector
    jp list_to_vector
.h2:
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
    or a
    jr z,.eof
.c2:
    cp "|"
    jr nz,.comment
    call getc
    cp "#"
    jr nz,.c2
    jp read
.eof:
    ERR m_eof

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
    call getc
    call is_delim
    jr nz,.dig
    call ungetc
    ; a fixnum if it fits (0..&3FFF, or negated), else up to &FFFF a float,
    ; as a decimal that big is (through the library)
    ld a,h
    cp #40
    jr c,.fits
    ld a,b
    or a
    jr nz,.big2
    ld a,12
    call lnum
    ret nc
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
