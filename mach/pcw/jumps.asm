;; CPC Lisp -- the PCW's machine routines: their numbers. They live in the
;; machine pages (page.asm, pageb.asm), blocks seen at &C000 only while one
;; runs -- in place of the image there, which the routine's return brings
;; back; the resident part (resident.asm), in the block at &0000, always
;; seen, holds a jumpblock whose entry k does "call mfar : db 2k", which
;; maps the machine page, calls the kth routine of its table (MTAB: a
;; routine in page B has bit 14 clear) and maps back what was there.
;; machine.asm names the entries; tools/trs80/mkjumps.py keeps the three
;; in step.

RESIDENT    equ #0000           ; the resident part: RST 0 (a reboot), the
                                ;   interrupt at &0038 (IM 1), then:
SYS_BANK    equ #0040           ;   C = a bank -> C = the one before
SYS_CURBANK equ #0043           ;   -> A = the bank at &C000
RS_XFER     equ #0046           ;   A = a block, carry set: BC bytes from
                                ;     RAM at HL to the block at DE (seen at
                                ;     WINDOW), clear: from the block at HL to
                                ;     RAM at DE (the RAM disc, far arrays)
RS_QUIT     equ #0049           ;   the boot program again (SC_REBOOT)
RS_BOOT     equ #004C           ;   the start, once the loader is done
RS_P1       equ #004F           ; what &4000 shows now: &80 + its block
RS_P3       equ #0050           ;   and &C000
RS_BANK     equ #0051           ; the bank at &C000 (0-5)
RS_FRAMES   equ #0052           ; 4 bytes: 1/300 s since the start
RS_HOOK     equ #0056           ; the test harness's: EDHOOK sets it (pcw.py)
RS_HZ       equ #0057           ; 100: page B's ticks a second (sound.asm)
RS_NBLK     equ #0058           ; the machine's blocks: 16 or 32
RS_QUITF    equ #0059           ; 1 once (quit) ran under the harness
RS_T3       equ #005A           ; interrupts until the next sound tick (3)
RS_T6       equ #005B           ;   and key scan (6)
RS_SEGS     equ #005C           ; 8: &80 + the blocks of banks 0-5, then
SEG_A       equ RS_SEGS+6       ;   machine page A's
SEG_B       equ RS_SEGS+7       ;   and B's
RS_RDN      equ #0064           ; the RAM disc's blocks: how many,
RS_RD       equ #0065           ;   then each, &80 + its number (up to RD_MAX)
RD_MAX      equ 32
RS_MOTOR    equ RS_RD+RD_MAX    ; 1/50 s until the drives' motors stop (0:
                                ;   they are off): page A's tick counts it
RS_HARN     equ RS_MOTOR+1      ; 1 on the test harness's disc (mkdisk.py
                                ;   --hook): the transcript's ring is filled
JB          equ #0100           ; the jumpblock, four bytes an entry
MTAB        equ #C100           ; machine page A's table, a word an entry
P_INIT      equ #C000           ; page A: its start (rs_boot calls it),
P_TICK      equ #C003           ;   the interrupt's work (the keys)
PB_TICK     equ #C003           ; page B: the interrupt's sound
FILE_BUFSIZE equ 64+512         ; a file's buffer: its state, a sector

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
J_M_NEXTY        equ 89
NJ             equ 90
