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

;; (circle x y r [pen]), (disc x y r [pen]): a circle, a filled one
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
    jr .loop
.done:
    ld hl,CI_SIZE
    add hl,sp
    ld sp,hl
    jp lnil

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
