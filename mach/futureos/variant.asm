;; CPC Lisp -- under FutureOS: the 512K CPC's resident part (mach/cpc512,
;; links to its files), which goes back to FutureOS's desktop where the
;; 512K CPC's resets (FUTUREOS: resident.asm, fosback.asm); jumps.asm
;; includes this.

RESIDENT        equ #A100       ; 96 bytes below the 512K CPC's: VDOS 2.0,
RESIDENT_END    equ #A6B0       ;   the Vortex's ROM 7, takes &052E bytes of
                                ;   workspace (AMSDOS &0500) and leaves &A6CD
                                ;   -- under &A6F0 it said "Too many ROMs"
                                ;   on Mike's 464 (2026-11-17); and the way
                                ;   back (r_reset) is longer than the 512K's
RAMDISC         equ 1
FUTUREOS        equ 1           ; (quit), (reset), (basic): back to FutureOS
FOS_SAVE_CFG    equ #FF         ; FutureOS's RAM kept in bank 7's block 3
                                ;   (at &4000: C7 + 8 * 7), by LISP.64K:
                                ;   &A000-&BFFF at &4000, &0000-&00FF at
FOS_SAVE_BACK   equ #6100       ;   &6000, the way back (fosback.asm) here,
FOS_BACK_LEN    equ 192         ;   at most this long (the reset copies it),
FOS_SAVE_ROMD   equ #61C0       ;   ROM D's number, then &DF,
FOS_SAVE_ROMB   equ #61C2       ;   ROM B's,
FOS_KEEP        equ #7000       ;   and while FutureOS loads the images,
                                ;   LISP.64K's first 4 KB (loader.asm)
XBUF            equ 1           ; the disc files' buffers: bank 7's block 2 at
XB_UNITS        equ 2           ;   &4000 (C6 + 8 * 7), the RAM disc's unit
XB_IN           equ #4000       ;   below FutureOS's, given up too
XB_OUT          equ #4800       ;   (resident.asm): an input file's 2 KB, an
XB_CAT          equ #5000       ;   output file's, 4 KB for CAS CATALOG,
XB_FONT         equ #6000       ;   the function editor's font copy (768)
