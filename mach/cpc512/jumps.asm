;; CPC Lisp -- the 512K CPC's resident part: where its entries are. It is
;; loaded at RESIDENT by LISP.BIN (loader.asm) and stays there, in the main
;; RAM, which is always mapped at &0000-&BFFF; the Lisp's code is in the
;; expansion's banks, one at a time at &C000 (configuration C1: block 3 of
;; the bank), where the screen's RAM is otherwise (resident.asm).

    include "variant.asm"       ; RESIDENT, where the resident part starts:
                                ;   to RESIDENT_END, under the disc ROM's
                                ;   workspace (KL ROM WALK leaves &A6F7 on a
                                ;   6128 or a 464 with a DDI-1: more ROMs,
                                ;   less)
RS_BANK         equ RESIDENT+0  ; SYS_BANK: C = a bank -> C = the one before
RS_CURBANK      equ RESIDENT+3  ; SYS_CURBANK: -> A = the bank at &C000
RS_RAMRD        equ RESIDENT+6  ; HL -> A = the byte in the main RAM there
RS_RAMWR        equ RESIDENT+9  ; HL, A -> the byte written to the main RAM
RS_RESET        equ RESIDENT+12 ; the main RAM's screen in, then RST 0
RS_VIDINIT      equ RESIDENT+15 ; the function editor's renderer (frcode.asm)
RS_VIDCHAR      equ RESIDENT+18
RS_XFER         equ RESIDENT+21 ; A = a configuration (#C4-#C7 + 8 * bank),
                                ;   HL to DE, BC bytes: an LDIR with that
                                ;   bank's block at &4000 (the RAM disc)
RS_FGETC        equ RESIDENT+24 ; FILE_GETC: the RAM disc's, or CAS IN CHAR
RS_FPUTC        equ RESIDENT+27 ; FILE_PUTC
RS_FICLOSE      equ RESIDENT+30 ; FILE_ICLOSE
RS_FIABANDON    equ RESIDENT+33 ; FILE_IABANDON
RS_FOCLOSE      equ RESIDENT+36 ; FILE_OCLOSE
RS_FOABANDON    equ RESIDENT+39 ; FILE_OABANDON
FWJB            equ RESIDENT+42 ; the firmware's trampolines, 5 bytes each
RESIDENT_END    equ #A6F0

;; the RAM disc's state, shared by the resident part and the library's
;; RAM disc (ramdisc.asm); the loader clears it and sets RD_NBANKS
RS_RD           equ RESIDENT_END-16
RD_BANK         equ RS_RD+0     ; the bank of the RAM disc's code
RD_IN           equ RS_RD+1     ; 1: the file open for input is on M:
RD_OUT          equ RS_RD+2     ; 1: the one for output
RD_IBUF         equ RS_RD+3     ; their buffers (a word each)
RD_OBUF         equ RS_RD+5
RD_VGETC        equ RS_RD+7     ; the library's rd_getc, rd_putc, rd_close
RD_VPUTC        equ RS_RD+9
RD_VCLOSE       equ RS_RD+11
RD_NBANKS       equ RS_RD+13    ; the expansion's banks (6-8)
RD_STATELEN     equ 14
