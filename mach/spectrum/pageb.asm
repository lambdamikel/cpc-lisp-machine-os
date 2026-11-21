;; CPC Lisp -- the Spectrum's machine page B: files, floats, the RAM disc
;; (page.asm includes this, after page A). Assembled for &2000, where the
;; resident part maps it; in LISPM.ROM after page A. Its routines' entries
;; in the table (MTAB, in page A) have bit 15 set: each name m_... is its
;; routine's address + &8000.

PB_DATA     equ #3B00           ; this page's data (no code at &3D00-&3DFF)

    org #2000,#4000
    jp b_init                   ; rs_boot calls this once
    db "ZX SPECTRUM MACHINE PAGE B",0

;; b_init: from rs_boot, once
b_init:
    ret

;; ---------------------------------------------------------------------------
;; FILES (not yet)

b_file_iopen:
b_file_oopen:
b_file_getc:
b_file_putc:
b_m_rdin:
b_m_rdout:
b_m_delete:
    or a
    ret
b_file_iclose:
b_file_iabandon:
b_file_oclose:
b_file_oabandon:
b_m_drive:
    scf
    ret
b_file_cat:
b_m_rdcat:
    ret

;; ---------------------------------------------------------------------------
;; FLOATS (not yet)

b_fp_move:
b_fp_int2r:
b_fp_bin2r:
b_fp_r2int:
b_fp_r2bin:
b_fp_fix:
b_fp_int:
b_fp_exp10:
b_fp_add:
b_fp_rsub:
b_fp_mul:
b_fp_div:
b_fp_cmp:
b_fp_neg:
b_fp_sgn:
b_fp_angle:
b_fp_pi:
b_fp_sqr:
b_fp_pow:
b_fp_log:
b_fp_exp:
b_fp_sin:
b_fp_cos:
b_fp_tan:
b_fp_atn:
    or a
    ret

page_b_end:
    print "machine page B: ",page_b_end-#2000," bytes"
    assert page_b_end <= PB_DATA

;; the names in the table: page B's routines, bit 15 set
m_file_iopen    equ b_file_iopen+#8000
m_file_iclose   equ b_file_iclose+#8000
m_file_iabandon equ b_file_iabandon+#8000
m_file_getc     equ b_file_getc+#8000
m_file_oopen    equ b_file_oopen+#8000
m_file_oclose   equ b_file_oclose+#8000
m_file_oabandon equ b_file_oabandon+#8000
m_file_putc     equ b_file_putc+#8000
m_file_cat      equ b_file_cat+#8000
m_fp_move       equ b_fp_move+#8000
m_fp_int2r      equ b_fp_int2r+#8000
m_fp_bin2r      equ b_fp_bin2r+#8000
m_fp_r2int      equ b_fp_r2int+#8000
m_fp_r2bin      equ b_fp_r2bin+#8000
m_fp_fix        equ b_fp_fix+#8000
m_fp_int        equ b_fp_int+#8000
m_fp_exp10      equ b_fp_exp10+#8000
m_fp_add        equ b_fp_add+#8000
m_fp_rsub       equ b_fp_rsub+#8000
m_fp_mul        equ b_fp_mul+#8000
m_fp_div        equ b_fp_div+#8000
m_fp_cmp        equ b_fp_cmp+#8000
m_fp_neg        equ b_fp_neg+#8000
m_fp_sgn        equ b_fp_sgn+#8000
m_fp_angle      equ b_fp_angle+#8000
m_fp_pi         equ b_fp_pi+#8000
m_fp_sqr        equ b_fp_sqr+#8000
m_fp_pow        equ b_fp_pow+#8000
m_fp_log        equ b_fp_log+#8000
m_fp_exp        equ b_fp_exp+#8000
m_fp_sin        equ b_fp_sin+#8000
m_fp_cos        equ b_fp_cos+#8000
m_fp_tan        equ b_fp_tan+#8000
m_fp_atn        equ b_fp_atn+#8000
m_m_rdin        equ b_m_rdin+#8000
m_m_rdout       equ b_m_rdout+#8000
m_m_rdcat       equ b_m_rdcat+#8000
m_m_delete      equ b_m_delete+#8000
m_m_drive       equ b_m_drive+#8000

    defs #4000-$,0
