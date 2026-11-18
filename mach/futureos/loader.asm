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
;; desktop. MC START PROGRAM's body is at &060E in the 464's lower ROM,
;; &061F in the 6128's (also a 464 with the 1.1 firmware) and &0609 in
;; the 664's, entered the same way (DE, the routine to call): the bytes
;; are checked at each.

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
    ld ix,fw_tab                ; which firmware: its MC START PROGRAM body
    ld c,(fw_tab_end-fw_tab)/2
.try:
    ld e,(ix+0)
    ld d,(ix+1)
    ld hl,fw_body
    ld b,fw_body_end-fw_body
.chk:
    ld a,(de)
    cp (hl)
    jr nz,.next
    inc hl
    inc de
    djnz .chk
    ld l,(ix+0)                 ; found: the jump below goes there
    ld h,(ix+1)
    ld (fw_go+1),hl
    jr .found
.next:
    inc ix
    inc ix
    dec c
    jr nz,.try
    jp fos_fail                 ; none of them
.found:
    ld hl,crtc_fw               ; the firmware's screen geometry: FutureOS's
    ld e,crtc_fw_end-crtc_fw    ;   is 64 bytes by 256 lines, and the firmware
.crtc:                          ;   sets only R12 and R13 (fosback.asm puts
    ld b,#BC                    ;   FutureOS's back)
    ld c,(hl)
    out (c),c                   ; the register
    inc hl
    ld b,#BD
    ld c,(hl)
    out (c),c                   ; its value
    inc hl
    dec e
    dec e
    jr nz,.crtc
    ld de,fos_island            ; called once the firmware is up
    ld hl,0
    ld c,0
fw_go:
    jp #060E                    ; (patched above)
fw_tab:
    dw #060E                    ; 464
    dw #061F                    ; 6128, or a 464 with the 1.1 firmware
    dw #0609                    ; 664
fw_tab_end:
fw_body:
    db #F3,#ED,#56,#D9,#01,#00,#DF  ; di : im 1 : exx : ld bc,&DF00
fw_body_end:
crtc_fw:
    db 1,#28, 2,#2E, 6,#19, 7,#1E   ; R1, R2, R6, R7 as the firmware's
crtc_fw_end:                        ;   reset sets them

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
