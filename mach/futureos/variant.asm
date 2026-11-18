;; CPC Lisp -- under FutureOS: the 512K CPC's resident part (mach/cpc512,
;; links to its files), which goes back to FutureOS's desktop where the
;; 512K CPC's resets (FUTUREOS: resident.asm, fosback.asm); jumps.asm
;; includes this.

RESIDENT        equ #A120       ; 64 bytes below the 512K CPC's: VDOS 2.0,
RESIDENT_END    equ #A6B0       ;   the Vortex's ROM 7, takes &052E bytes of
                                ;   workspace (AMSDOS &0500) and leaves &A6CD
                                ;   -- under &A6F0 it said "Too many ROMs"
                                ;   on Mike's 464 (2026-11-17)
RAMDISC         equ 1
FUTUREOS        equ 1           ; (quit), (reset), (basic): back to FutureOS
FOS_SAVE_CFG    equ #FF         ; FutureOS's RAM kept in bank 7's block 3
                                ;   (at &4000: C7 + 8 * 7), by LISP.64K:
                                ;   &A000-&BFFF at &4000, &0000-&00FF at
FOS_SAVE_BACK   equ #6100       ;   &6000, the way back (fosback.asm) here,
FOS_SAVE_ROMD   equ #6180       ;   ROM D's number, then &DF,
FOS_SAVE_ROMB   equ #6182       ;   ROM B's;
FOS_SAVE_CAT    equ #7000       ;   and 4 KB for CAS CATALOG (r_catalog)
