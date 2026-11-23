;; CPC Lisp -- the machine's macros, on the PCW. Included by
;; src/macros.asm. (mach/README.md: the contracts.)

;; MACH_START: the resident part (rs_boot) has made the machine ready: the
;; images in their blocks, the machine pages set up, the interrupt its own,
;; the core's block in. The stack goes under the fixed area (in the block at
;; &8000: never the WINDOW's); the last usable byte is pushed.
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
;; share: a quarter -- some 11 KB here, more than twice a 464's strings
;; (the TRS-80's quarter of its smaller heap ran out: three eighths there)
;; -- and the rest cells. DE is free here.
macro MACH_BLOCKS
    srl h
    rr l
    srl h
    rr l                        ; a quarter
mend

;; FM routine: a maths routine, through the jumpblock
macro FM addr
    call {addr}
mend

;; MACH_TITLE: the banner's second line
macro MACH_TITLE
    db "A Lisp machine for the Amstrad PCW",13,10,0
mend

;; SYS_RESET: the boot program again (there is nothing else to go back to)
macro SYS_RESET
    jp M_QUIT
mend
