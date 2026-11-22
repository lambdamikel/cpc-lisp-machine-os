;; CPC Lisp -- the MSX's resident part: what must be seen whatever image
;; is at &C000 and whatever segment at &8000. The start of LISP.COM, at
;; &0100 (the loader, loader.asm, follows it), there for good.
;;
;;   RESIDENT+0  RS_START: LISP.COM's start, the loader
;;   RESIDENT+3  SYS_BANK: C = a bank (0-5) -> C = the one before (AF, B lost)
;;   RESIDENT+6  SYS_CURBANK: -> A = the bank at &C000
;;   RESIDENT+9  RS_XFER: A = a segment, mapped at &8000 for one LDIR (HL to
;;               DE, BC bytes), then what was there (the RAM disc's way to
;;               its segments)
;;   RESIDENT+12 RS_DOS: a DOS call -- C its function, A, B, DE, HL, IX as
;;               it takes them and as it gives them back, IY kept -- with DOS's
;;               segments in pages 2 and 3 for it, on a stack in DOS's page 3
;;   RESIDENT+15 RS_MATH: IX = a Math-Pack routine (the main ROM's), HL =
;;               a number of its own, 8 bytes, into DAC; DE = another, into
;;               ARG (or 0); the routine called (CALSLT) and DAC back at HL
;;               -- with DOS's page 3 for it (the BIOS's variables, DAC and
;;               ARG), the main ROM in pages 0 and 1, page 2 left as it is
;;               (machine page B calls it), the interrupts off
;;   RESIDENT+18 RS_QUIT: back to DOS -- SCREEN 0 through the BIOS, the
;;               program's end (DOS frees our segments)
;;   RESIDENT+21 RS_BOOT: the start, once everything is loaded
;;   JB          the jumpblock: entry k is "call mfar : db 2k" (jumps.asm)
;;
;; The mapper's ports cannot be read: RS_P2 says what page 2 holds, and
;; anything that changes it writes RS_P2 first, so an interrupt between
;; the two puts back the new one. Page 3's image is RS_BANK's.
;;
;; THE INTERRUPT (the VDP's, 50 or 60 a second, IM 1): DOS's &0038 jumps
;; into its page 3. While Lisp runs, that jump's address is r_int, ours:
;; it maps machine page A for its tick (the clock, the keys), then B (the
;; sound), and puts back page 2. For a DOS or ROM call it is DOS's again
;; (to_dos), with DOS's segments.
;;
;; A call to entry k lands on "call mfar": mfar takes the byte after it
;; (and drops that return), maps machine page A, finds the routine in its
;; table (MTAB; bit 14 set: in page B, which it maps instead), calls it
;; with every register as the caller left it, maps back what was there and
;; returns to the caller, every register as the routine left it. Machine
;; routines may call the jumpblock too: that is how one page reaches the
;; other.

    include "firmware.asm"
    include "jumps.asm"
    include "memmap.asm"

    org RESIDENT
    jp ld_start                 ; RS_START (loader.asm follows)
    jp r_bank
    jp r_curbank
    jp r_copy
    jp r_dos
    jp r_math
    jp r_quit
    jp r_boot
    assert $ == RS_P2
    db 0                        ; RS_P2
    db 0                        ; RS_BANK
    dw 0,0                      ; RS_FRAMES
    db 0                        ; RS_HOOK
    db 50                       ; RS_HZ
    db 1                        ; RS_KBD
    db 1                        ; RS_TPA2
    db 0                        ; RS_TPA3
    defs 8,0                    ; RS_SEGS
    assert $ == RS_RDN
    db 0                        ; RS_RDN
    defs RD_MAX,0               ; RS_RD
mf_hl:      dw 0                ; mfar's, while it finds the routine
mf_prev:    db 0
mf_tgt:     dw 0
rs_dosint:  dw 0                ; DOS's interrupt (its &0038 jump's address)
rs_sp:      dw 0                ; the caller's stack, during a DOS call
rs_in:      db 0                ; 1 while DOS or the ROM has the machine
rp_prev:    db 0                ; r_copy's
    assert $ <= JB

    defs JB-$,0
    include "jumptab.inc"

;; mfar: the jumpblock's way into a machine page (above)
mfar:
    ld (mf_hl),hl
    pop hl                      ; HL -> the entry's byte
    push af
    ld a,(RS_P2)
    ld (mf_prev),a
    ld a,(SEG_A)
    ld (RS_P2),a
    out (P_MAP2),a
    ld a,(hl)
    ld l,a
    ld h,MTAB >> 8              ; HL -> the table's word for the entry
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    bit 6,h
    jr z,.a
    res 6,h                     ; a routine of page B's
    ld a,(SEG_B)
    ld (RS_P2),a
    out (P_MAP2),a
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
    ld (RS_P2),a
    out (P_MAP2),a
    pop af
    pop hl
    ret
.go:
    push hl
    ld hl,(mf_tgt)
    ex (sp),hl
    ret

;; SYS_CURBANK: -> A = the bank at &C000
r_curbank:
    ld a,(RS_BANK)
    ret

;; SYS_BANK: C = a bank, 0-5 (the core 0) -> it at &C000, C = the one
;; before. (Called from RAM: the trampoline.)
r_bank:
    ld a,(RS_BANK)
    ld b,a
    ld a,c
    ld (RS_BANK),a
    push hl
    ld hl,RS_SEGS
    add a,l
    ld l,a
    ld a,(hl)
    pop hl
    out (P_MAP3),a
    ld c,b
    ret
    assert (RS_SEGS and #FF) <= #F8     ; (one page: r_bank, to_lisp add to L)

;; RS_XFER: A = a segment -> an LDIR (HL to DE, BC bytes) with it at
;; &8000, then what was mapped put back. AF lost.
r_copy:
    push af
    ld a,(RS_P2)
    ld (rp_prev),a
    pop af
    ld (RS_P2),a
    out (P_MAP2),a
    ldir
    ld a,(rp_prev)
    ld (RS_P2),a
    out (P_MAP2),a
    ret

;; the interrupt, while Lisp runs: machine page A's tick, then page B's,
;; with the page that was there put back after. IY and the alternate
;; registers are not touched.
r_int:
    push af
    in a,(P_VDPCTL)             ; the VDP's status: the interrupt answered
    push hl
    ld a,(RS_P2)
    push af
    ld a,(SEG_A)
    ld (RS_P2),a
    out (P_MAP2),a
    push bc
    push de
    push ix
    call P_TICK                 ; page A: the clock, the keys
    ld a,(SEG_B)
    ld (RS_P2),a
    out (P_MAP2),a
    call PB_TICK                ; page B: the sound
    pop ix
    pop de
    pop bc
    pop af
    ld (RS_P2),a
    out (P_MAP2),a
    pop hl
    pop af
    ei
    ret

;; to_dos: DOS's pages 2 and 3 and its interrupt, the interrupts off. All
;; registers kept. to_dos3: the same but for page 2, which stays.
to_dos:
    di
    push af
    ld a,(RS_TPA2)
    out (P_MAP2),a
    jr td3
to_dos3:
    di
    push af
td3:
    push hl
    ld a,1
    ld (rs_in),a
    ld hl,(rs_dosint)
    ld (DOS_INT+1),hl
    ld a,(RS_TPA3)
    out (P_MAP3),a
    pop hl
    pop af
    ret

;; to_lisp: back from to_dos: the bank, RS_P2's segment, our interrupt,
;; the interrupts on. All registers kept.
to_lisp:
    di
    push af
    push hl
    ld a,(RS_BANK)
    ld hl,RS_SEGS
    add a,l
    ld l,a
    ld a,(hl)
    out (P_MAP3),a
    ld a,(RS_P2)
    out (P_MAP2),a
    ld hl,r_int
    ld (DOS_INT+1),hl
    xor a
    ld (rs_in),a
    pop hl
    pop af
    ei
    ret

;; RS_DOS: DOS's function C with A, B, DE, HL, IX as it takes them -> what
;; it gives back. Its pointers must be in pages 0 and 1, or in page 3's TPA
;; below DOS_STACK-256 (seen only during the call).
r_dos:
    call to_dos
    ld (rs_sp),sp
    ld sp,DOS_STACK
    push iy                     ; (_ALLOC's IY, say)
    ei
    call DOS_BDOS
    pop iy
rd_back:
    ld sp,(rs_sp)
    jp to_lisp

;; RS_MATH: IX = a Math-Pack routine, HL = 8 bytes for DAC, DE = 8 for ARG
;; or 0 -> the routine run, DAC back at HL. HL kept; AF, BC, DE lost. The
;; numbers must be in pages 0-2.
r_math:
    call to_dos3
    ld (rs_sp),sp
    ld sp,DOS_STACK
    push hl                     ; where the answer goes
    push de
    ld de,MP_DAC
    ld bc,8
    ldir
    pop hl                      ; ARG's, if there is one
    ld a,h
    or l
    jr z,.go
    ld de,MP_ARG
    ld bc,8
    ldir
.go:
    ld a,8                      ; double precision
    ld (MP_VALTYP),a
    push iy
    push ix
    ld a,(EXPTBL)               ; the ROM in page 1 too: the Math-Pack calls
    ld h,#40                    ;   BASIC's half (SIN its INT)
    call DOS_ENASLT
    pop ix
    ld iy,(EXPTBL-1)            ; IYH = the main ROM's slot
    call DOS_CALSLT
    di
    ld a,(RAMAD1)               ; our RAM in page 1 again
    ld h,#40
    call DOS_ENASLT
    di
    pop iy
    pop de
    push de
    ld hl,MP_DAC
    ld bc,8
    ldir
    pop hl
    jr rd_back

;; r_abort: DOS's abort routine (D_DEFAB), called when a DOS call meets an
;; error it would end the program for (CTRL-STOP, a disc error aborted):
;; inside RS_DOS it returns from that call instead, with A = the error
;; (B, the one that caused it, if there is one) and NZ; anywhere else the
;; program ends, SCREEN 0 first.
r_abort:
    ld c,a
    ld a,(rs_in)
    or a
    jr z,r_end
    ld a,b
    or a
    jr nz,.b
    ld a,c
.b:
    or a                        ; NZ (an error is never 0)
    jr rd_back
;; r_diskerr: DOS's disc error routine (D_DEFER): abort, which r_abort
;; turns into the call's error
r_diskerr:
    ld a,1
    ret

;; RS_QUIT: SCREEN 0, the program's end
r_quit:
    call to_dos
    ld sp,DOS_STACK
r_end:
    ld iy,(EXPTBL-1)
    ld ix,INITXT
    call DOS_CALSLT
    ei
    ld de,0                     ; no abort routine (the end would call it)
    ld c,D_DEFAB
    call DOS_BDOS
    ld c,D_TERM0
    jp DOS_BDOS

;; (what is kept ends here: the start's code below runs on past LOWMEM,
;; which the core clears once it is started)
res_end:
    print "resident part: ",res_end-RESIDENT," bytes, to ",res_end
    assert res_end <= LOWMEM

;; RS_BOOT: everything loaded -- the images and the machine pages in their
;; segments, the RS_ variables set, DOS told of r_abort and r_diskerr: the
;; machine set up, the interrupt ours, the core started.
r_boot:
    di
    ld sp,LINEBUF
    ld hl,0
    ld (RS_FRAMES),hl
    ld (RS_FRAMES+2),hl
    xor a
    ld (rs_in),a
    ld hl,(DOS_INT+1)
    ld (rs_dosint),hl
    ld a,(SEG_B)                ; page B sets itself up,
    ld (RS_P2),a
    out (P_MAP2),a
    call MPAGE
    ld a,(SEG_A)                ;   then page A
    ld (RS_P2),a
    out (P_MAP2),a
    call P_INIT
    di
    ld a,(RS_TPA2)
    ld (RS_P2),a
    out (P_MAP2),a
    ld hl,r_int
    ld (DOS_INT+1),hl
    xor a
    ld (RS_BANK),a
    ld a,(RS_SEGS)              ; bank 0: the core
    out (P_MAP3),a
    ei
    jp #C006                    ; the core's start
boot_end:

    include "loader.asm"
