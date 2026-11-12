;; CPC Lisp -- the 512K CPC's firmware names (made by tools/cpc512/mkfw.py
;; from mach/cpc/firmware.asm: do not edit). A routine's name is its
;; trampoline in the resident part, which calls it with the screen's RAM
;; at &C000; the maths package and the ROM routines are called directly.

    include "jumps.asm"

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
KM_WAIT_CHAR        equ FWJB+5*0
KM_READ_CHAR        equ FWJB+5*1
KM_CHAR_RETURN      equ FWJB+5*2
KM_TEST_KEY         equ FWJB+5*3
KM_GET_JOYSTICK     equ FWJB+5*4

;; TEXT VDU
TXT_OUTPUT          equ FWJB+5*5
TXT_WR_CHAR         equ FWJB+5*6
TXT_RD_CHAR         equ FWJB+5*7
TXT_SET_GRAPHIC     equ FWJB+5*8
TXT_WIN_ENABLE      equ FWJB+5*9
TXT_GET_WINDOW      equ FWJB+5*10
TXT_CLEAR_WINDOW    equ FWJB+5*11
TXT_SET_CURSOR      equ FWJB+5*12
TXT_GET_CURSOR      equ FWJB+5*13
TXT_CUR_ENABLE      equ FWJB+5*14
TXT_CUR_DISABLE     equ FWJB+5*15
TXT_CUR_ON          equ FWJB+5*16
TXT_CUR_OFF         equ FWJB+5*17
TXT_SET_PEN         equ FWJB+5*18
TXT_GET_PEN         equ FWJB+5*19
TXT_SET_PAPER       equ FWJB+5*20
TXT_GET_PAPER       equ FWJB+5*21
TXT_INVERSE         equ FWJB+5*22
TXT_SET_BACK        equ FWJB+5*23
TXT_GET_MATRIX      equ FWJB+5*24
TXT_SET_MATRIX      equ FWJB+5*25
TXT_SET_M_TABLE     equ FWJB+5*26
TXT_GET_M_TABLE     equ FWJB+5*27

;; GRAPHICS VDU
GRA_MOVE_ABSOLUTE   equ FWJB+5*28
GRA_MOVE_RELATIVE   equ FWJB+5*29
GRA_ASK_CURSOR      equ FWJB+5*30
GRA_SET_ORIGIN      equ FWJB+5*31
GRA_GET_ORIGIN      equ FWJB+5*32
GRA_CLEAR_WINDOW    equ FWJB+5*33
GRA_SET_PEN         equ FWJB+5*34
GRA_GET_PEN         equ FWJB+5*35
GRA_SET_PAPER       equ FWJB+5*36
GRA_PLOT_ABSOLUTE   equ FWJB+5*37
GRA_PLOT_RELATIVE   equ FWJB+5*38
GRA_TEST_ABSOLUTE   equ FWJB+5*39
GRA_TEST_RELATIVE   equ FWJB+5*40
GRA_LINE_ABSOLUTE   equ FWJB+5*41
GRA_LINE_RELATIVE   equ FWJB+5*42

;; SCREEN PACK
SCR_GET_LOCATION    equ FWJB+5*43
SCR_SET_MODE        equ FWJB+5*44
SCR_GET_MODE        equ FWJB+5*45
SCR_DOT_POSITION    equ FWJB+5*46
SCR_NEXT_BYTE       equ FWJB+5*47
SCR_PREV_BYTE       equ FWJB+5*48
SCR_INK_ENCODE      equ FWJB+5*49
SCR_SET_INK         equ FWJB+5*50
SCR_SET_BORDER      equ FWJB+5*51
SCR_SET_FLASHING    equ FWJB+5*52
SCR_FILL_BOX        equ FWJB+5*53
SCR_SW_ROLL         equ FWJB+5*54
SCR_ACCESS          equ FWJB+5*55

;; CASSETTE MANAGER: the file vectors, which a disc ROM (AMSDOS, Parados)
;; takes over -- or a tape
CAS_IN_OPEN         equ FWJB+5*56
CAS_IN_CLOSE        equ FWJB+5*57
CAS_IN_ABANDON      equ FWJB+5*58
CAS_IN_CHAR         equ FWJB+5*59
CAS_OUT_OPEN        equ FWJB+5*60
CAS_OUT_CLOSE       equ FWJB+5*61
CAS_OUT_ABANDON     equ FWJB+5*62
CAS_OUT_CHAR        equ FWJB+5*63
CAS_CATALOG         equ FWJB+5*64

;; SOUND MANAGER
SOUND_QUEUE         equ FWJB+5*65
SOUND_CHECK         equ FWJB+5*66
SOUND_RELEASE       equ FWJB+5*67
SOUND_HOLD          equ FWJB+5*68
SOUND_CONTINUE      equ FWJB+5*69
SOUND_AMPL_ENVELOPE equ FWJB+5*70
SOUND_TONE_ENVELOPE equ FWJB+5*71

;; KERNEL
KL_ROM_WALK         equ #BCCB
KL_FIND_COMMAND     equ FWJB+5*72
KL_TIME_PLEASE      equ FWJB+5*73
KL_L_ROM_ENABLE     equ #B906
KL_ROM_RESTORE      equ #B90C
KL_ROM_SELECT       equ #B90F       ; C = ROM -> C = the one before. AF, B corrupt
KL_CURR_SELECTION   equ #B912       ; -> A = the ROM selected now
KL_FAR_PCHL         equ FWJB+5*74       ; RST 3's far call, by C = ROM, HL = address

;; MACHINE PACK
MC_WAIT_FLYBACK     equ FWJB+5*75

;; past &BD37: the 464's addresses, and what tells the machines apart
EDIT_464            equ FWJB+5*76
EDIT_6128           equ FWJB+5*77
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
