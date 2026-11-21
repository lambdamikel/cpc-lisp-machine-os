;; CPC Lisp -- the far arrays' way into the RAM disc (library part 1:
;; lib/farray.asm includes this): the directory's layout, as
;; mach/spectrum/rdisc.asm keeps it in the DivMMC's pages, and fa_xfer --
;; its rd_xfer again: keep them in step. (The RAM disc is not there yet:
;; until it is, M: refuses before anything comes here.)

FA_DIR0     equ 32              ; entry 0
FA_ESIZE    equ 32              ; [1 in use][name 12, blanks after][start 3]
FA_NENT     equ 31              ;   [length 3]
FA_USED     equ 0
FA_NAME     equ 1
FA_PAD      equ ' '
FA_START    equ 13
FA_LEN      equ 16
FA_W        equ 3

;; fa_xfer: A = 0: BC bytes from the disc at FA_OFF to RAM at HL; 1: from
;; RAM at HL to the disc (not yet)
fa_xfer:
    ret
