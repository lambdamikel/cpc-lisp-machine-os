;; CPC Lisp on FutureOS itself (mach/fos): what this machine sets. jumps.asm
;; and memmap.asm include it.

FOSN            equ 1           ; (the shared files' switch, where they differ)
RESIDENT        equ #9000       ; the resident part, in the main RAM below
RESIDENT_END    equ #9B00       ;   FutureOS's &A000-&BFFF; the fixed area
                                ;   above it (memmap.asm), to &9FFF
RAMDISC         equ 0           ; (not yet)
XBUF            equ 1           ; the buffers' block (bank 7's block 1, at
XB_CFG          equ #FD         ;   &4000): the function editor's font, and
XB_FONT         equ #4000       ;   &8000-&8FFF while FutureOS runs (its
XB_HI           equ #5000       ;   loads may use it as a sector buffer)
LOW_CFG         equ #FC         ; &0000-&3FFF while TEISI runs (bank 7's 0)
IN_CFG0         equ #F4         ; the input file: bank 6's blocks 0-2
OUT_CFG0        equ #C4         ; the output file: bank 0's blocks 0-2 (the
                                ;   first in FutureOS's XRAM order: TEISI
                                ;   writes from there)
FILE_MAXREC     equ 384         ;   (48 KB each)
XB_UNITS        equ 1           ; (the 512K RAM disc's, refusing here)
PAGE_BANK       equ 6           ; the machine page (page.asm): SYS_BANK's bank
PAGE_CFG        equ #F9         ;   6, bank 7's block 3 at &C000 (C1 + 8 x 7)
LORAM           equ #0100       ; LISP.64K loads each image here first
FOS_KEEP0       equ #FF00       ; in the page: FutureOS's &0000-&00FF, kept
                                ;   by LISP.64K for the way back,
FOS_KEEPX       equ #FEE0       ;   and its XRAM marks (XRAM_C4..FF, 32)
