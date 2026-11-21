;; CPC Lisp -- the memory map, on the ZX Spectrum +2A with a DivMMC.
;;
;; &0000-&3FFF is the 48 BASIC ROM (its calculator and font), or the
;; DivMMC's EEPROM and a page of its RAM while a machine routine runs. Bank
;; 5 is always at &4000, bank 2 at &8000: from &4000 to &BFFF is ours and
;; always there. &C000-&FFFF shows one of banks 0, 1, 3, 4, 6, 7: the six
;; images.
;;
;;   &4000-&5AFF  the screen
;;   &5B00-&5BFF  the 128K ROMs' own (BANK_M, BANK678 are kept)
;;   &5C00-&5CB5  48 BASIC's variables: the calculator needs them
;;   &5CB6-&5CFF  the calculator's stack
;;   &5D00-&5E00  the interrupt's table (IM 2), then the resident part:
;;                SYS_BANK, the jumpblock, the ways to the ROM and esxDOS
;;                (resident.asm)
;;   &6100-&65FF  the low system area: mark stack, symbol hash table,
;;                LIBDEFS, FNBOUND
;;   &6600-&75FF  symbols: 512 slots of 8 bytes
;;   &7600-       cells, the mark bitmap, block space, the stack
;;   &BB00-&BFFF  fixed variables and buffers

LOWMEM            equ #6100         ; the low system area starts here
MARKSTK           equ #6100         ; 256 words
MARKSTK_END       equ #6300
OBARRAY           equ #6300         ; NBUCKETS words, each a list of symbols
NBUCKETS          equ 64
OBARRAY_END       equ OBARRAY+2*NBUCKETS
LIBDEFS           equ OBARRAY_END   ; NSYMS bits: the symbol's definition came
LIBDEFS_END       equ LIBDEFS+NSYMS/8 ;   from library text (SAVE leaves it out)
FNBOUND           equ #6400         ; NSYMS bytes: non-zero if flet or labels
                                    ;   ever bound the symbol (ev_cons)
SYM_LO            equ #6600
NSYMS             equ 512
SYM_HI            equ SYM_LO+8*NSYMS   ; #7600
                  assert LIBDEFS_END <= FNBOUND
                  assert FNBOUND+NSYMS <= SYM_LO
                  assert (FNBOUND and #FF) == 0
CELL_LO           equ SYM_HI

LINEBUF           equ #BB00         ; 256: the line buffer
TOKBUF            equ #BC00         ; 256: the reader's token
VARS              equ #BD00         ; the variables
LIBSCR            equ #BE00         ; 256: scratch for the library
HISTBUF           equ #BF00         ; 128: the line editor's history
TRAMP             equ #BF80         ; 58: the cross-bank trampoline
RDISK             equ #BFC0         ; 64: an entry of the RAM disc's (32)
VARS_END          equ LIBSCR
