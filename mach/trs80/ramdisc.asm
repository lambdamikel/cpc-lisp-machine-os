;; CPC Lisp -- the RAM disc, drive M:, on the TRS-80: X-MEM/80's pages
;; 9-31, 368 KB, kept by the machine page (rdisc80.asm). lib/disc.asm
;; includes this.

;; RDISC_IS: TOKBUF holds a file name -> Z if it is on drive M:. A only.
RDISC_IS:
    ld a,(TOKBUF+1)
    cp ':'
    ret nz
    ld a,(TOKBUF)
    or #20
    cp 'm'
    ret
;; RDISC_IN, RDISC_OUT: TOKBUF holds "M:name", B its length, DE = the
;; file's buffer -> carry if it is open; RDISC_CAT: its files listed
RDISC_IN:
    jp M_RDIN
RDISC_OUT:
    jp M_RDOUT
RDISC_CAT:
    jp M_RDCAT

;; (delete-file "name") -> T: on M:, from the RAM disc; else LDOS's @KILL.
;; An error if there is no such file.
;@ DELETE-FILE 1 1 lf_delete_file
lf_delete_file:
    push hl
    call fl_name
    push bc
    call fl_lend                ; DE = a buffer, for the FCB or the moving
    pop bc
    call M_DELETE
    push af
    call fl_release
    pop af
    pop de
    jp c,lt
    ld hl,rd_m_none
    jp lib_error
rd_m_none:  db "no such file:",0
