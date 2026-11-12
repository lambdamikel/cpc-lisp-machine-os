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
c_m3:       db 0                ; 1: a Model III
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
    ld a,(#0125)                ; the Model III's ROM has an "I" there
    cp 'I'
    ld a,0
    jr nz,.m1
    inc a
.m1:
    ld (c_m3),a
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
    call f_init                 ; the ROM's divide helper in place
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

;; c_print: C to the printer: the Model I's at &37E8, the Model III's at
;; port &F8; bit 7 of the status is busy
c_print:
    ld a,(c_m3)
    or a
    jr nz,.m3
.w1:
    ld a,(PRINTER)
    rlca
    jr c,.w1
    ld a,c
    ld (PRINTER),a
    ret
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
;; LDOS's way, until they are let go and another key is pressed (and let
;; go). The keyboard is memory: &3801 row 0 (@ is bit 0), &3880 row 7
;; (the SHIFTs), &38FF every row at once. All kept but AF.
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
    ld l,c
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld a,h
    add a,VRAM >> 8
    ld h,a                      ; HL = the row's start
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
;;   BREAK ESC, CLEAR CLR, <- left, SHIFT <- DEL, -> right, SHIFT -> TAB,
;;   up and down, SHIFT up the copy cursor's up: the arrows only move
;;   (Mike, 2026-11-12), the TRS-80's <- backspace is SHIFT <-
;; and SHIFT DOWN-ARROW, pressed and let go, makes the next key one the
;; keyboard has not got (k_comp): twice is the copy cursor's down.

k_codes:
    db #01,#FC, #1F,#10, #08,#F2, #18,#7F, #09,#F3, #19,#09
    db #5B,#F0, #0A,#F1, #1B,#F4, 0

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
    db #1A,#F5                  ; SHIFT DOWN-ARROW again: copy cursor down
    db 0

;; KEY_READ: -> carry and A = a character; no carry if there is none
m_key_read:
    call k_backed
    ret c
    call k_scan
    or a
    ret z                       ; NC: none
    jr k_cook

;; KEY_WAIT: -> A = a character. It waits in the ROM's own loop (&0049),
;; where trs80gp's typed input (-i) arrives too.
m_key_wait:
    call k_backed
    ret c
    call k_wait
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
    call c_typed                ; ENTER: the transcript gets the line
    ld a,13
    scf
    ret

;; k_scan, k_wait: the ROM's key routines, every register but AF kept
k_scan:
    ld a,0
    jr k_rom
k_wait:
    ld a,1
k_rom:
    push bc
    push de
    push hl
    push ix
    push iy
    or a
    jr nz,.w
    call ROM_KBD                ; a key, or 0
    jr .done
.w:
    call ROM_KEY
.done:
    pop iy
    pop ix
    pop hl
    pop de
    pop bc
    ret

;; k_cook: A = the ROM's code -> carry and A = the CPC's; no carry for
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
    ld hl,g_rows
    add a,l
    ld l,a
    ld a,(hl)                   ; (row mod 3) * 32 + row / 3
    ld b,a
    rlca
    rlca
    rlca
    rlca                        ; 2 * (row mod 3) ...
    and 6
    bit 0,e
    jr z,.b
    inc a                       ;   + 1 on the right
.b:
    add a,g_bits and #FF
    ld l,a
    ld c,(hl)                   ; the block's bit
    ld a,b
    and 31
    ld l,a                      ; the character row
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

;; g_rows: for each block row, (row mod 3) * 32 + row / 3; g_bits: a
;; block's bit, from its number in the character (2 * row + column)
g_rows:
    db 0,32,64,1,33,65,2,34,66,3,35,67
    db 4,36,68,5,37,69,6,38,70,7,39,71
    db 8,40,72,9,41,73,10,42,74,11,43,75
    db 12,44,76,13,45,77,14,46,78,15,47,79
g_bits:     db 1,2,4,8,16,32
    assert g_rows >> 8 == (g_bits + 5) >> 8   ; (one page: g_cell adds to L)

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

;; M_INKMODE: A = how lines are drawn: 0 plain, 1 XOR, 2 AND, 3 OR (the
;; pen with what is there)
m_m_inkmode:
    and 3
    ld (g_ink),a
    ret

;; M_FILL: DE = x, HL = y, logical -> the area around that block of its
;; colour, to where the other starts, made the pen's; the position there.
;; A row at a time: a run of blocks to its ends, the runs above and below
;; it noted on a stack to do next (FILL_STK, past the page's code). Two
;; colours: a block painted is no longer the area's, so nothing is done
;; twice. IX corrupt.
m_m_fill:
    call m_gfx_move
    call g_pix
    ld a,d
    or h
    ret nz                      ; off the screen
    ld a,e
    cp 128
    ret nc
    ld a,l
    cp 48
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
    cp 47
    jr nc,.right
    inc l                       ; the row below
    ld bc,ff_dn
    call ff_side
    dec l
.right:
    inc e
    ld a,e
    cp 128
    jr c,.r
    jr .next
.done:
    pop af
    ld (g_ink),a
    ret
;; ff_side: E, L = a block next to the run, BC = its side's flag -> a run
;; starting there noted, if it is the area's and the block before it was
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
;; ff_push: E, L = a block -> on the stack (unless it is full)
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
;; ff_is: E, L = a block -> Z if it is the area's colour. BC, DE, HL kept.
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
    ld de,(l_y0)                ; a row? the quick way
    or a
    sbc hl,de
    jp z,g_hline
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

;; g_hline: a line along one row of blocks, l_x0 to l_x1 at l_y0: clipped
;; to the screen, then each block set the pen's way (g_set's, without its
;; sums)
g_hline:
    ld hl,(l_y0)
    ld a,h
    or a
    ret nz                      ; off the screen
    ld a,l
    cp 48
    ret nc
    ld de,(l_x0)
    ld hl,(l_x1)
    push hl
    or a
    sbc hl,de
    pop hl
    jp p,.ord
    ex de,hl                    ; DE = the left end, HL = the right
.ord:
    bit 7,h
    ret nz                      ; all to the left
    ld a,h
    or a
    jr nz,.r127
    ld a,l
    cp 128
    jr c,.rok
.r127:
    ld hl,127
.rok:
    bit 7,d
    jr nz,.l0
    ld a,d
    or a
    ret nz                      ; all to the right
    ld a,e
    cp 128
    ret nc
    jr .lok
.l0:
    ld de,0
.lok:
    ld a,l
    sub e
    ret c
    inc a
    ld (l_dx),a                 ; blocks to set
    push de
    ld de,0
    ld hl,(l_y0)
    call g_cell                 ; HL = the row's first cell, C = the bit
    pop de                      ;   of an even column
    ld a,c                      ; the masks: even column C, odd C * 2
    ld (l_sx),a
    add a,a
    ld (l_sx+1),a
    ld a,e
    srl a
    add a,l
    ld l,a                      ; the left end's cell
    ld b,0
    bit 0,e
    jr z,.even
    inc b                       ; start on the odd half
.even:
    ld a,(l_dx)
    ld c,a
.blk:
    ld a,b
    or a
    ld a,(l_sx)
    jr z,.m
    ld a,(l_sx+1)
.m:
    ld d,a                      ; this block's bit
    ld a,(hl)
    bit 7,a
    jr nz,.g
    ld a,#80
.g:
    ld e,a
    ld a,(g_ink)
    dec a
    jr z,.xor
    dec a
    jr z,.and
    dec a
    jr z,.or
    ld a,(g_pen)
    or a
    jr nz,.on
.off:
    ld a,d
    cpl
    and e
    jr .put
.xor:
    ld a,(g_pen)
    or a
    jr z,.next
    ld a,e
    xor d
    jr .put
.and:
    ld a,(g_pen)
    or a
    jr z,.off
    jr .next
.or:
    ld a,(g_pen)
    or a
    jr z,.next
.on:
    ld a,e
    or d
.put:
    ld (hl),a
.next:
    ld a,b
    xor 1
    ld b,a
    jr nz,.same
    inc hl                      ; past an odd column: the next cell
.same:
    dec c
    jr nz,.blk
    ret

;; ---------------------------------------------------------------------------
;; SOUND: one voice, a square wave on the cassette port (&FF, bits 0 and 1;
;; trs80gp plays it). The CPC's sound record: [3] the period, 125000 / the
;; frequency, [6] the volume, [7] the duration in 1/100 s (0: 0.2 s). The
;; note is played there and then; envelopes and the other channels are not
;; heard. A half wave takes period / 250000 s: the note lasts while
;; duration * 2500 of those units are not used up.

s_t:        db 0,0,0            ; the units left
s_x:        db 0,0,0            ; (for multiplying)
s_lvl:      db 1

m_snd_queue:
    push hl
    pop ix                      ; IX = the record
    ld l,(ix+7)
    ld h,(ix+8)
    ld a,h
    or l
    jr nz,.d
    ld hl,20
.d:
    push hl
    call s_2500                 ; s_t = duration * 2500
    pop hl
    ld c,(ix+3)
    ld b,(ix+4)                 ; BC = the period
    ld a,b
    or c
    jr z,.rest
    ld a,(ix+6)
    or a
    jr z,.rest
    ; the delay for half a wave: period * 7.1 T-states at 1.774 MHz, or
    ; period * 8.1 at 2.03 (a Model III), less what the clock's interrupts
    ; take (about a tenth, measured), 26 a loop: period/4 - period/64, or
    ; period/4 + period/32
    ld h,b
    ld l,c
    srl h
    rr l
    srl h
    rr l                        ; /4
    push hl
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l                        ; /32
    ld a,(c_m3)
    or a
    jr nz,.m3
    srl h
    rr l                        ; /64
    ex de,hl
    pop hl
    or a
    sbc hl,de
    jr .k
.m3:
    pop de
    add hl,de
.k:
    ex de,hl                    ; DE = the delay's loops
    inc de
.wave:
    ld a,(s_lvl)
    xor 3
    ld (s_lvl),a
    out (#FF),a
    push de
.dl:
    dec de
    ld a,d
    or e
    jr nz,.dl
    pop de
    ld hl,(s_t)
    or a
    sbc hl,bc
    ld (s_t),hl
    ld a,(s_t+2)
    sbc a,0
    ld (s_t+2),a
    jr nc,.wave
    xor a
    out (#FF),a
    scf
    ret
.rest:                          ; silence: duration * 10 ms
    ld b,h
    ld c,l
.r:
    ld de,640                   ; about 10 ms
.rl:
    dec de
    ld a,d
    or e
    jr nz,.rl
    dec bc
    ld a,b
    or c
    jr nz,.r
    scf
    ret

;; s_2500: HL = a number -> s_t = it times 2500 (24 bits)
s_2500:
    xor a
    ld (s_t),a
    ld (s_t+1),a
    ld (s_t+2),a
    ld (s_x),hl
    ld (s_x+2),a
    ld de,2500
    ld b,12
.bit:
    srl d
    rr e
    jr nc,.no
    ld hl,(s_t)                 ; s_t += s_x
    ld a,(s_x)
    add a,l
    ld l,a
    ld a,(s_x+1)
    adc a,h
    ld h,a
    ld (s_t),hl
    ld a,(s_x+2)
    ld hl,s_t+2
    adc a,(hl)
    ld (hl),a
.no:
    ld hl,(s_x)                 ; s_x *= 2
    add hl,hl
    ld (s_x),hl
    ld hl,s_x+2
    rl (hl)
    djnz .bit
    ret

;; ---------------------------------------------------------------------------
;; FILES: files80.asm

    include "files80.asm"
    include "rdisc80.asm"

;; ---------------------------------------------------------------------------
;; FLOATS: fp80.asm

    include "fp80.asm"

;; ---------------------------------------------------------------------------
;; SYSTEM

;; SYS_TIME: -> DEHL = a count of 1/300 s, from LDOS's clock and its
;; ticks. A Model III's LDOS counts 30 down to 1 at &4216 within each
;; second (seconds, minutes, hours at &4217): the second * 300 and the
;; ticks into it * 10. A Model I's counts 25 ms ticks at &4040, a byte that
;; runs on through the seconds (theirs at &4041): the ticks since the last
;; call are the number that is the byte's difference, modulo 256, and
;; nearest 40 times the seconds that went by -- exact for any time between
;; calls, the clock being less than 40 ticks out. They are added up, from
;; the time of day at the first call, and made 1/300 s (* 15 / 2).
m_sys_time:
    ld ix,t_raw
    ld a,(c_m3)
    or a
    jp nz,.m3
    di
    ld a,(L_TIME-1)             ; the ticks
    ld (ix+3),a
    ld hl,(L_TIME)              ; seconds, minutes
    ld a,(L_TIME+2)             ;   hours
    ei
    ld (ix+0),l
    ld (ix+1),h
    ld (ix+2),a
    ld a,(t_init)
    or a
    jr z,.first
    ld de,(t_lastR)             ; the same second as last time? Then the
    or a                        ;   ticks since are the byte's difference
    sbc hl,de
    jr nz,.new
    ld a,(t_lastR+2)
    cp (ix+2)
    jr nz,.new
    ld a,(t_lastT)
    ld b,a
    ld a,(ix+3)
    ld (t_lastT),a
    sub b
    ld l,a
    ld h,0
    ld de,0
    jr .add
.first:
    inc a
    ld (t_init),a
    call .secs                  ; DEHL = the second of the day
    call .last
    ld c,40
    call mul32                  ; the ticks, as the clock has them
    jr .total
.new:
    call .secs
    push de
    push hl
    ld bc,(t_lastS)             ; the seconds since, modulo a day
    or a
    sbc hl,bc
    ex de,hl
    ld bc,(t_lastS+2)
    sbc hl,bc
    ex de,hl
    jr nc,.pos
    ld bc,#5180                 ; + 86400
    add hl,bc
    ex de,hl
    ld bc,1
    adc hl,bc
    ex de,hl
.pos:
    ld c,40
    call mul32                  ; DEHL: about the ticks since
    ld a,(t_lastT)
    ld b,a
    ld a,(ix+3)
    sub b                       ; the byte's difference,
    sub l                       ;   less the estimate's: -128..127 off
    ld c,a
    ld b,0
    bit 7,a
    jr z,.adj
    dec b
.adj:
    add hl,bc
    ld a,e
    adc a,b
    ld e,a
    ld a,d
    adc a,b
    ld d,a
    pop bc                      ; this second, for next time
    ld (t_lastS),bc
    pop bc
    ld (t_lastS+2),bc
    ld bc,(t_raw)
    ld (t_lastR),bc
    ld a,(ix+2)
    ld (t_lastR+2),a
    ld a,(ix+3)
    ld (t_lastT),a
    bit 7,d
    jr z,.add
    ld hl,0                     ; (never: none the less, not backwards)
    ld de,0
.add:
    ld bc,(t_tot)
    add hl,bc
    ex de,hl
    ld bc,(t_tot+2)
    adc hl,bc
    ex de,hl                    ; DEHL = the new total
.total:
    ld (t_tot),hl
    ld (t_tot+2),de
    ld c,15
    call mul32
    srl d
    rr e
    rr h
    rr l
    ret
.last:
    ld (t_lastS),hl
    ld (t_lastS+2),de
    ld bc,(t_raw)
    ld (t_lastR),bc
    ld a,(ix+2)
    ld (t_lastR+2),a
    ld a,(ix+3)
    ld (t_lastT),a
    ret
.m3:
    di
    ld a,(L_TIME3-1)            ; the ticks left of this second
    ld (ix+3),a
    ld hl,(L_TIME3)
    ld a,(L_TIME3+2)
    ei
    ld (ix+0),l
    ld (ix+1),h
    ld (ix+2),a
    call .secs
    ld c,100
    call mul32
    ld c,3
    call mul32                  ; the second * 300
    ld a,(ix+3)
    cp 31
    jr c,.in
    ld a,30
.in:
    or a
    jr nz,.nz
    inc a
.nz:
    ld b,a
    ld a,30
    sub b                       ; the ticks into it, 0-29
    ld b,a
    add a,a
    add a,a
    add a,b                     ; * 5, twice
    push af
    call add32a
    pop af
    jp add32a
;; .secs: t_raw (IX) -> DEHL = the second of the day
.secs:
    ld l,(ix+2)
    ld h,0
    ld de,0
    ld c,60
    call mul32
    ld a,(ix+1)
    call add32a
    ld c,60
    call mul32
    ld a,(ix+0)
    jp add32a
t_raw:      db 0,0,0,0          ; seconds, minutes, hours as read; the ticks
t_init:     db 0                ; 1 once the Model I's count has begun
t_lastS:    dw 0,0              ;   the second of the day at the last call,
t_lastT:    db 0                ;   the ticks then,
t_lastR:    db 0,0,0            ;   and the clock as read
t_tot:      dw 0,0              ;   the ticks so far
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

FILL_STK    equ #E000           ; flood-fill's stack: 2048 blocks, in the page
FILL_END    equ #F000           ;   past its code (not in the image)
page_end:
    print "machine page: ",page_end-#C000," bytes"
    assert page_end <= FILL_STK
    defs #10000-$,#FF
