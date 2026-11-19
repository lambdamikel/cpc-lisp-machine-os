;; CPC Lisp on FutureOS itself -- the machine page: the CPC firmware's
;; routines that Lisp calls, done again without the firmware. A 16 KB image
;; of its own (LISP6.IMG), in bank 7's block 3, mapped at &C000 by the
;; resident part's trampolines (fwp) for each call; what needs the screen's
;; RAM -- which is at &C000 only in configuration C0 -- it asks the
;; resident part for (r_glyph, r_rowfill, r_rowcopy).
;;
;; Each routine keeps the contract of the firmware routine it stands for
;; (The Amstrad CPC Firmware Guide; mach/README.md says what Lisp relies
;; on): the text screen -- in mode 2 characters drawn by FutureOS's PR_2
;; --, the keys and the keyboard's scan, the screen's mode and inks,
;; graphics, sound, files through FutureOS.
;;
;; The text screen: 80 by 25 (mode 2) in the firmware's layout at &C000,
;; scrolled by the CRTC's start address (scr_off), as the firmware does; a
;; copy of the characters on it (shadow) for TXT RD CHAR, which the line
;; editor's copy cursor reads; the cursor is the character under it drawn
;; inverted.

    include "firmware.asm"      ; the names (and jumps.asm)
    include "memmap.asm"
    include "resident.inc"      ; the resident part's labels (post-build.sh)
    include "fos.asm"

ROWS        equ 25
KB_DELAY    equ 30              ; key repeat: after 30 scans (0.6 s),
KB_RATE     equ 2               ;   then every 2 (as the firmware's)

    org #C000
    include "pagetab.inc"       ; the firmware's names, in mkfw.py's order
    jp p_init                   ; LISP.64K's finisher calls it once
    jp p_tick                   ; the interrupt, 100 times a second

;; ---- the state ----
cmode:      db 2                ; the screen mode
ccols:      db 80               ; its columns
ccw:        db 1                ; bytes a character is wide
cmask:      db 1                ; the pens' mask: 1, 3, 15
win_l:      db 0                ; the text window, physical, from 0
win_r:      db 79
win_t:      db 0
win_b:      db 24
cur_c:      db 0                ; the cursor, physical (may be past the
cur_r:      db 0                ;   window's right: wrapped when used)
roll:       db 0                ; the roll count: down one each scroll up
pen:        db 1
paper:      db 0
cur_on:     db 0                ; TXT CUR ON/OFF (the system's)
cur_ena:    db 1                ; TXT CUR ENABLE/DISABLE (the user's)
cur_shown:  db 0                ; the cursor drawn now, at
cur_sc:     db 0                ;   this column
cur_sr:     db 0                ;   and row
scr_off:    dw 0                ; the screen's start, bytes (0-&7FE)
sh_top:     db 0                ; the shadow's row that is screen row 0
ctl_n:      db 0                ; a control code's parameters still to come
ctl_code:   db 0
ctl_par:    defs 9,0
ctl_p:      dw 0
km_back:    db 0                ; KM CHAR RETURN's character, 0 if none
m_first:    dw 256              ; SYMBOL: the first user-defined character
m_tab:      dw 0                ;   and their table
inks:       defs 17,0           ; the inks' hardware colours (16: border)

;; ---- the console ----

;; TXT OUTPUT: A = a character or a control code. All kept.
p_TXT_OUTPUT:
    push af
    push bc
    push de
    push hl
    call cur_hide
    call out_char
    call cur_show
    pop hl
    pop de
    pop bc
    pop af
    ret

;; TXT WR CHAR: A drawn as it is, the cursor moved on. All kept.
p_TXT_WR_CHAR:
    push af
    push bc
    push de
    push hl
    call cur_hide
    call put_char
    call cur_show
    pop hl
    pop de
    pop bc
    pop af
    ret

;; out_char: A, as TXT OUTPUT takes it (the cursor hidden)
out_char:
    ld c,a
    ld a,(ctl_n)
    or a
    jr z,.plain
    ld hl,(ctl_p)               ; a parameter
    ld (hl),c
    inc hl
    ld (ctl_p),hl
    dec a
    ld (ctl_n),a
    ret nz
    ld a,(ctl_code)
    jr ctl_do
.plain:
    ld a,c
    cp 32
    jp nc,put_char
    ld hl,ctl_npar              ; how many parameters it takes
    ld e,a
    ld d,0
    add hl,de
    ld b,(hl)
    inc b
    dec b
    jr z,ctl_do
    ld (ctl_code),a
    ld a,b
    ld (ctl_n),a
    ld hl,ctl_par
    ld (ctl_p),hl
    ret
ctl_npar:
    db 0,1,0,0,1,1,0,0, 0,0,0,0,0,0,1,1
    db 0,0,0,0,0,0,1,1, 0,9,4,0,3,2,0,2

;; ctl_do: A = a control code, its parameters in ctl_par
ctl_do:
    add a,a
    ld l,a
    ld h,0
    ld de,ctl_tab
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    jp (hl)
ctl_tab:
    dw c_none,c_sym,c_cdis,c_cena,c_mode,c_none,c_none,c_none ; 0-7
    dw c_left,c_right,c_down,c_up,c_cls,c_cr,c_paper,c_pen    ; 8-15
    dw c_delch,c_clrlb,c_clrle,c_clrwb,c_clrwe,c_none,c_none,c_none ; 16-23
    dw c_inv,c_none,c_win,c_none,c_ink,c_border,c_home,c_loc  ; 24-31
c_none:
    ret
c_sym:
    ld a,(ctl_par)
    jp put_char
c_cdis:
    xor a
    ld (cur_ena),a
    ret
c_cena:
    ld a,1
    ld (cur_ena),a
    ret
c_mode:
    ld a,(ctl_par)
    jp p_SCR_SET_MODE
c_left:
    ld hl,cur_c
    dec (hl)
    ret
c_right:
    ld hl,cur_c
    inc (hl)
    ret
c_down:
    ld a,(cur_r)
    inc a
    ld (cur_r),a
    jp val_row
c_up:
    ld a,(cur_r)
    dec a
    ld (cur_r),a
    jp val_row
c_cls:
    jp p_TXT_CLEAR_WINDOW
c_cr:
    ld a,(win_l)
    ld (cur_c),a
    ret
c_paper:
    ld a,(ctl_par)
    jp p_TXT_SET_PAPER
c_pen:
    ld a,(ctl_par)
    jp p_TXT_SET_PEN
c_inv:
    jp p_TXT_INVERSE
c_home:
    ld a,(win_l)
    ld (cur_c),a
    ld a,(win_t)
    ld (cur_r),a
    ret
c_loc:                          ; 31, column, row: from 1, in the window
    ld hl,(ctl_par)
    ld a,l
    ld l,h
    ld h,a
    jp p_TXT_SET_CURSOR
c_win:                          ; 26, left, right, top, bottom: from 1
    ld hl,ctl_par
    ld a,(hl)
    dec a
    ld h,a
    ld a,(ctl_par+1)
    dec a
    ld d,a
    ld a,(ctl_par+2)
    dec a
    ld l,a
    ld a,(ctl_par+3)
    dec a
    ld e,a
    jp p_TXT_WIN_ENABLE
c_ink:                          ; 28, ink, colour, colour
    ld bc,(ctl_par+1)
    ld b,c
    ld a,(ctl_par+2)
    ld c,a
    ld a,(ctl_par)
    jp p_SCR_SET_INK
c_border:                       ; 29, colour, colour
    ld bc,(ctl_par)
    ld a,b
    ld b,c
    ld c,a
    jp p_SCR_SET_BORDER
c_delch:                        ; 16: the character at the cursor
    call val_col
    ld a,(cur_c)
    ld b,a
    jp clr_part
c_clrlb:                        ; 17: the line from the window's left to it
    call val_col
    ld a,(win_l)
    ld b,a
    ld a,(cur_c)
    ld c,a
    ld a,(cur_r)
    jp clr_span
c_clrle:                        ; 18: the line from it to the window's right
    call val_col
    ld a,(cur_c)
    ld b,a
    ld a,(win_r)
    ld c,a
    ld a,(cur_r)
    jp clr_span
c_clrwb:                        ; 19: the window from its start to it
    call c_clrlb
    ld a,(win_t)
.l:
    ld hl,cur_r
    cp (hl)
    ret nc
    push af
    call clr_row
    pop af
    inc a
    jr .l
c_clrwe:                        ; 20: from it to the window's end
    call c_clrle
    ld a,(cur_r)
.l:
    inc a
    ld hl,win_b
    cp (hl)
    jr z,.last
    ret nc
.last:
    push af
    call clr_row
    pop af
    jr .l
clr_part:                       ; B = a column on the cursor's row
    ld c,b
    ld a,(cur_r)
    jp clr_span

;; put_char: A drawn at the cursor (wrapped and scrolled into the window
;; first), the cursor moved on
put_char:
    push af
    call val_col
    call val_row
    pop af
    ld bc,(cur_c)               ; C = column, B = row
    call draw_at
    ld hl,cur_c
    inc (hl)
    ret

;; val_col: the cursor's column into the window -- past its right, to the
;; next row's left; before its left (or below 0), to the row above's right
val_col:
    ld a,(win_l)
    ld b,a
    ld a,(cur_c)
    bit 7,a
    jr nz,.before
    cp b
    jr c,.before
    ld hl,win_r
    cp (hl)
    ret z
    ret c
    ld a,b
    ld (cur_c),a
    ld hl,cur_r
    inc (hl)
    ret
.before:
    ld a,(win_r)
    ld (cur_c),a
    ld hl,cur_r
    dec (hl)
    ret
;; val_row: the cursor's row into the window, scrolling it
val_row:
    ld a,(cur_r)
    bit 7,a
    jr nz,.above
    ld hl,win_t
    cp (hl)
    jr c,.above
    ld hl,win_b
    cp (hl)
    ret z
    ret c
    ld a,(hl)
    ld (cur_r),a
    jp scroll_up
.above:
    ld a,(win_t)
    ld (cur_r),a
    jp scroll_down

;; draw_at: A = a character, C = column, B = row (physical): drawn in the
;; text pen and paper, and kept in the shadow
draw_at:
    push bc
    push af
    call shadow_at
    pop af
    ld (hl),a
    pop bc
;; draw_cell: A, C = column, B = row: drawn in the text pen and paper.
;; In mode 2, a character of the lower ROM's font in two inks by FutureOS's
;; PR_2 (or PR_2I); anything else -- modes 0 and 1, a user-defined
;; character, a pen the same as the paper -- by draw_gen.
draw_cell:
    ld e,0
;; draw_it: as draw_cell, E = 1 for the cursor (pen and paper swapped)
draw_it:
    push af
    call cell_addr
    pop af
    ld d,a
    ld a,(cmode)
    cp 2
    jr nz,.gen
    ld a,d
    push hl
    ld hl,(m_first)
    inc h
    dec h
    jr nz,.rom                  ; (no user-defined ones)
    cp l
    jr nc,.genp
.rom:
    pop hl
    ld a,(paper)
    ld b,a
    ld a,(pen)
    xor b
    and 1
    jr z,.gen
    ld a,b
    and 1
    xor e
    ld b,a                      ; 1: inverted
    ld a,d
    jp r_glyph
.genp:
    pop hl
.gen:
    ld a,d
    ld b,e
;; draw_gen: A = a character, HL = its cell, B = 1 to swap pen and paper:
;; its glyph (the lower ROM's, or a user-defined one) in the text pen and
;; paper, for the mode, into rs_cell, and r_cellw puts it on the screen
draw_gen:
    push hl
    push bc
    call glyph_get
    ld a,(pen)
    call p_SCR_INK_ENCODE
    ld d,a
    ld a,(paper)
    call p_SCR_INK_ENCODE
    ld e,a
    pop bc
    dec b
    jr nz,.ns
    ld a,d
    ld d,e
    ld e,a
.ns:
    ld hl,rs_cell+32            ; the glyph
    ld bc,rs_cell               ; the bytes
    ld a,8
.l:
    push af
    ld a,(hl)
    inc hl
    push hl
    ld l,a                      ; L: the glyph's row
    ld a,(cmode)
    cp 1
    jr z,.m1
    jr c,.m0
    ld a,l                      ; mode 2: the row is the mask
    call dg_put
    jr .nx
.m1:
    ld a,l                      ; mode 1: four pixels a byte
    and #F0
    ld h,a
    rrca
    rrca
    rrca
    rrca
    or h
    call dg_put
    ld a,l
    and #0F
    ld h,a
    rlca
    rlca
    rlca
    rlca
    or h
    call dg_put
    jr .nx
.m0:
    ld h,4                      ; mode 0: two pixels a byte
.m0l:
    xor a
    sla l
    jr nc,.p0
    or #AA
.p0:
    sla l
    jr nc,.p1
    or #55
.p1:
    call dg_put
    dec h
    jr nz,.m0l
.nx:
    pop hl
    pop af
    dec a
    jr nz,.l
    pop hl
    ld a,(ccw)
    ld b,a
    jp r_cellw
;; dg_put: A = a pixel mask -> the pen's bits (D) there, the paper's (E)
;; elsewhere, into (BC), BC moved on
dg_put:
    push hl
    ld h,a
    and d
    ld l,a
    ld a,h
    cpl
    and e
    or l
    ld (bc),a
    inc bc
    pop hl
    ret
;; glyph_get: A = a character -> its eight bytes at rs_cell+32
glyph_get:
    ld hl,(m_first)
    ld e,a
    ld d,0
    ex de,hl
    or a
    sbc hl,de                   ; the character - the first user-defined
    jr c,.rom
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,(m_tab)
    add hl,de
    ld de,rs_cell+32
    ld bc,8
    ldir
    ret
.rom:
    ld de,rs_cell+32            ; (A: still the character)
    jp r_romfont
;; draw_inv: the cursor -- the shadow's character at C, B, pen and paper
;; swapped
draw_inv:
    push bc
    call shadow_at
    pop bc
    ld a,(hl)
    ld e,1
    jp draw_it

;; cell_addr: C = column, B = row (physical) -> HL = the cell's address on
;; its top pixel line. BC kept.
cell_addr:
    push bc
    ld l,b
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl                   ; 16 r
    ld d,h
    ld e,l
    add hl,hl
    add hl,hl
    add hl,de                   ; 80 r
    ld a,(ccw)
    ld e,c
    ld d,0
.w:
    rra
    jr c,.wd
    sla e
    rl d
    jr .w
.wd:
    add hl,de
    ld de,(scr_off)
    add hl,de
    ld a,h
    and 7
    or #C0
    ld h,a
    pop bc
    ret
;; shadow_at: C = column, B = row -> HL = its place in the shadow. BC lost.
shadow_at:
    ld a,(sh_top)
    add a,b
    cp ROWS
    jr c,.r
    sub ROWS
.r:
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld d,h
    ld e,l
    add hl,hl
    add hl,hl
    add hl,de                   ; 80 r
    ld b,0
    add hl,bc
    ld de,shadow
    add hl,de
    ret

;; scroll_up, scroll_down: the window one row, the new row cleared. The
;; whole screen by the CRTC's start address; a smaller window by copying.
scroll_up:
    ld hl,roll
    dec (hl)
    call win_full
    jr nz,.soft
    ld hl,(scr_off)
    ld de,80
    add hl,de
    ld a,h
    and 7
    ld h,a
    ld (scr_off),hl
    call crtc_start
    ld a,(sh_top)
    inc a
    cp ROWS
    jr c,.t
    xor a
.t:
    ld (sh_top),a
    ld a,ROWS-1
    jp clr_row
.soft:
    ld a,(win_t)
.l:
    ld hl,win_b
    cp (hl)
    jr nc,.last
    push af
    ld b,a
    inc b
    ld c,a
    call row_copy               ; row B to row C
    pop af
    inc a
    jr .l
.last:
    jp clr_row
scroll_down:
    ld hl,roll
    inc (hl)
    call win_full
    jr nz,.soft
    ld hl,(scr_off)
    ld de,-80
    add hl,de
    ld a,h
    and 7
    ld h,a
    ld (scr_off),hl
    call crtc_start
    ld a,(sh_top)
    dec a
    jp p,.t
    ld a,ROWS-1
.t:
    ld (sh_top),a
    xor a
    jp clr_row
.soft:
    ld a,(win_b)
.l:
    ld hl,win_t
    cp (hl)
    jr z,.last
    jr c,.last
    push af
    ld c,a
    ld b,a
    dec b
    call row_copy
    pop af
    dec a
    jr .l
.last:
    jp clr_row
;; win_full: Z if the window is the whole screen
win_full:
    ld a,(win_l)
    or a
    ret nz
    ld a,(win_t)
    or a
    ret nz
    ld a,(win_b)
    cp ROWS-1
    ret nz
    ld a,(ccols)
    dec a
    ld hl,win_r
    cp (hl)
    ret
;; row_copy: the window's columns of row B copied to row C, on the screen
;; and in the shadow
row_copy:
    ld a,b
    ld (rc_src),a
    ld a,c
    ld (rc_dst),a
    ld a,(win_l)
    ld c,a
    call cell_addr              ; HL: from
    push hl
    ld a,(rc_dst)
    ld b,a
    call cell_addr
    ex de,hl                    ; DE: to
    pop hl
    call win_bytes
    call r_rowcopy
    ld a,(win_l)
    ld c,a
    ld a,(rc_src)
    ld b,a
    call shadow_at
    push hl
    ld a,(win_l)
    ld c,a
    ld a,(rc_dst)
    ld b,a
    call shadow_at
    ex de,hl
    pop hl
    ld a,(win_l)
    ld b,a
    ld a,(win_r)
    sub b
    inc a
    ld c,a
    ld b,0
    ldir
    ret
rc_src:     db 0
rc_dst:     db 0
;; win_bytes: B = the window's width in bytes
win_bytes:
    ld a,(win_l)
    ld b,a
    ld a,(win_r)
    sub b
    inc a
    ld b,a
    ld a,(ccw)
.m:
    rra
    ret c
    sla b
    jr .m
;; clr_row: A = a row: the window's width of it cleared to the paper
clr_row:
    ld b,a
    ld a,(win_l)
    ld c,a
    ld a,(win_r)
    ld e,a
    ld a,b
    ld b,c
    ld c,e
;; clr_span: A = a row, B, C = its first and last column: cleared to the
;; paper, on the screen and in the shadow
clr_span:
    ld (cs_row),a
    ld a,b
    ld (cs_first),a
    ld a,c
    sub b
    inc a
    ld (cs_n),a
    ld a,(cs_row)
    ld b,a
    ld a,(cs_first)
    ld c,a
    call cell_addr
    ld a,(cs_n)
    ld b,a
    ld a,(ccw)
.m:
    rra
    jr c,.md
    sla b
    jr .m
.md:
    ld a,(paper)
    call p_SCR_INK_ENCODE
    call r_rowfill
    ld a,(cs_row)
    ld b,a
    ld a,(cs_first)
    ld c,a
    call shadow_at
    ld a,(cs_n)
    ld b,a
.s:
    ld (hl),32
    inc hl
    djnz .s
    ret
cs_row:     db 0
cs_first:   db 0
cs_n:       db 0

;; crtc_start: the CRTC's start address from scr_off (in words), at &C000
crtc_start:
    ld hl,(scr_off)
    srl h
    rr l
    ld a,h
    or #30
    ld bc,#BC0C
    out (c),c
    inc b
    out (c),a
    ld bc,#BC0D
    out (c),c
    inc b
    out (c),l
    ret

;; the cursor: shown when the system and the user both have it on.
;; cur_show and cur_hide keep every register.
cur_show:
    push af
    push bc
    push de
    push hl
    call cur_sdo
    jr cur_pop
cur_sdo:
    ld a,(cur_shown)
    or a
    ret nz
    ld a,(cur_on)
    or a
    ret z
    ld a,(cur_ena)
    or a
    ret z
    call val_col
    call val_row
    ld bc,(cur_c)
    ld (cur_sc),bc
    ld a,1
    ld (cur_shown),a
    jp draw_inv
cur_hide:
    push af
    push bc
    push de
    push hl
    call cur_hdo
cur_pop:
    pop hl
    pop de
    pop bc
    pop af
    ret
cur_hdo:
    ld a,(cur_shown)
    or a
    ret z
    xor a
    ld (cur_shown),a
    ld bc,(cur_sc)
    push bc
    call shadow_at
    pop bc
    ld a,(hl)
    jp draw_cell

;; TXT RD CHAR: -> carry and A = the character at the cursor
p_TXT_RD_CHAR:
    push bc
    push de
    push hl
    call cur_hide
    call val_col
    call val_row
    ld bc,(cur_c)
    call shadow_at
    ld a,(hl)
    push af
    call cur_show
    pop af
    pop hl
    pop de
    pop bc
    scf
    ret

p_TXT_SET_GRAPHIC:
p_TXT_SET_BACK:
    ret

;; TXT WIN ENABLE: H, D = two columns, L, E = two rows (physical, from 0,
;; either way round): the window, the cursor at its top left
p_TXT_WIN_ENABLE:
    push af
    push bc
    push de
    push hl
    call cur_hide
    ld a,h
    cp d
    jr c,.c
    ld h,d
    ld d,a
.c:
    ld a,(ccols)
    dec a
    cp d
    jr nc,.c2
    ld d,a
.c2:
    ld a,l
    cp e
    jr c,.r
    ld l,e
    ld e,a
.r:
    ld a,ROWS-1
    cp e
    jr nc,.r2
    ld e,a
.r2:
    ld a,h
    ld (win_l),a
    ld (cur_c),a
    ld a,d
    ld (win_r),a
    ld a,l
    ld (win_t),a
    ld (cur_r),a
    ld a,e
    ld (win_b),a
    call cur_show
    pop hl
    pop de
    pop bc
    pop af
    ret
;; TXT GET WINDOW: -> H, D = left, right; L, E = top, bottom; carry if the
;; window is not the whole screen
p_TXT_GET_WINDOW:
    ld a,(win_l)
    ld h,a
    ld a,(win_r)
    ld d,a
    ld a,(win_t)
    ld l,a
    ld a,(win_b)
    ld e,a
    push hl
    push de
    call win_full
    pop de
    pop hl
    scf
    ret nz
    or a
    ret
;; TXT CLEAR WINDOW: the window cleared to the paper, the cursor at its top
;; left
p_TXT_CLEAR_WINDOW:
    push af
    push bc
    push de
    push hl
    call cur_hide
    ld a,(win_t)
.l:
    push af
    call clr_row
    pop af
    ld hl,win_b
    cp (hl)
    inc a
    jr c,.l
    call c_home
    call cur_show
    pop hl
    pop de
    pop bc
    pop af
    ret
;; TXT SET CURSOR: H = column, L = row (from 1, in the window)
p_TXT_SET_CURSOR:
    push af
    push hl
    call cur_hide
    pop hl
    push hl
    ld a,(win_l)
    add a,h
    dec a
    ld (cur_c),a
    ld a,(win_t)
    add a,l
    dec a
    ld (cur_r),a
    call cur_show
    pop hl
    pop af
    ret
;; TXT GET CURSOR: -> H = column, L = row (from 1, in the window), A = the
;; roll count
p_TXT_GET_CURSOR:
    ld a,(win_l)
    ld h,a
    ld a,(cur_c)
    sub h
    inc a
    ld h,a
    ld a,(win_t)
    ld l,a
    ld a,(cur_r)
    sub l
    inc a
    ld l,a
    ld a,(roll)
    ret
p_TXT_CUR_ENABLE:
    push af
    ld a,1
    ld (cur_ena),a
    jr cur_set
p_TXT_CUR_DISABLE:
    push af
    xor a
    ld (cur_ena),a
    jr cur_set
p_TXT_CUR_ON:
    push af
    ld a,1
    ld (cur_on),a
    jr cur_set
p_TXT_CUR_OFF:
    push af
    xor a
    ld (cur_on),a
cur_set:
    push bc
    push de
    push hl
    call cur_hide
    call cur_show
    pop hl
    pop de
    pop bc
    pop af
    ret
p_TXT_SET_PEN:
    push hl
    ld hl,cmask
    and (hl)
    ld (pen),a
    pop hl
    ret
p_TXT_GET_PEN:
    ld a,(pen)
    ret
p_TXT_SET_PAPER:
    push hl
    ld hl,cmask
    and (hl)
    ld (paper),a
    pop hl
    ret
p_TXT_GET_PAPER:
    ld a,(paper)
    ret
p_TXT_INVERSE:
    push af
    push bc
    ld a,(pen)
    ld b,a
    ld a,(paper)
    ld (pen),a
    ld a,b
    ld (paper),a
    pop bc
    pop af
    ret
;; TXT GET MATRIX: A = a character -> HL = its eight bytes: in the lower
;; ROM's font (with the lower ROM in: KL L ROM ENABLE), or a user-defined
;; one's (carry)
p_TXT_GET_MATRIX:
    push de
    ld e,a
    ld d,0
    ld hl,(m_first)
    ex de,hl
    or a
    sbc hl,de                   ; the character - the first user-defined
    jr c,.rom
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,(m_tab)
    add hl,de
    pop de
    scf
    ret
.rom:
    ld l,a
    ld h,#07
    add hl,hl
    add hl,hl
    add hl,hl
    pop de
    or a
    ret
p_TXT_SET_MATRIX:               ; A = a character, HL = 8 bytes
    push de
    push hl
    call p_TXT_GET_MATRIX
    pop de
    jr nc,.no
    ex de,hl
    push bc
    ld bc,8
    ldir
    pop bc
    pop de
    scf
    ret
.no:
    pop de
    or a
    ret
p_TXT_SET_M_TABLE:              ; DE = the first character (D = 0), HL = the table
    ld (m_tab),hl
    ld a,d
    or a
    jr z,.e
    ld de,256                   ; (none)
.e:
    ld (m_first),de
    ret
p_TXT_GET_M_TABLE:
    ld hl,(m_tab)
    ld a,(m_first)
    ld e,a
    ld a,(m_first+1)
    or a
    scf
    ret z
    or a
    ret

;; ---- the screen ----

;; SCR SET MODE: A = a mode -- the screen cleared, the window the whole
;; screen, the cursor at its top left, the pens masked
p_SCR_SET_MODE:
    push af
    push bc
    push de
    push hl
    and 3
    cp 3
    jr nz,.m
    ld a,2
.m:
    ld (cmode),a
    ld hl,mode_tab
    ld e,a
    add a,a
    add a,e
    ld e,a
    ld d,0
    add hl,de
    ld a,(hl)
    ld (ccols),a
    inc hl
    ld a,(hl)
    ld (ccw),a
    inc hl
    ld a,(hl)
    ld (cmask),a
    ld hl,pen
    and (hl)
    ld (hl),a
    ld a,(cmask)
    ld hl,paper
    and (hl)
    ld (hl),a
    ld a,(cmask)
    ld hl,g_pen
    and (hl)
    ld (hl),a
    ld a,(cmask)
    ld hl,g_paper
    and (hl)
    ld (hl),a
    ld a,(cmode)                ; the width in pixels: 160, 320, 640
    ld hl,160
    or a
    jr z,.w
    add hl,hl
    dec a
    jr z,.w
    add hl,hl
.w:
    ld (gp_w),hl
    xor a
    ld (cur_shown),a
    ld a,(rs_rom)
    and #FC
    ld hl,cmode
    or (hl)
    ld (rs_rom),a
    ld b,#7F
    out (c),a
    call scr_clear
    pop hl
    pop de
    pop bc
    pop af
    ret
mode_tab:
    db 20,4,15, 40,2,3, 80,1,1
;; scr_clear: the whole screen to ink 0... the paper, unscrolled; the
;; window the whole screen
scr_clear:
    ld hl,0
    ld (scr_off),hl
    xor a
    ld (sh_top),a
    call crtc_start
    xor a
    ld (win_l),a
    ld (win_t),a
    ld a,(ccols)
    dec a
    ld (win_r),a
    ld a,ROWS-1
    ld (win_b),a
    ld hl,shadow                ; the shadow: spaces
    ld de,shadow+1
    ld bc,ROWS*80-1
    ld (hl),32
    ldir
    ld hl,#C000                 ; the whole 16 KB, as eight 2 KB lines
    ld a,(paper)
    call p_SCR_INK_ENCODE
    ld c,26                     ; (25.6 rows of 80 bytes in 2 KB)
.r:
    ld b,80
    call r_rowfill
    ld de,80
    add hl,de
    dec c
    jr nz,.r
    jp c_home
p_SCR_GET_MODE:                 ; -> A = the mode; C if 0, Z if 1
    ld a,(cmode)
    cp 1
    ret
p_SCR_GET_LOCATION:             ; -> A = the screen's base, HL = its offset
    ld hl,(scr_off)
    ld a,#C0
    ret
;; SCR INK ENCODE: A = an ink -> A = a byte of it, every pixel
p_SCR_INK_ENCODE:
    push bc
    ld c,a
    ld a,(cmode)
    cp 1
    jr c,.m0
    jr z,.m1
    ld a,c                      ; mode 2
    rra
    sbc a,a
    pop bc
    ret
.m1:
    xor a
    bit 0,c
    jr z,.e1a
    or #F0
.e1a:
    bit 1,c
    jr z,.e1b
    or #0F
.e1b:
    pop bc
    ret
.m0:
    xor a
    bit 0,c
    jr z,.e0a
    or #C0
.e0a:
    bit 1,c
    jr z,.e0b
    or #0C
.e0b:
    bit 2,c
    jr z,.e0c
    or #30
.e0c:
    bit 3,c
    jr z,.e0d
    or #03
.e0d:
    pop bc
    ret
;; SCR SET INK: A = an ink, B, C = its colours (the firmware's 0-26; no
;; flashing: B)
p_SCR_SET_INK:
    push af
    push bc
    push hl
    and 15
ink_set:
    ld c,a
    ld a,b
    cp 27
    jr c,.ok
    xor a
.ok:
    ld hl,hw_cols
    add a,l
    ld l,a
    adc a,h
    sub l
    ld h,a
    ld a,(hl)
    ld hl,inks
    ld b,0
    add hl,bc
    ld (hl),a
    ld b,#7F
    out (c),c
    or #40
    out (c),a
    pop hl
    pop bc
    pop af
    ret
p_SCR_SET_BORDER:
    push af
    push bc
    push hl
    ld a,16
    jr ink_set
hw_cols:                        ; the firmware's colours 0-26 as the gate array's
    db #14,#04,#15,#1C,#18,#1D,#0C,#05,#0D
    db #16,#06,#17,#1E,#00,#1F,#0E,#07,#0F
    db #12,#02,#13,#1A,#19,#1B,#0A,#03,#0B
;; SCR FILL BOX: A = an encoded byte, H, D = columns, L, E = rows: filled
p_SCR_FILL_BOX:
    push af
    push bc
    push de
    push hl
    ld (fb_byte),a
    ld a,h
    ld (fb_l),a
    ld a,d
    sub h
    inc a
    ld (fb_n),a
    ld a,e
    ld (fb_b),a
    ld a,l
.l:
    ld (fb_r),a
    ld b,a
    ld a,(fb_l)
    ld c,a
    call cell_addr
    ld a,(fb_n)
    ld b,a
    ld a,(ccw)
.m:
    rra
    jr c,.md
    sla b
    jr .m
.md:
    ld a,(fb_byte)
    call r_rowfill
    ld a,(fb_r)
    ld hl,fb_b
    cp (hl)
    inc a
    jr c,.l
    pop hl
    pop de
    pop bc
    pop af
    ret
fb_byte:    db 0
fb_l:       db 0
fb_n:       db 0
fb_b:       db 0
fb_r:       db 0
p_SCR_SET_FLASHING:
p_SCR_SW_ROLL:
    ret

;; ---- the keys ----

;; p_tick: from the resident part's interrupt, 100 times a second, with the
;; page mapped in (AF, BC, DE, HL saved there): the keyboard every other
;; time (50 Hz), the sound every time.
p_tick:
    ld hl,kb_div
    dec (hl)
    jr nz,.snd
    ld (hl),2
    call kb_scan
.snd:
    jp snd_tick
kb_div:     db 2

;; kb_scan: the matrix through the PSG's port A (register 14), each row
;; selected on the PPI's port C; each key newly down queued, and the last
;; one repeated while it is held.
kb_scan:
    ld bc,#F40E
    out (c),c                   ; PSG register 14
    ld bc,#F6C0
    out (c),c                   ; latched
    ld bc,#F600
    out (c),c
    ld bc,#F792
    out (c),c                   ; PPI port A in
    ld hl,kb_new
    ld d,#40
.row:
    ld b,#F6
    out (c),d                   ; the row, PSG read
    ld b,#F4
    in a,(c)
    ld (hl),a
    inc hl
    inc d
    ld a,d
    cp #4A
    jr nz,.row
    ld bc,#F782
    out (c),c                   ; PPI port A out again
    ld bc,#F600
    out (c),c
    ld hl,kb_mat
    ld de,kb_new
    ld b,0                      ; the first key of the row
.cmp:
    ld a,(de)
    ld c,(hl)                   ; the old row
    ld (hl),a                   ; the new one kept
    cpl                         ; down now: 1
    and c                       ;   and up before
    jr z,.next
    push hl
    push de
    push bc
    ld d,a
    ld e,b
.bit:
    srl d
    jr nc,.nb
    ld a,e
    push de
    call kb_push                ; (BC, HL lost)
    pop de
.nb:
    inc e
    ld a,d
    or a
    jr nz,.bit
    pop bc
    pop de
    pop hl
.next:
    inc hl
    inc de
    ld a,b
    add a,8
    ld b,a
    cp 80
    jr nz,.cmp
    ld a,(kb_last)              ; the repeat
    cp #FF
    ret z
    call r_testkey
    jr z,.gone
    ld hl,kb_rep
    dec (hl)
    ret nz
    ld (hl),KB_RATE
    ld a,(kb_last)
    jr kb_queue
.gone:
    ld a,#FF
    ld (kb_last),a
    ret
;; kb_push: A = a key newly down -> queued, and it repeats from now on
;; (SHIFT and CTRL are not keys of their own)
kb_push:
    cp 21
    ret z
    cp 23
    ret z
    ld (kb_last),a
    ld c,a
    ld a,KB_DELAY
    ld (kb_rep),a
    ld a,c
;; kb_queue: A = a key -> into the queue with SHIFT (bit 0) and CTRL (bit
;; 1) as they are now; dropped if it is full. BC, HL lost.
kb_queue:
    ld c,a
    ld a,(kb_mat+2)             ; row 2: SHIFT bit 5, CTRL bit 7
    cpl
    ld b,0
    bit 5,a
    jr z,.s
    set 0,b
.s:
    bit 7,a
    jr z,.c
    set 1,b
.c:
    ld a,(kb_put)
    ld l,a
    add a,2
    and 31
    ld h,a
    ld a,(kb_get)
    cp h
    ret z                       ; full
    ld a,h
    ld (kb_put),a
    ld a,l
    ld hl,kb_buf
    add a,l
    ld l,a
    adc a,h
    sub l
    ld h,a
    ld (hl),c
    inc hl
    ld (hl),b
    ret


;; KM READ CHAR: -> carry and A = a key's character, or no carry if none is
;; waiting. The firmware's translation tables: plain, SHIFT, CTRL.
p_KM_READ_CHAR:
    ld a,(km_back)
    or a
    jr z,.q
    push af
    xor a
    ld (km_back),a
    pop af
    scf
    ret
.q:
    push bc
    push hl
.next:
    di
    ld a,(kb_get)
    ld hl,kb_put
    cp (hl)
    jr z,.none
    ld l,a
    add a,2
    and 31
    ld (kb_get),a
    ld a,l
    ld hl,kb_buf
    add a,l
    ld l,a
    adc a,h
    sub l
    ld h,a
    ld c,(hl)                   ; the key
    inc hl
    ld b,(hl)                   ; SHIFT 1, CTRL 2
    ei
    ld hl,km_plain
    bit 1,b
    jr z,.s
    ld hl,km_ctrl
    jr .t
.s:
    bit 0,b
    jr z,.t
    ld hl,km_shift
.t:
    ld a,c
    cp 80
    jr nc,.next
    add a,l
    ld l,a
    adc a,h
    sub l
    ld h,a
    ld a,(hl)
    cp #FF
    jr z,.next                  ; no character
    cp #FD
    jr z,.next                  ; (CAPS LOCK, SHIFT LOCK)
    cp #FE
    jr z,.next
    pop hl
    pop bc
    scf
    ret
.none:
    ei
    pop hl
    pop bc
    or a
    ret
;; KM WAIT CHAR: -> A = a key's character
p_KM_WAIT_CHAR:
    call p_KM_READ_CHAR
    ret c
    halt
    jr p_KM_WAIT_CHAR
;; KM CHAR RETURN: A = a character, read next
p_KM_CHAR_RETURN:
    ld (km_back),a
    ret
;; KM GET JOYSTICK: -> H = joystick 0, L = joystick 1 (bits as the
;; firmware's: up, down, left, right, fire 2, fire 1), A = H
p_KM_GET_JOYSTICK:
    ld a,(kb_mat+6)
    cpl
    and #3F
    ld l,a
    ld a,(kb_mat+9)
    cpl
    and #3F
    ld h,a
    ret
km_plain:
    db #F0,#F3,#F1,#89,#86,#83,#8B,#8A,#F2,#E0,#87,#88,#85,#81,#82,#80
    db #10,#5B,#0D,#5D,#84,#FF,#5C,#FF,#5E,#2D,#40,#70,#3B,#3A,#2F,#2E
    db #30,#39,#6F,#69,#6C,#6B,#6D,#2C,#38,#37,#75,#79,#68,#6A,#6E,#20
    db #36,#35,#72,#74,#67,#66,#62,#76,#34,#33,#65,#77,#73,#64,#63,#78
    db #31,#32,#FC,#71,#09,#61,#FD,#7A,#0B,#0A,#08,#09,#58,#5A,#FF,#7F
km_shift:
    db #F4,#F7,#F5,#89,#86,#83,#8B,#8A,#F6,#E0,#87,#88,#85,#81,#82,#80
    db #10,#7B,#0D,#7D,#84,#FF,#60,#FF,#A3,#3D,#7C,#50,#2B,#2A,#3F,#3E
    db #5F,#29,#4F,#49,#4C,#4B,#4D,#3C,#28,#27,#55,#59,#48,#4A,#4E,#20
    db #26,#25,#52,#54,#47,#46,#42,#56,#24,#23,#45,#57,#53,#44,#43,#58
    db #21,#22,#FC,#51,#09,#41,#FD,#5A,#0B,#0A,#08,#09,#58,#5A,#FF,#7F
km_ctrl:
    db #F8,#FB,#F9,#89,#86,#83,#8C,#8A,#FA,#E0,#87,#88,#85,#81,#82,#80
    db #10,#1B,#0D,#1D,#84,#FF,#1C,#FF,#1E,#FF,#00,#10,#FF,#FF,#FF,#FF
    db #1F,#FF,#0F,#09,#0C,#0B,#0D,#FF,#FF,#FF,#15,#19,#08,#0A,#0E,#FF
    db #FF,#FF,#12,#14,#07,#06,#02,#16,#FF,#FF,#05,#17,#13,#04,#03,#18
    db #FF,#7E,#FC,#11,#E1,#01,#FE,#1A,#FF,#FF,#FF,#FF,#FF,#FF,#FF,#7F

;; ---- graphics ----
;;
;; The firmware's: logical coordinates, x 0-639 and y 0-399, from the
;; origin, y up; a pixel is 1, 2 or 4 units wide (mode 2, 1, 0) and 2
;; high. Plotted and tested here (the pixel's address and mask), written
;; by the resident part (r_pix, in the ink mode that SCR ACCESS set).

p_GRA_MOVE_ABSOLUTE:
    ld (g_x),de
    ld (g_y),hl
    ret
p_GRA_MOVE_RELATIVE:
    call g_rel
    jr p_GRA_MOVE_ABSOLUTE
;; g_rel: DE, HL relative to the graphics cursor -> absolute
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
p_GRA_ASK_CURSOR:
    ld de,(g_x)
    ld hl,(g_y)
    ret
p_GRA_SET_ORIGIN:
    ld (g_ox),de
    ld (g_oy),hl
    ld hl,0
    ld (g_x),hl
    ld (g_y),hl
    ret
p_GRA_GET_ORIGIN:
    ld de,(g_ox)
    ld hl,(g_oy)
    ret
p_GRA_SET_PEN:
    push hl
    ld hl,cmask
    and (hl)
    ld (g_pen),a
    pop hl
    ret
p_GRA_GET_PEN:
    ld a,(g_pen)
    ret
p_GRA_SET_PAPER:
    push hl
    ld hl,cmask
    and (hl)
    ld (g_paper),a
    pop hl
    ret
p_SCR_ACCESS:                   ; A = the ink mode: 0 as it is, 1 XOR,
    and 3                       ;   2 AND, 3 OR
    ld (g_acc),a
    ret
;; GRA CLEAR WINDOW: the screen to the graphics paper (the text with it),
;; the graphics cursor at the origin
p_GRA_CLEAR_WINDOW:
    push af
    push bc
    push de
    push hl
    call cur_hide
    ld hl,shadow
    ld de,shadow+1
    ld bc,ROWS*80-1
    ld (hl),32
    ldir
    ld a,(g_paper)
    call p_SCR_INK_ENCODE
    ld hl,#C000
    ld c,26
.r:
    ld b,80
    call r_rowfill
    ld de,80
    add hl,de
    dec c
    jr nz,.r
    ld hl,0
    ld (g_x),hl
    ld (g_y),hl
    call cur_show
    pop hl
    pop de
    pop bc
    pop af
    ret

p_GRA_PLOT_RELATIVE:
    call g_rel
p_GRA_PLOT_ABSOLUTE:
    ld (g_x),de
    ld (g_y),hl
    call g_abs
    call g_phys
    ret nc
    jp g_plot
;; GRA TEST: -> A = the pen at the point (the cursor moved there)
p_GRA_TEST_RELATIVE:
    call g_rel
p_GRA_TEST_ABSOLUTE:
    ld (g_x),de
    ld (g_y),hl
    call g_abs
    call g_phys
    jr c,.on
    ld a,(g_paper)
    ret
.on:
    call g_addr                 ; HL, C: the byte, the mask
    call r_pixrd
    and c                       ; this pixel's bits
    ld b,a
    ld a,(cmode)
    cp 1
    jr c,.m0
    jr z,.m1
    ld a,b                      ; mode 2
    or a
    ret z
    ld a,1
    ret
.m1:                            ; mode 1: bit 7-p ink bit 0, 3-p bit 1
    ld a,c
    and #F0
    and b
    ld e,0
    jr z,.b1
    inc e
.b1:
    ld a,c
    and #0F
    and b
    jr z,.b2
    set 1,e
.b2:
    ld a,e
    ret
.m0:                            ; mode 0: ink bits 0-3 at 7, 3, 5, 1 (6, 2,
    ld a,c                      ;   4, 0 for the right pixel)
    and #AA
    ld a,b
    jr nz,.l0
    rlca                        ; the right pixel: as the left's
.l0:
    ld e,0
    bit 7,a
    jr z,.c1
    set 0,e
.c1:
    bit 3,a
    jr z,.c2
    set 1,e
.c2:
    bit 5,a
    jr z,.c3
    set 2,e
.c3:
    bit 1,a
    jr z,.c4
    set 3,e
.c4:
    ld a,e
    ret

p_GRA_LINE_RELATIVE:
    call g_rel
;; GRA LINE: from the cursor to DE, HL, both ends drawn (Bresenham, in
;; pixels; what is off the screen is left out)
p_GRA_LINE_ABSOLUTE:
    push de
    push hl
    ld de,(g_x)
    ld hl,(g_y)
    call g_abs
    call g_pix
    ld (ln_x),de
    ld (ln_y),hl
    pop hl
    pop de
    ld (g_x),de
    ld (g_y),hl
    call g_abs
    call g_pix
    ld (ln_x1),de
    ld (ln_y1),hl
    ld a,(g_pen)                ; the pen's byte, once
    call p_SCR_INK_ENCODE
    ld (g_penb),a
    ld de,(ln_y)                ; a row: a span of whole bytes
    or a
    sbc hl,de
    jp z,g_hspan
    ld hl,(ln_x1)               ; dx = |x1 - x|, sx
    ld de,(ln_x)
    ld a,1
    or a
    sbc hl,de
    jp p,.xp
    ld a,-1
    ex de,hl
    ld hl,0
    or a
    sbc hl,de
.xp:
    ld (ln_dx),hl
    ld (ln_sx),a
    ld hl,(ln_y1)               ; dy = |y1 - y|, sy
    ld de,(ln_y)
    ld a,1
    or a
    sbc hl,de
    jp p,.yp
    ld a,-1
    ex de,hl
    ld hl,0
    or a
    sbc hl,de
.yp:
    ld (ln_dy),hl
    ld (ln_sy),a
    ld hl,(ln_dx)               ; err = dx - dy
    ld de,(ln_dy)
    or a
    sbc hl,de
    ld (ln_err),hl
.step:
    ld de,(ln_x)
    ld hl,(ln_y)
    call g_inpix
    call c,g_plotb
    ld hl,(ln_x)
    ld de,(ln_x1)
    or a
    sbc hl,de
    jr nz,.go
    ld hl,(ln_y)
    ld de,(ln_y1)
    or a
    sbc hl,de
    ret z                       ; the end
.go:
    ld hl,(ln_err)              ; e2 = 2 err
    add hl,hl
    push hl
    ld de,(ln_dy)               ; e2 > -dy, i.e. e2 + dy > 0:
    or a                        ;   err -= dy, x += sx (ADC: ADD HL
    adc hl,de                   ;   sets no S or Z)
    jr z,.nx
    jp m,.nx
    ld hl,(ln_err)
    or a
    sbc hl,de
    ld (ln_err),hl
    ld a,(ln_sx)
    ld e,a
    rla
    sbc a,a
    ld d,a
    ld hl,(ln_x)
    add hl,de
    ld (ln_x),hl
.nx:
    pop hl                      ; e2 < dx: err += dx, y += sy
    ld de,(ln_dx)
    or a
    sbc hl,de
    jp p,.step
    ld hl,(ln_err)
    add hl,de
    ld (ln_err),hl
    ld a,(ln_sy)
    ld e,a
    rla
    sbc a,a
    ld d,a
    ld hl,(ln_y)
    add hl,de
    ld (ln_y),hl
    jp .step

;; g_abs: DE, HL from the origin -> the screen's logical coordinates
g_abs:
    push hl
    ld hl,(g_ox)
    add hl,de
    ex de,hl
    pop hl
    push de
    ld de,(g_oy)
    add hl,de
    pop de
    ret
;; g_pix: logical DE, HL -> pixels (signed, not clipped): x / the pixel's
;; width, y / 2
g_pix:
    sra h
    rr l
    ld a,(cmode)
    cp 2
    ret z
    sra d
    rr e
    or a
    ret nz
    sra d
    rr e
    ret
;; g_phys: logical DE, HL -> carry and pixels if on the screen
g_phys:
    call g_pix
;; g_inpix: pixels DE, HL -> carry if on the screen. DE, HL kept.
g_inpix:
    bit 7,d
    jr nz,.off
    bit 7,h
    jr nz,.off
    push hl
    ld bc,200
    or a
    sbc hl,bc
    pop hl
    ret nc
    push hl
    ld hl,(gp_w)                ; the mode's width in pixels
    ex de,hl
    or a
    sbc hl,de
    add hl,de
    ex de,hl
    pop hl
    ret
.off:
    or a
    ret
;; g_plot: pixels DE, HL (on the screen) -> plotted in the graphics pen;
;; g_plotb: in the pen's byte g_penb
g_plot:
    ld a,(g_pen)
    call p_SCR_INK_ENCODE
    ld (g_penb),a
g_plotb:
    call g_addr
    ld a,(g_penb)
    ld b,a
    ld a,(g_acc)
    jp r_pix
;; g_hspan: the line is a row, ln_y, from ln_x to ln_x1: clipped, and
;; written a byte at a time (r_span), the ends masked
g_hspan:
    ld hl,(ln_y)
    bit 7,h
    ret nz
    ld de,200
    or a
    sbc hl,de
    ret nc                      ; not on the screen
    ld hl,(ln_x)                ; from the smaller x
    ld de,(ln_x1)
    or a
    sbc hl,de
    add hl,de
    jp m,.ord
    ex de,hl
.ord:                           ; HL <= DE
    bit 7,h
    jr z,.l0
    ld hl,0
.l0:
    bit 7,d
    ret nz                      ; all left of the screen
    push hl
    ld hl,(gp_w)
    dec hl
    or a
    sbc hl,de
    jr nc,.r0                   ; DE <= the right edge
    ld de,(gp_w)
    dec de
.r0:
    pop hl
    push de
    ex de,hl
    ld hl,(gp_w)
    or a
    sbc hl,de
    pop hl
    ret c                       ; (the left end past the right edge)
    ret z
    push hl                     ; (DE: the left end, HL: the right)
    ld hl,(ln_y)
    call g_addr                 ; the left end's byte and mask
    ld (hs_a0),hl
    ld a,c
    ld (hs_m0),a
    pop de
    ld hl,(ln_y)
    call g_addr                 ; the right end's
    ld (hs_a1),hl
    ld a,c
    ld (hs_m1),a
    ld a,(hs_m0)                ; the left byte: its pixel and those right
    call hs_right               ;   of it
    ld (hs_m0),a
    ld a,(hs_m1)                ; the right byte: its pixel and those left
    call hs_left
    ld (hs_m1),a
    ld hl,(hs_a1)               ; bytes: the right's - the left's (in the
    ld de,(hs_a0)               ;   2 KB ring: a row is at most 80), + 1
    or a
    sbc hl,de
    ld b,l
    inc b
    ld a,(hs_m0)
    ld d,a
    ld a,(hs_m1)
    ld e,a
    ld hl,(hs_a0)
    ld a,(g_penb)
    ld c,a
    ld a,(g_acc)
    jp r_span
;; hs_right: A = a pixel's mask -> its pixel's and those right of it in the
;; byte; hs_left: ... left of it
hs_right:
    ld c,a
    ld e,a
.l:
    call hs_last
    jr z,.d
    srl c
    ld a,c
    or e
    ld e,a
    jr .l
.d:
    ld a,e
    ret
hs_left:
    ld c,a
    ld e,a
.l:
    call hs_first
    jr z,.d
    sla c
    ld a,c
    or e
    ld e,a
    jr .l
.d:
    ld a,e
    ret
;; hs_last, hs_first: Z if C is the mode's rightmost, leftmost pixel mask
hs_last:
    ld a,(cmode)
    ld b,#01
    cp 2
    jr z,.c
    ld b,#11
    dec a
    jr z,.c
    ld b,#55
.c:
    ld a,c
    cp b
    ret
hs_first:
    ld a,(cmode)
    ld b,#80
    cp 2
    jr z,.c
    ld b,#88
    dec a
    jr z,.c
    ld b,#AA
.c:
    ld a,c
    cp b
    ret
;; SCR DOT POSITION: DE = a pixel's x, HL = its y (from the bottom, 0-199)
;; -> HL = its byte, C = its mask, B = pixels in a byte - 1
p_SCR_DOT_POSITION:
    call g_addr
    ld a,(cmode)
    ld b,7
    cp 2
    ret z
    ld b,3
    dec a
    ret z
    ld b,1
    ret
;; g_addr: pixels DE, HL -> HL = the screen byte, C = the pixel's mask. DE
;; kept.
g_addr:
    push de
    ld a,199
    sub l                       ; the row from the top
    ld b,a
    and 7
    add a,a
    add a,a
    add a,a
    ld (ga_line),a              ; its pixel line x 8: &800 apart
    ld a,b
    and #F8                     ; the character row x 8
    ld l,a
    ld h,0
    add hl,hl                   ; x 16
    ld b,h
    ld c,l
    add hl,hl
    add hl,hl
    add hl,bc                   ; x 80
    push hl
    ld a,(cmode)                ; the byte along the row, and the mask
    cp 1
    jr c,.m0
    jr z,.m1
    ld a,e                      ; mode 2: 8 pixels a byte
    and 7
    ld b,a
    ld c,#80
    srl d
    rr e
    jr .sh
.m1:
    ld a,e                      ; mode 1: 4
    and 3
    ld b,a
    ld c,#88
    jr .sh
.m0:
    ld a,e                      ; mode 0: 2
    and 1
    ld b,a
    ld c,#AA
    jr .sh2
.sh:
    srl d
    rr e
.sh2:
    srl d
    rr e
    inc b
    dec b
    jr z,.mk
.ms:
    srl c
    djnz .ms
.mk:
    pop hl
    add hl,de
    ld de,(scr_off)
    add hl,de
    ld a,h
    and 7
    ld h,a
    ld a,(ga_line)
    or #C0
    add a,h
    ld h,a
    pop de
    ret
;; SCR NEXT BYTE, SCR PREV BYTE: HL = a screen byte -> the one beside it on
;; its pixel line (in its 2 KB)
p_SCR_NEXT_BYTE:
    ld a,l
    add a,1
    ld l,a
    ret nc
    inc h
    ld a,h
    and 7
    ret nz
    ld a,h
    sub 8
    ld h,a
    ret
p_SCR_PREV_BYTE:
    ld a,l
    sub 1
    ld l,a
    ret nc
    ld a,h
    and 7
    jr nz,.n
    ld a,h
    add a,8
    ld h,a
.n:
    dec h
    ret

g_x:        dw 0                ; the graphics cursor, from the origin
g_y:        dw 0
g_ox:       dw 0                ; the origin
g_oy:       dw 0
g_pen:      db 1
g_paper:    db 0
g_acc:      db 0                ; the ink mode (SCR ACCESS)
g_penb:     db 0                ; the pen's byte, for a line
hs_a0:      dw 0
hs_a1:      dw 0
hs_m0:      db 0
hs_m1:      db 0
gp_w:       dw 640              ; the mode's width in pixels
ga_line:    db 0
ln_x:       dw 0
ln_y:       dw 0
ln_x1:      dw 0
ln_y1:      dw 0
ln_dx:      dw 0
ln_dy:      dw 0
ln_err:     dw 0
ln_sx:      db 0
ln_sy:      db 0

;; ---- sound ----
;;
;; The firmware's sound manager, cut down: three channels (A, B, C: 1, 2,
;; 4), a queue of four sounds each, amplitude envelopes (15, of up to five
;; sections: steps, a step's size, the pause after each, in 1/100 s); no
;; tone envelopes and no rendezvous yet (a sound waiting for one is played
;; anyway). snd_tick, 100 times a second from the resident part's
;; interrupt with the page mapped in, plays them on the AY.

SQN         equ 4               ; sounds a channel's queue holds

;; SOUND QUEUE: HL = a sound, nine bytes (channels and flags, amplitude
;; envelope, tone envelope, period (2), noise, volume, duration (2)) ->
;; carry if it was queued on its channels, none if a queue was full
p_SOUND_QUEUE:
    push bc
    push de
    push hl
    di
    ld a,(hl)
    bit 7,a                     ; flush: the channels' queues and sounds
    jr z,.nf
    push hl
    call snd_flush
    pop hl
    ld a,(hl)
.nf:
    and 7
    jr z,.ok
    ld (sq_ch),a
    ld c,a                      ; room on every channel?
    ld b,0
.room:
    rr c
    jr nc,.rn
    ld de,snd_cnt
    call snd_ix
    ld a,(de)
    cp SQN
    jr nc,.full
.rn:
    inc b
    ld a,b
    cp 3
    jr nz,.room
    ld a,(sq_ch)                ; then onto each
    ld c,a
    ld b,0
.each:
    rr c
    jr nc,.en
    pop hl
    push hl
    push bc
    call snd_put
    pop bc
.en:
    inc b
    ld a,b
    cp 3
    jr nz,.each
.ok:
    ei
    pop hl
    pop de
    pop bc
    scf
    ret
.full:
    ei
    pop hl
    pop de
    pop bc
    or a
    ret
;; snd_ix: DE = an array of three bytes, B = a channel -> DE = its byte.
;; AF kept.
snd_ix:
    push af
    ld a,e
    add a,b
    ld e,a
    adc a,d
    sub e
    ld d,a
    pop af
    ret
;; snd_put: HL = a sound, B = a channel with room -> queued (8 bytes: the
;; period, noise, volume, duration, envelope)
snd_put:
    push hl
    ld de,snd_cnt
    call snd_ix
    ld a,(de)
    ld c,a
    inc a
    ld (de),a
    ld de,snd_rd
    call snd_ix
    ld a,(de)
    add a,c
    and SQN-1                   ; the slot: (first + waiting) mod SQN
    ld c,a
    ld a,b                      ; snd_q + 8 (SQN b + slot)
    add a,a
    add a,a
    add a,c
    add a,a
    add a,a
    add a,a
    ld e,a
    ld d,0
    ld hl,snd_q
    add hl,de
    ex de,hl
    pop hl
    push hl
    inc hl
    ld a,(hl)                   ; the envelope
    inc hl
    inc hl
    ld c,(hl)                   ; the period
    inc hl
    ld b,(hl)
    inc hl
    ex de,hl
    ld (hl),c
    inc hl
    ld (hl),b
    inc hl
    ld c,a                      ; (C: the envelope)
    ld a,(de)                   ; noise
    inc de
    ld (hl),a
    inc hl
    ld a,(de)                   ; volume
    inc de
    ld (hl),a
    inc hl
    ld a,(de)                   ; duration
    inc de
    ld (hl),a
    inc hl
    ld a,(de)
    ld (hl),a
    inc hl
    ld (hl),c
    pop hl
    ret
;; snd_flush: A = channels: their queues emptied, their sounds stopped
snd_flush:
    and 7
    ld c,a
    ld b,0
.l:
    rr c
    jr nc,.n
    push bc
    ld de,snd_cnt
    call snd_ix
    xor a
    ld (de),a
    ld a,b
    add a,a
    ld e,a
    ld d,0
    ld hl,ch_dur
    add hl,de
    xor a
    ld (hl),a
    inc hl
    ld (hl),a
    ld de,ch_amp
    call snd_ix
    xor a
    ld (de),a
    ld a,b
    add a,8
    ld c,0
    call ay_w                   ; silent
    pop bc
.n:
    inc b
    ld a,b
    cp 3
    jr nz,.l
    ret
;; SOUND CHECK: A = a channel (1, 2, 4) -> A = its state: free places in
;; its queue (bits 0-2), playing (bit 7)
p_SOUND_CHECK:
    push bc
    push de
    push hl
    ld b,0
    rra
    jr c,.c
    inc b
    rra
    jr c,.c
    inc b
.c:
    ld de,snd_cnt
    call snd_ix
    ld a,(de)
    ld c,a
    ld a,SQN
    sub c
    ld c,a
    ld a,b
    add a,a
    ld e,a
    ld d,0
    ld hl,ch_dur
    add hl,de
    ld a,(hl)
    inc hl
    or (hl)
    ld a,c
    jr z,.r
    or #80
.r:
    pop hl
    pop de
    pop bc
    ret
;; SOUND HOLD: everything stops where it is -> carry if anything played;
;; SOUND CONTINUE: on again
p_SOUND_HOLD:
    push bc
    ld a,1
    ld (snd_hold),a
    xor a                       ; silent meanwhile
    ld c,a
    ld a,8
    call ay_w
    ld a,9
    call ay_w
    ld a,10
    call ay_w
    ld hl,(ch_dur)
    ld a,h
    or l
    ld hl,(ch_dur+2)
    or h
    or l
    ld hl,(ch_dur+4)
    or h
    or l
    pop bc
    ret z
    scf
    ret
p_SOUND_CONTINUE:
    xor a
    ld (snd_hold),a
    ret
p_SOUND_RELEASE:
p_SOUND_TONE_ENVELOPE:
    ret
;; SOUND AMPL ENVELOPE: A = an envelope (1-15), HL = its sections' count,
;; then three bytes a section: kept
p_SOUND_AMPL_ENVELOPE:
    push bc
    push de
    push hl
    dec a
    and 15
    cp 15
    jr nc,.no
    add a,a
    add a,a
    add a,a
    add a,a
    ld e,a
    ld d,0
    push hl
    ld hl,snd_env
    add hl,de
    ex de,hl
    pop hl
    ld bc,16
    ldir
.no:
    pop hl
    pop de
    pop bc
    scf
    ret

;; snd_tick: once every 1/100 s (the interrupt, the page mapped in): each
;; channel's sound on, its envelope a step on, the next from its queue
;; when it ends. Every register kept but AF... and IX, IY not used.
snd_tick:
    ld a,(snd_hold)
    or a
    ret nz
    ld b,0
.ch:
    push bc
    call snd_chan
    pop bc
    inc b
    ld a,b
    cp 3
    jr nz,.ch
    ret
;; snd_chan: B = a channel
snd_chan:
    ld a,b
    add a,a
    ld e,a
    ld d,0
    ld hl,ch_dur
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,d
    or e
    jr z,.next                  ; idle: the next, if one waits
    dec de
    ld (hl),d
    dec hl
    ld (hl),e
    ld a,d
    or e
    jr z,.next
    jp snd_envstep
.next:
    ld de,snd_cnt
    call snd_ix
    ld a,(de)
    or a
    jr nz,.take
    ld de,ch_amp                ; nothing: silent
    call snd_ix
    ld a,(de)
    or a
    ret z
    xor a
    ld (de),a
    ld a,b
    add a,8
    ld c,0
    jp ay_w
.take:
    dec a
    ld (de),a
    ld de,snd_rd
    call snd_ix
    ld a,(de)
    ld c,a
    inc a
    and SQN-1
    ld (de),a
    ld a,b                      ; its slot
    add a,a
    add a,a
    add a,c
    add a,a
    add a,a
    add a,a
    ld e,a
    ld d,0
    ld hl,snd_q
    add hl,de
    ld e,(hl)                   ; the period
    inc hl
    ld d,(hl)
    inc hl
    push hl
    ld a,b
    add a,a
    ld c,e
    call ay_w                   ; its two registers
    ld a,b
    add a,a
    inc a
    ld c,d
    call ay_w
    pop hl
    ld a,d                      ; tone on if there is a period
    or e
    ld c,(hl)                   ; noise
    inc hl
    push hl
    call snd_mix
    pop hl
    ld a,(hl)                   ; the volume
    and 15
    inc hl
    ld de,ch_amp
    call snd_ix
    ld (de),a
    ld e,(hl)                   ; the duration
    inc hl
    ld d,(hl)
    inc hl
    ld a,(hl)                   ; the envelope
    push de
    call snd_envset             ; -> HL = its length, if it has one
    pop de
    bit 7,d
    jr z,.d
    ld de,0                     ; (a count of the envelope: its length)
.d:
    ld a,d
    or e
    jr nz,.dur
    ex de,hl
    ld a,d
    or e
    jr nz,.dur
    ld de,200                   ; none: two seconds
.dur:
    ld a,b
    add a,a
    ld l,a
    ld h,0
    push de
    ld de,ch_dur
    add hl,de
    pop de
    ld (hl),e
    inc hl
    ld (hl),d
    jp snd_amp
;; snd_mix: B = a channel, NZ: its tone on; C = noise (0: off) -> the
;; mixer (register 7) and the noise's period (6)
snd_mix:
    push af
    ld a,b
    ld hl,mix_bits
    add a,l
    ld l,a
    adc a,h
    sub l
    ld h,a
    pop af
    ld a,(snd_mixv)
    jr z,.toff
    ld e,a                      ; tone on: its bit clear
    ld a,(hl)
    cpl
    and e
    jr .t
.toff:
    or (hl)
.t:
    ld e,a
    ld a,(hl)
    rlca
    rlca
    rlca                        ; its noise bit
    ld d,a
    ld a,c
    or a
    ld a,e
    jr z,.noff
    ld a,d
    cpl
    and e
    ld e,a
    push bc
    ld a,6
    call ay_w                   ; the noise's period
    pop bc
    jr .m
.noff:
    or d
    ld e,a
.m:
    ld a,e
    and #3F                     ; (bit 6 clear: PSG port A reads the keys)
    ld (snd_mixv),a
    push bc
    ld c,a
    ld a,7
    call ay_w
    pop bc
    ret
mix_bits:   db 1,2,4
;; snd_envset: A = an envelope (0: none), B = the channel -> its state
;; set; HL = its length in 1/100 s (0 if none)
snd_envset:
    ld de,ch_env
    call snd_ix
    and 15
    ld (de),a
    ld hl,0
    ret z
    ld de,ch_sec
    call snd_ix
    xor a
    ld (de),a                   ; (section 0: loaded at the first step)
    ld de,ch_cnt
    call snd_ix
    ld (de),a
    ld de,ch_pau
    call snd_ix
    ld (de),a
    call snd_envp               ; HL = the envelope
    ld c,(hl)                   ; its sections
    inc hl
    ld de,0
    inc c
    dec c
    jr z,.e
.s:
    ld a,(hl)                   ; steps x (pause + 1)
    and #7F
    inc hl
    inc hl
    push bc
    ld b,a
    ld a,(hl)
    inc hl
    inc a
    ld c,a
    jr nz,.p
    ld c,255
.p:
    ld a,b
    or a
    jr z,.sn
.m:
    ld a,e
    add a,c
    ld e,a
    jr nc,.mn
    inc d
.mn:
    djnz .m
.sn:
    pop bc
    dec c
    jr nz,.s
.e:
    ex de,hl
    ret
;; snd_envp: B = a channel -> HL = its envelope's sixteen bytes
snd_envp:
    ld de,ch_env
    call snd_ix
    ld a,(de)
    dec a
    add a,a
    add a,a
    add a,a
    add a,a
    ld e,a
    ld d,0
    ld hl,snd_env
    add hl,de
    ret
;; snd_envstep: B = a channel sounding: its envelope a step on, if it has
;; one
snd_envstep:
    ld de,ch_env
    call snd_ix
    ld a,(de)
    or a
    ret z
    ld de,ch_pau
    call snd_ix
    ld a,(de)
    or a
    jr z,.step
    dec a
    ld (de),a
    ret
.step:
    ld de,ch_cnt
    call snd_ix
    ld a,(de)
    or a
    jr nz,.go
    ld de,ch_sec                ; the next section, if there is one
    call snd_ix
    ld a,(de)
    push af
    push de
    call snd_envp
    pop de
    pop af
    cp (hl)
    ret nc                      ; none: the volume stays
    ld c,a
    inc a
    ld (de),a
    ld a,c                      ; HL + 1 + 3 x the section
    add a,a
    add a,c
    inc a
    add a,l
    ld l,a
    adc a,h
    sub l
    ld h,a
    ld a,(hl)                   ; steps
    and #7F
    ld de,ch_cnt
    call snd_ix
    ld (de),a
    inc hl
    ld a,(hl)                   ; a step's size
    ld de,ch_stp
    call snd_ix
    ld (de),a
    inc hl
    ld a,(hl)                   ; the pause
    ld de,ch_pl
    call snd_ix
    ld (de),a
    ld de,ch_cnt
    call snd_ix
    ld a,(de)
    or a
    ret z
.go:
    dec a
    ld (de),a
    ld de,ch_stp
    call snd_ix
    ld a,(de)
    ld c,a
    ld de,ch_amp
    call snd_ix
    ld a,(de)
    add a,c
    and 15
    ld (de),a
    ld de,ch_pl
    call snd_ix
    ld a,(de)
    ld de,ch_pau
    call snd_ix
    ld (de),a
;; snd_amp: B = a channel -> its volume on the AY
snd_amp:
    ld de,ch_amp
    call snd_ix
    ld a,(de)
    ld c,a
    ld a,b
    add a,8
;; ay_w: A = an AY register, C = a value: written (through the PPI). B
;; kept... and A, flags lost.
ay_w:
    push bc
    ld b,#F4
    out (c),a
    ld b,#F6
    ld a,#C0
    out (c),a
    xor a
    out (c),a
    ld b,#F4
    out (c),c
    ld b,#F6
    ld a,#80
    out (c),a
    xor a
    out (c),a
    pop bc
    ret

sq_ch:      db 0
snd_hold:   db 0
snd_mixv:   db #3F              ; the mixer: all off
snd_cnt:    db 0,0,0            ; sounds waiting, each channel
snd_rd:     db 0,0,0            ; the first of them
ch_dur:     dw 0,0,0            ; the sound on: 1/100 s to go
ch_amp:     db 0,0,0            ;   its volume
ch_env:     db 0,0,0            ;   its envelope (0: none),
ch_sec:     db 0,0,0            ;   the next section,
ch_cnt:     db 0,0,0            ;   steps left in this one,
ch_stp:     db 0,0,0            ;   a step's size,
ch_pl:      db 0,0,0            ;   the pause after a step,
ch_pau:     db 0,0,0            ;   and the pause now
snd_q:      defs 3*SQN*8,0      ; the queues: 8 bytes a sound
snd_env:    defs 15*16,0        ; the envelopes

;; ---- files: through FutureOS ----
;;
;; A name is "[d:]name[.ext]", d a FutureOS drive A-M; without one, the
;; drive LISP.64K came from. Its directory must be one FutureOS has read
;; (buffered: TURBO_A..M) -- the drive LISP.64K was tagged on, or any other
;; tagged on the desktop before. A file is read whole into bank 6's blocks
;; 0-2 by LADE_N (at most 48 KB), its length from the directory's extents;
;; the resident part's FILE_GETC reads it from there.

;; CAS IN OPEN: B = the name's length, HL = the name (DE, a buffer, not
;; used) -> carry if the file is open
p_CAS_IN_OPEN:
    push ix
    call f_name
    jr nc,.no
    call f_find                 ; HL = its records
    jr nc,.no
    ld de,FILE_MAXREC+1
    or a
    sbc hl,de
    add hl,de
    jr nc,.no                   ; too long
    add hl,hl                   ; bytes: 128 x records
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld (in_len),hl
    ld a,3                      ; into the expansion, bank 6's block 0
    ld (REG08_4),a
    ld hl,#4000
    ld (REG16_3),hl
    ld hl,#7F00+IN_CFG0
    ld (AKT_RAM),hl
    ld a,(f_drive)
    or #80                      ; any header's addresses not used
    ld de,rs_fname
    ld hl,LADE_N
    call r_fos
    inc a
    jr nz,.no
    ld hl,0
    ld (in_pos),hl
    ld a,1
    ld (in_open),a
    pop ix
    scf
    ret
.no:
    pop ix
    xor a
    ld (in_open),a
    ld a,#0E
    or a
    ret

;; f_name: B = a name's length, HL = the name -> rs_fname (user 0, the name
;; and extension upper case, blank-filled), f_drive; carry if it is one
f_name:
    ld a,(rs_drive)
    ld (f_drive),a
    ld a,b
    cp 2
    jr c,.nod
    inc hl
    ld a,(hl)
    dec hl
    cp ":"
    jr nz,.nod
    ld a,(hl)
    and #DF
    sub "A"
    cp 13
    ret nc                      ; no such drive
    ld (f_drive),a
    inc hl
    inc hl
    dec b
    dec b
.nod:
    push hl
    ld hl,rs_fname
    ld (hl),0
    inc hl
    ld c,11
.bl:
    ld (hl),32
    inc hl
    dec c
    jr nz,.bl
    pop hl
    ld de,rs_fname+1
    ld c,8                      ; the name, up to 8
    ld a,b
    or a
    ret z                       ; (no carry: empty)
.n:
    ld a,(hl)
    inc hl
    cp "."
    jr z,.ext
    call f_up
    ld (de),a
    inc de
    dec c
    jr z,.skip
    djnz .n
    scf
    ret
.skip:                          ; past 8: up to the dot
    dec b
    scf
    ret z
    ld a,(hl)
    inc hl
    cp "."
    jr nz,.skip
.ext:
    dec b
    scf
    ret z
    ld de,rs_fname+9
    ld c,3
.e:
    ld a,(hl)
    inc hl
    call f_up
    ld (de),a
    inc de
    dec c
    scf
    ret z
    djnz .e
    scf
    ret
f_up:
    cp "a"
    ret c
    cp "z"+1
    ret nc
    sub 32
    ret

;; f_dir: f_drive's directory, as FutureOS buffers it -> f_cfg, its block;
;; HL its first entry; B its entries (32 bytes each); carry if it was read
f_dir:
    ld a,(f_drive)
    add a,a
    add a,a
    add a,a
    add a,TURBO_A and #FF
    ld l,a
    ld h,TURBO_A >> 8
    bit 0,(hl)
    ret z                       ; (no carry)
    inc hl
    ld a,(hl)
    ld (f_cfg),a
    inc hl
    ld d,(hl)                   ; its page
    inc hl
    ld a,(hl)                   ; its pages: 8 entries each
    add a,a
    add a,a
    add a,a
    ld b,a
    ld h,d
    ld l,0
    scf
    ret

;; f_find: rs_fname on f_drive -> HL = its records (128 bytes); carry if it
;; is there. The length is the last extent's: (EX + 32 S2) x 128 + RC.
f_find:
    call f_dir
    ret nc
    ld de,0
    ld (f_rec),de
    xor a
    ld (f_hit),a
.e:
    push bc
    push hl
    ld a,(f_cfg)
    ld b,16
    call r_eread
    call f_same
    jr nz,.next
    ld a,1
    ld (f_hit),a
    call f_recs
    ld de,(f_rec)
    or a
    sbc hl,de
    add hl,de
    jr c,.next
    ld (f_rec),hl
.next:
    pop hl
    ld de,32
    add hl,de
    pop bc
    djnz .e
    ld hl,(f_rec)
    ld a,(f_hit)
    rra
    ret
;; f_same: Z if rs_ebuf's entry is rs_fname's (attribute bits aside)
f_same:
    ld hl,rs_ebuf
    ld de,rs_fname
    ld a,(de)
    cp (hl)
    ret nz
    ld b,11
.c:
    inc hl
    inc de
    ld a,(hl)
    and #7F
    ld c,a
    ld a,(de)
    cp c
    ret nz
    djnz .c
    ret
;; f_recs: rs_ebuf's entry -> HL = the records up to its end, (EX + 32 S2)
;; x 128 + RC (&FFFF if that is more)
f_recs:
    ld a,(rs_ebuf+14)           ; S2
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld a,(rs_ebuf+12)           ; EX
    and #1F
    ld e,a
    ld d,0
    add hl,de                   ; the extent's number
    ld a,h
    cp 2
    jr nc,.big
    xor a                       ; x 128
    srl h
    rr l
    rra
    ld h,l
    ld l,a
    ld a,(rs_ebuf+15)           ; RC
    ld e,a
    add hl,de
    ret nc
.big:
    ld hl,#FFFF
    ret

;; CAS CATALOG: the directory of the drive LISP.64K came from, sorted, two
;; names a line as AMSDOS shows them, each with its size in KB
p_CAS_CATALOG:
    push ix
    ld a,(rs_drive)
    ld (f_drive),a
    call f_dir
    jp nc,.none
    xor a
    ld (cat_n),a
.e:
    push bc
    push hl
    ld a,(f_cfg)
    ld b,32
    call r_eread
    ld a,(rs_ebuf)
    or a
    jr nz,.next                 ; another user's, or &E5: free
    call cat_add
.next:
    pop hl
    ld de,32
    add hl,de
    pop bc
    djnz .e
    call cat_sort
    ld hl,cat_head
    call cat_puts
    ld a,(f_drive)
    add a,"A"
    call TXT_OUTPUT
    ld hl,cat_head2
    call cat_puts
    ld a,(cat_n)
    or a
    jr z,.done
    ld b,a
    ld hl,cat_tab
    ld c,0                      ; the column
.p:
    push bc
    push hl
    ld b,8
    call cat_put
    ld a,"."
    call TXT_OUTPUT
    ld b,3
    call cat_put
    ld e,(hl)                   ; records -> KB, rounded up
    inc hl
    ld d,(hl)
    ex de,hl
    ld de,7
    add hl,de
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l
    call cat_num
    ld a,"K"
    call TXT_OUTPUT
    pop hl
    ld de,13
    add hl,de
    pop bc
    ld a,c
    xor 1
    ld c,a
    ld a,32
    jr nz,.sp
    ld a,13
    call TXT_OUTPUT
    ld a,10
.sp:
    call TXT_OUTPUT
    ld a,c
    or a
    jr z,.nsp
    ld a,32
    call TXT_OUTPUT
    ld a,32
    call TXT_OUTPUT
.nsp:
    djnz .p
    ld a,c
    or a
    jr z,.done
    ld a,13
    call TXT_OUTPUT
    ld a,10
    call TXT_OUTPUT
.done:
    pop ix
    scf
    ret
.none:
    ld hl,cat_nodir
    call cat_puts
    pop ix
    or a
    ret
cat_head:   db 13,10,"Drive ",0
cat_head2:  db ": user  0",13,10,13,10,0
cat_nodir:  db "No directory read for this drive",13,10,0
;; cat_add: rs_ebuf's entry into cat_tab, or its records into the one there
cat_add:
    ld a,(cat_n)
    ld b,a
    ld hl,cat_tab
    or a
    jr z,.new
.f:
    push bc
    push hl
    ld de,rs_ebuf+1
    ld b,11
.c:
    ld a,(de)
    and #7F
    cp (hl)
    jr nz,.ne
    inc hl
    inc de
    djnz .c
    call f_recs                 ; the same file: the larger end
    ex de,hl
    pop hl
    push hl
    ld bc,11
    add hl,bc
    ld c,(hl)
    inc hl
    ld b,(hl)
    ex de,hl
    or a
    sbc hl,bc
    add hl,bc
    jr c,.ne2
    ex de,hl
    ld (hl),d
    dec hl
    ld (hl),e
.ne2:
    pop hl
    pop bc
    ret
.ne:
    pop hl
    ld de,13
    add hl,de
    pop bc
    djnz .f
.new:
    ld a,(cat_n)
    cp CAT_MAX
    ret nc
    inc a
    ld (cat_n),a
    ld de,rs_ebuf+1
    ex de,hl
    ld b,11
.cp:
    ld a,(hl)
    and #7F
    ld (de),a
    inc hl
    inc de
    djnz .cp
    push de
    call f_recs
    pop de
    ex de,hl
    ld (hl),e
    inc hl
    ld (hl),d
    ret
;; cat_sort: cat_tab by name (an insertion sort: some 64 names)
cat_sort:
    ld a,(cat_n)
    cp 2
    ret c
    ld b,a
    dec b
    ld hl,cat_tab+13
.o:
    push bc
    push hl
.i:
    push hl
    ld de,-13
    add hl,de                   ; the one before
    pop de                      ; DE: this one
    ld bc,cat_tab
    or a
    sbc hl,bc
    add hl,bc
    jr c,.in                    ; (before the first)
    push hl
    push de
    ld b,11
.cm:
    ld a,(de)
    cp (hl)
    jr c,.sw                    ; this one is less: swap
    jr nz,.ok
    inc hl
    inc de
    djnz .cm
.ok:
    pop de
    pop hl
.in:
    pop hl
    ld de,13
    add hl,de
    pop bc
    djnz .o
    ret
.sw:
    pop de
    pop hl
    push hl
    ld b,13
.x:
    ld a,(de)
    ld c,(hl)
    ld (hl),a
    ld a,c
    ld (de),a
    inc hl
    inc de
    djnz .x
    pop hl                      ; on with the one before
    jr .i
;; cat_put: B characters at HL (HL moved on)
cat_put:
    ld a,(hl)
    inc hl
    call TXT_OUTPUT
    djnz cat_put
    ret
;; cat_puts: the text at HL, to a 0
cat_puts:
    ld a,(hl)
    or a
    ret z
    inc hl
    call TXT_OUTPUT
    jr cat_puts
;; cat_num: HL (0-9999) right-aligned in four places
cat_num:
    ld b,0                      ; not started
    ld de,1000
    call .d
    ld de,100
    call .d
    ld de,10
    call .d
    ld a,l
    add a,"0"
    jp TXT_OUTPUT
.d:
    ld a,"0"-1
.l:
    inc a
    or a
    sbc hl,de
    jr nc,.l
    add hl,de
    cp "0"
    jr nz,.out
    inc b
    dec b
    jr nz,.out
    ld a,32
    jp TXT_OUTPUT
.out:
    ld b,1
    jp TXT_OUTPUT
CAT_MAX     equ 128
cat_n:      db 0
cat_tab:    defs CAT_MAX*13,0   ; the name (11), the records (2)
f_drive:    db 0
f_cfg:      db 0
f_rec:      dw 0
f_hit:      db 0

;; CAS OUT OPEN: B = the name's length, HL = the name -> carry if open:
;; written to bank 0's blocks 0-2 (the resident part's FILE_PUTC), saved
;; when it is closed
p_CAS_OUT_OPEN:
    push ix
    call f_name
    jr nc,.no
    call f_dir                  ; (its directory must have been read)
    jr nc,.no
    ld hl,rs_fname
    ld de,out_name
    ld bc,12
    ldir
    ld a,(f_drive)
    ld (out_drive),a
    call f_era                  ; an old one of the name gone now, before
    ld hl,0                     ;   anything is in bank 0's blocks (EWEG
    ld (out_pos),hl             ;   leaves directory data in free blocks)
    ld a,1
    ld (out_open),a
    pop ix
    scf
    ret
.no:
    pop ix
    ld a,#0E
    or a
    ret
p_CAS_OUT_ABANDON:
    xor a
    ld (out_open),a
    scf
    ret
;; CAS OUT CLOSE: the file saved through FutureOS -- its last record padded
;; with &1A, an old one of the name deleted (EWEG), the new one written
;; (TEISI, from the short-time buffers: bank 0's blocks 0-2 are the first),
;; the directory written back (SIDIR) -> carry if all went well
p_CAS_OUT_CLOSE:
    ld a,(out_open)
    or a
    scf
    ret z
    push ix
    call f_save
    call nc,f_saymsg            ; why not, as AMSDOS says it
    push af
    xor a
    ld (out_open),a
    ld bc,#FA7E                 ; the motors off
    out (c),a
    pop af
    pop ix
    ret
f_save:
.pad:
    ld hl,(out_pos)             ; to a whole record, at least one
    ld a,l
    and #7F
    jr nz,.p1
    ld a,h
    or l
    jr nz,.padded
.p1:
    ld a,#1A
    call r_fputc
    jr c,.pad
.padded:
    ld hl,(out_pos)             ; records: the bytes / 128
    ld a,l
    rla
    ld a,h
    rla
    ld l,a
    ld a,0
    rla
    ld h,a
    push hl
    dec hl                      ; the last extent's: 1-128
    ld a,l
    and #7F
    inc a
    ld (IDE_32_39),a
    xor a
    ld (IDE_40_47),a            ; (S1: none, as CP/M 2.2 and AMSDOS)
    pop hl
    ld a,(out_drive)            ; blocks: 1 KB, or 4 KB on a Vortex disc
    ld (f_drive),a
    push hl
    call f_vortex               ; (HL lost)
    pop hl
    ld de,7
    ld b,3
    jr nz,.bs
    ld de,31
    ld b,5
.bs:
    add hl,de
.sh:
    srl h
    rr l
    djnz .sh
    ld (REG_BC1),hl
    ld hl,XRAM_C4               ; bank 0's blocks 0-2 must be free to
    ld b,3                      ;   FutureOS (free, or short-time buffers)
.x:
    ld a,(hl)
    cp #01
    jr z,.xok
    cp #09
    ld a,5                      ; ("no room in the expansion")
    jr nz,.err
.xok:
    inc hl
    djnz .x
    ld bc,#FA7E                 ; the motor on
    ld a,#FF
    out (c),a
    call out_reg8
    call chg_off
    ld a,1                      ; (it writes in &0000-&3FFF)
    ld (fos_low),a
    ld a,(out_drive)
    ld hl,TEISI
    call r_fos
    push af
    call chg_on
    pop af
    cp #FF
    jr nz,.err                  ; an error, 0-6, or &F0
    ld hl,SIDIR
    call r_fosb
    scf
    ret
.err:
    or a                        ; (no carry; A the code)
    ret
;; chg_off: every drive's "directory changed" bit (3 of its tagging byte)
;; kept in chg_mask and cleared: TEISI sorts a changed directory first, in
;; the first free expansion block -- where the file is (from &2C00 on: the
;; file came out wrong past 11 KB, MAME 2026-11-19). chg_on: put back, the
;; output file's drive's set (TEISI changed it; SIDIR writes it back).
chg_off:
    ld hl,TURBO_A
    ld de,chg_mask
    ld b,13
.l:
    ld a,(hl)
    and 8
    ld (de),a
    res 3,(hl)
    inc de
    ld a,l
    add a,8
    ld l,a
    djnz .l
    ret
chg_on:
    ld hl,TURBO_A
    ld de,chg_mask
    ld b,13
.l:
    ld a,(de)
    or (hl)
    ld (hl),a
    inc de
    ld a,l
    add a,8
    ld l,a
    djnz .l
    ld a,(out_drive)
    ld (f_drive),a
    add a,a
    add a,a
    add a,a
    add a,TURBO_A and #FF
    ld l,a
    ld h,TURBO_A >> 8
    set 3,(hl)
    ret
chg_mask:   defs 13,0
;; out_reg8: REG16_8 = the output file's user, name, extension
out_reg8:
    ld hl,out_name
    ld de,REG16_8
    ld bc,12
    ldir
    ret
;; f_era: the output file's name deleted on its drive, in the buffered
;; directory (EWEG; it says changed). All lost.
f_era:
    call out_reg8
    ld a,(out_drive)
    ld (REG08_1),a
    ld hl,EWEG
    jp r_fos
;; f_vortex: f_drive's disc -> NZ if Vortex (its tagging byte: data 11..,
;; system 01.., IBM 001., Vortex 0001...: TEISI's own test)
f_vortex:
    ld a,(f_drive)
    add a,a
    add a,a
    add a,a
    add a,TURBO_A and #FF
    ld l,a
    ld h,TURBO_A >> 8
    ld a,(hl)
    and #F0
    cp #10
    ret
;; f_saymsg: A = TEISI's error code (0-6, &F0): "NAME.EXT not saved: why".
;; Carry clear after.
f_saymsg:
    push af
    ld hl,out_name+1
    ld b,8
    call cat_put
    ld a,"."
    call TXT_OUTPUT
    ld b,3
    call cat_put
    ld hl,sv_m
    call cat_puts
    pop af
    cp 7
    jr c,.k
    ld a,7
.k:
    ld hl,sv_why
.f:
    or a
    jr z,.p
.s:
    bit 7,(hl)
    inc hl
    jr z,.s
    dec a
    jr .f
.p:
    ld a,(hl)
    inc hl
    push af
    and #7F
    call TXT_OUTPUT
    pop af
    rla
    jr nc,.p
    ld a,13
    call TXT_OUTPUT
    ld a,10
    call TXT_OUTPUT
    or a
    ret
sv_m:       db " not saved: ",0
sv_why:     db "no directory rea","d"+#80
            db "the drive is not tagge","d"+#80
            db "it is empt","y"+#80
            db "disc ful","l"+#80
            db "directory ful","l"+#80
            db "no room in the expansio","n"+#80
            db "drive not read","y"+#80
            db "too lon","g"+#80
out_name:   defs 12,0
out_drive:  db 0

p_CAS_IN_CHAR:                  ; (the resident part's FILE_GETC)
    ld a,#1A
    or a
    ret
p_CAS_IN_CLOSE:
p_CAS_IN_ABANDON:
    xor a
    ld (in_open),a
    scf
    ret
p_CAS_OUT_CHAR:                 ; (the resident part's FILE_PUTC)
    jp r_fputc

;; |ERA, for delete-file (mach/cpc512/ramdisc.asm finds it with KL FIND
;; COMMAND and calls it with KL FAR PCHL, as the disc ROM's): KL FIND
;; COMMAND answers for "ERA" alone, KL FAR PCHL runs ours for its address.
p_KL_FIND_COMMAND:
    ld a,(hl)
    cp "E"
    jr nz,.no
    inc hl
    ld a,(hl)
    cp "R"
    jr nz,.no
    inc hl
    ld a,(hl)
    cp "A"+#80
    jr nz,.no
    ld hl,era_mark
    ld c,0
    scf
    ret
.no:
    or a
    ret
p_KL_FAR_PCHL:
    push de
    ld de,era_mark
    or a
    sbc hl,de
    pop de
    ret nz
;; era: IX = |ERA's parameters, one: a string descriptor (length, address)
;; -> the file deleted through FutureOS (EWEG, SIDIR), or "not found"
era_mark:
    ld l,(ix+0)
    ld h,(ix+1)                 ; the descriptor
    ld b,(hl)
    inc hl
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    push hl
    push bc
    call f_name
    jr nc,.nf
    call f_find
    jr nc,.nf
    ld hl,rs_fname
    ld de,out_name
    ld bc,12
    ldir
    ld a,(f_drive)
    ld (out_drive),a
    call f_era
    ld bc,#FA7E
    ld a,#FF
    out (c),a
    ld hl,SIDIR
    call r_fosb
    ld bc,#FA7E
    xor a
    out (c),a
    pop bc
    pop hl
    ret
.nf:
    pop bc
    pop hl
.p:
    ld a,(hl)
    inc hl
    call TXT_OUTPUT
    djnz .p
    ld hl,era_nf
    jp cat_puts
era_nf:     db " not found",13,10,0

;; ---- the rest ----
p_none:
    ret
;; EDIT (the firmware's line editor, used only without the library): an
;; empty line
p_EDIT_464:
p_EDIT_6128:
    ld (hl),0
    scf
    ret

;; p_init: once, from LISP.64K: the screen in mode 2, cleared; the text
;; pen 1 on paper 0; the border and the sixteen inks as the firmware sets
;; them (without its flashing)
p_init:
    ld a,1
    ld b,a
    ld c,a
    call p_SCR_SET_BORDER
    ld hl,ink_def
    xor a
.ink:
    ld b,(hl)
    ld c,b
    inc hl
    push af
    push hl
    call p_SCR_SET_INK
    pop hl
    pop af
    inc a
    cp 16
    jr nz,.ink
    ld a,1
    ld (pen),a
    xor a
    ld (paper),a
    ld a,2
    jp p_SCR_SET_MODE

ink_def:    db 1,24,20,6,26,0,2,8,10,12,14,16,18,22,1,16
shadow:     defs ROWS*80,32     ; the characters on the screen

page_end:
    print "page: ",page_end-#C000," bytes"
    assert page_end <= FOS_KEEP0
    defs #10000-$,0
