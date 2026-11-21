;; CPC Lisp -- the machine's macros, on the ZX Spectrum. Included by
;; src/macros.asm. (mach/README.md: the contracts.)

;; MACH_START: the resident part (rs_boot) has made the machine ready: the
;; images in their banks, the machine pages set up, the interrupt its own,
;; the core's bank in. The stack goes under the fixed area; the last
;; usable byte is pushed.
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
;; share: three eighths, as on the TRS-80 (strings, compiled code, the
;; names of every symbol read). DE is free here.
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
    db "A Lisp machine for the ZX Spectrum",13,10,0
mend

;; SYS_RESET: the machine starts afresh, into its menu
macro SYS_RESET
    jp M_QUIT
mend
