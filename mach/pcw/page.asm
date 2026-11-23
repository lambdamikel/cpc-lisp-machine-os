;; CPC Lisp -- the PCW's machine pages: the routines behind the machine
;; interface (mach/README.md has their contracts). Two blocks of 16 KB,
;; seen at &C000 while one of their routines runs -- in place of the image
;; that called (the resident part, resident.asm, maps them for each call
;; through the jumpblock, and the image back after): page A (SEG_A) the
;; screen, the keys, graphics and the interrupt's keys; page B (SEG_B,
;; pageb.asm) files, floats, sound and the RAM disc. Their variables are
;; in them too: the pages are RAM. One image of 32 KB, LISPM.ROM: page A,
;; then page B. (A routine here never reads the caller's image: whatever
;; it is handed is in Lisp's RAM.)
;;
;; THE SCREEN is the PCW's own, 720 by 256, in 90 columns and 32 rows of
;; eight by eight (a font of our own, font.inc: the Spectrum's made bold).
;; A character row is 720 bytes, eight bytes a character -- its eight
;; lines one after the other -- rows 0-21 in block 1, 22-31 in block 3 with
;; the roller RAM (its 256 words say where each line is): seen in the
;; WINDOW (&4000) for a moment, RS_P1 saying so. The rows scroll by the
;; roller: port &F6 shows another line at the top, the row going off it
;; cleared and seen again at the bottom -- c_top is the row at the top.
;; The console works as the CPC's text VDU does, as far as the Lisp asks
;; (the TRS-80's page is the pattern): a cursor that may stand one past
;; the last column until the next character wraps, a roll count that goes
;; down by one each scroll, the CPC's controls 7-13, 30 and 31. A copy of
;; the characters (the shadow) is what CON_RDCH reads. Under the test
;; harness everything printed goes into the transcript's ring too (T_BUF,
;; which tools/pcw/pcw.py empties).
;;
;; GRAPHICS are the screen's pixels, from the CPC's logical 640 by 400: a
;; pixel a unit wide (the 640 in the middle of the 720: a circle's walk,
;; a unit a step, leaves no gaps for flood-fill to leak through) and 25/16
;; high -- the CPC's proportions within a few per cent. One colour: a pen
;; lights a pixel, pen 0 puts it out.

    include "firmware.asm"
    include "jumps.asm"
    include "memmap.asm"

VCOLS       equ 90
VROWS       equ 32
XLEFT       equ 40              ; graphics' x 0, in pixels
FILL_STK    equ #DB00           ; flood-fill's stack, 512 entries of 4,
FILL_END    equ #E300           ;   to SHADOW
SHADOW      equ #E300           ; the characters on the screen, 90 x 32
PA_BUF      equ #EF00           ; the harness's paste: 256 bytes
T_BUF       equ #F000           ; the transcript's ring: 4 KB
T_MASK      equ #0FFF
    assert SHADOW+90*32 <= PA_BUF

    org #C000,#4000             ; (LISPM.ROM: page A, then page B)
    assert $ == P_INIT
    jp m_init                   ; rs_boot calls this once
    assert $ == P_TICK
    jp m_tick                   ; the interrupt
    ;; the harness's paste (tools/pcw/pcw.py): a line given to KEY_READ as
    ;; if typed. It writes PA_BUF, PA_REC, PA_POS = 0 and then PA_LEN; the
    ;; keys come from there until PA_POS reaches PA_LEN, which is then made
    ;; 0. With PA_REC = n+1, the line from its byte n on goes into the
    ;; transcript as its return is read (the editor's own echo does not):
    ;; the harness types a space first, as the CPC's does, and leaves it out
    ;; of the transcript. The transcript: T_BUF from T_OUT (the harness's)
    ;; to T_IN (ours), words; full, the machine waits for the harness.
PA_LEN:     db 0                ; &C006
PA_POS:     db 0
PA_REC:     db 0
T_IN:       dw 0
T_OUT:      dw 0
    db "PCW MACHINE PAGE A",0
    defs MTAB-$,0
    include "mtab.inc"

;; ---------------------------------------------------------------------------
;; STATE

c_col:      db 0                ; 0-89, or 90: past the end
c_row:      db 0                ; 0-31
c_top:      db 0                ; the screen row (of the 32 in the blocks)
                                ;   seen at the top
c_roll:     db 0                ; down by one a scroll
c_sys:      db 0                ; the cursor on (CON_CURON)
c_usr:      db 1                ;   and enabled (CON_CURENA)
c_drawn:    db 0                ; it is on the screen (the cell inverted)
c_esc:      db 0                ; 31 (locate): bytes still to come
c_parm:     db 0                ;   the column, when the row comes
c_echo:     db 0                ; 1: the harness gets it all too (T_BUF)
c_pen:      db 1                ; the text pen, 0 or 1 (pixels lit)
c_paper:    db 0                ;   and paper
c_inks:     db 1,24,20,6,26,0,2,8,10,12,14,16,18,22,1,16 ; (VID_INK's)
d_and:      db #FF              ; how a glyph is drawn: its pixels AND this,
d_xor:      db 0                ;   XOR this (the pen and paper)
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

;; m_init: from rs_boot, once (the interrupts off)
m_init:
    ld a,(RS_HARN)              ; the harness, if its disc said so
    ld (c_echo),a
    xor a
    ld (k_back),a
    ld (c_drawn),a
    ld (c_sys),a
    ld (c_esc),a
    ld (c_roll),a
    ld (c_top),a
    ld (g_ink),a
    ld (PA_LEN),a
    ld (PA_POS),a
    ld h,a
    ld l,a
    ld (T_IN),hl
    ld (T_OUT),hl
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
    call v_init
    di
    ret

;; m_tick: the interrupt's work, 50 times a second, from the resident part
;; (AF, BC, DE, HL, IX saved there): the drives' motors stopped once they
;; have been idle 2 s (RS_MOTOR), the keys. (The clock is the resident
;; part's, the sound page B's.) IY and the alternate registers are not
;; touched.
m_tick:
    ld a,(RS_MOTOR)
    or a
    jr z,.k
    dec a
    ld (RS_MOTOR),a
    jr nz,.k
    ld a,SC_MOTOFF
    out (P_SYS),a
.k:
    jp k_tick

;; ---------------------------------------------------------------------------
;; THE SCREEN'S MEMORY

;; s_tab: for each of the 32 rows in the blocks: &80 + its block, its first
;; byte in the WINDOW
s_tab:
    repeat SCR_SPLIT,rr,0
    db #80+BL_SCR0
    dw WINDOW+rr*720
    rend
    repeat VROWS-SCR_SPLIT,rr,0
    db #80+BL_SCR1
    dw WINDOW+rr*720
    rend

;; s_row: C = a row on the screen (0-31) -> A = &80 + its block, HL = its
;; first byte in the WINDOW. BC, DE kept. s_prow: A = a row in the blocks.
s_row:
    ld a,(c_top)
    add a,c
    and 31
s_prow:
    push de
    ld e,a
    ld d,0
    ld hl,s_tab
    add hl,de
    add hl,de
    add hl,de
    ld a,(hl)
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl
    pop de
    ret

;; s_map: A = &80 + a block -> it in the WINDOW (RS_P1 first: the
;; interrupt puts back what that says). s_unmap: Lisp's block again. All
;; kept (s_map: but nothing).
s_map:
    ld (RS_P1),a
    out (P_MAP1),a
    ret
s_unmap:
    push af
    ld a,#80+BL_MID
    ld (RS_P1),a
    out (P_MAP1),a
    pop af
    ret

;; v_init: the roller RAM -- line y of the screen at row y/8's line y mod 8
;; -- the screen cleared, the top line the roller's first, the screen on
v_init:
    ld a,#80+BL_SCR1
    call s_map
    ld ix,WINDOW+ROLLER
    ld b,0                      ; the line
.l:
    ld a,b
    rrca
    rrca
    rrca
    and 31
    push bc
    call s_prow                 ; A = the block, HL = WINDOW + its offset
    pop bc
    and 7
    rrca
    rrca
    rrca
    ld c,a                      ; the block, in bits 13-15: * 32 in the high byte
    ld de,-WINDOW
    add hl,de                   ; the offset (a multiple of 16)
    srl h
    rr l                        ; halved
    ld a,b
    and 7
    or l
    ld (ix+0),a
    ld a,h
    or c
    ld (ix+1),a
    inc ix
    inc ix
    inc b
    jr nz,.l
    call s_unmap
    ld a,BL_SCR1*32+ROLLER/512
    out (P_ROLLER),a
    xor a
    ld (c_top),a
    out (P_ORIGIN),a
    call c_clear
    ld a,#40                    ; on, not inverse
    out (P_VIDEO),a
    ret

;; ---------------------------------------------------------------------------
;; DRAWING A CHARACTER

;; d_cell: A = a character, B = column, C = row -> its glyph drawn there,
;; its pixels AND d_and XOR d_xor. BC kept; DE, HL, IX lost.
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
    ld de,font
    add hl,de
    push hl
    pop ix                      ; IX = the glyph
    call d_addr                 ; HL = the cell, its block in the WINDOW
    push bc
    ld a,(d_and)
    ld c,a
    ld a,(d_xor)
    ld b,a
    ld a,(ix+0)
    and c
    xor b
    ld (hl),a
    inc hl
    ld a,(ix+1)
    and c
    xor b
    ld (hl),a
    inc hl
    ld a,(ix+2)
    and c
    xor b
    ld (hl),a
    inc hl
    ld a,(ix+3)
    and c
    xor b
    ld (hl),a
    inc hl
    ld a,(ix+4)
    and c
    xor b
    ld (hl),a
    inc hl
    ld a,(ix+5)
    and c
    xor b
    ld (hl),a
    inc hl
    ld a,(ix+6)
    and c
    xor b
    ld (hl),a
    inc hl
    ld a,(ix+7)
    and c
    xor b
    ld (hl),a
    pop bc
    jp s_unmap

;; d_addr: B = column, C = row -> HL = the cell's first byte, its block in
;; the WINDOW (s_unmap after). BC, DE kept.
d_addr:
    call s_row
    call s_map
    push de
    ld e,b
    ld d,0
    ex de,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,de
    pop de
    ret

;; d_inv: B = column, C = row -> the cell inverted (the cursor). BC kept.
d_inv:
    push de
    push hl
    call d_addr
    ld e,8
.l:
    ld a,(hl)
    cpl
    ld (hl),a
    inc hl
    dec e
    jr nz,.l
    call s_unmap
    pop hl
    pop de
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
    ld a,#FF
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
    add hl,hl                   ; 2r
    ld d,h
    ld e,l
    add hl,hl
    add hl,hl                   ; 8r
    add hl,de                   ; 10r
    ld d,h
    ld e,l
    add hl,hl
    add hl,hl
    add hl,hl                   ; 80r
    add hl,de                   ; 90r
    ld de,SHADOW
    add hl,de
    ld e,b
    ld d,0
    add hl,de
    pop de
    ret
    assert VCOLS == 90

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
    call c_at
    call d_inv
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

;; c_echoc: C to the transcript (the harness's ring), waiting while it is
;; full. All kept but AF.
c_echoc:
    ld a,(c_echo)
    or a
    ret z
    push de
    push hl
.w:
    ld hl,(T_IN)
    inc hl
    ld a,h
    and T_MASK >> 8
    ld h,a
    ld de,(T_OUT)
    or a
    sbc hl,de
    jr z,.w                     ; full: the harness empties it
    ld hl,(T_IN)
    push hl
    ld de,T_BUF
    add hl,de
    ld (hl),c
    pop hl
    inc hl
    ld a,h
    and T_MASK >> 8
    ld h,a
    ld (T_IN),hl
    pop hl
    pop de
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

;; c_scroll: the screen up a row by the roller: the top row cleared, the
;; next one shown at the top -- the cleared one is the bottom now
c_scroll:
    push bc
    push de
    push hl
    ld a,(c_top)
    call s_prow
    call s_map
    call c_fill
    call c_bytes                ; the row's 720 bytes the paper's
    call s_unmap
    ld a,(c_top)
    inc a
    and 31
    ld (c_top),a
    add a,a
    add a,a
    add a,a
    out (P_ORIGIN),a
    ld hl,SHADOW+VCOLS
    ld de,SHADOW
    ld bc,VCOLS*(VROWS-1)
    ldir
    ld h,d
    ld l,e
    inc de
    ld (hl),' '
    ld bc,VCOLS-1
    ldir
    ld hl,c_roll
    dec (hl)
    pop hl
    pop de
    pop bc
    ret

;; c_bytes: HL = a row's first byte (in the WINDOW), A = a byte -> its 720
;; bytes that. BC, DE lost.
c_bytes:
    ld (hl),a
    ld d,h
    ld e,l
    inc de
    ld bc,719
    ldir
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
    call s_row
    call s_map
    call c_fill
    push bc
    call c_bytes
    pop bc
    call s_unmap
    ld b,0
    call c_shadow
    ld b,VCOLS
.b:
    ld (hl),' '
    inc hl
    djnz .b
    pop hl
    pop de
    pop bc
    ret

;; c_clear: the screen blank, the cursor home
c_clear:
    ld b,VROWS
.r:
    ld a,b
    dec a
    call c_clrrow
    djnz .r
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

;; c_beep: the bell -- the beeper on for a tenth of a second
c_beep:
    push bc
    ld a,SC_BEEPON
    out (P_SYS),a
    ld bc,#4000
.w:
    dec bc
    ld a,b
    or c
    jr nz,.w
    ld a,SC_BEEPOFF
    out (P_SYS),a
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

;; CON_GETWIN: the whole screen -> H, D = columns 0, 89; L, E = rows 0, 31
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

;; VID_INK: A = an ink, B = a colour (the CPC's 0-26): one colour here, so
;; only what it would make of the screen: ink 0 brighter than ink 1 is the
;; screen inverse (the CPC's brightness: 0-26 in nine steps of three)
m_vid_ink:
    push bc
    push hl
    and 15
    ld c,a
    ld a,b
    ld b,0
    ld hl,c_inks
    add hl,bc
    ld (hl),a
    ld a,c
    cp 2
    jr nc,.x
    ld a,(c_inks)
    ld b,a
    ld a,(c_inks+1)
    cp b                        ; carry: ink 1 below ink 0
    ld a,#40
    jr nc,.n
    ld a,#C0
.n:
    out (P_VIDEO),a
.x:
    pop hl
    pop bc
    ret

;; VID_BORDER: B = a colour: there is no border to colour
m_vid_border:
    ret

;; VID_FRAME: until the next frame (1/50 s: six ticks of the clock)
m_vid_frame:
    push bc
    push hl
    ld a,(RS_FRAMES)
    add a,6
    ld b,a
    ld hl,RS_FRAMES
.w:
    ld a,(hl)
    sub b
    jp m,.w
    pop hl
    pop bc
    ret

;; VID_FILLBOX: A = the paper (VID_PAPER), H, D = columns, L, E = rows, from
;; 0 -> those cells blank. Whole rows a row at a time.
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
    ld hl,#FFFF                 ; inverse
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
;;   the cursor keys the arrows (with SHIFT: the copy cursor; ALT: the
;;   CPC's CTRL ones), <-DEL DEL, DEL-> CLR, TAB, RETURN and ENTER, STOP
;;   and EXIT ESC (they interrupt), COPY and f1 COPY, f2 (SHIFT f1)
;;   CTRL-S (both the function editor's "done"), SHIFT LOCK locks the
;;   capitals, ALT with a letter its control code
;; and the PCW's characters, SHIFT the upper ones -- but for three a Lisp
;; wants more: 1/2 is ` (SHIFT @), the paragraph sign \ (SHIFT <), SHIFT 3
;; # (not the pound); EXTRA with the paragraph sign is |, with 1/2 ~, with
;; = ^. The keyboard is the last 16 bytes of block 3 (KEYMAP): a bit for
;; each key, 1 while it is down; bytes 9 and 10 swapped below bit 7 (as
;; MAME has them, the other way from ZEsarUX and John Elliott's notes):
;; both are taken.

KQ          equ 16              ; the queue's size
REPDEL      equ 25              ; ticks before a held key repeats,
REPPER      equ 3               ;   and between its repeats
KN_SHIFT    equ 21              ; byte * 8 + bit
KN_LOCK     equ 70
KN_EXTRA    equ 81
KN_ALT      equ 87
KN_ESC      equ 96              ; STOP or EXIT: machine.asm's KEY_ESC
KBYTES      equ 12

k_raw:      defs KBYTES,0       ; the keyboard as last read
k_mat:      defs KBYTES,0       ;   and merged, 1 = down
k_last:     db #FF              ; the key held, or &FF
k_cnt:      db 0                ;   ticks until it repeats
k_lock:     db 0                ; 1: SHIFT LOCK
k_in:       db 0                ; the queue: where the next goes in,
k_out:      db 0                ;   where the next comes out
k_q:        defs KQ,0

;; the keys, by byte and bit (byte * 8 + bit): plain, SHIFT. 0 is none;
;; &FE is SHIFT LOCK.
k_plain:
    db 0,0,#E0,0,0,0,#F3,0              ; f3 KP0 f1 PASTE KP9 KP6 right KP2
    db #FC,0,0,#E0,0,0,#F0,#F2          ; EXIT PTR CUT COPY KP8 KP4 up left
    db #10,']',13,'#',0,0,'`',0         ; DEL> ] RETURN # KP7 SHIFT 1/2 [+]
    db '=','-','[','p',#5C,';','/','.'
    db '0','9','o','i','l','k','m',','
    db '8','7','u','y','h','j','n',' '
    db '6','5','r','t','g','f','b','v'
    db '4','3','e','w','s','d','c','x'
    db '1','2',#FC,'q',9,'a',#FE,'z'    ; ... STOP q TAB a LOCK z
    db 0,0,0,0,0,0,0,#7F                ; <DEL
    db 0,0,0,0,0,13,#F1,0               ; f5 EXTRA CAN [-] f7 ENTER down ALT
    db 0,0,0,0,0,0,0,0
k_shift:
    db 0,0,#13,0,0,0,#F7,0
    db #FC,0,0,#E0,0,0,#F4,#F6
    db #10,'}',13,'>',0,0,'@',0
    db '+','_','{','P','<',':','?','.'
    db ')','(','O','I','L','K','M',','
    db '*','&','U','Y','H','J','N',' '
    db "'",'%','R','T','G','F','B','V'
    db '$','#','E','W','S','D','C','X'
    db '!','"',#FC,'Q',9,'A',#FE,'Z'
    db 0,0,0,0,0,0,0,#7F
    db 0,0,0,0,0,13,#F5,0
    db 0,0,0,0,0,0,0,0
    assert $-k_shift == 8*KBYTES
;; EXTRA's: the key, its character
k_extra:
    db 28,'|',22,'~',24,'^',0

;; k_init: the queue empty, nothing held, no lock
k_init:
    xor a
    ld (k_in),a
    ld (k_out),a
    ld (k_lock),a
    dec a
    ld (k_last),a
    ret

;; k_tick: the keyboard read, a key newly down (or held long enough) queued
k_tick:
    ld a,(RS_P1)
    push af
    ld a,#80+BL_KEYS
    ld (RS_P1),a
    out (P_MAP1),a
    ld hl,WINDOW+KEYMAP
    ld de,k_raw
    ld bc,KBYTES
    ldir
    pop af
    ld (RS_P1),a
    out (P_MAP1),a
    ld hl,k_raw
    ld de,k_mat
    ld bc,9
    ldir
    ld a,(k_raw+9)              ; bytes 9 and 10, bits 0-6: either way round
    ld b,a
    and #80
    ld (de),a
    inc de
    ld a,b
    and #7F
    ld hl,k_raw+10
    or (hl)
    ld (de),a
    inc de
    xor a
    ld (de),a
    ; the first key down that is not a shift: E = its number, byte * 8 + bit
    ld hl,k_mat
    ld e,0
    ld c,KBYTES
.row:
    ld a,(hl)
    ld b,8
.bit:
    rra
    jr nc,.up
    push af
    ld a,e
    cp KN_SHIFT
    jr z,.skip
    cp KN_EXTRA
    jr z,.skip
    cp KN_ALT
    jr z,.skip
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
    ld a,#FF                    ; none
    ld (k_last),a
    ret
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
    cp KN_LOCK
    ret z                       ; SHIFT LOCK does not repeat
    jr k_emit

;; k_emit: E = a key's number -> its code queued, as the shifts say
k_emit:
    ld a,(k_mat+10)
    and 2                       ; EXTRA: its few
    jr z,.plain
    ld hl,k_extra
.x:
    ld a,(hl)
    or a
    ret z
    inc hl
    cp e
    ld a,(hl)
    inc hl
    jr nz,.x
    jr k_queue
.plain:
    ld d,0
    ld hl,k_shift
    ld a,(k_mat+2)
    and #20                     ; SHIFT
    jr nz,.look
    ld hl,k_plain
.look:
    add hl,de
    ld a,(hl)
    or a
    ret z
    cp #FE
    jr z,.lock
    ld c,a
    ld a,(k_mat+10)
    and #80                     ; ALT: the CPC's CTRL -- a letter's control
    jr z,.nctl                  ;   code (and @ [ \ ] ^ _'s), the arrows'
    ld a,c                      ;   CTRL codes; the rest as they are
    cp #F0
    jr c,.ctl
    cp #F4
    jr nc,k_queue
    add a,8
    jr k_queue
.ctl:
    cp '@'
    jr c,k_queue
    cp #80
    jr nc,k_queue
    and #1F
    jr k_queue
.nctl:
    ld a,c
    cp 'a'
    jr c,k_queue
    cp 'z'+1
    jr nc,k_queue
    ld a,(k_lock)
    or a
    ld a,c
    jr z,k_queue
    and #DF                     ; SHIFT LOCK
    jr k_queue
.lock:
    ld a,(k_lock)
    xor 1
    ld (k_lock),a
    ret

;; k_queue: A = a code -> into the queue, unless it is full. ESC makes the
;; core look at the keys in its very next body: it looks only every 32nd
;; (V_BRK counts them down: src/eval.asm), and a body full of floats takes
;; a while (V_BRK's address: the core's, from post-build.sh)
k_queue:
    ld c,a
    cp #FC
    jr nz,.q
    ld a,1
    ld (V_BRK),a
.q:
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

;; KEY_TEST: A = a key number, byte * 8 + bit (bytes 0-11), or 96 for STOP
;; or EXIT -> NZ if it is down (the keyboard as the interrupt last read
;; it). BC, DE, HL kept.
m_key_test:
    push bc
    push hl
    cp KN_ESC
    jr z,.esc
    cp 8*KBYTES
    jr nc,.no
    ld c,a
    rrca
    rrca
    rrca
    and 31
    ld hl,k_mat
    add a,l
    ld l,a
    jr nc,.n
    inc h
.n:
    ld b,(hl)
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
    pop hl
    pop bc
    ret
.esc:
    ld a,(k_mat+8)
    and 4                       ; STOP
    ld b,a
    ld a,(k_mat+1)
    and 1                       ; EXIT
    or b
    pop hl
    pop bc
    ret
.no:
    xor a
    pop hl
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
    ld c,64                     ; within +-16384
    call g_clamp
    ld de,XLEFT
    add hl,de                   ; a unit a pixel, centred
    ex (sp),hl                  ; the column kept; HL = y
    ld de,(g_oy)
    add hl,de
    ld c,7                      ; within +-1792
    call g_clamp
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl                   ; * 16
    ld c,25
    call g_div                  ; / 25
    ex de,hl
    ld hl,255
    or a
    sbc hl,de                   ; rows go down
    pop de
    ret

;; M_NEXTY: HL = a y, logical, from the origin -> HL = the next y up on
;; another pixel row: y+1 or y+2, a row being 25/16 units. fill-box and
;; disc (lib/gfx.asm) step by it: every row once, none left out (two at a
;; time, as on the CPC, left every fourth row out). BC, DE kept. (The
;; Model 4's, mach/trs80m4/hires.asm.)
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

;; g_cell: DE = column, HL = row, on the screen -> HL = the pixel's byte
;; with its block in the WINDOW (s_unmap after), C = its bit. NC if off the
;; screen (nothing mapped). B lost; DE kept.
g_cell:
    ld a,h
    or a
    ret nz                      ; (nz with carry clear: or)
    ld a,d
    cp 720 >> 8
    jr c,.x
    ret nz
    ld a,e
    cp 720 and #FF
    ret nc
.x:
    ld a,(c_top)                ; the line in the blocks: + c_top * 8
    add a,a
    add a,a
    add a,a
    add a,l
    ld b,a
    rrca
    rrca
    rrca
    and 31
    call s_prow                 ; A = the block, HL = the row's start
    call s_map
    ld a,b
    and 7                       ; + the line in the row
    add a,l
    ld l,a
    jr nc,.l
    inc h
.l:
    push de                     ; + the column / 8 * 8
    ld a,e
    and #F8
    ld e,a
    add hl,de
    pop de
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

;; g_set: DE, HL = a pixel -> lit or put out, as the pen and ink-mode say
g_set:
    call g_cell
    ret nc
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
    jr .put
.xor:
    ld a,(g_pen)
    or a
    jp z,s_unmap
    ld a,b
    xor c
    jr .put
.and:
    ld a,(g_pen)
    or a
    jr z,.off
    jp s_unmap
.or:
    ld a,(g_pen)
    or a
    jp z,s_unmap
.on:
    ld a,b
    or c
.put:
    ld (hl),a
    jp s_unmap

;; g_get: DE, HL = a pixel -> A = 1 if it is lit, else 0 (and off the
;; screen)
g_get:
    call g_cell
    ld a,0
    ret nc
    ld a,(hl)
    call s_unmap
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

;; GFX_PEN: A = a pen: 0 puts out, any other lights. GFX_PAPER: nothing
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
    call fl_in                  ; both ends on the screen: the fast way
    jp c,fl_draw
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

;; THE FAST LINE: both ends on the screen. Bresenham's in the screen's own
;; terms: the byte and its bit moved along a step at a time (fl_xr...),
;; the block mapped only when a row in another one comes (fl_row); the
;; plot (fl_plot1, fl_plot2: four bytes) set for the ink-mode and the pen
;; before, the steps' calls set for the directions. Some 150 T-states a
;; pixel, against g_set's 700 and more. The error and the two distances
;; are in the alternate registers (the interrupt does not touch them).
fl_rs:      dw 0                ; the row's first byte (in the WINDOW)
fl_prow:    db 0                ; the row, of the 32 in the blocks
fl_line:    db 0                ; the line in it, 0-7
fl_ym:      db 0                ; &FF: y goes further than x

;; fl_in: -> carry if (l_x0, l_y0) and (l_x1, l_y1) are both on the screen
fl_in:
    ld de,(l_x0)
    ld hl,(l_y0)
    call .one
    ret nc
    ld de,(l_x1)
    ld hl,(l_y1)
.one:
    ld a,h
    or a
    ret nz                      ; (no carry: or)
    ld a,d
    cp 720 >> 8
    ret c
    ret nz
    ld a,e
    cp 720 and #FF
    ret

;; fl_draw: the line from (l_x0, l_y0) to (l_x1, l_y1), both on the screen
fl_draw:
    call fl_mode
    ret z                       ; the ink-mode and pen draw nothing
    ld hl,(l_x1)                ; dx = |x1 - x0|, the step
    ld de,(l_x0)
    ld bc,fl_xr
    or a
    sbc hl,de
    jr nc,.dxp
    ld bc,fl_xl
    call g_neg
.dxp:
    ld (l_dx),hl
    ld (fl_xs1+1),bc
    ld (fl_xs2+1),bc
    ld a,(l_y1)                 ; dy = |y1 - y0| (rows: below 256)
    ld hl,l_y0
    ld bc,fl_yd
    sub (hl)
    jr nc,.dyp
    ld bc,fl_yu
    neg
.dyp:
    ld l,a
    ld h,0
    ld (l_dy),hl
    ld (fl_ys1+1),bc
    ld (fl_ys2+1),bc
    ld hl,(l_dx)                ; which goes further: x or y
    ld de,(l_dy)
    or a
    sbc hl,de
    sbc a,a
    ld (fl_ym),a                ; &FF: y
    ld de,(l_x0)                ; the start: its byte, its bit
    ld a,(l_y0)
    ld l,a
    call fl_at
    ld a,(fl_ym)
    or a
    jr nz,fl_ymaj
    exx                         ; x the major: err = dx / 2
    ld de,(l_dx)                ; DE' = dx
    ld bc,(l_dy)                ; BC' = dy
    ld h,d
    ld l,e
    srl h
    rr l                        ; HL' = err
    exx
    ld de,(l_dx)
    inc de                      ; DE = the pixels: dx + 1
fl_xloop:
fl_plot1:
    ld a,(hl)
    or c
    ld (hl),a
    nop
    dec de
    ld a,d
    or e
    jp z,s_unmap
fl_xs1:
    call fl_xr
    exx
    or a
    sbc hl,bc                   ; err -= dy
    exx
    jr nc,fl_xloop
    exx
    add hl,de                   ; err += dx
    exx
fl_ys1:
    call fl_yd
    jr fl_xloop
fl_ymaj:
    exx
    ld de,(l_dy)                ; DE' = dy
    ld bc,(l_dx)                ; BC' = dx
    ld h,d
    ld l,e
    srl h
    rr l                        ; HL' = err
    exx
    ld de,(l_dy)
    inc de                      ; DE = the pixels: dy + 1
fl_yloop:
fl_plot2:
    ld a,(hl)
    or c
    ld (hl),a
    nop
    dec de
    ld a,d
    or e
    jp z,s_unmap
fl_ys2:
    call fl_yd
    exx
    or a
    sbc hl,bc                   ; err -= dx
    exx
    jr nc,fl_yloop
    exx
    add hl,de                   ; err += dy
    exx
fl_xs2:
    call fl_xr
    jr fl_yloop

;; fl_mode: the plot for the ink-mode and the pen into fl_plot1 and
;; fl_plot2 -> Z if it draws nothing
fl_mode:
    ld a,(g_pen)
    or a
    ld a,(g_ink)
    jr z,.pen0
    cp 2
    ret z                       ; AND with a lit pen: nothing changes
    ld hl,fl_or
    dec a
    jr nz,.set                  ; plain, OR: lit
    ld hl,fl_xor                ; XOR
    jr .set
.pen0:
    cp 1
    ret z                       ; XOR, OR with pen 0: nothing
    cp 3
    ret z
    ld hl,fl_clr                ; plain, AND: put out
.set:
    push hl
    ld de,fl_plot1
    ld bc,4
    ldir
    pop hl
    ld de,fl_plot2
    ld bc,4
    ldir
    or 1                        ; (NZ)
    ret
fl_or:      ld a,(hl) : or c : ld (hl),a : nop
fl_xor:     ld a,(hl) : xor c : ld (hl),a : nop
fl_clr:     ld a,c : cpl : and (hl) : ld (hl),a

;; fl_at: DE = a column, L = a row, on the screen -> HL = its byte, its
;; block in the WINDOW, C = its bit; fl_rs, fl_prow, fl_line set. DE kept.
fl_at:
    ld a,(c_top)
    add a,a
    add a,a
    add a,a
    add a,l                     ; its line in the blocks
    ld b,a
    and 7
    ld (fl_line),a
    ld a,b
    rrca
    rrca
    rrca
    and 31
    ld (fl_prow),a
    call s_prow
    ld (fl_rs),hl
    call s_map
    ld a,(fl_line)
    add a,l
    ld l,a
    jr nc,.n
    inc h
.n:
    push de
    ld a,e
    and #F8
    ld e,a
    add hl,de
    pop de
    ld a,e
    and 7
    ld c,#80
    ret z
    ld b,a
.s:
    srl c
    djnz .s
    ret

;; the steps: HL, C a pixel's byte and bit -> the next one's. B, DE kept
;; (fl_row's: AF).
fl_xr:                          ; right
    rrc c
    ret nc
    ld a,l
    add a,8
    ld l,a
    ret nc
    inc h
    ret
fl_xl:                          ; left
    rlc c
    ret nc
    ld a,l
    sub 8
    ld l,a
    ret nc
    dec h
    ret
fl_yd:                          ; down
    ld a,(fl_line)
    cp 7
    jr z,.row
    inc a
    ld (fl_line),a
    inc hl
    ret
.row:
    xor a
    ld (fl_line),a
    ld a,(fl_prow)
    inc a
    jr fl_row
fl_yu:                          ; up
    ld a,(fl_line)
    or a
    jr z,.row
    dec a
    ld (fl_line),a
    dec hl
    ret
.row:
    ld a,7
    ld (fl_line),a
    ld a,(fl_prow)
    dec a
;; fl_row: A = the row now (mod 32), HL still in the one before -> HL in
;; the new row, the same column, at fl_line; its block in the WINDOW
fl_row:
    and 31
    ld (fl_prow),a
    push de
    ld de,(fl_rs)
    or a
    sbc hl,de
    ld a,l
    and #F8
    ld l,a                      ; the column * 8
    push hl
    ld a,(fl_prow)
    call s_prow
    ld (fl_rs),hl
    ld e,a
    ld a,(RS_P1)
    cp e
    ld a,e
    call nz,s_map
    pop de
    add hl,de
    ld a,(fl_line)
    add a,l
    ld l,a
    jr nc,.n
    inc h
.n:
    pop de
    ret

;; M_FILL: DE = x, HL = y, logical -> the area around that pixel of its
;; colour, to where the other starts, made the pen's; the position there.
;; A row at a time: a run of pixels to its ends, the runs above and below
;; it noted on a stack to do next (FILL_STK: a column's two bytes and a
;; row's, and one spare). Two colours: a pixel painted is no longer the
;; area's, so nothing is done twice. IX corrupt.
m_m_fill:
    call m_gfx_move
    call g_pix
    ld a,h
    or a
    ret nz                      ; off the screen
    bit 7,d
    ret nz
    ld a,d
    cp 720 >> 8
    jr c,.in
    ret nz
    ld a,e
    cp 720 and #FF
    ret nc
.in:
    call ff_get
    ld (ff_t),a
    ld b,a
    ld a,(g_pen)
    or a
    jr z,.p0
    ld a,1
.p0:
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
    dec ix
    dec ix
    ld e,(ix+0)                 ; DE = a column,
    ld d,(ix+1)
    ld l,(ix+2)                 ;   L = a row
    ld h,0
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
    cp 255
    jr nc,.right
    inc l                       ; the row below
    ld bc,ff_dn
    call ff_side
    dec l
.right:
    inc de
    ld a,d
    cp 720 >> 8
    jr c,.r
    ld a,e
    cp 720 and #FF
    jr c,.r                     ; (past column 719: the run's end)
    jr .next
.done:
    pop af
    ld (g_ink),a
    ret
;; ff_side: DE, L = a pixel next to the run, BC = its side's flag -> a run
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
;; ff_push: DE, L = a pixel -> on the stack (unless it is full)
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
    inc ix
    inc ix
    inc ix
    inc ix
    ret
;; ff_is: DE, L = a pixel -> Z if it is the area's colour. BC, DE, HL kept.
ff_is:
    call ff_get
    push hl
    ld hl,ff_t
    cp (hl)
    pop hl
    ret
;; ff_get, ff_set: g_get, g_set on DE, L (H = 0). BC, DE, HL kept.
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
;; SYSTEM

;; SYS_TIME: -> DEHL = the 1/300 s since the start (the interrupt counts)
m_sys_time:
    di
    ld hl,(RS_FRAMES)
    ld de,(RS_FRAMES+2)
    ei
    ret

;; M_EDIT: a line typed into (HL), for when there is no library's editor
;; -> carry for ENTER, none for ESC
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

;; M_QUIT: the boot program again (RS_QUIT); under the harness, RS_QUITF
;; says so and the machine stops: the harness ends ZEsarUX
m_m_quit:
    ld a,(c_echo)
    or a
    jp z,RS_QUIT
    ld a,1
    ld (RS_QUITF),a
    di
    halt

;; M_MIDI: A = a byte -> nowhere: a PCW has no MIDI. Under the harness it
;; goes to the transcript, as <hex>. All kept but AF.
m_m_midi:
    push bc
    push hl
    ld l,a
    ld a,(c_echo)
    or a
    call nz,mi_echo
    pop hl
    pop bc
    ret
;; mi_echo: L = a byte -> "<hex>" into the transcript. HL kept.
mi_echo:
    ld c,'<'
    call c_echoc
    ld a,l
    rrca
    rrca
    rrca
    rrca
    call .hex
    ld a,l
    call .hex
    ld c,'>'
    jp c_echoc
.hex:
    and 15
    add a,'0'
    cp '9'+1
    jr c,.h
    add a,7
.h:
    ld c,a
    jp c_echoc

font:
    include "font.inc"

page_a_end:
    print "machine page A: ",page_a_end-#C000," bytes"
    assert page_a_end <= FILL_STK
    defs #10000-$,0

    include "pageb.asm"
