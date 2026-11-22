;; CPC Lisp -- the ZX Spectrum +2A/+2B/+3 with a DivMMC: the hardware, the
;; ROM and esxDOS, as the machine layer uses them. Included by src/defs.asm
;; (and by the resident part, the machine pages and the loader).

;; PAGING. &7FFD: bits 0-2 the RAM bank at &C000, bit 3 the screen (0: bank
;; 5), bit 4 the ROM's low bit, bit 5 locks it all. &1FFD: bit 0 the
;; all-RAM modes (never here), bit 2 the ROM's high bit, bit 3 the disc
;; motor, bit 4 the printer's strobe. ROM 3 -- 48 BASIC, with the
;; calculator and the font -- is &10 and &04.
P_7FFD      equ #7FFD
P_1FFD      equ #1FFD
PG_7FFD     equ #10             ; ROM 3's half; OR the bank
PG_1FFD     equ #04             ;   and the other half
BANK_M      equ #5B5C           ; the 128K ROMs' copy of &7FFD, kept so
BANK678     equ #5B67           ;   (and of &1FFD): esxDOS may look

;; THE DIVMMC: port &E3, write only -- bit 7 CONMEM (its EEPROM at &0000,
;; a RAM page at &2000, whatever automapping says), bit 6 MAPRAM (never),
;; bits 0-5 the page of its RAM at &2000 (8 KB each: 16 on a 128 KB one).
;; esxDOS has pages 0-4 for itself; the machine layer is in pages 14 and 15
;; (page.asm), the RAM disc in the rest (rdisc.asm).
P_DIVMMC    equ #E3
CONMEM      equ #80
MP_A        equ 14              ; the machine page A: screen, keys, sound
MP_B        equ 15              ;   and B: files, floats, the RAM disc
E3_A        equ CONMEM+MP_A
E3_B        equ CONMEM+MP_B
MPAGE       equ #2000           ; where a DivMMC page is seen

;; THE ULA: port &FE -- out: the border (bits 0-2), the speaker (bit 4);
;; in: a half-row of the keyboard, chosen by A8-A15 (0 selects; bits 0-4
;; are its keys, 0 when down).
P_ULA       equ #FE
SCREEN      equ #4000           ; 6144 bytes of pixels, 768 of attributes
ATTRS       equ #5800

;; THE AY-3-8912 (the 128K's sound): register at &FFFD, data at &BFFD;
;; clocked at 1.7734 MHz (the CPC's at 1 MHz): a period 227/128 times the
;; CPC's; its port A an output (the RS232 and MIDI: the mixer's bit 6).
;; AY_OUT: A = a register, C = a value -> written; B kept, AF lost; it
;; returns (sound.asm's ay_w)
P_AYREG     equ #FFFD
P_AYDAT     equ #BFFD
AY_MUL      equ 227
AY_IO       equ #40
macro AY_OUT
    push bc
    ld b,c
    ld c,P_AYREG and #FF
    push bc                     ; (B: the value)
    ld b,P_AYREG >> 8
    out (c),a
    pop af                      ; A = the value
    ld b,P_AYDAT >> 8
    out (c),a
    pop bc
    ret
mend

;; THE 48 BASIC ROM (ROM 3)
ROM_FONT    equ #3D00           ; characters 32-127, 8 bytes each
ROM_CALC    equ #28             ; RST 28: the calculator
SV_ERRNR    equ #5C3A           ; IY's place: ERR_NR
SV_ERRSP    equ #5C3D           ; ERR_SP: where an error's RET goes
SV_STKBOT   equ #5C63           ; the calculator's stack: its bottom,
SV_STKEND   equ #5C65           ;   its end
SV_BREG     equ #5C67
SV_MEM      equ #5C68           ; its memory: MEMBOT, 30 bytes
SV_MEMBOT   equ #5C92
CALC_STK    equ #5CB6           ; our calculator stack, to &5CFF

;; ESXDOS: RST 8, then a function's byte; pointers in IX (a program's, not
;; a dot command's); carry and A = the error on failure
ESX_GETSETDRV equ #89
ESX_OPEN    equ #9A             ; A = drive, IX = name, B = mode -> A = handle
ESX_CLOSE   equ #9B
ESX_SYNC    equ #9C
ESX_READ    equ #9D             ; A = handle, IX = buffer, BC = bytes -> BC read
ESX_WRITE   equ #9E
ESX_SEEK    equ #9F
ESX_FSTAT   equ #A1
ESX_OPENDIR equ #A3             ; A = drive, IX = path -> A = handle
ESX_READDIR equ #A4             ; A = handle, IX = buffer -> A = 0 at the end
ESX_GETCWD  equ #A8
ESX_CHDIR   equ #A9
ESX_UNLINK  equ #AD             ; A = drive, IX = name
ESX_RENAME  equ #B0
FA_READ     equ #01             ; open modes
FA_WRITE    equ #02
FA_OPEN_EX  equ #00             ;   the file must be there,
FA_CREATE_AL equ #0C            ;   made afresh,

;; ZESARUX (the emulator the tests run in), with --hardware-debug-ports:
;; a register's number out to &CF3B, then its data to or from &DF3B.
;; Register 4 reads the version, a character at a time ("13.0"), 6 writes
;; a byte to the file --hardware-debug-ports-byte-file names (the test
;; transcript), 3 bit 0 ends the emulator. On a real machine nothing
;; answers: m_init looks before using them.
ZX_DBGREG   equ #CF3B
ZX_DBGDAT   equ #DF3B
