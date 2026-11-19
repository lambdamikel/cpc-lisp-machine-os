;; CPC Lisp on FutureOS itself (mach/fos): what this machine sets. jumps.asm
;; and memmap.asm include it.

FOSN            equ 1           ; (the shared files' switch, where they differ)
RESIDENT        equ #9000       ; the resident part, in the main RAM below
RESIDENT_END    equ #9B00       ;   FutureOS's &A000-&BFFF; the fixed area
                                ;   above it (memmap.asm), to &9FFF
RAMDISC         equ 0           ; (not yet)
PAGE_BANK       equ 6           ; the machine page (page.asm): SYS_BANK's bank
PAGE_CFG        equ #F9         ;   6, bank 7's block 3 at &C000 (C1 + 8 x 7)
LORAM           equ #0100       ; LISP.64K loads each image here first
FOS_KEEP0       equ #FF00       ; in the page: FutureOS's &0000-&00FF, kept
                                ;   by LISP.64K for the way back
