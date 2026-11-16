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

;; MACH_BLOCKS: HL = the bytes for cells and blocks -> HL = block space's
;; share: three eighths (a quarter until 2026-11-15: some 4 KB of strings,
;; and Mike's Model III said "out of string space" after an afternoon of
;; demos and editing -- every name read stays there, compiled code too).
;; DE is free here.
macro MACH_BLOCKS
    srl h
    rr l
    srl h
    rr l                        ; a quarter
    ld d,h
    ld e,l
    srl d
    rr e                        ; an eighth
    add hl,de
mend

;; FM routine: a maths routine, through the jumpblock
macro FM addr
    call {addr}
mend

;; MACH_TITLE: the banner's second line
macro MACH_TITLE
    db "A Lisp machine for the TRS-80",13,10,0
mend

;; SYS_RESET: back to LDOS, as (quit) -- RST 0, the ROM's start with
;; X-MEM/80's pages as they are, hung (trs80gp)
macro SYS_RESET
    jp M_QUIT
mend
