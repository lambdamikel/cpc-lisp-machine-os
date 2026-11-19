;; CPC Lisp -- FutureOS's API, the entries this machine uses.
;;
;; From TFM's public documentation (futureos.de: API-ENG, API-A..D;
;; "How to create an Application for FutureOS"; his HELLO.MAX/HW.64K),
;; FutureOS System .8. TFM's label file #EQU-API.ENG is the reference;
;; the addresses here are checked against his binaries where they occur.
;; Nothing of FutureOS itself is in this repository.

;; The API page, the same in all four OS ROMs (API-ENG): jump to HL in
;; ROM A..D (BC is lost), or call IX in another ROM and come back.
ROM_A       equ #FF00
ROM_B       equ #FF06
ROM_C       equ #FF0C
ROM_D       equ #FF12
ROM_A2B     equ #FF18
ROM_A2C     equ #FF2A
ROM_A2D     equ #FF3C
OSRON_A     equ #FF22           ; bank ROM A in, nothing else
FOS_ROMNUM_A equ #FF01          ; ROM A's physical number, &DF after it:
FOS_ROMNUM_B equ #FF07          ;   `ld bc,(FOS_ROMNUM_x) : out (c),c`
FOS_ROMNUM_C equ #FF0D
FOS_ROMNUM_D equ #FF13

;; System variables (&B800-&BBFF). Those LADE_N uses (API-C) are found
;; in its code (ROM C &D0CC): REG08_4 and REG16_3 are read where it loads
;; a file without a header, REG_PC+1 is written with the medium.
RAMCHAR     equ #B847           ; the gate array's mode/ROM byte (&7Fxx)
AKT_RAM     equ #B84C           ; an E-RAM block to load into, &7Fxx
TURBO_A     equ #B858           ; 8 bytes a medium, A-M: +0 tagged (bit 0),
                                ;   +1 the block its directory is buffered
                                ;   in, +2 its page there, +3 its pages
REG_BC1     equ #B8C4           ; TEISI: the file's blocks (low byte)
REG_PC      equ #B8DA           ; +1: the medium the last file came from
REG08_1     equ #B8DD           ; EWEG: the drive
REG08_4     equ #B8E0           ; LADE_N: the type of loading (2: the main
REG16_3     equ #B8EA           ;   RAM) and the address, for a file whose
                                ;   header is not used
REG16_8     equ #B8F4           ; TEISI, EWEG: user, name, extension (12)
XRAM_C4     equ #B9D0           ; 32 bytes: what each E-RAM block holds
IDE_32_39   equ #BBCC           ; TEISI: the last extent's records (RC), and
IDE_40_47   equ #BBCD           ;   the last record's bytes (S1; G_BLK sets
                                ;   both, ROM C &FBD5)

;; ROM A: text
TERM_2      equ #D48C           ; HL = a string ending in 0, control codes
                                ;   work; mode 2; a charset at &3800
PR_2        equ #C9BD           ; one mode 2 character

;; ROM C: files
LADE_N      equ #FD5C           ; A = the medium (0-14: A-O; + &80: the
                                ;   header's addresses not used), DE = user,
                                ;   name (8), extension (3), in one page;
                                ;   its directory must have been read. A =
                                ;   &FF: loaded; 0, 1, 2: no directory read,
                                ;   that one not read, no such file

TEISI       equ #FD56           ; A = a drive (0-7): the file in REG16_8 written
                                ;   from the short-time buffers (the XRAM's
                                ;   &09 blocks, in order -- FESB marks every
                                ;   free one so first); A = &FF: written
EWEG        equ #FD7A           ; REG08_1, REG16_8: deleted in the buffered
                                ;   directory (marked changed)

;; ROM B: the directories
SIDIR       equ #FDE8           ; every changed directory written back

;; ROM D: back to the desktop
KLICK       equ #FE9A           ; the icons kept (only the lower part used)
TUR_E       equ #FE9D
TUR_D       equ #FEA0           ; the whole screen redrawn
