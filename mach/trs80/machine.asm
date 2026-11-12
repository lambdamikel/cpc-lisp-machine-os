;; CPC Lisp -- the machine interface, bound to the TRS-80 Model I/III with
;; X-MEM/80. Each name is an entry of the resident jumpblock (jumps.asm,
;; resident.asm), which calls the routine of that name in the machine page
;; (page.asm). mach/README.md has the contracts.

    include "jumps.asm"

SYS_BANK        equ RESIDENT               ; C = a page -> C = the one before
SYS_CURBANK     equ RESIDENT+3             ; -> A = the page at &C000
NBANKS          equ 32                ; X-MEM/80's pages: the library is in 3-7
KEY_ESC         equ 50                ; BREAK: row 6, bit 2 of the matrix

CON_PUTC        equ JB+4*J_CON_PUTC
CON_WRCH        equ JB+4*J_CON_WRCH
CON_RDCH        equ JB+4*J_CON_RDCH
CON_GETCUR      equ JB+4*J_CON_GETCUR
CON_SETCUR      equ JB+4*J_CON_SETCUR
CON_CURON       equ JB+4*J_CON_CURON
CON_CUROFF      equ JB+4*J_CON_CUROFF
CON_CURENA      equ JB+4*J_CON_CURENA
CON_CURDIS      equ JB+4*J_CON_CURDIS
CON_INVERSE     equ JB+4*J_CON_INVERSE
CON_GETWIN      equ JB+4*J_CON_GETWIN
CON_CLS         equ JB+4*J_CON_CLS
CON_PEN         equ JB+4*J_CON_PEN
CON_PAPER       equ JB+4*J_CON_PAPER
KEY_READ        equ JB+4*J_KEY_READ
KEY_WAIT        equ JB+4*J_KEY_WAIT
KEY_UNREAD      equ JB+4*J_KEY_UNREAD
KEY_TEST        equ JB+4*J_KEY_TEST
VID_MODE        equ JB+4*J_VID_MODE
VID_INK         equ JB+4*J_VID_INK
VID_BORDER      equ JB+4*J_VID_BORDER
VID_FRAME       equ JB+4*J_VID_FRAME
VID_FILLBOX     equ JB+4*J_VID_FILLBOX
GFX_PLOT        equ JB+4*J_GFX_PLOT
GFX_PLOTR       equ JB+4*J_GFX_PLOTR
GFX_MOVE        equ JB+4*J_GFX_MOVE
GFX_MOVER       equ JB+4*J_GFX_MOVER
GFX_LINE        equ JB+4*J_GFX_LINE
GFX_LINER       equ JB+4*J_GFX_LINER
GFX_TEST        equ JB+4*J_GFX_TEST
GFX_TESTR       equ JB+4*J_GFX_TESTR
GFX_WHERE       equ JB+4*J_GFX_WHERE
GFX_ORIGIN      equ JB+4*J_GFX_ORIGIN
GFX_PEN         equ JB+4*J_GFX_PEN
GFX_PAPER       equ JB+4*J_GFX_PAPER
GFX_CLEAR       equ JB+4*J_GFX_CLEAR
SND_QUEUE       equ JB+4*J_SND_QUEUE
FILE_IOPEN      equ JB+4*J_FILE_IOPEN
FILE_ICLOSE     equ JB+4*J_FILE_ICLOSE
FILE_IABANDON   equ JB+4*J_FILE_IABANDON
FILE_GETC       equ JB+4*J_FILE_GETC
FILE_OOPEN      equ JB+4*J_FILE_OOPEN
FILE_OCLOSE     equ JB+4*J_FILE_OCLOSE
FILE_OABANDON   equ JB+4*J_FILE_OABANDON
FILE_PUTC       equ JB+4*J_FILE_PUTC
FILE_CAT        equ JB+4*J_FILE_CAT
FP_MOVE         equ JB+4*J_FP_MOVE
FP_INT2R        equ JB+4*J_FP_INT2R
FP_BIN2R        equ JB+4*J_FP_BIN2R
FP_R2INT        equ JB+4*J_FP_R2INT
FP_R2BIN        equ JB+4*J_FP_R2BIN
FP_FIX          equ JB+4*J_FP_FIX
FP_INT          equ JB+4*J_FP_INT
FP_EXP10        equ JB+4*J_FP_EXP10
FP_ADD          equ JB+4*J_FP_ADD
FP_RSUB         equ JB+4*J_FP_RSUB
FP_MUL          equ JB+4*J_FP_MUL
FP_DIV          equ JB+4*J_FP_DIV
FP_CMP          equ JB+4*J_FP_CMP
FP_NEG          equ JB+4*J_FP_NEG
FP_SGN          equ JB+4*J_FP_SGN
FP_ANGLE        equ JB+4*J_FP_ANGLE
FP_PI           equ JB+4*J_FP_PI
FP_SQR          equ JB+4*J_FP_SQR
FP_POW          equ JB+4*J_FP_POW
FP_LOG          equ JB+4*J_FP_LOG
FP_EXP          equ JB+4*J_FP_EXP
FP_SIN          equ JB+4*J_FP_SIN
FP_COS          equ JB+4*J_FP_COS
FP_TAN          equ JB+4*J_FP_TAN
FP_ATN          equ JB+4*J_FP_ATN
SYS_TIME        equ JB+4*J_SYS_TIME
M_EDIT          equ JB+4*J_M_EDIT
M_QUIT          equ JB+4*J_M_QUIT
