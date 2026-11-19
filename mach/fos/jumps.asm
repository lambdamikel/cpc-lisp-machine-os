;; CPC Lisp on FutureOS itself -- the resident part's entries (resident.asm),
;; at the same offsets as the 512K CPC's (mach/cpc512/jumps.asm), whose
;; shared files use them by name.

    include "variant.asm"
RS_BANK         equ RESIDENT+0  ; SYS_BANK: C = a bank -> C = the one before
RS_CURBANK      equ RESIDENT+3  ; SYS_CURBANK: -> A = the bank at &C000
RS_RAMRD        equ RESIDENT+6  ; HL -> A = the byte in the main RAM there
RS_RAMWR        equ RESIDENT+9  ; HL, A -> the byte written to the main RAM
RS_RESET        equ RESIDENT+12 ; back to FutureOS's desktop
RS_VIDINIT      equ RESIDENT+15 ; the function editor's renderer (frcode.asm)
RS_VIDCHAR      equ RESIDENT+18
RS_XFER         equ RESIDENT+21 ; the RAM disc's copying: A = its unit
RS_FGETC        equ RESIDENT+24 ; FILE_GETC
RS_FPUTC        equ RESIDENT+27 ; FILE_PUTC
RS_FICLOSE      equ RESIDENT+30 ; FILE_ICLOSE
RS_FIABANDON    equ RESIDENT+33 ; FILE_IABANDON
RS_FOCLOSE      equ RESIDENT+36 ; FILE_OCLOSE
RS_FOABANDON    equ RESIDENT+39 ; FILE_OABANDON
RS_FM           equ RESIDENT+42 ; a maths routine: IX = its entry in FM_JB
FWJB            equ RESIDENT+45 ; the trampolines, 5 bytes each (fwtab.inc)

;; the RAM disc's state (the 512K CPC's layout, for its shared files)
RS_RD           equ RESIDENT_END-16
;; the maths package's jumpblock: "jp address" for each routine, in the
;; 464's order (M_MOVE first), the lower ROM's real addresses -- LISP.64K
;; reads them from the lower ROM's own jumpblock table (fp.asm)
FM_JB           equ RS_RD-48*3
RD_BANK         equ RS_RD+0
RD_IN           equ RS_RD+1
RD_OUT          equ RS_RD+2
RD_IBUF         equ RS_RD+3
RD_OBUF         equ RS_RD+5
RD_VGETC        equ RS_RD+7
RD_VPUTC        equ RS_RD+9
RD_VCLOSE       equ RS_RD+11
RD_NBANKS       equ RS_RD+13
RD_STATELEN     equ 14
