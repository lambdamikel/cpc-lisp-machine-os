;; CPC Lisp on FutureOS itself -- the machine page: the CPC firmware's
;; routines that Lisp calls, done again without the firmware. A 16 KB image
;; of its own (LISP6.IMG), in bank 7's block 3, mapped at &C000 by the
;; resident part's trampolines (fwp) for each call; what needs the screen's
;; RAM -- which is at &C000 only in configuration C0 -- it asks the
;; resident part for (r_glyph, r_rowfill, r_rowcopy).
;;
;; Each routine keeps the contract of the firmware routine it stands for
;; (The Amstrad CPC Firmware Guide; mach/README.md says what Lisp relies
;; on). So far: the text screen in mode 2 -- characters drawn by FutureOS's
;; PR_2 --, the keys, the screen's mode and inks, the time. Graphics, sound
;; and files are stubs that do nothing (or fail) for now.
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

    org #C000
    include "pagetab.inc"       ; the firmware's names, in mkfw.py's order
    jp p_init                   ; LISP.64K's finisher calls it once

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
gfx_x:      dw 0                ; the graphics cursor (stubs)
gfx_y:      dw 0
gfx_ox:     dw 0
gfx_oy:     dw 0
gfx_pen:    db 1
gfx_paper:  db 0
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
;; draw_cell: A, C = column, B = row: drawn, from the shadow's character
;; (inverted when the paper is the lit ink)
draw_cell:
    push af
    call cell_addr
    pop af
    ld e,a
    ld a,(paper)
    ld d,a
    ld a,(pen)
    xor d
    and 1
    ld b,0
    jr nz,.pn
    ld a,d                      ; pen = paper: nothing to see but paper
    and 1
    ld b,a
    ld e,32
    jr .go
.pn:
    ld a,d
    and 1
    ld b,a                      ; paper 1: inverted
.go:
    ld a,e
    jp r_glyph
;; draw_inv: the cursor -- the shadow's character at C, B inverted
draw_inv:
    push bc
    call shadow_at
    pop bc
    ld a,(hl)
    push af
    call cell_addr
    pop af
    ld e,a
    ld a,(paper)
    and 1
    xor 1
    ld b,a
    ld a,e
    jp r_glyph

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
p_SCR_ACCESS:
    ret
p_SCR_DOT_POSITION:
    ld hl,#C000
    ld c,#80
    ld b,1
    ret
p_SCR_NEXT_BYTE:
    inc hl
    ret
p_SCR_PREV_BYTE:
    dec hl
    ret

;; ---- the keys ----

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

;; ---- graphics: not yet (the graphics cursor is kept) ----
p_GRA_MOVE_ABSOLUTE:
p_GRA_PLOT_ABSOLUTE:
p_GRA_LINE_ABSOLUTE:
    ld (gfx_x),de
    ld (gfx_y),hl
    ret
p_GRA_MOVE_RELATIVE:
p_GRA_PLOT_RELATIVE:
p_GRA_LINE_RELATIVE:
    push hl
    ld hl,(gfx_x)
    add hl,de
    ld (gfx_x),hl
    pop hl
    ld de,(gfx_y)
    add hl,de
    ld (gfx_y),hl
    ld de,(gfx_x)
    ret
p_GRA_ASK_CURSOR:
    ld de,(gfx_x)
    ld hl,(gfx_y)
    ret
p_GRA_SET_ORIGIN:
    ld (gfx_ox),de
    ld (gfx_oy),hl
    ret
p_GRA_GET_ORIGIN:
    ld de,(gfx_ox)
    ld hl,(gfx_oy)
    ret
p_GRA_CLEAR_WINDOW:
    ret
p_GRA_SET_PEN:
    ld (gfx_pen),a
    ret
p_GRA_GET_PEN:
    ld a,(gfx_pen)
    ret
p_GRA_SET_PAPER:
    ld (gfx_paper),a
    ret
p_GRA_TEST_ABSOLUTE:
p_GRA_TEST_RELATIVE:
    xor a
    ret

;; ---- sound: not yet ----
p_SOUND_QUEUE:
    scf
    ret
p_SOUND_CHECK:
    ld a,4
    ret
p_SOUND_RELEASE:
p_SOUND_HOLD:
p_SOUND_CONTINUE:
p_SOUND_AMPL_ENVELOPE:
p_SOUND_TONE_ENVELOPE:
    ret

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
    ld b,16
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

;; the output file: not yet
p_CAS_OUT_OPEN:
    ld a,#0E
    or a
    ret
p_CAS_IN_CHAR:                  ; (the resident part's FILE_GETC)
    ld a,#1A
    or a
    ret
p_CAS_IN_CLOSE:
p_CAS_IN_ABANDON:
    xor a
    ld (in_open),a
p_CAS_OUT_CLOSE:
p_CAS_OUT_ABANDON:
p_CAS_OUT_CHAR:
    scf
    ret

;; ---- the rest ----
p_KL_FIND_COMMAND:
    or a
    ret
p_KL_FAR_PCHL:
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
;; pen 1 on paper 0; the inks as the firmware's (border and ink 0 blue, ink
;; 1 bright yellow, 2 bright cyan, 3 bright red)
p_init:
    ld a,1
    ld b,a
    ld c,a
    call p_SCR_SET_BORDER
    xor a
    call p_SCR_SET_INK
    ld a,1
    ld bc,24*257
    call p_SCR_SET_INK
    ld a,2
    ld bc,20*257
    call p_SCR_SET_INK
    ld a,3
    ld bc,6*257
    call p_SCR_SET_INK
    ld a,1
    ld (pen),a
    xor a
    ld (paper),a
    ld a,2
    jp p_SCR_SET_MODE

shadow:     defs ROWS*80,32     ; the characters on the screen

page_end:
    print "page: ",page_end-#C000," bytes"
    assert page_end <= FOS_KEEP0
    defs #10000-$,0
