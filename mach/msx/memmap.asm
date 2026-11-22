;; CPC Lisp -- the memory map, on an MSX1 with a memory mapper, under
;; MSX-DOS 2 (Nextor).
;;
;; All four pages are the mapper's RAM (LISP.COM runs in DOS's TPA). Pages
;; 0 and 1 (DOS's TPA segments) are always there: the resident part and
;; the Lisp's RAM. Page 2 (&8000-&BFFF) shows a machine page (A or B,
;; page.asm, pageb.asm) while one of its routines runs, or a RAM disc
;; segment for one copy, or DOS's own TPA segment. Page 3 (&C000-&FFFF)
;; shows one of the six images -- DOS's segment there, with the BIOS's
;; and DOS's variables, only while the resident part calls DOS or the
;; ROM (resident.asm).
;;
;;   &0000-&00FF  DOS's: its jumps (&0005, the slot routines), the
;;                interrupt's at &0038 (ours while Lisp runs), the
;;                command line
;;   &0100-&04FF  the resident part: SYS_BANK, the jumpblock, the
;;                interrupt, the ways to DOS and the ROM (resident.asm)
;;   &0500-&09FF  the low system area: mark stack, symbol hash table,
;;                LIBDEFS, FNBOUND
;;   &0A00-&19FF  symbols: 512 slots of 8 bytes
;;   &1A00-       cells, the mark bitmap, block space, the stack
;;   &7B00-&7FFF  fixed variables and buffers
;;
;; (Below &0500 a value is an immediate -- a character, a marker -- so no
;; Lisp object lives there: it is free for DOS and the resident part.)

LOWMEM            equ #0500         ; the low system area starts here
MARKSTK           equ #0500         ; 256 words
MARKSTK_END       equ #0700
OBARRAY           equ #0700         ; NBUCKETS words, each a list of symbols
NBUCKETS          equ 64
OBARRAY_END       equ OBARRAY+2*NBUCKETS
LIBDEFS           equ OBARRAY_END   ; NSYMS bits: the symbol's definition came
LIBDEFS_END       equ LIBDEFS+NSYMS/8 ;   from library text (SAVE leaves it out)
FNBOUND           equ #0800         ; NSYMS bytes: non-zero if flet or labels
                                    ;   ever bound the symbol (ev_cons)
SYM_LO            equ #0A00
NSYMS             equ 512
SYM_HI            equ SYM_LO+8*NSYMS   ; #1A00
                  assert LIBDEFS_END <= FNBOUND
                  assert FNBOUND+NSYMS <= SYM_LO
                  assert (FNBOUND and #FF) == 0
CELL_LO           equ SYM_HI

LINEBUF           equ #7B00         ; 256: the line buffer
TOKBUF            equ #7C00         ; 256: the reader's token
VARS              equ #7D00         ; the variables
LIBSCR            equ #7E00         ; 256: scratch for the library
HISTBUF           equ #7F00         ; 128: the line editor's history
TRAMP             equ #7F80         ; 58: the cross-bank trampoline
RDISK             equ #7FC0         ; 64: an entry of the RAM disc's (32)
VARS_END          equ LIBSCR
