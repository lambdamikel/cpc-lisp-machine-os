;; CPC Lisp -- what the 512K CPC and the plain 6128 (mach/cpc6128, links to
;; these files) do differently in the resident part; jumps.asm includes it.

RESIDENT        equ #A160       ; where the resident part starts (jumps.asm)
RAMDISC         equ 1           ; 1: a RAM disc in the expansion, with its
                                ;   copying and file routines here
XBUF            equ 1           ; the disc files' buffers in the RAM disc's
XB_UNITS        equ 1           ;   top unit, given up -- bank 7's block 3
XB_IN           equ #4000       ;   with eight banks; seen at &4000
XB_OUT          equ #4800       ;   (RD_XBCFG, the loader's xb_cfgs): an
XB_CAT          equ #5000       ;   input file's 2 KB, an output file's, 4 KB
                                ;   for CAS CATALOG (VDOS 2.0 fills 4 KB),
XB_FONT         equ #6000       ;   the function editor's font copy (768)
