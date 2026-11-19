;; CPC Lisp -- the 512K CPC's resident part: what must be there whatever is
;; at &C000. Loaded at RESIDENT by LISP.BIN (loader.asm), in the main RAM,
;; and there for good.
;;
;; The Lisp's six images are in the expansion, each in block 3 of a 64K bank
;; (banks 0-5), and the one running is at &C000 in configuration C1: &7F
;; with #C1 + 8 * bank (the DK'tronics/Amstrad scheme; Revaldinho's cards in
;; their 464 mode, the 6128's own banking for bank 0). The main RAM's
;; &C000-&FFFF is the screen, which the CRTC always shows -- but the CPU
;; sees it only in configuration C0. So everything that writes or reads the
;; screen runs here, with C0 for the length of it, and puts the Lisp's bank
;; back after: each firmware routine the Lisp calls (a trampoline, "call
;; fwc : dw address", fwtab.inc), the function editor's renderer
;; (frcode.asm), and the screen bytes of peek, poke and flood-fill.
;;
;;   RESIDENT+0   SYS_BANK: C = a bank -> C = the one before (AF, B lost):
;;                configuration BANK_CFGS[bank] (memmap.asm)
;;   RESIDENT+3   SYS_CURBANK: -> A = the bank at &C000
;;   RESIDENT+6   RS_RAMRD: HL -> A = (HL) in the main RAM. All else kept.
;;   RESIDENT+9   RS_RAMWR: HL, A -> (HL) = A in the main RAM. All kept.
;;   RESIDENT+12  RS_RESET: the main RAM in, RST 0: the CPC starts again
;;                (under FutureOS, mach/futureos: back to its desktop)
;;   RESIDENT+15  VID_INIT, RESIDENT+18 VID_CHAR (frcode.asm)
;;   RESIDENT+21  RS_XFER: A = #C4-#C7 + 8 * bank, carry if HL is its
;;                side: BC bytes from HL to DE, between that block at &4000
;;                and the main RAM -- the RAM disc's copying
;;   RESIDENT+24  FILE_GETC, FILE_PUTC, the closes and abandons: the RAM
;;                disc's (its code in the library, called in its bank)
;;                for a file on M:, the firmware's for any other
;;   RESIDENT+42  the trampolines, 5 bytes each
;;
;; Nothing here is reentrant, nor needs to be: the Lisp registers no
;; firmware events, so no Lisp code runs at interrupt time.

    include "jumps.asm"
    include "fwreal.asm"
    include "memmap.asm"

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
    assert $ == FWJB
    include "fwtab.inc"

rs_cur:     db 0                ; the Lisp's bank at &C000,
rs_cfg:     db #C1              ;   and its configuration (C1 + 8 * bank)

;; fwc: from a trampoline -- the routine's address after the call -- with
;; every register as the caller left it; back to the caller with every
;; register as the routine left it. fwx: the same with the disc files'
;; buffers mapped in at &4000 for the call (configuration RD_XBCFG, which
;; the loader sets), for the disc ROM's routines that use them -- so a file
;; open on a disc takes no string space (the main RAM's &4000-&7FFF is
;; not needed meanwhile: the name is in TOKBUF, the stack above &8000).
    ifdef XBUF
fwx:
    push af
    ld a,(RD_XBCFG)
    jr fw_go
fwc:
    push af
    ld a,#C0
fw_go:
    ld (fw_cfg+1),a
    pop af
    else
fwc:
fwx:
    endif
    ex (sp),hl                  ; HL -> the address; the caller's HL on top
    push af
    ld a,(hl)
    ld (fw_call+1),a
    inc hl
    ld a,(hl)
    ld (fw_call+2),a
    pop af
    pop hl                      ; (the caller's return on top again)
    ifdef XBUF
    push bc
fw_cfg:
    ld bc,#7FC0                 ; (C0 or RD_XBCFG)
    out (c),c
    pop bc
    else
    call to_main
    endif
fw_call:
    call 0
    jp to_lisp

;; to_main: configuration C0, the main RAM at &C000. All kept.
to_main:
    push bc
    ld bc,#7FC0
    out (c),c
    pop bc
    ret
;; to_lisp: the Lisp's bank at &C000 again. All kept.
to_lisp:
    push bc
    push af
    ld a,(rs_cfg)
    ld b,#7F
    ld c,a
    out (c),c
    pop af
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
    ld b,#7F
    ld c,a
    out (c),c
    pop bc
    ld c,b
    ret
rs_cfgs:    BANK_CFGS           ; (memmap.asm)
;; SYS_CURBANK
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
r_reset:
    call to_main
    ifdef FUTUREOS
    di                          ; back to FutureOS's desktop: the way back
    ld bc,#7F00+FOS_SAVE_CFG    ;   (fosback.asm), kept beside FutureOS's
    out (c),c                   ;   RAM, overwrites this part: it runs from
    ld hl,FOS_SAVE_BACK         ;   &8000 (the cells: no longer needed)
    ld de,#8000
    ld bc,FOS_BACK_LEN
    ldir
    jp #8000
    else
    rst 0
    endif

    ifdef XBUF
;; CAS IN OPEN, CAS OUT OPEN and CAS CATALOG (their trampolines -- fwtab.inc)
;; with a buffer in the block RD_XBCFG maps at &4000: an input file's 2 KB,
;; an output file's, and 4 KB for the catalogue, which VDOS 2.0 fills. DE,
;; the library's buffer, is not used: the library lends none (disc.asm).
r_fiopen:
    ld de,XB_IN
    call fwx
    dw CAS_IN_OPEN
r_foopen:
    ld de,XB_OUT
    call fwx
    dw CAS_OUT_OPEN
r_catalog:
    ld de,XB_CAT
    call fwx
    dw CAS_CATALOG
    endif

r_vidinit:
    call to_main
    call VID_INIT
    jp to_lisp
r_vidchar:
    call to_main
    call VID_CHAR
    jp to_lisp

    if RAMDISC
;; RS_XFER: A = the RAM disc's configuration (a block at &4000), carry set
;; if HL is the block's side, clear if DE is; BC bytes from HL to DE. The
;; other side is the main RAM, and may be at &4000-&7FFF too (a file's
;; buffer, low in block space): so each piece goes through rx_buf, read in
;; the one configuration and written in the other. The Lisp's bank after.
r_xfer:
    ifdef FUTUREOS
    push af                     ; under FutureOS (mach/futureos) the RAM
    and #38                     ;   disc's banks 3-6 are banks 4-7: bank 3
    cp #18                      ;   is the base RAM's shadow on Revaldinho's
    jr c,.lo                    ;   card in configurations 8 and 12, which
    pop af                      ;   FutureOS needs on a 464
    push af
    add a,8
    jr .cfg
.lo:
    pop af
    push af
.cfg:
    ld (rx_src),a
    ld (rx_dst),a
    pop af                      ; (the caller's carry)
    else
    ld (rx_src),a
    ld (rx_dst),a
    endif
    ld a,(rs_cfg)
    jr c,.tomain
    ld (rx_src),a               ; from the main RAM to the block
    jr .l
.tomain:
    ld (rx_dst),a               ; from the block to the main RAM
.l:
    ld a,b
    or c
    jp z,to_lisp
    push bc                     ; what is left
    ld a,b
    or a
    jr nz,.full
    ld a,c
    cp RX_LEN
    jr c,.part
.full:
    ld bc,RX_LEN
.part:
    push de
    ld de,rx_buf
    ld a,(rx_src)
    call rx_out
    pop de
    push hl
    ld hl,rx_buf
    ld a,(rx_dst)
    call rx_out
    pop hl
    ex (sp),hl                  ; HL = what was left, the source's place kept
    or a
    sbc hl,bc
    ld b,h
    ld c,l
    pop hl
    jr .l
;; rx_out: configuration A, then BC bytes from HL to DE (HL, DE moved on)
rx_out:
    push bc
    ld b,#7F
    ld c,a
    out (c),c
    pop bc
    push bc
    ldir
    pop bc
    ret
RX_LEN      equ 128
rx_src:     db 0
rx_dst:     db 0
rx_buf:     defs RX_LEN,0

;; The file routines. FILE_IOPEN and FILE_OOPEN are the firmware's: the
;; library opens a file on M: itself (ramdisc.asm), and says so in RD_IN
;; or RD_OUT, with the buffer, the bank and its routines.
r_fgetc:
    ld a,(RD_IN)
    or a
    jr z,.fw
    push de
    push hl
    push ix
    ld ix,(RD_IBUF)
    ld hl,(RD_VGETC)
    call rd_far
    pop ix
    pop hl
    pop de
    ret
.fw:
    call fwx
    dw CAS_IN_CHAR
r_fputc:
    push af
    ld a,(RD_OUT)
    or a
    jr z,.fw
    pop af
    push de
    push hl
    push ix
    ld ix,(RD_OBUF)
    ld hl,(RD_VPUTC)
    call rd_far
    pop ix
    pop hl
    pop de
    ret
.fw:
    pop af
    call fwx
    dw CAS_OUT_CHAR
r_ficlose:
    ld a,(RD_IN)
    or a
    jr z,.fw
    xor a
    ld (RD_IN),a
    scf
    ret
.fw:
    call fwx
    dw CAS_IN_CLOSE
r_fiabandon:
    ld a,(RD_IN)
    or a
    jr z,.fw
    xor a
    ld (RD_IN),a
    scf
    ret
.fw:
    call fwx
    dw CAS_IN_ABANDON
r_foclose:
    ld a,(RD_OUT)
    or a
    jr z,.fw
    xor a
    ld (RD_OUT),a
    push de
    push hl
    push ix
    ld ix,(RD_OBUF)
    ld hl,(RD_VCLOSE)
    call rd_far                 ; its entry and the header written
    pop ix
    pop hl
    pop de
    ret
.fw:
    call fwx
    dw CAS_OUT_CLOSE
r_foabandon:
    ld a,(RD_OUT)
    or a
    jr z,.fw
    xor a
    ld (RD_OUT),a               ; forgotten: the space past the files is
    scf                         ;   free again
    ret
.fw:
    call fwx
    dw CAS_OUT_ABANDON

;; rd_far: HL = a routine of the RAM disc's, in RD_BANK; A and IX for it ->
;; its A and flags, in the caller's bank again. BC, DE kept.
rd_far:
    ld (rf_go+1),hl
    ld (rf_a),a
    push bc
    ld a,(rs_cur)
    ld (rf_bank),a
    ld a,(RD_BANK)
    ld c,a
    call r_bank
    ld a,(rf_a)
rf_go:
    call 0
    push af
    ld a,(rf_bank)
    ld c,a
    call r_bank
    pop af
    pop bc
    ret
rf_a:       db 0
rf_bank:    db 0

    else
;; no RAM disc (the plain 6128): the firmware's file routines, straight
r_xfer:
    ret
r_fgetc:
    call fwx
    dw CAS_IN_CHAR
r_fputc:
    call fwx
    dw CAS_OUT_CHAR
r_ficlose:
    call fwx
    dw CAS_IN_CLOSE
r_fiabandon:
    call fwx
    dw CAS_IN_ABANDON
r_foclose:
    call fwx
    dw CAS_OUT_CLOSE
r_foabandon:
    call fwx
    dw CAS_OUT_ABANDON
    endif

    include "frcode.asm"

res_end:
    print "resident: ",res_end-RESIDENT," bytes"
    assert res_end <= RS_RD
