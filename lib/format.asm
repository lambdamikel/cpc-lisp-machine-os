;; CPC Lisp -- format (library ROM, part 1).
;;
;;   (format t control arg...)    prints, -> NIL
;;   (format nil control arg...)  -> the output as a string (255 at most)
;;   (format stream control arg...)  into the file open for output
;;
;; A directive is ~, up to five parameters separated by commas (a number,
;; 'c a character, V the next argument, # how many arguments are left),
;; the modifiers : and @, and a letter (either case). CL's directives:
;;
;;   ~A ~S        princ, prin1; ~mincol,,,padcharA pads on the right, ~@A
;;                on the left; ~:A prints NIL as ()
;;   ~D ~B ~O ~X  an integer in base 10, 2, 8, 16: ~mincol,padchar,
;;                commachar,intervalD; ~@D a sign always, ~:D commas. A
;;                whole float is printed as an integer; anything else as ~A
;;   ~nR          in base n (then as ~D's parameters); ~R in words, ~:R
;;                ordinal words, ~@R Roman numerals, ~:@R old Roman
;;   ~w,d,,,padF  a number in fixed point, d digits after the point (all of
;;                them if d is not given), w wide at least; ~E ~G as ~F
;;                without d; ~d,,w,pad$ money: two digits after the point
;;   ~C           a character; ~@C as #\c
;;   ~P           "s" unless the argument is 1; ~:P the argument before;
;;                ~@P "y" or "ies"
;;   ~% ~& ~| ~~  newline, fresh line, page, tilde; ~n% n of them
;;   ~colnum,colincT  to a column; ~n@T n spaces
;;   ~n*          skip n arguments; ~n:* back; ~n@* go to argument n
;;   ~? ~@?       a control string from the argument (and its arguments
;;                from a list, or the rest)
;;   ~{...~}      the body over a list's elements; ~:{ over a list of
;;                lists, ~@{ over the arguments left, ~:@{ both; ~n{ at
;;                most n times; ~:} at least once
;;   ~[a~;b~]     clause n: the argument's (or ~n[); ~:; the default;
;;                ~:[false~;true~]; ~@[clause~] if the argument is true
;;   ~(...~)      lower case; ~:( each word capitalised, ~@( the first,
;;                ~:@( upper case (up to 128 characters)
;;   ~^           stop here if no arguments are left (the iteration, or
;;                everything)
;;   ~newline     the newline and the blanks after it are left out (~:
;;                keeps the blanks, ~@ the newline)
;;
;; Nothing here allocates until the string is made at the end, so the
;; control string cannot move while it is read. The arguments are a run of
;; words, read downwards (NEXTARG): the call's own, or a list's elements
;; pushed onto the stack (fmt_frame) for ~{ and ~?.

FMT_P     equ LIBSCR+0          ; five parameters, 255 = not given
NPARAMS   equ 5
FMT_FL    equ LIBSCR+5          ; the modifiers: bit 0 ":", bit 1 "@"
FMT_A0    equ LIBSCR+6          ; the arguments: the first,
FMT_CP    equ LIBSCR+8          ; the control string: next character,
FMT_CN    equ LIBSCR+10         ;   how many are left
FMT_AP    equ LIBSCR+12         ; the arguments: the next,
FMT_AN    equ LIBSCR+14         ;   how many are left,
FMT_AT    equ LIBSCR+15         ;   how many in all
FMT_BCP   equ LIBSCR+240        ; ~{: the body,
FMT_BCN   equ LIBSCR+242        ;   its length,
FMT_ITN   equ LIBSCR+244        ;   iterations left (255 no limit),
FMT_ITF   equ LIBSCR+245        ;   its modifiers, bit 2: once at least
FMT_RET   equ LIBSCR+246        ; fmt_frame's return
FMT_SKIP  equ LIBSCR+248        ; parsing to pass over: V takes nothing
FMT_RADIX equ LIBSCR+249
FMT_LG    equ LIBSCR+250        ; ~:R: the words being printed end it
    assert FMT_P+NPARAMS == FMT_FL
    assert (FMT_P and #FF)+NPARAMS < 256
    assert FMT_AN+1 == FMT_AT
    assert FMT_ITN+1 == FMT_ITF

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
    ld (FMT_A0),hl
    ld a,b
    sub 2
    ld (FMT_AN),a
    ld (FMT_AT),a
    pop hl
    ld a,h
    or l
    jr z,.string
    ld de,S_T
    or a
    sbc hl,de
    jr nz,.file
    call fmt_run                ; T: the screen
    jp lnil
.string:
    ld ix,fmt_run
    jp to_string_ix
.file:                          ; a stream: the file open for output
    ld a,(V_FILES)
    and 2
    jr z,.closed
    ld a,(V_OUTMODE)
    ld c,a
    ld a,(V_OUTCOL)
    ld b,a
    push bc
    ld a,3
    ld (V_OUTMODE),a
    ld a,(SO_FCOL)
    ld (V_OUTCOL),a
    call fmt_run
    ld a,(V_OUTCOL)
    ld (SO_FCOL),a
    pop bc
    ld a,c
    ld (V_OUTMODE),a
    ld a,b
    ld (V_OUTCOL),a
    jp lnil
.closed:
    ld hl,fmt_m_closed
    ld de,UNBOUND
    jp lib_error
fmt_m_closed: db "the stream is not open",0

;; fmt_run: the control string from FMT_CP on, until it ends (A = 0), a
;; directive that closes a group -- ~} ~] ~; ~) (A = it, FMT_FL its
;; modifiers) -- or ~^ with nothing left (A = "^")
fmt_run:
    ld hl,(FMT_CN)
    ld a,h
    or l
    ret z
    call fmt_next
    cp #7E
    jr z,.dir
    call lputc
    jr fmt_run
.dir:
    xor a
    ld (FMT_SKIP),a
    call fmt_parse              ; A = the directive
    ld c,a
    ld hl,fmt_table
.find:
    ld a,(hl)
    or a
    jr z,fmt_bad
    inc hl
    cp c
    jr z,.go
    inc hl
    inc hl
    jr .find
.go:
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld a,c
    jp (hl)

fmt_bad:
    ld hl,fmt_m_dir
    ld de,UNBOUND
    jp lib_error

fmt_table:
    db "A" : dw fmt_a
    db "S" : dw fmt_s
    db "D" : dw fmt_d
    db "B" : dw fmt_b
    db "O" : dw fmt_o
    db "X" : dw fmt_x
    db "R" : dw fmt_r
    db "F" : dw fmt_f
    db "E" : dw fmt_e
    db "G" : dw fmt_e
    db "$" : dw fmt_dollar
    db "C" : dw fmt_c
    db "P" : dw fmt_plural
    db "%" : dw fmt_nl
    db "&" : dw fmt_fresh
    db "|" : dw fmt_page
    db #7E : dw fmt_tilde
    db "T" : dw fmt_t
    db "*" : dw fmt_star
    db "?" : dw fmt_ind
    db "{" : dw fmt_iter
    db "[" : dw fmt_cond
    db "(" : dw fmt_case
    db "^" : dw fmt_up
    db 10  : dw fmt_newline
    db 13  : dw fmt_newline
    db "}" : dw fmt_close
    db "]" : dw fmt_close
    db ";" : dw fmt_close
    db ")" : dw fmt_close
    db 0

;; fmt_next: the next character of the control string -> A. DE, BC kept
fmt_next:
    ld hl,(FMT_CN)
    dec hl
    ld (FMT_CN),hl
    ld hl,(FMT_CP)
    ld a,(hl)
    inc hl
    ld (FMT_CP),hl
    ret

;; fmt_dch: the same inside a directive: an error if there is none
fmt_dch:
    ld hl,(FMT_CN)
    ld a,h
    or l
    jr z,fmt_bad
    jr fmt_next

;; fmt_peek: A = the next character, not taken; 0 if there is none
fmt_peek:
    ld hl,(FMT_CN)
    ld a,h
    or l
    ret z
    ld hl,(FMT_CP)
    ld a,(hl)
    ret

;; fmt_parse: after a ~: its parameters into FMT_P, its modifiers into
;; FMT_FL -> A = the directive, a letter in upper case
fmt_parse:
    ld hl,FMT_P
    ld b,NPARAMS
.clr:
    ld (hl),255
    inc hl
    djnz .clr
    ld (hl),0                   ; FMT_FL
    ld de,FMT_P                 ; DE = the parameter being read
.param:
    call fmt_dch
    cp "'"
    jr z,.quote
    cp "#"
    jr z,.count
    cp "V"
    jr z,.v
    cp "v"
    jr z,.v
    cp "0"
    jr c,.sep
    cp "9"+1
    jr nc,.sep
    ld hl,0
.dig:
    sub "0"
    push de
    ld e,l
    ld d,h
    add hl,hl
    add hl,hl
    add hl,de
    add hl,hl
    ld e,a
    ld d,0
    add hl,de                   ; HL = HL * 10 + the digit
    pop de
    push hl
    call fmt_dch
    pop hl
    cp "0"
    jr c,.num
    cp "9"+1
    jr c,.dig
.num:
    push af
    ld a,h
    or a
    jr nz,.big
    ld a,l
    cp 255
    jr c,.ok
.big:
    ld a,254                    ; (255 means none)
.ok:
    ld (de),a
    pop af
    jr .sep
.quote:
    call fmt_dch
    ld (de),a
    jr .more
.count:
    ld a,(FMT_AN)
    ld (de),a
    jr .more
.v:
    ld a,(FMT_SKIP)
    or a
    jr nz,.more
    push de
    call fmt_arg                ; a number, a character, or NIL: none
    pop de
    bit 0,l
    jr nz,.vfix
    ld a,h
    cp 4
    jr nc,.more                 ; not a character
    or l
    jr z,.more                  ; NIL
    srl h
    rr l
    srl h
    rr l
    ld a,l
    ld (de),a
    jr .more
.vfix:
    sra h
    rr l
    bit 7,h
    jr nz,.more                 ; negative: none
    ld a,h
    or a
    jr nz,.vbig
    ld a,l
    cp 255
    jr c,.vst
.vbig:
    ld a,254
.vst:
    ld (de),a
.more:
    call fmt_dch
.sep:
    cp ","
    jr nz,.mods
    ld a,e
    cp (FMT_P+NPARAMS-1) and #FF
    jp z,.param                 ; (a sixth goes over the fifth)
    inc de
    jp .param
.mods:
    cp ":"
    jr z,.colon
    cp "@"
    jr z,.at
    cp "a"
    ret c
    cp "z"+1
    ret nc
    and #DF
    ret
.colon:
    ld hl,FMT_FL
    set 0,(hl)
    call fmt_dch
    jr .mods
.at:
    ld hl,FMT_FL
    set 1,(hl)
    call fmt_dch
    jr .mods

;; fmt_param: A = which, C = a default -> A = that parameter, or C. HL goes
fmt_param:
    add a,FMT_P and #FF
    ld l,a
    ld h,FMT_P/256
    ld a,(hl)
    inc a
    ld a,c
    ret z
    ld a,(hl)
    ret

;; fmt_padp: A = which parameter is the pad character -> D = the width
;; (parameter 0, or 0), E = the pad character (or a blank). HL, IX kept
fmt_padp:
    push hl
    ld c," "
    call fmt_param
    ld e,a
    xor a
    ld c,a
    call fmt_param
    ld d,a
    pop hl
    ret

;; fmt_arg: the next argument -> HL. BC, DE, IX kept
fmt_arg:
    ld a,(FMT_AN)
    or a
    jr z,fmt_few
    dec a
    ld (FMT_AN),a
    push de
    ld hl,(FMT_AP)
    NEXTARG
    ld (FMT_AP),hl
    ex de,hl
    pop de
    ret
fmt_few:
    ld hl,m_few                 ; (the core's message: CORE error reads it)
    ld de,UNBOUND
    CORE error

;; fmt_index: A = how many arguments have been taken
fmt_index:
    ld a,(FMT_AT)
    ld hl,FMT_AN
    sub (hl)
    ret

;; fmt_goto: A = an argument's index -> the next to be taken
fmt_goto:
    ld c,a
    ld a,(FMT_AT)
    sub c
    jr c,fmt_few
    ld (FMT_AN),a
    ld hl,(FMT_A0)
    ld b,0
    or a
    sbc hl,bc
    sbc hl,bc
    ld (FMT_AP),hl
    ret

;; fmt_frame: HL = a list -> its elements pushed onto the stack, the
;; arguments now (255 at most). The caller saves FMT_A0, FMT_AP, FMT_AN
;; first, and drops them after with SP = FMT_A0 + 2.
fmt_frame:
    pop de
    ld (FMT_RET),de
    ld a,l
    and 3
    jr nz,.bad
    ex de,hl                    ; DE = the list
    ld hl,-2
    add hl,sp
    ld (FMT_A0),hl
    ld (FMT_AP),hl
    ld b,0
.l:
    ld a,d
    or e
    jr z,.done
    ld a,e
    and 3
    jr nz,.done                 ; a dotted end
    ld a,b
    inc a
    jr z,.done
    ld b,a
    ex de,hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push de                     ; the car
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; on to the cdr
    jr .l
.done:
    ld a,b
    ld (FMT_AN),a
    ld (FMT_AT),a
    ld hl,(FMT_RET)
    jp (hl)
.bad:
    ex de,hl
    ld hl,m_notlist
    CORE error

;; fmt_col: A = the column the output is at (0 the first). BC, DE kept
fmt_col:
    ld a,(V_OUTMODE)
    or a
    ld a,(V_OUTCOL)
    ret nz
    push hl
    call TXT_GET_CURSOR
    ld a,h
    pop hl
    dec a
    ret

;; fmt_pad: C times the character E. HL kept
fmt_pad:
    inc c
.l:
    dec c
    ret z
    ld a,e
    call lputc
    jr .l

;; ---------------------------------------------------------------------------
;; PRINTING AN ARGUMENT: a printer (IX) is called with HL = the argument;
;; fmt_field pads what it prints to a width

;; fmt_field: HL = an object, IX = its printer, D = the width, E = the pad
;; character, B bit 0: pad on the left
fmt_field:
    ld a,d
    or a
    jp z,lcall_ix               ; no width
    push bc
    push de
    push hl
    push ix
    call fmt_width              ; A = the characters it takes
    pop ix
    pop hl
    pop de
    pop bc
    sub d
    jp nc,lcall_ix              ; no room to pad: as it is
    neg
    ld c,a                      ; C = how many to pad
    bit 0,b
    jr z,.right
    call fmt_pad
    jp lcall_ix
.right:
    push bc
    push de
    call lcall_ix
    pop de
    pop bc
    jr fmt_pad

;; fmt_width: HL = an object, IX = its printer -> A = how many characters
;; it prints (255 at most), printing nothing
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
    call lcall_ix
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

;; the printers
fmt_princ:
    CORE princ
    ret
fmt_prin1:
    CORE prin1
    ret
fmt_pr_nil:
    ld a,"("
    call lputc
    ld a,")"
    jp lputc

;; ~A ~S
fmt_s:
    ld ix,fmt_prin1
    jr fmt_as
fmt_a:
    ld ix,fmt_princ
fmt_as:
    call fmt_arg
    ld a,h
    or l
    jr nz,.go
    ld a,(FMT_FL)
    rra
    jr nc,.go
    ld ix,fmt_pr_nil            ; ~:A of NIL
.go:
    ld a,3
    call fmt_padp
    ld a,(FMT_FL)
    rra
    ld b,a                      ; ~@A: pad on the left
    call fmt_field
    jp fmt_run

;; ~C
fmt_c:
    call fmt_arg
    ld ix,fmt_princ
    ld a,(FMT_FL)
    bit 1,a
    jr z,.go
    ld ix,fmt_prin1
.go:
    call lcall_ix
    jp fmt_run

;; ~D ~B ~O ~X, and ~nR
fmt_d:
    ld a,10
    jr fmt_base
fmt_b:
    ld a,2
    jr fmt_base
fmt_o:
    ld a,8
    jr fmt_base
fmt_x:
    ld a,16
fmt_base:
    ld (FMT_RADIX),a
fmt_num:
    call fmt_arg
    ld ix,fmt_dnum
    ld a,1
    call fmt_padp
    ld b,1
    call fmt_field
    jp fmt_run

fmt_r:
    ld a,(FMT_P)
    cp 255
    jr z,.words
    cp 2
    jp c,fmt_bad
    cp 37
    jp nc,fmt_bad
    ld (FMT_RADIX),a
    ld hl,FMT_P+1               ; the rest are ~D's
    ld de,FMT_P
    ld bc,NPARAMS-1
    ldir
    ld a,255
    ld (de),a
    jr fmt_num
.words:
    call fmt_arg
    ld ix,fmt_princ
    bit 0,l
    jr z,.go                    ; not an integer
    ld ix,fmt_roman
    ld a,(FMT_FL)
    bit 1,a
    jr nz,.go
    ld ix,fmt_cardinal
.go:
    call lcall_ix
    jp fmt_run

;; fmt_dnum: ~D's printer. A fixnum in FMT_RADIX; a whole float in base 10
;; as an integer; anything else as ~A
fmt_dnum:
    bit 0,l
    jr nz,fmt_int
    push hl
    CORE is_float
    pop hl
    jp nz,fmt_princ
    ld a,(FMT_RADIX)
    cp 10
    jp nz,fmt_princ
    push hl
    call fl_digits
    pop hl
    jr z,.whole                 ; 0
    ld a,(FL_K)
    bit 7,a
    jp nz,fmt_princ             ; under 1: not whole
    ld b,a
    ld a,(FL_LAST)
    cp b
    jr z,.whole
    jp nc,fmt_princ             ; a digit after the point
.whole:
    ld a,(FMT_FL)
    ld c,a
    and 2                       ; @: bit 1, a "+"
    bit 0,c
    jr z,.nc
    or 4                        ; :: bit 2, commas
.nc:
    or 1                        ; no point
    ld c,a
    ld b,0
    jp fl_fixed

;; fmt_int: HL = a fixnum -> printed in FMT_RADIX, with ~@D's sign and
;; ~:D's commas
fmt_int:
    sra h
    rr l
    bit 7,h
    jr z,.pos
    ld a,"-"
    call lputc
    xor a
    sub l
    ld l,a
    sbc a,a
    sub h
    ld h,a
    jr .digits
.pos:
    ld a,(FMT_FL)
    bit 1,a
    jr z,.digits
    ld a,"+"
    call lputc
.digits:
    ld b,0                      ; the digits, last first, onto the stack
.d:
    ld a,(FMT_RADIX)
    ld c,a
    call fmt_div
    add a,"0"
    cp "9"+1
    jr c,.dg
    add a,"A"-"9"-1
.dg:
    push af
    inc b
    ld a,h
    or l
    jr nz,.d
.p:
    pop af
    call lputc
    dec b
    ret z
    ld a,(FMT_FL)
    rra
    jr nc,.p                    ; no commas
    ld a,3
    ld c,3
    call fmt_param              ; the interval
    or a
    jr z,.p
    ld c,a
    ld a,b
.m:
    sub c
    jr z,.comma
    jr nc,.m
    jr .p
.comma:
    ld a,2
    ld c,","
    call fmt_param
    call lputc
    jr .p

;; fmt_div: HL = HL / C, A = the remainder (C under 128). B kept
fmt_div:
    push bc
    ld b,16
    xor a
.l:
    add hl,hl
    rla
    cp c
    jr c,.n
    sub c
    inc l
.n:
    djnz .l
    pop bc
    ret

;; ~F ~E ~G ~$
fmt_e:
    ld a,255
    ld (FMT_P+1),a              ; no d: as many digits as it has
    jr fmt_f
fmt_dollar:
    ld c,2
    xor a
    call fmt_param
    ld (FMT_P+1),a              ; d, 2 if not given
    ld a,(FMT_P+2)
    ld (FMT_P),a                ; the width
    ld a,(FMT_P+3)
    ld (FMT_P+4),a              ; the pad character
fmt_f:
    call fmt_arg
    call fmt_isnum
    ld ix,fmt_princ
    jr nz,.go
    ld ix,fmt_free
    ld a,(FMT_P+1)
    inc a
    jr z,.go
    ld ix,fmt_fixed
.go:
    ld a,4
    call fmt_padp
    ld b,1
    call fmt_field
    jp fmt_run

;; fmt_isnum: HL -> Z if it is a number. HL kept
fmt_isnum:
    bit 0,l
    jr z,.f
    cp a
    ret
.f:
    push hl
    CORE is_float
    pop hl
    ret

;; fmt_fixed: ~w,dF's printer
fmt_fixed:
    ld a,(FMT_P+1)
    ld b,a
    ld a,(FMT_FL)
    and 2
    ld c,a
    jp fl_fixed

;; fmt_free: ~F's printer without d: as print shows it, a fixnum with .0
fmt_free:
    ld a,(FMT_FL)
    bit 1,a
    jr z,.go
    push hl                     ; ~@F: a "+" unless negative
    call fl_arg
    pop hl
    ld a,(V_FA+3)
    rla
    jr c,.go
    ld a,"+"
    call lputc
.go:
    bit 0,l
    jp z,ln_print
    CORE print_fixnum
    ld a,"."
    call lputc
    ld a,"0"
    jp lputc

;; ~P
fmt_plural:
    ld a,(FMT_FL)
    rra
    jr nc,.arg
    call fmt_index              ; ~:P: the argument before again
    or a
    jp z,fmt_few
    dec a
    call fmt_goto
.arg:
    call fmt_arg
    ld de,3                     ; 1
    or a
    sbc hl,de
    ld a,(FMT_FL)
    ld hl,fmt_s_y
    jr z,.one
    ld hl,fmt_s_ies
    bit 1,a
    jr nz,.puts
    ld hl,fmt_s_s
.puts:
    call lputs
    jp fmt_run
.one:
    bit 1,a
    jr nz,.puts
    jp fmt_run
fmt_s_y:    db "y",0
fmt_s_ies:  db "ie"
fmt_s_s:    db "s",0

;; ~% ~& ~| ~~
fmt_nl:
    ld c,1
    xor a
    call fmt_param
    ld b,a
fmt_nls:
    inc b
.l:
    dec b
    jp z,fmt_run
    push bc
    CORE newline
    pop bc
    jr .l
fmt_fresh:
    ld c,1
    xor a
    call fmt_param
    ld b,a
    or a
    jp z,fmt_run
    call fmt_col
    or a
    jr nz,fmt_nls
    dec b
    jr fmt_nls
fmt_page:
    ld a,12
    jr fmt_rep
fmt_tilde:
    ld a,#7E
;; fmt_rep: A printed P0 times (once if not given)
fmt_rep:
    push af
    ld c,1
    xor a
    call fmt_param
    ld c,a
    pop de
    ld e,d
    call fmt_pad
    jp fmt_run

;; ~T
fmt_t:
    ld a,(FMT_FL)
    bit 1,a
    jr nz,.rel
    ld c,1
    xor a
    call fmt_param
    ld d,a                      ; D = colnum
    ld c,1
    ld a,c
    call fmt_param
    ld e,a                      ; E = colinc
    call fmt_col
    sub d
    jr c,.to                    ; short of it: -A spaces
    inc e
    dec e
    jp z,fmt_run
.m:
    sub e                       ; past it: on to colnum + k * colinc
    jr nc,.m
.to:
    neg
    ld c,a
    ld e," "
    call fmt_pad
    jp fmt_run
.rel:
    ld c,1
    xor a
    call fmt_param
    push af                     ; colrel
    ld c,1
    ld a,c
    call fmt_param
    ld d,a                      ; colinc
    pop af
    ld c,a
    ld e," "
    call fmt_pad
    ld a,d
    or a
    jp z,fmt_run
    call fmt_col
.r:
    sub d
    jr nc,.r
    neg
    cp d
    jp z,fmt_run
    ld c,a
    call fmt_pad
    jp fmt_run

;; ~*
fmt_star:
    ld a,(FMT_FL)
    bit 1,a
    jr nz,.abs
    ld c,1
    xor a
    call fmt_param
    ld b,a                      ; n
    call fmt_index
    ld c,a
    ld a,(FMT_FL)
    rra
    ld a,c
    jr c,.back
    add a,b
    jp c,fmt_few
    jr .go
.back:
    sub b
    jr nc,.go
    xor a
    jr .go
.abs:
    ld c,0
    xor a
    call fmt_param
.go:
    call fmt_goto
    jp fmt_run

;; ~^
fmt_up:
    ld a,(FMT_P)
    cp 255
    jr nz,.p
    ld a,(FMT_AN)
.p:
    or a
    jp nz,fmt_run
    ld a,"^"
    ret

;; ~} ~] ~; ~): the end of a group, for whoever runs it
fmt_close:
    ret

;; ~newline
fmt_newline:
    cp 13
    jr nz,.nl
    call fmt_peek
    cp 10
    call z,fmt_next             ; CR LF
.nl:
    ld a,(FMT_FL)
    bit 1,a
    jr z,.noat
    push af
    CORE newline                ; ~@: the newline stays
    pop af
.noat:
    rra
    jp c,fmt_run                ; ~:: the blanks stay
.ws:
    call fmt_peek
    cp " "
    jr z,.skip
    cp 9
    jp nz,fmt_run
.skip:
    call fmt_next
    jr .ws

;; ---------------------------------------------------------------------------
;; GROUPS

;; fmt_pass: the control string passed over up to a ~; ~] ~} ~) of this
;; level -> A = which (FMT_FL its modifiers), 0 if the string ends first
fmt_pass:
    ld b,0                      ; how deep
.l:
    ld hl,(FMT_CN)
    ld a,h
    or l
    ret z
    call fmt_next
    cp #7E
    jr nz,.l
    ld a,1
    ld (FMT_SKIP),a
    push bc
    call fmt_parse
    pop bc
    ld hl,fmt_s_open
    call fmt_inset
    jr z,.in
    ld hl,fmt_s_close
    call fmt_inset
    jr z,.out
    cp ";"
    jr nz,.l
    inc b
    dec b
    ret z
    jr .l
.in:
    inc b
    jr .l
.out:
    inc b
    dec b
    ret z
    dec b
    jr .l
fmt_s_open:  db "[{(<",0
fmt_s_close: db "]})>",0

;; fmt_inset: Z if A is one of the characters at HL. A, BC kept
fmt_inset:
    push bc
    ld b,a
.l:
    ld a,(hl)
    or a
    jr z,.no
    cp b
    jr z,.yes
    inc hl
    jr .l
.no:
    inc a                       ; NZ
.yes:
    ld a,b
    pop bc
    ret

;; ~[ ~]
fmt_cond:
    ld a,(FMT_FL)
    bit 1,a
    jr nz,.at
    rra
    jr c,.colon
    ld a,(FMT_P)                ; ~n[: clause n
    cp 255
    jr nz,.n
    call fmt_arg                ; or the argument's
    bit 0,l
    jr z,.none
    sra h
    rr l
    ld a,h
    or a
    jr nz,.none
    ld a,l
.n:
    ld c,a
.sel:                           ; pass over C clauses
    ld a,c
    or a
    jr z,.run
    push bc
    call fmt_pass
    pop bc
    or a
    jp z,fmt_run
    cp "]"
    jp z,fmt_run                ; no such clause
    ld a,(FMT_FL)
    rra
    jr c,.run                   ; ~:;: the default
    dec c
    jr .sel
.run:
    call fmt_run
    cp ";"
    jr z,.rest
    cp "]"
    jp z,fmt_run
    ret                         ; ~^, or the end: on out
.rest:
    call fmt_pass               ; the clauses after it, to the ~]
    cp ";"
    jr z,.rest
    jp fmt_run
.none:
    ld c,255
    jr .sel
.colon:                         ; ~:[false~;true~]
    call fmt_arg
    ld a,h
    or l
    ld c,0
    jr z,.sel
    inc c
    jr .sel
.at:                            ; ~@[x~]: if the argument is true, for x
    call fmt_arg
    ld a,h
    or l
    jr z,.none
    call fmt_index
    dec a
    call fmt_goto
    ld c,0
    jr .sel

;; fmt_save: push FMT_A0, FMT_AP, FMT_AN and FMT_AT (call it, then
;; fmt_frame); fmt_drop: drop the frame and pop them again
macro FMTSAVE
    ld hl,(FMT_A0)
    push hl
    ld hl,(FMT_AP)
    push hl
    ld hl,(FMT_AN)
    push hl
mend
macro FMTDROP
    ld hl,(FMT_A0)
    inc hl
    inc hl
    ld sp,hl
    pop hl
    ld (FMT_AN),hl
    pop hl
    ld (FMT_AP),hl
    pop hl
    ld (FMT_A0),hl
mend

;; ~{ ~}
fmt_iter:
    ld hl,(FMT_BCP)             ; the enclosing ~{'s state
    push hl
    ld hl,(FMT_BCN)
    push hl
    ld hl,(FMT_ITN)
    push hl
    ld a,(FMT_P)
    ld (FMT_ITN),a
    ld a,(FMT_FL)
    ld (FMT_ITF),a
    ld hl,(FMT_CP)              ; the body
    ld (FMT_BCP),hl
    ld hl,(FMT_CN)
    ld (FMT_BCN),hl
    call fmt_pass
    cp "}"
    jp nz,fmt_bad
    ld a,(FMT_FL)
    rra
    jr nc,.n1
    ld hl,FMT_ITF
    set 2,(hl)                  ; ~:}: once at least
.n1:
    ld hl,(FMT_CN)              ; where to go on from
    push hl
    ld hl,(FMT_CP)
    push hl
    ld a,(FMT_ITF)
    bit 1,a
    jr nz,.rest
    call fmt_arg                ; ~{: over a list
    ex de,hl
    FMTSAVE
    ex de,hl
    call fmt_frame
    call fmt_loop
    FMTDROP
    jr .out
.rest:
    call fmt_loop               ; ~@{: over the arguments left
.out:
    pop hl
    ld (FMT_CP),hl
    pop hl
    ld (FMT_CN),hl
    pop hl
    ld (FMT_ITN),hl
    pop hl
    ld (FMT_BCN),hl
    pop hl
    ld (FMT_BCP),hl
    jp fmt_run

;; fmt_loop: the body over the arguments, as FMT_ITF says
fmt_loop:
    ld a,(FMT_ITF)
    ld c,a
.l:
    ld a,(FMT_AN)
    or a
    jr nz,.go
    bit 2,c
    ret z                       ; nothing left
.go:
    res 2,c
    ld a,(FMT_ITN)
    cp 255
    jr z,.nolimit
    or a
    ret z                       ; as many times as it may
    dec a
    ld (FMT_ITN),a
.nolimit:
    push bc
    ld hl,(FMT_BCP)
    ld (FMT_CP),hl
    ld hl,(FMT_BCN)
    ld (FMT_CN),hl
    ld a,(FMT_ITF)
    rra
    jr c,.sub
    ld a,(FMT_AN)
    push af
    call fmt_run
    pop bc                      ; B = how many were left before
    cp "^"
    jr z,.end
    ld a,(FMT_AN)
    cp b
    jr z,.end                   ; none taken: it would go on for ever
    pop bc
    jr .l
.end:
    pop bc
    ret
.sub:                           ; ~:{: each argument a list of arguments
    call fmt_arg
    ex de,hl
    FMTSAVE
    ex de,hl
    call fmt_frame
    call fmt_run                ; (~^ ends this one only)
    FMTDROP
    pop bc
    jr .l

;; ~? ~@?
fmt_ind:
    ld hl,(FMT_CN)
    push hl
    ld hl,(FMT_CP)
    push hl
    call fmt_arg
    call lstring
    ld (FMT_CP),hl
    ld (FMT_CN),bc
    ld a,(FMT_FL)
    bit 1,a
    jr nz,.at
    call fmt_arg                ; its arguments, a list
    ex de,hl
    FMTSAVE
    ex de,hl
    call fmt_frame
    call fmt_run
    FMTDROP
    jr .out
.at:
    call fmt_run                ; ~@?: the arguments left
.out:
    pop hl
    ld (FMT_CP),hl
    pop hl
    ld (FMT_CN),hl
    jp fmt_run

;; ~( ~): what is printed inside goes into 128 bytes on the stack, and from
;; there out in the case asked for
FMT_CASEBUF equ 128
fmt_case:
    ld a,(FMT_FL)
    push af
    ld hl,(V_OUTPTR)
    push hl
    ld hl,(V_OUTEND)
    push hl
    ld hl,(V_OUTCNT)
    push hl
    ld a,(V_OUTCOL)
    ld h,a
    ld a,(V_OUTMODE)
    ld l,a
    push hl
    ld hl,-FMT_CASEBUF
    add hl,sp
    ld sp,hl
    ld (V_OUTPTR),hl
    ld de,FMT_CASEBUF
    add hl,de
    ld (V_OUTEND),hl
    ld a,1
    ld (V_OUTMODE),a
    call fmt_run
    ld b,a                      ; B = what ended it
    ld ix,FMT_CASEBUF
    add ix,sp                   ; IX = what was saved, above the buffer
    ld de,(V_OUTPTR)            ; DE = the end of the text
    ld a,(ix+0)
    ld (V_OUTMODE),a
    ld a,(ix+1)
    ld (V_OUTCOL),a
    ld l,(ix+2)
    ld h,(ix+3)
    ld (V_OUTCNT),hl
    ld l,(ix+4)
    ld h,(ix+5)
    ld (V_OUTEND),hl
    ld l,(ix+6)
    ld h,(ix+7)
    ld (V_OUTPTR),hl
    ld c,(ix+9)                 ; the modifiers
    ld hl,0
    add hl,sp                   ; HL = the text
    push bc
    call fmt_conv
    pop af                      ; A = what ended it
    ld hl,FMT_CASEBUF+10
    add hl,sp
    ld sp,hl
    cp ")"
    jp z,fmt_run
    ret

;; fmt_conv: the characters from HL up to DE out, C the modifiers: none
;; lower case, : each word capitalised, @ the first word, :@ upper case
fmt_conv:
    ld b,0                      ; bit 0: in a word, bit 7: a word was seen
.l:
    or a
    push hl
    sbc hl,de
    pop hl
    ret nc
    ld a,(hl)
    inc hl
    call fmt_alnum
    jr c,.w
    res 0,b
    call lputc
    jr .l
.w:
    bit 0,c
    jr z,.nocolon
    bit 1,c
    jr nz,.up                   ; :@
    bit 0,b
    jr nz,.low
    set 0,b
    jr .up
.nocolon:
    bit 1,c
    jr z,.low
    bit 0,b
    jr nz,.low
    set 0,b
    bit 7,b
    jr nz,.low
    set 7,b
.up:
    cp "a"
    jr c,.out
    cp "z"+1
    jr nc,.out
    sub 32
    jr .out
.low:
    cp "A"
    jr c,.out
    cp "Z"+1
    jr nc,.out
    add a,32
.out:
    call lputc
    jr .l

;; fmt_alnum: C if A is a letter or a digit
fmt_alnum:
    cp "0"
    ccf
    ret nc
    cp "9"+1
    ret c
    cp "A"
    ccf
    ret nc
    cp "Z"+1
    ret c
    cp "a"
    ccf
    ret nc
    cp "z"+1
    ret

;; ---------------------------------------------------------------------------
;; ~R IN WORDS

;; fmt_cardinal: HL = a fixnum -> in words; ~:R ordinal
fmt_cardinal:
    ld a,(FMT_FL)
    and 1
    ld (FMT_LG),a
    sra h
    rr l
    ld a,h
    or l
    jr nz,.nz
    ld a,(FMT_LG)
    ld e,a
    xor a
    jp fw_word                  ; zero
.nz:
    bit 7,h
    jr z,.pos
    push hl
    ld hl,fw_s_neg
    call lputs
    pop hl
    xor a
    sub l
    ld l,a
    sbc a,a
    sub h
    ld h,a
.pos:
    ld de,1000
    ld b,0
.th:
    or a
    sbc hl,de
    jr c,.thd
    inc b
    jr .th
.thd:
    add hl,de                   ; HL = the rest under 1000
    ld a,b
    or a
    jr z,fw_hundreds
    ld a,(FMT_LG)
    push af
    xor a
    ld (FMT_LG),a               ; the thousands are never the end
    push hl
    ld l,b
    ld h,0
    call fw_hundreds
    ld hl,fw_s_thousand
    call lputs
    pop hl
    pop af
    ld (FMT_LG),a
    ld a,h
    or l
    jr z,fw_th
    ld a," "
    call lputc
;; fw_hundreds: HL = 1-999 in words; FMT_LG: the last one ordinal
fw_hundreds:
    ld b,0
    ld de,100
.h:
    or a
    sbc hl,de
    jr c,.hd
    inc b
    jr .h
.hd:
    add hl,de
    ld a,b
    or a
    jr z,fw_tens
    push hl
    ld e,0
    call fw_word
    ld hl,fw_s_hundred
    call lputs
    pop hl
    ld a,l
    or a
    jr z,fw_th
    ld a," "
    call lputc
;; fw_tens: L = 1-99
fw_tens:
    ld a,l
    cp 20
    jr c,.small
    ld b,0
.t:
    sub 10
    inc b
    cp 10
    jr nc,.t
    ld c,a                      ; C = the units, B = the tens
    ld e,0
    or a
    jr nz,.tw
    ld a,(FMT_LG)
    ld e,a
.tw:
    ld a,b
    add a,18                    ; twenty is word 20
    push bc
    call fw_word
    pop bc
    ld a,c
    or a
    ret z
    ld a,"-"
    call lputc
    ld a,c
.small:
    push af
    ld a,(FMT_LG)
    ld e,a
    pop af
    jr fw_word

;; fw_th: "th" if the number is ordinal
fw_th:
    ld a,(FMT_LG)
    or a
    ret z
fw_th1:
    ld hl,fw_s_th
    jp lputs

;; fw_word: A = a word's number (0-27), E = 1 for its ordinal
fw_word:
    ld c,a
    call fw_find
    bit 0,e
    jr z,fw_puts7
    ld a,c
    cp 20
    jr nc,.ty
    push hl
    ld hl,fw_ords
.o:
    ld a,(hl)
    inc hl
    cp #FF
    jr z,.reg
    cp c
    jr z,.irr
.sk:
    bit 7,(hl)
    inc hl
    jr z,.sk
    jr .o
.irr:
    pop de
    jr fw_puts7
.reg:
    pop hl
    call fw_puts7
    jr fw_th1
.ty:                            ; twenty -> twentieth
    ld a,(hl)
    bit 7,a
    jr nz,.ie
    call lputc
    inc hl
    jr .ty
.ie:
    ld hl,fw_s_ieth
    jp lputs

;; fw_find: C = a word's number -> HL = its text. C kept
fw_find:
    ld hl,fw_words
    ld b,c
    inc b
.l:
    dec b
    ret z
.s:
    bit 7,(hl)
    inc hl
    jr z,.s
    jr .l

;; fw_puts7: the text at HL, up to the character with bit 7 set
fw_puts7:
    ld a,(hl)
    and #7F
    call lputc
    bit 7,(hl)
    inc hl
    jr z,fw_puts7
    ret

fw_words:
    str "zero"
    str "one"
    str "two"
    str "three"
    str "four"
    str "five"
    str "six"
    str "seven"
    str "eight"
    str "nine"
    str "ten"
    str "eleven"
    str "twelve"
    str "thirteen"
    str "fourteen"
    str "fifteen"
    str "sixteen"
    str "seventeen"
    str "eighteen"
    str "nineteen"
    str "twenty"
    str "thirty"
    str "forty"
    str "fifty"
    str "sixty"
    str "seventy"
    str "eighty"
    str "ninety"
fw_ords:
    db 1 : str "first"
    db 2 : str "second"
    db 3 : str "third"
    db 5 : str "fifth"
    db 8 : str "eighth"
    db 9 : str "ninth"
    db 12 : str "twelfth"
    db #FF
fw_s_neg:       db "negative ",0
fw_s_hundred:   db " hundred",0
fw_s_thousand:  db " thousand",0
fw_s_th:        db "th",0
fw_s_ieth:      db "ieth",0

;; fmt_roman: HL = a fixnum -> in Roman numerals (~:@R without IV, IX...);
;; outside 1-3999 as ~D
fmt_roman:
    sra h
    rr l
    ld a,h
    or l
    jr z,.dec
    bit 7,h
    jr nz,.dec
    ld de,4000
    or a
    sbc hl,de
    add hl,de
    jr nc,.dec
    ld a,(FMT_FL)
    ld c,a
    ld ix,fr_table
.l:
    ld e,(ix+0)
    ld d,(ix+1)
    ld a,d
    or e
    ret z
    bit 0,c
    jr z,.use
    bit 0,(ix+4)
    jr nz,.next                 ; old Roman: no IV, IX, XL...
.use:
    or a
    sbc hl,de
    jr c,.back
    ld a,(ix+2)
    call lputc
    ld a,(ix+3)
    or a
    call nz,lputc
    jr .use
.back:
    add hl,de
.next:
    ld de,5
    add ix,de
    jr .l
.dec:
    add hl,hl
    inc hl
    xor a
    ld (FMT_FL),a
    ld a,10
    ld (FMT_RADIX),a
    jp fmt_int
fr_table:
    dw 1000 : db "M",0,0
    dw 900 : db "CM",1
    dw 500 : db "D",0,0
    dw 400 : db "CD",1
    dw 100 : db "C",0,0
    dw 90 : db "XC",1
    dw 50 : db "L",0,0
    dw 40 : db "XL",1
    dw 10 : db "X",0,0
    dw 9 : db "IX",1
    dw 5 : db "V",0,0
    dw 4 : db "IV",1
    dw 1 : db "I",0,0
    dw 0
