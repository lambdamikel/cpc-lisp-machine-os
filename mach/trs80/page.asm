;; CPC Lisp -- the TRS-80's machine page: the routines behind the machine
;; interface (mach/README.md has their contracts). The loader puts this in
;; X-MEM/80 page MACHPAGE; the resident part (resident.asm) maps it at
;; &C000 for each call through the jumpblock and maps the caller's page
;; back after. Its variables are here too: the page is RAM.
;;
;; THE SCREEN is the Model I's: 64 by 16 characters at &3C00, which every
;; page sees. The console works as the CPC's text VDU does, as far as the
;; Lisp asks: a cursor that may stand one past the last column until the
;; next character wraps, a roll count that goes down by one each scroll,
;; the CPC's controls 7-13, 30 and 31. With trs80gp's emulator extensions
;; (-ee), everything printed goes to the printer too: the test transcript.
;;
;; GRAPHICS are the screen's 2 x 3 blocks: 128 by 48, from the CPC's
;; logical 640 by 400 -- a block is 5 units wide, 25/3 high.

    include "firmware.asm"
    include "jumps.asm"
    include "memmap.asm"

    org #C000
    jp m_init                   ; the loader calls this once
    db "TRS-80 MACHINE PAGE",0
    defs MTAB-$,0
    include "mtab.inc"

;; ---------------------------------------------------------------------------
;; STATE

c_col:      db 0                ; 0-63, or 64: past the end
c_row:      db 0                ; 0-15
c_roll:     db 0                ; down by one a scroll
c_sys:      db 0                ; the cursor on (CON_CURON)
c_usr:      db 1                ;   and enabled (CON_CURENA)
c_drawn:    db 0                ; it is on the screen,
c_under:    db 0                ;   over this character
c_esc:      db 0                ; 31 (locate): bytes still to come
c_parm:     db 0                ;   the column, when the row comes
c_echo:     db 0                ; 1: the printer gets it all too
k_back:     db 0                ; KEY_UNREAD's character, 0 if none
g_x:        dw 0                ; graphics: where the last one ended,
g_y:        dw 0
g_ox:       dw 0                ;   the origin,
g_oy:       dw 0
g_pen:      db 1                ;   1 draws, 0 erases
l_x0:       dw 0                ; a line: from,
l_y0:       dw 0
l_x1:       dw 0                ;   to (blocks),
l_y1:       dw 0
l_dx:       dw 0
l_dy:       dw 0
l_sx:       dw 0
l_sy:       dw 0
l_err:      dw 0
t32:        dw 0,0

;; m_init: from the loader, once
m_init:
    ld a,255
    out (EE_PORT),a             ; trs80gp -ee answers 1
    in a,(EE_PORT)
    cp 1
    ld a,0
    jr nz,.real
    inc a
.real:
    ld (c_echo),a
    xor a
    ld (k_back),a
    ld (c_drawn),a
    ld (c_sys),a
    ld (c_esc),a
    ld (c_roll),a
    inc a
    ld (c_usr),a
    ld (g_pen),a
    ld hl,0
    ld (g_x),hl
    ld (g_y),hl
    ld (g_ox),hl
    ld (g_oy),hl
    jp c_clear

;; ---------------------------------------------------------------------------
;; CONSOLE

;; c_addr: -> HL = the screen address of the cursor's cell (c_col < 64)
c_addr:
    ld a,(c_row)
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld a,(c_col)
    or l
    ld l,a
    ld a,h
    add a,VRAM >> 8
    ld h,a
    ret

;; c_hide: the cursor off the screen, if it is on it. HL kept.
c_hide:
    ld a,(c_drawn)
    or a
    ret z
    push hl
    call c_addr
    ld a,(c_under)
    ld (hl),a
    xor a
    ld (c_drawn),a
    pop hl
    ret

;; c_show: the cursor drawn, if it is on and enabled. HL kept.
c_show:
    ld a,(c_drawn)
    or a
    ret nz
    ld a,(c_sys)
    or a
    ret z
    ld a,(c_usr)
    or a
    ret z
    ld a,(c_col)
    cp VCOLS
    ret nc
    push hl
    call c_addr
    ld a,(hl)
    ld (c_under),a
    ld (hl),#B0                 ; the Level II cursor
    ld a,1
    ld (c_drawn),a
    pop hl
    ret

;; c_print: C to the printer
c_print:
    ld a,(PRINTER)
    rlca
    jr c,c_print                ; busy
    ld a,c
    ld (PRINTER),a
    ret

;; c_put: A = a character, at the cursor; the cursor on. BC, DE corrupt.
c_put:
    ld c,a
    ld a,(c_col)
    cp VCOLS
    call nc,c_wrap
    call c_addr
    ld (hl),c
    ld hl,c_col
    inc (hl)
    ret
c_wrap:
    xor a
    ld (c_col),a
    ; fall through
;; c_lf: down a row, scrolling at the bottom
c_lf:
    ld a,(c_row)
    cp VROWS-1
    jr nc,c_scroll
    inc a
    ld (c_row),a
    ret
c_scroll:
    push bc
    push de
    ld hl,VRAM+VCOLS
    ld de,VRAM
    ld bc,VCOLS*(VROWS-1)
    ldir
    ld b,VCOLS
.blank:
    ld a,' '
    ld (de),a
    inc de
    djnz .blank
    ld hl,c_roll
    dec (hl)
    pop de
    pop bc
    ret

;; c_clear: the screen blank, the cursor home
c_clear:
    ld hl,VRAM
    ld de,VRAM+1
    ld bc,VCOLS*VROWS-1
    ld (hl),' '
    ldir
    xor a
    ld (c_col),a
    ld (c_row),a
    ld (c_drawn),a
    ret

;; c_setcur: H = column, L = row, from 1 -> the cursor there, kept on the
;; screen (a column one past the last is allowed)
c_setcur:
    ld a,h
    or a
    jr nz,.c1
    inc a
.c1:
    dec a
    cp VCOLS+1
    jr c,.c2
    ld a,VCOLS
.c2:
    ld (c_col),a
    ld a,l
    or a
    jr nz,.r1
    inc a
.r1:
    dec a
    cp VROWS
    jr c,.r2
    ld a,VROWS-1
.r2:
    ld (c_row),a
    ret

;; CON_PUTC: A = a character, or a control. Every register kept.
m_con_putc:
    push af
    push bc
    push de
    push hl
    ld c,a
    ld a,(c_echo)
    or a
    call nz,c_print
    call c_hide
    ld a,(c_esc)
    or a
    jr nz,.parm
    ld a,c
    cp 32
    jr nc,.char
    cp 13
    jr z,.cr
    cp 10
    jr z,.lf
    cp 8
    jr z,.bs
    cp 9
    jr z,.right
    cp 11
    jr z,.up
    cp 12
    jr z,.cls
    cp 30
    jr z,.home
    cp 31
    jr z,.locate
    jr .done                    ; 7 and the rest: nothing
.char:
    call c_put
    jr .done
.cr:
    xor a
    ld (c_col),a
    jr .done
.lf:
    call c_lf
    jr .done
.bs:
    ld a,(c_col)
    or a
    jr z,.done
    dec a
    ld (c_col),a
    jr .done
.right:
    ld a,(c_col)
    cp VCOLS-1
    jr nc,.done
    inc a
    ld (c_col),a
    jr .done
.up:
    ld a,(c_row)
    or a
    jr z,.done
    dec a
    ld (c_row),a
    jr .done
.cls:
    call c_clear
    jr .done
.home:
    xor a
    ld (c_col),a
    ld (c_row),a
    jr .done
.locate:
    ld a,2
    ld (c_esc),a
    jr .done
.parm:
    dec a
    ld (c_esc),a
    jr z,.row
    ld a,c
    ld (c_parm),a               ; the column
    jr .done
.row:
    ld a,(c_parm)
    ld h,a
    ld l,c
    call c_setcur
.done:
    call c_show
    pop hl
    pop de
    pop bc
    pop af
    ret

;; CON_WRCH: A = a character, drawn as it is. Every register kept.
m_con_wrch:
    push af
    push bc
    push de
    push hl
    ld c,a
    ld a,(c_echo)
    or a
    call nz,c_print
    call c_hide
    ld a,c
    call c_put
    call c_show
    pop hl
    pop de
    pop bc
    pop af
    ret

;; CON_RDCH: -> carry and A = the character at the cursor
m_con_rdch:
    ld a,(c_col)
    cp VCOLS
    jr nc,.no
    ld a,(c_drawn)
    or a
    jr z,.screen
    ld a,(c_under)
    scf
    ret
.screen:
    push hl
    call c_addr
    ld a,(hl)
    pop hl
    scf
    ret
.no:
    or a
    ret

;; CON_GETCUR: -> H = column, L = row, from 1; A = the roll count
m_con_getcur:
    ld a,(c_col)
    inc a
    ld h,a
    ld a,(c_row)
    inc a
    ld l,a
    ld a,(c_roll)
    ret

;; CON_SETCUR: H = column, L = row, from 1
m_con_setcur:
    call c_hide
    call c_setcur
    jp c_show

;; the cursor's two switches. Every register but AF kept.
m_con_curon:
    ld a,1
    ld (c_sys),a
    jp c_show
m_con_curoff:
    call c_hide
    xor a
    ld (c_sys),a
    ret
m_con_curena:
    ld a,1
    ld (c_usr),a
    jp c_show
m_con_curdis:
    call c_hide
    xor a
    ld (c_usr),a
    ret

;; CON_GETWIN: the whole screen -> H, D = columns 0, 63; L, E = rows 0, 15
m_con_getwin:
    ld hl,0
    ld de,(VCOLS-1)*256+VROWS-1
    or a
    ret

;; CON_CLS
m_con_cls:
    push bc
    push de
    push hl
    call c_clear
    call c_show
    pop hl
    pop de
    pop bc
    ret

;; inverse video, pens and paper: there are none
m_con_inverse:
m_con_pen:
m_con_paper:
m_vid_ink:
m_vid_border:
m_gfx_paper:
    ret

;; ---------------------------------------------------------------------------
;; KEYS: the ROM's scan, its codes made the CPC's
;;   BREAK ESC, CLEAR CLR, <- DEL, SHIFT <- left, -> right, SHIFT -> TAB,
;;   up and down, SHIFT up and SHIFT down the copy cursor's

k_codes:
    db #01,#FC, #1F,#10, #08,#7F, #18,#F2, #09,#F3, #19,#09
    db #5B,#F0, #0A,#F1, #1B,#F4, #1A,#F5, 0

;; KEY_READ: -> carry and A = a character; no carry if there is none
m_key_read:
    ld a,(k_back)
    or a
    jr z,.scan
    push af
    xor a
    ld (k_back),a
    pop af
    scf
    ret
.scan:
    push bc
    push de
    push hl
    push ix
    push iy
    call ROM_KBD
    pop iy
    pop ix
    or a
    jr z,.none
    ld hl,k_codes
.x:
    ld c,(hl)
    inc c
    dec c
    jr z,.got
    inc hl
    cp c
    ld c,(hl)
    inc hl
    jr nz,.x
    ld a,c
.got:
    pop hl
    pop de
    pop bc
    scf
    ret
.none:
    pop hl
    pop de
    pop bc
    ret                         ; NC (or a)

;; KEY_WAIT: -> A = a character
m_key_wait:
    call m_key_read
    jr nc,m_key_wait
    ret

;; KEY_UNREAD: A = a character, read next
m_key_unread:
    ld (k_back),a
    ret

;; KEY_TEST: A = a key number, row * 8 + bit of the matrix -> NZ if down.
;; BC, DE, HL kept.
m_key_test:
    push bc
    push hl
    ld c,a
    and 7
    call .bit
    ld h,a                      ; the column's bit
    ld a,c
    rrca
    rrca
    rrca
    and 7
    call .bit
    ld l,a                      ; the row's address: &3800 + 2^row
    ld a,h
    ld h,KBD >> 8
    and (hl)
    pop hl
    pop bc
    ret
.bit:                           ; A = n -> 2^n
    ld b,a
    ld a,1
    inc b
.sh:
    dec b
    ret z
    add a,a
    jr .sh

;; ---------------------------------------------------------------------------
;; VIDEO

;; VID_MODE: one mode only; the screen is cleared, as the CPC's is
m_vid_mode:
    jp m_con_cls

;; VID_FRAME: about a fiftieth of a second (the Model I has no frame signal)
m_vid_frame:
    push bc
    ld b,12
.o:
    push bc
    ld b,0
.i:
    djnz .i
    pop bc
    djnz .o
    pop bc
    ret

;; VID_FILLBOX: H, D = columns, L, E = rows, from 0 -> blank
m_vid_fillbox:
    call c_hide
    ld a,d
    sub h
    inc a
    ld c,a                      ; columns
    ld a,e
    sub l
    inc a
    ld b,a                      ; rows
    ld a,l
.row:
    push bc
    push af
    push hl
    ld l,a
    ld a,h
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    or l
    ld l,a
    ld a,h
    add a,VRAM >> 8
    ld h,a
    ld b,c
.col:
    ld (hl),' '
    inc hl
    djnz .col
    pop hl
    pop af
    inc a
    pop bc
    djnz .row
    ret

;; ---------------------------------------------------------------------------
;; GRAPHICS

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
    xor a                       ; -floor(-x / c) ... is floor((x) / c)
    sub l                       ;   for x < 0: -((-x + c - 1) / c)
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

;; g_pix: DE = x, HL = y, logical, from the origin -> DE = the block
;; column, HL = the block row (signed, perhaps off the screen)
g_pix:
    push hl
    ld hl,(g_ox)
    add hl,de
    ld c,80                     ; within +-20480
    call g_clamp
    ld c,5
    call g_div
    ex (sp),hl                  ; the column kept; HL = y
    ld de,(g_oy)
    add hl,de
    ld c,40                     ; within +-10240
    call g_clamp
    ld d,h
    ld e,l
    add hl,hl
    add hl,de                   ; * 3
    ld c,25
    call g_div                  ; / 25
    ex de,hl
    ld hl,47
    or a
    sbc hl,de                   ; rows go down
    pop de
    ret

;; g_cell: DE = block column, HL = block row, on the screen -> HL = the
;; character's address, C = the block's bit. NC if off the screen.
g_cell:
    ld a,d
    or h
    ret nz                      ; (nz with carry clear: or)
    ld a,e
    cp 128
    ret nc
    ld a,l
    cp 48
    ret nc
    ld b,0
.d3:
    cp 3
    jr c,.r
    sub 3
    inc b
    jr .d3
.r:
    add a,a                     ; 2 * (row mod 3)
    bit 0,e
    jr z,.b
    inc a
.b:
    ld c,1
    or a
    jr z,.m
.sh:
    sla c
    dec a
    jr nz,.sh
.m:
    ld l,b
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld a,e
    srl a
    or l
    ld l,a
    ld a,h
    add a,VRAM >> 8
    ld h,a
    scf
    ret

;; g_set: DE, HL = a block -> lit or put out, as the pen says
g_set:
    call g_cell
    ret nc
    ld a,(hl)
    bit 7,a
    jr nz,.g
    ld a,#80                    ; a character there: blank blocks now
.g:
    ld b,a
    ld a,(g_pen)
    or a
    ld a,b
    jr z,.off
    or c
    ld (hl),a
    ret
.off:
    ld a,c
    cpl
    and b
    or #80
    ld (hl),a
    ret

;; g_get: DE, HL = a block -> A = 1 lit, 0 not (or off the screen)
g_get:
    call g_cell
    ld a,0
    ret nc
    ld a,(hl)
    bit 7,a
    ld a,0
    ret z
    ld a,(hl)
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

;; GFX_CLEAR: the screen blank (text and graphics share it); the position
;; at the origin
m_gfx_clear:
    call c_hide
    ld hl,VRAM
    ld de,VRAM+1
    ld bc,VCOLS*VROWS-1
    ld (hl),' '
    ldir
    ld hl,0
    ld (g_x),hl
    ld (g_y),hl
    jp c_show

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

;; ---------------------------------------------------------------------------
;; SOUND: none yet -- a sound is taken, and not heard

m_snd_queue:
    scf
    ret

;; ---------------------------------------------------------------------------
;; FILES: not yet

m_file_iopen:
m_file_oopen:
    ld a,1
    or a                        ; NC, NZ: an error
    ret
m_file_iclose:
m_file_oclose:
m_file_iabandon:
m_file_oabandon:
m_file_putc:
    scf
    ret
m_file_getc:
    xor a                       ; NC: the end
    ret
m_file_cat:
    ret

;; ---------------------------------------------------------------------------
;; FLOATS: five-byte reals, the CPC's -- Microsoft's binary form with a
;; 32-bit mantissa. Not yet: all but the constants fail.

m_fp_move:
    push hl
    ex de,hl
    ld bc,5
    ldir
    pop hl
    scf
    ret
m_fp_pi:
    push hl
    ex de,hl
    ld hl,fp_pi
    ld bc,5
    ldir
    pop hl
    scf
    ret
fp_pi:
    db #A2,#DA,#0F,#49,#82
m_fp_int2r:
m_fp_bin2r:
m_fp_r2int:
m_fp_r2bin:
m_fp_fix:
m_fp_int:
m_fp_exp10:
m_fp_add:
m_fp_rsub:
m_fp_mul:
m_fp_div:
m_fp_cmp:
m_fp_neg:
m_fp_sgn:
m_fp_angle:
m_fp_sqr:
m_fp_pow:
m_fp_log:
m_fp_exp:
m_fp_sin:
m_fp_cos:
m_fp_tan:
m_fp_atn:
    or a
    ret

;; ---------------------------------------------------------------------------
;; SYSTEM

;; SYS_TIME: -> DEHL = the time of day in 1/300 s, from LDOS's clock
m_sys_time:
    ld a,(L_TIME+2)
    ld l,a
    ld h,0
    ld de,0
    ld c,60
    call mul32
    ld a,(L_TIME+1)
    call add32a
    ld c,60
    call mul32
    ld a,(L_TIME)
    call add32a
    ld c,100
    call mul32
    ld c,3
    ;; fall through
;; mul32: DEHL *= C (1 or more)
mul32:
    ld (t32),hl
    ld (t32+2),de
.l:
    dec c
    ret z
    push bc
    ld bc,(t32)
    add hl,bc
    ex de,hl
    ld bc,(t32+2)
    adc hl,bc
    ex de,hl
    pop bc
    jr .l
;; add32a: DEHL += A
add32a:
    add a,l
    ld l,a
    ret nc
    inc h
    ret nz
    inc de
    ret

;; M_EDIT: a line typed into (HL), for when there is no library's editor
;; -> carry for ENTER, none for BREAK
m_m_edit:
    push hl
    ld b,0
    ld a,1
    ld (c_sys),a
.k:
    call c_show
    call m_key_wait
    cp 13
    jr z,.enter
    cp #FC
    jr z,.esc
    cp #7F
    jr z,.del
    cp 32
    jr c,.k
    ld c,a
    ld a,b
    cp 250
    jr nc,.k
    ld (hl),c
    inc hl
    inc b
    ld a,c
    call m_con_wrch
    jr .k
.del:
    ld a,b
    or a
    jr z,.k
    dec hl
    dec b
    ld a,8
    call m_con_putc
    ld a,' '
    call m_con_wrch
    ld a,8
    call m_con_putc
    jr .k
.enter:
    ld (hl),0
    call m_con_curoff
    pop hl
    scf
    ret
.esc:
    ld (hl),0
    call m_con_curoff
    pop hl
    or a
    ret

;; M_QUIT: back to LDOS -- or out of trs80gp, with -ee
m_m_quit:
    ld a,(c_echo)
    or a
    jr z,.dos
    ld bc,0
    ld a,128
    out (EE_PORT),a
.dos:
    jp L_EXIT

page_end:
    print "machine page: ",page_end-#C000," bytes"
    assert page_end <= #10000
    defs #10000-$,#FF
