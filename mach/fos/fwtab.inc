;; the trampolines (made by tools/fos/mkfw.py: do not edit)
    assert $ == FWJB+5*0
    call fwp : dw #C000+3*0     ; KM_WAIT_CHAR
    assert $ == FWJB+5*1
    call fwp : dw #C000+3*1     ; KM_READ_CHAR
    assert $ == FWJB+5*2
    call fwp : dw #C000+3*2     ; KM_CHAR_RETURN
    assert $ == FWJB+5*3
    jp r_testkey : db 0,0             ; KM_TEST_KEY
    assert $ == FWJB+5*4
    call fwp : dw #C000+3*4     ; KM_GET_JOYSTICK
    assert $ == FWJB+5*5
    call fwp : dw #C000+3*5     ; TXT_OUTPUT
    assert $ == FWJB+5*6
    call fwp : dw #C000+3*6     ; TXT_WR_CHAR
    assert $ == FWJB+5*7
    call fwp : dw #C000+3*7     ; TXT_RD_CHAR
    assert $ == FWJB+5*8
    call fwp : dw #C000+3*8     ; TXT_SET_GRAPHIC
    assert $ == FWJB+5*9
    call fwp : dw #C000+3*9     ; TXT_WIN_ENABLE
    assert $ == FWJB+5*10
    call fwp : dw #C000+3*10     ; TXT_GET_WINDOW
    assert $ == FWJB+5*11
    call fwp : dw #C000+3*11     ; TXT_CLEAR_WINDOW
    assert $ == FWJB+5*12
    call fwp : dw #C000+3*12     ; TXT_SET_CURSOR
    assert $ == FWJB+5*13
    call fwp : dw #C000+3*13     ; TXT_GET_CURSOR
    assert $ == FWJB+5*14
    call fwp : dw #C000+3*14     ; TXT_CUR_ENABLE
    assert $ == FWJB+5*15
    call fwp : dw #C000+3*15     ; TXT_CUR_DISABLE
    assert $ == FWJB+5*16
    call fwp : dw #C000+3*16     ; TXT_CUR_ON
    assert $ == FWJB+5*17
    call fwp : dw #C000+3*17     ; TXT_CUR_OFF
    assert $ == FWJB+5*18
    call fwp : dw #C000+3*18     ; TXT_SET_PEN
    assert $ == FWJB+5*19
    call fwp : dw #C000+3*19     ; TXT_GET_PEN
    assert $ == FWJB+5*20
    call fwp : dw #C000+3*20     ; TXT_SET_PAPER
    assert $ == FWJB+5*21
    call fwp : dw #C000+3*21     ; TXT_GET_PAPER
    assert $ == FWJB+5*22
    call fwp : dw #C000+3*22     ; TXT_INVERSE
    assert $ == FWJB+5*23
    call fwp : dw #C000+3*23     ; TXT_SET_BACK
    assert $ == FWJB+5*24
    call fwp : dw #C000+3*24     ; TXT_GET_MATRIX
    assert $ == FWJB+5*25
    call fwp : dw #C000+3*25     ; TXT_SET_MATRIX
    assert $ == FWJB+5*26
    call fwp : dw #C000+3*26     ; TXT_SET_M_TABLE
    assert $ == FWJB+5*27
    call fwp : dw #C000+3*27     ; TXT_GET_M_TABLE
    assert $ == FWJB+5*28
    call fwp : dw #C000+3*28     ; GRA_MOVE_ABSOLUTE
    assert $ == FWJB+5*29
    call fwp : dw #C000+3*29     ; GRA_MOVE_RELATIVE
    assert $ == FWJB+5*30
    call fwp : dw #C000+3*30     ; GRA_ASK_CURSOR
    assert $ == FWJB+5*31
    call fwp : dw #C000+3*31     ; GRA_SET_ORIGIN
    assert $ == FWJB+5*32
    call fwp : dw #C000+3*32     ; GRA_GET_ORIGIN
    assert $ == FWJB+5*33
    call fwp : dw #C000+3*33     ; GRA_CLEAR_WINDOW
    assert $ == FWJB+5*34
    call fwp : dw #C000+3*34     ; GRA_SET_PEN
    assert $ == FWJB+5*35
    call fwp : dw #C000+3*35     ; GRA_GET_PEN
    assert $ == FWJB+5*36
    call fwp : dw #C000+3*36     ; GRA_SET_PAPER
    assert $ == FWJB+5*37
    call fwp : dw #C000+3*37     ; GRA_PLOT_ABSOLUTE
    assert $ == FWJB+5*38
    call fwp : dw #C000+3*38     ; GRA_PLOT_RELATIVE
    assert $ == FWJB+5*39
    call fwp : dw #C000+3*39     ; GRA_TEST_ABSOLUTE
    assert $ == FWJB+5*40
    call fwp : dw #C000+3*40     ; GRA_TEST_RELATIVE
    assert $ == FWJB+5*41
    call fwp : dw #C000+3*41     ; GRA_LINE_ABSOLUTE
    assert $ == FWJB+5*42
    call fwp : dw #C000+3*42     ; GRA_LINE_RELATIVE
    assert $ == FWJB+5*43
    call fwp : dw #C000+3*43     ; SCR_GET_LOCATION
    assert $ == FWJB+5*44
    call fwp : dw #C000+3*44     ; SCR_SET_MODE
    assert $ == FWJB+5*45
    call fwp : dw #C000+3*45     ; SCR_GET_MODE
    assert $ == FWJB+5*46
    call fwp : dw #C000+3*46     ; SCR_DOT_POSITION
    assert $ == FWJB+5*47
    call fwp : dw #C000+3*47     ; SCR_NEXT_BYTE
    assert $ == FWJB+5*48
    call fwp : dw #C000+3*48     ; SCR_PREV_BYTE
    assert $ == FWJB+5*49
    call fwp : dw #C000+3*49     ; SCR_INK_ENCODE
    assert $ == FWJB+5*50
    call fwp : dw #C000+3*50     ; SCR_SET_INK
    assert $ == FWJB+5*51
    call fwp : dw #C000+3*51     ; SCR_SET_BORDER
    assert $ == FWJB+5*52
    call fwp : dw #C000+3*52     ; SCR_SET_FLASHING
    assert $ == FWJB+5*53
    call fwp : dw #C000+3*53     ; SCR_FILL_BOX
    assert $ == FWJB+5*54
    call fwp : dw #C000+3*54     ; SCR_SW_ROLL
    assert $ == FWJB+5*55
    call fwp : dw #C000+3*55     ; SCR_ACCESS
    assert $ == FWJB+5*56
    call fwp : dw #C000+3*56     ; CAS_IN_OPEN
    assert $ == FWJB+5*57
    call fwp : dw #C000+3*57     ; CAS_IN_CLOSE
    assert $ == FWJB+5*58
    call fwp : dw #C000+3*58     ; CAS_IN_ABANDON
    assert $ == FWJB+5*59
    call fwp : dw #C000+3*59     ; CAS_IN_CHAR
    assert $ == FWJB+5*60
    call fwp : dw #C000+3*60     ; CAS_OUT_OPEN
    assert $ == FWJB+5*61
    call fwp : dw #C000+3*61     ; CAS_OUT_CLOSE
    assert $ == FWJB+5*62
    call fwp : dw #C000+3*62     ; CAS_OUT_ABANDON
    assert $ == FWJB+5*63
    call fwp : dw #C000+3*63     ; CAS_OUT_CHAR
    assert $ == FWJB+5*64
    call fwp : dw #C000+3*64     ; CAS_CATALOG
    assert $ == FWJB+5*65
    call fwp : dw #C000+3*65     ; SOUND_QUEUE
    assert $ == FWJB+5*66
    call fwp : dw #C000+3*66     ; SOUND_CHECK
    assert $ == FWJB+5*67
    call fwp : dw #C000+3*67     ; SOUND_RELEASE
    assert $ == FWJB+5*68
    call fwp : dw #C000+3*68     ; SOUND_HOLD
    assert $ == FWJB+5*69
    call fwp : dw #C000+3*69     ; SOUND_CONTINUE
    assert $ == FWJB+5*70
    call fwp : dw #C000+3*70     ; SOUND_AMPL_ENVELOPE
    assert $ == FWJB+5*71
    call fwp : dw #C000+3*71     ; SOUND_TONE_ENVELOPE
    assert $ == FWJB+5*72
    call fwp : dw #C000+3*72     ; KL_FIND_COMMAND
    assert $ == FWJB+5*73
    jp r_time : db 0,0             ; KL_TIME_PLEASE
    assert $ == FWJB+5*74
    jp r_lromon : db 0,0             ; KL_L_ROM_ENABLE
    assert $ == FWJB+5*75
    jp r_romrest : db 0,0             ; KL_ROM_RESTORE
    assert $ == FWJB+5*76
    jp r_romsel : db 0,0             ; KL_ROM_SELECT
    assert $ == FWJB+5*77
    jp r_romcur : db 0,0             ; KL_CURR_SELECTION
    assert $ == FWJB+5*78
    call fwp : dw #C000+3*78     ; KL_FAR_PCHL
    assert $ == FWJB+5*79
    jp r_flyback : db 0,0             ; MC_WAIT_FLYBACK
    assert $ == FWJB+5*80
    call fwp : dw #C000+3*80     ; EDIT_464
    assert $ == FWJB+5*81
    call fwp : dw #C000+3*81     ; EDIT_6128
