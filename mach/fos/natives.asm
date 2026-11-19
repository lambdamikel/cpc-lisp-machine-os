;; CPC Lisp on FutureOS itself -- the machine's own Lisp functions, in
;; library part 0 (lib/gfx.asm includes this): the 512K CPC's, and cd.

    include "../cpc512/natives.asm"

;; (cd "e:"): the drive for a name without one -- load, save, open, dir --
;; from now on (FutureOS's drives A-L; M: is Lisp's RAM disc: "m:" names
;; it) -> T, or NIL for no such drive. Its directory must be one FutureOS
;; has read, as for any name.
;@ CD 1 1 lf_cd
lf_cd:
    call lstring
    ld a,b
    or c
    jp z,lnil
    ld a,(hl)
    and #DF
    sub "A"
    cp 12
    jp nc,lnil
    ld (RS_DRIVE),a
    jp lt
