;; CPC Lisp -- the machine's macros, on the TRS-80. Included by
;; src/macros.asm. (mach/README.md: the contracts.)

;; MACH_START: the loader (loader.asm) has made the machine ready: the
;; pages loaded, the resident part in place, the core's page in. The stack
;; goes under the fixed area; the last usable byte is pushed.
macro MACH_START
    ld sp,LINEBUF
    ld hl,LINEBUF-1
    push hl
mend

;; MACH_INIT: HL = the last usable byte -> V_MEMTOP, and V_EDITV: a plain
;; line input of the machine page's, for when there is no library
macro MACH_INIT
    ld (V_MEMTOP),hl
    ld hl,M_EDIT
    ld (V_EDITV),hl
mend

;; FM routine: a maths routine, through the jumpblock
macro FM addr
    call {addr}
mend

;; MACH_TITLE: the banner's second line
macro MACH_TITLE
    db "A Lisp machine for the TRS-80",13,10,0
mend

;; SYS_RESET: start again -- the ROM, then LDOS from its disc
macro SYS_RESET
    rst 0
mend
