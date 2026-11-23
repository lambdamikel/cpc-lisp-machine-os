;; CPC Lisp -- the PCW's disc drives, in machine page B (pageb.asm includes
;; this): the uPD765A without DMA, polled -- the interrupts off for each
;; transfer (a byte every 32 us: the interrupt's work would lose one), the
;; ticks they miss counted all the same (port &F4: the clock loses none).
;; A transfer's end is the terminal count (port &F8's commands 5 and 6).
;; The motors (both drives' at once) go on for a transfer and off 2 s after
;; the last (RS_MOTOR, which page A's tick counts down).
;;
;; A drive's sectors are counted from track 0 side 0's first: a logical
;; track has the disc's sectors (9), a double-sided disc's alternate sides
;; (track t is cylinder t/2, head t mod 2) -- the geometry is the drive's
;; DPB's (files.asm), which fd_geo points at.

fd_unit:    db 0                ; the drive (0 A, 1 B)
fd_cyls:    db #FF,#FF          ; where each drive's head is (&FF: not known)
fd_try:     db 0
fd_op:      db 0                ; 0 read, 1 write
fd_n:       db 0                ; fd_ls's: sectors to go,
fd_cnt:     db 0                ;   this time
fd_ls:      dw 0                ;   the next one
fd_buf:     dw 0                ;   where it goes
fd_spt:     db 9                ; the geometry: sectors a track,
fd_sides:   db 1                ;   sides
fd_r:       defs 7,0            ; the controller's result bytes
fd_cmd:     db #66              ; READ DATA (MFM, deleted marks skipped) or
fd_hu:      db 0                ;   WRITE DATA (&45): head * 4 + unit
fd_cyl:     db 0
fd_head:    db 0
fd_sec:     db 0
            db 2                ;   512 bytes
fd_eot:     db 0
            db #2A,#FF
fd_recal:   db 7                ; RECALIBRATE
fd_ru:      db 0
fd_seek:    db #0F              ; SEEK
fd_su:      db 0
fd_ncn:     db 0
fd_sis:     db 8                ; SENSE INTERRUPT STATUS

;; fd_motor: the motors on, and up to speed (half a second) if they were
;; off; off 2 s after this. All but AF kept.
fd_motor:
    ld a,(RS_MOTOR)
    or a
    push af
    ld a,100
    ld (RS_MOTOR),a
    pop af
    ret nz
    ld a,SC_MOTON
    out (P_SYS),a
    push bc
    push hl
    ld hl,RS_FRAMES
    ld a,(hl)
    add a,150
    ld b,a
    ei
.w:
    ld a,(hl)
    sub b
    jp m,.w
    pop hl
    pop bc
    ret

;; fd_rd, fd_wr: HL = a logical sector, A = how many, DE = where (Lisp's
;; RAM or this page) -> read or written, a track's part at a time; carry
;; if it went. fd_unit, fd_spt and fd_sides say the drive.
fd_rd:
    push af
    xor a
    jr fd_rw
fd_wr:
    push af
    ld a,1
fd_rw:
    ld (fd_op),a
    pop af
    ld (fd_n),a
    ld (fd_ls),hl
    ld (fd_buf),de
    call fd_motor
.l:
    ld a,(fd_n)
    or a
    scf
    ret z
    ld hl,(fd_ls)
    call fd_chs                 ; C, D, E; B left on its track
    ld a,(fd_n)
    cp b
    jr nc,.max
    ld b,a
.max:
    ld a,b
    ld (fd_cnt),a
    call fd_xfer
    ret nc
    ld a,(fd_cnt)
    ld c,a
    ld b,0
    ld hl,(fd_ls)
    add hl,bc
    ld (fd_ls),hl
    ld a,(fd_n)
    sub c
    ld (fd_n),a
    jr .l

;; fd_chs: HL = a logical sector -> C = cylinder, D = head, E = sector,
;; B = the sectors left on its track from it
fd_chs:
    ld a,(fd_spt)
    ld e,a
    ld d,0
    xor a
.t:
    or a
    sbc hl,de
    jr c,.tr
    inc a
    jr .t
.tr:
    add hl,de
    ld c,a
    ld d,0
    ld a,(fd_sides)
    cp 2
    jr nz,.ss
    srl c
    rl d
.ss:
    ld a,(fd_spt)
    sub l
    ld b,a
    ld e,l
    inc e
    ret

;; fd_xfer: C = cylinder, D = head, E = first sector, B = how many ->
;; read into or written from (fd_buf), which moves past them; carry if it
;; went (three tries, the drive recalibrated before the last)
fd_xfer:
    ld a,3
    ld (fd_try),a
.again:
    push bc
    push de
    call fd_to                  ; the head there
    pop de
    pop bc
    jp nc,.fail
    ld a,c
    ld (fd_cyl),a
    ld a,d
    ld (fd_head),a
    add a,a
    add a,a
    ld hl,fd_unit
    or (hl)
    ld (fd_hu),a
    ld a,e
    ld (fd_sec),a
    add a,b
    dec a
    ld (fd_eot),a
    ld a,(fd_op)
    or a
    ld a,#66
    jr z,.c
    ld a,#45
.c:
    ld (fd_cmd),a
    push bc
    push de
    ld a,b
    add a,a
    ld d,a
    ld e,0                      ; DE = the bytes: 512 a sector
    ld hl,fd_cmd
    ld b,9
    di
    call fd_out
    ld hl,(fd_buf)
    ld c,P_FDCDAT
    ld a,(fd_op)
    or a
    jr nz,.wr
.rd:
    in a,(P_FDCST)
    rlca
    jr nc,.rd                   ; until a byte is there
    and #40                     ; (bit 5) the execution phase still?
    jr z,.res
    ini
    dec de
    ld a,d
    or e
    jr nz,.rd
    jr .tc
.wr:
    in a,(P_FDCST)
    rlca
    jr nc,.wr
    and #40
    jr z,.res
    outi
    dec de
    ld a,d
    or e
    jr nz,.wr
.tc:
    ld a,SC_TCON                ; the terminal count: the transfer's end
    out (P_SYS),a
.res:
    push hl
    call fd_in
    pop hl
    ld a,SC_TCOFF
    out (P_SYS),a
    ei
    pop de
    pop bc
    ld a,(fd_r)                 ; ST0
    and #C0
    jr z,.ok
    cp #40                      ; abnormal, but only the track's end (EN)?
    jr nz,.bad
    ld a,(fd_r+1)
    cp #80
    jr nz,.bad
.ok:
    ld (fd_buf),hl
    scf
    ret
.bad:
    ld a,(fd_r+1)
    and 2                       ; not writable: no use trying again
    jr nz,.fail
.retry:
    ld a,(fd_try)
    dec a
    ld (fd_try),a
    jr z,.fail
    cp 1
    jp nz,.again
    ld hl,fd_cyls               ; the last try: from track 0
    ld a,(fd_unit)
    add a,l
    ld l,a
    jr nc,.n
    inc h
.n:
    ld (hl),#FF
    jp .again
.fail:
    ei
    or a
    ret

;; fd_to: C = a cylinder -> fd_unit's head there (recalibrated first if
;; where it is is not known); carry if it went. B, DE, HL lost.
fd_to:
    ld hl,fd_cyls
    ld a,(fd_unit)
    add a,l
    ld l,a
    jr nc,.n
    inc h
.n:
    ld a,(hl)
    cp c
    scf
    ret z                       ; there
    push hl
    inc a
    jr nz,.seek
    ld a,(fd_unit)
    ld (fd_ru),a
    push bc
    ld hl,fd_recal
    ld b,2
    ld c,0
    call fd_go
    pop bc
    jr c,.seek
    push bc                     ; (once more: 77 steps at most a time)
    ld hl,fd_recal
    ld b,2
    ld c,0
    call fd_go
    pop bc
    jr nc,.no
.seek:
    ld a,(fd_unit)
    ld (fd_su),a
    ld a,c
    ld (fd_ncn),a
    ld hl,fd_seek
    ld b,3
    call fd_go
    jr nc,.no
    pop hl
    ld (hl),c
    scf
    ret
.no:
    pop hl
    ld (hl),#FF
    or a
    ret

;; fd_go: HL = a SEEK or RECALIBRATE command, B its bytes, C the cylinder
;; it ends on -> sent, its end awaited (some 3 s at most, the interrupts
;; on); carry if it ended normally there. A, B, HL lost.
fd_go:
    di
    call fd_out
    ei
    ld hl,0
    ld b,6
.w:
    in a,(P_SYS)
    and #20
    jr nz,.int
    dec hl
    ld a,h
    or l
    jr nz,.w
    djnz .w
    ei
    or a
    ret
.int:
    di
    ld hl,fd_sis
    ld b,1
    call fd_out
    call fd_in
    ei
    ld a,(fd_r)
    and #F8
    cp #20                      ; seek end, normal
    ret nz
    ld a,(fd_r+1)               ; the cylinder it is on
    cp c
    scf
    ret z
    or a
    ret

;; fd_out: HL = command bytes, B = how many -> to the controller. A lost.
fd_out:
    in a,(P_FDCST)
    rlca
    jr nc,fd_out
    rlca
    jr c,.drop                  ; it has something to say: taken, dropped
    ld a,(hl)
    out (P_FDCDAT),a
    inc hl
    ex (sp),hl                  ; (12 us before the status again)
    ex (sp),hl
    djnz fd_out
    ret
.drop:
    in a,(P_FDCDAT)
    jr fd_out
;; fd_in: the controller's result bytes -> fd_r (up to 7, the rest
;; dropped). A, B, HL lost.
fd_in:
    ld hl,fd_r
    ld b,7
.r:
    in a,(P_FDCST)
    rlca
    jr nc,.r
    rlca
    ret nc                      ; it wants a command: all read
    in a,(P_FDCDAT)
    ld (hl),a
    ex (sp),hl
    ex (sp),hl
    ld a,b
    or a
    jr z,.r
    dec b
    inc hl
    jr .r
