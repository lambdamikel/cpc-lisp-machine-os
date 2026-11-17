;; CPC Lisp -- under FutureOS: the 512K CPC's resident part (mach/cpc512,
;; links to its files), which goes back to FutureOS's desktop where the
;; 512K CPC's resets (FUTUREOS: resident.asm, fosback.asm); jumps.asm
;; includes this.

RESIDENT        equ #A160       ; as the 512K CPC's
RAMDISC         equ 1
FUTUREOS        equ 1           ; (quit), (reset), (basic): back to FutureOS
FOS_SAVE_CFG    equ #FF         ; FutureOS's RAM kept in bank 7's block 3
                                ;   (at &4000: C7 + 8 * 7), by LISP.64K:
                                ;   &A000-&BFFF at &4000, &0000-&00FF at
FOS_SAVE_BACK   equ #7000       ;   &6000, the way back (fosback.asm) here,
FOS_SAVE_ROMD   equ #7FFE       ;   ROM D's number, then &DF,
FOS_SAVE_ROMB   equ #7FFC       ;   ROM B's
