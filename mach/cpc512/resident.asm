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
;;   RESIDENT+0   SYS_BANK: C = a bank -> C = the one before (AF, B lost)
;;   RESIDENT+3   SYS_CURBANK: -> A = the bank at &C000
;;   RESIDENT+6   RS_RAMRD: HL -> A = (HL) in the main RAM. All else kept.
;;   RESIDENT+9   RS_RAMWR: HL, A -> (HL) = A in the main RAM. All kept.
;;   RESIDENT+12  RS_RESET: the main RAM in, RST 0: the CPC starts again
;;   RESIDENT+15  VID_INIT, RESIDENT+18 VID_CHAR (frcode.asm)
;;   RESIDENT+21  the trampolines, 5 bytes each
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
    assert $ == FWJB
    include "fwtab.inc"

rs_cur:     db 0                ; the Lisp's bank at &C000,
rs_cfg:     db #C1              ;   and its configuration (C1 + 8 * bank)

;; fwc: from a trampoline -- the routine's address after the call -- with
;; every register as the caller left it; back to the caller with every
;; register as the routine left it.
fwc:
    ex (sp),hl                  ; HL -> the address; the caller's HL on top
    push af
    ld a,(hl)
    ld (fw_call+1),a
    inc hl
    ld a,(hl)
    ld (fw_call+2),a
    pop af
    pop hl                      ; (the caller's return on top again)
    call to_main
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
    add a,a
    add a,a
    add a,a
    or #C1
    ld (rs_cfg),a
    push bc
    ld b,#7F
    ld c,a
    out (c),c
    pop bc
    ld c,b
    ret
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
    rst 0

r_vidinit:
    call to_main
    call VID_INIT
    jp to_lisp
r_vidchar:
    call to_main
    call VID_CHAR
    jp to_lisp

    include "frcode.asm"

res_end:
    print "resident: ",res_end-RESIDENT," bytes"
    assert res_end <= RESIDENT_END
