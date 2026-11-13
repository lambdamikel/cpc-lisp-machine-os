;; CPC Lisp -- the Model 4's resident part: what must be seen whatever bank
;; is at &8000. Loaded at RESIDENT (&2600) with the loader (LISP/CMD), there
;; for good.
;;
;;   RESIDENT+0  SYS_BANK: C = a slot -> C = the one before (AF, B lost)
;;   RESIDENT+3  SYS_CURBANK: -> A = the slot in
;;   RESIDENT+6  RS_SVC: A = an LS-DOS supervisor call, the rest its
;;               registers -> its registers and flags
;;   RESIDENT+9  the variables (jumps.asm), then at JB the jumpblock:
;;               entry k is "call mfar : db 2k"
;;
;; A slot is half of one of LS-DOS's 32 KB banks 0-2 (slot s, 2-7: bank
;; s/2 - 1, at &C000 if s is odd, else at &8000). Bringing a bank in is OPREG's bits
;; 4-6, written to the port and to LS-DOS's image of it (OFLAG$) -- the
;; image first: LS-DOS's drivers, in an interrupt, map the keyboard and the
;; screen in from it and put it back, so it must always say what is in.
;; LS-DOS itself is called with its bank 0 in (RS_SVC): its drivers and
;; disk routines take what they find, and the caller's bank comes back.
;;
;; A call to entry k lands on "call mfar": mfar takes the byte after it
;; (and drops that return), brings the machine page's slot in, calls the
;; routine its table (MTAB) has for the entry -- with every register as
;; the caller left it -- puts the caller's slot back and returns to the
;; caller, every register as the routine left it. Not reentrant: the
;; machine routines never call the jumpblock (they call RS_SVC).

    include "firmware.asm"
    include "jumps.asm"
    include "memmap.asm"

    org RESIDENT
    jp rs_bank
    jp rs_curbank
    assert $ == RS_SVC
    jp rs_gate
    assert $ == RS_P84
    db #87                      ; RS_P84: OPREG as it is now
    db CORESLOT                 ; RS_SLOT: the slot in
    db #87                      ; RS_BASE: OPREG with bank 0, LS-DOS's
    dw 0                        ; RS_OFLAG: &OFLAG$ (the loader sets it)
    db 0,0,0,0                  ; RS_TICKS: the clock task's count
    assert $ == RS_TCB
    dw rs_task                  ; RS_TCB: the clock task's control block
    assert $ == RS_TSLOT
    db 255,0                    ; RS_TSLOT: its slot (the loader), 255: none
    assert $ == JB
    include "jumptab.inc"

;; rs_set: A = a slot -> its bank in (OFLAG$, then the port). All but AF kept.
rs_set:
    push hl
    ld (RS_SLOT),a
    srl a
    dec a                       ; the bank
    jr z,.none                  ; 0: LS-DOS's own, no bank bits
    dec a
    ld a,#20                    ; 1
    jr z,.bits
    ld a,#30                    ; 2
    jr .bits
.none:
    xor a
.bits:
    ld hl,RS_BASE
    or (hl)
    ld (RS_P84),a
    ld hl,(RS_OFLAG)
    ld (hl),a
    out (OPREG),a
    pop hl
    ret

rs_bank:
    ld a,(RS_SLOT)
    ld b,a
    ld a,c
    call rs_set
    ld c,b
    ret
rs_curbank:
    ld a,(RS_SLOT)
    ret

;; rs_gate: bank 0 in, as LS-DOS has it, for the call; then LS-DOS's image
;; (it may have changed the screen's bits) is the base the caller's slot
;; comes back on. Not reentrant (LS-DOS never calls the Lisp).
rs_gate:
    ld (sv_a),a
    ld a,(RS_SLOT)
    ld (sv_slot),a
    push hl
    ld hl,(RS_OFLAG)
    ld a,(RS_BASE)
    ld (hl),a
    ld (RS_P84),a
    out (OPREG),a
    pop hl
    ld a,(sv_a)
    rst #28
    push af
    push hl
    ld hl,(RS_OFLAG)
    ld a,(hl)
    and #FF-OP_BANK
    ld (RS_BASE),a
    ld a,(sv_slot)
    call rs_set
    pop hl
    pop af
    ret
sv_a:       db 0
sv_slot:    db 0

mfar:
    ex (sp),hl                  ; HL -> the entry's byte; the caller's HL
    push af                     ;   on the stack, over the caller's return
    ld a,(hl)
    ld l,a
    ld h,MTAB >> 8              ; HL -> the table's word for the entry
    ld a,(RS_SLOT)
    ld (mf_slot),a
    ld a,MACHSLOT
    call rs_set
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld (mf_tgt),hl
    pop af
    pop hl                      ; the caller's AF and HL; its return next
    call .go
    push af
    ld a,(mf_slot)
    call rs_set
    pop af
    ret
.go:
    push hl
    ld hl,(mf_tgt)
    ex (sp),hl
    ret
mf_slot:    db 0
mf_tgt:     dw 0

;; rs_task: the clock task (LS-DOS's task processor calls it, through
;; RS_TCB, 30 times a second -- a medium slot): the count up by one.
rs_task:
    ld hl,RS_TICKS
    inc (hl)
    ret nz
    inc hl
    inc (hl)
    ret nz
    inc hl
    inc (hl)
    ret nz
    inc hl
    inc (hl)
    ret
res_end:
    print "resident: ",res_end-RESIDENT," bytes"
    assert res_end <= LINEBUF
