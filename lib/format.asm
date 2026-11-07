;; CPC Lisp -- format (library ROM).
;;
;;   (format t control arg...)    prints, -> NIL
;;   (format nil control arg...)  -> the output as a string (255 at most)
;;
;; Directives, in either case: ~A princ, ~S prin1, ~D a number (as ~A),
;; ~C a character (as ~A), ~% a newline, ~& a newline unless at the start of
;; a line, ~~ a tilde. ~A, ~S and ~D take a width: ~8A pads on the right,
;; ~5D on the left.
;;
;; Nothing here allocates until the string is made at the end, so the
;; control string cannot move while it is read.

FMT_CP    equ LIBSCR+9          ; the control string: next character,
FMT_CN    equ LIBSCR+11         ;   how many are left
FMT_AP    equ LIBSCR+13         ; the arguments: the next,
FMT_AN    equ LIBSCR+15         ;   how many are left

fmt_m_dir:  db "bad format directive",0

;@ FORMAT 2 255 lf_format
lf_format:
    NEXTARG
    push de                     ; the destination
    NEXTARG
    push hl
    push bc
    ex de,hl
    call lstring                ; HL = its characters, BC = how many
    ld (FMT_CP),hl
    ld (FMT_CN),bc
    pop bc
    pop hl
    ld (FMT_AP),hl
    ld a,b
    sub 2
    ld (FMT_AN),a
    pop hl
    ld a,h
    or l
    jr z,.string
    call fmt_run                ; T (or anything else): the screen
    jp lnil
.string:
    ld ix,fmt_run
    jp to_string_ix

;; fmt_run: the output, wherever putc is sending it
fmt_run:
    ld hl,(FMT_CN)
    ld a,h
    or l
    ret z
    call fmt_next
    cp #7E
    jr z,.dir
    call lputc
    jp fmt_run
.dir:
    ld c,0                      ; a width
.w:
    ld hl,(FMT_CN)
    ld a,h
    or l
    jr z,.bad
    call fmt_next
    cp "0"
    jr c,.letter
    cp "9"+1
    jr nc,.letter
    sub "0"
    ld b,a
    ld a,c
    add a,a
    ld c,a
    add a,a
    add a,a
    add a,c
    add a,b
    ld c,a                      ; C = C * 10 + the digit
    jr .w
.letter:
    and #DF                     ; upper case (and ~ stays ~ ... see below)
    cp "A"
    jr z,.princ
    cp "D"
    jr z,.num
    cp "C"
    jr z,.princ
    cp "S"
    jr z,.prin1
    cp #25 and #DF               ; %
    jr z,.nl
    cp #26 and #DF               ; &
    jr z,.fresh
    cp #7E and #DF               ; ~
    jr z,.tilde
.bad:
    ld hl,fmt_m_dir
    ld de,UNBOUND
    jp lib_error
.tilde:
    ld a,#7E
    call lputc
    jp fmt_run
.nl:
    CORE newline
    jp fmt_run
.fresh:
    ld a,(V_OUTMODE)
    or a
    jr nz,.col
    CORE fresh_line
    jp fmt_run
.col:
    ld a,(V_OUTCOL)
    or a
    jr nz,.nl
    jp fmt_run
.princ:
    ld de,princ
    ld b,0                      ; pad on the right
    jr .arg
.num:
    ld de,princ
    ld b,1                      ; pad on the left
    jr .arg
.prin1:
    ld de,prin1
    ld b,0
.arg:
    ld a,(FMT_AN)
    or a
    jr nz,.have
    ld hl,m_few
    ld de,UNBOUND
    CORE error
.have:
    dec a
    ld (FMT_AN),a
    ld hl,(FMT_AP)
    push de
    NEXTARG
    ld (FMT_AP),hl
    ex de,hl                    ; HL = the argument
    pop ix                      ; IX = how to print it
    ld a,c
    or a
    jr z,.print                 ; no width
    push bc
    push hl
    push ix
    call fmt_width              ; A = the characters it takes
    pop ix
    pop hl
    pop bc
    sub c
    jr nc,.print                ; no room to pad: as it is
    neg
    ld c,a                      ; C = spaces
    bit 0,b
    jr z,.right
    call fmt_spaces
.print:
    call CORECALL
    jp fmt_run
.right:
    push bc
    call CORECALL
    pop bc
    call fmt_spaces
    jp fmt_run

;; fmt_next: the next character of the control string -> A
fmt_next:
    ld hl,(FMT_CN)
    dec hl
    ld (FMT_CN),hl
    ld hl,(FMT_CP)
    ld a,(hl)
    inc hl
    ld (FMT_CP),hl
    ret

;; fmt_spaces: C spaces
fmt_spaces:
    ld a," "
    call lputc
    dec c
    jr nz,fmt_spaces
    ret

;; fmt_width: HL = an object, IX = prin1 or princ -> A = how many
;; characters it prints (255 at most), printing nothing
fmt_width:
    ld a,(V_OUTMODE)
    ld e,a
    ld a,(V_OUTCOL)
    ld d,a
    push de
    ld de,(V_OUTCNT)
    push de
    ld a,2
    ld (V_OUTMODE),a
    ld de,0
    ld (V_OUTCNT),de
    call CORECALL
    ld hl,(V_OUTCNT)
    pop de
    ld (V_OUTCNT),de
    pop de
    ld a,e
    ld (V_OUTMODE),a
    ld a,d
    ld (V_OUTCOL),a
    ld a,h
    or a
    ld a,l
    ret z
    ld a,255
    ret
