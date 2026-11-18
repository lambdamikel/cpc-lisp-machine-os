;; CPC Lisp under FutureOS -- the way back to FutureOS's desktop.
;;
;; Kept by LISP.64K in bank 7's block 3 (FOS_SAVE_BACK, variant.asm),
;; beside FutureOS's RAM; the resident part's reset copies it to &8000
;; and runs it there (it overwrites &A000-&BFFF, where the resident part
;; is): FutureOS's RAM -- &A000-&BFFF and &0000-&00FF -- back over the
;; firmware's; the
;; main RAM, ROM D, IM 2 with FutureOS's table (I = &BD), and TUR_D, which
;; draws the desktop afresh. No jumps inside, no stack until TUR_D's.

fos_back:
    di
    ld bc,#7F00+FOS_SAVE_CFG
    out (c),c
    ld hl,#4000
    ld de,#A000
    ld bc,#2000
    ldir
    ld hl,#6000
    ld de,#0000
    ld bc,#0100
    ldir
    ld de,(FOS_SAVE_ROMD)
    ld hl,(FOS_SAVE_ROMB)
    ld bc,#7FC0                 ; the main RAM
    out (c),c
    ld bc,#7F86                 ; mode 2, the upper ROM in, the lower out,
    out (c),c                   ;   as FutureOS has them
    ld b,h
    ld c,l
    out (c),c                   ; ROM B: FutureOS's colours at &FE0B
    ld hl,#FE0B                 ;   (border, inks 0-3, the gate array's
    ld bc,#7F10                 ;   values), which TUR_D does not set
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
    ld bc,#BC01                 ; FutureOS's screen, 64 bytes by 256 lines:
    out (c),c                   ;   R1, R2, R6, R7 as its ROMs set them (the
    ld bc,#BD20                 ;   firmware's are 80 by 200: LISP.64K sets
    out (c),c                   ;   those; the CRTC's registers cannot be
    ld bc,#BC02                 ;   read back, and MC START PROGRAM sets only
    out (c),c                   ;   R12 and R13)
    ld bc,#BD2A
    out (c),c
    ld bc,#BC06
    out (c),c
    ld bc,#BD20
    out (c),c
    ld bc,#BC07
    out (c),c
    ld bc,#BD22
    out (c),c
    ld bc,#BC0C                 ; the screen at &C000 again, unscrolled
    out (c),c
    ld bc,#BD30
    out (c),c
    ld bc,#BC0D
    out (c),c
    ld bc,#BD00
    out (c),c
    ld b,d
    ld c,e
    out (c),c                   ; ROM D at &C000
    im 2
    ld a,#BD
    ld i,a
    ld sp,#C000
    jp #FEA0                    ; TUR_D (fos.asm)
fos_back_end:
    assert fos_back_end-fos_back <= FOS_BACK_LEN    ; (the reset copies that)
