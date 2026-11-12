;; CPC Lisp -- the TRS-80's own Lisp functions, in library part 0
;; (lib/gfx.asm includes this).

;; (quit): back to LDOS -- or, in trs80gp with -ee, out of the emulator
;@ QUIT 0 0 lf_quit
lf_quit:
    jp M_QUIT
