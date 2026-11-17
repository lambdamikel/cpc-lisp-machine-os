;; CPC Lisp under FutureOS -- LISP.64K, the program FutureOS's desktop
;; starts (RUN).
;;
;; LISP.64K is loaded at &8000 and started at &9000 (FutureOS reads both
;; from its AMSDOS header). FutureOS keeps its variables, tables and stack at &A000-&BFFF; the
;; firmware wants the same RAM. So this puts FutureOS's RAM aside in bank
;; 7's block 3 (fosback.asm puts it back), then starts the firmware as the
;; 464 starts a program -- MC START PROGRAM's body in its lower ROM, &060E:
;; the firmware's RAM cleared, every pack initialised, IM 1, EI, then DE
;; called; no ROM walk and no BASIC -- and then the 512K CPC's loader
;; (loader512.asm, a link), which walks the ROMs (the disc's: AMSDOS,
;; Parados, VDOS), loads the six images and starts Lisp, as RUN"LISP does.
;; Lisp is then the 512K CPC's; (quit), (reset), (basic) go back to the
;; desktop. A 464's firmware only, so far (checked: the bytes at &060E).

    include "fos.asm"
    include "loader512.asm"     ; at &8000-&87FF, its buffer &8800-&8FFF

    org #9000                   ; (FutureOS never touches &9000-&9FFF; the
fos_start:                      ;   stub must stay out of &4000-&7FFF)
    di
    ld bc,(FOS_ROMNUM_D)        ; a FutureOS ROM is in when a program starts
    push bc
    ld bc,(FOS_ROMNUM_B)
    push bc
    ld bc,#7F00+FOS_SAVE_CFG    ; bank 7's block 3 at &4000
    out (c),c
    ld hl,#A000                 ; FutureOS's variables, tables, stack
    ld de,#4000
    ld bc,#2000
    ldir
    ld hl,#0000                 ; its restarts
    ld de,#6000
    ld bc,#0100
    ldir
    ld hl,fos_back              ; the way back, beside it
    ld de,FOS_SAVE_BACK
    ld bc,fos_back_end-fos_back
    ldir
    pop hl
    ld (FOS_SAVE_ROMB),hl       ; and ROMs B and D
    pop hl
    ld (FOS_SAVE_ROMD),hl
    ld bc,#7F89                 ; the main RAM, then mode 1 with the lower
    ld a,#C0                    ;   ROM in
    out (c),a
    out (c),c
    ld hl,fw464                 ; a 464's firmware?
    ld de,#060E
    ld b,fw464_end-fw464
.chk:
    ld a,(de)
    cp (hl)
    jr nz,fos_fail
    inc hl
    inc de
    djnz .chk
    ld de,fos_island            ; called once the firmware is up
    ld hl,0
    ld c,0
    jp #060E
fw464:
    db #F3,#ED,#56,#D9,#01,#00,#DF  ; di : im 1 : exx : ld bc,&DF00
fw464_end:

fos_island:
    call start                  ; the 512K loader: back only if it failed
    call #BB06                  ; KM WAIT CHAR: its message is read
fos_fail:
    di
    ld hl,fos_back
    ld de,#8000
    ld bc,fos_back_end-fos_back
    ldir
    jp #8000

    include "fosback.asm"
