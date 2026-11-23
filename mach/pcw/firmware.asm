;; CPC Lisp -- the Amstrad PCW 8256/8512 (the Schneider Joyce): the
;; hardware, as the machine layer uses it. There is no firmware: no ROM at
;; all once the machine has booted (the printer's controller hands the Z80
;; a boot program at power-on, which loads a disc's first sector). Included
;; by src/defs.asm (and by the resident part, the machine pages, the boot
;; sector and the loader).

;; MEMORY: blocks of 16 KB -- 16 on an 8256, 32 on an 8512 -- and ports
;; &F0-&F3 (write only), what the Z80 sees at &0000, &4000, &8000, &C000:
;; &80 + a block ("extended" paging; a block past the RAM is taken modulo
;; it). The keyboard is the last 16 bytes of block 3, whenever block 3 is
;; seen; the screen may be anywhere in blocks 0-7.
P_MAP0      equ #F0
P_MAP1      equ #F1
P_MAP2      equ #F2
P_MAP3      equ #F3

;; THE SYSTEM PORTS. &F4 read: bits 0-3 the 300 Hz ticks since it was last
;; read (up to 15; reading makes them 0 and answers the interrupt). &F5:
;; where the roller RAM is (bits 5-7 its block, 0-4 its offset / 512);
;; &F6: the roller RAM's line at the top of the screen; &F7: bit 6 the
;; screen on, bit 7 inverse. &F8 written: a command (below); read: bit 5
;; the disc controller wants attention, bit 6 the frame's flyback, bit 4 a
;; 60 Hz machine (200 lines seen), bits 0-3 the ticks (not cleared).
P_TICKS     equ #F4
P_ROLLER    equ #F5
P_ORIGIN    equ #F6
P_VIDEO     equ #F7
P_SYS       equ #F8
SC_REBOOT   equ 1               ; the boot program again: the disc in A boots
SC_FDCINT   equ 3               ; the disc controller's interrupts to INT,
SC_FDCNONE  equ 4               ;   or nowhere (polled: P_SYS bit 5)
SC_TCON     equ 5               ; the controller's terminal count: a
SC_TCOFF    equ 6               ;   transfer's end
SC_MOTON    equ 9               ; the drives' motors
SC_MOTOFF   equ 10
SC_BEEPON   equ 11              ; the beeper: one tone, on or off
SC_BEEPOFF  equ 12

;; THE DISC CONTROLLER: a uPD765A without DMA (as the CPC's): its main
;; status at &00, its data at &01; the terminal count through P_SYS.
P_FDCST     equ #00
P_FDCDAT    equ #01

;; THE DKTRONICS SOUND GENERATOR (an AY-3-8912, if one is plugged in):
;; &AA selects a register, &AB writes it, &A9 reads it. Its clock is taken
;; for the Spectrum's, 1.7734 MHz (ZEsarUX's); the beeper sounds too while
;; a note plays (pageb.asm: ay_pcw).
P_AYRD      equ #A9
P_AYREG     equ #AA
P_AYDAT     equ #AB
AY_MUL      equ 227             ; a period 227/128 times the CPC's
AY_IO       equ #00             ; the mixer's port bits: both inputs
;; AY_OUT: A = a register, C = a value -> written; B kept, AF lost; it
;; returns (sound.asm's ay_w)
macro AY_OUT
    jp ay_pcw
mend

;; THE BLOCKS, as Lisp uses them (the loader puts them there)
BL_LO       equ 4               ; at &0000: the resident part, the low area,
BL_MID      equ 5               ;   the cells; at &4000;
BL_HI       equ 6               ;   at &8000: block space, the stack, the
                                ;   fixed area
BL_IMG      equ 8               ; the six images: blocks 8-13, at &C000 in
                                ;   turn
BL_PA       equ 14              ; machine page A, at &C000 while it runs
BL_PB       equ 15              ;   and B
BL_SCR0     equ 1               ; the screen: character rows 0-21,
BL_SCR1     equ 3               ;   22-31 and the roller RAM (with the keys)
BL_KEYS     equ 3               ; the keyboard: its last 16 bytes
KEYMAP      equ #3FF0           ;   (within the block)
SCR_SPLIT   equ 22              ; the rows in BL_SCR0
ROLLER      equ #1E00           ; the roller RAM, in BL_SCR1
WINDOW      equ #4000           ; where a block is seen for a moment (port
                                ;   &F1: RS_P1 says what is there)
RD_BLOCKS   equ 3               ; the RAM disc on an 8256: blocks 0, 2, 7;
                                ;   an 8512's 16-31 too
