;; CPC Lisp on FutureOS itself -- the disc drive, in library part 1
;; (lib/lib2.asm includes this): (cd). RS_DRIVE (0-11: A-L) is the drive
;; the page's file routines (page.asm) take for a name without one, and
;; CAS CATALOG lists; RS_START the one LISP.64K came from.

;; (cd "e:"): the drive a name without one goes to from now on, (dir)'s
;; too -> T, or NIL for no such drive (A-L; M: is Lisp's RAM disc); (cd
;; nil): LISP.64K's again; (cd) -> that drive, "A:"... Its directory must
;; be one FutureOS has read, as for any name.
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
    ld a,(RS_START)
    jr z,.set                   ; (cd nil)
    ex de,hl
    call lstring
    ld a,b
    or c
    jp z,lnil
    ld a,(hl)
    and #DF
    sub "A"
    cp 12
    jp nc,lnil
.set:
    ld (RS_DRIVE),a
    jp lt
.ask:
    ld a,(RS_DRIVE)
    add a,"A"
    ld hl,TOKBUF
    ld (hl),a
    inc hl
    ld (hl),":"
    ld c,2
    jp lstr_result
