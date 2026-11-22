;; CPC Lisp -- an MSX1 with a memory mapper, under MSX-DOS 2 (Nextor):
;; the hardware, the BIOS and DOS, as the machine layer uses them. Included
;; by src/defs.asm (and by the resident part, the machine pages and the
;; loader).

;; THE MEMORY MAPPER: ports &FC-&FF, write only -- the segment (16 KB) in
;; pages 0-3. DOS 2 gives a program its segments (ALL_SEG, the mapper
;; support routines, EXTBIO) and keeps its own idea of pages 0-2 (PUT_Pn):
;; the resident part puts DOS's back before every call. Page 3 is DOS's
;; system segment; while Lisp runs an image is there instead.
P_MAP0      equ #FC
P_MAP1      equ #FD
P_MAP2      equ #FE
P_MAP3      equ #FF
MPAGE       equ #8000           ; where a machine page is seen (page 2)

;; THE VDP (TMS9918A/9929A): data at &98, control at &99. Screen 2
;; (Graphics II), 256 by 192: the pattern table at &0000 (6 KB, a byte
;; for each 8 pixels across, eight rows of a cell together), the names at
;; &1800 (0-255, three times), the colours at &2000 (6 KB, foreground and
;; background for each 8 pixels), sprites off.
P_VDPDAT    equ #98
P_VDPCTL    equ #99
VR_PAT      equ #0000
VR_NAME     equ #1800
VR_COL      equ #2000
VR_SPRATT   equ #1B00

;; THE PPI (8255): &A8 the primary slots (never touched here), &A9 a row of
;; the keyboard (0 when down), &AA bits 0-3 which row, bit 4 the cassette
;; motor (1 off), bit 5 its output, bit 6 the CAPS lamp (0 on), bit 7 the
;; key click.
P_PPIA      equ #A8
P_KEYROW    equ #A9
P_PPIC      equ #AA

;; THE PSG (AY-3-8910): register at &A0, value at &A1, read at &A2;
;; clocked at 1.7898 MHz (the CPC's at 1 MHz). Register 7's bit 6 must be
;; 0 (port A an input: joysticks, the keyboard's layout bit), bit 7 1
;; (port B an output).
P_AYREG     equ #A0
P_AYDAT     equ #A1
P_AYRD      equ #A2
AY_MUL      equ 229             ; a period 229/128 times the CPC's
AY_IO       equ #80             ; the mixer's port bits: B out, A in
;; AY_OUT: A = a register, C = a value -> written; B kept, AF lost; it
;; returns (sound.asm's ay_w)
macro AY_OUT
    out (P_AYREG),a
    ld a,c
    out (P_AYDAT),a
    ret
mend

;; OPENMSX (the emulator the tests run in): the harness watches writes to
;; port &2F -- the transcript, a byte each. Written only when the harness
;; has said so (c_echo, from the paste buffer's first line).
P_DEBUG     equ #2F

;; THE MAIN ROM (BIOS and BASIC, its slot in EXPTBL): what is read of it
ROM_ID1     equ #002B           ; bit 7: 50 Hz (else 60); bits 0-3 the
                                ;   character set
ROM_ID2     equ #002C           ; bits 0-3 the keyboard: 0 Japanese, 1
                                ;   international, 2 French, 3 British,
                                ;   4 German...
INITXT      equ #006C           ; the BIOS: SCREEN 0 (for DOS, at the end)
CHGMOD      equ #005F

;; THE MATH-PACK (the main ROM's: BASIC's maths, decimal, 14 digits): a
;; number is 8 bytes -- bit 7 the sign, bits 0-6 the exponent (64: 0.d1d2...
;; times 10^0; 0 is zero), then 14 digits of BCD, d1 not 0. The routines
;; work on DAC (and ARG), VALTYP 8 (double); an error would end in BASIC's
;; error handler: what would cause one is looked for first (fpmsx.asm).
MP_DECMUL   equ #27E6           ; DAC = DAC * ARG
MP_COS      equ #2993
MP_SIN      equ #29AC
MP_TAN      equ #29FB
MP_ATN      equ #2A14
MP_LOG      equ #2A72
MP_SQR      equ #2AFF
MP_EXP      equ #2B4A
MP_DAC      equ #F7F6
MP_ARG      equ #F847
MP_VALTYP   equ #F663

;; THE BIOS'S AND DOS'S PAGE 3 (seen only with DOS's segment there)
EXPTBL      equ #FCC1           ; the main ROM's slot, then each slot's
                                ;   expanded bit
EXTBIO      equ #FFCA           ; the extended BIOS: D = device
LINL40      equ #F3AE           ; SCREEN 0's width
RAMAD1      equ #F342           ; the RAM's slot in page 1 (DOS's)

;; DOS's page 0 (in our page 0 too)
DOS_BDOS    equ #0005           ; C = a function
DOS_RDSLT   equ #000C           ; A = slot, HL = address -> A
DOS_CALSLT  equ #001C           ; IY = slot (high byte), IX = address
DOS_ENASLT  equ #0024           ; A = slot, H = the page's address: every
                                ;   register lost
DOS_INT     equ #0038           ; the interrupt: a JP, ours while Lisp runs

;; MSX-DOS 2's functions
D_TERM0     equ #00
D_CONOUT    equ #02
D_STROUT    equ #09
D_SELDSK    equ #0E             ; E = a drive (0 A:) -> A = drives
D_LOGIN     equ #18             ; -> HL: bit n, drive n is there
D_CURDRV    equ #19             ; -> A = the current drive (0 A:)
D_ALLOC     equ #1B             ; E = a drive (0 the current) -> A =
                                ;   sectors a cluster, HL = free clusters
D_FFIRST    equ #40             ; DE = a name, B = attributes, IX = a FIB
D_FNEXT     equ #41             ;   IX = the FIB
D_OPEN      equ #43             ; DE = a name, A = mode -> B = handle
D_CREATE    equ #44             ; DE = a name, A = mode, B = attributes
D_CLOSE     equ #45             ; B = handle
D_READ      equ #48             ; B = handle, DE = buffer, HL = bytes -> HL
D_WRITE     equ #49
D_DELETE    equ #4D             ; DE = a name
D_TERM      equ #62             ; B = an error code
D_DEFAB     equ #63             ; DE = the abort routine
D_DEFER     equ #64             ; DE = the disc error routine
D_GENV      equ #6B             ; HL = a name, DE = a buffer, B = its size
D_DOSVER    equ #6F             ; -> B = the kernel's major version
E_EOF       equ #C7             ; DOS's "end of file"
E_NOFIL     equ #D7             ; "file not found"
