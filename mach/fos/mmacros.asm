;; CPC Lisp on FutureOS itself -- the machine's macros (mach/cpc512's, with
;; the resident part at &9000 and no firmware).

;; MACH_START: LISP.64K has loaded the images, put the resident part in
;; place and started the interrupts; the stack below the resident part
;; (&C000 is the screen, &A000-&BFFF FutureOS's).
macro MACH_START
    ld sp,RESIDENT
    ld hl,RESIDENT-1            ; the top: the resident part above
    push hl
mend

;; MACH_INIT: HL = the last usable byte -> V_MEMTOP; 128 bytes under it for
;; user-defined characters (V_UDG, SYMBOL); V_EDITV, the line editor for
;; when there is no library, the machine page's (a stub).
macro MACH_INIT
    ld de,-127
    add hl,de
    ld (V_UDG),hl
    dec hl
    ld (V_MEMTOP),hl
    ld hl,EDIT_6128
    ld (V_EDITV),hl
mend

;; MACH_BLOCKS: a quarter of the heap for blocks (strings), as on the 512K
macro MACH_BLOCKS
    srl h
    rr l
    srl h
    rr l
mend

;; FM routine: a maths routine of the lower ROM's (fp.asm)
macro FM addr
    call fmcall
    db {addr}-M_MOVE
mend

macro MACH_TITLE
    db "A Lisp machine for the Amstrad CPC on FutureOS",13,10,0
mend

macro SYS_RESET
    jp RS_RESET
mend
