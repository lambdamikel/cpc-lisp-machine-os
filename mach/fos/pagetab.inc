;; the machine page's jump table (made by tools/fos/mkfw.py: do not edit)
    jp p_KM_WAIT_CHAR
    jp p_KM_READ_CHAR
    jp p_KM_CHAR_RETURN
    jp p_none                   ; KM_TEST_KEY (the resident part's)
    jp p_KM_GET_JOYSTICK
    jp p_TXT_OUTPUT
    jp p_TXT_WR_CHAR
    jp p_TXT_RD_CHAR
    jp p_TXT_SET_GRAPHIC
    jp p_TXT_WIN_ENABLE
    jp p_TXT_GET_WINDOW
    jp p_TXT_CLEAR_WINDOW
    jp p_TXT_SET_CURSOR
    jp p_TXT_GET_CURSOR
    jp p_TXT_CUR_ENABLE
    jp p_TXT_CUR_DISABLE
    jp p_TXT_CUR_ON
    jp p_TXT_CUR_OFF
    jp p_TXT_SET_PEN
    jp p_TXT_GET_PEN
    jp p_TXT_SET_PAPER
    jp p_TXT_GET_PAPER
    jp p_TXT_INVERSE
    jp p_TXT_SET_BACK
    jp p_TXT_GET_MATRIX
    jp p_TXT_SET_MATRIX
    jp p_TXT_SET_M_TABLE
    jp p_TXT_GET_M_TABLE
    jp p_GRA_MOVE_ABSOLUTE
    jp p_GRA_MOVE_RELATIVE
    jp p_GRA_ASK_CURSOR
    jp p_GRA_SET_ORIGIN
    jp p_GRA_GET_ORIGIN
    jp p_GRA_CLEAR_WINDOW
    jp p_GRA_SET_PEN
    jp p_GRA_GET_PEN
    jp p_GRA_SET_PAPER
    jp p_GRA_PLOT_ABSOLUTE
    jp p_GRA_PLOT_RELATIVE
    jp p_GRA_TEST_ABSOLUTE
    jp p_GRA_TEST_RELATIVE
    jp p_GRA_LINE_ABSOLUTE
    jp p_GRA_LINE_RELATIVE
    jp p_SCR_GET_LOCATION
    jp p_SCR_SET_MODE
    jp p_SCR_GET_MODE
    jp p_SCR_DOT_POSITION
    jp p_SCR_NEXT_BYTE
    jp p_SCR_PREV_BYTE
    jp p_SCR_INK_ENCODE
    jp p_SCR_SET_INK
    jp p_SCR_SET_BORDER
    jp p_SCR_SET_FLASHING
    jp p_SCR_FILL_BOX
    jp p_SCR_SW_ROLL
    jp p_SCR_ACCESS
    jp p_CAS_IN_OPEN
    jp p_CAS_IN_CLOSE
    jp p_CAS_IN_ABANDON
    jp p_CAS_IN_CHAR
    jp p_CAS_OUT_OPEN
    jp p_CAS_OUT_CLOSE
    jp p_CAS_OUT_ABANDON
    jp p_CAS_OUT_CHAR
    jp p_CAS_CATALOG
    jp p_SOUND_QUEUE
    jp p_SOUND_CHECK
    jp p_SOUND_RELEASE
    jp p_SOUND_HOLD
    jp p_SOUND_CONTINUE
    jp p_SOUND_AMPL_ENVELOPE
    jp p_SOUND_TONE_ENVELOPE
    jp p_KL_FIND_COMMAND
    jp p_none                   ; KL_TIME_PLEASE (the resident part's)
    jp p_none                   ; KL_L_ROM_ENABLE (the resident part's)
    jp p_none                   ; KL_ROM_RESTORE (the resident part's)
    jp p_none                   ; KL_ROM_SELECT (the resident part's)
    jp p_none                   ; KL_CURR_SELECTION (the resident part's)
    jp p_KL_FAR_PCHL
    jp p_none                   ; MC_WAIT_FLYBACK (the resident part's)
    jp p_EDIT_464
    jp p_EDIT_6128
