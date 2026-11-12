;; CPC Lisp -- the memory map, on the TRS-80 with X-MEM/80.
;;
;; &0000-&3FFF is ROM, the keyboard and the screen; LDOS keeps &4000-&51FF.
;; From &5200 to &BFFF is ours and always there: &8000-&BFFF is X-MEM page
;; HEAPPAGE, which never moves. &C000-&FFFF shows one code page at a time.
;;
;;   &5200-&53FF  the resident part: SYS_BANK, the jumpblock (resident.asm)
;;   &5400-&58FF  the low system area: mark stack, symbol hash table,
;;                LIBDEFS, FNBOUND
;;   &5900-&68FF  symbols: 512 slots of 8 bytes
;;   &6900-       cells, the mark bitmap, block space, the stack
;;   &BB00-&BFFF  fixed variables and buffers

LOWMEM            equ #5400         ; the low system area starts here
MARKSTK           equ #5400         ; 256 words
MARKSTK_END       equ #5600
OBARRAY           equ #5600         ; NBUCKETS words, each a list of symbols
NBUCKETS          equ 64
OBARRAY_END       equ OBARRAY+2*NBUCKETS
LIBDEFS           equ OBARRAY_END   ; NSYMS bits: the symbol's definition came
LIBDEFS_END       equ LIBDEFS+NSYMS/8 ;   from library text (SAVE leaves it out)
FNBOUND           equ #5700         ; NSYMS bytes: non-zero if flet or labels
                                    ;   ever bound the symbol (ev_cons)
SYM_LO            equ #5900
NSYMS             equ 512
SYM_HI            equ SYM_LO+8*NSYMS   ; #6900
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
RDISK             equ #BFC0         ; 64: an entry of the RAM disc's (32),
TK_MODE           equ RDISK+63      ;   and 1 once Talker/80 is in DECtalk
                                    ;   mode this Lisp (m_init clears it)
VARS_END          equ LIBSCR
