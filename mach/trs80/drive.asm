;; CPC Lisp -- the disc drive on the TRS-80, in library part 1
;; (lib/lib2.asm includes this; the Model 4's links here): (cd). The
;; machine page keeps the drive (M_DRIVE, files80.asm / files4.asm).

;; (cd "b:"): the drive a name without one goes to from now on -- A-D,
;; LDOS's :0-:3 -- and the one (dir) lists -> T, or NIL for no such drive;
;; (cd nil): none again (LDOS looks in every drive, (dir) lists them all);
;; (cd) -> that drive, "B:"..., or NIL for none
;@ CD 0 1 lf_cd
lf_cd:
    ld a,b
    or a
    jr z,.ask
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,d
    or e
    jr z,.set                   ; (cd nil): A = 0
    ex de,hl
    call lstring
    ld a,b
    or c
    jp z,lnil
    ld a,(hl)
.set:
    call M_DRIVE
    jp nc,lnil
    jp lt
.ask:
    ld a,#FF
    call M_DRIVE
    or a
    jp z,lnil
    ld hl,TOKBUF
    ld (hl),a
    inc hl
    ld (hl),":"
    ld c,2
    jp lstr_result
