;; CPC Lisp -- the TRS-80's resident part: what must be seen whatever page
;; is at &C000. Loaded at RESIDENT (&5200) with the loader (LISP/CMD), there
;; for good.
;;
;;   RESIDENT+0  SYS_BANK: C = a page -> C = the one before (AF, B lost)
;;   RESIDENT+3  SYS_CURBANK: -> A = the page at &C000
;;   RESIDENT+6  the jumpblock: entry k is "call mfar : db 2k" (jumps.asm)
;;
;; A call to entry k lands on "call mfar": mfar takes the byte after it
;; (and drops that return), maps the machine page (MACHPAGE) at &C000,
;; calls the routine its table (MTAB) has for the entry -- with every
;; register as the caller left it -- maps the caller's page back and
;; returns to the caller, every register as the routine left it. Not
;; reentrant: the machine routines never call the jumpblock.

    include "firmware.asm"
    include "jumps.asm"
    include "memmap.asm"

    org RESIDENT
    jp rs_bank
    jp rs_curbank
    assert $ == JB
    include "jumptab.inc"

mfar:
    ex (sp),hl                  ; HL -> the entry's byte; the caller's HL
    push af                     ;   on the stack, over the caller's return
    ld a,(hl)
    ifdef TRACE
    push af
.tw:
    ld a,(PRINTER)
    rlca
    jr c,.tw
    pop af
    push af
    srl a
    add a,'0'
    ld (PRINTER),a
    pop af
    endif
    ld l,a
    ld h,MTAB >> 8              ; HL -> the table's word for the entry
    ld a,(xm_cur)
    ld (mf_page),a
    ld a,MACHPAGE
    ld (xm_cur),a
    out (XM_HI),a
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld (mf_tgt),hl
    pop af
    pop hl                      ; the caller's AF and HL; its return next
    call .go
    push af
    ld a,(mf_page)
    ld (xm_cur),a
    out (XM_HI),a
    pop af
    ret
.go:
    push hl
    ld hl,(mf_tgt)
    ex (sp),hl
    ret

rs_bank:
    ld a,(xm_cur)
    ld b,a
    ld a,c
    ld (xm_cur),a
    out (XM_HI),a
    ld c,b
    ret
rs_curbank:
    ld a,(xm_cur)
    ret

xm_cur:     db COREPAGE         ; the page at &C000
mf_page:    db 0
mf_tgt:     dw 0
res_end:
    assert res_end <= LOWMEM
