;; CPC Lisp -- the TRS-80 Model I and III: the hardware, the ROM and LDOS,
;; as the machine layer uses them. Included by src/defs.asm (through
;; machine.asm's jumps.asm too).

;; MEMORY
VRAM        equ #3C00           ; the screen: 16 rows of 64 characters
VROWS       equ 16
VCOLS       equ 64
KBD         equ #3800           ; the keyboard matrix: row r at &3800 + 2^r
PRINTER     equ #37E8           ; Model I printer: write a character, read
                                ;   the status (bit 7 busy)

;; X-MEM/80 in its X-MEM mode: 32 pages of 16 KB, one at &8000, one at &C000
XM_LO       equ 65              ; out: the page at &8000
XM_HI       equ 66              ; out: the page at &C000
HEAPPAGE    equ 1               ; at &8000 for good: the heap's upper half
COREPAGE    equ 2               ; the core, then the library parts and the VM:
                                ;   pages 3-7 (the loader puts them there)
MACHPAGE    equ 8               ; the machine page (page.asm)

;; TRS-80 ROM
ROM_KBD     equ #002B           ; -> A = a key, 0 if none (through LDOS's DCB)
ROM_KEY     equ #0049           ; -> A = a key: waits for one
ROM_DSP     equ #0033           ; A = a character to the screen (LDOS's driver)

;; LDOS 5.3 (Model I and III alike)
L_DSPLY     equ #4467           ; HL = a message ending in 13 (or 3)
L_FSPEC     equ #441C           ; HL = a file name, DE = an FCB -> NZ if bad
L_OPEN      equ #4424           ; HL = a 256-byte buffer, DE = FCB, B = LRL
L_INIT      equ #4420           ;   the same, made if it is not there
L_CLOSE     equ #4428           ; DE = FCB
L_READ      equ #4436           ; DE = FCB: the next record into the buffer
L_WRITE     equ #4439
L_EXIT      equ #402D           ; back to LDOS Ready
L_TIME      equ #4041           ; seconds, minutes, hours (Model I)

;; trs80gp's emulator extensions (-ee): a function code out to port &47
EE_PORT     equ #47
