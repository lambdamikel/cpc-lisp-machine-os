;; CPC Lisp -- more graphics, text, sound and machine functions (library
;; ROM, part 0): what BASIC has beyond plot and draw, and a little more.
;; All through firmware vectors below &BD37, the same on every CPC.


;; gx_plot, gx_move, gx_line: DE = x, HL = y, IX kept
gx_plot:
    push ix
    call GFX_PLOT
    pop ix
    ret
gx_move:
    push ix
    call GFX_MOVE
    pop ix
    ret
gx_line:
    push ix
    call GFX_LINE
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
    call GFX_PEN
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
    ifdef M_NEXTY
    push hl                     ; a pixel row once, at its lowest y: on a
    dec hl                      ;   Model 4 a row is 5/3 units, and the
    call M_NEXTY                ;   CPC's even ys left every sixth row out
    pop de
    or a
    sbc hl,de
    ex de,hl
    ret nz
    else
    bit 0,l                     ; a pixel row once: the even y of the two
    ret nz
    endif
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
    ifndef M_NEXTY
    ld a,l                      ; a pixel row is two y values: from the
    and #FE                     ;   even one of the lowest row to the odd
    ld l,a                      ;   one of the highest, two at a time
    set 0,e
    endif                       ; (a Model 4's row is 5/3: M_NEXTY steps)
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
    ifdef M_NEXTY
    call M_NEXTY                ; the next y on another pixel row
    else
    inc hl
    inc hl
    endif
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

    include "natives.asm"       ; the machine's own: mach/cpc/natives.asm

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

    include "graphics.asm"      ; SYMBOL, FLOOD-FILL: mach/cpc/graphics.asm
