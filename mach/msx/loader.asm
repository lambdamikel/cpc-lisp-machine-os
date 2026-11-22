;; CPC Lisp -- the MSX's loader: LISP.COM's own code, after the resident
;; part (resident.asm includes this). Run once, under MSX-DOS 2, as any
;; program: it asks DOS for eight segments of the memory mapper -- the six
;; images, the two machine pages -- and for the RAM disc's (as many as are
;; free, up to RD_MAX), reads LISP.IMG (from LISP.COM's own folder: DOS's
;; PROGRAM) into them, a segment at a time through page 1, notes what the
;; resident part needs, and starts it (RS_BOOT). LISP.IMG: banks 0-5 (the
;; core, library parts 0-3, the VM), then machine pages A and B, 16 KB
;; each.
;;
;; What it reads of the machine: the main ROM's &002B (50 or 60 Hz) and
;; &002C (the keyboard) through RDSLT; DOS's segments in pages 2 and 3
;; (GET_P2, GET_P3); the mapper support routines (EXTBIO, device 4).

LD_BUF      equ #4000           ; a segment read here, then copied
NIMG        equ 8

ld_start:
    ld hl,#0080                 ; "LISP /T": under the test harness (the
    ld b,(hl)                   ;   transcript to port &2F)
    inc b
.arg:
    dec b
    jr z,.args
    inc hl
    ld a,(hl)
    cp "/"
    jr nz,.arg
    inc hl
    dec b
    jr z,.args
    ld a,(hl)
    and #DF
    cp "T"
    jr nz,.arg
    ld a,1
    ld (RS_HOOK),a
.args:
    ld de,m_load
    call ld_print
    ld c,D_DOSVER               ; MSX-DOS 2 (Nextor too)?
    call DOS_BDOS
    or a
    jp nz,ld_nodos
    ld a,b
    cp 2
    jp c,ld_nodos
    ld a,(DOS_BDOS+2)           ; DOS's code above our stack in its page 3
    cp (DOS_STACK >> 8)+1
    jp c,ld_noroom
    xor a                       ; the mapper's routines: A = segments,
    ld de,#0402                 ;   C = free ones, HL = their jumps
    call EXTBIO
    or a
    jp z,ld_nomap
    ld (ld_mtab),hl
    ld a,c
    cp NIMG+1                   ; (and one for the RAM disc at least)
    jp c,ld_nosegs
    ld e,#27                    ; GET_P2: DOS's segments in pages 2, 3
    call ld_mcall
    ld (RS_TPA2),a
    ld e,#2D                    ; GET_P3
    call ld_mcall
    ld (RS_TPA3),a

    ld hl,RS_SEGS               ; the images' and pages' segments
    ld b,NIMG
.al:
    push bc
    push hl
    call ld_alloc
    pop hl
    pop bc
    jp c,ld_nosegs
    ld (hl),a
    inc hl
    djnz .al
    ld hl,RS_RD                 ; the RAM disc's: what is left
    ld c,0
.ar:
    ld a,c
    cp RD_MAX
    jr nc,.ard
    push bc
    push hl
    call ld_alloc
    pop hl
    pop bc
    jr c,.ard
    ld (hl),a
    inc hl
    inc c
    jr .ar
.ard:
    ld a,c
    ld (RS_RDN),a

    ld a,(EXPTBL)               ; the main ROM: 50 or 60 Hz, the keyboard
    ld hl,ROM_ID1
    call DOS_RDSLT
    ei
    ld b,60
    bit 7,a
    jr z,.hz
    ld b,50
.hz:
    ld a,b
    ld (RS_HZ),a
    ld a,(EXPTBL)
    ld hl,ROM_ID2
    call DOS_RDSLT
    ei
    and #0F
    ld (RS_KBD),a

    ld hl,s_program             ; LISP.IMG beside LISP.COM: PROGRAM's
    ld de,ld_path               ;   folder, or the current one
    ld b,ld_pathlen
    ld c,D_GENV
    call DOS_BDOS
    ld de,ld_path
    or a
    jr nz,.name
    ld hl,ld_path
.sep:
    ld a,(hl)
    or a
    jr z,.name
    inc hl
    cp #5C                      ; (a backslash)
    jr z,.at
    cp ":"
    jr nz,.sep
.at:
    ld d,h
    ld e,l
    jr .sep
.name:
    ld hl,s_img
    ld bc,s_img_len
    ldir
    ld de,ld_path
    ld a,1                      ; read only
    ld c,D_OPEN
    call DOS_BDOS
    or a
    jp nz,ld_nofile
    ld a,b
    ld (ld_fh),a

    ld hl,RS_SEGS
    ld b,NIMG
.img:
    push bc
    push hl
    ld a,(ld_fh)
    ld b,a
    ld de,LD_BUF
    ld hl,#4000
    ld c,D_READ
    call DOS_BDOS
    or a
    jp nz,ld_short
    ld a,h
    cp #40
    jp nz,ld_short
    pop hl
    push hl
    ld a,(hl)                   ; into its segment, through page 2
    di
    out (P_MAP2),a
    ld hl,LD_BUF
    ld de,MPAGE
    ld bc,#4000
    ldir
    ld a,(RS_TPA2)
    out (P_MAP2),a
    ei
    pop hl
    inc hl
    pop bc
    djnz .img
    ld a,(ld_fh)
    ld b,a
    ld c,D_CLOSE
    call DOS_BDOS

    ld de,r_abort               ; DOS's errors and aborts: ours
    ld c,D_DEFAB
    call DOS_BDOS
    ld de,r_diskerr
    ld c,D_DEFER
    call DOS_BDOS
    jp RS_BOOT

;; ld_alloc: -> A = a user segment of the primary mapper; carry if none
ld_alloc:
    xor a
    ld b,a
    ld e,0                      ; ALL_SEG
;; ld_mcall: E = the offset of a mapper routine in its jumps; A, B as it
;; takes them -> what it gives back
ld_mcall:
    ld hl,(ld_mtab)
    ld d,0
    add hl,de
    jp (hl)

ld_print:
    ld c,D_STROUT
    jp DOS_BDOS

ld_nodos:
    ld de,m_nodos
    jr ld_fail
ld_noroom:
    ld de,m_noroom
    jr ld_fail
ld_nomap:
    ld de,m_nomap
    jr ld_fail
ld_nosegs:
    ld de,m_nosegs
    jr ld_fail
ld_nofile:
    ld de,m_nofile
    jr ld_fail
ld_short:
    ld de,m_short
ld_fail:
    call ld_print
    ld c,D_TERM0                ; (DOS frees what was allocated)
    jp DOS_BDOS

m_load:     db "CPC Lisp: loading",13,10,"$"
m_nodos:    db "MSX-DOS 2 or Nextor is needed",13,10,"$"
m_noroom:   db "DOS leaves too little memory",13,10,"$"
m_nomap:    db "A memory mapper is needed",13,10,"$"
m_nosegs:   db "Not enough mapper memory: 144 KB free is needed",13,10,"$"
m_nofile:   db "LISP.IMG is not beside LISP.COM",13,10,"$"
m_short:    db "LISP.IMG cannot be read",13,10,"$"
s_program:  db "PROGRAM",0
s_img:      db "LISP.IMG",0
s_img_len   equ $-s_img
ld_mtab:    dw 0
ld_fh:      db 0
ld_pathlen  equ 128
ld_path:    defs ld_pathlen,0
ld_end:
    print "LISP.COM: ",ld_end-RESIDENT," bytes"
    assert ld_end <= LD_BUF
