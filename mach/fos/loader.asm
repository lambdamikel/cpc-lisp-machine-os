;; CPC Lisp on FutureOS itself -- LISP.64K, the program FutureOS's desktop
;; starts (RUN): loaded at &8000, started at &9000.
;;
;; While FutureOS still runs, the stub (&9000) loads the seven images --
;; the core, the library's four parts, the VM ROM and the machine page
;; (page.asm), LISP0.IMG-LISP6.IMG -- through FutureOS's LADE_N, from the
;; drive LISP.64K came from: each into the main RAM at LORAM, then copied
;; into block 3 of its bank. Then the finisher (below &9000) puts the
;; resident part in place over the stub, keeps FutureOS's restarts in the
;; page, puts ours (the interrupt), builds the maths package's jumpblock
;; from the lower ROM's table, gives the screen FutureOS's 80 by 25
;; (S80X25), lets the page set it up, and starts the core in bank 0. No
;; firmware is started: FutureOS's RAM, &A000-&BFFF, stays as it is, and
;; (reset) goes back to its desktop.

    include "jumps.asm"
    include "memmap.asm"
    include "fos.asm"
    include "resident.inc"      ; the resident part's labels (post-build.sh)
    include "nfw.asm"

NIMG        equ 7
PARK        equ #6000           ; LISP.64K's first 4 KB while the images load
S80X25      equ #D60E           ; ROM A
FOS_COLS    equ #FE0B           ; ROM B: FutureOS's border and inks 0-3

    org #8000
lr_res:
    incbin "resident.bin"
lr_res_end:

;; fin: the stub's last step, from here (it overwrites the stub)
fin:
    di
    ld hl,lr_res
    ld de,RESIDENT
    ld bc,lr_res_end-lr_res
    ldir
    ld hl,(lr_roma)
    ld (rs_roma),hl
    ld hl,(lr_romb)
    ld (rs_romb),hl
    ld hl,(lr_romc)
    ld (rs_romc),hl
    ld hl,(lr_sp)
    ld (rs_fossp),hl
    ld a,(RAMCHAR)
    ld (rs_ramchar),a
    ld hl,RS_RD                 ; the RAM disc's state: no file open
    ld b,16
.rd:
    ld (hl),0
    inc hl
    djnz .rd
    ld a,(lr_drv)               ; (after: RS_DRIVE and RS_START are RS_RD's
    ld (RS_DRIVE),a             ;   last two)
    ld (RS_START),a
    ld hl,(lr_romd)
    ld (rs_romd),hl
    ld bc,#7F00+PAGE_CFG        ; FutureOS's restarts, kept in the page
    out (c),c
    ld hl,#0000
    ld de,FOS_KEEP0
    ld bc,#0100
    ldir
    ld hl,XRAM_C4               ; and its XRAM marks
    ld de,FOS_KEEPX
    ld bc,32
    ldir
    ld bc,#7FC0
    out (c),c
    ld hl,lr_mine               ; ours marked in use by a program (&11):
.mk:                            ;   FutureOS's FESB makes every free block a
    ld a,(hl)                   ;   short-time buffer, which TEISI uses
    inc hl
    cp #FF
    jr z,.mkd
    add a,XRAM_C4 and #FF
    ld e,a
    ld d,XRAM_C4 >> 8
    ld a,#11
    ld (de),a
    jr .mk
.mkd:
    ld hl,lr_units              ; the RAM disc, M:: those of its blocks
    ld de,rs_units              ;   FutureOS has free (or as short-time
    ld c,0                      ;   buffers), in order, marked in use too
.un:
    ld a,(hl)
    inc hl
    cp #FF
    jr z,.und
    push hl
    ld b,a
    add a,XRAM_C4 and #FF
    ld l,a
    ld h,XRAM_C4 >> 8
    ld a,(hl)
    and #F7
    cp 1
    jr nz,.unx
    ld (hl),#11
    ld a,b                      ; its configuration: &C4 + 8 x bank + block
    and #1C
    add a,a
    ld l,a
    ld a,b
    and 3
    or l
    or #C4
    ld (de),a
    inc de
    inc c
.unx:
    pop hl
    jr .un
.und:
    ld a,c
    ld (RD_NBANKS),a            ; (its units, for ramdisc.asm's rd_ready)
    ld hl,#0000                 ; ours: RETs, &0000 the way back, &0038
    ld (hl),#C9                 ;   the interrupt
    ld de,#0001
    ld bc,#003F
    ldir
    ld a,#C3
    ld (#0000),a
    ld hl,RS_RESET
    ld (#0001),hl
    ld (#0038),a
    ld hl,r_int
    ld (#0039),hl
    im 1
    call fm_build
    ld bc,(lr_roma)             ; the screen: FutureOS's 80 by 25
    out (c),c
    ld bc,#7F86                 ; (mode 2, the upper ROM in)
    out (c),c
    call S80X25
    ld bc,(lr_romb)             ; FutureOS's colours: its border, inks 0
    out (c),c                   ;   and 1, for the page (p_init: Lisp's
    ld hl,FOS_COLS              ;   text in them)
    ld de,lr_cols
    ld bc,3
    ldir
    ld a,#8E                    ; both ROMs out from now on
    ld (rs_rom),a
    ld b,#7F
    out (c),a
    ld a,PAGE_CFG               ; the page sets the screen up
    ld (rs_now),a
    ld b,#7F
    ld c,a
    out (c),c
    ld hl,lr_cols
    call #C000+3*NFW            ; (p_init)
    xor a                       ; the core, bank 0
    ld (rs_cur),a
    ld a,#C1
    ld (rs_cfg),a
    ld (rs_now),a
    ld bc,#7FC1
    out (c),c
    ei
    jp #C006

;; fm_build: FM_JB from the lower ROM's jumpblock table -- found by the code
;; that copies it to &BB00 (464: "ld de,table : ld hl,&BB00 : ld bc,&BFCF";
;; 664/6128: "ld hl,table : ld de,&BB00 : ld bc,&CBCF": the table, then
;; B entries before the maths routines'). Each entry "jp address"; those not
;; found, "jp fm_fail".
fm_build:
    ld hl,FM_JB
    ld b,48
    ld de,fm_fail
.f:
    ld (hl),#C3
    inc hl
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    djnz .f
    ld bc,#7F8A                 ; the lower ROM in (mode 2, upper out)
    out (c),c
    ld hl,#0800
.s:
    ld a,(hl)                   ; "00 BB 01 CF n"
    or a
    jr nz,.n
    push hl
    inc hl
    ld a,(hl)
    cp #BB
    jr nz,.no
    inc hl
    ld a,(hl)
    cp #01
    jr nz,.no
    inc hl
    ld a,(hl)
    cp #CF
    jr nz,.no
    inc hl
    ld c,(hl)                   ; the entries before the maths'
    pop hl
    dec hl
    dec hl
    ld d,(hl)
    dec hl
    ld e,(hl)                   ; the table
    ex de,hl
    ld b,0
    add hl,bc
    add hl,bc
    ld de,FM_JB+1
    ld b,32                     ; (the 464 has 48, the 664/6128 32)
.c:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    inc de
    djnz .c
    jr .done
.no:
    pop hl
.n:
    inc hl
    ld a,h
    cp #0A
    jr c,.s
.done:
    ld bc,#7F8E
    out (c),c
    ret

;; the blocks Lisp keeps, as XRAM indices (4 x bank + block): the images
;; (block 3 of banks 0-2, 4-6), the page (bank 7's 3), the buffers' block
;; (7's 1), the input file's (6's 0-2), the low RAM's keeping (7's 0); not
;; the output file's (0's 0-2: TEISI writes from there)
lr_mine:    db 3,7,11,19,23,27,31,29,24,25,26,28,#FF
;; the RAM disc's: blocks 0-2 of banks 1, 2, 4 and 5 (bank 3 is the base
;; RAM's shadow on Revaldinho's card in configuration 8), where free
lr_units:   db 4,5,6,8,9,10,16,17,18,20,21,22,#FF
    assert XRAM_C4+31 < (XRAM_C4 and #FF00)+256
lr_roma:    dw 0
lr_romb:    dw 0
lr_romc:    dw 0
lr_romd:    dw 0
lr_drv:     db 0
lr_sp:      dw 0
lr_cols:    defs 3,0            ; FutureOS's border, inks 0 and 1
    assert $ <= #8F00

    org #9000
fos_start:
    ld (lr_sp),sp               ; FutureOS's stack, for its functions later
    ld hl,(FOS_ROMNUM_A)        ; FutureOS's ROMs, from its API page
    ld (lr_roma),hl
    ld hl,(FOS_ROMNUM_B)
    ld (lr_romb),hl
    ld hl,(FOS_ROMNUM_C)
    ld (lr_romc),hl
    ld hl,(FOS_ROMNUM_D)
    ld (lr_romd),hl
    ld a,(REG_PC+1)             ; the drive LISP.64K came from
    ld (lr_drive),a
    ld (lr_drv),a
    ld hl,#8000                 ; the resident part and the finisher out of
    ld de,PARK                  ;   the way: a load may write past the
    ld bc,#1000                 ;   file's end, a sector at a time
    ldir
    xor a
.img:
    ld (lr_k),a
    add a,"0"
    ld (lr_name+5),a
    ld a,2                      ; into the main RAM (the header off)
    ld (REG08_4),a
    ld hl,LORAM
    ld (REG16_3),hl
    ld a,(lr_drive)
    or #80                      ; the header's addresses not used
    ld de,lr_name
    ld hl,LADE_N
    call ROM_C
    inc a                       ; &FF: loaded
    jr nz,lr_fail
    ld a,(lr_k)                 ; into its bank's block 3, at &C000
    ld hl,lr_cfgs
    add a,l
    ld l,a
    adc a,h
    sub l
    ld h,a
    ld c,(hl)
    ld b,#7F
    ld a,i                      ; (P/V: the interrupts were on)
    push af
    di
    out (c),c
    ld hl,LORAM
    ld de,#C000
    ld bc,#4000
    ldir
    ld bc,#7FC0
    out (c),c
    pop af
    jp po,.di
    ei
.di:
    ld a,(lr_k)
    inc a
    cp NIMG
    jr c,.img
    ld bc,#FA7E                 ; the drive motors off
    xor a
    out (c),a
    ld hl,PARK
    ld de,#8000
    ld bc,#1000
    ldir
    jp fin

;; lr_fail: an image not there -- said on the desktop's lower half, which
;; stays (KLICK) after a few seconds
lr_fail:
    ld bc,#FA7E
    xor a
    out (c),a
    ld a,(lr_k)
    add a,"0"
    ld (lr_mk),a
    ld bc,(FOS_ROMNUM_A)
    out (c),c
    ld bc,#7F82                 ; mode 2, both ROMs in (the font)
    out (c),c
    ld (RAMCHAR),bc
    ld hl,lr_msg
    call TERM_2
    ld d,40                     ; some four seconds
.w1:
    ld bc,0
.w2:
    dec bc
    ld a,b
    or c
    jr nz,.w2
    dec d
    jr nz,.w1
    ld hl,KLICK
    jp ROM_D

lr_cfgs:    db #C1,#C9,#D1,#E1,#E9,#F1,#F9  ; (memmap.asm's BANK_CFGS)
lr_k:       db 0
lr_drive:   db 0
lr_name:    db 0,"LISP0   IMG"  ; user, name, extension: in one page
    assert (lr_name and #FF) <= #F4
lr_msg:     db #1E,30,2,"CPC Lisp: cannot load LISP"
lr_mk:      db "0.IMG from the drive LISP.64K came from.",0
    assert $ <= RESIDENT_END
