;; CPC Lisp on FutureOS itself -- the resident part: what must be there
;; whatever is at &C000. LISP.64K (loader.asm) puts it at RESIDENT, below
;; FutureOS's &A000-&BFFF, and it stays there.
;;
;; There is no firmware: FutureOS stays, with its RAM, and Lisp runs beside
;; it. The CPC firmware's routines that Lisp calls -- by their names,
;; machine.asm -- are a trampoline each here (fwtab.inc, made by
;; tools/fos/mkfw.py), into the machine page (page.asm): a 16 KB image of
;; our own, in bank 7's block 3, mapped at &C000 for the call (PAGE_CFG).
;; What the page cannot do from there is here, in the main RAM: anything
;; that writes the screen (the screen's RAM is at &C000 only in
;; configuration C0), the interrupts and the keyboard's matrix, the ROM
;; switches, and the way back to FutureOS.
;;
;; The interrupts are ours while Lisp runs (IM 1, &0038 jumps to r_int):
;; a 300 Hz tick, and every sixth the keyboard, into kb_mat and the keys'
;; queue, which the page's KM routines read.
;;
;; The configuration in now is kept in rs_now: a call into the page
;; (fwp) and the screen's routines put back the one they found.

    include "firmware.asm"      ; the names (and jumps.asm)
    include "memmap.asm"
    include "fos.asm"

C_POS       equ #B848           ; FutureOS: PR_2's cursor (ROM A &C9BD;
                                ;   PR_2, fos.asm: glyph from &3800)
PR_2I       equ #D064           ;   ... inverted
S80X25      equ #D60E           ; ROM A: the CRTC as the firmware's (80 x 25)
S64X32      equ #D5A8           ; ROM A: FutureOS's own (64 x 32)
FOS_COLS    equ #FE0B           ; ROM B: FutureOS's border and inks 0-3
KB_DELAY    equ 30              ; key repeat: after 30 scans (0.6 s),
KB_RATE     equ 2               ;   then every 2 (as the firmware's)

    org RESIDENT
    jp r_bank
    jp r_curbank
    jp r_ramrd
    jp r_ramwr
    jp r_reset
    jp r_vidinit
    jp r_vidchar
    jp r_xfer
    jp r_fgetc
    jp r_fputc
    jp r_ficlose
    jp r_fiabandon
    jp r_foclose
    jp r_foabandon
    jp r_fm
    assert $ == FWJB
    include "fwtab.inc"

;; the state, set by LISP.64K's finisher (loader.asm)
rs_cur:     db 0                ; the Lisp's bank at &C000,
rs_cfg:     db #C1              ;   its configuration (C1 + 8 * bank),
rs_now:     db #C1              ;   and the configuration in now
rs_rom:     db #8E              ; the gate array's mode and ROM byte now:
                                ;   &8C + mode, both ROMs off
rs_roma:    dw 0                ; FutureOS's ROMs A, B, D: number, &DF
rs_romb:    dw 0
rs_romd:    dw 0
ticks:      dw 0,0              ; 1/300 s since the start
kb_div:     db 6                ; interrupts to the next keyboard scan
kb_mat:     defs 10,#FF         ; the matrix, a byte a row, 0 = down
kb_new:     defs 10,#FF
kb_last:    db #FF              ; the key that repeats, or &FF
kb_rep:     db 0                ; scans to its next repeat
kb_put:     db 0                ; the queue: kb_buf, 16 keys of two bytes
kb_get:     db 0                ;   (the key's number; bit 0 SHIFT, 1 CTRL)
kb_buf:     defs 32,0

;; fwp: from a trampoline ("call fwp : dw address") with every register
;; as the caller left it: the machine page in at &C000, the routine called,
;; the configuration that was in put back, every register as the routine
;; left it. (fp_call is written each time: the page's routines call each
;; other directly, never through here.)
fwp:
    ex (sp),hl                  ; HL -> the address; the caller's HL on top
    push af
    ld a,(hl)
    ld (fp_call+1),a
    inc hl
    ld a,(hl)
    ld (fp_call+2),a
    ld a,(rs_now)
    ld h,a                      ; H: the configuration to come back to
    pop af
    ex (sp),hl                  ; it on the stack, the caller's HL back
    call to_page
fp_call:
    call 0
    ex (sp),hl                  ; H = that configuration; the routine's HL
    push af                     ;   on the stack
    push bc
    ld a,h
    call set_cfg
    pop bc
    pop af
    pop hl
    ret

;; to_page, to_main, to_lisp: the machine page, the screen's RAM (C0), the
;; Lisp's bank at &C000. All registers kept.
to_page:
    push af
    push bc
    ld a,PAGE_CFG
    jr to_cfg
to_main:
    push af
    push bc
    ld a,#C0
    jr to_cfg
to_lisp:
    push af
    push bc
    ld a,(rs_cfg)
to_cfg:
    call set_cfg
    pop bc
    pop af
    ret
;; set_cfg: configuration A, and rs_now. B, C lost.
set_cfg:
    ld (rs_now),a
    ld b,#7F
    ld c,a
    out (c),c
    ret
;; rom_set: A = the gate array's mode and ROM byte (&8x), and rs_rom. All
;; else kept.
rom_set:
    push bc
    ld (rs_rom),a
    ld b,#7F
    out (c),a
    pop bc
    ret

;; SYS_BANK: C = a bank -> it at &C000, C = the one before. AF, B lost.
r_bank:
    ld a,(rs_cur)
    ld b,a
    ld a,c
    and 7
    ld (rs_cur),a
    push hl
    ld hl,rs_cfgs
    add a,l
    ld l,a
    adc a,h
    sub l
    ld h,a
    ld a,(hl)                   ; its configuration
    pop hl
    ld (rs_cfg),a
    push bc
    call set_cfg
    pop bc
    ld c,b
    ret
rs_cfgs:    BANK_CFGS           ; (memmap.asm)
r_curbank:
    ld a,(rs_cur)
    ret

r_ramrd:
    call to_main
    ld a,(hl)
    jp to_lisp
r_ramwr:
    call to_main
    ld (hl),a
    jp to_lisp

;; KL L ROM ENABLE: the lower ROM in (its font at &3800), the interrupts
;; off meanwhile -- its &0038 is the firmware's, not ours -> A = the ROM
;; state before. KL ROM RESTORE: A = such a state; the interrupts on again
;; once the lower ROM is out.
r_lromon:
    di
    ld a,(rs_rom)
    push af
    and #FB
    call rom_set
    pop af
    ret
r_romrest:
    call rom_set
    and 4
    ret z
    ei
    ret
r_romsel:                       ; (KL ROM SELECT, KL CURR SELECTION: not
r_romcur:                       ;   used here)
    ret

;; KL TIME PLEASE: -> DEHL = the time in 1/300 s.
r_time:
    di
    ld hl,(ticks)
    ld de,(ticks+2)
    ei
    ret
;; MC WAIT FLYBACK: until the frame flyback (PPI port B, bit 0). All kept
;; but the flags.
r_flyback:
    push af
    push bc
    ld b,#F5
.w:
    in a,(c)
    rra
    jr nc,.w
    pop bc
    pop af
    ret
;; KM TEST KEY: A = a key number -> NZ if it is down (kb_mat). A lost; all
;; else kept.
r_testkey:
    push hl
    push bc
    ld c,a
    srl a
    srl a
    srl a
    ld hl,kb_mat
    add a,l
    ld l,a
    adc a,h
    sub l
    ld h,a
    ld a,c
    and 7
    inc a
    ld b,a
    xor a
    scf
.m:
    rla
    djnz .m
    ld c,a
    ld a,(hl)
    cpl
    and c
    pop bc
    pop hl
    ret

;; r_int: the interrupt, 300 times a second (&0038: jp r_int). The tick;
;; every sixth, the keyboard.
r_int:
    push af
    push hl
    ld hl,ticks
    inc (hl)
    jr nz,.t
    inc hl
    inc (hl)
    jr nz,.t
    inc hl
    inc (hl)
    jr nz,.t
    inc hl
    inc (hl)
.t:
    ld hl,kb_div
    dec (hl)
    jr nz,.out
    ld (hl),6
    push bc
    push de
    call kb_scan
    pop de
    pop bc
.out:
    pop hl
    pop af
    ei
    ret

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

;; r_glyph: for the page -- A = a character, HL = its cell on the top pixel
;; line (&C000-&C7FF), B = 0 normal, 1 inverted: drawn in mode 2 by
;; FutureOS's PR_2 (or PR_2I), its glyph from the lower ROM's font at
;; &3800 -- FutureOS's character output. All kept; the page in again.
r_glyph:
    push af
    push bc
    push de
    push hl
    di
    call to_main
    dec hl
    ld (C_POS),hl               ; PR_2 moves it on by one first
    ld l,a
    ld de,PR_2
    dec b
    jr nz,.n
    ld de,PR_2I
.n:
    ld (.call+1),de
    ld bc,(rs_roma)
    out (c),c                   ; FutureOS's ROM A
    ld a,(rs_rom)
    push af
    and #F3                     ; the upper and the lower ROM in
    call rom_set
.call:
    call 0
    pop af
    call rom_set                ; both out again
    call to_page
    ei
    pop hl
    pop de
    pop bc
    pop af
    ret

;; r_rowfill: for the page -- HL = an address on a character row's top
;; pixel line (&C000-&C7FF), B = bytes (1-80), A = a byte: the row's eight
;; pixel lines filled there, each wrapping in its 2 KB. All kept.
r_rowfill:
    push af
    push bc
    push de
    push hl
    call to_main
    ld c,a
    ld e,8
.line:
    push hl
    push bc
.b:
    ld (hl),c
    inc l
    jr nz,.n
    inc h
    ld a,h
    and 7
    jr nz,.n
    ld a,h
    sub 8
    ld h,a
.n:
    djnz .b
    pop bc
    pop hl
    ld a,h
    add a,8
    ld h,a
    dec e
    jr nz,.line
    call to_page
    pop hl
    pop de
    pop bc
    pop af
    ret

;; r_rowcopy: for the page -- HL, DE = addresses on two character rows' top
;; pixel lines (&C000-&C7FF), B = bytes (1-80): each of the eight pixel
;; lines copied from HL's row to DE's, wrapping in its 2 KB. All kept.
r_rowcopy:
    push af
    push bc
    push de
    push hl
    call to_main
    ld c,8
.line:
    push hl
    push de
    push bc
.b:
    ld a,(hl)
    ld (de),a
    inc l
    jr nz,.s
    inc h
    ld a,h
    and 7
    jr nz,.s
    ld a,h
    sub 8
    ld h,a
.s:
    inc e
    jr nz,.d
    inc d
    ld a,d
    and 7
    jr nz,.d
    ld a,d
    sub 8
    ld d,a
.d:
    djnz .b
    pop bc
    pop de
    pop hl
    ld a,h
    add a,8
    ld h,a
    ld a,d
    add a,8
    ld d,a
    dec c
    jr nz,.line
    call to_page
    pop hl
    pop de
    pop bc
    pop af
    ret

;; r_romfont: for the page -- A = a character, DE = 8 bytes in the main
;; RAM: its glyph from the lower ROM's font. All kept but AF.
r_romfont:
    push bc
    push de
    push hl
    ld l,a
    ld h,#07
    add hl,hl
    add hl,hl
    add hl,hl                   ; &3800 + 8 * the character
    call r_lromon
    ld bc,8
    ldir
    call r_romrest
    pop hl
    pop de
    pop bc
    ret

;; The way back to FutureOS's desktop (SYS_RESET, (reset)): FutureOS's
;; restarts back from the page (where LISP.64K kept them), its screen --
;; 64 by 32 (S64X32, ROM A), at &C000, its colours (ROM B's table) --
;; mode 2 with the upper ROM in, IM 2 with I = &BD, and TUR_D, which draws
;; the desktop afresh.
r_reset:
    di
    call to_page
    ld hl,FOS_KEEP0
    ld de,#0000
    ld bc,#0100
    ldir
    call to_main
    ld a,#86                    ; mode 2, the upper ROM in, the lower out
    call rom_set
    ld bc,(rs_roma)
    out (c),c
    call S64X32
    ld bc,#BC0C                 ; the screen at &C000, unscrolled
    out (c),c
    ld bc,#BD30
    out (c),c
    ld bc,#BC0D
    out (c),c
    ld bc,#BD00
    out (c),c
    ld bc,(rs_romb)
    out (c),c
    ld hl,FOS_COLS              ; border, inks 0-3 (hardware values)
    ld bc,#7F10
    out (c),c
    ld a,(hl)
    out (c),a
    ld c,0
.ink:
    inc hl
    out (c),c
    ld a,(hl)
    out (c),a
    inc c
    bit 2,c
    jr z,.ink
    ld bc,(rs_romd)
    out (c),c                   ; ROM D at &C000
    im 2
    ld a,#BD
    ld i,a
    ld sp,#C000
    jp TUR_D

;; RS_FM: IX = a routine's entry in FM_JB (fp.asm); A, BC, DE, HL for it
;; -> what it leaves in them, and its flags. The lower ROM in, the
;; interrupts off; the RAM the maths package keeps its state in -- the
;; 464's at &B8D0-&B8F7, the 664/6128's at &B100-&B117, FutureOS's
;; variables and disc buffers now -- swapped with its own copy (fm_s1,
;; fm_s2) for the call: the angle's unit, set once, stays.
r_fm:
    di
    push af
    push bc
    push de
    push hl
    call fm_x
    ld a,(rs_rom)
    and #FB
    call rom_set
    pop hl
    pop de
    pop bc
    pop af
    call jp_ix
    push af
    push bc
    push de
    push hl
    ld a,(rs_rom)
    or 4
    call rom_set
    call fm_x
    pop hl
    pop de
    pop bc
    pop af
    ei
    ret
jp_ix:
    jp (ix)
fm_x:
    ld hl,#B8D0
    ld de,fm_s1
    ld b,40
    call .x
    ld hl,#B100
    ld de,fm_s2
    ld b,24
.x:
    ld a,(de)
    ld c,(hl)
    ld (hl),a
    ld a,c
    ld (de),a
    inc hl
    inc de
    djnz .x
    ret
fm_s1:      defs 40,0
fm_s2:      defs 24,0
fm_fail:                        ; (an FM_JB entry the lower ROM had none for)
    or a
    ret

;; The function editor's renderer (frcode.asm): with the screen's RAM in.
r_vidinit:
    call to_main
    call VID_INIT
    jp to_lisp
r_vidchar:
    call to_main
    call VID_CHAR
    jp to_lisp

;; No RAM disc yet: the files are the machine page's (CAS routines).
r_xfer:
    ret
r_fgetc:
    jp CAS_IN_CHAR
r_fputc:
    jp CAS_OUT_CHAR
r_ficlose:
    jp CAS_IN_CLOSE
r_fiabandon:
    jp CAS_IN_ABANDON
r_foclose:
    jp CAS_OUT_CLOSE
r_foabandon:
    jp CAS_OUT_ABANDON

    include "frcode.asm"

res_end:
    print "resident: ",res_end-RESIDENT," bytes"
    assert res_end <= FM_JB
