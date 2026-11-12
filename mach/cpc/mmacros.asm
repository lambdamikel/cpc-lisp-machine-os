;; CPC Lisp -- the machine's macros, on the Amstrad CPC: what the portable
;; sources expand in place, where a call would not do. Included by
;; src/macros.asm, so the core and every library ROM have them.

;; MACH_START: the core's first step. The machine is made ready, the stack
;; set, and the last usable byte of RAM pushed. The firmware enters a
;; foreground ROM with DE = the first usable byte (&0040), HL = the last
;; (&ABFF) and BC = the top of the foreground's own area (&B0FF), on the
;; 464 and the 6128 alike. The background ROMs are not initialised yet:
;; that is the foreground program's job -- BASIC's first instruction after
;; LD SP,&C000 is this same CALL KL ROM WALK -- and without it there is no
;; disc.
macro MACH_START
    ld sp,#C000
    call KL_ROM_WALK            ; DE, HL in; HL out, lowered by each ROM
    push hl
mend

;; MACH_INIT: HL = the last usable byte; the low area and the variables
;; are clear -> V_MEMTOP set, and V_EDITV, the line editor for when there
;; is no library. On the CPC: 128 bytes under the top for user-defined
;; characters (V_UDG, SYMBOL), and the firmware's EDIT, past &BD37, where
;; the 464 and the 664/6128 differ (&BD3D is a FIRM JUMP, &EF, only on a
;; 464).
macro MACH_INIT
    ld de,-127
    add hl,de
    ld (V_UDG),hl
    dec hl
    ld (V_MEMTOP),hl
    ld hl,EDIT_6128
    ld a,(FIRM_464_PROBE)
    cp #EF
    jr nz,@not464
    ld hl,EDIT_464
@not464:
    ld (V_EDITV),hl
mend

;; FM routine: call a maths routine, an FP_ name (machine.asm). A, BC, DE
;; and HL go in; IX is lost. On the CPC the byte after the call says which
;; (fmcall, fp.asm); fp_callix calls the one whose FP_ name is in IX.
macro FM addr
    call fmcall
    db {addr}-M_MOVE
mend

;; MACH_TITLE: the banner's second line
macro MACH_TITLE
    db "A Lisp machine for the Amstrad CPC",13,10,0
mend

;; SYS_RESET: start the machine afresh
macro SYS_RESET
    rst 0
mend
