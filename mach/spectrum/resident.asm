;; CPC Lisp -- the Spectrum's resident part: what must be seen whatever
;; bank is at &C000 and whatever the DivMMC shows at &0000-&3FFF. Loaded at
;; IM2TAB (&5D00) with the loader, there for good.
;;
;;   IM2TAB      257 bytes of IM2HI: the interrupt (IM 2) goes to IM2VEC
;;   RESIDENT+0  SYS_BANK: C = a bank (0-5) -> C = the one before (AF, B lost)
;;   RESIDENT+3  SYS_CURBANK: -> A = the bank at &C000
;;   RESIDENT+6  RS_XFER: A = a DivMMC page, mapped at &2000 for one LDIR
;;               (HL to DE, BC bytes), then what was there (the RAM disc's
;;               way to its pages)
;;   RESIDENT+9  RS_ESX: an esxDOS call -- RS_FN its function, A, BC, DE,
;;               HL, IX as it takes them and as it gives them back
;;   RESIDENT+12 RS_CALC: A = a calculator literal, run on the ROM's
;;               calculator stack -> carry, or none if the ROM had an error
;;   RESIDENT+15 RS_BOOT: the start, once everything is loaded
;;   IM2VEC      the interrupt: machine page A's tick (P_TICK)
;;   JB          the jumpblock: entry k is "call mfar : db 2k" (jumps.asm)
;;
;; A machine page is DivMMC RAM, seen at &2000 with CONMEM set -- the
;; DivMMC's EEPROM is then at &0000 instead of the ROM. RS_E3 says what the
;; port holds now (it cannot be read): anything that changes it puts it in
;; RS_E3 first, so an interrupt between the two puts back the new one.
;;
;; A call to entry k lands on "call mfar": mfar takes the byte after it
;; (and drops that return), maps machine page A, finds the routine in its
;; table (MTAB; bit 15 set: in page B, which it maps instead), calls it
;; with every register as the caller left it, maps back what was there and
;; returns to the caller, every register as the routine left it. Machine
;; routines may call the jumpblock too: that is how one page reaches the
;; other.

    include "firmware.asm"
    include "jumps.asm"
    include "memmap.asm"

    org IM2TAB
    defs 257,IM2HI
    assert $ == RESIDENT
    jp r_bank
    jp r_curbank
    jp r_copy
    jp r_esx
    jp r_calc
    jp r_boot
    assert $ == RS_E3
    db 0                        ; RS_E3
    db 0                        ; RS_FN
    db 0                        ; RS_BANK
    dw 0,0                      ; RS_FRAMES
    db 0                        ; RS_HOOK
    db 0                        ; RS_MODEL
mf_hl:      dw 0                ; mfar's, while it finds the routine
mf_prev:    db 0
mf_tgt:     dw 0
rs_a:       db 0                ; r_esx's
rx_e3:      db 0
rc_e3:      db 0                ; r_calc's
rp_e3:      db 0                ; r_copy's
bank_phys:  db 0,1,3,4,6,7      ; the banks' RAM banks

;; SYS_CURBANK: -> A = the bank at &C000
r_curbank:
    ld a,(RS_BANK)
    ret

;; RS_XFER: A = a DivMMC page -> an LDIR (HL to DE, BC bytes) with it at
;; &2000, then what was mapped put back. AF lost.
r_copy:
    push af
    ld a,(RS_E3)
    ld (rp_e3),a
    pop af
    or CONMEM
    ld (RS_E3),a
    out (P_DIVMMC),a
    ldir
    ld a,(rp_e3)
    ld (RS_E3),a
    out (P_DIVMMC),a
    ret

    defs IM2VEC-$,0
;; the interrupt, 50 times a second: machine page A's tick, with the page
;; that was there put back after. IY and the alternate registers are not
;; touched (the ROM's calculator may be running).
    assert $ == IM2VEC
im2:
    push af
    push hl
    ld a,(RS_E3)
    push af
    ld a,E3_A
    out (P_DIVMMC),a
    push bc
    push de
    push ix
    call P_TICK
    pop ix
    pop de
    pop bc
    pop af
    out (P_DIVMMC),a
    pop hl
    pop af
    ei
    reti
    assert $ <= JB

    defs JB-$,0
    include "jumptab.inc"

;; mfar: the jumpblock's way into a machine page (above)
mfar:
    ld (mf_hl),hl
    pop hl                      ; HL -> the entry's byte
    push af
    ld a,(RS_E3)
    ld (mf_prev),a
    ld a,E3_A
    ld (RS_E3),a
    out (P_DIVMMC),a
    ld a,(hl)
    ld l,a
    ld h,MTAB >> 8              ; HL -> the table's word for the entry
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    bit 7,h
    jr z,.a
    res 7,h                     ; a routine of page B's
    ld a,E3_B
    ld (RS_E3),a
    out (P_DIVMMC),a
.a:
    ld (mf_tgt),hl
    ld a,(mf_prev)
    ld h,a
    pop af                      ; the caller's AF; its return next
    push hl                     ; under it, what was mapped
    ld hl,(mf_hl)
    call .go
    ex (sp),hl                  ; H = what was mapped
    push af
    ld a,h
    ld (RS_E3),a
    out (P_DIVMMC),a
    pop af
    pop hl
    ret
.go:
    push hl
    ld hl,(mf_tgt)
    ex (sp),hl
    ret

;; SYS_BANK: C = a bank, 0-5 (the core 0) -> it at &C000, C = the one before
r_bank:
    ld a,(RS_BANK)
    ld b,a
    ld a,c
    ld (RS_BANK),a
    push hl
    ld hl,bank_phys
    add a,l
    ld l,a
    ld a,(hl)
    pop hl
    or PG_7FFD
    ld (BANK_M),a
    push bc
    ld bc,P_7FFD
    out (c),a
    pop bc
    ld c,b
    ret
    assert (bank_phys and #FF) <= #FA     ; (one page: r_bank adds to L)

;; RS_ESX: esxDOS's function RS_FN, with A, BC, DE, HL, IX as it takes
;; them -> what it gives back (carry and A = the error, if it failed). The
;; DivMMC is left to esxDOS for the call -- it maps itself in at the RST and
;; sets the port its own way -- with the interrupts off: ours maps a
;; machine page, which would pull esxDOS's own RAM from under it.
r_esx:
    ld (rs_a),a
    ld a,(RS_FN)
    ld (.fn),a
    ld a,(RS_E3)
    ld (rx_e3),a
    di
    xor a
    ld (RS_E3),a
    out (P_DIVMMC),a
    ld a,(rs_a)
    rst 8
.fn:
    db 0
    di
    push af
    ld a,(rx_e3)
    ld (RS_E3),a
    out (P_DIVMMC),a
    pop af
    ei
    ret

;; RS_CALC: A = a calculator literal -> run with RST 28 on the ROM's
;; calculator stack (STKEND), the ROM mapped in for it; carry, or none if
;; the ROM met an error (its RST 8 ends at ERR_SP: SET-STK has emptied the
;; calculator's stack). BC, DE, HL lost; IY kept.
r_calc:
    ld (.op),a
    ld a,(RS_E3)
    ld (rc_e3),a
    push iy
    ld iy,SV_ERRNR
    ld hl,(SV_ERRSP)
    push hl
    ld hl,.err
    push hl
    ld (SV_ERRSP),sp
    xor a
    ld (RS_E3),a
    out (P_DIVMMC),a
    rst ROM_CALC
.op:
    db 0
    db #38                      ; end-calc
    pop hl                      ; (.err)
    scf
    jr .back
.err:
    or a
.back:
    pop hl
    ld (SV_ERRSP),hl
    pop iy
    push af
    ld a,(rc_e3)
    ld (RS_E3),a
    out (P_DIVMMC),a
    pop af
    ret

;; (what is kept ends here: the start's code below may run on past
;; LOWMEM, which the core clears once it is started)
res_end:
    print "resident part: ",res_end-RESIDENT," bytes, to ",res_end
    assert res_end <= LOWMEM

;; RS_BOOT: everything loaded -- the images in their banks, the machine
;; pages in the DivMMC's pages MP_A, MP_B, this at IM2TAB: the machine set
;; up, the interrupt ours, the core started.
r_boot:
    di
    ld sp,LINEBUF
    ld a,(RS_MODEL)
    or a
    jr nz,.p
    ld a,PG_1FFD                ; (a 128 has no &1FFD: its 48 BASIC is
    ld (BANK678),a              ;   ROM 1, &7FFD's bit 4 alone)
    ld bc,P_1FFD
    out (c),a
.p:
    xor a
    ld (RS_BANK),a
    ld a,PG_7FFD                ; bank 0: the core
    ld (BANK_M),a
    ld bc,P_7FFD
    out (c),a
    ld iy,SV_ERRNR              ; the calculator's variables
    ld hl,CALC_STK
    ld (SV_STKBOT),hl
    ld (SV_STKEND),hl
    ld hl,SV_MEMBOT
    ld (SV_MEM),hl
    ld hl,0
    ld (RS_FRAMES),hl
    ld (RS_FRAMES+2),hl
    ld a,IM2TAB >> 8
    ld i,a
    im 2
    ld a,E3_B                   ; page B sets itself up,
    ld (RS_E3),a
    out (P_DIVMMC),a
    call MPAGE
    ld a,E3_A                   ;   then page A
    ld (RS_E3),a
    out (P_DIVMMC),a
    call P_INIT
    xor a
    ld (RS_E3),a
    out (P_DIVMMC),a
    ei
    jp #C006                    ; the core's start
boot_end:
    assert boot_end <= SYM_LO
