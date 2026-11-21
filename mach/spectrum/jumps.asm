;; CPC Lisp -- the Spectrum's machine routines: their numbers. They live in
;; the machine pages (page.asm), DivMMC RAM seen at &2000 only while one
;; runs; the resident part (resident.asm), in RAM that is always there,
;; holds a jumpblock whose entry k does "call mfar : db 2k", which maps the
;; machine page, calls the kth routine of its table (MTAB: a routine in
;; page B has bit 15 set) and maps back what was there. machine.asm names
;; the entries; tools/trs80/mkjumps.py keeps the three in step.

IM2TAB      equ #5D00           ; the interrupt's table: 257 bytes of IM2HI,
IM2HI       equ #5E             ;   so the interrupt goes to &5E5E
IM2VEC      equ IM2HI*257
RESIDENT    equ #5E01           ; the resident part's fixed entries:
SYS_BANK    equ RESIDENT        ;   C = a bank -> C = the one before
SYS_CURBANK equ RESIDENT+3      ;   -> A = the bank at &C000
RS_XFER     equ RESIDENT+6      ;   A = a DivMMC page: an LDIR with it at
                                ;     &2000 (the RAM disc's way to it)
RS_ESX      equ RESIDENT+9      ;   an esxDOS call, its function in RS_FN
RS_CALC     equ RESIDENT+12     ;   A = a calculator literal, run on its stack
RS_BOOT     equ RESIDENT+15     ;   the start (the loader, the harness)
RS_E3       equ RESIDENT+18     ; the DivMMC's port as it is now
RS_FN       equ RESIDENT+19     ; esxDOS's function for RS_ESX
RS_BANK     equ RESIDENT+20     ; the bank at &C000 (0-5)
RS_FRAMES   equ RESIDENT+21     ; 4 bytes: 1/300 s since the start
RS_HOOK     equ RESIDENT+25     ; the test harness's: ZEsarUX sets it at
                                ;   EDHOOK (a breakpoint's action)
RS_MODEL    equ RESIDENT+26     ; 0: a +2A, +2B or +3; 1: a 128 or a grey
                                ;   +2 (no port &1FFD) -- the loader's
JB          equ #5E80           ; the jumpblock, four bytes an entry
MTAB        equ #2100           ; machine page A's table, a word an entry
P_INIT      equ #2000           ; page A: its start (rs_boot calls it),
P_TICK      equ #2003           ;   the interrupt's work
FILE_BUFSIZE equ 32+256         ; a file's buffer: its state, 256 bytes of it

J_CON_PUTC       equ 0
J_CON_WRCH       equ 1
J_CON_RDCH       equ 2
J_CON_GETCUR     equ 3
J_CON_SETCUR     equ 4
J_CON_CURON      equ 5
J_CON_CUROFF     equ 6
J_CON_CURENA     equ 7
J_CON_CURDIS     equ 8
J_CON_INVERSE    equ 9
J_CON_GETWIN     equ 10
J_CON_CLS        equ 11
J_CON_PEN        equ 12
J_CON_PAPER      equ 13
J_KEY_READ       equ 14
J_KEY_WAIT       equ 15
J_KEY_UNREAD     equ 16
J_KEY_TEST       equ 17
J_VID_MODE       equ 18
J_VID_INK        equ 19
J_VID_BORDER     equ 20
J_VID_FRAME      equ 21
J_VID_FILLBOX    equ 22
J_GFX_PLOT       equ 23
J_GFX_PLOTR      equ 24
J_GFX_MOVE       equ 25
J_GFX_MOVER      equ 26
J_GFX_LINE       equ 27
J_GFX_LINER      equ 28
J_GFX_TEST       equ 29
J_GFX_TESTR      equ 30
J_GFX_WHERE      equ 31
J_GFX_ORIGIN     equ 32
J_GFX_PEN        equ 33
J_GFX_PAPER      equ 34
J_GFX_CLEAR      equ 35
J_SND_QUEUE      equ 36
J_FILE_IOPEN     equ 37
J_FILE_ICLOSE    equ 38
J_FILE_IABANDON  equ 39
J_FILE_GETC      equ 40
J_FILE_OOPEN     equ 41
J_FILE_OCLOSE    equ 42
J_FILE_OABANDON  equ 43
J_FILE_PUTC      equ 44
J_FILE_CAT       equ 45
J_FP_MOVE        equ 46
J_FP_INT2R       equ 47
J_FP_BIN2R       equ 48
J_FP_R2INT       equ 49
J_FP_R2BIN       equ 50
J_FP_FIX         equ 51
J_FP_INT         equ 52
J_FP_EXP10       equ 53
J_FP_ADD         equ 54
J_FP_RSUB        equ 55
J_FP_MUL         equ 56
J_FP_DIV         equ 57
J_FP_CMP         equ 58
J_FP_NEG         equ 59
J_FP_SGN         equ 60
J_FP_ANGLE       equ 61
J_FP_PI          equ 62
J_FP_SQR         equ 63
J_FP_POW         equ 64
J_FP_LOG         equ 65
J_FP_EXP         equ 66
J_FP_SIN         equ 67
J_FP_COS         equ 68
J_FP_TAN         equ 69
J_FP_ATN         equ 70
J_SYS_TIME       equ 71
J_M_EDIT         equ 72
J_M_QUIT         equ 73
J_M_INKMODE      equ 74
J_M_RDIN         equ 75
J_M_RDOUT        equ 76
J_M_RDCAT        equ 77
J_M_DELETE       equ 78
J_M_FILL         equ 79
J_M_MIDI         equ 80
J_M_DRIVE        equ 81
J_M_VIDCHAR      equ 82
NJ             equ 83
