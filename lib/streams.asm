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
;; output goes to the stream: none or NIL is *standard-output*'s value,
;; NIL or T there the screen; a file stream the file open for output; a
;; string output stream TOKBUF, its text pushed onto the stream at the end.
;; What to put back is left on the stack under the caller's return: the
;; stream, V_OUTPTR, V_OUTEND, V_OUTCNT, and V_OUTMODE (bit 7: switched to
;; the file, bit 6: to a string) with V_OUTCOL. The caller ends with jp
;; so_back.
so_from:
    pop ix
    push de
    ld de,NIL
    inc b
    dec b
    jr z,.d
    NEXTARG
.d:
    ld a,d
    or e
    jr nz,.given
    ld de,(S_STDOUT+SY_VALUE)
.given:
    call so_kind                ; A = 0 screen, 1 file, 2 string
    pop hl                      ; the caller's DE
    push de                     ; the stream
    ld de,(V_OUTPTR)
    push de
    ld de,(V_OUTEND)
    push de
    ld de,(V_OUTCNT)
    push de
    ex de,hl                    ; DE as the caller had it
    ld bc,0
    or a
    jr z,.go
    ld l,a                      ; the kind
    ld a,(V_OUTCOL)
    ld b,a
    ld a,(V_OUTMODE)
    ld c,a
    ld a,l
    cp 2
    jr z,.string
    jr nc,.closed               ; an input stream
    ld a,(V_FILES)              ; a file
    and 2
    jr z,.closed
    set 7,c
    ld a,3
    ld (V_OUTMODE),a
    ld a,(SO_FCOL)
    ld (V_OUTCOL),a
    jr .go
.string:
    set 6,c
    ld a,1
    ld (V_OUTMODE),a
    ld hl,TOKBUF
    ld (V_OUTPTR),hl
    ld hl,TOKBUF+255
    ld (V_OUTEND),hl
    ld hl,0
    ld (V_OUTCNT),hl
    xor a
    ld (V_OUTCOL),a
.go:
    push bc
    jp (ix)
.closed:                        ; the stream, for the message
    ld hl,6
    add hl,sp
    LDHLI
    ex de,hl
    jp so_closed

;; so_back: the output as it was before so_from. HL kept
so_back:
    pop bc
    bit 6,c
    jr nz,.string
    bit 7,c
    jr z,.drop
    ld a,(V_OUTCOL)             ; the file's column, for next time
    ld (SO_FCOL),a
    ld a,c
    and #3F
    ld (V_OUTMODE),a
    ld a,b
    ld (V_OUTCOL),a
.drop:
    pop de
    pop de
    pop de
    pop de
    ret
.string:                        ; TOKBUF up to V_OUTPTR: the text printed
    push bc
    push hl
    ld hl,(V_OUTPTR)
    ld de,TOKBUF
    or a
    sbc hl,de
    ld b,h
    ld c,l
    ex de,hl
    CORE make_string
    ld de,10                    ; the stream, under the value, the mode and
    ex de,hl                    ;   three words
    add hl,sp
    LDHLI
    ex de,hl
    call so_chunk
    pop hl
    pop bc
    pop de
    ld (V_OUTCNT),de
    pop de
    ld (V_OUTEND),de
    pop de
    ld (V_OUTPTR),de
    pop de
    ld a,c
    and #3F
    ld (V_OUTMODE),a
    ld a,b
    ld (V_OUTCOL),a
    ret

;; so_chunk: HL = a string, DE = a string output stream -> pushed onto its
;; list (slot 1). The stream is held elsewhere, where the GC sees it.
so_chunk:
    push de
    push hl
    ex de,hl
    CORE vec_data               ; HL = &slot 0
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    pop hl
    CORE cons
    ex de,hl                    ; DE = the list with it
    pop hl
    push de
    CORE vec_data               ; (the cons may have moved the slots)
    inc hl
    inc hl
    pop de
    ld (hl),e
    inc hl
    ld (hl),d
    ret

;; so_kind: DE = a stream designator -> A = 0 the screen (NIL or T), 1 a
;; file stream, 2 a string output stream, 3 a string input stream (a
;; structure of two, three slots: the type and its text; and its index).
;; BC, DE, HL kept
so_kind:
    call so_file
    ld a,0
    ret z
    push hl
    push bc
    push de
    push ix                     ; (CORE takes IX: so_from and si_from keep
                                ;   their return in it)
    ex de,hl
    ld c,HDR_STRUCT and #FF
    push hl
    CORE is_typed
    pop hl
    ld a,1
    jr nz,.done
    CORE vec_data               ; BC = its slots and type
    ld a,c
    cp 2
    jr z,.done                  ; 2: a string output stream
    cp 3
    jr z,.done                  ; 3: a string input stream
    ld a,1
.done:
    pop ix
    pop de
    pop bc
    pop hl
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
;; many -> input comes from the stream: the keyboard (NIL, T), the file
;; open for input, or a string input stream's text, from its index on. Left
;; on the stack under the caller's return: eof-value, eof-error-p,
;; V_SRCOBJ, V_SRCPTR, the stream, and V_INSRC (bit 7: switched, bit 6: to
;; a string) with V_PEEK. The caller ends with jp si_back, or jp si_eof at
;; the end.
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
    ld de,(V_SRCOBJ)
    push de
    ld de,(V_SRCPTR)
    push de
    xor a
    ld de,NIL
    call sd_nth                 ; DE = the stream
    push de
    ld bc,0
    call so_kind
    or a
    jr nz,.stream
    ld a,(V_INSRC)              ; the keyboard: as it is, unless a file is
    or a                        ;   being loaded (or text read)
    jr z,.go
    xor a
    ld e,a                      ; E = the source, D = its pushed-back char
    ld d,a
    jr .switch
.stream:
    cp 3
    jr z,.string
    cp 2
    jp z,so_closed              ; an output stream
    ld a,(V_FILES)              ; a file
    rra
    jp nc,so_closed
    ld e,3
    ld a,(SO_FPEEK)
    ld d,a
    jr .switch
.string:
    ex de,hl
    push ix
    CORE vec_data               ; HL = &slot 0
    pop ix
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; the string
    inc hl
    ld (V_SRCOBJ),de
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; the index, a fixnum
    ex de,hl
    sra h
    rr l
    ld (V_SRCPTR),hl
    ld bc,#0040                 ; C bit 6: a string
    ld de,2                     ; E = the source, D = nothing pushed back
.switch:
    ld a,(V_INSRC)
    or #80
    or c
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
    bit 7,c
    jr z,.drop
    ld a,(V_INSRC)
    cp 3
    jr nz,.str
    ld a,(V_PEEK)               ; the file's, for next time
    ld (SO_FPEEK),a
    jr .put
.str:
    bit 6,c
    jr z,.put
    push hl                     ; a string stream: where it got to, back
    push bc                     ;   in its slot 2 (one less for a character
    ld hl,(V_SRCPTR)            ;   pushed back)
    ld a,(V_PEEK)
    or a
    jr z,.at
    dec hl
.at:
    add hl,hl
    inc hl
    ex de,hl                    ; DE = the index, a fixnum
    ld hl,4
    add hl,sp
    LDHLI                       ; the stream
    push de
    CORE vec_data
    pop de
    ld bc,4
    add hl,bc
    ld (hl),e
    inc hl
    ld (hl),d
    pop bc
    pop hl
.put:
    ld a,c
    and #3F
    ld (V_INSRC),a
    ld a,b
    ld (V_PEEK),a
.drop:
    pop de                      ; the stream
    pop de
    ld (V_SRCPTR),de
    pop de
    ld (V_SRCOBJ),de
    pop de
    pop de
    ret

;; si_eof: the end of the input: eof-value, or an error if eof-error-p
si_eof:
    ld hl,8
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

;; si_infile: Z if the input is a file or a string stream now (read a
;; character at a time), NZ for the keyboard
si_infile:
    ld a,(V_INSRC)
    cp 2
    ret z
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
    call CON_GETCUR         ; the screen: where the cursor is
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
    call KEY_WAIT
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
    call KEY_READ
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
    call KEY_WAIT
    push af
    call KEY_UNREAD
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
    call so_kind                ; A = the kind (BC, DE kept)
    cp 3
    jr z,.str
    or a
    ld a,c
    jr z,.key
    ld (SO_FPEEK),a
    jp lnil
.str:                           ; a string stream: its index back one
    ex de,hl
    CORE vec_data
    ld bc,4
    add hl,bc
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,d
    or a
    jr nz,.back
    ld a,e
    cp 3
    jp c,lnil                   ; at 0 already
.back:
    dec de
    dec de
    ld (hl),d
    dec hl
    ld (hl),e
    jp lnil
.key:
    call KEY_UNREAD
    jp lnil

;; (listen [stream]) -> T if a key is waiting, or the file is not at its end
;@ LISTEN 0 1 lf_listen
lf_listen:
    call si_from
    call si_infile
    jr z,.file
    call KEY_READ
    ld hl,NIL
    jp nc,si_back
    call KEY_UNREAD
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
    call FILE_OCLOSE
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
    call FILE_ICLOSE
    ld hl,V_FILES
    res 0,(hl)
    res 2,(hl)
    call fl_release
    jp lt
