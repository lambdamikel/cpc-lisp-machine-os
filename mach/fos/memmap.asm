;; CPC Lisp on FutureOS itself -- the memory map. FutureOS keeps &A000-&BFFF
;; (its file tagging bytes, its disc buffers, its variables and stack) while
;; Lisp runs, so the fixed area and the resident part are below it: the
;; heap is &1500-&8FFF. Otherwise as on the CPC (mach/cpc/memmap.asm).
;; (variant.asm comes first, through firmware.asm and jumps.asm.)

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

LINEBUF           equ #9B00         ; 256: the EDIT buffer
TOKBUF            equ #9C00         ; 256: the reader's token
VARS              equ #9D00         ; the variables
LIBSCR            equ #9E00         ; 256: scratch for the library ROM
HISTBUF           equ #9F00         ; 128: the line editor's history
TRAMP             equ #9F80         ; 58: the cross-ROM trampoline, copied at boot
RDISK             equ #9FC0         ; 64: the RAM disc's state
VARS_END          equ LIBSCR
                  assert LINEBUF == RESIDENT_END

;; The images' banks: bank k (SYS_BANK) is configuration BANK_CFGS[k],
;; block 3 of an expansion bank at &C000 (C1 + 8 x bank). Bank 3 is skipped:
;; on Revaldinho's card in configuration 8 (FutureOS on a 464) it is the
;; base RAM's shadow. Bank 6 is the machine page (page.asm), bank 7's
;; block 3; the core finds no library signature there.
NBANKS            equ 8
macro BANK_CFGS
    db #C1,#C9,#D1,#E1,#E9,#F1,#F9,#F9
mend
