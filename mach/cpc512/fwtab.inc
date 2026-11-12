;; the trampolines (made by tools/cpc512/mkfw.py: do not edit)
    assert $ == FWJB+5*0
    call fwc : dw #BB06           ; KM_WAIT_CHAR
    assert $ == FWJB+5*1
    call fwc : dw #BB09           ; KM_READ_CHAR
    assert $ == FWJB+5*2
    call fwc : dw #BB0C           ; KM_CHAR_RETURN
    assert $ == FWJB+5*3
    call fwc : dw #BB1E           ; KM_TEST_KEY
    assert $ == FWJB+5*4
    call fwc : dw #BB24           ; KM_GET_JOYSTICK
    assert $ == FWJB+5*5
    call fwc : dw #BB5A           ; TXT_OUTPUT
    assert $ == FWJB+5*6
    call fwc : dw #BB5D           ; TXT_WR_CHAR
    assert $ == FWJB+5*7
    call fwc : dw #BB60           ; TXT_RD_CHAR
    assert $ == FWJB+5*8
    call fwc : dw #BB63           ; TXT_SET_GRAPHIC
    assert $ == FWJB+5*9
    call fwc : dw #BB66           ; TXT_WIN_ENABLE
    assert $ == FWJB+5*10
    call fwc : dw #BB69           ; TXT_GET_WINDOW
    assert $ == FWJB+5*11
    call fwc : dw #BB6C           ; TXT_CLEAR_WINDOW
    assert $ == FWJB+5*12
    call fwc : dw #BB75           ; TXT_SET_CURSOR
    assert $ == FWJB+5*13
    call fwc : dw #BB78           ; TXT_GET_CURSOR
    assert $ == FWJB+5*14
    call fwc : dw #BB7B           ; TXT_CUR_ENABLE
    assert $ == FWJB+5*15
    call fwc : dw #BB7E           ; TXT_CUR_DISABLE
    assert $ == FWJB+5*16
    call fwc : dw #BB81           ; TXT_CUR_ON
    assert $ == FWJB+5*17
    call fwc : dw #BB84           ; TXT_CUR_OFF
    assert $ == FWJB+5*18
    call fwc : dw #BB90           ; TXT_SET_PEN
    assert $ == FWJB+5*19
    call fwc : dw #BB93           ; TXT_GET_PEN
    assert $ == FWJB+5*20
    call fwc : dw #BB96           ; TXT_SET_PAPER
    assert $ == FWJB+5*21
    call fwc : dw #BB99           ; TXT_GET_PAPER
    assert $ == FWJB+5*22
    call fwc : dw #BB9C           ; TXT_INVERSE
    assert $ == FWJB+5*23
    call fwc : dw #BB9F           ; TXT_SET_BACK
    assert $ == FWJB+5*24
    call fwc : dw #BBA5           ; TXT_GET_MATRIX
    assert $ == FWJB+5*25
    call fwc : dw #BBA8           ; TXT_SET_MATRIX
    assert $ == FWJB+5*26
    call fwc : dw #BBAB           ; TXT_SET_M_TABLE
    assert $ == FWJB+5*27
    call fwc : dw #BBAE           ; TXT_GET_M_TABLE
    assert $ == FWJB+5*28
    call fwc : dw #BBC0           ; GRA_MOVE_ABSOLUTE
    assert $ == FWJB+5*29
    call fwc : dw #BBC3           ; GRA_MOVE_RELATIVE
    assert $ == FWJB+5*30
    call fwc : dw #BBC6           ; GRA_ASK_CURSOR
    assert $ == FWJB+5*31
    call fwc : dw #BBC9           ; GRA_SET_ORIGIN
    assert $ == FWJB+5*32
    call fwc : dw #BBCC           ; GRA_GET_ORIGIN
    assert $ == FWJB+5*33
    call fwc : dw #BBDB           ; GRA_CLEAR_WINDOW
    assert $ == FWJB+5*34
    call fwc : dw #BBDE           ; GRA_SET_PEN
    assert $ == FWJB+5*35
    call fwc : dw #BBE1           ; GRA_GET_PEN
    assert $ == FWJB+5*36
    call fwc : dw #BBE4           ; GRA_SET_PAPER
    assert $ == FWJB+5*37
    call fwc : dw #BBEA           ; GRA_PLOT_ABSOLUTE
    assert $ == FWJB+5*38
    call fwc : dw #BBED           ; GRA_PLOT_RELATIVE
    assert $ == FWJB+5*39
    call fwc : dw #BBF0           ; GRA_TEST_ABSOLUTE
    assert $ == FWJB+5*40
    call fwc : dw #BBF3           ; GRA_TEST_RELATIVE
    assert $ == FWJB+5*41
    call fwc : dw #BBF6           ; GRA_LINE_ABSOLUTE
    assert $ == FWJB+5*42
    call fwc : dw #BBF9           ; GRA_LINE_RELATIVE
    assert $ == FWJB+5*43
    call fwc : dw #BC0B           ; SCR_GET_LOCATION
    assert $ == FWJB+5*44
    call fwc : dw #BC0E           ; SCR_SET_MODE
    assert $ == FWJB+5*45
    call fwc : dw #BC11           ; SCR_GET_MODE
    assert $ == FWJB+5*46
    call fwc : dw #BC1D           ; SCR_DOT_POSITION
    assert $ == FWJB+5*47
    call fwc : dw #BC20           ; SCR_NEXT_BYTE
    assert $ == FWJB+5*48
    call fwc : dw #BC23           ; SCR_PREV_BYTE
    assert $ == FWJB+5*49
    call fwc : dw #BC2C           ; SCR_INK_ENCODE
    assert $ == FWJB+5*50
    call fwc : dw #BC32           ; SCR_SET_INK
    assert $ == FWJB+5*51
    call fwc : dw #BC38           ; SCR_SET_BORDER
    assert $ == FWJB+5*52
    call fwc : dw #BC3E           ; SCR_SET_FLASHING
    assert $ == FWJB+5*53
    call fwc : dw #BC44           ; SCR_FILL_BOX
    assert $ == FWJB+5*54
    call fwc : dw #BC50           ; SCR_SW_ROLL
    assert $ == FWJB+5*55
    call fwc : dw #BC59           ; SCR_ACCESS
    assert $ == FWJB+5*56
    call fwc : dw #BC77           ; CAS_IN_OPEN
    assert $ == FWJB+5*57
    call fwc : dw #BC7A           ; CAS_IN_CLOSE
    assert $ == FWJB+5*58
    call fwc : dw #BC7D           ; CAS_IN_ABANDON
    assert $ == FWJB+5*59
    call fwc : dw #BC80           ; CAS_IN_CHAR
    assert $ == FWJB+5*60
    call fwc : dw #BC8C           ; CAS_OUT_OPEN
    assert $ == FWJB+5*61
    call fwc : dw #BC8F           ; CAS_OUT_CLOSE
    assert $ == FWJB+5*62
    call fwc : dw #BC92           ; CAS_OUT_ABANDON
    assert $ == FWJB+5*63
    call fwc : dw #BC95           ; CAS_OUT_CHAR
    assert $ == FWJB+5*64
    call fwc : dw #BC9B           ; CAS_CATALOG
    assert $ == FWJB+5*65
    call fwc : dw #BCAA           ; SOUND_QUEUE
    assert $ == FWJB+5*66
    call fwc : dw #BCAD           ; SOUND_CHECK
    assert $ == FWJB+5*67
    call fwc : dw #BCB3           ; SOUND_RELEASE
    assert $ == FWJB+5*68
    call fwc : dw #BCB6           ; SOUND_HOLD
    assert $ == FWJB+5*69
    call fwc : dw #BCB9           ; SOUND_CONTINUE
    assert $ == FWJB+5*70
    call fwc : dw #BCBC           ; SOUND_AMPL_ENVELOPE
    assert $ == FWJB+5*71
    call fwc : dw #BCBF           ; SOUND_TONE_ENVELOPE
    assert $ == FWJB+5*72
    call fwc : dw #BCD4           ; KL_FIND_COMMAND
    assert $ == FWJB+5*73
    call fwc : dw #BD0D           ; KL_TIME_PLEASE
    assert $ == FWJB+5*74
    call fwc : dw #001B           ; KL_FAR_PCHL
    assert $ == FWJB+5*75
    call fwc : dw #BD19           ; MC_WAIT_FLYBACK
    assert $ == FWJB+5*76
    call fwc : dw #BD3A           ; EDIT_464
    assert $ == FWJB+5*77
    call fwc : dw #BD5E           ; EDIT_6128
NFW equ 78
