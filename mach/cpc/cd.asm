;; CPC Lisp -- the disc drive: (cd), through the disc ROM's |DRIVE --
;; AMSDOS's, Parados's -- found as delete-file finds |ERA. The disc ROM
;; keeps the drive; V_DRIVE says which one Lisp chose (0: A, the disc
;; ROM's own at the start). In library part 0 on the ROMs (natives.asm
;; includes this), in part 1 on the 512K's, the plain 6128's and
;; FutureOS's island (mach/cpc512/drive.asm): where there is room.

CD_NAME     equ TOKBUF+80       ; "DRIVE", in RAM for KL FIND COMMAND
CD_STR      equ TOKBUF+85       ; the letter: a string of one
CD_DESC     equ TOKBUF+86       ; its descriptor: length, address
CD_PARM     equ TOKBUF+89       ; |DRIVE's parameter: the descriptor's address

;; (cd "b:"): the drive a name without one goes to from now on, (dir)'s too
;; -> T, or NIL for no such drive (A-P) or no |DRIVE; (cd nil): A again;
;; (cd) -> that drive, "A:"...
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
    ld a,"A"
    jr z,.set                   ; (cd nil)
    ex de,hl
    call lstring
    ld a,b
    or c
    jr z,.no
    ld a,(hl)
    and #DF
    sub "A"
    cp 16
    jr nc,.no
    add a,"A"
.set:
    ld hl,cd_tpl                ; |DRIVE's name and parameter, in RAM
    ld de,CD_NAME
    ld bc,cd_tpl_end-cd_tpl
    ldir
    ld (CD_STR),a
    ld hl,CD_NAME
    call KL_FIND_COMMAND
    jr nc,.no                   ; no disc ROM, or none with |DRIVE
    ld ix,CD_PARM
    ld a,1
    call KL_FAR_PCHL
    bit 7,a                     ; (AMSDOS: A = the drive's number, or an
    jr nz,.no                   ;   error it has told: &90, "Bad command")
    ld a,(CD_STR)
    ld (V_DRIVE),a
    jp lt
.no:
    jp lnil
.ask:
    ld a,(V_DRIVE)
    or a
    jr nz,.say
    ld a,"A"
.say:
    ld hl,TOKBUF
    ld (hl),a
    inc hl
    ld (hl),":"
    ld c,2
    jp lstr_result
cd_tpl:     db "DRIV","E"+#80   ; CD_NAME
            db 0                ; CD_STR
            db 1 : dw CD_STR    ; CD_DESC
            dw CD_DESC          ; CD_PARM
cd_tpl_end:
    assert cd_tpl_end-cd_tpl == CD_PARM+2-CD_NAME
