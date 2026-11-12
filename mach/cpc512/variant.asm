;; CPC Lisp -- what the 512K CPC and the plain 6128 (mach/cpc6128, links to
;; these files) do differently in the resident part; jumps.asm includes it.

RESIDENT        equ #A160       ; where the resident part starts (jumps.asm)
RAMDISC         equ 1           ; 1: a RAM disc in the expansion, with its
                                ;   copying and file routines here
