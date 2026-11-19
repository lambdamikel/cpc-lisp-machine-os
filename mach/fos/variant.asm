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
IN_CFG0         equ #F4         ; the input file: bank 6's blocks 0-2
OUT_CFG0        equ #EC         ; the output file: bank 5's blocks 0-2
FILE_MAXREC     equ 384         ;   (48 KB each)
XB_UNITS        equ 1           ; (the 512K RAM disc's, refusing here)
PAGE_BANK       equ 6           ; the machine page (page.asm): SYS_BANK's bank
PAGE_CFG        equ #F9         ;   6, bank 7's block 3 at &C000 (C1 + 8 x 7)
LORAM           equ #0100       ; LISP.64K loads each image here first
FOS_KEEP0       equ #FF00       ; in the page: FutureOS's &0000-&00FF, kept
                                ;   by LISP.64K for the way back
