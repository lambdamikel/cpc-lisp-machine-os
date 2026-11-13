;; CPC Lisp -- the TRS-80 Model 4 under LS-DOS 6.3.1: its hardware, its
;; ROM (the Model III's: the floats) and LS-DOS's supervisor calls, as the
;; machine layer uses them. Included by src/defs.asm (through machine.asm's
;; jumps.asm too).

;; MEMORY, in memory map 2: the keyboard and the screen over &F400-&FFFF
VRAM        equ #F800           ; the screen: 24 rows of 80 characters
VROWS       equ 24
VCOLS       equ 80
KBD         equ #F400           ; the keyboard matrix: row r at &F400 + 2^r
OPREG       equ #84             ; port (write): the memory map, the banks,
OP_MAP      equ #03             ;   bits 0-1: 3 all RAM, 2 the keyboard and
                                ;   screen at &F400, 0 the ROM at &0000
OP_BANK     equ #70             ;   bits 4-6: a 32 KB bank at &8000 (&20:
                                ;   LS-DOS's bank 1, &30: bank 2)
SLOTS       equ 8               ; a slot is half a bank: slot s is bank s/2 - 1,
                                ;   at &C000 if s is odd, else at &8000; 2-7
                                ;   (a ROM number of 0 is none to the core)
CORESLOT    equ 3               ; the core: bank 0, &C000
MACHSLOT    equ 7               ; the machine page (page.asm): bank 2, &C000

;; LS-DOS 6.3.1's supervisor calls: A = the number, then RST &28 -- always
;; through the resident part's gate (RS_SVC), which puts LS-DOS's bank in
SV_KEY       equ 1               ; -> A = a key from *KI: waits
SV_DSP       equ 2               ; C = a character to *DO
SV_GET       equ 3               ; DE = an FCB or DCB -> A = a byte, Z if it went
SV_PUT       equ 4               ; DE = an FCB or DCB, C = a byte -> Z if it went
SV_KBD       equ 8               ; -> A = a key, Z if there is one (else NZ)
SV_KEYIN     equ 9               ; HL = a buffer, B = its length -> a line
SV_DSPLY     equ 10              ; HL = a message ending in 13
SV_TIME      equ 19              ; HL = 8 bytes -> "HH:MM:SS"
SV_EXIT      equ 22              ; HL = a return code: back to LS-DOS Ready
SV_ADTSK     equ 29              ; DE = a task block, C = its slot
SV_RMTSK     equ 30              ; C = the slot
SV_DODIR     equ 34              ; the directory, B = a function
SV_RAMDIR    equ 35
SV_REMOV     equ 57              ; DE = an open FCB: the file deleted
SV_INIT      equ 58              ; HL = a 256-byte buffer, DE = FCB, B = LRL
SV_OPEN      equ 59              ;   (the same: an existing file only)
SV_CLOSE     equ 60              ; DE = FCB
SV_READ      equ 67              ; DE = FCB: the next record into the buffer
SV_WRITE     equ 75
SV_FSPEC     equ 78              ; HL = a name, DE = an FCB -> NZ if bad
SV_HIGH      equ 100             ; B = 0 HIGH$ (1 LOW$), HL = 0 -> HL = it
SV_FLAGS     equ 101             ; -> IY = the system flags
SV_BANK      equ 102             ; B = a function, C = a bank
SV_SOUND     equ 104
SV_CKBRKC    equ 106             ; -> NZ if BREAK was pressed (it is cleared)
F_OFLAG     equ 'O'-'A'         ; the flags: the image of OPREG

;; trs80gp's emulator extensions (-ee): a function code out to port &47
EE_PORT     equ #47
