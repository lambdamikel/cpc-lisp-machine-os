;; CPC Lisp -- streams (library ROM, part 0): the printing and reading
;; functions, with CL's stream argument. NIL or T is the screen and the
;; keyboard; anything else is a file stream (open, close, with-open-file
;; are Lisp, in lisp.lsp), which is the file the firmware has open for
;; output, or the one it has open for input: there is one of each.
;;
;; While a function prints to a file, V_OUTMODE is 3 and V_OUTCOL is the
;; file's column; while it reads one, V_INSRC is 3 and V_PEEK the file's
;; pushed-back character. In between, the file's are kept in SO_FCOL and
;; SO_FPEEK.

so_m_closed:  db "the stream is not open",0
so_m_eof:     db "end of file",0

;; so_from: B = 0, or more and HL = &the stream argument; DE kept ->
;; output goes to the stream. The state to put back is left on the stack
;; under the caller's return: the caller ends with jp so_back.
so_from:
    pop ix
    push de
    ld de,NIL
    inc b
    dec b
    jr z,.d
    NEXTARG
.d:
    ld bc,0                     ; nothing to put back
    call so_file
    jr z,.go
    ld a,(V_FILES)
    and 2
    jr z,so_closed
    ld a,(V_OUTMODE)
    or #80
    ld c,a
    ld a,(V_OUTCOL)
    ld b,a
    ld a,3
    ld (V_OUTMODE),a
    ld a,(SO_FCOL)
    ld (V_OUTCOL),a
.go:
    pop de
    push bc
    jp (ix)

;; so_back: the output as it was before so_from. HL kept
so_back:
    pop bc
    bit 7,c
    ret z
    ld a,(V_OUTCOL)
    ld (SO_FCOL),a
    ld a,c
    and #7F
    ld (V_OUTMODE),a
    ld a,b
    ld (V_OUTCOL),a
    ret

so_closed:
    ld hl,so_m_closed
    jp lib_error

;; so_file: DE = a stream designator -> Z for the screen and keyboard (NIL
;; or T), NZ for a file stream. DE, BC kept
so_file:
    ld a,d
    or e
    ret z
    push hl
    ld hl,S_T
    or a
    sbc hl,de
    pop hl
    ret

;; sd_nth: HL = &argument 0, B = how many, A = an index, DE = a default ->
;; DE = that argument, or the default if there are not so many. BC, HL kept
sd_nth:
    cp b
    ret nc
    push hl
    push bc
    add a,a
    ld c,a
    ld b,0
    or a
    sbc hl,bc
    ld e,(hl)
    inc hl
    ld d,(hl)
    pop bc
    pop hl
    ret

;; si_from: HL = &the arguments (stream eof-error-p eof-value), B = how
;; many -> input comes from the stream. Left on the stack under the
;; caller's return: eof-value, eof-error-p, the state to put back; the
;; caller ends with jp si_back, or jp si_eof at the end of the file.
si_from:
    pop ix
    ld a,2
    ld de,NIL
    call sd_nth
    push de                     ; eof-value
    ld a,1
    ld de,S_T
    call sd_nth
    push de                     ; eof-error-p
    xor a
    ld de,NIL
    call sd_nth                 ; DE = the stream
    ld bc,0
    call so_file
    jr nz,.file
    ld a,(V_INSRC)              ; the keyboard: as it is, unless a file is
    or a                        ;   being loaded (or library text read)
    jr z,.go
    xor a
    ld e,a                      ; E = the source, D = its pushed-back char
    ld d,a
    jr .switch
.file:
    ld a,(V_FILES)
    rra
    jr nc,so_closed
    ld e,3
    ld a,(SO_FPEEK)
    ld d,a
.switch:
    ld a,(V_INSRC)
    or #80
    ld c,a
    ld a,(V_PEEK)
    ld b,a
    ld a,e
    ld (V_INSRC),a
    ld a,d
    ld (V_PEEK),a
.go:
    push bc
    jp (ix)

;; si_back: the input as it was before si_from. HL kept
si_back:
    pop bc
    pop de
    pop de
    bit 7,c
    ret z
    ld a,(V_INSRC)
    cp 3
    jr nz,.put
    ld a,(V_PEEK)               ; the file's, for next time
    ld (SO_FPEEK),a
.put:
    ld a,c
    and #7F
    ld (V_INSRC),a
    ld a,b
    ld (V_PEEK),a
    ret

;; si_eof: the end of the file: eof-value, or an error if eof-error-p
si_eof:
    ld hl,2
    add hl,sp
    ld a,(hl)
    inc hl
    or (hl)
    jr nz,.err
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl
    jr si_back
.err:
    ld hl,so_m_eof
    ld de,UNBOUND
    jp lib_error

;; si_infile: Z if the input is the file now
si_infile:
    ld a,(V_INSRC)
    cp 3
    ret

;; si_getc: the input file's next character, a CR LF as one LF -> A, 0 at
;; the end
si_getc:
    CORE getc
    cp 13
    jr z,si_getc
    ret

;; ---------------------------------------------------------------------------
;; PRINTING

;; (print x [stream]): a new line, x readably, a blank
;@ PRINT 1 2 lf_print
lf_print:
    NEXTARG
    dec b
    call so_from
    ex de,hl
    CORE newline
    CORE prin1
    ld a," "
    call lputc
    jp so_back

;; (prin1 x [stream]), (princ x [stream]), (write-string s [stream])
;@ PRIN1 1 2 lf_prin1
lf_prin1:
    NEXTARG
    dec b
    call so_from
    ex de,hl
    CORE prin1
    jp so_back
;@ PRINC 1 2 lf_princ
;@ WRITE-STRING 1 2 lf_princ
lf_princ:
    NEXTARG
    dec b
    call so_from
    ex de,hl
    CORE princ
    jp so_back

;; (write-line s [stream]): s and a new line
;@ WRITE-LINE 1 2 lf_write_line
lf_write_line:
    NEXTARG
    dec b
    call so_from
    ex de,hl
    CORE princ
    CORE newline
    jp so_back

;; (write-char c [stream])
;@ WRITE-CHAR 1 2 lf_write_char
lf_write_char:
    NEXTARG
    dec b
    call so_from
    ex de,hl
    push hl
    CORE check_char
    pop hl
    push hl
    srl h
    rr l
    srl h
    rr l
    ld a,l
    call lputc
    pop hl
    jp so_back

;; (terpri [stream]): a new line
;@ TERPRI 0 1 lf_terpri
lf_terpri:
    call so_from
    CORE newline
    ld hl,NIL
    jp so_back

;; (fresh-line [stream]): a new line unless at the start of one -> T if it
;; was needed
;@ FRESH-LINE 0 1 lf_fresh_line
lf_fresh_line:
    call so_from
    ld a,(V_OUTMODE)
    or a
    jr nz,.col
    push hl
    call TXT_GET_CURSOR         ; the screen: where the cursor is
    ld a,h
    pop hl
    dec a
    jr .nl
.col:
    ld a,(V_OUTCOL)
.nl:
    ld hl,NIL
    or a
    jp z,so_back
    CORE newline
    ld hl,S_T
    jp so_back

;; (pprint x [stream]): a new line, x pretty-printed (72 wide into a file)
;@ PPRINT 1 2 lf_pprint
lf_pprint:
    NEXTARG
    dec b
    call so_from
    ex de,hl
    push hl
    ld a,(V_OUTMODE)
    cp 3
    ld a,72
    jr z,.w
    call pp_setw
    jr .nl
.w:
    ld (PP_W),a
.nl:
    CORE newline
    pop hl
    push hl
    call pp_start
    pop hl
    ld hl,NIL
    jp so_back

;; ---------------------------------------------------------------------------
;; READING. On the keyboard read-char waits for a key, read-char-no-hang
;; does not; read-line uses the line editor.

;; (read [stream eof-error-p eof-value])
;@ READ 0 4 lf_read
lf_read:
    call si_from
    CORE read
    ld a,h
    cp 4
    jp nz,si_back
    ld a,l
    cp EOFMARK and #FF
    jp z,si_eof
    CORE check_real             ; a ")" or "." out of place
    jp si_back

;; (read-line [stream eof-error-p eof-value]) -> the line, a string
;@ READ-LINE 0 4 lf_read_line
lf_read_line:
    call si_from
    call si_infile
    jr z,.file
    CORE edit_line
    jr nc,.esc
    ld hl,0                     ; the REPL's line is used up
    ld (V_INPTR),hl
    xor a
    ld (V_PEEK),a
    ld hl,LINEBUF
    ld bc,0
.l:
    ld a,(hl)
    or a
    jr z,.e
    inc hl
    inc bc
    jr .l
.e:
    CORE newline                ; as a terminal echoes RETURN
    ld hl,LINEBUF
    jr .make
.esc:
    CORE input_break
.file:
    ld hl,TOKBUF
    ld bc,0
.fl:
    call si_getc
    or a
    jr z,.fend
    cp 10
    jr z,.fdone
    ld (hl),a
    inc hl
    inc c
    jr nz,.fl
    dec c                       ; 255 at most
    jr .fdone
.fend:
    ld a,c
    or a
    jp z,si_eof
.fdone:
    ld hl,TOKBUF
.make:
    CORE make_string
    jp si_back

;; (read-char [stream eof-error-p eof-value]), (read-char-no-hang ...)
;@ READ-CHAR 0 4 lf_read_char
lf_read_char:
    call si_from
    call si_infile
    jr z,.file
    call KM_WAIT_CHAR_L
    jr .ch
.file:
    call si_getc
    or a
    jp z,si_eof
.ch:
    call lchar
    jp si_back
;@ READ-CHAR-NO-HANG 0 4 lf_read_char_no_hang
lf_read_char_no_hang:
    call si_from
    call si_infile
    jr z,lf_read_char.file
    call KM_READ_CHAR_L
    jr c,lf_read_char.ch
    ld hl,NIL
    jp si_back

;; (peek-char [peek-type stream eof-error-p eof-value]): the next
;; character, left to be read again; peek-type T: blanks passed over first
;; (in a file)
;@ PEEK-CHAR 0 5 lf_peek_char
lf_peek_char:
    xor a
    inc b
    dec b
    jr z,.t
    NEXTARG
    dec b
    ld a,d
    or e
.t:
    ld (SO_PTYPE),a
    call si_from
    call si_infile
    jr z,.file
    call KM_WAIT_CHAR_L
    push af
    call KM_CHAR_RETURN
    pop af
    jr .ch
.file:
    call si_getc
    or a
    jp z,si_eof
    ld c,a
    ld a,(SO_PTYPE)
    or a
    jr z,.keep
    ld a,c
    cp " "+1
    jr c,.file                  ; a blank, passed over
.keep:
    ld a,c
    ld (V_PEEK),a               ; (the file's, while it is the input)
.ch:
    call lchar
    jp si_back

;; (unread-char c [stream]): c is the next one read
;@ UNREAD-CHAR 1 2 lf_unread_char
lf_unread_char:
    NEXTARG
    push de
    ld de,NIL
    dec b
    jr z,.k
    NEXTARG
.k:
    pop hl
    push de
    push hl
    CORE check_char
    pop hl
    pop de
    srl h
    rr l
    srl h
    rr l
    ld c,l
    call so_file                ; (BC kept)
    ld a,c
    jr z,.key
    ld (SO_FPEEK),a
    jp lnil
.key:
    call KM_CHAR_RETURN
    jp lnil

;; (listen [stream]) -> T if a key is waiting, or the file is not at its end
;@ LISTEN 0 1 lf_listen
lf_listen:
    call si_from
    call si_infile
    jr z,.file
    call KM_READ_CHAR_L
    ld hl,NIL
    jp nc,si_back
    call KM_CHAR_RETURN
    ld hl,S_T
    jp si_back
.file:
    call si_getc
    ld hl,NIL
    or a
    jp z,si_back
    ld (V_PEEK),a
    ld hl,S_T
    jp si_back

;; ---------------------------------------------------------------------------
;; OPENING AND CLOSING (open and close in lisp.lsp make the stream)

;; (%open name output-p) -> T, the file open for input (output-p NIL)
;; or output: an error if it cannot be, or one is open that way already
;@ %OPEN 2 2 lf_open
lf_open:
    ld a,d
    or e
    ld a,1                      ; V_FILES bit 0: input, bit 1: output
    jr z,.dir
    ld a,2
.dir:
    ld c,a
    ld a,(V_FILES)
    and c
    jr nz,.busy
    ld a,c
    ld (SO_DIR),a
    push hl                     ; the name, for an error
    call fl_name                ; TOKBUF, B = its length
    push bc
    call fl_lend                ; DE = a buffer
    pop bc
    ld hl,TOKBUF
    ld a,(SO_DIR)
    rra
    jr nc,.out
    call fl_in_open
    jr .opened
.out:
    call fl_out_open
.opened:
    pop de
    jr nc,.fail
    ld a,(SO_DIR)
    ld hl,V_FILES
    res 2,(hl)                  ; (an input file not at its end yet)
    or (hl)
    ld (hl),a
    xor a
    ld (SO_FPEEK),a
    ld a,(SO_DIR)
    rra
    jp c,lt
    xor a
    ld (SO_FCOL),a
    jp lt
.fail:
    call fl_release
    ld hl,fl_m_open
    jp lib_error
.busy:
    ex de,hl
    ld hl,fl_m_twice
    jp lib_error

;; (%close output-p): the output (or input) file closed -> T
;@ %CLOSE 1 1 lf_close
lf_close:
    ld a,h
    or l
    jr z,.in
    ld a,(V_FILES)
    and 2
    jp z,lt
    call CAS_OUT_CLOSE
    push af
    ld hl,V_FILES
    res 1,(hl)
    call fl_release
    pop af
    jp c,lt
    ld hl,m_write
    ld de,UNBOUND
    CORE error
.in:
    ld a,(V_FILES)
    rra
    jp nc,lt
    call CAS_IN_CLOSE
    ld hl,V_FILES
    res 0,(hl)
    res 2,(hl)
    call fl_release
    jp lt
