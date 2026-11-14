;; CPC Lisp -- graphics on the TRS-80 Model 4's high-resolution board
;; (Radio Shack's 26-1126; the Grafyx Solution and Ian Mavric's Improved
;; Grafyx answer the same way), in the machine page (page.asm includes
;; this). 640 by 240 pixels from the CPC's logical 640 by 400: a pixel is
;; one unit wide, 5/3 high.
;;
;; The board is ports, seen in any memory map: &80 the X register (a
;; byte's column, 0-79), &81 the Y register (a row, 0-239), &82 the byte
;; there (bit 7 the leftmost pixel), &83 the options -- bit 0 the
;; graphics shown, 2 and 3 X and Y counting down, 4 and 5 X and Y left as
;; they are after a read, 6 and 7 after a write. Bit 1 is the boards'
;; difference: on the Tandy board the video waits (no snow while drawing),
;; on the Grafyx "no text" -- set, the Grafyx shows the graphics alone:
;; on Mike's Improved Grafyx the Lisp's screen went black (2026-11-13;
;; trs80gp -gg, xtrs's grafyx_write_mode). So it is 0: the Grafyx shows
;; the text over the graphics, the Tandy board draws without waits. &8E =
;; 1 is the Tandy board's way to show the text over them (undocumented: a
;; character over lit pixels is inverted). With no board (g_board 0)
;; everything is done but the drawing: a test answers 0.

HR_X        equ #80
HR_Y        equ #81
HR_DATA     equ #82
HR_OPT      equ #83
HR_MIXED    equ #8E
HR_PIXEL    equ #F1             ; shown, nothing counted: one pixel
HR_ROW      equ #B1             ;   X counted after a write: a row
HR_HIDDEN   equ #F0             ; the graphics not shown
GW          equ 640             ; pixels
GH          equ 240

g_board:    db 0                ; 1: a board answered (hr_init)

;; hr_init: from m_init -- is there a board? Then it is cleared and shown,
;; with the text over it
hr_init:
    ld a,HR_PIXEL
    out (HR_OPT),a
    xor a
    out (HR_X),a
    out (HR_Y),a
    ld a,#A5
    out (HR_DATA),a
    in a,(HR_DATA)
    cp #A5
    jr nz,.none
    ld a,#5A
    out (HR_DATA),a
    in a,(HR_DATA)
    cp #5A
    jr nz,.none
    ld a,1
    ld (g_board),a
    call hr_clear
    ld a,1
    out (HR_MIXED),a
    ret
.none:
    xor a
    ld (g_board),a
    ld a,HR_HIDDEN
    out (HR_OPT),a
    ret

;; hr_off: for M_QUIT -- LS-DOS's text alone again
hr_off:
    xor a
    out (HR_MIXED),a
    ld a,HR_HIDDEN
    out (HR_OPT),a
    ret

;; hr_clear: every pixel out. BC, DE, HL kept.
hr_clear:
    ld a,(g_board)
    or a
    ret z
    push bc
    ld a,HR_ROW
    out (HR_OPT),a
    ld b,0                      ; the row
.row:
    xor a
    out (HR_X),a
    ld a,b
    out (HR_Y),a
    ld c,HR_DATA
    xor a
    push bc
    ld b,GW/8
.byte:
    out (c),a
    djnz .byte
    pop bc
    inc b
    ld a,b
    cp GH
    jr c,.row
    ld a,HR_PIXEL
    out (HR_OPT),a
    pop bc
    ret

;; g_clamp: HL = a coordinate -> within -C*256..C*256
g_clamp:
    ld a,h
    bit 7,a
    jr nz,.neg
    cp c
    ret c
    ld h,c
    ld l,0
    ret
.neg:
    neg
    cp c
    ret c
    ld a,c
    neg
    ld h,a
    ld l,0
    ret

;; g_div: HL = a signed number, C = a divisor -> HL = it divided, floored
g_div:
    bit 7,h
    jr z,g_udiv
    xor a                       ; for x < 0: -((-x + c - 1) / c)
    sub l
    ld l,a
    sbc a,a
    sub h
    ld h,a
    ld a,c
    dec a
    add a,l
    ld l,a
    jr nc,.n
    inc h
.n:
    call g_udiv
    xor a
    sub l
    ld l,a
    sbc a,a
    sub h
    ld h,a
    ret
;; g_udiv: HL / C -> HL, A = the remainder
g_udiv:
    xor a
    ld b,16
.l:
    add hl,hl
    rla
    cp c
    jr c,.s
    sub c
    inc l
.s:
    djnz .l
    ret

;; g_pix: DE = x, HL = y, logical, from the origin -> DE = the pixel's
;; column, HL = its row (signed, perhaps off the screen)
g_pix:
    push hl
    ld hl,(g_ox)
    add hl,de
    ld c,80                     ; within +-20480
    call g_clamp
    ex (sp),hl                  ; the column kept; HL = y
    ld de,(g_oy)
    add hl,de
    ld c,40                     ; within +-10240
    call g_clamp
    ld d,h
    ld e,l
    add hl,hl
    add hl,de                   ; * 3
    ld c,5
    call g_div                  ; / 5
    ex de,hl
    ld hl,GH-1
    or a
    sbc hl,de                   ; rows go down
    pop de
    ret

;; M_NEXTY: HL = a y, logical, from the origin -> HL = the next y up on
;; another pixel row: y+1 or y+2, a row being 5/3 units. fill-box (lib/
;; gfx.asm) steps by it: every row once, none left out (two at a time, as
;; on the CPC, left every fifth row out). BC, DE kept.
m_m_nexty:
    push bc
    push de
    push hl
    ld de,0
    call g_pix                  ; HL = y's row
    ex (sp),hl                  ; it kept; HL = y
    inc hl
    push hl
    ld de,0
    call g_pix                  ; HL = y+1's row
    pop de                      ; DE = y+1
    pop bc                      ; BC = y's row
    or a
    sbc hl,bc
    ex de,hl
    jr nz,.new
    inc hl                      ; the same row: y+2 is on the next
.new:
    pop de
    pop bc
    ret

;; g_cell: DE = a pixel's column, HL = its row -> the board's X and Y at
;; its byte, C = its bit; NC if it is off the screen (or there is no
;; board). DE, HL kept.
g_cell:
    ld a,h
    or a
    ret nz                      ; (NZ, carry clear: or)
    ld a,l
    cp GH
    ret nc
    ld a,d
    cp GW >> 8
    jr c,.in
    ret nz
    ld a,e
    cp GW and #FF
    ret nc
.in:
    ld a,(g_board)
    or a
    ret z
    ld a,l
    out (HR_Y),a
    ld a,e
    and 7
    ld b,a
    ld a,#80
    jr z,.bit
.sh:
    rrca
    djnz .sh
.bit:
    ld c,a
    push de
    ld a,e
    srl d
    rra
    srl d
    rra
    srl d
    rra                         ; the column / 8
    out (HR_X),a
    pop de
    scf
    ret

;; g_set: DE, HL = a pixel -> lit or put out, as the pen and the ink-mode
;; say. DE, HL kept.
g_set:
    call g_cell
    ret nc
    in a,(HR_DATA)
    ld b,a
    ld a,(g_ink)
    dec a
    jr z,.xor
    dec a
    jr z,.and
    dec a
    jr z,.or
    ld a,(g_pen)                ; plain: the pen's
    or a
    jr nz,.on
.off:
    ld a,c
    cpl
    and b
    out (HR_DATA),a
    ret
.xor:
    ld a,(g_pen)
    or a
    ret z
    ld a,b
    xor c
    out (HR_DATA),a
    ret
.and:
    ld a,(g_pen)
    or a
    jr z,.off
    ret
.or:
    ld a,(g_pen)
    or a
    ret z
.on:
    ld a,b
    or c
    out (HR_DATA),a
    ret

;; g_get: DE, HL = a pixel -> A = 1 lit, 0 not (or off the screen). DE, HL
;; kept.
g_get:
    call g_cell
    ld a,0
    ret nc
    in a,(HR_DATA)
    and c
    ret z
    ld a,1
    ret

;; GFX_MOVE, GFX_MOVER: DE = x, HL = y
m_gfx_mover:
    call g_rel
m_gfx_move:
    ld (g_x),de
    ld (g_y),hl
    ret
g_rel:
    push hl
    ld hl,(g_x)
    add hl,de
    ex de,hl
    pop hl
    push de
    ld de,(g_y)
    add hl,de
    pop de
    ret

;; GFX_PLOT, GFX_PLOTR
m_gfx_plotr:
    call g_rel
m_gfx_plot:
    call m_gfx_move
    call g_pix
    jp g_set

;; GFX_TEST, GFX_TESTR -> A = the pen there
m_gfx_testr:
    call g_rel
m_gfx_test:
    call m_gfx_move
    call g_pix
    jp g_get

;; GFX_WHERE: -> DE = x, HL = y
m_gfx_where:
    ld de,(g_x)
    ld hl,(g_y)
    ret

;; GFX_ORIGIN: DE = x, HL = y; the position goes there
m_gfx_origin:
    ld (g_ox),de
    ld (g_oy),hl
    ld hl,0
    ld (g_x),hl
    ld (g_y),hl
    ret

;; GFX_PEN: A = a pen: 0 puts out, any other lights
m_gfx_pen:
    or a
    jr z,.p
    ld a,1
.p:
    ld (g_pen),a
    ret

;; M_INKMODE: A = how lines are drawn: 0 plain, 1 XOR, 2 AND, 3 OR (the
;; pen with what is there)
m_m_inkmode:
    and 3
    ld (g_ink),a
    ret

;; GFX_CLEAR: the graphics blank (the text stays); the position at the
;; origin
m_gfx_clear:
    call hr_clear
    ld hl,0
    ld (g_x),hl
    ld (g_y),hl
    ret

;; GFX_LINE, GFX_LINER: from where the last one ended, Bresenham's way
m_gfx_liner:
    call g_rel
m_gfx_line:
    push de
    push hl
    ld de,(g_x)
    ld hl,(g_y)
    call g_pix
    ld (l_x0),de
    ld (l_y0),hl
    pop hl
    pop de
    call m_gfx_move
    call g_pix
    ld (l_x1),de
    ld (l_y1),hl
    ; dx = |x1 - x0|, sx = the sign
    ld hl,(l_x1)
    ld de,(l_x0)
    ld bc,1
    or a
    sbc hl,de
    jp p,.dxp
    ld bc,-1
    call g_neg
.dxp:
    ld (l_dx),hl
    ld (l_sx),bc
    ; dy = -|y1 - y0|, sy = the sign
    ld hl,(l_y1)
    ld de,(l_y0)
    ld bc,1
    or a
    sbc hl,de
    jp p,.dyp
    ld bc,-1
    call g_neg
.dyp:
    call g_neg
    ld (l_dy),hl
    ld (l_sy),bc
    ld de,(l_dx)
    add hl,de
    ld (l_err),hl               ; err = dx + dy
.step:
    ld de,(l_x0)
    ld hl,(l_y0)
    call g_set
    ld hl,(l_x0)
    ld de,(l_x1)
    or a
    sbc hl,de
    jr nz,.on
    ld hl,(l_y0)
    ld de,(l_y1)
    or a
    sbc hl,de
    ret z                       ; at the end
.on:
    ld hl,(l_err)
    add hl,hl                   ; e2 = 2 err
    push hl
    ld de,(l_dy)
    or a
    sbc hl,de                   ; e2 >= dy?
    jp m,.noy
    ld hl,(l_err)
    add hl,de
    ld (l_err),hl
    ld hl,(l_x0)
    ld de,(l_sx)
    add hl,de
    ld (l_x0),hl
.noy:
    pop hl
    ld de,(l_dx)
    ex de,hl
    or a
    sbc hl,de                   ; dx >= e2?
    jp m,.step
    ld hl,(l_err)
    ld de,(l_dx)
    add hl,de
    ld (l_err),hl
    ld hl,(l_y0)
    ld de,(l_sy)
    add hl,de
    ld (l_y0),hl
    jr .step
g_neg:
    xor a
    sub l
    ld l,a
    sbc a,a
    sub h
    ld h,a
    ret

;; M_FILL: DE = x, HL = y, logical -> the area around that pixel of its
;; colour, to where the other starts, made the pen's; the position there.
;; A row at a time: a run of pixels to its ends, the runs above and below
;; it noted on a stack to do next (FILL_STK, past the page's code: 1280
;; of them, a column word and a row word each). Two colours: a pixel
;; painted is no longer the area's, so nothing is done twice. IX corrupt.
m_m_fill:
    call m_gfx_move
    call g_pix
    call g_cell
    ret nc                      ; off the screen, or no board
    call ff_get
    ld (ff_t),a
    ld b,a
    ld a,(g_pen)
    cp b
    ret z                       ; the pen's already
    ld a,(g_ink)
    push af
    xor a
    ld (g_ink),a                ; the pen as it is, whatever ink-mode says
    ld ix,FILL_STK
    call ff_push
.next:
    push ix
    pop hl
    ld bc,FILL_STK
    or a
    sbc hl,bc
    jr z,.done
    ld bc,-4
    add ix,bc
    ld e,(ix+0)                 ; DE = a column,
    ld d,(ix+1)
    ld l,(ix+2)                 ;   HL = a row
    ld h,(ix+3)
    call ff_is
    jr nz,.next                 ; done already
.left:
    ld a,d                      ; to the run's left end
    or e
    jr z,.run
    dec de
    call ff_is
    jr z,.left
    inc de
.run:
    xor a
    ld (ff_up),a
    ld (ff_dn),a
.r:
    call ff_is
    jr nz,.next                 ; its right end
    call ff_set
    ld a,l
    or a
    jr z,.below
    dec l                       ; the row above
    ld bc,ff_up
    call ff_side
    inc l
.below:
    ld a,l
    cp GH-1
    jr nc,.right
    inc l                       ; the row below
    ld bc,ff_dn
    call ff_side
    dec l
.right:
    inc de
    ld a,d
    cp GW >> 8
    jr c,.r
    ld a,e
    cp GW and #FF
    jr c,.r
    jr .next
.done:
    pop af
    ld (g_ink),a
    ret
;; ff_side: DE, HL = a pixel next to the run, BC = its side's flag -> a
;; run starting there noted, if it is the area's and the pixel before it
;; was not
ff_side:
    call ff_is
    jr z,.is
    xor a
    ld (bc),a
    ret
.is:
    ld a,(bc)
    or a
    ret nz                      ; noted already
    inc a
    ld (bc),a
;; ff_push: DE, HL = a pixel -> on the stack (unless it is full)
ff_push:
    push hl
    push ix
    pop hl
    ld a,h
    cp FILL_END >> 8
    pop hl
    ret nc
    ld (ix+0),e
    ld (ix+1),d
    ld (ix+2),l
    ld (ix+3),h
    inc ix
    inc ix
    inc ix
    inc ix
    ret
;; ff_is: DE, HL = a pixel -> Z if it is the area's colour. BC, DE, HL
;; kept.
ff_is:
    call ff_get
    push hl
    ld hl,ff_t
    cp (hl)
    pop hl
    ret
;; ff_get, ff_set: g_get, g_set, BC kept too
ff_get:
    push bc
    call g_get
    pop bc
    ret
ff_set:
    push bc
    call g_set
    pop bc
    ret
ff_t:       db 0                ; the area's colour
ff_up:      db 0                ; a run above noted, and not ended yet
ff_dn:      db 0                ;   below
