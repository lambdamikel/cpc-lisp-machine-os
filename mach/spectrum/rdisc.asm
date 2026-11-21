;; CPC Lisp -- the RAM disc, drive M:, in the DivMMC's free pages: not yet.
;; Until it is, M: says there is none.

;; rd_is: HL = a name -> Z if it is on M:. HL kept.
rd_is:
    inc hl
    ld a,(hl)
    dec hl
    cp ':'
    ret nz
    ld a,(hl)
    or #20
    cp 'm'
    ret

rd_getc:
rd_putc:
rd_close:
rd_delete:
b_m_rdin:
b_m_rdout:
    jp f_fail
b_m_rdcat:
    ret
