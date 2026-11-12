;; CPC Lisp -- the 512K CPC's resident part: where its entries are. It is
;; loaded at RESIDENT by LISP.BIN (loader.asm) and stays there, in the main
;; RAM, which is always mapped at &0000-&BFFF; the Lisp's code is in the
;; expansion's banks, one at a time at &C000 (configuration C1: block 3 of
;; the bank), where the screen's RAM is otherwise (resident.asm).

RESIDENT        equ #A000       ; the resident part, to RESIDENT_END: under
                                ;   the disc ROM's workspace (KL ROM WALK
                                ;   leaves &A6F7 on a 6128 or a 464 with a
                                ;   DDI-1: more ROMs, less)
RS_BANK         equ RESIDENT+0  ; SYS_BANK: C = a bank -> C = the one before
RS_CURBANK      equ RESIDENT+3  ; SYS_CURBANK: -> A = the bank at &C000
RS_RAMRD        equ RESIDENT+6  ; HL -> A = the byte in the main RAM there
RS_RAMWR        equ RESIDENT+9  ; HL, A -> the byte written to the main RAM
RS_RESET        equ RESIDENT+12 ; the main RAM's screen in, then RST 0
RS_VIDINIT      equ RESIDENT+15 ; the function editor's renderer (frcode.asm)
RS_VIDCHAR      equ RESIDENT+18
FWJB            equ RESIDENT+21 ; the firmware's trampolines, 5 bytes each
RESIDENT_END    equ #A6F0
