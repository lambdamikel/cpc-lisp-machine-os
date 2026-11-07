;; CPC Lisp -- the line editor (library ROM).
;;
;; Replaces the firmware's EDIT when the library is present, with the same
;; contract: fill LINEBUF, carry set for ENTER, clear for ESC. On top of
;; EDIT's editing it knows Lisp:
;;
;;  * a ")" typed shows its "(" for a moment -- the cursor goes there, on
;;    this line or an earlier one -- and an unmatched one beeps;
;;  * a continuation line starts indented: two under the "(" of a form with
;;    a body (DEFUN, LET, WHEN, DOLIST...), else under the first argument,
;;    else one in from the "(";
;;  * TAB indents a blank line to there;
;;  * up arrow brings back the last line;
;;  * SHIFT + arrows move a copy cursor and COPY copies from under it, as on
;;    the CPC's own editor.
;;
;; What is open from earlier lines is kept in a stack (ED_STACK, V_EDDEPTH)
;; that ENTER updates by scanning the line. The reader's own nesting
;; (V_DEPTH) is the truth: with nothing open there, the stack is emptied.
;;
;; Screen positions: a line starts at column ED_COL0 and wraps at the window
;; width. Rows are kept as row + the firmware's roll count (TXT GET CURSOR
;; returns it), which does not change when the screen scrolls; subtracting
;; the current roll count gives the row now.

TXT_GET_WINDOW      equ #BB69
TXT_CUR_ENABLE      equ #BB7B
TXT_RD_CHAR         equ #BB60
TXT_INVERSE         equ #BB9C
KM_CHAR_RETURN      equ #BB0C

ED_COL0   equ LIBSCR+16         ; the column the line starts in
ED_VROW0  equ LIBSCR+17         ; its row plus the roll count
ED_W      equ LIBSCR+18         ; window width
ED_H      equ LIBSCR+19         ; window height
ED_LEN    equ LIBSCR+20         ; characters in LINEBUF
ED_POS    equ LIBSCR+21         ; the cursor's index
ED_CCOL   equ LIBSCR+22         ; copy cursor: column, 0 = none
ED_CVROW  equ LIBSCR+23         ;   row plus roll count
ED_CCHAR  equ LIBSCR+24         ;   the character under it
ED_INSTR  equ LIBSCR+25         ; scanning: inside a string
ED_ATOM   equ LIBSCR+26         ; scanning: start of the atom being read, 255 none
ED_I      equ LIBSCR+27         ; scanning: index
ED_G      equ LIBSCR+28         ; matching: ")"s that closed earlier lines' "("s
ED_LD     equ LIBSCR+29         ; matching: "("s open in this line
ED_LOCAL  equ LIBSCR+32         ; matching: their indices, 32
ED_STACK  equ LIBSCR+64         ; earlier lines' "("s: column, vrow, indent, tokens
ED_MAX    equ 48
ED_LIMIT  equ 250               ; longest line

lib_editor:
    call TXT_GET_CURSOR         ; H = column, L = row, A = roll count
    add a,l
    ld (ED_VROW0),a
    ld a,h
    ld (ED_COL0),a
    call TXT_GET_WINDOW         ; H left, D right, L top, E bottom
    ld a,d
    sub h
    inc a
    ld (ED_W),a
    ld a,e
    sub l
    inc a
    ld (ED_H),a
    xor a
    ld (ED_LEN),a
    ld (ED_POS),a
    ld (ED_CCOL),a
    ; the reader knows what is open
    ld a,(V_DEPTH)
    or a
    jr nz,.open
    ld (V_EDDEPTH),a
    ld (V_EDSTR),a
    jr .fill
.open:
    ld b,a
    ld a,(V_EDDEPTH)
    cp b
    jr c,.fill
    ld a,b
    ld (V_EDDEPTH),a
.fill:
    call ed_indent              ; A = blanks to start with
    or a
    jr z,.ready
    ld b,a
    ld hl,LINEBUF
.sp:
    ld (hl)," "
    inc hl
    djnz .sp
    ld (ED_LEN),a
    ld (ED_POS),a
    xor a
    call ed_draw
.ready:
    call ed_place
    call TXT_CUR_ENABLE
    call TXT_CUR_ON
ed_key:
    call KM_WAIT_CHAR_L
    cp #0D
    jp z,ed_enter
    cp #FC
    jp z,ed_esc
    cp #7F
    jr z,.del
    cp #10
    jr z,.clr
    cp #F2
    jr z,.left
    cp #F3
    jr z,.right
    cp #FA
    jr z,.home
    cp #FB
    jr z,.end
    cp #F0
    jp z,ed_up
    cp #E0
    jp z,ed_copy
    cp 9
    jp z,ed_tab
    cp #F4
    jr c,.char
    cp #F8
    jp c,ed_cmove
.char:
    cp " "
    jp c,ed_key
    cp #7F
    jp nc,ed_key
    push af
    call ed_insert
    pop af
    cp ")"
    call z,ed_blink
    jp ed_key
.del:
    ld a,(ED_POS)
    or a
    jp z,ed_key
    dec a
    ld (ED_POS),a
    jr .rub
.clr:
    ld a,(ED_POS)
    ld hl,ED_LEN
    cp (hl)
    jp nc,ed_key
.rub:
    call ed_delete
    ld a,(ED_POS)
    call ed_draw
    call ed_place
    jp ed_key
.left:
    ld a,(ED_POS)
    or a
    jp z,ed_key
    dec a
    jr .setpos
.right:
    ld a,(ED_POS)
    ld hl,ED_LEN
    cp (hl)
    jp nc,ed_key
    inc a
    jr .setpos
.home:
    xor a
    jr .setpos
.end:
    ld a,(ED_LEN)
.setpos:
    ld (ED_POS),a
    call ed_place
    jp ed_key

ed_enter:
    call ed_uncopy
    ld a,(ED_LEN)
    call ed_goto                ; the newline that follows goes after it all
    call ed_commit
    call ed_hsave
    call ed_end
    scf
    ret

ed_esc:
    call ed_uncopy
    ld a,(ED_LEN)
    call ed_goto
    xor a
    ld (ED_LEN),a
    ld (V_EDDEPTH),a
    ld (V_EDSTR),a
    call ed_end
    or a
    ret

;; zero-terminate the line and take the cursor away
ed_end:
    ld a,(ED_LEN)
    ld e,a
    ld d,0
    ld hl,LINEBUF
    add hl,de
    ld (hl),0
    jp TXT_CUR_OFF

;; up arrow: the last line again
ed_up:
    ld a,(HISTBUF)
    or a
    jp z,ed_key
    ld c,a
    ld b,0
    ld a,(ED_LEN)
    push af
    ld a,c
    ld (ED_LEN),a
    ld (ED_POS),a
    ld hl,HISTBUF+1
    ld de,LINEBUF
    ldir
    xor a
    call ed_draw
    pop af                      ; blank out the rest of a longer line
    ld hl,ED_LEN
    sub (hl)
    jr c,.done
    jr z,.done
    ld b,a
.er:
    push bc
    ld a," "
    call TXT_WR_CHAR
    pop bc
    djnz .er
.done:
    call ed_place
    jp ed_key

;; TAB: blanks up to the indentation, if there is room before the cursor
ed_tab:
    call ed_indent
    ld b,a
    ld a,(ED_POS)
    cp b
    jp nc,ed_key
    sub b
    neg
.l:
    push af
    ld a," "
    call ed_insert
    pop af
    dec a
    jr nz,.l
    jp ed_key

;; SHIFT + an arrow (A = &F4 up, &F5 down, &F6 left, &F7 right)
ed_cmove:
    push af
    ld a,(ED_CCOL)
    or a
    jr nz,.have
    call ed_place               ; it starts where the cursor is
    call TXT_GET_CURSOR
    push af
    ld a,h
    ld (ED_CCOL),a
    pop af
    add a,l
    ld (ED_CVROW),a
    jr .move
.have:
    call ed_undraw_copy
.move:
    pop af
    ld hl,ED_CVROW
    cp #F4
    jr nz,.m1
    dec (hl)
.m1:
    cp #F5
    jr nz,.m2
    inc (hl)
.m2:
    ld hl,ED_CCOL
    cp #F6
    jr nz,.m3
    ld a,(hl)
    dec a
    jr z,.m3
    ld (hl),a
.m3:
    cp #F7
    jr nz,.m4
    ld a,(ED_W)
    cp (hl)
    jr z,.m4
    inc (hl)
.m4:
    call ed_clamp_copy
    call ed_draw_copy
    call ed_place
    jp ed_key

;; COPY: the character under the copy cursor goes into the line
ed_copy:
    ld a,(ED_CCOL)
    or a
    jr nz,.ok
    call ed_beep
    jp ed_key
.ok:
    call ed_undraw_copy
    ld a,(ED_CCHAR)
    call ed_insert
    ld a,(ED_W)
    ld hl,ED_CCOL
    cp (hl)
    jr z,.edge
    inc (hl)
.edge:
    call ed_draw_copy
    call ed_place
    jp ed_key

;; keep the copy cursor on the screen
ed_clamp_copy:
    call TXT_GET_CURSOR         ; A = roll
    ld b,a
    ld a,(ED_CVROW)
    sub b                       ; its row now
    jr z,.top
    bit 7,a
    jr nz,.top
    ld c,a
    ld a,(ED_H)
    cp c
    ret nc
    add a,b
    ld (ED_CVROW),a
    ret
.top:
    ld a,b
    inc a
    ld (ED_CVROW),a
    ret

;; ed_copy_at: the text cursor to the copy cursor
ed_copy_at:
    call TXT_GET_CURSOR
    ld b,a
    ld a,(ED_CVROW)
    sub b
    ld l,a
    ld a,(ED_CCOL)
    ld h,a
    jp TXT_SET_CURSOR

ed_draw_copy:
    call TXT_CUR_OFF
    call ed_copy_at
    call TXT_RD_CHAR
    jr c,.got
    ld a," "
.got:
    ld (ED_CCHAR),a
    call TXT_INVERSE
    ld a,(ED_CCHAR)
    call TXT_WR_CHAR
    call TXT_INVERSE
    jp TXT_CUR_ON

ed_undraw_copy:
    call TXT_CUR_OFF
    call ed_copy_at
    ld a,(ED_CCHAR)
    call TXT_WR_CHAR
    jp TXT_CUR_ON

;; ed_uncopy: put away the copy cursor, if there is one
ed_uncopy:
    ld a,(ED_CCOL)
    or a
    ret z
    call ed_undraw_copy
    xor a
    ld (ED_CCOL),a
    ret

;; ---------------------------------------------------------------------------
;; the line and the screen

;; ed_insert: A = a character, put in at the cursor
ed_insert:
    push af
    ld a,(ED_LEN)
    cp ED_LIMIT
    jr nc,.full
    ld b,a
    ld e,a
    ld d,0
    ld hl,LINEBUF
    add hl,de
    ld d,h
    ld e,l
    dec hl                      ; HL = the last character, DE = past it
    ld a,(ED_POS)
    ld c,a
    ld a,b
    sub c
    jr z,.put
    ld c,a
    ld b,0
    lddr
.put:
    ld a,(ED_POS)
    ld e,a
    ld d,0
    ld hl,LINEBUF
    add hl,de
    pop af
    ld (hl),a
    ld hl,ED_LEN
    inc (hl)
    ld a,(ED_POS)
    push af
    inc a
    ld (ED_POS),a
    pop af
    call ed_draw
    jp ed_place
.full:
    pop af
ed_beep:
    ld a,7
    jp TXT_OUTPUT

;; ed_delete: take out the character at the cursor
ed_delete:
    ld a,(ED_POS)
    ld e,a
    ld d,0
    ld hl,LINEBUF
    add hl,de
    ld d,h
    ld e,l
    inc hl
    ld a,(ED_POS)
    ld b,a
    ld a,(ED_LEN)
    sub b
    dec a
    jr z,.done
    ld c,a
    ld b,0
    ldir
.done:
    ld hl,ED_LEN
    dec (hl)
    ret

;; ed_draw: A = an index -> the line from there redrawn, and one blank
;; after it for what a deletion left
ed_draw:
    push af
    call ed_goto
    pop af
    ld c,a
    ld e,a
    ld d,0
    ld hl,LINEBUF
    add hl,de
    ld a,(ED_LEN)
    sub c
    ld b,a
    inc b
    jr .n
.l:
    ld a,(hl)
    push hl
    push bc
    call TXT_WR_CHAR
    pop bc
    pop hl
    inc hl
.n:
    djnz .l
    ld a," "
    jp TXT_WR_CHAR

ed_place:
    ld a,(ED_POS)
;; ed_goto: A = an index -> the text cursor at it
ed_goto:
    call ed_where
    push hl
    call TXT_GET_CURSOR
    ld b,a
    pop hl
    ld a,(ED_VROW0)
    add a,l
    sub b
    ld l,a
    jp TXT_SET_CURSOR

;; ed_where: A = an index -> H = its column, L = rows below the line's first
ed_where:
    ld e,a
    ld d,0
    ld a,(ED_COL0)
    dec a
    ld l,a
    ld h,0
    add hl,de
    ld a,(ED_W)
    ld e,a
    ld c,0
.div:
    or a
    sbc hl,de
    jr c,.done
    inc c
    jr .div
.done:
    add hl,de
    ld a,l
    inc a
    ld h,a
    ld l,c
    ret

;; ---------------------------------------------------------------------------
;; parentheses

;; ed_indent -> A = the blanks a new line starts with
ed_indent:
    ld a,(V_EDDEPTH)
    or a
    ret z
    call ed_top
    inc hl
    inc hl
    ld a,(hl)                   ; the column to indent to
    ld hl,ED_COL0
    sub (hl)
    ret nc
    xor a
    ret

;; ed_top -> HL = the innermost entry; ed_entry: A = an index -> HL
ed_top:
    ld a,(V_EDDEPTH)
    dec a
ed_entry:
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    ld de,ED_STACK
    add hl,de
    ret

;; ed_blink: a ")" is just before the cursor: show its "(" for a moment
ed_blink:
    call ed_match
    jr nc,.show
    or a
    ret z
    jp ed_beep
.show:
    call TXT_SET_CURSOR
    ld b,15
.w:
    push bc
    call MC_WAIT_FLYBACK
    call KM_READ_CHAR_L
    jr c,.key
    pop bc
    djnz .w
    jr .back
.key:
    call KM_CHAR_RETURN
    pop bc
.back:
    jp ed_place

;; ed_match: the "(" for the ")" before the cursor -> NC and H = its column,
;; L = its row; or C, with A = 1 if there is none (beep) or 0 if the ")" is
;; in a string or a comment (say nothing)
ed_match:
    ld a,(V_EDSTR)
    ld (ED_INSTR),a
    xor a
    ld (ED_G),a
    ld (ED_LD),a
    ld (ED_I),a
.loop:
    ld a,(ED_POS)
    dec a
    ld b,a
    ld a,(ED_I)
    cp b
    jr nc,.end
    call ed_char
    ld c,a
    ld a,(ED_INSTR)
    or a
    jr z,.code
    ld a,c
    cp #5C
    jr nz,.s1
    call ed_inc_i
    jr .next
.s1:
    cp #22
    jr nz,.next
    xor a
    ld (ED_INSTR),a
    jr .next
.code:
    ld a,c
    cp #22
    jr nz,.c1
    ld a,1
    ld (ED_INSTR),a
    jr .next
.c1:
    cp ";"
    jr z,.quiet
    cp "#"
    jr nz,.c2
    call ed_peek_next
    cp #5C
    jr nz,.next
    call ed_inc_i
    call ed_inc_i
    jr .next
.c2:
    cp "("
    jr nz,.c3
    ld a,(ED_LD)
    cp 32
    jr nc,.next
    ld e,a
    ld d,0
    ld hl,ED_LOCAL
    add hl,de
    ld a,(ED_I)
    ld (hl),a
    ld hl,ED_LD
    inc (hl)
    jr .next
.c3:
    cp ")"
    jr nz,.next
    ld a,(ED_LD)
    or a
    jr z,.outer
    dec a
    ld (ED_LD),a
    jr .next
.outer:
    ld hl,ED_G
    inc (hl)
.next:
    call ed_inc_i
    jp .loop
.quiet:
    xor a
    scf
    ret
.end:
    ld a,(ED_INSTR)
    or a
    jr nz,.quiet
    ld a,(ED_LD)
    or a
    jr z,.earlier
    dec a
    ld e,a
    ld d,0
    ld hl,ED_LOCAL
    add hl,de
    ld a,(hl)
    call ed_where
    push hl
    call TXT_GET_CURSOR
    ld b,a
    pop hl
    ld a,(ED_VROW0)
    add a,l
    sub b
    ld l,a
    or a
    ret
.earlier:
    ld a,(ED_G)
    ld b,a
    ld a,(V_EDDEPTH)
    sub b
    jr c,.none
    jr z,.none
    dec a
    call ed_entry
    ld d,(hl)                   ; column
    inc hl
    ld e,(hl)                   ; row + roll
    push de
    call TXT_GET_CURSOR
    ld b,a
    pop de
    ld a,e
    sub b
    jr z,.quiet                 ; scrolled off the top
    bit 7,a
    jr nz,.quiet
    ld l,a
    ld h,d
    or a
    ret
.none:
    ld a,1
    scf
    ret

;; ed_commit: ENTER -- what the line opens and closes goes into the stack,
;; with the indentation each open form wants
ed_commit:
    ld a,(V_EDDEPTH)            ; what earlier lines opened is settled
    or a
    jr z,.f2
    ld b,a
    ld hl,ED_STACK+3
.f1:
    ld (hl),255
    inc hl
    inc hl
    inc hl
    inc hl
    djnz .f1
.f2:
    ld a,(V_EDSTR)
    ld (ED_INSTR),a
    ld a,255
    ld (ED_ATOM),a
    xor a
    ld (ED_I),a
.loop:
    ld a,(ED_I)
    ld hl,ED_LEN
    cp (hl)
    jp nc,.eol
    call ed_char
    ld c,a
    ld a,(ED_INSTR)
    or a
    jr z,.code
    ld a,c
    cp #5C
    jr nz,.s1
    call ed_inc_i
    jr .next
.s1:
    cp #22
    jr nz,.next
    xor a
    ld (ED_INSTR),a
    jr .next
.code:
    ld a,c
    call ed_isdelim
    jr nz,.constituent
    call ed_atom_end
    call ed_char
    cp " "+1
    jr c,.next
    cp #22
    jr nz,.c1
    call ed_tokstart
    ld a,1
    ld (ED_INSTR),a
    jr .next
.c1:
    cp ";"
    jr z,.eol
    cp "("
    jr nz,.c2
    call ed_tokstart
    call ed_push
    jr .next
.c2:
    cp ")"
    jr nz,.next
    call ed_pop
    jr .next
.constituent:
    ld a,(ED_ATOM)
    cp 255
    jr nz,.next                 ; inside an atom
    ld a,c
    cp "#"
    jr nz,.atom
    call ed_peek_next
    cp "'"
    jr nz,.hc
    call ed_inc_i               ; #' is a prefix, like '
    jr .next
.hc:
    cp #5C
    jr nz,.atom
    ld a,(ED_I)                 ; #\x: an atom whose third character may be anything
    ld (ED_ATOM),a
    call ed_tokstart
    call ed_inc_i
    call ed_inc_i
    jr .next
.atom:
    ld a,(ED_I)
    ld (ED_ATOM),a
    call ed_tokstart
.next:
    call ed_inc_i
    jp .loop
.eol:
    call ed_atom_end
    ld a,(ED_INSTR)
    ld (V_EDSTR),a
    ret

;; a token starts at ED_I, in the innermost open form
ed_tokstart:
    ld a,(V_EDDEPTH)
    or a
    ret z
    call ed_top
    inc hl
    inc hl
    inc hl
    ld a,(hl)
    cp 255
    ret z
    inc a
    ld (hl),a
    cp 2
    ret nz
    ld (hl),255                 ; the second: line up with it, and that is that
    dec hl
    push hl
    ld a,(ED_I)
    call ed_where
    ld a,h
    pop hl
    ld (hl),a
    ret

;; an atom ends at ED_I. If it was a form's first, a body form decides.
ed_atom_end:
    ld a,(ED_ATOM)
    cp 255
    ret z
    ld b,a
    ld a,255
    ld (ED_ATOM),a
    ld a,(V_EDDEPTH)
    or a
    ret z
    call ed_top
    push hl
    inc hl
    inc hl
    inc hl
    ld a,(hl)
    pop hl
    cp 1
    ret nz
    push hl
    ld a,(ED_I)
    sub b
    ld c,a                      ; the atom's length
    ld e,b
    ld d,0
    ld hl,LINEBUF
    add hl,de
    ex de,hl                    ; DE = the atom
    call ed_bodyform
    pop hl
    ret nz
    ld a,(hl)                   ; the "("'s column
    add a,2
    inc hl
    inc hl
    ld (hl),a
    inc hl
    ld (hl),255
    ret

;; a "(" at ED_I
ed_push:
    ld a,(V_EDDEPTH)
    cp ED_MAX
    ret nc
    inc a
    ld (V_EDDEPTH),a
    ld a,(ED_I)
    call ed_where               ; H = column, L = rows down
    ld a,(ED_VROW0)
    add a,l
    ld c,a
    ld b,h
    call ed_top
    ld (hl),b
    inc hl
    ld (hl),c
    inc hl
    ld a,b
    inc a
    ld (hl),a                   ; until we know better: one in
    inc hl
    ld (hl),0
    ret

ed_pop:
    ld a,(V_EDDEPTH)
    or a
    ret z
    dec a
    ld (V_EDDEPTH),a
    ret

;; ed_bodyform: DE = an atom's text, C = its length -> Z if it names a form
;; whose body is indented by two, and A = how many of its arguments come
;; before the body (the pretty printer keeps those on the first line)
ed_bodyform:
    ld hl,bodyforms
.t:
    ld a,(hl)
    or a
    jr z,.no
    cp c
    jr nz,.skip
    push hl
    push bc
    push de
    inc hl
    ld b,c
.c:
    ld a,(de)
    cp "a"
    jr c,.u
    cp "z"+1
    jr nc,.u
    sub #20
.u:
    cp (hl)
    jr nz,.ne
    inc hl
    inc de
    djnz .c
    ld a,(hl)                   ; how many before the body
    pop de
    pop bc
    pop hl
    cp a
    ret
.ne:
    pop de
    pop bc
    pop hl
.skip:
    ld a,(hl)
    add a,2
    add a,l
    ld l,a
    jr nc,.t
    inc h
    jr .t
.no:
    or 1
    ret

bodyforms:
    db 5,"DEFUN",2
    db 8,"DEFMACRO",2
    db 6,"LAMBDA",1
    db 3,"LET",1
    db 4,"LET*",1
    db 4,"FLET",1
    db 6,"LABELS",1
    db 4,"WHEN",1
    db 6,"UNLESS",1
    db 6,"DOLIST",1
    db 7,"DOTIMES",1
    db 5,"BLOCK",1
    db 4,"LOOP",0
    db 5,"PROGN",0
    db 5,"PROG1",1
    db 4,"CASE",1
    db 5,"CATCH",1
    db 2,"DO",2
    db 3,"DO*",2
    db 0

;; scanning helpers
ed_char:
    ld a,(ED_I)
    ld e,a
    ld d,0
    ld hl,LINEBUF
    add hl,de
    ld a,(hl)
    ret
ed_peek_next:
    ld a,(ED_I)
    inc a
    ld hl,ED_LEN
    cp (hl)
    ld a,0
    ret nc
    ld a,(ED_I)
    inc a
    ld e,a
    ld d,0
    ld hl,LINEBUF
    add hl,de
    ld a,(hl)
    ret
ed_inc_i:
    ld hl,ED_I
    inc (hl)
    ret
;; Z if A ends an atom
ed_isdelim:
    cp " "+1
    jr c,.yes
    cp "("
    ret z
    cp ")"
    ret z
    cp #22
    ret z
    cp ";"
    ret z
    cp "'"
    ret z
    cp "`"
    ret z
    cp ","
    ret
.yes:
    cp a
    ret

;; ed_hsave: a line that is not blank becomes the history
ed_hsave:
    ld a,(ED_LEN)
    or a
    ret z
    ld b,a
    ld hl,LINEBUF
.chk:
    ld a,(hl)
    cp " "
    jr nz,.save
    inc hl
    djnz .chk
    ret
.save:
    ld a,(ED_LEN)
    cp 127
    jr c,.n
    ld a,127
.n:
    ld (HISTBUF),a
    ld c,a
    ld b,0
    ld hl,LINEBUF
    ld de,HISTBUF+1
    ldir
    ret
