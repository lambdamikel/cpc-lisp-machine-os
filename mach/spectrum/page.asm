;; CPC Lisp -- the Spectrum's machine pages: the routines behind the
;; machine interface (mach/README.md has their contracts). Two pages of the
;; DivMMC's RAM, 8 KB each, seen at &2000 while one of their routines runs
;; (the resident part, resident.asm, maps them for each call through the
;; jumpblock): page A (MP_A) the screen, the keys, graphics, sound and the
;; interrupt's work; page B (MP_B, pageb.asm) files, floats and the RAM
;; disc. Their variables are in them too: the pages are RAM. One image of
;; 16 KB, LISPM.ROM: page A, then page B.
;;
;; While a page is in, the DivMMC's EEPROM is at &0000-&1FFF instead of
;; the ROM: what needs the ROM -- the calculator, esxDOS -- goes through
;; the resident part. And no code may be at &3D00-&3DFF: a fetch there maps
;; the DivMMC in by itself (its TR-DOS trap), and it would stay in after
;; the page went out. Each page keeps data there (&3B00-&3FFF).
;;
;; THE SCREEN is the Spectrum's, 256 by 192, in 40 columns of six pixels
;; -- the CPC's mode 1 -- and 24 rows (a font of our own, font.inc: 5 by 7
;; in 6 by 8), centred, one colour
;; on another for the whole screen (the attributes). The console works as
;; the CPC's text VDU does, as far as the Lisp asks (the TRS-80's page is
;; the pattern): a cursor that may stand one past the last column until
;; the next character wraps, a roll count that goes down by one each
;; scroll, the CPC's controls 7-13, 30 and 31. A copy of the characters
;; (the shadow) is what CON_RDCH reads. In ZEsarUX with its debug ports,
;; everything printed goes to its byte file too: the test transcript.
;;
;; GRAPHICS are the screen's pixels, from the CPC's logical 640 by 400: a
;; pixel is 2.5 units wide and 25/12 high -- the CPC's proportions.

    include "firmware.asm"
    include "jumps.asm"
    include "memmap.asm"

VCOLS       equ 40              ; as the CPC's mode 1: 240 pixels, centred
XLEFT       equ 8               ;   on the 256
VROWS       equ 24
PA_BUF      equ #3B00           ; the harness's paste: 256 bytes
SHADOW      equ #3C00           ; the characters on the screen, 40 x 24
FILL_STK    equ #3800           ; flood-fill's stack, to PA_BUF
FILL_END    equ #3B00

    org #2000
    assert $ == P_INIT
    jp m_init                   ; rs_boot calls this once
    assert $ == P_TICK
    jp m_tick                   ; the interrupt
    ;; the harness's paste (tools/spectrum/zx.py): a line given to KEY_READ
    ;; as if typed. It writes PA_BUF, PA_REC, PA_POS = 0 and then PA_LEN;
    ;; the keys come from there until PA_POS reaches PA_LEN, which is then
    ;; made 0. With PA_REC = n+1, the line from its byte n on goes into the
    ;; transcript as its return is read (the editor's own echo does not):
    ;; the harness types a space first, as the CPC's does, and leaves it
    ;; out of the transcript.
PA_LEN:     db 0                ; &2006
PA_POS:     db 0
PA_REC:     db 0
    db "ZX SPECTRUM MACHINE PAGE A",0
    defs MTAB-$,0
    include "mtab.inc"

;; ---------------------------------------------------------------------------
;; STATE

c_col:      db 0                ; 0-39, or 40: past the end
c_row:      db 0                ; 0-23
c_roll:     db 0                ; down by one a scroll
c_sys:      db 0                ; the cursor on (CON_CURON)
c_usr:      db 1                ;   and enabled (CON_CURENA)
c_drawn:    db 0                ; it is on the screen (the cell inverted)
c_esc:      db 0                ; 31 (locate): bytes still to come
c_parm:     db 0                ;   the column, when the row comes
c_echo:     db 0                ; 1: ZEsarUX's byte file gets it all too
c_pen:      db 1                ; the text pen, 0 or 1 (pixels lit)
c_paper:    db 0                ;   and paper
;; the sixteen inks' colours, the Spectrum's (8: bright), from the CPC's
;; defaults: ink 0 the paper's, 1 the text's, the rest the graphics pens'
c_inks:     db 1,14,13,10,15,0,9,11,5,6,13,11,12,12,9,11
c_ink0      equ c_inks
c_ink1      equ c_inks+1
c_border:   db 1
d_and:      db #FF              ; how a glyph is drawn: its pixels AND this,
d_xor:      db 0                ;   XOR this (the pen and paper)
d_sh:       db 0                ; the cell's shift in its byte,
d_mh:       db 0                ;   the masks of what is not the cell's
d_ml:       db 0
k_back:     db 0                ; KEY_UNREAD's character, 0 if none
g_x:        dw 0                ; graphics: where the last one ended,
g_y:        dw 0
g_ox:       dw 0                ;   the origin,
g_oy:       dw 0
g_pen:      db 1                ;   1 draws, 0 erases,
g_ink:      db 0                ;   ink-mode: 0 plain, 1 XOR, 2 AND, 3 OR
l_x0:       dw 0                ; a line: from,
l_y0:       dw 0
l_x1:       dw 0                ;   to (pixels),
l_y1:       dw 0
l_dx:       dw 0
l_dy:       dw 0
l_sx:       dw 0
l_sy:       dw 0
l_err:      dw 0

;; m_init: from rs_boot, once
m_init:
    ld bc,ZX_DBGREG             ; ZEsarUX? Its version, "13.0", from
    ld a,4                      ;   register 4
    out (c),a
    ld b,ZX_DBGDAT >> 8
    xor a
    out (c),a
    in a,(c)
    sub '0'
    cp 10
    ld a,0
    jr nc,.real
    ld b,ZX_DBGREG >> 8
    ld a,6                      ; register 6 from now on: the byte file
    out (c),a
    ld a,1
.real:
    ld (c_echo),a
    xor a
    ld (k_back),a
    ld (c_drawn),a
    ld (c_sys),a
    ld (c_esc),a
    ld (c_roll),a
    ld (g_ink),a
    ld (PA_LEN),a
    ld (PA_POS),a
    ld (c_paper),a
    inc a
    ld (c_usr),a
    ld (g_pen),a
    ld (c_pen),a
    call c_colours
    ld hl,0
    ld (g_x),hl
    ld (g_y),hl
    ld (g_ox),hl
    ld (g_oy),hl
    call k_init
    call s_init
    ld a,(c_border)
    call v_border
    jp c_clear

;; m_tick: the interrupt's work, 50 times a second, from the resident part
;; (AF, BC, DE, HL, IX saved there): the clock, the keys, the sound. IY
;; and the alternate registers are not touched.
m_tick:
    ld hl,(RS_FRAMES)
    ld de,6
    add hl,de
    ld (RS_FRAMES),hl
    jr nc,.c
    ld hl,(RS_FRAMES+2)
    inc hl
    ld (RS_FRAMES+2),hl
.c:
    call k_tick
    jp s_tick

;; ---------------------------------------------------------------------------
;; DRAWING A CHARACTER

;; d_addr: B = column, C = row -> DE = the cell's first pixel line, d_sh
;; its shift in that byte, d_mh and d_ml the masks of what is not the
;; cell's in it and the next (d_ml &FF: the cell is in one byte). BC kept.
d_addr:
    ld a,b
    add a,a
    add a,b
    add a,a
    add a,XLEFT                 ; x = 6 column + 8
    ld e,a
    and 7
    ld (d_sh),a
    push bc
    ld hl,#FC00                 ; the cell's six pixels
    or a
    jr z,.m1
    ld b,a
.m0:
    srl h
    rr l
    djnz .m0
.m1:
    ld a,h
    cpl
    ld (d_mh),a
    ld a,l
    cpl
    ld (d_ml),a
    pop bc
    ld a,e
    rrca
    rrca
    rrca
    and 31
    ld e,a                      ; the byte's column
    ld a,c
    and #18
    or #40
    ld d,a                      ; the row's third
    ld a,c
    and 7
    rrca
    rrca
    rrca
    or e
    ld e,a
    ret

;; d_cell: A = a character, B = column, C = row -> its glyph drawn there,
;; its pixels AND d_and XOR d_xor. BC kept; IX lost.
d_cell:
    sub 32
    cp 96
    jr c,.ok
    ld a,'?'-32
.ok:
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    push de
    ld de,font
    add hl,de
    pop de
    push hl
    call d_addr
    pop ix                      ; IX = the glyph
    push bc
    ld b,8
.line:
    ld a,(d_and)
    and (ix+0)
    ld h,a
    ld a,(d_xor)
    xor h
    ld h,a
    ld l,0                      ; HL = the line's six pixels, bits 15-10
    ld a,(d_sh)
    or a
    jr z,.put
    ld c,a
.sh:
    srl h
    rr l
    dec c
    jr nz,.sh
.put:
    ex de,hl                    ; HL = the screen, DE = the pixels
    ld a,(d_mh)
    and (hl)
    or d
    ld (hl),a
    ld a,(d_ml)
    cp #FF
    jr z,.next
    inc l
    and (hl)
    or e
    ld (hl),a
    dec l
.next:
    inc h                       ; the next pixel line
    ex de,hl
    inc ix
    djnz .line
    pop bc
    ret

;; d_inv: B = column, C = row -> the cell's pixels inverted (the cursor).
;; BC kept.
d_inv:
    call d_addr
    ex de,hl
    push bc
    ld b,8
.l:
    ld a,(d_mh)
    cpl
    xor (hl)
    ld (hl),a
    ld a,(d_ml)
    cpl
    or a
    jr z,.n
    inc l
    xor (hl)
    ld (hl),a
    dec l
.n:
    inc h
    djnz .l
    pop bc
    ret

;; c_colours: the pen and paper into d_and and d_xor: the glyph as it is
;; (pen 1, paper 0), inverted (0, 1), blank (0, 0) or solid (1, 1)
c_colours:
    ld a,(c_pen)
    or a
    ld a,#FF
    jr nz,.p
    xor a
.p:
    ld (d_and),a
    ld a,(c_paper)
    or a
    jr z,.q
    ld a,#FC
.q:
    ld (d_xor),a
    ld a,(c_pen)                ; pen 0 on paper 1: the glyph's holes lit
    or a
    ret nz
    ld a,(c_paper)
    or a
    ret z
    ld a,#FF
    ld (d_and),a
    ret

;; ---------------------------------------------------------------------------
;; CONSOLE

;; c_shadow: B = column, C = row -> HL = their place in the shadow. BC, DE
;; kept.
c_shadow:
    push de
    ld l,c
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl                   ; 8r
    ld d,h
    ld e,l
    add hl,hl
    add hl,hl                   ; 32r
    add hl,de                   ; 40r
    ld e,b
    ld d,SHADOW >> 8
    add hl,de
    pop de
    ret
    assert VCOLS == 40

;; c_at: -> B = the cursor's column, C = its row
c_at:
    ld a,(c_col)
    ld b,a
    ld a,(c_row)
    ld c,a
    ret

;; c_hide: the cursor off the screen, if it is on it. All kept but AF.
c_hide:
    ld a,(c_drawn)
    or a
    ret z
    xor a
    ld (c_drawn),a
c_xcur:
    push bc
    push de
    push hl
    call c_at
    call d_inv
    pop hl
    pop de
    pop bc
    ret

;; c_show: the cursor drawn, if it is on and enabled. All kept but AF.
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
    ld a,1
    ld (c_drawn),a
    jr c_xcur

;; c_echoc: C to the transcript (ZEsarUX's byte file). All kept but AF.
c_echoc:
    ld a,(c_echo)
    or a
    ret z
    push bc
    ld a,c
    ld bc,ZX_DBGDAT
    out (c),a
    pop bc
    ret

;; c_put: C = a character, at the cursor; the cursor on. BC, DE, HL, IX
;; corrupt.
c_put:
    ld a,(c_col)
    cp VCOLS
    call nc,c_wrap
    push bc
    call c_at
    call c_shadow
    pop de
    ld (hl),e
    ld a,e
    call d_cell
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

;; c_scroll: the screen up a row, the bottom row cleared
c_scroll:
    push bc
    push de
    push hl
    ld c,0                      ; the row copied into
.row:
    push bc
    call c_line0
    push hl
    inc c
    call c_line0
    pop de                      ; HL = row c+1's first line, DE = row c's
    ld b,8
.line:
    push bc
    push hl
    push de
    ld bc,32
    ldir
    pop de
    pop hl
    inc h
    inc d
    pop bc
    djnz .line
    pop bc
    inc c
    ld a,c
    cp VROWS-1
    jr c,.row
    ld hl,SHADOW+VCOLS
    ld de,SHADOW
    ld bc,VCOLS*(VROWS-1)
    ldir
    ld a,VROWS-1
    call c_clrrow
    ld hl,c_roll
    dec (hl)
    pop hl
    pop de
    pop bc
    ret

;; c_line0: C = a row -> HL = its first pixel line's start. BC, DE kept.
c_line0:
    ld a,c
    and #18
    or #40
    ld h,a
    ld a,c
    and 7
    rrca
    rrca
    rrca
    ld l,a
    ret

;; c_fill: -> A = the paper's byte: 0, or &FF for paper 1
c_fill:
    ld a,(c_paper)
    or a
    ret z
    ld a,#FF
    ret

;; c_clrrow: A = a row -> its pixels the paper's, its shadow blank
c_clrrow:
    push bc
    push de
    push hl
    ld c,a
    call c_line0
    call c_fill
    ld e,a
    ld b,8
.l:
    push bc
    push hl
    ld b,32
.b:
    ld (hl),e
    inc l
    djnz .b
    pop hl
    inc h
    pop bc
    djnz .l
    ld b,0
    call c_shadow
    ld b,VCOLS
.s:
    ld (hl),' '
    inc hl
    djnz .s
    pop hl
    pop de
    pop bc
    ret

;; c_clear: the screen blank, the cursor home
c_clear:
    call c_fill
    ld hl,SCREEN
    ld de,SCREEN+1
    ld bc,6143
    ld (hl),a
    ldir
    ld hl,SHADOW
    ld de,SHADOW+1
    ld bc,VCOLS*VROWS-1
    ld (hl),' '
    ldir
    call c_attrs
    xor a
    ld (c_col),a
    ld (c_row),a
    ld (c_drawn),a
    ret

;; c_attrs: the whole screen's attributes from the two inks
c_attrs:
    ld a,(c_ink0)
    and 7
    rlca
    rlca
    rlca
    ld b,a
    ld a,(c_ink1)
    ld c,a
    and 7
    or b
    bit 3,c
    jr z,.nb
    or #40                      ; bright: the pen's says
.nb:
    ld hl,ATTRS
    ld de,ATTRS+1
    ld bc,767
    ld (hl),a
    ldir
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

;; c_beep: the bell -- a short note on the speaker (port &FE bit 4)
c_beep:
    push bc
    push de
    ld d,100                    ; 100 cycles of 1 ms
.c:
    ld a,(c_border)
    or #10
    out (P_ULA),a
    ld b,135
.h1:
    djnz .h1
    ld a,(c_border)
    out (P_ULA),a
    ld b,135
.h2:
    djnz .h2
    dec d
    jr nz,.c
    pop de
    pop bc
    ret

;; CON_PUTC: A = a character, or a control. Every register kept.
m_con_putc:
    push af
    push bc
    push de
    push hl
    push ix
    ld c,a
    call c_echoc
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
    cp 7
    jr z,.bell
    cp 30
    jr z,.home
    cp 31
    jr z,.locate
    jr .done                    ; the rest: nothing
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
.bell:
    call c_beep
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
    pop ix
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
    push ix
    ld c,a
    call c_hide
    call c_put
    call c_show
    pop ix
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
    push bc
    push hl
    call c_at
    call c_shadow
    ld a,(hl)
    pop hl
    pop bc
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

;; CON_GETWIN: the whole screen -> H, D = columns 0, 39; L, E = rows 0, 23
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

;; CON_INVERSE: the pen and paper swapped
m_con_inverse:
    push af
    ld a,(c_pen)
    push af
    ld a,(c_paper)
    ld (c_pen),a
    pop af
    ld (c_paper),a
    call c_colours
    pop af
    ret
;; CON_PEN, CON_PAPER: A = a pen: 0 is the paper's ink, any other the pen's
m_con_pen:
    call c_01
    ld (c_pen),a
    jp c_colours
m_con_paper:
    call c_01
    ld (c_paper),a
    jp c_colours
c_01:
    or a
    ret z
    ld a,1
    ret

;; ---------------------------------------------------------------------------
;; VIDEO

;; VID_MODE: one mode only; the screen is cleared, as the CPC's is
m_vid_mode:
    jp m_con_cls

;; VID_INK: A = an ink, B = a colour (the CPC's 0-26) -> that ink's colour:
;; for ink 0 the paper's and 1 the pen's, on the whole screen (the
;; graphics' colours go); the others the graphics pens' (g_set)
m_vid_ink:
    push bc
    push de
    push hl
    and 15
    ld c,a
    ld a,b
    call v_colour
    ld b,0
    ld hl,c_inks
    add hl,bc
    ld (hl),a
    ld a,c
    cp 2
    call c,c_attrs
    pop hl
    pop de
    pop bc
    ret

;; v_colour: A = a CPC colour, 0-26 -> the Spectrum's nearest, 0-7, +8 if
;; bright
v_colour:
    cp 27
    jr c,.ok
    ld a,26
.ok:
    push hl
    ld hl,v_colours
    add a,l
    ld l,a
    jr nc,.n
    inc h
.n:
    ld a,(hl)
    pop hl
    ret
v_colours:
    db 0,1,9,2,3,3,10,3,11,4,5,13,6,7,13,10,11,11,12,12,13,12,12,13,14,14,15

;; VID_BORDER: B = a colour (the CPC's)
m_vid_border:
    push bc
    ld a,b
    call v_colour
    and 7
    ld (c_border),a
    pop bc
v_border:
    and 7
    out (P_ULA),a
    ret

;; VID_FRAME: until the next frame's interrupt
m_vid_frame:
    push hl
    ld hl,RS_FRAMES
    ld a,(hl)
.w:
    cp (hl)
    jr z,.w
    pop hl
    ret

;; VID_FILLBOX: A = the paper (VID_PAPER), H, D = columns, L, E = rows, from
;; 0 -> those cells blank. Whole rows a byte at a time.
m_vid_fillbox:
    push bc
    push de
    push hl
    push ix
    call c_hide
    ld a,h
    or a
    jr nz,.cells
    ld a,d
    cp VCOLS-1
    jr c,.cells
.rows:
    ld a,l
    call c_clrrow
    ld a,l
    inc l
    cp e
    jr c,.rows
    jr .done
.cells:
    ld c,l                      ; row
.crow:
    ld b,h                      ; column, from the left
.ccol:
    push bc
    push de
    push hl
    call c_shadow
    ld (hl),' '
    ld a,' '
    call d_cell
    pop hl
    pop de
    pop bc
    ld a,b
    inc b
    cp d
    jr c,.ccol
    ld a,c
    inc c
    cp e
    jr c,.crow
.done:
    pop ix
    pop hl
    pop de
    pop bc
    ret

;; M_VIDCHAR: A = a character, B = column, C = row, from 0; D = 1 to draw
;; it inverse -> drawn (the function editor's renderer, fr.asm). BC, DE,
;; HL kept.
m_m_vidchar:
    push bc
    push de
    push hl
    push ix
    push af
    call c_shadow
    pop af
    ld (hl),a
    ld e,a
    ld hl,(d_and)               ; (d_and, d_xor)
    push hl
    ld a,d
    or a
    ld hl,#00FF                 ; as it is
    jr z,.n
    ld hl,#FCFF                 ; inverse
.n:
    ld (d_and),hl
    ld a,e
    call d_cell
    pop hl
    ld (d_and),hl
    pop ix
    pop hl
    pop de
    pop bc
    ret

;; ---------------------------------------------------------------------------
;; KEYS: our own scan, from the interrupt, into a queue of codes -- the
;; CPC's codes for the editing keys:
;;   EDIT (CAPS SHIFT 1) COPY, DELETE (CAPS 0) DEL, the cursor keys (CAPS
;;   5-8) the arrows, TRUE VIDEO (CAPS 3) TAB, INV VIDEO (CAPS 4) CLR,
;;   GRAPH (CAPS 9) CTRL-S, BREAK (CAPS SPACE) ESC, CAPS LOCK (CAPS 2)
;;   locks the capitals; EXTEND (CAPS and SYMBOL SHIFT) and then a cursor
;;   key: SHIFT with it, the copy cursor
;; and SYMBOL SHIFT the keyboard's symbols, with [ ] { } ~ | \ (its EXTEND
;; ones) and the backquote on Y U F G A S D X directly.

KQ          equ 16              ; the queue's size
REPDEL      equ 25              ; frames before a held key repeats,
REPPER      equ 3               ;   and between its repeats

k_mat:      defs 8,0            ; the matrix as last read, 1 = down
k_last:     db #FF              ; the key held, or &FF
k_cnt:      db 0                ;   frames until it repeats
k_ext:      db 0                ; 1: EXTEND, waiting for its key
k_lock:     db 0                ; 1: CAPS LOCK
k_in:       db 0                ; the queue: where the next goes in,
k_out:      db 0                ;   where the next comes out
k_q:        defs KQ,0

;; the keys, by half-row (&FEFE ... &7FFE) and bit: plain, CAPS SHIFT,
;; SYMBOL SHIFT. 0 is none; &FE is CAPS LOCK.
k_plain:
    db 0,'z','x','c','v',  'a','s','d','f','g',  'q','w','e','r','t'
    db '1','2','3','4','5',  '0','9','8','7','6',  'p','o','i','u','y'
    db 13,'l','k','j','h',  ' ',0,'m','n','b'
k_caps:
    db 0,'Z','X','C','V',  'A','S','D','F','G',  'Q','W','E','R','T'
    db #E0,#FE,9,#10,#F2,  #7F,#13,#F3,#F0,#F1,  'P','O','I','U','Y'
    db 13,'L','K','J','H',  #FC,0,'M','N','B'
k_sym:
    db 0,':','`','?','/',  '~','|',#5C,'{','}',  0,0,0,'<','>'
    db '!','@','#','$','%',  '_',')','(',"'",'&',  '"',';',0,']','['
    db 13,'=','+','-','^',  ' ',0,'.',',','*'

;; k_init: the queue empty, nothing held
k_init:
    xor a
    ld (k_in),a
    ld (k_out),a
    ld (k_ext),a
    ld (k_lock),a
    dec a
    ld (k_last),a
    ret

;; k_tick: the matrix read, a key newly down (or held long enough) queued
k_tick:
    ld hl,k_mat
    ld bc,#FEFE
.r:
    in a,(c)
    cpl
    and #1F
    ld (hl),a
    inc hl
    rlc b
    jr c,.r
    ; the first key down that is not a shift: E = its number, row * 5 + bit
    ld hl,k_mat
    ld e,0
    ld c,8
.row:
    ld a,(hl)
    ld b,5
.bit:
    rra
    jr nc,.up
    push af
    ld a,e
    or a
    jr z,.skip                  ; CAPS SHIFT
    cp 36
    jr z,.skip                  ; SYMBOL SHIFT
    pop af
    jr .key
.skip:
    pop af
.up:
    inc e
    djnz .bit
    inc hl
    dec c
    jr nz,.row
    ; no key: both shifts together are EXTEND
    ld a,(k_mat)
    rra
    jr nc,.none
    ld a,(k_mat+7)
    and 2
    jr z,.none
    ld e,40                     ; EXTEND, as a key
.key:
    ld a,(k_last)
    cp e
    jr z,.held
    ld a,e
    ld (k_last),a
    ld a,REPDEL
    ld (k_cnt),a
    jr k_emit
.held:
    ld hl,k_cnt
    dec (hl)
    ret nz
    ld (hl),REPPER
    ld a,e
    cp 40
    ret z                       ; EXTEND does not repeat
    jr k_emit
.none:
    ld a,#FF
    ld (k_last),a
    ret

;; k_emit: E = a key's number -> its code queued, as the shifts say
k_emit:
    ld a,e
    cp 40
    jr nz,.k
    ld a,1
    ld (k_ext),a
    ret
.k:
    ld a,(k_mat)
    and 1
    ld b,a                      ; B: CAPS SHIFT
    ld a,(k_mat+7)
    and 2
    ld c,a                      ; C: SYMBOL SHIFT
    ld d,0
    ld a,(k_ext)
    or a
    jr z,.plain
    xor a
    ld (k_ext),a
    ld a,e                      ; EXTEND: the cursor keys with SHIFT
    cp 19
    ld a,#F6                    ; 5: left
    jr z,k_queue
    ld a,e
    sub 20
    jr c,.sym
    cp 5
    jr nc,.sym
    ld hl,k_xcur                ; 0 9 8 7 6: -, -, right, up, down
    add a,l
    ld l,a
    jr nc,.x
    inc h
.x:
    ld a,(hl)
    or a
    jr nz,k_queue
.sym:
    inc c
    dec c
    ret z                       ; EXTEND and no SYMBOL SHIFT: nothing
.plain:
    ld hl,k_sym
    inc c
    dec c
    jr nz,.look
    ld hl,k_caps
    inc b
    dec b
    jr nz,.look
    ld hl,k_plain
.look:
    add hl,de
    ld a,(hl)
    or a
    ret z
    cp #FE
    jr z,.lock
    cp 'a'
    jr c,k_queue
    cp 'z'+1
    jr nc,k_queue
    ld c,a
    ld a,(k_lock)
    or a
    ld a,c
    jr z,k_queue
    and #DF                     ; CAPS LOCK
    jr k_queue
.lock:
    ld a,(k_lock)
    xor 1
    ld (k_lock),a
    ret
k_xcur:     db 0,0,#F7,#F4,#F5

;; k_queue: A = a code -> into the queue, unless it is full
k_queue:
    ld c,a
    ld a,(k_in)
    ld b,a
    inc a
    and KQ-1
    ld hl,k_out
    cp (hl)
    ret z                       ; full
    ld (k_in),a
    ld a,b
    ld hl,k_q
    add a,l
    ld l,a
    jr nc,.n
    inc h
.n:
    ld (hl),c
    ret

;; k_pop: -> carry and A = the next code from the queue; NC if it is empty.
;; BC, DE, HL kept.
k_pop:
    push hl
    ld a,(k_out)
    ld hl,k_in
    cp (hl)
    jr z,.none
    push af
    inc a
    and KQ-1
    ld (k_out),a
    pop af
    ld hl,k_q
    add a,l
    ld l,a
    jr nc,.n
    inc h
.n:
    ld a,(hl)
    pop hl
    scf
    ret
.none:
    pop hl
    or a
    ret

;; k_paste: -> carry and A = the next character of the harness's paste; NC
;; if there is none. At its end PA_LEN is made 0. As the first is read, a
;; line to be recorded goes into the transcript (k_record) -- where the
;; CPC's harness writes it, before the editor answers it (a beep). BC, DE,
;; HL kept.
k_paste:
    ld a,(PA_LEN)
    or a
    ret z
    push bc
    push hl
    ld c,a
    ld a,(PA_POS)
    cp c
    jr nc,.end
    or a
    call z,k_record
    ld a,(PA_POS)
    ld l,a
    inc a
    ld (PA_POS),a
    ld h,PA_BUF >> 8
    ld a,(hl)
    pop hl
    pop bc
    scf
    ret
.end:
    xor a
    ld (PA_LEN),a
    pop hl
    pop bc
    or a
    ret
;; k_record: C = PA_LEN -> with PA_REC = n+1, the paste from its byte n to
;; its return into the transcript
k_record:
    ld a,(PA_REC)
    or a
    ret z
    dec a
    ld l,a
    ld h,PA_BUF >> 8
.r:
    ld a,l
    cp c
    ret nc
    ld a,(hl)
    cp 13
    ret z
    push bc
    ld c,a
    call c_echoc
    pop bc
    inc l
    jr .r

;; KEY_READ: -> carry and A = a character; no carry if there is none
m_key_read:
    call k_backed
    ret c
    call k_paste
    ret c
    jp k_pop

;; KEY_WAIT: -> A = a character
m_key_wait:
    call m_key_read
    ret c
    halt
    jr m_key_wait

;; k_backed: -> carry and A = KEY_UNREAD's character, if there is one
k_backed:
    ld a,(k_back)
    or a
    ret z
    push af
    xor a
    ld (k_back),a
    pop af
    scf
    ret

;; KEY_UNREAD: A = a character, read next
m_key_unread:
    ld (k_back),a
    ret

;; KEY_TEST: A = a key number, half-row * 8 + bit (the half-rows &FEFE,
;; &FDFE ... &7FFE as 0-7), or 64 for BREAK (CAPS SHIFT and SPACE) -> NZ if
;; it is down. BC, DE, HL kept.
m_key_test:
    push bc
    cp 64
    jr z,.brk
    ld c,a
    rrca
    rrca
    rrca
    and 7
    ld b,a
    ld a,#FE                    ; the half-row's address: A8-A15 with its
    inc b                       ;   bit 0
.r:
    dec b
    jr z,.got
    rlca
    jr .r
.got:
    in a,(P_ULA)                ; (the port's high byte is A)
    cpl
    ld b,a
    ld a,c
    and 7
    inc a
    ld c,a
    ld a,b
.b:
    dec c
    jr z,.t
    rrca
    jr .b
.t:
    and 1
    pop bc
    ret
.brk:
    ld a,#FE
    in a,(P_ULA)
    ld b,a
    ld a,#7F
    in a,(P_ULA)
    or b
    cpl
    and 1                       ; bit 0 of both: CAPS SHIFT and SPACE
    pop bc
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
    xor a                       ; floor(x / c) for x < 0:
    sub l                       ;   -((-x + c - 1) / c)
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
    jp g_neg
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
g_neg:
    xor a
    sub l
    ld l,a
    sbc a,a
    sub h
    ld h,a
    ret

;; g_pix: DE = x, HL = y, logical, from the origin -> DE = the pixel's
;; column, HL = its row, from the top (signed, perhaps off the screen)
g_pix:
    push hl
    ld hl,(g_ox)
    add hl,de
    ld c,62                     ; within +-15872
    call g_clamp
    add hl,hl
    ld c,5
    call g_div                  ; * 2 / 5
    ex (sp),hl                  ; the column kept; HL = y
    ld de,(g_oy)
    add hl,de
    ld c,10                     ; within +-2560
    call g_clamp
    add hl,hl
    add hl,hl                   ; * 4
    ld d,h
    ld e,l
    add hl,hl
    add hl,de                   ; * 12
    ld c,25
    call g_div                  ; / 25
    ex de,hl
    ld hl,191
    or a
    sbc hl,de                   ; rows go down
    pop de
    ret

;; g_cell: DE = column, HL = row, on the screen -> HL = the pixel's byte, C
;; = its bit. NC if off the screen.
g_cell:
    ld a,d
    or h
    ret nz                      ; (nz with carry clear: or)
    ld a,l
    cp 192
    ret nc
    and 7
    ld h,a
    ld a,l
    and #C0
    rrca
    rrca
    rrca
    or h
    or #40
    ld h,a
    ld a,l
    and #38
    rlca
    rlca
    ld l,a
    ld a,e
    rrca
    rrca
    rrca
    and 31
    or l
    ld l,a
    ld a,e
    and 7
    ld c,#80
    jr z,.b
.s:
    srl c
    dec a
    jr nz,.s
.b:
    scf
    ret

;; g_set: DE, HL = a pixel -> lit or put out, as the pen and ink-mode say;
;; a pen that lights it gives its cell its colour (the attribute's ink,
;; the paper's kept: the Spectrum's way -- text there takes it too)
g_set:
    call g_cell
    ret nc
    ld a,(g_pen)
    or a
    call nz,g_attr
    ld b,(hl)
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
    ld (hl),a
    ret
.xor:
    ld a,(g_pen)
    or a
    ret z
    ld a,b
    xor c
    ld (hl),a
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
    ld (hl),a
    ret

;; g_get: DE, HL = a pixel -> A = the pen whose colour its cell has, if it
;; is lit (1 if no pen has it); 0 if not (or off the screen)
g_get:
    call g_cell
    ld a,0
    ret nc
    ld a,(hl)
    and c
    ret z
    call g_atad
    ld a,(hl)
    and 7
    bit 6,(hl)
    jr z,.nb
    or 8
.nb:
    ld c,a                      ; the cell's colour
    ld hl,c_inks+1
    ld b,1
.p:
    ld a,(hl)
    cp c
    ld a,b
    ret z
    inc hl
    inc b
    ld a,b
    cp 16
    jr c,.p
    ld a,1
    ret

;; g_atad: HL = a pixel's byte on the screen -> HL = its cell's attribute.
;; BC, DE kept.
g_atad:
    ld a,h
    rrca
    rrca
    rrca
    and 3
    or ATTRS >> 8
    ld h,a
    ret

;; g_attr: HL = a pixel's byte -> its cell's ink the pen's colour. All kept
;; but AF.
g_attr:
    push bc
    push hl
    push de
    ld a,(g_pen)
    ld e,a
    ld d,0
    ld bc,c_inks
    ex de,hl
    add hl,bc
    ld a,(hl)                   ; the pen's colour
    ex de,hl
    ld c,a
    call g_atad
    ld a,(hl)
    and #38                     ; the paper's kept
    ld b,a
    ld a,c
    and 7
    or b
    bit 3,c
    jr z,.nb
    or #40
.nb:
    ld (hl),a
    pop de
    pop hl
    pop bc
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

;; GFX_PEN: A = a pen: 0 puts out, any other lights in its colour.
;; GFX_PAPER: nothing
m_gfx_pen:
    and 15
    ld (g_pen),a
    ret
m_gfx_paper:
    ret

;; M_INKMODE: A = how lines are drawn: 0 plain, 1 XOR, 2 AND, 3 OR (the
;; pen with what is there)
m_m_inkmode:
    and 3
    ld (g_ink),a
    ret

;; GFX_CLEAR: the screen blank (text and graphics share it); the position
;; at the origin
m_gfx_clear:
    call c_hide
    push bc
    push de
    push hl
    ld a,(c_col)
    push af
    ld a,(c_row)
    push af
    call c_clear
    pop af
    ld (c_row),a
    pop af
    ld (c_col),a
    ld hl,0
    ld (g_x),hl
    ld (g_y),hl
    pop hl
    pop de
    pop bc
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

;; M_FILL: DE = x, HL = y, logical -> the area around that pixel of its
;; colour, to where the other starts, made the pen's; the position there.
;; A row at a time: a run of pixels to its ends, the runs above and below
;; it noted on a stack to do next (FILL_STK). Two colours: a pixel painted
;; is no longer the area's, so nothing is done twice. IX corrupt.
m_m_fill:
    call m_gfx_move
    call g_pix
    ld a,d
    or h
    ret nz                      ; off the screen
    ld a,l
    cp 192
    ret nc
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
    dec ix
    dec ix
    ld e,(ix+0)                 ; E = a column,
    ld l,(ix+1)                 ;   L = a row
    ld d,0
    ld h,d
    call ff_is
    jr nz,.next                 ; done already
.left:
    ld a,e                      ; to the run's left end
    or a
    jr z,.run
    dec e
    call ff_is
    jr z,.left
    inc e
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
    cp 191
    jr nc,.right
    inc l                       ; the row below
    ld bc,ff_dn
    call ff_side
    dec l
.right:
    inc e
    jr nz,.r                    ; (past column 255: the run's end)
    jr .next
.done:
    pop af
    ld (g_ink),a
    ret
;; ff_side: E, L = a pixel next to the run, BC = its side's flag -> a run
;; starting there noted, if it is the area's and the pixel before it was
;; not
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
;; ff_push: E, L = a pixel -> on the stack (unless it is full)
ff_push:
    push hl
    push ix
    pop hl
    ld a,h
    cp FILL_END >> 8
    pop hl
    ret nc
    ld (ix+0),e
    ld (ix+1),l
    inc ix
    inc ix
    ret
;; ff_is: E, L = a pixel -> Z if it is the area's colour. BC, DE, HL kept.
ff_is:
    call ff_get
    push hl
    ld hl,ff_t
    cp (hl)
    pop hl
    ret
;; ff_get, ff_set: g_get, g_set on E, L (D = H = 0). BC, DE, HL kept.
ff_get:
    push bc
    push de
    push hl
    call g_get
    jr ff_pop
ff_set:
    push bc
    push de
    push hl
    call g_set
ff_pop:
    pop hl
    pop de
    pop bc
    ret
ff_t:       db 0                ; the area's colour
ff_up:      db 0                ; a run above noted, and not ended yet
ff_dn:      db 0                ;   below

;; ---------------------------------------------------------------------------
;; SOUND: sound.asm

    include "sound.asm"

;; ---------------------------------------------------------------------------
;; SYSTEM

;; SYS_TIME: -> DEHL = the 1/300 s since the start (the interrupt counts)
m_sys_time:
    di
    ld hl,(RS_FRAMES)
    ld de,(RS_FRAMES+2)
    ei
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

;; M_QUIT: in ZEsarUX (the tests), out of the emulator; on the machine, a
;; reset into its menu (the ROMs as at power-up; the DivMMC maps esxDOS in
;; at &0000 and starts it)
m_m_quit:
    ld a,(c_echo)
    or a
    jr z,.reset
    ld bc,ZX_DBGREG
    ld a,3
    out (c),a
    ld b,ZX_DBGDAT >> 8
    ld a,1
    out (c),a
.reset:
    di
    xor a
    ld bc,P_7FFD
    out (c),a
    ld hl,RS_MODEL
    cp (hl)
    jr nz,.r128                 ; (a 128 has no &1FFD)
    ld b,P_1FFD >> 8
    out (c),a
.r128:
    out (P_DIVMMC),a
    rst 0

;; M_MIDI: A = a byte -> out of the +2A's MIDI socket (not yet: nothing)
m_m_midi:
    ret

font:
    include "font.inc"

page_a_end:
    print "machine page A: ",page_a_end-#2000," bytes"
    assert page_a_end <= FILL_STK
    defs #4000-$,0

    include "pageb.asm"
