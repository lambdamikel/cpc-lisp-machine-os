;; CPC Lisp -- the machine interface, bound to the Amstrad CPC.
;;
;; The portable code (src/, lib/) reaches the machine only through these
;; names. On the CPC each is a firmware entry point (firmware.asm), so the
;; interface costs nothing; another machine defines the same names for
;; routines of its own, with the same contracts. mach/README.md has them:
;; what goes in, what comes out, what must be kept.
;;
;; Included by src/defs.asm; the library ROMs get these through
;; build/core.inc. Entry points that live in a library ROM rather than in
;; the firmware (the function editor's screen, VID_INIT...; the maths call,
;; FM) are defined by the machine's files there: fr.asm, fp.asm.

;; CONSOLE: the text screen, through the firmware's text VDU
CON_PUTC        equ TXT_OUTPUT          ; A = a character; obeys controls
CON_WRCH        equ TXT_WR_CHAR         ; A = a character, drawn as it is
CON_RDCH        equ TXT_RD_CHAR         ; -> A = the character at the cursor
CON_GETCUR      equ TXT_GET_CURSOR      ; -> H = column, L = row, A = roll count
CON_SETCUR      equ TXT_SET_CURSOR      ; H = column, L = row
CON_CURON       equ TXT_CUR_ON          ; the cursor shown / hidden
CON_CUROFF      equ TXT_CUR_OFF
CON_CURENA      equ TXT_CUR_ENABLE      ; ... and the user's switch for it
CON_CURDIS      equ TXT_CUR_DISABLE
CON_INVERSE     equ TXT_INVERSE         ; pen and paper swapped
CON_GETWIN      equ TXT_GET_WINDOW      ; -> H, D = columns; L, E = rows
CON_CLS         equ TXT_CLEAR_WINDOW
CON_PEN         equ TXT_SET_PEN         ; A = a pen
CON_PAPER       equ TXT_SET_PAPER

;; KEYS
KEY_READ        equ KM_READ_CHAR        ; -> C, A = a character; NC: none
KEY_WAIT        equ KM_WAIT_CHAR        ; -> A = a character
KEY_UNREAD      equ KM_CHAR_RETURN      ; A = a character, read next
KEY_TEST        equ KM_TEST_KEY         ; A = a key number -> NZ if down
KEY_ESC         equ 66                  ; ESC's key number: it breaks

;; VIDEO: the screen as a whole
VID_MODE        equ SCR_SET_MODE        ; A = a mode
VID_INK         equ SCR_SET_INK         ; A = an ink, B, C = its colours
VID_BORDER      equ SCR_SET_BORDER      ; B, C = its colours
VID_FRAME       equ MC_WAIT_FLYBACK     ; wait for the next frame
VID_FILLBOX     equ SCR_FILL_BOX        ; A = VID_PAPER; H-D columns, L-E rows

;; GRAPHICS: logical coordinates, x 0-639 and y 0-399, from the origin
GFX_PLOT        equ GRA_PLOT_ABSOLUTE   ; DE = x, HL = y
GFX_PLOTR       equ GRA_PLOT_RELATIVE
GFX_MOVE        equ GRA_MOVE_ABSOLUTE
GFX_MOVER       equ GRA_MOVE_RELATIVE
GFX_LINE        equ GRA_LINE_ABSOLUTE
GFX_LINER       equ GRA_LINE_RELATIVE
GFX_TEST        equ GRA_TEST_ABSOLUTE   ; -> A = the pen there
GFX_TESTR       equ GRA_TEST_RELATIVE
GFX_WHERE       equ GRA_ASK_CURSOR      ; -> DE = x, HL = y
GFX_ORIGIN      equ GRA_SET_ORIGIN      ; DE = x, HL = y
GFX_PEN         equ GRA_SET_PEN         ; A = a pen
GFX_PAPER       equ GRA_SET_PAPER
GFX_CLEAR       equ GRA_CLEAR_WINDOW

;; SOUND
SND_QUEUE       equ SOUND_QUEUE         ; HL = a sound, 9 bytes -> NC: full

;; FILES: one input file and one output file at a time
FILE_IOPEN      equ CAS_IN_OPEN         ; B = length, HL = name, DE = 2 KB buffer
FILE_ICLOSE     equ CAS_IN_CLOSE
FILE_IABANDON   equ CAS_IN_ABANDON
FILE_GETC       equ CAS_IN_CHAR         ; -> C, A = a character; NC: the end
FILE_OOPEN      equ CAS_OUT_OPEN        ; B = length, HL = name, DE = 2 KB buffer
FILE_OCLOSE     equ CAS_OUT_CLOSE
FILE_OABANDON   equ CAS_OUT_ABANDON
FILE_PUTC       equ CAS_OUT_CHAR        ; A = a character
FILE_CAT        equ CAS_CATALOG         ; DE = 2 KB buffer: the directory shown

;; FLOATS: five-byte reals, the firmware's (fp.asm calls them: FM)
FP_MOVE         equ M_MOVE
FP_INT2R        equ M_INT2R
FP_BIN2R        equ M_BIN2R
FP_R2INT        equ M_R2INT
FP_R2BIN        equ M_R2BIN
FP_FIX          equ M_FIX
FP_INT          equ M_INT
FP_EXP10        equ M_EXP10
FP_ADD          equ M_ADD
FP_RSUB         equ M_RSUB
FP_MUL          equ M_MUL
FP_DIV          equ M_DIV
FP_CMP          equ M_CMP
FP_NEG          equ M_NEG
FP_SGN          equ M_SGN
FP_ANGLE        equ M_ANGLE
FP_PI           equ M_PI
FP_SQR          equ M_SQR
FP_POW          equ M_POW
FP_LOG          equ M_LOG
FP_EXP          equ M_EXP
FP_SIN          equ M_SIN
FP_COS          equ M_COS
FP_TAN          equ M_TAN
FP_ATN          equ M_ATN

;; SYSTEM
SYS_BANK        equ KL_ROM_SELECT       ; C = a bank -> C = the one before
NBANKS          equ 16                  ; banks 1 to NBANKS-1 may hold the library
SYS_CURBANK     equ KL_CURR_SELECTION   ; -> A = the bank in now
SYS_TIME        equ KL_TIME_PLEASE      ; -> DEHL = 1/300 s since power-up
