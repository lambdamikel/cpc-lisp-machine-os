;; CPC Lisp -- more graphics, text, sound and machine functions (library
;; ROM, part 0): what BASIC has beyond plot and draw, and a little more.
;; All through firmware vectors below &BD37, the same on every CPC.

TXT_SET_GRAPHIC     equ #BB63
TXT_WIN_ENABLE      equ #BB66
TXT_GET_CURSOR_L    equ #BB78
TXT_SET_BACK        equ #BB9F
SCR_SET_FLASHING    equ #BC3E
SCR_ACCESS          equ #BC59
KM_GET_JOYSTICK     equ #BB24
SOUND_RELEASE       equ #BCB3
SOUND_CHECK         equ #BCAD
SOUND_HOLD          equ #BCB6
SOUND_CONTINUE      equ #BCB9
SOUND_AMPL_ENVELOPE equ #BCBC
SOUND_TONE_ENVELOPE equ #BCBF

;; gx_plot, gx_move, gx_line: DE = x, HL = y, IX kept
gx_plot:
    push ix
    call GRA_PLOT_ABSOLUTE
    pop ix
    ret
gx_move:
    push ix
    call GRA_MOVE_ABSOLUTE
    pop ix
    ret
gx_line:
    push ix
    call GRA_LINE_ABSOLUTE
    pop ix
    ret

;; gx_ints: HL = &the first argument, C = how many to read -> them on the
;; stack, as integers, the first deepest; HL past them. B kept. Returns
;; with them pushed: the caller pops.
gx_ints:
    pop ix                      ; the return address
.l:
    NEXTARG
    call lint_de                ; (B, C kept)
    push de
    dec c
    jr nz,.l
    jp (ix)

;; gx_pen: HL = &the next argument, A = B = how many there are, C = the
;; count with a pen -> the graphics pen set if it is there. IX kept.
gx_pen:
    cp c
    ret nz
    NEXTARG
    call lint_de
    ld a,e
    push ix
    call GRA_SET_PEN
    pop ix
    ret

;; ---------------------------------------------------------------------------
;; CIRCLES

CI_X    equ 0                   ; the centre
CI_Y    equ 2
CI_DX   equ 4                   ; the midpoint walk: x,
CI_DY   equ 6                   ;   y,
CI_E    equ 8                   ;   the error
CI_F    equ 10                  ; 0 a circle, 1 a disc
CI_A    equ 12                  ; ci_pair's half-width
CI_YY   equ 14                  ; ci_row's y
CI_SIZE equ 16

;; (circle x y r [pen]), (disc x y r [pen]): a circle, a filled one. The
;; disc draws each pixel row once (at its even y), so it inverts cleanly
;; with (ink-mode 1): a ball can be drawn and taken off again.
;@ CIRCLE 3 4 lf_circle
lf_circle:
    xor a
    jr gx_circle
;@ DISC 3 4 lf_disc
lf_disc:
    ld a,1
gx_circle:
    push af
    ld c,3
    call gx_ints                ; x y r on the stack
    ld a,b
    ld c,4
    call gx_pen
    pop bc                      ; r
    pop hl                      ; y
    pop de                      ; x
    pop af
    ld ix,-CI_SIZE
    add ix,sp
    ld sp,ix
    ld (ix+CI_F),a
    ld (ix+CI_X),e
    ld (ix+CI_X+1),d
    ld (ix+CI_Y),l
    ld (ix+CI_Y+1),h
    ld (ix+CI_DX),c
    ld (ix+CI_DX+1),b
    xor a
    ld (ix+CI_DY),a
    ld (ix+CI_DY+1),a
    ld hl,1
    or a
    sbc hl,bc
    ld (ix+CI_E),l              ; 1 - r
    ld (ix+CI_E+1),h
.loop:
    ld l,(ix+CI_DX)
    ld h,(ix+CI_DX+1)
    ld e,(ix+CI_DY)
    ld d,(ix+CI_DY+1)
    or a
    sbc hl,de
    jp m,.done                  ; until x < y
    bit 0,(ix+CI_F)
    jr nz,.disc
    ld l,(ix+CI_DY)             ; (x, y) and (y, x): all eight octants
    ld h,(ix+CI_DY+1)
    ld e,(ix+CI_DX)
    ld d,(ix+CI_DX+1)
    call ci_pair
    ld l,(ix+CI_DX)
    ld h,(ix+CI_DX+1)
    ld e,(ix+CI_DY)
    ld d,(ix+CI_DY+1)
    call ci_pair
    jr .step
.disc:                          ; the rows cy +- y, x wide, every step
    ld e,(ix+CI_DX)
    ld d,(ix+CI_DX+1)
    ld l,(ix+CI_DY)
    ld h,(ix+CI_DY+1)
    call di_rows
    bit 7,(ix+CI_E+1)
    jr nz,.step                 ; x stays: the rows cy +- x get wider yet
    ld l,(ix+CI_DX)             ; x moves in after this: rows cy +- x, as
    ld h,(ix+CI_DX+1)           ;   wide as they get (y), unless they are
    ld e,(ix+CI_DY)             ;   the rows just drawn
    ld d,(ix+CI_DY+1)
    or a
    sbc hl,de
    jr z,.step
    add hl,de
    call di_rows
.step:
    ld l,(ix+CI_DY)             ; y + 1
    ld h,(ix+CI_DY+1)
    inc hl
    ld (ix+CI_DY),l
    ld (ix+CI_DY+1),h
    ld e,(ix+CI_E)
    ld d,(ix+CI_E+1)
    bit 7,d
    jr z,.xdec
    add hl,hl                   ; error < 0: error + 2y + 1
    inc hl
    add hl,de
    jr .err
.xdec:
    ld c,(ix+CI_DX)             ; else x - 1, error + 2(y - x) + 1
    ld b,(ix+CI_DX+1)
    dec bc
    ld (ix+CI_DX),c
    ld (ix+CI_DX+1),b
    or a
    sbc hl,bc
    add hl,hl
    inc hl
    add hl,de
.err:
    ld (ix+CI_E),l
    ld (ix+CI_E+1),h
    jp .loop
.done:
    ld hl,CI_SIZE
    add hl,sp
    ld sp,hl
    jp lnil

;; di_rows: DE = a, HL = b -> the disc's rows cy + b and cy - b (once if b
;; is 0), from cx - a to cx + a; only an even y draws a pixel row
di_rows:
    ld (ix+CI_A),e
    ld (ix+CI_A+1),d
    ld e,(ix+CI_Y)
    ld d,(ix+CI_Y+1)
    push hl
    add hl,de
    call .row                   ; cy + b
    pop de
    ld a,d
    or e
    ret z
    ld l,(ix+CI_Y)
    ld h,(ix+CI_Y+1)
    or a
    sbc hl,de                   ; cy - b
.row:
    bit 0,l
    ret nz
    jp ci_row

;; ci_pair: DE = a, HL = b -> the points (cx +- a, cy +- b), or the lines
;; between them for a disc
ci_pair:
    ld (ix+CI_A),e
    ld (ix+CI_A+1),d
    ld e,(ix+CI_Y)
    ld d,(ix+CI_Y+1)
    push hl
    add hl,de
    call ci_row                 ; cy + b
    pop de
    ld l,(ix+CI_Y)
    ld h,(ix+CI_Y+1)
    or a
    sbc hl,de                   ; cy - b
;; ci_row: HL = y -> (cx - a, y) and (cx + a, y), or the line between
ci_row:
    ld (ix+CI_YY),l
    ld (ix+CI_YY+1),h
    ld l,(ix+CI_X)
    ld h,(ix+CI_X+1)
    ld e,(ix+CI_A)
    ld d,(ix+CI_A+1)
    or a
    sbc hl,de
    ex de,hl                    ; DE = cx - a
    ld l,(ix+CI_YY)
    ld h,(ix+CI_YY+1)
    bit 0,(ix+CI_F)
    jr nz,.line
    call gx_plot
    call .right
    jp gx_plot
.line:
    call gx_move
    call .right
    jp gx_line
.right:                         ; DE = cx + a, HL = y
    ld l,(ix+CI_X)
    ld h,(ix+CI_X+1)
    ld e,(ix+CI_A)
    ld d,(ix+CI_A+1)
    add hl,de
    ex de,hl
    ld l,(ix+CI_YY)
    ld h,(ix+CI_YY+1)
    ret

;; ---------------------------------------------------------------------------
;; BOXES

BX_X1   equ 6                   ; on the stack, under the return address
BX_Y1   equ 4                   ;   and the flag
BX_X2   equ 2
BX_Y2   equ 0

;; (box x1 y1 x2 y2 [pen]), (fill-box x1 y1 x2 y2 [pen]): a rectangle's
;; edges, or all of it; fill-box draws each pixel row once, so it inverts
;; cleanly with (ink-mode 1)
;@ BOX 4 5 lf_box
lf_box:
    xor a
    jr gx_box
;@ FILL-BOX 4 5 lf_fill_box
lf_fill_box:
    ld a,1
gx_box:
    push af
    ld c,4
    call gx_ints                ; x1 y1 x2 y2
    ld a,b
    ld c,5
    call gx_pen
    ld ix,0
    add ix,sp
    ld a,(ix+9)                 ; the flag, under the four (A, of AF)
    or a
    jr nz,.fill
    ld e,(ix+BX_X1)             ; the edges
    ld d,(ix+BX_X1+1)
    ld l,(ix+BX_Y1)
    ld h,(ix+BX_Y1+1)
    call gx_move
    ld e,(ix+BX_X2)
    ld d,(ix+BX_X2+1)
    ld l,(ix+BX_Y1)
    ld h,(ix+BX_Y1+1)
    call gx_line
    ld e,(ix+BX_X2)
    ld d,(ix+BX_X2+1)
    ld l,(ix+BX_Y2)
    ld h,(ix+BX_Y2+1)
    call gx_line
    ld e,(ix+BX_X1)
    ld d,(ix+BX_X1+1)
    ld l,(ix+BX_Y2)
    ld h,(ix+BX_Y2+1)
    call gx_line
    ld e,(ix+BX_X1)
    ld d,(ix+BX_X1+1)
    ld l,(ix+BX_Y1)
    ld h,(ix+BX_Y1+1)
    call gx_line
    jr .out
.fill:
    ld l,(ix+BX_Y1)             ; y1 the lower: swap them if not
    ld h,(ix+BX_Y1+1)
    ld e,(ix+BX_Y2)
    ld d,(ix+BX_Y2+1)
    push hl
    or a
    sbc hl,de
    pop hl
    jp m,.ordered
    ex de,hl
.ordered:
    ld a,l                      ; a pixel row is two y values: from the
    and #FE                     ;   even one of the lowest row to the odd
    ld l,a                      ;   one of the highest, two at a time
    set 0,e
    ld (ix+BX_Y2),e
    ld (ix+BX_Y2+1),d
.row:
    ld (ix+BX_Y1),l
    ld (ix+BX_Y1+1),h
    ld e,(ix+BX_X1)
    ld d,(ix+BX_X1+1)
    call gx_move
    ld e,(ix+BX_X2)
    ld d,(ix+BX_X2+1)
    ld l,(ix+BX_Y1)
    ld h,(ix+BX_Y1+1)
    call gx_line
    ld l,(ix+BX_Y1)
    ld h,(ix+BX_Y1+1)
    inc hl
    inc hl
    ld e,(ix+BX_Y2)
    ld d,(ix+BX_Y2+1)
    ex de,hl
    push hl
    or a
    sbc hl,de
    pop hl
    ex de,hl
    jp p,.row                   ; while y <= the top
.out:
    ld hl,10
    add hl,sp
    ld sp,hl
    jp lnil

;; ---------------------------------------------------------------------------
;; GRAPHICS AND TEXT MODES

;; (ink-mode n): how graphics are drawn: 0 normally, 1 XOR, 2 AND, 3 OR
;@ INK-MODE 1 1 lf_ink_mode
lf_ink_mode:
    push hl
    call lint_hl
    ld a,l
    and 3
    call SCR_ACCESS
    pop hl
    ret

;; (window left right top bottom): the text window, from 1, as in BASIC
;@ WINDOW 4 4 lf_window
lf_window:
    ld c,4
    call gx_ints
    pop de                      ; E = bottom
    pop hl                      ; L = top
    pop bc
    ld d,c                      ; D = right
    pop bc
    ld h,c                      ; H = left
    dec h
    dec d
    dec l
    dec e
    call TXT_WIN_ENABLE
    jp lnil

;; (tag on): T sends text to the graphics cursor (BASIC's TAG), NIL back
;@ TAG 1 1 lf_tag
lf_tag:
    ld a,h
    or l
    push hl
    call TXT_SET_GRAPHIC
    pop hl
    ret

;; (transparent on): T draws text without its paper, NIL with
;@ TRANSPARENT 1 1 lf_transparent
lf_transparent:
    ld a,h
    or l
    jr z,.set
    ld a,1
.set:
    push hl
    call TXT_SET_BACK
    pop hl
    ret

;; (flash-speed on off): how long each colour of a flashing ink shows, in
;; 1/50 s (BASIC's SPEED INK)
;@ FLASH-SPEED 2 2 lf_flash_speed
lf_flash_speed:
    call lint_hl
    call lint_de
    ld h,l
    ld l,e
    call SCR_SET_FLASHING
    jp lnil

;; (text-cursor) -> (column row), from 1, as BASIC's POS and VPOS
;@ TEXT-CURSOR 0 0 lf_text_cursor
lf_text_cursor:
    call TXT_GET_CURSOR_L
    push hl
    ld l,h
    ld h,0
    add hl,hl
    inc hl                      ; the column
    ex (sp),hl
    ld h,0
    add hl,hl
    inc hl                      ; the row
    ld de,NIL
    CORE cons
    ex de,hl
    pop hl
    CORE cons
    ret

;; ---------------------------------------------------------------------------
;; THE MACHINE

;; (joystick [n]) -> joystick n's state (0 or 1): 1 up, 2 down, 4 left,
;; 8 right, 16 fire 2, 32 fire 1, added
;@ JOYSTICK 0 1 lf_joystick
lf_joystick:
    ld c,0
    ld a,b
    or a
    jr z,.read
    NEXTARG
    call lint_de
    ld c,e
.read:
    push bc
    call KM_GET_JOYSTICK
    pop bc
    ld a,c
    or a
    ld a,h
    jr z,.got
    ld a,l
.got:
    and #3F
    ld l,a
    ld h,0
    add hl,hl
    inc hl
    ret

;; (peek address) -> the byte in RAM there (0-65535; above 16383 the reader
;; makes a float of it, which is fine). RAM, not the ROMs: through the
;; firmware's RAM LAM.
;@ PEEK 1 1 lf_peek
lf_peek:
    call lint_hl
    rst #20                     ; RAM LAM: A = (HL) in RAM
    ld l,a
    ld h,0
    add hl,hl
    inc hl
    ret

;; (poke address byte) -> the byte. Writes always reach RAM.
;@ POKE 2 2 lf_poke
lf_poke:
    call lint_hl
    push de
    call lint_de
    ld (hl),e
    pop hl
    ret

;; ---------------------------------------------------------------------------
;; SOUND

;; (envelope n count step pause ...): volume envelope n (1-15), up to five
;; sections of three (BASIC's ENV)
;@ ENVELOPE 4 16 lf_envelope
lf_envelope:
    ld c,0
    jr sd_env
;; (tone-envelope n count step pause ...): tone envelope n (1-15), up to
;; five sections; a negative n repeats it (BASIC's ENT)
;@ TONE-ENVELOPE 4 16 lf_tone_envelope
lf_tone_envelope:
    ld c,1
sd_env:
    NEXTARG
    call lint_de                ; n
    push bc
    ld a,b                      ; the sections: (arguments - 1) / 3
    dec a
    ld b,0
.div:
    sub 3
    jr c,.divd
    inc b
    jr .div
.divd:
    add a,3
    jr nz,.bad                  ; not whole sections
    ld a,b
    ld (TOKBUF),a
    ld a,e                      ; a negative n: repeat
    bit 7,d
    jr z,.pos
    neg
    ld e,a
    ld a,(TOKBUF)
    or #80
    ld (TOKBUF),a
.pos:
    push de                     ; n
    ld de,TOKBUF+1
    ld a,b
    add a,a
    add a,b
    ld b,a                      ; 3 bytes a section
.sec:
    push de
    NEXTARG
    call lint_de
    ld a,e
    pop de
    ld (de),a
    inc de
    djnz .sec
    pop de
    pop bc
    ld a,e
    ld hl,TOKBUF
    bit 0,c
    jr nz,.tone
    ld a,(TOKBUF)
    and #7F
    ld (TOKBUF),a
    ld a,e
    call SOUND_AMPL_ENVELOPE
    jp lnil
.tone:
    call SOUND_TONE_ENVELOPE
    jp lnil
.bad:
    ld de,(V_LIBFN)
    ld hl,m_nargs
    CORE error

;; (release channels): sound held for a rendezvous goes (1 A, 2 B, 4 C)
;@ RELEASE 1 1 lf_release
lf_release:
    push hl
    call lint_hl
    ld a,l
    call SOUND_RELEASE
    pop hl
    ret

;; (sound-check channel) -> its queue's state, as BASIC's SQ (1 A, 2 B, 4 C)
;@ SOUND-CHECK 1 1 lf_sound_check
lf_sound_check:
    call lint_hl
    ld a,l
    call SOUND_CHECK
    ld l,a
    ld h,0
    add hl,hl
    inc hl
    ret

;; (sound-hold) -> T if any sound was playing: everything stops where it is
;@ SOUND-HOLD 0 0 lf_sound_hold
lf_sound_hold:
    call SOUND_HOLD
    jp c,lt
    jp lnil

;; (sound-continue): what sound-hold stopped goes on
;@ SOUND-CONTINUE 0 0 lf_sound_continue
lf_sound_continue:
    call SOUND_CONTINUE
    jp lnil

;; ---------------------------------------------------------------------------
;; THE TURTLE, as Logo's: it starts in the middle, facing up; headings in
;; degrees, 0 up, clockwise. Its position is kept in 1/256 units (four
;; bytes each), so many short steps do not drift; the trigonometry is a
;; table of sines in 1/256.

TT_X        equ V_TURTLE        ; x, 1/256 units, signed, four bytes
TT_Y        equ V_TURTLE+4
TT_H        equ V_TURTLE+8      ; the heading, 0-359
TT_PEN      equ V_TURTLE+10     ; 0 down, 1 up
TT_MAGIC    equ V_TURTLE+11     ; &A5 once it is set up

;; tt_ready: the turtle at home, pen down, the first time. All kept.
tt_ready:
    push af
    ld a,(TT_MAGIC)
    cp #A5
    jr z,.ok
    push hl
    push de
    call tt_home
    xor a
    ld (TT_PEN),a
    ld a,#A5
    ld (TT_MAGIC),a
    pop de
    pop hl
.ok:
    pop af
    ret

;; tt_home: in the middle, facing up
tt_home:
    ld hl,320
    ld de,200
    call tt_setpos
    ld hl,0
    ld (TT_H),hl
    ret

;; tt_setpos: HL = x, DE = y, whole units
tt_setpos:
    push de
    ld de,TT_X
    call .one
    pop hl
    ld de,TT_Y
.one:                           ; (DE) = HL * 256, four bytes
    xor a
    ld (de),a
    inc de
    ld a,l
    ld (de),a
    inc de
    ld a,h
    ld (de),a
    inc de
    rla
    sbc a,a                     ; the sign, spread
    ld (de),a
    ret

;; tt_whole: HL = the address of a position -> DE = it, rounded
tt_whole:
    ld a,(hl)
    add a,128
    inc hl
    ld a,(hl)
    adc a,0
    ld e,a
    inc hl
    ld a,(hl)
    adc a,0
    ld d,a
    ret

;; tt_where: DE = x, HL = y, rounded
tt_where:
    ld hl,TT_Y
    call tt_whole
    push de
    ld hl,TT_X
    call tt_whole
    pop hl
    ret

;; tt_neg: HL = -HL
tt_neg:
    xor a
    sub l
    ld l,a
    sbc a,a
    sub h
    ld h,a
    ret

;; tt_sin: HL = degrees, 0-719 -> HL = the sine * 256
tt_sin:
    ld de,360
.m:
    or a
    sbc hl,de
    jr nc,.m
    add hl,de                   ; 0-359
    ld de,180
    or a
    sbc hl,de
    jr c,.upper
    call .half                  ; 180-359: the negative half
    jr tt_neg
.upper:
    add hl,de
.half:                          ; HL = 0-179 -> the table's
    ld de,90
    or a
    sbc hl,de
    jr c,.q1
    ex de,hl                    ; 90-179: sin(180 - h)
    ld hl,90
    or a
    sbc hl,de
    jr .t
.q1:
    add hl,de
.t:
    add hl,hl
    ld de,tt_sines
    add hl,de
    LDHLI
    ret

;; tt_prod: HL = n (signed), DE = s (-256..256) -> A:HL = n * s, signed,
;; 24 bits
tt_prod:
    ld a,h
    xor d
    ld (V_S1),a                 ; the product's sign, bit 7
    bit 7,h
    call nz,tt_neg
    ex de,hl
    bit 7,h
    call nz,tt_neg
    ex de,hl
    ld c,l
    ld b,h                      ; BC = |n|, DE = |s|
    ld a,d
    or a
    jr z,.byte
    ld a,b                      ; |s| = 256: |n| * 256
    ld h,c
    ld l,0
    jr .sign
.byte:
    ld hl,0
    xor a
    ld d,8
.l:
    add hl,hl
    rla
    rl e
    jr nc,.n
    add hl,bc
    adc a,0
.n:
    dec d
    jr nz,.l
.sign:
    ld c,a
    ld a,(V_S1)
    rla
    ld a,c
    ret nc
    xor a                       ; negative: A:HL = -A:HL
    sub l
    ld l,a
    ld a,0
    sbc a,h
    ld h,a
    ld a,0
    sbc a,c
    ret

;; tt_add: DE = a position, A:HL = a signed 24-bit amount -> added
tt_add:
    ld c,a
    rla
    sbc a,a
    ld b,a                      ; the sign, spread
    ex de,hl
    ld a,(hl)
    add a,e
    ld (hl),a
    inc hl
    ld a,(hl)
    adc a,d
    ld (hl),a
    inc hl
    ld a,(hl)
    adc a,c
    ld (hl),a
    inc hl
    ld a,(hl)
    adc a,b
    ld (hl),a
    ret

;; (forward n), (back n): the turtle moves, drawing if its pen is down
;@ FORWARD 1 1 lf_forward
lf_forward:
    call lint_hl
    jr tt_fwd
;@ BACK 1 1 lf_back
lf_back:
    call lint_hl
    call tt_neg
tt_fwd:
    call tt_ready
    push hl
    call tt_where               ; from where it is
    call gx_move
    ld hl,(TT_H)
    call tt_sin                 ; x by n * sin heading
    ex de,hl
    pop hl
    push hl
    call tt_prod
    ld de,TT_X
    call tt_add
    ld hl,(TT_H)
    ld de,90
    add hl,de
    call tt_sin                 ; y by n * cos heading
    ex de,hl
    pop hl
    call tt_prod
    ld de,TT_Y
    call tt_add
    call tt_where
    ld a,(TT_PEN)
    or a
    jr nz,.up
    call gx_line
    jp lnil
.up:
    call gx_move
    jp lnil

;; (right degrees), (left degrees): the turtle turns
;@ RIGHT 1 1 lf_right
lf_right:
    call lint_hl
    jr tt_turn
;@ LEFT 1 1 lf_left
lf_left:
    call lint_hl
    call tt_neg
tt_turn:
    call tt_ready
    ld de,(TT_H)
    add hl,de
    ld de,360
.neg:
    bit 7,h
    jr z,.p
    add hl,de
    jr .neg
.p:
    or a
    sbc hl,de
    jr nc,.p
    add hl,de
    ld (TT_H),hl
    jp lnil

;; (set-heading degrees), (heading)
;@ SET-HEADING 1 1 lf_set_heading
lf_set_heading:
    call lint_hl
    call tt_ready
    ld de,0
    ld (TT_H),de
    jr tt_turn
;@ HEADING 0 0 lf_heading
lf_heading:
    call tt_ready
    ld hl,(TT_H)
    add hl,hl
    inc hl
    ret

;; (pen-up), (pen-down): whether the turtle draws
;@ PEN-UP 0 0 lf_pen_up
lf_pen_up:
    ld a,1
    jr tt_setpen
;@ PEN-DOWN 0 0 lf_pen_down
lf_pen_down:
    xor a
tt_setpen:
    call tt_ready
    ld (TT_PEN),a
    jp lnil

;; (home): the turtle back in the middle, facing up (it draws nothing)
;@ HOME 0 0 lf_home
lf_home:
    call tt_ready
    call tt_home
    jp lnil

;; (set-position x y): the turtle there (it draws nothing)
;@ SET-POSITION 2 2 lf_set_position
lf_set_position:
    call lint_hl
    call lint_de
    call tt_ready
    call tt_setpos
    jp lnil

;; (turtle-position) -> (x y), rounded
;@ TURTLE-POSITION 0 0 lf_turtle_position
lf_turtle_position:
    call tt_ready
    call tt_where
    add hl,hl
    inc hl
    push de
    ld de,NIL
    CORE cons
    pop de
    ex de,hl
    add hl,hl
    inc hl
    CORE cons
    ret

;; sin 0-90 degrees, * 256
tt_sines:
    dw 0,4,9,13,18,22,27,31,36,40
    dw 44,49,53,58,62,66,71,75,79,83
    dw 88,92,96,100,104,108,112,116,120,124
    dw 128,132,136,139,143,147,150,154,158,161
    dw 165,168,171,175,178,181,184,187,190,193
    dw 196,199,202,204,207,210,212,215,217,219
    dw 222,224,226,228,230,232,234,236,237,239
    dw 241,242,243,245,246,247,248,249,250,251
    dw 252,253,254,254,255,255,255,256,256,256
    dw 256

;; ---------------------------------------------------------------------------
;; USER-DEFINED CHARACTERS

TXT_SET_MATRIX      equ #BBA8
TXT_SET_M_TABLE     equ #BBAB
TXT_GET_M_TABLE     equ #BBAE

;; (symbol code row...): character code, 240-255, drawn from up to eight
;; rows, the top first, each a byte (#b00111100...): BASIC's SYMBOL, with
;; its SYMBOL AFTER 240. The table is the 128 bytes the core keeps under the
;; top of memory (V_UDG), set up the first time.
;@ SYMBOL 1 9 lf_symbol
lf_symbol:
    NEXTARG
    call lint_de
    ld a,d
    or a
    jr nz,.bad
    ld a,e
    cp 240
    jr c,.bad
    push de                     ; the code
    push hl
    push bc
    call TXT_GET_M_TABLE        ; ours already?
    jr nc,.set
    ld de,(V_UDG)
    or a
    sbc hl,de
    jr z,.have
.set:
    ld de,240
    ld hl,(V_UDG)
    call TXT_SET_M_TABLE        ; (it copies the present shapes in)
.have:
    pop bc
    pop hl
    ld de,TOKBUF                ; the rows, missing ones blank
    push de
    ld a,8
.z:
    ex de,hl
    ld (hl),0
    inc hl
    ex de,hl
    dec a
    jr nz,.z
    pop de
    dec b
    jr z,.rows
.r:
    push de
    NEXTARG
    call lint_de
    ld a,e
    pop de
    ld (de),a
    inc de
    djnz .r
.rows:
    pop de
    ld a,e
    ld hl,TOKBUF
    call TXT_SET_MATRIX
    jp lnil
.bad:
    ld hl,m_index
    ld de,UNBOUND
    CORE error

;; ---------------------------------------------------------------------------
;; FLOOD FILL

GRA_GET_PEN         equ #BBE1
GRA_GET_ORIGIN      equ #BBCC
SCR_DOT_POSITION    equ #BC1D
SCR_NEXT_BYTE       equ #BC20
SCR_PREV_BYTE       equ #BC23

FF_TARGET   equ TOKBUF+200      ; the colour being filled over
FF_DX       equ TOKBUF+202      ; a pixel's width in x (1, 2 or 4)
FF_SP       equ TOKBUF+204      ; the seed stack: next free,
FF_BASE     equ TOKBUF+206      ;   bottom,
FF_LIMIT    equ TOKBUF+208      ;   full
FF_XL       equ TOKBUF+210      ; the span: left,
FF_XR       equ TOKBUF+212      ;   right,
FF_Y        equ TOKBUF+214      ;   its y
FF_IN       equ TOKBUF+216      ; scanning: in a run of the target colour
FF_PEN      equ TOKBUF+217
FF_BITS     equ TOKBUF+218      ; the target colour, encoded in every pixel
FF_SHIFT    equ TOKBUF+219      ; x to a pixel: shifted right this much
FF_OX       equ TOKBUF+220      ; the graphics origin
FF_OY       equ TOKBUF+222
FF_XMIN     equ TOKBUF+224      ; the screen's edges, in user coordinates
FF_XMAX     equ TOKBUF+226
FF_YMIN     equ TOKBUF+228
FF_YMAX     equ TOKBUF+230
FC_ADDR     equ TOKBUF+232      ; the cursor along a row: its byte,
FC_MASK     equ TOKBUF+234      ;   its pixel's bits
FF_M0       equ TOKBUF+235      ; the leftmost pixel's bits in a byte,
FF_ML       equ TOKBUF+236      ;   the rightmost's

;; (flood-fill x y [pen]): the area around (x, y) that is the colour of
;; (x, y), to where any other colour starts, painted with pen (the graphics
;; pen) -- a paint bucket. (BASIC 1.1's FILL, the 664/6128 firmware's, stops
;; only at the pen's colour; this works the same on every CPC.) A pixel row
;; at a time, reading the screen through RAM LAM: a whole screen in mode 1
;; takes about half a minute.
;@ FLOOD-FILL 2 3 lf_flood_fill
lf_flood_fill:
    ld c,2
    call gx_ints                ; x y
    ld a,b
    ld c,3
    call gx_pen
    pop hl
    pop de
    push de
    push hl
    call gx_move                ; the cursor there
    call GRA_GET_PEN
    ld (FF_PEN),a
    call fl_lend                ; DE = 2 KB for a stack
    ld (FF_BASE),de
    ld (FF_SP),de
    ld hl,2048-4
    add hl,de
    ld (FF_LIMIT),hl
    call SCR_GET_MODE           ; a pixel: mode 0 4 wide, 1 2, 2 1
    ld hl,4
    ld c,2
    or a
    jr z,.w
    ld l,2
    dec c
    dec a
    jr z,.w
    ld l,1
    dec c
.w:
    ld (FF_DX),hl
    ld a,c
    ld (FF_SHIFT),a
    ld hl,#0180                 ; a pixel's bits: shift 0, mode 2 &80..&01,
    or a
    jr z,.m
    ld hl,#1188                 ;   shift 1, mode 1 &88..&11,
    dec a
    jr z,.m
    ld hl,#55AA                 ;   shift 2, mode 0 &AA..&55
.m:
    ld (FF_M0),hl               ; (FF_ML after it)
    call GRA_GET_ORIGIN         ; DE, HL: added to x and y
    ld (FF_OX),de
    ld (FF_OY),hl
    ld bc,0                     ; the edges, in user coordinates
    call .edge
    ld (FF_XMIN),hl
    ld bc,639
    call .edge
    ld (FF_XMAX),hl
    ex de,hl
    ld de,(FF_OY)
    ld bc,0
    call .edge
    ld (FF_YMIN),hl
    ld bc,399
    call .edge
    ld (FF_YMAX),hl
    jr .edged
.edge:                          ; HL = BC - DE
    ld l,c
    ld h,b
    or a
    sbc hl,de
    ret
.edged:
    pop hl                      ; y
    pop de                      ; x
    push de
    push hl
    call gx_test
    ld (FF_TARGET),a
    push af
    call SCR_INK_ENCODE         ; that colour in every pixel of a byte
    ld (FF_BITS),a
    pop af
    ld b,a
    ld a,(FF_PEN)
    cp b
    pop hl
    pop de
    jr z,.done                  ; already that colour
    call ff_push
.next:
    ld hl,(FF_SP)
    ld de,(FF_BASE)
    or a
    sbc hl,de
    jr z,.done
    call ff_pop                 ; DE = x, HL = y
    call ff_span
    jr .next
.done:
    call fe_release
    jp lnil

;; gx_test: DE = x, HL = y -> A = the pen there. IX kept.
gx_test:
    push ix
    call GRA_TEST_ABSOLUTE
    pop ix
    ret

;; ff_push: DE = x, HL = y -> a seed (if there is room)
ff_push:
    push hl
    ld hl,(FF_SP)
    ld bc,(FF_LIMIT)
    or a
    sbc hl,bc
    add hl,bc
    pop bc
    ret nc                      ; full: this part is left
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld (hl),c
    inc hl
    ld (hl),b
    inc hl
    ld (FF_SP),hl
    ret

;; ff_pop -> DE = x, HL = y
ff_pop:
    ld hl,(FF_SP)
    dec hl
    ld b,(hl)
    dec hl
    ld c,(hl)
    dec hl
    ld d,(hl)
    dec hl
    ld e,(hl)
    ld (FF_SP),hl
    ld l,c
    ld h,b
    ret

;; ff_is: DE = x, HL = y -> Z if it is on the screen and the target colour.
;; DE, HL kept. Fast: the screen byte itself, through SCR DOT POSITION and
;; RAM LAM (from a ROM, &C000 up reads the ROM), against FF_BITS.
ff_is:
    push hl
    push de
    ld bc,(FF_OX)               ; to standard coordinates
    ex de,hl
    add hl,bc
    ex de,hl
    ld bc,(FF_OY)
    add hl,bc
    bit 7,d
    jr nz,.no
    bit 7,h
    jr nz,.no
    push hl
    ld bc,640
    ex de,hl
    or a
    sbc hl,bc
    add hl,bc
    ex de,hl
    pop hl
    jr nc,.no
    ld bc,400
    or a
    sbc hl,bc
    add hl,bc
    jr nc,.no
    srl h                       ; to pixels: y / 2, x / the pixel's width
    rr l
    ld a,(FF_SHIFT)
    or a
    jr z,.px
.sh:
    srl d
    rr e
    dec a
    jr nz,.sh
.px:
    call SCR_DOT_POSITION       ; HL = its byte, C = its mask
    rst #20                     ; RAM LAM: A = (HL), in RAM
    and c
    ld b,a
    ld a,(FF_BITS)
    and c
    cp b
    pop de
    pop hl
    ret
.no:
    pop de
    pop hl
    or 1
    ret

;; fc_at: DE = x, HL = y, on the screen -> the cursor on that pixel
fc_at:
    push hl
    push de
    ld bc,(FF_OX)
    ex de,hl
    add hl,bc
    ex de,hl
    ld bc,(FF_OY)
    add hl,bc
    srl h
    rr l
    ld a,(FF_SHIFT)
    or a
    jr z,.px
.sh:
    srl d
    rr e
    dec a
    jr nz,.sh
.px:
    call SCR_DOT_POSITION
    ld (FC_ADDR),hl
    ld a,c
    ld (FC_MASK),a
    pop de
    pop hl
    ret

;; fc_test -> Z if the cursor's pixel is the target colour. DE, HL kept.
fc_test:
    push hl
    ld hl,(FC_ADDR)
    rst #20                     ; RAM LAM
    ld b,a
    ld a,(FC_MASK)
    ld c,a
    and b
    ld b,a
    ld a,(FF_BITS)
    and c
    cp b
    pop hl
    ret

;; fc_right, fc_left: the cursor a pixel on. DE kept.
fc_right:
    ld a,(FC_MASK)
    ld hl,FF_ML
    cp (hl)
    jr z,.byte
    srl a
    ld (FC_MASK),a
    ret
.byte:
    ld a,(FF_M0)
    ld (FC_MASK),a
    ld hl,(FC_ADDR)
    push de
    call SCR_NEXT_BYTE
    pop de
    ld (FC_ADDR),hl
    ret
fc_left:
    ld a,(FC_MASK)
    ld hl,FF_M0
    cp (hl)
    jr z,.byte
    sla a
    ld (FC_MASK),a
    ret
.byte:
    ld a,(FF_ML)
    ld (FC_MASK),a
    ld hl,(FC_ADDR)
    push de
    call SCR_PREV_BYTE
    pop de
    ld (FC_ADDR),hl
    ret

;; ff_span: DE = x, HL = y, a seed -> its row's run painted, and seeds for
;; the runs above and below it
ff_span:
    call ff_is
    ret nz
    ld (FF_Y),hl
    ld (FF_XL),de
    ld (FF_XR),de
    call fc_at
    ld hl,(FC_ADDR)             ; the seed's place, for the right
    push hl
    ld a,(FC_MASK)
    push af
.left:
    ld hl,(FF_XL)               ; x - dx, if on the screen
    ld bc,(FF_DX)
    or a
    sbc hl,bc
    push hl
    ld bc,(FF_XMIN)
    or a
    sbc hl,bc
    pop hl
    jp m,.lend
    push hl
    call fc_left
    call fc_test
    pop hl
    jr nz,.lend
    ld (FF_XL),hl
    jr .left
.lend:
    pop af
    ld (FC_MASK),a
    pop hl
    ld (FC_ADDR),hl
.right:
    ld hl,(FF_XR)               ; x + dx, if on the screen
    ld bc,(FF_DX)
    add hl,bc
    push hl
    ld bc,(FF_XMAX)
    scf
    sbc hl,bc                   ; x' - xmax - 1: negative if x' <= xmax
    pop hl
    jp p,.rend
    push hl
    call fc_right
    call fc_test
    pop hl
    jr nz,.rend
    ld (FF_XR),hl
    jr .right
.rend:
    ld de,(FF_XL)               ; paint it
    ld hl,(FF_Y)
    call gx_move
    ld de,(FF_XR)
    ld hl,(FF_Y)
    call gx_line
    ld hl,(FF_Y)                ; the rows above and below
    inc hl
    inc hl
    call ff_row
    ld hl,(FF_Y)
    dec hl
    dec hl
;; ff_row: HL = a y -> a seed at the start of each run of the target
;; colour in it, from FF_XL to FF_XR
ff_row:
    push hl                     ; on the screen?
    ld bc,(FF_YMIN)
    or a
    sbc hl,bc
    pop hl
    ret m
    push hl
    ld bc,(FF_YMAX)
    scf
    sbc hl,bc
    pop hl
    ret p
    xor a
    ld (FF_IN),a
    ld de,(FF_XL)
    call fc_at
.x:
    call fc_test
    jr nz,.out
    ld a,(FF_IN)
    or a
    jr nz,.step
    inc a
    ld (FF_IN),a
    push hl
    push de
    call ff_push
    pop de
    pop hl
    jr .step
.out:
    xor a
    ld (FF_IN),a
.step:
    push hl
    ld hl,(FF_DX)               ; x + dx, up to the right end
    add hl,de
    ex de,hl
    ld hl,(FF_XR)
    or a
    sbc hl,de
    pop hl
    ret m
    push hl
    call fc_right
    pop hl
    jr .x
