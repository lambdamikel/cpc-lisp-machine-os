;; CPC Lisp -- the library ROM.
;;
;; A background ROM that does nothing at the ROM walk: the core finds it by
;; its signature and calls in through the trampoline (src/xrom.asm has the
;; whole arrangement). It is assembled against the core's symbols
;; (build/core.inc, made by tools/build.sh), so it can use the core's
;; constants and variables directly -- but the core's CODE only through
;; CORE, which selects the core's ROM around the call.
;;
;; A native function is a label preceded by a line
;;
;;     ;@ NAME MIN MAX label
;;
;; which tools/mklib.py collects into the symbol table, with the Lisp-defined
;; functions from lib/*.lsp. Arguments arrive as for the core's subrs: fixed
;; arity up to 3 in HL, DE, BC, otherwise HL = &arg 0 and B = count (read
;; with NEXTARG). Return the value in HL.
;;
;; Anything handed to the core must be in RAM: the core cannot read this
;; ROM. Its messages (m_...) are the core's and can be passed as they are.

    include "core.inc"
    include "macros.asm"

macro CORE routine
    ld ix,{routine}
    call CORECALL
mend

;; firmware used only here
GRA_MOVE_ABSOLUTE   equ #BBC0
GRA_MOVE_RELATIVE   equ #BBC3
GRA_ASK_CURSOR      equ #BBC6
GRA_SET_ORIGIN      equ #BBC9
GRA_CLEAR_WINDOW    equ #BBDB
GRA_SET_PEN         equ #BBDE
GRA_SET_PAPER       equ #BBE4
GRA_PLOT_ABSOLUTE   equ #BBEA
GRA_PLOT_RELATIVE   equ #BBED
GRA_TEST_ABSOLUTE   equ #BBF0
GRA_TEST_RELATIVE   equ #BBF3
GRA_LINE_ABSOLUTE   equ #BBF6
GRA_LINE_RELATIVE   equ #BBF9
KM_WAIT_CHAR_L      equ #BB06
KM_READ_CHAR_L      equ #BB09
SOUND_QUEUE         equ #BCAA
KL_TIME_PLEASE      equ #BD0D

    org #C000
    db 1                        ; a background ROM
    db 0,2,0
    dw lib_names
    jp lib_init                 ; the ROM walk: nothing to do

    defs LIBHDR-$,0
    db "CPCLISPLIB"
    dw BUILD_ID
    dw lib_buckets
    dw lib_boot
    dw lib_dispatch
    dw lib_editor
    dw lib_numbers

;; The name has a space so that BASIC cannot call it as a command.
lib_names:
    db "LISP LIBRAR","Y"+#80
    db 0

lib_init:
    scf
    ret

;; lib_dispatch: called through the trampoline for every library function,
;; with HL = &arg 0, B = count and V_LIBFN = the function object. Checks
;; the count, puts fixed arguments in registers, jumps to the code.
lib_dispatch:
    push hl
    ld hl,(V_LIBFN)
    LDHLI                       ; its entry in this ROM
    push hl
    pop ix
    pop hl
    ld a,b
    cp (ix+LE_MIN)
    jr c,.args
    ld a,(ix+LE_MAX)
    cp b
    jr c,.args
    ld e,(ix+LE_ADDR)
    ld d,(ix+LE_ADDR+1)
    push de                     ; ret goes to the code
    ld a,(ix+LE_MIN)
    cp (ix+LE_MAX)
    ret nz                      ; variadic: HL and B as they are
    cp 4
    ret nc
    or a
    ret z
    dec a
    jr z,.one
    dec a
    jr z,.two
    push hl
    dec hl
    dec hl
    dec hl
    dec hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    pop hl
.two:
    push hl
    dec hl
    dec hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    pop hl
.one:
    LDHLI
    ret
.args:
    ld de,(V_LIBFN)
    ld hl,m_nargs
    CORE error

;; ---------------------------------------------------------------------------
;; helpers

;; lfix_hl, lfix_de: error unless a fixnum. All kept.
lfix_hl:
    bit 0,l
    ret nz
    ex de,hl
lfix_de:
    bit 0,e
    ret nz
    ld hl,m_notnum
    CORE error

;; lint_hl: a number in HL -> the plain number in HL, a float rounded.
;; lint_de likewise. All else kept.
lint_hl:
    bit 0,l
    jr z,.float
    sra h
    rr l
    ret
.float:
    push de
    ex de,hl
    call fl_plain
    pop de
    ret
lint_de:
    bit 0,e
    jr z,.float
    sra d
    rr e
    ret
.float:
    push hl
    call fl_plain
    ex de,hl
    pop hl
    ret

;; a plain number in HL -> a fixnum, assumed in range
ltag:
    add hl,hl
    inc hl
    ret

;; A -> a character object in HL
lchar:
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    inc hl
    inc hl
    ret

lnil:
    ld hl,NIL
    ret
lt:
    ld hl,S_T
    ret

lcall_ix:
    jp (ix)

;; lstring: HL = a string -> HL = its characters, BC = how many. An error
;; for anything else.
lstring:
    push hl
    CORE is_string
    pop hl
    jr nz,.bad
    LDHLI
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    ret
.bad:
    ex de,hl
    ld hl,m_notstr
    CORE error

;; ---------------------------------------------------------------------------
;; THE TEXT SCREEN (moved here from the core)

;@ CLS 0 0 lf_cls
lf_cls:
    call TXT_CLEAR_WINDOW
    jr lnil

;@ MODE 1 1 lf_mode
lf_mode:
    push hl
    call lint_hl
    ld a,l
    and 3
    call SCR_SET_MODE
    pop hl
    ret

;; (locate column row), from 1 as in BASIC
;@ LOCATE 2 2 lf_locate
lf_locate:
    call lint_hl
    call lint_de
    ld h,l
    ld l,e
    call TXT_SET_CURSOR
    jr lnil

;@ PEN 1 1 lf_pen
lf_pen:
    push hl
    call lint_hl
    ld a,l
    call TXT_SET_PEN
    pop hl
    ret

;@ PAPER 1 1 lf_paper
lf_paper:
    push hl
    call lint_hl
    ld a,l
    call TXT_SET_PAPER
    pop hl
    ret

;; (ink pen colour [colour2])
;@ INK 2 3 lf_ink
lf_ink:
    NEXTARG
    call lint_de
    push de
    NEXTARG
    call lint_de
    ld c,e
    ld a,b
    cp 3
    jr nz,.one
    NEXTARG
    call lint_de
    ld b,c
    ld c,e
    jr .set
.one:
    ld b,c
.set:
    pop de
    ld a,e
    call SCR_SET_INK
    jp lnil

;; (border colour [colour2])
;@ BORDER 1 2 lf_border
lf_border:
    NEXTARG
    call lint_de
    ld c,e
    ld a,b
    cp 2
    jr nz,.one
    NEXTARG
    call lint_de
    ld b,c
    ld c,e
    jr .set
.one:
    ld b,c
.set:
    call SCR_SET_BORDER
    jp lnil

;@ RESET 0 0 lf_reset
lf_reset:
    rst 0

;; ---------------------------------------------------------------------------
;; GRAPHICS, through the firmware's GRA pack: x 0-639, y 0-399 whatever the
;; mode, as in BASIC

;@ PLOT 2 3 lf_plot
lf_plot:
    ld ix,GRA_PLOT_ABSOLUTE
    jr gra_xy
;@ PLOTR 2 3 lf_plotr
lf_plotr:
    ld ix,GRA_PLOT_RELATIVE
    jr gra_xy
;@ DRAW 2 3 lf_draw
lf_draw:
    ld ix,GRA_LINE_ABSOLUTE
    jr gra_xy
;@ DRAWR 2 3 lf_drawr
lf_drawr:
    ld ix,GRA_LINE_RELATIVE
    jr gra_xy
;@ MOVE 2 3 lf_move
lf_move:
    ld ix,GRA_MOVE_ABSOLUTE
    jr gra_xy
;@ MOVER 2 3 lf_mover
lf_mover:
    ld ix,GRA_MOVE_RELATIVE

;; gra_xy: (x y [pen]) for the GRA routine IX, which takes DE = x, HL = y
gra_xy:
    NEXTARG
    call lint_de
    push de                     ; x
    NEXTARG
    call lint_de
    push de                     ; y
    ld a,b
    cp 3
    jr nz,.nopen
    NEXTARG
    call lint_de
    ld a,e
    push ix
    call GRA_SET_PEN
    pop ix
.nopen:
    pop hl
    pop de
    call lcall_ix
    jp lnil

;; (test x y) -> the pen of that pixel; testr likewise, relative
;@ TEST 2 2 lf_test
lf_test:
    ld ix,GRA_TEST_ABSOLUTE
    jr gra_test
;@ TESTR 2 2 lf_testr
lf_testr:
    ld ix,GRA_TEST_RELATIVE
gra_test:
    call lint_hl
    call lint_de
    ex de,hl
    call lcall_ix
    ld l,a
    ld h,0
    jp ltag

;@ ORIGIN 2 2 lf_origin
lf_origin:
    call lint_hl
    call lint_de
    ex de,hl
    call GRA_SET_ORIGIN
    jp lnil

;; (clg [paper])
;@ CLG 0 1 lf_clg
lf_clg:
    ld a,b
    or a
    jr z,.clear
    NEXTARG
    call lint_de
    ld a,e
    call GRA_SET_PAPER
.clear:
    call GRA_CLEAR_WINDOW
    jp lnil

;@ GRAPHICS-PEN 1 1 lf_gpen
lf_gpen:
    push hl
    call lint_hl
    ld a,l
    call GRA_SET_PEN
    pop hl
    ret

;@ GRAPHICS-PAPER 1 1 lf_gpaper
lf_gpaper:
    push hl
    call lint_hl
    ld a,l
    call GRA_SET_PAPER
    pop hl
    ret

;@ XPOS 0 0 lf_xpos
lf_xpos:
    call GRA_ASK_CURSOR
    ex de,hl
    jp ltag
;@ YPOS 0 0 lf_ypos
lf_ypos:
    call GRA_ASK_CURSOR
    jp ltag

;; ---------------------------------------------------------------------------
;; SOUND

;; (sound channels period [duration [volume [envelope [tone-envelope
;; [noise]]]]]) -- BASIC's SOUND: channels 1 A, 2 B, 4 C (add them for
;; more), period 0-4095, duration in 1/100 s (default 20), volume 0-15
;; (default 12). Waits while the channel's queue is full.
;@ SOUND 2 7 lf_sound
lf_sound:
    push hl
    ld hl,LIBSCR
    ld (hl),0                   ; channels
    inc hl
    ld (hl),0                   ; envelope
    inc hl
    ld (hl),0                   ; tone envelope
    inc hl
    ld (hl),0                   ; period
    inc hl
    ld (hl),0
    inc hl
    ld (hl),0                   ; noise
    inc hl
    ld (hl),12                  ; volume
    inc hl
    ld (hl),20                  ; duration
    inc hl
    ld (hl),0
    pop hl
    NEXTARG
    call lint_de
    ld a,e
    ld (LIBSCR+0),a
    NEXTARG
    call lint_de
    ld (LIBSCR+3),de
    ld a,b
    sub 2
    jr z,.go
    ld b,a
    NEXTARG
    call lint_de
    ld (LIBSCR+7),de
    dec b
    jr z,.go
    NEXTARG
    call lint_de
    ld a,e
    ld (LIBSCR+6),a
    dec b
    jr z,.go
    NEXTARG
    call lint_de
    ld a,e
    ld (LIBSCR+1),a
    dec b
    jr z,.go
    NEXTARG
    call lint_de
    ld a,e
    ld (LIBSCR+2),a
    dec b
    jr z,.go
    NEXTARG
    call lint_de
    ld a,e
    ld (LIBSCR+5),a
.go:
    ld hl,LIBSCR
    call SOUND_QUEUE
    jp c,lnil
    CORE poll_esc               ; full: wait, but let ESC out
    call MC_WAIT_FLYBACK
    jr .go

;; ---------------------------------------------------------------------------
;; KEYS AND TIME

;; (inkey) -> the next character typed, or NIL if there is none
;@ INKEY 0 0 lf_inkey
lf_inkey:
    call KM_READ_CHAR_L
    jp nc,lnil
    jp lchar

;; (wait-key) -> the next character typed, waiting for it
;@ WAIT-KEY 0 0 lf_wait_key
lf_wait_key:
    call KM_WAIT_CHAR_L
    jp lchar

;; (key-down-p key-number) -> T while that key is held (BASIC's INKEY)
;@ KEY-DOWN-P 1 1 lf_key_down_p
lf_key_down_p:
    call lint_hl
    ld a,l
    call KM_TEST_KEY
    jp z,lnil
    jp lt

;; (frame): wait for the next frame flyback, 1/50 s
;@ FRAME 0 0 lf_frame
lf_frame:
    call MC_WAIT_FLYBACK
    jp lnil

;; (time) -> the firmware's clock in 1/300 s, modulo 16384
;@ TIME 0 0 lf_time
lf_time:
    call KL_TIME_PLEASE
    res 7,h
    res 6,h
    jp ltag

;; ---------------------------------------------------------------------------
;; STRINGS AND CHARACTERS. Results are built in TOKBUF, so up to 255 long.

;; lstr_result: TOKBUF holds C characters -> a new string
lstr_result:
    ld b,0
    ld hl,TOKBUF
    CORE make_string
    ret

;@ STRING-UPCASE 1 1 lf_string_upcase
lf_string_upcase:
    ld e,0
    jr case_string
;@ STRING-DOWNCASE 1 1 lf_string_downcase
lf_string_downcase:
    ld e,1
case_string:
    push de
    call lstring
    ld a,b
    or a
    jr nz,str_long
    pop de
    push bc                     ; the length
    ld b,c
    ld c,e                      ; the direction
    ld de,TOKBUF
    inc b
    jr .next
.l:
    ld a,(hl)
    call case_char
    ld (de),a
    inc hl
    inc de
.next:
    djnz .l
    pop bc
    jr lstr_result
str_long:
    ld hl,m_toolong
    ld de,UNBOUND
    CORE error

;; case_char: A -> A upcased (C = 0) or downcased (C = 1)
case_char:
    bit 0,c
    jr nz,.down
    cp "a"
    ret c
    cp "z"+1
    ret nc
    sub #20
    ret
.down:
    cp "A"
    ret c
    cp "Z"+1
    ret nc
    add a,#20
    ret

;@ CHAR-UPCASE 1 1 lf_char_upcase
lf_char_upcase:
    ld c,0
    jr case_ch
;@ CHAR-DOWNCASE 1 1 lf_char_downcase
lf_char_downcase:
    ld c,1
case_ch:
    push hl
    CORE check_char
    pop hl
    srl h
    rr l
    srl h
    rr l
    ld a,l
    call case_char
    jp lchar

;; (concatenate 'string string...): the type is not looked at
;@ CONCATENATE 1 255 lf_concatenate
lf_concatenate:
    ld de,TOKBUF
    ld c,0                      ; the length so far
    dec b
    jr z,.done
    dec hl
    dec hl                      ; past the type
.arg:
    push bc                     ; B = arguments left, C = length so far
    push de                     ; where the next one goes
    NEXTARG
    push hl                     ; the argument pointer
    ex de,hl
    call lstring                ; HL = characters, BC = how many
    ld a,b
    or a
    jr nz,.long
    pop ix
    pop de
    ex (sp),hl                  ; L = length so far
    ld a,l
    add a,c
    jr c,.long
    ld l,a
    ex (sp),hl
    ld a,c
    or a
    jr z,.empty
    ld b,0
    ldir
.empty:
    pop bc
    push ix
    pop hl
    djnz .arg
.done:
    jp lstr_result
.long:
    jp str_long

;; (subseq string start [end]): strings only, for now
;@ SUBSEQ 2 3 lf_subseq
lf_subseq:
    NEXTARG
    push de                     ; the string
    NEXTARG
    call lint_de
    push de                     ; start
    ld de,-1                    ; no end
    ld a,b
    cp 3
    jr nz,.noend
    NEXTARG
    call lint_de
.noend:
    pop bc                      ; start
    pop hl                      ; the string
    push de
    push bc
    call lstring                ; HL = characters, BC = length
    pop de                      ; start
    ex (sp),hl                  ; HL = end, the characters on the stack
    bit 7,h
    jr z,.hasend
    ld l,c
    ld h,b
.hasend:
    ld a,c
    sub l
    ld a,b
    sbc a,h
    jr c,.bad                   ; end past the length
    bit 7,d
    jr nz,.bad
    or a
    sbc hl,de                   ; end - start
    jr c,.bad
    ld a,h
    or a
    jr nz,.long
    ld c,l
    ld b,0
    pop hl
    add hl,de
    ld de,TOKBUF
    ld a,c
    or a
    jr z,.e
    ldir
.e:
    ld c,a
    jp lstr_result
.bad:
    ld hl,m_index
    ld de,UNBOUND
    CORE error
.long:
    jp str_long

;; (parse-integer string) -> the number, or NIL if it is not one
;@ PARSE-INTEGER 1 1 lf_parse_integer
lf_parse_integer:
    call lstring
    ld a,b
    or a
    jp nz,lnil
    ld b,c
    ld a,c
    or a
    jp z,lnil
    ld de,TOKBUF
    push bc
    ld b,0
    ldir
    pop bc
    CORE parse_int
    jp c,lnil
    ret

;; ---------------------------------------------------------------------------
;; LISTS

;; (nreconc list tail): list reversed, in place, onto tail
;@ NRECONC 2 2 lf_nreconc
lf_nreconc:
    CORE nreverse_onto
    ret

    include "editor.asm"
    include "pp.asm"
    include "fr.asm"
    include "fed.asm"
    include "disc.asm"
    include "float.asm"
    include "libtab.asm"

lib_end:
    print "LIBRARY used: ",lib_end-#C000," bytes, free: ",#10000-lib_end
    assert lib_end <= #10000
    defs #10000-$,#FF
