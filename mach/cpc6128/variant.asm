;; CPC Lisp -- what the plain 6128 does differently in the resident part
;; (mach/cpc512/variant.asm has the 512K CPC's); jumps.asm includes it.

RESIDENT        equ #A2F0       ; no RAM disc here: the resident part is
RAMDISC         equ 0           ;   smaller, and block space bigger
