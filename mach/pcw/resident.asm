;; CPC Lisp -- the PCW's resident part: what must be seen whatever image or
;; machine page is at &C000 and whatever block in the WINDOW. Block 4 at
;; &0000, there for good; the loader (loader.asm) puts it there.
;;
;;   &0000       RST 0: OUT (&F0),A -- with A = &80, block 0 at &0000 and so
;;               the boot program at &0002 (RS_QUIT's way: on a real PCW
;;               SC_REBOOT reboots the machine; ZEsarUX puts the boot
;;               program into block 0 and goes to &0000)
;;   &0038       the interrupt (IM 1)
;;   SYS_BANK    C = a bank (0-5) -> C = the one before (AF, B lost)
;;   SYS_CURBANK -> A = the bank at &C000
;;   RS_XFER     A = &80 + a block; carry set: BC bytes from RAM at HL to the
;;               block at DE (WINDOW's addresses), clear: from the block at
;;               HL to RAM at DE -- through a buffer of its own, so the RAM
;;               may be anywhere below &C000, the WINDOW's too (the RAM
;;               disc's way to its blocks, far arrays')
;;   RS_QUIT     the boot program again
;;   RS_BOOT     the start, once the loader has put everything in place
;;   JB          the jumpblock: entry k is "call mfar : db 2k" (jumps.asm)
;;
;; The ports cannot be read: RS_P1 and RS_P3 say what &4000 and &C000
;; show, and anything that changes one writes its RS_ first, so an
;; interrupt between the two puts back the new one.
;;
;; THE INTERRUPT (300 a second, IM 1): reading port &F4 answers it and
;; says how many ticks there were since it was last read (more than one
;; after the interrupts were off: a disc transfer); each counts 1/300 s.
;; Every 6th the keys (machine page A's tick), every 3rd the sound (page
;; B's) -- each page mapped at &C000 for it, then what was there again.
;;
;; A call to entry k lands on "call mfar": mfar takes the byte after it
;; (and drops that return), maps machine page A at &C000, finds the routine
;; in its table (MTAB; bit 14 clear: in page B, which it maps instead),
;; calls it with every register as the caller left it, maps back what was
;; there and returns to the caller, every register as the routine left it.
;; Machine routines may call the jumpblock too: that is how one page
;; reaches the other.

    include "firmware.asm"
    include "jumps.asm"
    include "memmap.asm"

    org RESIDENT
    out (P_MAP0),a              ; &0000 (RS_QUIT's: A = &80)
    defs #0038-$,0
    jp r_int                    ; &0038
    defs SYS_BANK-$,0
    jp r_bank                   ; SYS_BANK
    jp r_curbank                ; SYS_CURBANK
    jp r_xfer                   ; RS_XFER
    jp r_quit                   ; RS_QUIT
    jp r_boot                   ; RS_BOOT
    assert $ == RS_P1
    db #80+BL_MID               ; RS_P1
    db #80+BL_PA                ; RS_P3
    db 0                        ; RS_BANK
    dw 0,0                      ; RS_FRAMES
    db 0                        ; RS_HOOK
    db 100                      ; RS_HZ
    db 16                       ; RS_NBLK (the loader's)
    db 0                        ; RS_QUITF
    db 3                        ; RS_T3
    db 6                        ; RS_T6
    assert $ == RS_SEGS
    db #80+BL_IMG,#81+BL_IMG,#82+BL_IMG,#83+BL_IMG,#84+BL_IMG,#85+BL_IMG
    db #80+BL_PA,#80+BL_PB
    assert $ == RS_RDN
    db 0                        ; RS_RDN (the loader's)
    defs RD_MAX,0               ; RS_RD
    assert $ == RS_MOTOR
    db 0                        ; RS_MOTOR
    db 0                        ; RS_HARN (the harness's disc has 1 here)
mf_hl:      dw 0                ; mfar's, while it finds the routine
mf_prev:    db 0
mf_tgt:     dw 0
rx_blk:     db 0                ; r_xfer's
rx_dir:     db 0
rx_prev:    db 0
rx_n:       dw 0
rx_k:       dw 0
    assert $ <= JB

    defs JB-$,0
    include "jumptab.inc"

;; mfar: the jumpblock's way into a machine page (above)
mfar:
    ld (mf_hl),hl
    pop hl                      ; HL -> the entry's byte
    push af
    ld a,(RS_P3)
    ld (mf_prev),a
    ld a,(SEG_A)
    ld (RS_P3),a
    out (P_MAP3),a
    ld a,(hl)
    ld l,a
    ld h,MTAB >> 8              ; HL -> the table's word for the entry
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    bit 6,h
    jr nz,.a
    set 6,h                     ; a routine of page B's
    ld a,(SEG_B)
    ld (RS_P3),a
    out (P_MAP3),a
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
    ld (RS_P3),a
    out (P_MAP3),a
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
    ld (RS_P3),a
    out (P_MAP3),a
    ld c,b
    ret
    assert (RS_SEGS and #FF) <= #F8     ; (one page: r_bank adds to L)

;; RS_XFER: (above) 128 bytes at a time through rx_buf: the RAM's side with
;; the WINDOW as it was, the block's with the block there. AF, BC lost; HL,
;; DE past what was copied.
r_xfer:
    ld (rx_blk),a
    sbc a,a                     ; &FF: to the block
    ld (rx_dir),a
    ld (rx_n),bc
.l:
    ld bc,(rx_n)
    ld a,b
    or c
    ret z
    ld a,b
    or a
    jr nz,.big
    ld a,c
    cp 128
    jr c,.k
.big:
    ld bc,128
.k:
    push hl                     ; BC = this piece's bytes
    ld hl,(rx_n)
    or a
    sbc hl,bc
    ld (rx_n),hl
    pop hl
    ld (rx_k),bc
    ld a,(rx_dir)
    or a
    jr z,.from
    push de                     ; to the block: RAM to the buffer,
    ld de,rx_buf
    ldir
    pop de
    push hl
    call rx_on                  ;   the buffer to the block
    ld hl,rx_buf
    ld bc,(rx_k)
    ldir
    call rx_off
    pop hl
    jr .l
.from:
    call rx_on                  ; from the block: it to the buffer,
    push de
    ld de,rx_buf
    ldir
    pop de
    call rx_off
    push hl                     ;   the buffer to RAM
    ld hl,rx_buf
    ld bc,(rx_k)
    ldir
    pop hl
    jr .l
;; rx_on: rx_blk in the WINDOW; rx_off: what was there again. All kept.
rx_on:
    push af
    ld a,(RS_P1)
    ld (rx_prev),a
    ld a,(rx_blk)
    jr rx_set
rx_off:
    push af
    ld a,(rx_prev)
rx_set:
    ld (RS_P1),a
    out (P_MAP1),a
    pop af
    ret

;; the interrupt (above). IY and the alternate registers are not touched.
r_int:
    push af
    in a,(P_TICKS)              ; the ticks since: the interrupt answered
    and 15
    jr z,.out                   ; (not the timer's)
    push hl
    push bc
    ld c,a
    ld hl,(RS_FRAMES)
    ld b,0
    add hl,bc
    ld (RS_FRAMES),hl
    jr nc,.f
    ld hl,(RS_FRAMES+2)
    inc hl
    ld (RS_FRAMES+2),hl
.f:
    ld h,b                      ; H: the keys are due, B: sound ticks due
.t:
    ld a,(RS_T3)
    dec a
    jr nz,.t3
    inc b
    ld a,3
.t3:
    ld (RS_T3),a
    ld a,(RS_T6)
    dec a
    jr nz,.t6
    inc h
    ld a,6
.t6:
    ld (RS_T6),a
    dec c
    jr nz,.t
    ld a,b
    or h
    jr z,.done
    ld a,(RS_P3)
    push af
    push de
    push ix
    ld a,h
    or a
    jr z,.snd
    ld a,(SEG_A)
    ld (RS_P3),a
    out (P_MAP3),a
    push bc
    call P_TICK                 ; page A: the keys, the motors
    pop bc
.snd:
    ld a,b
    or a
    jr z,.back
    ld a,(SEG_B)
    ld (RS_P3),a
    out (P_MAP3),a
.s:
    push bc
    call PB_TICK                ; page B: the sound
    pop bc
    djnz .s
.back:
    pop ix
    pop de
    pop af
    ld (RS_P3),a
    out (P_MAP3),a
.done:
    pop bc
    pop hl
.out:
    pop af
    ei
    ret

;; RS_QUIT: the boot program again: a real PCW reboots; ZEsarUX goes to
;; &0000 at once, A = &80 (above)
r_quit:
    di
    ld a,#80
    ld bc,SC_REBOOT*256+P_SYS
    out (c),b
    jp RESIDENT

rx_buf:     defs 128,0          ; r_xfer's

;; (what is kept ends here: the start's code below runs on past LOWMEM,
;; which the core clears once it is started)
res_end:
    print "resident part: ",res_end-RESIDENT," bytes, to ",res_end
    assert res_end <= LOWMEM

;; RS_BOOT: everything loaded -- the images and the machine pages in their
;; blocks, Lisp's at &0000-&BFFF, RS_NBLK and the RAM disc's blocks noted
;; (the loader): the machine pages set up, the interrupt on, the core
;; started. The stack: the loader's, wherever it was.
r_boot:
    di
    ld sp,LINEBUF
    im 1
    ld a,SC_FDCNONE             ; the disc controller polled
    out (P_SYS),a
    ld hl,0
    ld (RS_FRAMES),hl
    ld (RS_FRAMES+2),hl
    xor a
    ld (RS_QUITF),a
    ld a,100                    ; the motors are on (the loader's): off in 2 s
    ld (RS_MOTOR),a
    ld a,#80+BL_MID
    ld (RS_P1),a
    out (P_MAP1),a
    ld a,(SEG_B)                ; page B sets itself up,
    ld (RS_P3),a
    out (P_MAP3),a
    call P_INIT
    ld a,(SEG_A)                ;   then page A
    ld (RS_P3),a
    out (P_MAP3),a
    call P_INIT
    di
    xor a
    ld (RS_HOOK),a
    ld (RS_BANK),a
    ld a,(RS_SEGS)              ; bank 0: the core
    ld (RS_P3),a
    out (P_MAP3),a
    in a,(P_TICKS)              ; (the ticks so far: none)
    ei
    jp #C006                    ; the core's start
boot_end:
    assert boot_end <= LOWMEM+#200
