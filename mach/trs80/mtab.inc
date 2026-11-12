;; made by tools/trs80/mkjumps.py: the machine page's table (page.asm)
    assert $ == MTAB+2*J_CON_PUTC
    dw m_con_putc
    assert $ == MTAB+2*J_CON_WRCH
    dw m_con_wrch
    assert $ == MTAB+2*J_CON_RDCH
    dw m_con_rdch
    assert $ == MTAB+2*J_CON_GETCUR
    dw m_con_getcur
    assert $ == MTAB+2*J_CON_SETCUR
    dw m_con_setcur
    assert $ == MTAB+2*J_CON_CURON
    dw m_con_curon
    assert $ == MTAB+2*J_CON_CUROFF
    dw m_con_curoff
    assert $ == MTAB+2*J_CON_CURENA
    dw m_con_curena
    assert $ == MTAB+2*J_CON_CURDIS
    dw m_con_curdis
    assert $ == MTAB+2*J_CON_INVERSE
    dw m_con_inverse
    assert $ == MTAB+2*J_CON_GETWIN
    dw m_con_getwin
    assert $ == MTAB+2*J_CON_CLS
    dw m_con_cls
    assert $ == MTAB+2*J_CON_PEN
    dw m_con_pen
    assert $ == MTAB+2*J_CON_PAPER
    dw m_con_paper
    assert $ == MTAB+2*J_KEY_READ
    dw m_key_read
    assert $ == MTAB+2*J_KEY_WAIT
    dw m_key_wait
    assert $ == MTAB+2*J_KEY_UNREAD
    dw m_key_unread
    assert $ == MTAB+2*J_KEY_TEST
    dw m_key_test
    assert $ == MTAB+2*J_VID_MODE
    dw m_vid_mode
    assert $ == MTAB+2*J_VID_INK
    dw m_vid_ink
    assert $ == MTAB+2*J_VID_BORDER
    dw m_vid_border
    assert $ == MTAB+2*J_VID_FRAME
    dw m_vid_frame
    assert $ == MTAB+2*J_VID_FILLBOX
    dw m_vid_fillbox
    assert $ == MTAB+2*J_GFX_PLOT
    dw m_gfx_plot
    assert $ == MTAB+2*J_GFX_PLOTR
    dw m_gfx_plotr
    assert $ == MTAB+2*J_GFX_MOVE
    dw m_gfx_move
    assert $ == MTAB+2*J_GFX_MOVER
    dw m_gfx_mover
    assert $ == MTAB+2*J_GFX_LINE
    dw m_gfx_line
    assert $ == MTAB+2*J_GFX_LINER
    dw m_gfx_liner
    assert $ == MTAB+2*J_GFX_TEST
    dw m_gfx_test
    assert $ == MTAB+2*J_GFX_TESTR
    dw m_gfx_testr
    assert $ == MTAB+2*J_GFX_WHERE
    dw m_gfx_where
    assert $ == MTAB+2*J_GFX_ORIGIN
    dw m_gfx_origin
    assert $ == MTAB+2*J_GFX_PEN
    dw m_gfx_pen
    assert $ == MTAB+2*J_GFX_PAPER
    dw m_gfx_paper
    assert $ == MTAB+2*J_GFX_CLEAR
    dw m_gfx_clear
    assert $ == MTAB+2*J_SND_QUEUE
    dw m_snd_queue
    assert $ == MTAB+2*J_FILE_IOPEN
    dw m_file_iopen
    assert $ == MTAB+2*J_FILE_ICLOSE
    dw m_file_iclose
    assert $ == MTAB+2*J_FILE_IABANDON
    dw m_file_iabandon
    assert $ == MTAB+2*J_FILE_GETC
    dw m_file_getc
    assert $ == MTAB+2*J_FILE_OOPEN
    dw m_file_oopen
    assert $ == MTAB+2*J_FILE_OCLOSE
    dw m_file_oclose
    assert $ == MTAB+2*J_FILE_OABANDON
    dw m_file_oabandon
    assert $ == MTAB+2*J_FILE_PUTC
    dw m_file_putc
    assert $ == MTAB+2*J_FILE_CAT
    dw m_file_cat
    assert $ == MTAB+2*J_FP_MOVE
    dw m_fp_move
    assert $ == MTAB+2*J_FP_INT2R
    dw m_fp_int2r
    assert $ == MTAB+2*J_FP_BIN2R
    dw m_fp_bin2r
    assert $ == MTAB+2*J_FP_R2INT
    dw m_fp_r2int
    assert $ == MTAB+2*J_FP_R2BIN
    dw m_fp_r2bin
    assert $ == MTAB+2*J_FP_FIX
    dw m_fp_fix
    assert $ == MTAB+2*J_FP_INT
    dw m_fp_int
    assert $ == MTAB+2*J_FP_EXP10
    dw m_fp_exp10
    assert $ == MTAB+2*J_FP_ADD
    dw m_fp_add
    assert $ == MTAB+2*J_FP_RSUB
    dw m_fp_rsub
    assert $ == MTAB+2*J_FP_MUL
    dw m_fp_mul
    assert $ == MTAB+2*J_FP_DIV
    dw m_fp_div
    assert $ == MTAB+2*J_FP_CMP
    dw m_fp_cmp
    assert $ == MTAB+2*J_FP_NEG
    dw m_fp_neg
    assert $ == MTAB+2*J_FP_SGN
    dw m_fp_sgn
    assert $ == MTAB+2*J_FP_ANGLE
    dw m_fp_angle
    assert $ == MTAB+2*J_FP_PI
    dw m_fp_pi
    assert $ == MTAB+2*J_FP_SQR
    dw m_fp_sqr
    assert $ == MTAB+2*J_FP_POW
    dw m_fp_pow
    assert $ == MTAB+2*J_FP_LOG
    dw m_fp_log
    assert $ == MTAB+2*J_FP_EXP
    dw m_fp_exp
    assert $ == MTAB+2*J_FP_SIN
    dw m_fp_sin
    assert $ == MTAB+2*J_FP_COS
    dw m_fp_cos
    assert $ == MTAB+2*J_FP_TAN
    dw m_fp_tan
    assert $ == MTAB+2*J_FP_ATN
    dw m_fp_atn
    assert $ == MTAB+2*J_SYS_TIME
    dw m_sys_time
    assert $ == MTAB+2*J_M_EDIT
    dw m_m_edit
    assert $ == MTAB+2*J_M_QUIT
    dw m_m_quit
    assert $ == MTAB+2*J_M_INKMODE
    dw m_m_inkmode
    assert $ == MTAB+2*J_M_RDIN
    dw m_m_rdin
    assert $ == MTAB+2*J_M_RDOUT
    dw m_m_rdout
    assert $ == MTAB+2*J_M_RDCAT
    dw m_m_rdcat
    assert $ == MTAB+2*J_M_DELETE
    dw m_m_delete
    assert $ == MTAB+2*J_M_FILL
    dw m_m_fill
