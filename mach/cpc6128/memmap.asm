;; CPC Lisp -- the memory map, on a plain CPC 6128 (mach/cpc6128, an
;; overlay on mach/cpc512: what is not here is there).
;;
;; Included by src/defs.asm. Another machine lays out the same areas where
;; its RAM is: what the portable code needs is in mach/README.md.
;;
;;   &0040-&04FF  low system area: mark stack, symbol hash table, LIBDEFS,
;;                FNBOUND.
;;                The firmware sees its ROM here, so nothing the firmware reads goes here.
;;                Words below &0500 are also the immediates (characters,
;;                markers, headers), which is why no object lives here.
;;   &0500-&14FF  symbols: 512 slots of 8 bytes
;;   &1500-       cells: 4 bytes each, conses and typed cells
;;   then         the mark bitmap, block space (strings), the machine stack,
;;                sized at boot from what the ROM walk left (V_MEMTOP)
;;   &AC00-&B0FF  fixed variables and buffers. The firmware enters ROM 0 with
;;                HL=&ABFF and BC=&B0FF on every model: this is the area BASIC
;;                keeps for itself, and it is ours now.

LOWMEM            equ #0040         ; the low system area starts here
MARKSTK           equ #0040         ; 256 words
MARKSTK_END       equ #0240
OBARRAY           equ #0240         ; NBUCKETS words, each a list of symbols
NBUCKETS          equ 64
OBARRAY_END       equ OBARRAY+2*NBUCKETS
LIBDEFS           equ OBARRAY_END   ; NSYMS bits: the symbol's definition came
LIBDEFS_END       equ LIBDEFS+NSYMS/8 ;   from library text (SAVE leaves it out)

FNBOUND           equ #0300         ; NSYMS bytes: non-zero if flet or labels
                                    ;   ever bound the symbol (ev_cons)
SYM_LO            equ #0500
NSYMS             equ 512
SYM_HI            equ SYM_LO+8*NSYMS   ; #1500
                  assert LIBDEFS_END <= FNBOUND
                  assert FNBOUND+NSYMS <= SYM_LO
                  assert (FNBOUND and #FF) == 0
CELL_LO           equ SYM_HI

LINEBUF           equ #AC00         ; 256: the EDIT buffer
TOKBUF            equ #AD00         ; 256: the reader's token
VARS              equ #AE00         ; the variables, below
LIBSCR            equ #AF00         ; 256: scratch for the library ROM
HISTBUF           equ #B000         ; 128: the line editor's history
TRAMP             equ #B080         ; 58: the cross-ROM trampoline, copied at boot
RDISK             equ #B0C0         ; 64: the RAM disc's state (ramdisc.asm)
VARS_END          equ LIBSCR

;; The images: the core in block 7 at &C000 (configuration C1), as in ROM;
;; library parts 0-2 in blocks 4-6 at &4000 (C4-C6), part 3 in the main
;; RAM's &4000 (C0). So the parts are assembled at &4000 (LIB_ORG), and the
;; main RAM's &4000-&7FFF is no heap: the cells end at &4000 (CELL_TOP),
;; block space and the stack are above &8000 (BLK_LO), seen in every one.
LIB_ORG           equ #4000
CELL_TOP          equ #4000
BLK_LO            equ #8000
NBANKS            equ 5             ; the core and the four parts: no VM
STACK_SIZE        equ 3328          ; 3.25 KB (some 250 calls deep): block
                                    ;   space then holds two file buffers
macro BANK_CFGS
    db #C1,#C4,#C5,#C6,#C0,#C0,#C0,#C0
mend
