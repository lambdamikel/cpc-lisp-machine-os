;; CPC Lisp -- the machine's macros, on the TRS-80 Model 4. Included by
;; src/macros.asm. (mach/README.md: the contracts.)

;; MACH_START: the loader (loader.asm) has made the machine ready: the
;; slots loaded, the resident part in place, the core's slot in. A stack
;; for the start, in the line buffer (the low system area and the stack's
;; own place are cleared next); the heap's last byte is pushed.
macro MACH_START
    ld sp,TOKBUF
    ld hl,MEMTOP
    push hl
mend

;; MACH_INIT: HL = the last usable byte -> V_MEMTOP, and V_EDITV: a plain
;; line input of the machine page's, for when there is no library
macro MACH_INIT
    ld (V_MEMTOP),hl
    ld hl,M_EDIT
    ld (V_EDITV),hl
mend

;; MACH_BLOCKS: HL = the bytes for cells and blocks -> HL = block space's
;; share: a quarter (as on the TRS-80 Model I/III)
macro MACH_BLOCKS
    srl h
    rr l
    srl h
    rr l
mend

;; FM routine: a maths routine, through the jumpblock
macro FM addr
    call {addr}
mend

;; MACH_TITLE: the banner's second line
macro MACH_TITLE
    db "A Lisp machine for the TRS-80 Model 4",13,10,0
mend

;; SYS_RESET: back to LS-DOS, as (quit)
macro SYS_RESET
    jp M_QUIT
mend
