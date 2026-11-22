;; CPC Lisp -- the MSX's machine routines: their numbers. They live in
;; the machine pages (page.asm, pageb.asm), mapper segments seen at &8000
;; only while one runs; the resident part (resident.asm), in RAM that is
;; always there, holds a jumpblock whose entry k does "call mfar : db 2k",
;; which maps the machine page, calls the kth routine of its table (MTAB:
;; a routine in page B has bit 14 set) and maps back what was there.
;; machine.asm names the entries; tools/trs80/mkjumps.py keeps the three
;; in step.

RESIDENT    equ #0100           ; the resident part's fixed entries:
RS_START    equ RESIDENT        ;   LISP.COM's start: the loader
SYS_BANK    equ RESIDENT+3      ;   C = a bank -> C = the one before
SYS_CURBANK equ RESIDENT+6      ;   -> A = the bank at &C000
RS_XFER     equ RESIDENT+9      ;   A = a segment: an LDIR with it at &8000
                                ;     (the RAM disc's way to it)
RS_DOS      equ RESIDENT+12     ;   a DOS call, as DOS takes it, with DOS's
                                ;     own pages for it
RS_ROM      equ RESIDENT+15     ;   IX = a main ROM routine, called with DOS's
                                ;     page 3, the machine page kept
RS_QUIT     equ RESIDENT+18     ;   back to DOS: SCREEN 0, the program ends
RS_BOOT     equ RESIDENT+21     ;   the start, once everything is loaded
RS_P2       equ RESIDENT+24     ; the segment at &8000 now
RS_BANK     equ RESIDENT+25     ; the bank at &C000 (0-5)
RS_FRAMES   equ RESIDENT+26     ; 4 bytes: 1/300 s since the start
RS_HOOK     equ RESIDENT+30     ; the test harness's (openMSX's Tcl)
RS_HZ       equ RESIDENT+31     ; the interrupt's frequency: 50 or 60
RS_KBD      equ RESIDENT+32     ; the keyboard: the main ROM's &002C, bits 0-3
RS_TPA2     equ RESIDENT+33     ; DOS's segments in pages 2 and 3
RS_TPA3     equ RESIDENT+34
RS_SEGS     equ RESIDENT+35     ; 8: the segments of banks 0-5, then of
SEG_A       equ RS_SEGS+6       ;   machine page A
SEG_B       equ RS_SEGS+7       ;   and B
RS_RDN      equ RESIDENT+43     ; the RAM disc's segments: how many,
RS_RD       equ RESIDENT+44     ;   then each (up to RD_MAX)
RD_MAX      equ 32
JB          equ #0180           ; the jumpblock, four bytes an entry
MTAB        equ #8100           ; machine page A's table, a word an entry
P_INIT      equ #8000           ; page A: its start (rs_boot calls it),
P_TICK      equ #8003           ;   the interrupt's work
PB_TICK     equ #8003           ; page B: the interrupt's sound
DOS_STACK   equ #C200           ; in DOS's page 3 (TPA there): a stack for
                                ;   DOS's and the ROM's calls, down to &C100
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
J_M_SNDCHECK     equ 83
J_M_SNDREL       equ 84
J_M_SNDHOLD      equ 85
J_M_SNDCONT      equ 86
J_M_AMPENV       equ 87
J_M_TONEENV      equ 88
NJ             equ 89
