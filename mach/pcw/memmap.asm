;; CPC Lisp -- the memory map, on an Amstrad PCW 8256/8512.
;;
;; Blocks 4, 5, 6 at &0000, &4000, &8000 are the Lisp's RAM, always there
;; (but for a moment at &4000: the WINDOW, where a machine routine sees the
;; screen, the keyboard or the RAM disc -- RS_P1 says what is there, and
;; nothing of the Lisp's is touched meanwhile); &C000 shows one of the six
;; images, or a machine page while one of its routines runs.
;;
;;   &0000-&04FF  the resident part: RST 0, the interrupt (IM 1, &0038),
;;                SYS_BANK, the jumpblock, the ways between the blocks
;;                (resident.asm)
;;   &0500-&09FF  the low system area: mark stack, symbol hash table,
;;                LIBDEFS, FNBOUND
;;   &0A00-&19FF  symbols: 512 slots of 8 bytes
;;   &1A00-       cells, the mark bitmap, block space, the stack
;;   &BB00-&BFFF  fixed variables and buffers
;;
;; (Below &0500 a value is an immediate -- a character, a marker -- so no
;; Lisp object lives there: it is free for the resident part.)

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

LINEBUF           equ #BB00         ; 256: the line buffer
TOKBUF            equ #BC00         ; 256: the reader's token
VARS              equ #BD00         ; the variables
LIBSCR            equ #BE00         ; 256: scratch for the library
HISTBUF           equ #BF00         ; 128: the line editor's history
TRAMP             equ #BF80         ; 58: the cross-bank trampoline
RDISK             equ #BFC0         ; 64: an entry of the RAM disc's (32)
VARS_END          equ LIBSCR
