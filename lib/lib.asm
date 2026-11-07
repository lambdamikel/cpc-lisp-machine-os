;; CPC Lisp -- the library ROMs, and part 0 of them.
;;
;; Each part is a background ROM that does nothing at the ROM walk: the core
;; finds it by its signature and calls in through the trampoline
;; (src/xrom.asm has the whole arrangement). It is assembled against the
;; core's symbols (build/core.inc, made by tools/build.sh), so it can use the
;; core's constants and variables directly -- but the core's CODE only
;; through CORE, which selects the core's ROM around the call. One part
;; cannot call another's code; lib/common.asm, which each includes, has the
;; helpers they all need.
;;
;; A native function is a label preceded by a line
;;
;;     ;@ NAME MIN MAX label
;;
;; and Lisp text for a part is named in its main file by
;;
;;     ;@lisp file.lsp
;;
;; tools/mklib.py collects both into the part's symbol table, following the
;; main file's includes. Arguments arrive as for the core's subrs: fixed
;; arity up to 3 in HL, DE, BC, otherwise HL = &arg 0 and B = count (read
;; with NEXTARG). Return the value in HL.
;;
;; Anything handed to the core must be in RAM: the core cannot read this
;; ROM. Its messages (m_...) are the core's and can be passed as they are.
;;
;; Part 0 (this file): the text screen, graphics, sound, keys, strings, the
;; line editor, the pretty printer, the function editor, files. Part 1
;; (lib/lib2.asm): floats, format, and the functions written in Lisp.

    include "core.inc"
    include "macros.asm"

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
    dw lib_editor               ; the line editor
    dw 0                        ; no number routines
    assert $ == LIBHDR+LH_PART
    db 0                        ; part 0

;; The name has a space so that BASIC cannot call it as a command.
lib_names:
    db "LISP LIBRAR","Y"+#80
    db 0

    include "common.asm"

;; ---------------------------------------------------------------------------
;; THE TEXT SCREEN (moved here from the core)

;@ CLS 0 0 lf_cls
lf_cls:
    call TXT_CLEAR_WINDOW
    jp lnil

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
    jp lnil

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
    jp nz,str_long
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
    jp lstr_result

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
;@ %CONCATENATE 1 255 lf_concatenate
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
;@ %SUBSEQ 2 3 lf_subseq
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
    include "strings.asm"
    include "libtab.asm"

lib_end:
    print "LIBRARY 1 used: ",lib_end-#C000," bytes, free: ",#10000-lib_end
    assert lib_end <= #10000
    defs #10000-$,#FF
