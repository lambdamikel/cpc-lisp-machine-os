;; CPC Lisp -- the memory map, on the TRS-80 Model 4 with 128 KB under
;; LS-DOS 6.3.1.
;;
;; LS-DOS keeps &0000-&25FF (its library commands also &2600-&2FFF: the
;; Lisp runs none). The lower 32 KB is always there; &8000-&FFFF is one of
;; three 32 KB banks -- LS-DOS's bank 0 (the upper half of the first
;; 64 KB) and banks 1 and 2 (the second 64 KB) -- each with two images:
;; a slot is half a bank, slots 2-7: bank b's are 2b+2 at &8000 and 2b+3
;; at &C000. The Lisp
;; runs in memory map 3 (all RAM, as LS-DOS does); the screen is in map 2,
;; the Model III's ROM -- its floats -- in map 0, each a moment with the
;; interrupts off.
;;
;;   &2600-&29FF  the resident part (resident.asm)
;;   &2A00-&2EFF  the fixed variables and buffers
;;   &2F00-&33FF  the low system area: mark stack, symbol hash table,
;;                LIBDEFS, FNBOUND
;;   &3400-&3FFF  the machine stack (STACK_TOP: apart from the heap)
;;   &4000-&41FF  the ROM's own RAM, while it does a float (map 0 shows
;;                the ROM, its keyboard and its screen up to &3FFF)
;;   &4200-&51FF  symbols: 512 slots of 8 bytes
;;   &5200-&7FFF  cells, the mark bitmap, block space

LINEBUF           equ #2A00         ; 256: the line buffer
TOKBUF            equ #2B00         ; 256: the reader's token
VARS              equ #2C00         ; the variables
LIBSCR            equ #2D00         ; 256: scratch for the library
HISTBUF           equ #2E00         ; 128: the line editor's history
TRAMP             equ #2E80         ; 58: the cross-bank trampoline
RDISK             equ #2EC0         ; 64: (the RAM disc's on other machines),
FNAMEBUF          equ RDISK         ;   here a file's name for LS-DOS (24),
TK_MODE           equ RDISK+63      ;   and 1 once Talker/80 is in DECtalk mode
VARS_END          equ LIBSCR

MARKSTK           equ #2F00         ; 256 words
MARKSTK_END       equ #3100
LOWMEM            equ #3100         ; the low system area (cleared at boot)
OBARRAY           equ #3100         ; NBUCKETS words, each a list of symbols
NBUCKETS          equ 64
OBARRAY_END       equ OBARRAY+2*NBUCKETS
LIBDEFS           equ OBARRAY_END   ; NSYMS bits: the symbol's definition came
LIBDEFS_END       equ LIBDEFS+NSYMS/8 ;   from library text (SAVE leaves it out)
FNBOUND           equ #3200         ; NSYMS bytes: non-zero if flet or labels
                                    ;   ever bound the symbol (ev_cons)
STACK_TOP         equ #4000         ; the machine stack, down from here,
STACK_SIZE        equ #0C00         ;   3 KB (~250 calls deep)
ROMRAM            equ #4000         ; the ROM's RAM for floats: &4000-&41FF
SYM_LO            equ #4200
NSYMS             equ 512
SYM_HI            equ SYM_LO+8*NSYMS   ; #5200
                  assert LIBDEFS_END <= FNBOUND
                  assert FNBOUND+NSYMS <= STACK_TOP-STACK_SIZE
                  assert (FNBOUND and #FF) == 0
CELL_LO           equ SYM_HI
MEMTOP            equ #7FFF         ; the heap's last byte
LIB_MIXED         equ 1             ; parts at &8000 and &C000 (liborgs)
