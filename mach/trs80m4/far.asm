;; CPC Lisp -- far arrays on the Model 4: there is no RAM disc for them
;; (library part 1: lib/farray.asm includes this). The layout is any; the
;; first access says why.

FA_DIR0     equ 32
FA_ESIZE    equ 32
FA_NENT     equ 31
FA_USED     equ 0
FA_NAME     equ 1
FA_PAD      equ ' '
FA_START    equ 13
FA_LEN      equ 16
FA_W        equ 3

fa_xfer:
    ld hl,fa_m_nodisc
    ld de,UNBOUND
    jp lib_error
fa_m_nodisc: db "no RAM disc on a Model 4",0
