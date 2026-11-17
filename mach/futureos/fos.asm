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

;; System variables (&B800-&BBFF)
RAMCHAR     equ #B847           ; the gate array's mode/ROM byte (&7Fxx)

;; ROM A: text
TERM_2      equ #D48C           ; HL = a string ending in 0, control codes
                                ;   work; mode 2; a charset at &3800
PR_2        equ #C9BD           ; one mode 2 character

;; ROM D: back to the desktop
KLICK       equ #FE9A           ; the icons kept (only the lower part used)
TUR_E       equ #FE9D
TUR_D       equ #FEA0           ; the whole screen redrawn
