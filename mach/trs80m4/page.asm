;; CPC Lisp -- the TRS-80 Model 4's machine page: the routines behind the
;; machine interface (mach/README.md has their contracts), made from the
;; Model I/III's (mach/trs80/page.asm). The loader puts this in slot
;; MACHSLOT (bank 2, &C000); the resident part (resident.asm) brings it in
;; for each call through the jumpblock and puts the caller's slot back.
;; Its variables are here too: the page is RAM.
;;
;; THE SCREEN is the Model 4's: 80 by 24 characters at &F800, there in
;; memory map 2 only (the keyboard at &F400 with it). The Lisp runs in map
;; 3, so each routine that looks at them opens a window (vw_on, vw_off):
;; map 2 and the interrupts off -- LS-DOS's own drivers do the same. The
;; page ends below &F400, where map 2 leaves it in view. The console works
;; as the CPC's text VDU does, as far as the Lisp asks: a cursor that may
;; stand one past the last column until the next character wraps, a roll
;; count that goes down by one each scroll, the CPC's controls 7-13, 30
;; and 31. With trs80gp's emulator extensions (-ee), everything printed
;; goes to the printer too: the test transcript.
;;
;; KEYS come from LS-DOS (@KEY, @KBD): its type-ahead, and what trs80gp
;; types. GRAPHICS and SOUND are not here yet.

    include "firmware.asm"
    include "jumps.asm"
    include "memmap.asm"

    org #C000
    jp m_init                   ; the loader calls this once
    db "MODEL 4 MACHINE PAGE",0
    defs MTAB-$,0
    include "mtab.inc"

;; ---------------------------------------------------------------------------
;; STATE

c_col:      db 0                ; 0-79, or 80: past the end
c_row:      db 0                ; 0-23
c_roll:     db 0                ; down by one a scroll
c_sys:      db 0                ; the cursor on (CON_CURON)
c_usr:      db 1                ;   and enabled (CON_CURENA)
c_drawn:    db 0                ; it is on the screen,
c_under:    db 0                ;   over this character
c_esc:      db 0                ; 31 (locate): bytes still to come
c_parm:     db 0                ;   the column, when the row comes
c_echo:     db 0                ; 1: the printer gets it all too
k_back:     db 0                ; KEY_UNREAD's character, 0 if none
p_col:      db 0                ; the printer has had the screen up to here
p_row:      db 0
p_roll:     db 0
g_x:        dw 0                ; graphics: where the last one ended,
g_y:        dw 0
g_ox:       dw 0                ;   the origin,
g_oy:       dw 0
g_pen:      db 1                ;   1 draws, 0 erases,
g_ink:      db 0                ;   ink-mode: 0 plain, 1 XOR, 2 AND, 3 OR
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
    xor a
    ld (TK_MODE),a              ; Talker/80's mode not set yet: a reset
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
    ld (g_ink),a
    inc a
    ld (c_usr),a
    ld (g_pen),a
    ld hl,0
    ld (g_x),hl
    ld (g_y),hl
    ld (g_ox),hl
    ld (g_oy),hl
    call vw_on
    call c_clear
    jp vw_off

;; vw_on: the keyboard and the screen in (memory map 2), the interrupts
;; off; vw_off: map 3 as it was, the interrupts on. All but AF kept.
vw_on:
    di
    ld a,(RS_P84)
    and #FF-OP_MAP
    or 2
    out (OPREG),a
    ret
vw_off:
    ld a,(RS_P84)
    out (OPREG),a
    ei
    ret

;; k_svc: A = an LS-DOS call -> its A and flags; every other register kept
k_svc:
    push bc
    push de
    push hl
    push ix
    push iy
    call RS_SVC
    pop iy
    pop ix
    pop hl
    pop de
    pop bc
    ret

;; ---------------------------------------------------------------------------
;; CONSOLE

;; c_addr: -> HL = the screen address of the cursor's cell (c_col < 80)
c_addr:
    ld a,(c_row)
    call c_rowaddr
    ld a,(c_col)
    add a,l
    ld l,a
    ret nc
    inc h
    ret
;; c_rowaddr: A = a row -> HL = its screen address (VRAM + 80 * row).
;; All but AF kept.
c_rowaddr:
    push de
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl                   ; 16 * row
    ld d,h
    ld e,l
    add hl,hl
    add hl,hl                   ; 64 * row
    add hl,de                   ; 80 * row
    ld de,VRAM
    add hl,de
    pop de
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

;; c_print: C to the printer, at port &F8; bit 7 of the status is busy
c_print:
.m3:
    in a,(#F8)
    rlca
    jr c,.m3
    ld a,c
    out (#F8),a
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
    call c_pause
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

;; c_pause: SHIFT @ held as the screen is to scroll -> the output waits,
;; LS-DOS's way, until they are let go and another key is pressed (and
;; let go). The keyboard is memory, in map 2: &F401 row 0 (@ is bit 0),
;; &F480 row 7 (the SHIFTs), &F4FF every row at once. All kept but AF.
c_pause:
    ld a,(KBD+#80)
    and 3
    ret z
    ld a,(KBD+1)
    rra
    ret nc
.up:
    ld a,(KBD+#FF)              ; SHIFT @ let go,
    or a
    jr nz,.up
.down:
    ld a,(KBD+#FF)              ;   a key,
    or a
    jr z,.down
.up2:
    ld a,(KBD+#FF)              ;   and that let go
    or a
    jr nz,.up2
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
    call vw_on
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
    call c_mark
    call c_show
    call vw_off
    pop hl
    pop de
    pop bc
    pop af
    ret

;; c_mark: the printer has had all up to the cursor
c_mark:
    ld a,(c_col)
    ld (p_col),a
    ld a,(c_row)
    ld (p_row),a
    ld a,(c_roll)
    ld (p_roll),a
    ret

;; c_typed: the line typed since (the editor's echo is not printed): the
;; screen from where the printer stopped to the end of the cursor's row,
;; spaces at the end left out
c_typed:
    call c_hide
    ld a,(c_roll)
    ld b,a
    ld a,(p_roll)
    sub b                       ; scrolls since
    ld b,a
    ld a,(p_row)
    sub b
    jr nc,.r
    xor a
    ld (p_col),a                ; scrolled off: from the screen's top
.r:
    ld c,a                      ; the first row
    ld a,(p_col)
    ld e,a                      ; its column
.row:
    push bc
    ld a,c
    ld (t32),a
    ; the end of the row's text
    ld a,c
    call c_rowaddr              ; HL = the row's start
    ld d,VCOLS
    ld a,(c_row)
    cp c
    jr nz,.got                  ; a row the line goes on from: all of it
.end:
    push hl
    ld a,d
    dec a
    add a,l
    ld l,a
    jr nc,.nc2
    inc h
.nc2:
    ld a,(hl)
    pop hl
    cp ' '
    jr nz,.got
    dec d
    ld a,d
    cp e
    jr z,.got
    jr nc,.end
.got:
    ld a,l
    add a,e
    ld l,a                      ; from the column
    jr nc,.nc
    inc h
.nc:
    ld a,d
    sub e
    jr z,.nl
    jr c,.nl
    ld b,a
.ch:
    ld c,(hl)
    call c_print
    inc hl
    djnz .ch
.nl:
    pop bc
    ld e,0
    ld a,c
    ld hl,c_row
    cp (hl)
    inc c
    jr c,.row
    call c_mark
    jp c_show

;; CON_WRCH: A = a character, drawn as it is. Every register kept.
m_con_wrch:
    push af
    push bc
    push de
    push hl
    ld c,a
    call vw_on
    call c_hide
    ld a,c
    call c_put
    call c_show
    call vw_off
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
    call vw_on
    call c_addr
    ld h,(hl)
    call vw_off
    ld a,h
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
    call vw_on
    call c_hide
    call c_setcur
    call c_show
    jp vw_off

;; the cursor's two switches. Every register but AF kept.
m_con_curon:
    ld a,1
    ld (c_sys),a
    jr c_show_w
m_con_curoff:
    call vw_on
    call c_hide
    call vw_off
    xor a
    ld (c_sys),a
    ret
m_con_curena:
    ld a,1
    ld (c_usr),a
    jr c_show_w
m_con_curdis:
    call vw_on
    call c_hide
    call vw_off
    xor a
    ld (c_usr),a
    ret
;; c_show_w: c_show in a window of its own
c_show_w:
    call vw_on
    call c_show
    jp vw_off

;; CON_GETWIN: the whole screen -> H, D = columns 0, 79; L, E = rows 0, 23
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
    call vw_on
    call c_clear
    call c_show
    call vw_off
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
;; KEYS: LS-DOS's (@KEY, @KBD), its codes made the CPC's
;;   BREAK ESC, CLEAR CLR, <- left, SHIFT <- DEL, -> right, SHIFT -> TAB,
;;   up and down, SHIFT up the copy cursor's up: the arrows only move, as
;;   on the Model I/III; F1 is COPY. SHIFT DOWN-ARROW, pressed and let go,
;;   makes the next key one the keyboard has not got (k_comp): twice is
;;   the copy cursor's down.

k_codes:
    db #80,#FC, #1F,#10, #08,#F2, #18,#7F, #09,#F3, #19,#09
    db #0B,#F0, #0A,#F1, #1B,#F4, #81,#E0, 0

;; after SHIFT DOWN-ARROW: a key, shifted or not, and what it makes
k_comp:
    db '-','~', '=','~'         ; ~ format's directives
    db '/',#5C, '?',#5C         ; \ characters #\a, escapes
    db '1','|', '!','|'         ; | odd names, #| comments |#
    db '7','`', "'",'`'         ; ` backquote
    db '8','[', '(','['         ; [ ] format's ~[ ~]
    db '9',']', ')',']'
    db ',','{', '<','{'         ; { } format's ~{ ~}
    db '.','}', '>','}'
    db '@','^'                  ; ^ format's ~^
    db '0','_'
    db 'S',#13, 's',#13         ; CTRL-S: the function editor's "done"
    db 'C',#E0, 'c',#E0         ; COPY: from the copy cursor; also "done"
    db #1A,#F5                  ; SHIFT DOWN-ARROW again: copy cursor down
    db 0

;; KEY_READ: -> carry and A = a character; no carry if there is none
m_key_read:
    call k_backed
    ret c
    ld a,SV_KBD
    call k_svc
    jr z,.got
    or a                        ; NC: none
    ret
.got:
    or a
    ret z
    jr k_cook

;; KEY_WAIT: -> A = a character, from @KEY -- where trs80gp's typed input
;; (-i) arrives too
m_key_wait:
    call k_backed
    ret c
    ld a,SV_KEY
    call k_svc
    call k_cook
    jr nc,m_key_wait            ; the prefix: wait for the key after it
    cp 13
    scf
    ret nz
    ld a,(c_echo)
    or a
    ld a,13
    scf
    ret z
    call vw_on
    call c_typed                ; ENTER: the transcript gets the line
    call vw_off
    ld a,13
    scf
    ret

;; k_cook: A = LS-DOS's code -> carry and A = the CPC's; no carry for
;; SHIFT DOWN-ARROW, which is waiting for the next key. BC, DE, HL kept.
k_cook:
    push bc
    push hl
    ld hl,k_compose
    bit 0,(hl)
    jr z,.plain
    ld (hl),0
    ld hl,k_comp
    call k_look                 ; composed: one from the table, or the key
    jr .got
.plain:
    cp #1A
    jr nz,.x
    ld (hl),1                   ; SHIFT DOWN-ARROW: the next key composes
    pop hl
    pop bc
    or a
    ret
.x:
    ld hl,k_codes
    call k_look
.got:
    pop hl
    pop bc
    scf
    ret
;; k_look: A = a code, HL = a table of pairs ending in 0 -> A = its pair's
;; second, or as it was. C, HL lost.
k_look:
    ld c,(hl)
    inc c
    dec c
    ret z
    inc hl
    cp c
    ld c,(hl)
    inc hl
    jr nz,k_look
    ld a,c
    ret
k_compose:  db 0

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
    ld l,a                      ; the row's address: &F400 + 2^row
    call vw_on
    ld a,h
    ld h,KBD >> 8
    and (hl)
    ld b,a
    call vw_off
    ld a,b
    or a
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

;; VID_FRAME: about a fiftieth of a second (20 ms at 4 MHz)
m_vid_frame:
    push bc
    ld b,24
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
    call vw_on
    call c_hide
    ld a,d
    sub h
    inc a
    ld c,a                      ; columns
    ld a,e
    sub l
    inc a
    ld b,a                      ; rows
    ld a,l                      ; the first row
    ld e,h                      ; E = the first column
.row:
    push bc
    push af
    call c_rowaddr              ; HL = the row's start
    ld a,l
    add a,e
    ld l,a
    jr nc,.nc
    inc h
.nc:
    ld b,c
.col:
    ld (hl),' '
    inc hl
    djnz .col
    pop af
    inc a
    pop bc
    djnz .row
    jp vw_off

;; ---------------------------------------------------------------------------
;; GRAPHICS: not yet (the hi-res board comes next) -- the position is kept

m_gfx_plot:
m_gfx_plotr:
m_gfx_line:
m_gfx_liner:
m_gfx_clear:
m_m_inkmode:
m_m_fill:
    ret
m_gfx_move:
    ld (g_x),de
    ld (g_y),hl
    ret
m_gfx_mover:
    push hl
    ld hl,(g_x)
    add hl,de
    ld (g_x),hl
    pop de
    ld hl,(g_y)
    add hl,de
    ld (g_y),hl
    ret
m_gfx_test:
m_gfx_testr:
    xor a
    ret
m_gfx_where:
    ld de,(g_x)
    ld hl,(g_y)
    ret
m_gfx_origin:
    ld (g_ox),de
    ld (g_oy),hl
    ld hl,0
    ld (g_x),hl
    ld (g_y),hl
    ret
m_gfx_pen:
    ld (g_pen),a
    ret

;; ---------------------------------------------------------------------------
;; SOUND: not yet -- a note is taken (carry), not heard

m_snd_queue:
    scf
    ret

;; ---------------------------------------------------------------------------
;; FILES: files4.asm (no RAM disc on the Model 4: M: is no drive)

    include "files4.asm"

m_m_rdin:
m_m_rdout:
    or a
    ret
m_m_rdcat:
    ret

;; ---------------------------------------------------------------------------
;; FLOATS: fp4.asm

    include "fp4.asm"

;; ---------------------------------------------------------------------------
;; SYSTEM

;; SYS_TIME: -> DEHL = a count of 1/300 s: the clock task's ticks (resident,
;; 30 a second) times 10
m_sys_time:
    push bc
    di
    ld hl,(RS_TICKS)
    ld bc,(RS_TICKS+2)          ; BCHL = the ticks
    ei
    add hl,hl
    rl c
    rl b                        ; * 2
    push bc
    push hl
    add hl,hl
    rl c
    rl b
    add hl,hl
    rl c
    rl b                        ; * 8
    pop de
    add hl,de                   ; the low words: * 8 + * 2
    ex de,hl
    pop hl
    adc hl,bc                   ; the high ones, and the carry
    ex de,hl                    ; DEHL
    pop bc
    ret

;; M_EDIT: a line typed into (HL), for when there is no library's editor
;; -> carry for ENTER, none for BREAK
m_m_edit:
    push hl
    ld b,0
    ld a,1
    ld (c_sys),a
.k:
    call c_show_w
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

;; M_QUIT: back to LS-DOS -- or out of trs80gp, with -ee: the clock task
;; and the banks given back, and @EXIT through the gate, which puts bank 0
;; in as LS-DOS had it
m_m_quit:
    ld a,(c_echo)
    or a
    jr z,.dos
    ld bc,0
    ld a,128
    out (EE_PORT),a
.dos:
    ld a,(RS_TSLOT)
    cp 255
    jr z,.banks
    ld c,a
    ld a,SV_RMTSK
    call RS_SVC
.banks:
    ld c,1
    ld b,1
    ld a,SV_BANK
    call RS_SVC
    ld c,2
    ld b,1
    ld a,SV_BANK
    call RS_SVC
    ld hl,0
    ld a,SV_EXIT
    jp RS_SVC                   ; (it does not come back)

;; M_MIDI: A = a byte -> out of MIDI/80 (port 8), and its time on the
;; wire after it (a MIDI byte takes 320 us; TRACKER waits about 430). In
;; trs80gp (-ee), which has no MIDI/80, copied to the printer as <hex>, so
;; that a transcript shows it. All kept but AF.
MIDI_PORT   equ 8
m_m_midi:
    out (MIDI_PORT),a
    push bc
    ld c,a
    ld a,(c_echo)
    or a
    call nz,.echo
    ld b,64                     ; ~830 T: 470 us on a Model I, 410 on a III
.w:
    djnz .w
    pop bc
    ret
.echo:
    push bc
    ld b,c
    ld c,'<'
    call c_print
    ld a,b
    rrca
    rrca
    rrca
    rrca
    call .hex
    ld a,b
    call .hex
    ld c,'>'
    call c_print
    pop bc
    ret
.hex:
    and 15
    add a,'0'
    cp '9'+1
    jr c,.h
    add a,7
.h:
    ld c,a
    jp c_print

page_end:
    print "machine page: ",page_end-#C000," bytes"
    assert page_end <= #F400
    defs #10000-$,#FF
