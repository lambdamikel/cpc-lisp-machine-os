;; CPC Lisp -- no RAM disc on the Model 4: its second 64 KB holds the code.
;; An M: name is still the RAM disc's, and says so (lib/disc.asm includes
;; this).

;; RDISC_IS: TOKBUF holds a file name -> Z if it is on drive M:. A only.
RDISC_IS:
    ld a,(TOKBUF+1)
    cp ':'
    ret nz
    ld a,(TOKBUF)
    or #20
    cp 'm'
    ret
;; RDISC_IN, RDISC_OUT, RDISC_CAT: an error (the file buffer given back)
RDISC_IN:
RDISC_OUT:
RDISC_CAT:
rd_none:
    call fl_release
    ld hl,rd_m_noram
    ld de,UNBOUND
    jp lib_error
rd_m_noram: db "no RAM disc on a Model 4",0

;; (delete-file "name") -> T, through LS-DOS's @REMOV. An error if there is
;; no such file.
;@ DELETE-FILE 1 1 lf_delete_file
lf_delete_file:
    push hl
    call fl_name
    call RDISC_IS
    jr z,.m
    push bc
    call fl_lend                ; DE = a buffer, for the FCB
    pop bc
    call M_DELETE
    push af
    call fl_release
    pop af
    pop de
    jp c,lt
    ld hl,rd_m_none
    jp lib_error
.m:
    pop de
    jr rd_none
rd_m_none:  db "no such file:",0
