;; CPC Lisp -- the function editor (library ROM).
;;
;;     (ed 'name)     edit name's definition: (defun ...) or (defmacro ...),
;;                    pretty-printed; a template if it has none yet
;;     (ed)           the text last edited, again (after an error in it, say)
;;
;; The whole screen is the text, with a status line at the bottom. Lines
;; longer than the screen wrap. COPY (or CTRL-S) reads and evaluates all of
;; it; ESC leaves it as it was. Keys as in the line editor, and RETURN
;; indents the new line, TAB indents the line the cursor is on, a ")" shows
;; its "(", CTRL + up/down go to the top/bottom, CTRL + left/right to the
;; start/end of the line.
;;
;; THE BUFFER is lent from the top of block space (V_BLKHI is lowered, and
;; V_BLKSAVE remembers it, so an error anywhere gives it back): half of
;; what is free after a collection, at most 2 KB. Nothing allocates while
;; the editor runs, so it cannot move. Afterwards the text is kept in
;; V_EDITSTR, a string, and read from there.

FE_BUF    equ LIBSCR+32         ; the buffer: start,
FE_LIM    equ LIBSCR+34         ;   end,
FE_END    equ LIBSCR+36         ;   end of the text,
FE_CUR    equ LIBSCR+38         ;   the cursor,
FE_TOP    equ LIBSCR+40         ;   the first character on the screen
FE_W      equ LIBSCR+42         ; screen width
FE_H      equ LIBSCR+43         ; text rows: the screen less the status line
FE_ROW    equ LIBSCR+44         ; the cursor on the screen
FE_COL    equ LIBSCR+45
FE_DIRTY  equ LIBSCR+46         ; the screen needs drawing again
FE_RFROM  equ LIBSCR+47         ; drawing: first row,
FE_RTO    equ LIBSCR+48         ;   last row
FE_SP     equ LIBSCR+49         ; scanning: where,
FE_SEND   equ LIBSCR+51         ;   up to where,
FE_SLS    equ LIBSCR+53         ;   the start of its line,
FE_SATOM  equ LIBSCR+55         ;   the atom being read, 0 none,
FE_SSTR   equ LIBSCR+57         ;   in a string,
FE_SD     equ LIBSCR+58         ;   open forms
FE_TRIES  equ LIBSCR+59         ; fe_locate: rounds left
FE_STK    equ LIBSCR+64         ; their column, indentation, tokens, -
FE_MSTK   equ LIBSCR+64         ; matching: up to 32 "(" positions (shares the room)
FE_MAX    equ 48
FE_MAXBUF equ 2048

;@ ED 0 1 lf_ed
lf_ed:
    ld a,b
    or a
    jr nz,.sym
    ld hl,(V_EDITSTR)           ; (ed): the last text
    ld a,h
    or l
    jr nz,.again
    ld hl,fe_m_nothing
    jp lib_error
.again:
    call fe_reserve
    ld hl,(V_EDITSTR)
    call lstring                ; HL = characters, BC = how many
    push hl
    ld hl,(FE_LIM)
    ld de,(FE_BUF)
    or a
    sbc hl,de                   ; room
    or a
    sbc hl,bc
    jr nc,.fits
    add hl,bc
    ld b,h
    ld c,l
.fits:
    pop hl
    ld de,(FE_BUF)
    ld a,b
    or c
    jr z,.e
    ldir
.e:
    ld (FE_END),de
    jr .edit
.sym:
    NEXTARG
    ex de,hl                    ; the symbol
    push hl
    call fe_definition          ; HL = the form, or NIL
    pop de
    push de
    push hl
    call fe_reserve
    ld a,1                      ; print into the buffer
    ld (V_OUTMODE),a
    ld hl,(FE_BUF)
    ld (V_OUTPTR),hl
    ld hl,(FE_LIM)
    ld (V_OUTEND),hl
    xor a
    ld (V_OUTCOL),a
    pop hl
    pop de
    ld a,h
    or l
    jr z,.template
    push hl
    call pp_setw                ; (TXT GET WINDOW returns in HL)
    pop hl
    call pp
    jr .printed
.template:
    push de
    ld hl,fe_m_defun
    call fe_puts
    pop hl
    CORE prin1
    ld hl,fe_m_tail
    call fe_puts
.printed:
    xor a
    ld (V_OUTMODE),a
    ld hl,(V_OUTPTR)
    ld (FE_END),hl
.edit:
    call fe_edit
    push af
    xor a
    ld (V_OUTCOL),a
    call TXT_CLEAR_WINDOW
    pop af
    jr c,.done
    call fe_release
    jp lnil
.done:
    ; keep the text, give the space back, read and evaluate all of it
    ld hl,(FE_END)
    ld de,(FE_BUF)
    or a
    sbc hl,de
    ld b,h
    ld c,l
    ex de,hl
    CORE make_string
    ld (V_EDITSTR),hl
    call fe_release
    ld hl,(V_EDITSTR)
    ld (V_SRCOBJ),hl
    ld hl,0
    ld (V_SRCPTR),hl
    ld a,2
    ld (V_INSRC),a
    xor a
    ld (V_PEEK),a
    ld hl,NIL
    push hl                     ; the last value
.form:
    CORE read
    ld a,h
    cp 4
    jr nz,.eval
    ld a,l
    cp EOFMARK and #FF
    jr z,.end
    CORE check_real             ; ")" or "." where they cannot be
.eval:
    CORE eval
    pop de
    push hl
    jr .form
.end:
    xor a
    ld (V_INSRC),a
    pop hl
    ret

fe_m_nothing: db "nothing has been edited yet",0
fe_m_defun:   db "(defun ",0
fe_m_tail:    db " ()",10,"  )",0
fe_m_status:  db " COPY or CTRL-S: done   ESC: cancel",0
fe_m_cannot:  db "cannot edit a builtin:",0

;; fe_puts: HL = text in this ROM, through putc
fe_puts:
    ld a,(hl)
    or a
    ret z
    call lputc
    inc hl
    jr fe_puts

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

;; fe_reserve: lend the buffer out of block space
fe_reserve:
    CORE gc
    ld hl,(V_BLKHI)
    ld de,(V_BLKTOP)
    or a
    sbc hl,de
    srl h
    rr l                        ; half of what is free
    ld de,FE_MAXBUF
    push hl
    or a
    sbc hl,de
    pop hl
    jr c,.size
    ex de,hl
.size:
    ld de,256
    push hl
    or a
    sbc hl,de
    pop hl
    jr nc,.ok
    ld hl,m_nostr
    ld de,UNBOUND
    CORE error
.ok:
    ex de,hl                    ; DE = size
    ld hl,(V_BLKHI)
    ld (V_BLKSAVE),hl
    ld (FE_LIM),hl
    or a
    sbc hl,de
    ld (V_BLKHI),hl
    ld (FE_BUF),hl
    ld (FE_END),hl
    ret

fe_release:
    ld hl,(V_BLKSAVE)
    ld (V_BLKHI),hl
    ld hl,0
    ld (V_BLKSAVE),hl
    ret

;; fe_definition: HL = a symbol -> HL = (defun name ...) or (defmacro name
;; ...), or NIL if it has no definition. A builtin is an error.
fe_definition:
    push hl
    ld de,SY_FUNC
    add hl,de
    LDHLI
    pop de
    push de
    CORE resolve_fn             ; a library function in Lisp: load it first
    ld a,h
    cp 4
    jr nz,.has
    pop hl
    ld hl,NIL
    ret
.has:
    ld a,l
    and 3
    cp 2
    jp nz,.bad
    ld a,h
    cp CELL_LO >> 8
    jp c,.bad
    cp #C0
    jp nc,.bad
    push hl
    dec hl
    dec hl
    ld a,(hl)
    pop hl
    ld bc,S_DEFUN
    cp HDR_CLOSURE and #FF
    jr z,.clo
    cp HDR_MACRO and #FF
    jp nz,.bad
    LDHLI                       ; a macro's closure
    ld bc,S_DEFMACRO
.clo:
    LDHLI                       ; (code . env)
    LDHLI                       ; code: (lambda-list . body)
    push bc                     ; [symbol][defun or defmacro]
    push hl
    CDRHL                       ; the body
    ; (block name . body) as all of it was put there by defun: take it off
    ld a,l
    and 3
    jr nz,.keep
    ld a,h
    or l
    jr z,.keep
    push hl
    CDRHL
    ld a,h
    or l
    pop hl
    jr nz,.keep
    push hl
    LDHLI                       ; the one form
    ld a,l
    and 3
    jr nz,.keep1
    ld a,h
    or l
    jr z,.keep1
    push hl
    LDHLI
    ld de,S_BLOCK
    or a
    sbc hl,de
    pop hl
    jr nz,.keep1
    CDRHL
    ld a,l
    and 3
    jr nz,.keep1
    ld a,h
    or l
    jr z,.keep1
    CDRHL                       ; past BLOCK and the name
    pop de
    jr .body
.keep1:
    pop hl
.keep:
.body:                          ; HL = the body
    ex de,hl
    pop hl
    LDHLI                       ; the lambda list
    CORE cons                   ; (lambda-list . body)
    ex de,hl
    pop bc
    pop hl                      ; the symbol
    push bc
    CORE cons                   ; (name lambda-list . body)
    ex de,hl
    pop hl
    CORE cons                   ; (defun name ...)
    ret
.bad:
    pop de
    ld hl,fe_m_cannot
    jp lib_error

;; ---------------------------------------------------------------------------
;; editing

;; fe_edit -> C to keep the text, NC to drop it
fe_edit:
    call TXT_GET_WINDOW
    ld a,d
    sub h
    inc a
    ld (FE_W),a
    ld a,e
    sub l
    ld (FE_H),a                 ; the last row is the status line
    ld hl,(FE_BUF)
    ld (FE_CUR),hl
    ld (FE_TOP),hl
    call TXT_CLEAR_WINDOW
    ld a,(FE_H)
    inc a
    ld l,a
    ld h,1
    call TXT_SET_CURSOR
    call TXT_INVERSE
    ld hl,fe_m_status
.st:
    ld a,(hl)
    or a
    jr z,.st2
    push hl
    call TXT_WR_CHAR
    pop hl
    inc hl
    jr .st
.st2:
    call TXT_INVERSE
    call fe_render_all
    call TXT_CUR_ENABLE
    call TXT_CUR_ON
fe_loop:
    call fe_locate
    ld a,(FE_COL)
    ld h,a
    ld a,(FE_ROW)
    ld l,a
    call TXT_SET_CURSOR
    call KM_WAIT_CHAR_L
    cp #E0
    jr z,.done
    cp #13
    jr z,.done
    cp #FC
    jr z,.cancel
    cp #0D
    jp z,fe_return
    cp #7F
    jp z,fe_bs
    cp #10
    jp z,fe_clr
    cp 9
    jp z,fe_tab
    cp #F0
    jp z,fe_up
    cp #F1
    jp z,fe_down
    cp #F2
    jp z,fe_left
    cp #F3
    jp z,fe_right
    cp #F8
    jp z,fe_first
    cp #F9
    jp z,fe_last
    cp #FA
    jp z,fe_home
    cp #FB
    jp z,fe_eol
    cp " "
    jr c,fe_loop
    cp #7F
    jr nc,fe_loop
    push af
    call fe_ins
    jr c,.full
    pop af
    push af
    call fe_redraw
    pop af
    cp ")"
    call z,fe_blink
    jr fe_loop
.full:
    pop af
    call ed_beep
    jr fe_loop
.done:
    call TXT_CUR_OFF
    scf
    ret
.cancel:
    call TXT_CUR_OFF
    or a
    ret

;; fe_redraw: A = the character just put in or taken out, at the cursor's
;; row. A line still on one row is drawn again alone, else everything from
;; the row the change was on.
fe_redraw:
    push af
    ld a,(FE_ROW)
    ld (FE_RFROM),a
    ld a,(FE_H)
    ld (FE_RTO),a
    pop af
    cp 10
    jr z,.rest
    ld hl,(FE_CUR)
    call fe_lstart
    push hl
    ld hl,(FE_CUR)
    call fe_lend
    pop de
    or a
    sbc hl,de                   ; the line's length
    ld a,h
    or a
    jr nz,.rest
    ld a,(FE_W)
    dec a
    cp l
    jr c,.rest
    ld a,(FE_ROW)
    ld (FE_RTO),a
.rest:
    jp fe_render

fe_left:
    ld hl,(FE_CUR)
    ld de,(FE_BUF)
    call fe_cmp
    jp z,fe_loop
    dec hl
    jr fe_setcur
fe_right:
    ld hl,(FE_CUR)
    ld de,(FE_END)
    call fe_cmp
    jp z,fe_loop
    inc hl
    jr fe_setcur
fe_home:
    ld hl,(FE_CUR)
    call fe_lstart
    jr fe_setcur
fe_eol:
    ld hl,(FE_CUR)
    call fe_lend
    jr fe_setcur
fe_first:
    ld hl,(FE_BUF)
    jr fe_setcur
fe_last:
    ld hl,(FE_END)
fe_setcur:
    ld (FE_CUR),hl
    jp fe_loop

;; up and down keep the column, as far as the line allows
fe_up:
    ld hl,(FE_CUR)
    call fe_lstart
    ld de,(FE_BUF)
    call fe_cmp
    jp z,fe_loop                ; the first line
    push hl
    ld de,(FE_CUR)
    ex de,hl
    or a
    sbc hl,de
    ld b,h
    ld c,l                      ; the column
    pop hl
    dec hl                      ; the line above's end
    push hl
    call fe_lstart
    pop de
    jr fe_column
fe_down:
    ld hl,(FE_CUR)
    call fe_lstart
    push hl
    ld hl,(FE_CUR)
    call fe_lend
    ld de,(FE_END)
    call fe_cmp
    pop de
    jp z,fe_loop                ; the last line
    push hl
    ld hl,(FE_CUR)
    or a
    sbc hl,de
    ld b,h
    ld c,l                      ; the column
    pop hl
    inc hl                      ; the line below's start
    push hl
    call fe_lend
    ex de,hl
    pop hl
;; fe_column: HL = a line's start, DE = its end, BC = a column -> the
;; cursor there, or at the end if the line is shorter
fe_column:
    push hl
    add hl,bc
    call fe_cmp
    pop bc
    jr c,fe_setcur
    ex de,hl
    jr fe_setcur

;; DEL: the character before the cursor; CLR: the one under it
fe_bs:
    ld hl,(FE_CUR)
    ld de,(FE_BUF)
    call fe_cmp
    jp z,fe_loop
    dec hl
    ld (FE_CUR),hl
    call fe_locate
fe_clr:
    call fe_del
    jp c,fe_loop
    call fe_redraw
    jp fe_loop

;; RETURN: a new line, indented
fe_return:
    ld hl,(FE_CUR)
    call fe_indent              ; A = blanks
    push af
    ld a,10
    call fe_ins
    pop bc
    jr c,.full
    ld a,b
    or a
    jr z,.draw
.sp:
    push bc
    ld a," "
    call fe_ins
    pop bc
    jr c,.draw
    djnz .sp
.draw:
    ld a,10
    call fe_redraw
    jp fe_loop
.full:
    call ed_beep
    jp fe_loop

;; TAB: the line the cursor is on, indented as it should be
fe_tab:
    ld hl,(FE_CUR)
    call fe_lstart
    push hl
    call fe_indent              ; A = how far it should be in
    pop hl
    push af
    ld de,(FE_CUR)
    ex de,hl
    or a
    sbc hl,de
    push hl                     ; the cursor's column
    ld (FE_CUR),de
    ld b,0                      ; take the blanks out
.dl:
    ld hl,(FE_CUR)
    ld de,(FE_END)
    call fe_cmp
    jr z,.dd
    ld a,(hl)
    cp " "
    jr nz,.dd
    push bc
    call fe_del
    pop bc
    inc b
    jr .dl
.dd:
    pop hl                      ; the cursor's column
    pop af                      ; blanks wanted
    push hl
    push bc
    ld b,a
    or a
    jr z,.ins_done
.ins:
    push bc
    ld a," "
    call fe_ins
    pop bc
    djnz .ins
.ins_done:
    pop bc                      ; B = blanks taken out
    pop hl                      ; the column it was in
    ld c,b
    ld b,0
    or a
    sbc hl,bc
    jr c,.at
    ld de,(FE_CUR)
    add hl,de
    ld (FE_CUR),hl
.at:
    ld a,10
    call fe_redraw
    jp fe_loop

;; fe_blink: a ")" just before the cursor: show its "(", if it is on the
;; screen, for a moment; beep if it has none
fe_blink:
    ld hl,(FE_CUR)
    dec hl
    call fe_match               ; HL = the "(", or C
    jr nc,.found
    or a
    ret z
    jp ed_beep
.found:
    ld de,(FE_TOP)
    call fe_cmp
    ret c                       ; above the screen
    ex de,hl
    call fe_walk                ; B = row, C = column
    ld a,(FE_H)
    cp b
    ret c
    ld h,c
    ld l,b
    call TXT_SET_CURSOR
    ld b,15
.w:
    push bc
    call MC_WAIT_FLYBACK
    call KM_READ_CHAR_L
    jr c,.key
    pop bc
    djnz .w
    ret
.key:
    call KM_CHAR_RETURN
    pop bc
    ret

;; ---------------------------------------------------------------------------
;; the text

;; fe_cmp: HL - DE as an unsigned comparison, HL and DE kept
fe_cmp:
    or a
    sbc hl,de
    add hl,de
    ret

;; fe_lstart: HL -> the start of its line
fe_lstart:
    ld de,(FE_BUF)
.l:
    call fe_cmp
    ret z
    dec hl
    ld a,(hl)
    inc hl
    cp 10
    ret z
    dec hl
    jr .l

;; fe_lend: HL -> the end of its line: its LF, or the end of the text
fe_lend:
    ld de,(FE_END)
.l:
    call fe_cmp
    ret z
    ld a,(hl)
    cp 10
    ret z
    inc hl
    jr .l

;; fe_ins: A at the cursor, which moves past it. C if there is no room.
fe_ins:
    push af
    ld hl,(FE_END)
    ld de,(FE_LIM)
    call fe_cmp
    jr nc,.full
    ld de,(FE_CUR)
    or a
    sbc hl,de
    ld b,h
    ld c,l                      ; what moves up
    ld hl,(FE_END)
    ld d,h
    ld e,l
    dec hl
    ld a,b
    or c
    jr z,.put
    lddr
.put:
    ld hl,(FE_CUR)
    pop af
    ld (hl),a
    inc hl
    ld (FE_CUR),hl
    ld hl,(FE_END)
    inc hl
    ld (FE_END),hl
    or a
    ret
.full:
    pop af
    scf
    ret

;; fe_del: take out the character at the cursor -> A = it, or C if none
fe_del:
    ld hl,(FE_CUR)
    ld de,(FE_END)
    call fe_cmp
    jr nc,.none
    ld a,(hl)
    push af
    ex de,hl
    or a
    sbc hl,de
    dec hl
    ld b,h
    ld c,l                      ; what moves down
    ld h,d
    ld l,e
    inc hl
    ld a,b
    or c
    jr z,.d
    ldir
.d:
    ld hl,(FE_END)
    dec hl
    ld (FE_END),hl
    pop af
    or a
    ret
.none:
    scf
    ret

;; ---------------------------------------------------------------------------
;; the screen

;; fe_walk: DE = a place in the text, at or after FE_TOP -> B = its row,
;; C = its column. Stops counting a little past the bottom.
fe_walk:
    ld hl,(FE_TOP)
    ld bc,#0101
.l:
    call fe_cmp
    jr nc,.at
    ld a,(hl)
    inc hl
    cp 10
    jr z,.nl
    ld a,(FE_W)
    cp c
    jr nc,.put
    inc b
    ld c,1
.put:
    inc c
    jr .chk
.nl:
    inc b
    ld c,1
.chk:
    ld a,(FE_H)
    add a,2
    cp b
    jr nc,.l
    ret
.at:
    ld a,(FE_W)
    cp c
    ret nc
    inc b
    ld c,1
    ret

;; fe_locate: the cursor's row and column; if it is off the screen, the
;; screen moves (by half its height, so as not to do it at every line)
fe_locate:
    xor a
    ld (FE_DIRTY),a
    ld a,16                     ; a line taller than the screen: give up
    ld (FE_TRIES),a
.again:
    ld hl,FE_TRIES
    dec (hl)
    jr z,.fits
    ld hl,(FE_CUR)
    ld de,(FE_TOP)
    call fe_cmp
    jr nc,.below
    call fe_lstart              ; above: half a screen above its line
    ld a,(FE_H)
    srl a
    ld b,a
.up:
    ld de,(FE_BUF)
    call fe_cmp
    jr z,.settop
    dec hl
    call fe_lstart
    djnz .up
.settop:
    ld (FE_TOP),hl
    ld a,1
    ld (FE_DIRTY),a
    jr .again
.below:
    ld de,(FE_CUR)
    call fe_walk
    ld a,(FE_H)
    cp b
    jr nc,.fits
    ld a,(FE_H)                 ; below: down until it is half way
    srl a
    ld b,a
    ld hl,(FE_TOP)
.down:
    push bc
    call fe_lend
    ld de,(FE_END)
    call fe_cmp
    pop bc
    jr z,.settop
    inc hl
    djnz .down
    jr .settop
.fits:
    ld a,(FE_H)
    cp b
    jr nc,.rowok
    ld b,a
.rowok:
    ld a,b
    ld (FE_ROW),a
    ld a,c
    ld (FE_COL),a
    ld a,(FE_DIRTY)
    or a
    ret z
fe_render_all:
    ld a,1
    ld (FE_RFROM),a
    ld a,(FE_H)
    ld (FE_RTO),a
;; fe_render: draw rows FE_RFROM to FE_RTO
fe_render:
    call TXT_CUR_OFF
    ld hl,(FE_TOP)
    ld bc,#0101                 ; B = row, C = column
    call .rowstart
.l:
    ld a,(FE_RTO)
    cp b
    jr c,.out
    ld de,(FE_END)
    call fe_cmp
    jr z,.blank
    ld a,(hl)
    cp 10
    jr z,.nl
    ld a,(FE_W)
    cp c
    jr nc,.put
    inc b
    ld c,1
    call .rowstart
    jr .l
.put:
    call .drawing
    jr c,.skip
    ld a,(hl)
    push hl
    push bc
    call TXT_WR_CHAR
    pop bc
    pop hl
.skip:
    inc hl
    inc c
    jr .l
.nl:
    call .clear
    inc hl
    inc b
    ld c,1
    call .rowstart
    jr .l
.blank:
    call .clear
    inc b
    ld c,1
    ld a,(FE_RTO)
    cp b
    jr c,.out
    call .rowstart
    jr .blank
.out:
    jp TXT_CUR_ON
;; C if row B is not being drawn
.drawing:
    push hl
    ld a,b
    ld hl,FE_RFROM
    cp (hl)
    jr c,.dr
    ld a,(FE_RTO)
    cp b
.dr:
    pop hl
    ret
.rowstart:
    call .drawing
    ret c
    push hl
    push bc
    ld h,1
    ld l,b
    call TXT_SET_CURSOR
    pop bc
    pop hl
    ret
;; blanks from column C to the end of row B
.clear:
    call .drawing
    ret c
    push hl
    push bc
.c:
    ld a,(FE_W)
    cp c
    jr c,.cd
    push bc
    ld a," "
    call TXT_WR_CHAR
    pop bc
    inc c
    jr .c
.cd:
    pop bc
    pop hl
    ret

;; ---------------------------------------------------------------------------
;; reading the text: where a line starts, and what matches what

;; fe_indent: HL = a place in the text -> A = how many blanks a line
;; starting there should have, by what is open before it (the same rules
;; as the line editor's, editor.asm)
fe_indent:
    ld (FE_SEND),hl
    ld hl,(FE_BUF)
    ld (FE_SP),hl
    ld (FE_SLS),hl
    xor a
    ld (FE_SD),a
    ld (FE_SSTR),a
    ld hl,0
    ld (FE_SATOM),hl
.loop:
    ld hl,(FE_SP)
    ld de,(FE_SEND)
    call fe_cmp
    jp nc,.eol
    ld a,(hl)
    ld c,a
    cp 10
    jr nz,.notnl
    call .atom_end              ; a line ends: what is open is settled
    ld hl,(FE_SP)
    inc hl
    ld (FE_SLS),hl
    ld a,(FE_SD)
    or a
    jp z,.next
    ld b,a
    ld hl,FE_STK+2
.fz:
    ld (hl),255
    inc hl
    inc hl
    inc hl
    inc hl
    djnz .fz
    jp .next
.notnl:
    ld a,(FE_SSTR)
    or a
    jr z,.code
    ld a,c
    cp #5C
    jr nz,.s1
    call .inc
    jp .next
.s1:
    cp #22
    jp nz,.next
    xor a
    ld (FE_SSTR),a
    jp .next
.code:
    ld a,c
    call ed_isdelim
    jr nz,.constituent
    call .atom_end
    ld hl,(FE_SP)
    ld a,(hl)
    cp " "+1
    jp c,.next
    cp #22
    jr nz,.c1
    call .tokstart
    ld a,1
    ld (FE_SSTR),a
    jp .next
.c1:
    cp ";"
    jr nz,.c2
.comment:                       ; to the end of the line
    ld hl,(FE_SP)
    ld de,(FE_SEND)
    call fe_cmp
    jp nc,.eol
    ld a,(hl)
    cp 10
    jp z,.loop
    call .inc
    jr .comment
.c2:
    cp "("
    jr nz,.c3
    call .tokstart
    call .push
    jp .next
.c3:
    cp ")"
    jp nz,.next
    ld hl,FE_SD
    ld a,(hl)
    or a
    jp z,.next
    dec (hl)
    jp .next
.constituent:
    ld hl,(FE_SATOM)
    ld a,h
    or l
    jp nz,.next                 ; in an atom already
    ld a,c
    cp "#"
    jr nz,.atom
    ld hl,(FE_SP)
    inc hl
    ld a,(hl)
    cp "'"
    jr nz,.hc
    call .inc                   ; #' is only a prefix
    jp .next
.hc:
    cp #5C
    jr nz,.atom
    ld hl,(FE_SP)               ; #\x: an atom, whatever x is
    ld (FE_SATOM),hl
    call .tokstart
    call .inc
    call .inc
    jp .next
.atom:
    ld hl,(FE_SP)
    ld (FE_SATOM),hl
    call .tokstart
.next:
    call .inc
    jp .loop
.eol:
    call .atom_end
    ld a,(FE_SD)
    or a
    ret z
    call .top
    inc hl
    ld a,(hl)                   ; its indentation
    ret
.inc:
    ld hl,(FE_SP)
    inc hl
    ld (FE_SP),hl
    ret
;; HL = the innermost open form's entry
.top:
    ld a,(FE_SD)
    dec a
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    ld de,FE_STK
    add hl,de
    ret
;; A = the column of FE_SP
.column:
    ld hl,(FE_SP)
    ld de,(FE_SLS)
    or a
    sbc hl,de
    ld a,h
    or a
    ld a,l
    ret z
    ld a,255
    ret
.push:
    ld a,(FE_SD)
    cp FE_MAX
    ret nc
    inc a
    ld (FE_SD),a
    call .column
    ld b,a
    call .top
    ld (hl),b                   ; column
    inc hl
    inc b
    ld (hl),b                   ; indentation, for now: one in
    inc hl
    ld (hl),0                   ; tokens
    ret
.tokstart:
    ld a,(FE_SD)
    or a
    ret z
    call .top
    inc hl
    inc hl
    ld a,(hl)
    cp 255
    ret z
    inc a
    ld (hl),a
    cp 2
    ret nz
    ld (hl),255                 ; the second token: line up with it
    dec hl
    push hl
    call .column
    pop hl
    ld (hl),a
    ret
.atom_end:
    ld hl,(FE_SATOM)
    ld a,h
    or l
    ret z
    ld de,0
    ld (FE_SATOM),de
    ld a,(FE_SD)
    or a
    ret z
    push hl
    call .top
    inc hl
    inc hl
    ld a,(hl)
    pop de                      ; DE = the atom
    cp 1
    ret nz                      ; not a form's first
    push hl
    ld hl,(FE_SP)
    or a
    sbc hl,de
    ld c,l                      ; its length
    ld a,h
    or a
    pop hl
    ret nz
    push hl
    call ed_bodyform
    pop hl
    ret nz
    ld (hl),255                 ; a body form: two in from its "("
    dec hl
    dec hl
    ld a,(hl)
    add a,2
    inc hl
    ld (hl),a
    ret

;; fe_match: HL = a ")" in the text -> HL = its "(", or C (A = 1: there is
;; none, beep; A = 0: in a string or a comment, say nothing)
fe_match:
    ld (FE_SEND),hl
    ld hl,(FE_BUF)
    ld (FE_SP),hl
    xor a
    ld (FE_SSTR),a
    ld (FE_SD),a
.loop:
    ld hl,(FE_SP)
    ld de,(FE_SEND)
    call fe_cmp
    jp nc,.end
    ld a,(hl)
    ld c,a
    ld a,(FE_SSTR)
    or a
    jr z,.code
    ld a,c
    cp #5C
    jr nz,.s1
    inc hl
    ld (FE_SP),hl
    jp .next
.s1:
    cp #22
    jp nz,.next
    xor a
    ld (FE_SSTR),a
    jp .next
.code:
    ld a,c
    cp #22
    jr nz,.c1
    ld a,1
    ld (FE_SSTR),a
    jp .next
.c1:
    cp ";"
    jr nz,.c2
.comment:
    ld hl,(FE_SP)
    ld de,(FE_SEND)
    call fe_cmp
    jr nc,.quiet                ; the ")" is in the comment
    ld a,(hl)
    cp 10
    jp z,.loop
    inc hl
    ld (FE_SP),hl
    jr .comment
.c2:
    cp "#"
    jr nz,.c3
    inc hl
    ld a,(hl)
    cp #5C
    jp nz,.next
    inc hl
    ld (FE_SP),hl
    jp .next
.c3:
    cp "("
    jr nz,.c4
    ld a,(FE_SD)
    cp 32
    jp nc,.next
    inc a
    ld (FE_SD),a
    dec a
    add a,a
    ld e,a
    ld d,0
    ld hl,FE_MSTK
    add hl,de
    ld de,(FE_SP)
    ld (hl),e
    inc hl
    ld (hl),d
    jp .next
.c4:
    cp ")"
    jp nz,.next
    ld hl,FE_SD
    ld a,(hl)
    or a
    jp z,.next
    dec (hl)
.next:
    ld hl,(FE_SP)
    inc hl
    ld (FE_SP),hl
    jp .loop
.end:
    ld a,(FE_SSTR)
    or a
    jr nz,.quiet
    ld a,(FE_SD)
    or a
    jr z,.none
    dec a
    add a,a
    ld e,a
    ld d,0
    ld hl,FE_MSTK
    add hl,de
    LDHLI
    or a
    ret
.quiet:
    xor a
    scf
    ret
.none:
    ld a,1
    scf
    ret
