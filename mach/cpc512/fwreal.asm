;; The CPC's firmware addresses as they are, for the 512K CPC's resident
;; part (made by tools/cpc512/mkfw.py: do not edit)

;; CPC Lisp -- the Amstrad CPC's firmware: every entry point the ROMs use.
;;
;; Only the machine layer (this directory) and machine.asm's bindings name
;; these; the portable code calls the interface names of machine.asm.
;; Included by src/defs.asm, so the library ROMs get them through
;; build/core.inc.
;;
;; The jumpblock is the same on the 464, 664 and 6128 from &BB00 to &BD37.
;; Past that the machines differ: the 664/6128 add twelve entries at &BD3A,
;; which moves EDIT (the BASIC line editor, in the firmware ROM) from &BD3A
;; to &BD5E and the maths package from &BD3D to &BD61 -- with a different
;; set of entries, 49 on the 464 against 32. Code that calls past &BD37
;; looks the address up at boot (V_EDITV) or adds the difference (fmcall,
;; fp.asm). The Firmware Guide has the contracts.

;; KEY MANAGER
KM_WAIT_CHAR        equ #BB06
KM_READ_CHAR        equ #BB09
KM_CHAR_RETURN      equ #BB0C
KM_TEST_KEY         equ #BB1E
KM_GET_JOYSTICK     equ #BB24

;; TEXT VDU
TXT_OUTPUT          equ #BB5A
TXT_WR_CHAR         equ #BB5D
TXT_RD_CHAR         equ #BB60
TXT_SET_GRAPHIC     equ #BB63
TXT_WIN_ENABLE      equ #BB66
TXT_GET_WINDOW      equ #BB69
TXT_CLEAR_WINDOW    equ #BB6C
TXT_SET_CURSOR      equ #BB75
TXT_GET_CURSOR      equ #BB78
TXT_CUR_ENABLE      equ #BB7B
TXT_CUR_DISABLE     equ #BB7E
TXT_CUR_ON          equ #BB81
TXT_CUR_OFF         equ #BB84
TXT_SET_PEN         equ #BB90
TXT_GET_PEN         equ #BB93
TXT_SET_PAPER       equ #BB96
TXT_GET_PAPER       equ #BB99
TXT_INVERSE         equ #BB9C
TXT_SET_BACK        equ #BB9F
TXT_GET_MATRIX      equ #BBA5
TXT_SET_MATRIX      equ #BBA8
TXT_SET_M_TABLE     equ #BBAB
TXT_GET_M_TABLE     equ #BBAE

;; GRAPHICS VDU
GRA_MOVE_ABSOLUTE   equ #BBC0
GRA_MOVE_RELATIVE   equ #BBC3
GRA_ASK_CURSOR      equ #BBC6
GRA_SET_ORIGIN      equ #BBC9
GRA_GET_ORIGIN      equ #BBCC
GRA_CLEAR_WINDOW    equ #BBDB
GRA_SET_PEN         equ #BBDE
GRA_GET_PEN         equ #BBE1
GRA_SET_PAPER       equ #BBE4
GRA_PLOT_ABSOLUTE   equ #BBEA
GRA_PLOT_RELATIVE   equ #BBED
GRA_TEST_ABSOLUTE   equ #BBF0
GRA_TEST_RELATIVE   equ #BBF3
GRA_LINE_ABSOLUTE   equ #BBF6
GRA_LINE_RELATIVE   equ #BBF9

;; SCREEN PACK
SCR_GET_LOCATION    equ #BC0B
SCR_SET_MODE        equ #BC0E
SCR_GET_MODE        equ #BC11
SCR_DOT_POSITION    equ #BC1D
SCR_NEXT_BYTE       equ #BC20
SCR_PREV_BYTE       equ #BC23
SCR_INK_ENCODE      equ #BC2C
SCR_SET_INK         equ #BC32
SCR_SET_BORDER      equ #BC38
SCR_SET_FLASHING    equ #BC3E
SCR_FILL_BOX        equ #BC44
SCR_SW_ROLL         equ #BC50
SCR_ACCESS          equ #BC59

;; CASSETTE MANAGER: the file vectors, which a disc ROM (AMSDOS, Parados)
;; takes over -- or a tape
CAS_IN_OPEN         equ #BC77
CAS_IN_CLOSE        equ #BC7A
CAS_IN_ABANDON      equ #BC7D
CAS_IN_CHAR         equ #BC80
CAS_OUT_OPEN        equ #BC8C
CAS_OUT_CLOSE       equ #BC8F
CAS_OUT_ABANDON     equ #BC92
CAS_OUT_CHAR        equ #BC95
CAS_CATALOG         equ #BC9B

;; SOUND MANAGER
SOUND_QUEUE         equ #BCAA
SOUND_CHECK         equ #BCAD
SOUND_RELEASE       equ #BCB3
SOUND_HOLD          equ #BCB6
SOUND_CONTINUE      equ #BCB9
SOUND_AMPL_ENVELOPE equ #BCBC
SOUND_TONE_ENVELOPE equ #BCBF

;; KERNEL
KL_ROM_WALK         equ #BCCB
KL_FIND_COMMAND     equ #BCD4
KL_TIME_PLEASE      equ #BD0D
KL_L_ROM_ENABLE     equ #B906
KL_ROM_RESTORE      equ #B90C
KL_ROM_SELECT       equ #B90F       ; C = ROM -> C = the one before. AF, B corrupt
KL_CURR_SELECTION   equ #B912       ; -> A = the ROM selected now
KL_FAR_PCHL         equ #001B       ; RST 3's far call, by C = ROM, HL = address

;; MACHINE PACK
MC_WAIT_FLYBACK     equ #BD19

;; past &BD37: the 464's addresses, and what tells the machines apart
EDIT_464            equ #BD3A
EDIT_6128           equ #BD5E
FIRM_464_PROBE      equ #BD3D       ; &EF (FIRM JUMP) on a 464, &CF on a 664/6128

;; THE MATHS PACKAGE, by its 464 addresses (fmcall adds the 664/6128's
;; difference): a real is five bytes, four of mantissa, least significant
;; first, the top bit of the last the sign, then the exponent (0 = zero)
M_MOVE      equ #BD3D           ; (HL) = (DE)
M_INT2R     equ #BD40           ; HL = magnitude, A bit 7 = sign -> (DE)
M_BIN2R     equ #BD43           ; 4 bytes at HL, A bit 7 = sign -> real there
M_R2INT     equ #BD46           ; (HL) -> HL rounded, S = sign, C if it fit
M_R2BIN     equ #BD49           ; (HL) -> 4 bytes there, rounded; B bit 7 sign
M_FIX       equ #BD4C           ;   the same, truncated
M_INT       equ #BD4F           ;   the same, floored
M_EXP10     equ #BD55           ; (HL) *= 10^A
M_ADD       equ #BD58           ; (HL) += (DE)
M_RSUB      equ #BD5E           ; (HL) = (DE) - (HL)
M_MUL       equ #BD61           ; (HL) *= (DE)
M_DIV       equ #BD64           ; (HL) /= (DE)
M_CMP       equ #BD6A           ; A = 1, 0, &FF: (HL) >, =, < (DE)
M_NEG       equ #BD6D           ; (HL) = -(HL)
M_SGN       equ #BD70           ; A = 1, 0, &FF; Z if zero, C if negative
M_ANGLE     equ #BD73           ; A = 0: radians
M_PI        equ #BD76           ; (HL) = pi
M_SQR       equ #BD79           ; (HL) = sqrt (HL), and so on:
M_POW       equ #BD7C           ; (HL) = (HL) ^ (DE)
M_LOG       equ #BD7F
M_EXP       equ #BD85
M_SIN       equ #BD88
M_COS       equ #BD8B
M_TAN       equ #BD8E
M_ATN       equ #BD91
