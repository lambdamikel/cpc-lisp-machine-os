;; CPC Lisp -- the PCW's boot sector and loader. BOOT.BIN: 512 bytes of
;; boot sector, then 2 KB of loader (tools/pcw/mkdisk.py puts them in
;; track 0: sector 1, sectors 2-5; the resident part in 6-9).
;;
;; THE BOOT SECTOR: the boot program (the printer controller's, copied to
;; &0002) reads track 0's sector 1 to &F000 and, if its 512 bytes add up
;; to &FF, starts it at &F010: blocks 0-3 at &0000-&FFFF, the interrupts
;; off, the motors on, the head on track 0, the stack below the keyboard
;; (&FFF0). Its first 16 bytes are the disc's specification (as every PCW
;; disc's: CP/M reads the format from them; byte 15 is mkdisk.py's, to
;; make the sum). It reads track 0's sectors 2-9 to &2000-&2FFF -- the
;; loader, the resident part -- and starts the loader. Its uPD765 routines
;; are the loader's too: polled, the interrupts off, the terminal count the
;; transfer's end.
;;
;; THE LOADER (at &2000, in block 0): the screen set up as Lisp has it
;; (page.asm: rows 0-21 in block 1, 22-31 and the roller RAM in block 3 --
;; seen at &4000 and &C000 now), the RAM measured (an 8512's block 16 is
;; not block 0 again), the directory read (to &8000, block 2), LISP.IMG's
;; eight extents found -- 16 KB each: the six images and the two machine
;; pages -- and read into blocks 8-15 through the WINDOW, a cell of a
;; bar on the screen for each; the resident part copied to block 4 and
;; told the RAM's size and the RAM disc's blocks; then blocks 4-6 at
;; &0000-&BFFF and RS_BOOT. If something goes wrong: the screen bright,
;; beeps (as the boot program's), and again after a key -- the SPACE bar
;; boots afresh.

    include "firmware.asm"
    include "jumps.asm"

    org #F000
spec:       db 0,0,40,9,2,1,3,2,#2A,#52,0,0,0,0,0   ; 180 KB, PCW/CP/M's
            db 0                ; mkdisk.py's: the sector's sum &FF
    assert $ == #F010
    ld hl,#2000                 ; track 0's sectors 2-9: the loader, the
    ld bc,#0800                 ;   resident part
    ld de,#0002
    call fd_read
    jp c,ld_start
    ld a,1
    jp ld_fail

;; fd_read: C = cylinder, D = head, E = the first sector, B = how many (to
;; the track's end at most), HL = where -> carry if they were read (three
;; tries), HL past them; else A = 3. The interrupts off.
fd_read:
    ld a,3
    ld (fd_try),a
.again:
    di
    ld a,c
    ld (fc_cyl),a
    ld a,d
    ld (fc_head),a
    add a,a
    add a,a
    ld (fc_hu),a                ; the head, unit 0
    ld a,e
    ld (fc_sec),a
    add a,b
    dec a
    ld (fc_eot),a
    push bc
    push de
    push hl
    ld a,b
    add a,a
    ld d,a
    ld e,0                      ; DE = the bytes: 512 a sector
    push de
    ld hl,fc_read
    ld b,9
    call fd_out
    pop de
    pop hl
    push hl
    ld c,P_FDCDAT
.d:
    in a,(P_FDCST)
    rlca
    jr nc,.d                    ; until a byte is there
    and #40                     ; (bit 5) the execution phase still?
    jr z,.res                   ; no: it ended early
    ini
    dec de
    ld a,d
    or e
    jr nz,.d
    ld a,SC_TCON                ; the terminal count: the transfer's end
    out (P_SYS),a
.res:
    push hl
    call fd_in
    pop hl
    ld a,SC_TCOFF
    out (P_SYS),a
    pop de                      ; (where it started)
    ld a,(fd_r)                 ; ST0
    and #C0
    jr z,.ok
    cp #40                      ; abnormal, but only the track's end (EN)?
    jr nz,.bad
    ld a,(fd_r+1)
    cp #80
    jr nz,.bad
.ok:
    pop de
    pop bc
    scf
    ret
.bad:
    ex de,hl                    ; HL = where it started
    pop de
    pop bc
    ld a,(fd_try)
    dec a
    ld (fd_try),a
    jr nz,.again
    ld a,3
    or a
    ret

;; fd_out: HL = command bytes, B = how many -> to the controller. A lost.
fd_out:
    in a,(P_FDCST)
    rlca
    jr nc,fd_out                ; until it is ready
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
;; fd_in: the controller's result bytes -> fd_r (up to 7, the rest dropped).
;; A, B, HL lost.
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

;; fd_seek: C = a cylinder -> the head there; carry if it went. A, B, HL
;; lost. fd_recal: to cylinder 0.
fd_recal:
    ld hl,fc_recal
    ld b,2
    ld c,0
    jr fd_go
fd_seek:
    ld a,c
    ld (fc_ncn),a
    ld hl,fc_seek
    ld b,3
fd_go:
    di
    call fd_out
;; fd_sense: the seek's end awaited (at most some 3 s) -> carry if it ended
;; normally on cylinder C
fd_sense:
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
    or a                        ; (no end: no carry)
    ret
.int:
    ld hl,fc_sis
    ld b,1
    call fd_out
    call fd_in
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

;; the commands
fc_read:    db #66              ; READ DATA: MFM, deleted marks skipped
fc_hu:      db 0                ;   head * 4 + unit
fc_cyl:     db 0
fc_head:    db 0
fc_sec:     db 0
            db 2                ;   512 bytes
fc_eot:     db 0
            db #2A,#FF
fc_recal:   db 7,0              ; RECALIBRATE unit 0
fc_seek:    db #0F,0            ; SEEK unit 0, head 0, to
fc_ncn:     db 0
fc_sis:     db 8                ; SENSE INTERRUPT STATUS
fd_try:     db 0
fd_r:       defs 7,0            ; the result bytes

;; the end of the loader: Lisp's blocks at &0000-&BFFF, the resident
;; part's start (from here: block 3, which stays at &C000 until rs_boot
;; puts page B there)
bs_stub:
    ld a,#80+BL_LO
    out (P_MAP0),a
    ld a,#80+BL_MID
    out (P_MAP1),a
    ld a,#80+BL_HI
    out (P_MAP2),a
    jp RS_BOOT

bs_end:
    print "boot sector: ",bs_end-#F000," bytes"
    assert bs_end <= #F200
    defs #F200-$,0

;; ---------------------------------------------------------------------------
;; THE LOADER

    org #2000,#F200
LD_RES      equ #2800           ; the resident part, as the boot sector read it
LD_DBUF     equ #8000           ; the directory, read here (block 2)

ld_start:
    di
    ld sp,#F000-2               ; (below the boot sector: &FFF0 is the keys')
    call ld_screen
    ; THE RAM: 256 KB if block 16 is block 0 again
    ld a,#AA
    ld (#3FFF),a
    ld a,#90
    out (P_MAP1),a
    ld a,#55
    ld (#7FFF),a
    ld a,#81
    out (P_MAP1),a
    ld a,(#3FFF)
    cp #55
    ld a,16
    jr z,.small
    ld a,32
.small:
    ld (ld_nblk),a
    ; THE DISC'S GEOMETRY, from the specification (the boot sector's)
    ld a,(spec+1)
    and 3
    ld a,1
    jr z,.one
    inc a
.one:
    ld (ld_sides),a
    ld a,(spec+3)
    ld (ld_spt),a
    ld a,(spec+6)               ; the block shift: sectors a block, 1 << (BSH-2)
    sub 2
    ld b,a
    ld a,1
.spb:
    add a,a
    djnz .spb
    ld (ld_spb),a
    ld a,(spec+5)               ; the reserved tracks: the directory's start
    ld b,a
    ld hl,0
    ld de,(ld_spt)
    ld d,0
    inc b
.dl:
    dec b
    jr z,.dlx
    add hl,de
    jr .dl
.dlx:
    ld (ld_dir),hl
    ; the blocks on the disc: wide (two-byte) block numbers past 255
    ld a,(spec+2)               ; tracks * sides - reserved, * sectors, / a block's
    ld e,a
    ld a,(ld_sides)
    cp 2
    jr nz,.ts
    sla e
.ts:
    ld a,(spec+5)
    ld b,a
    ld a,e
    sub b
    ld e,a
    ld d,0
    ld hl,0
    ld a,(ld_spt)
    ld b,a
.mul:
    add hl,de
    djnz .mul                   ; HL = the data's sectors
    ld a,(ld_spb)
.div:
    rrca
    jr c,.divd
    srl h
    rr l
    jr .div
.divd:                          ; HL = the blocks
    ld a,h
    or a
    ld a,0
    jr z,.narrow
    inc a
.narrow:
    ld (ld_wide),a
    ; THE DIRECTORY: its blocks (spec+7) read to LD_DIR
    ld a,(spec+7)
    ld b,a
    ld a,(ld_spb)
    ld c,a
    xor a
.ds:
    add a,c
    djnz .ds
    ld (ld_dsec),a              ; its sectors
    ld hl,(ld_dir)
    ld de,LD_DBUF
    call ld_run
    ld a,4
    jp nc,ld_fail
    ; LISP.IMG's eight extents
    ld hl,ld_ext
    ld b,16
.z:
    ld (hl),0
    inc hl
    djnz .z
    ld a,(ld_dsec)
    add a,a
    add a,a
    add a,a
    add a,a                     ; 16 entries a sector
    ld b,a
    ld ix,LD_DBUF
.ent:
    ld a,(ix+0)
    or a
    jr nz,.next                 ; user 0 only
    ld a,(ix+14)                ; S2: extents past 31
    or a
    jr nz,.next
    ld a,(ix+12)
    cp 8
    jr nc,.next
    push bc
    push ix
    pop hl
    inc hl
    ld de,ld_name
    ld b,11
.cmp:
    ld a,(hl)
    and #7F
    ex de,hl
    cp (hl)
    ex de,hl
    jr nz,.nope
    inc hl
    inc de
    djnz .cmp
    ld a,(ix+12)                ; this extent's entry
    add a,a
    ld e,a
    ld d,0
    ld hl,ld_ext
    add hl,de
    push ix
    pop de
    ld (hl),e
    inc hl
    ld (hl),d
.nope:
    pop bc
.next:
    ld de,32
    add ix,de
    djnz .ent
    ; THE IMAGES: extent k into block 8 + k
    xor a
.img:
    ld (ld_k),a
    add a,a
    ld e,a
    ld d,0
    ld hl,ld_ext
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    or h
    ld a,5
    jp z,ld_fail                ; not there
    ld de,16
    add hl,de
    ld (ld_al),hl               ; its blocks
    ld a,(ld_k)
    add a,#80+BL_IMG
    out (P_MAP1),a
    ld de,WINDOW
    ld (ld_dst),de
    ld a,16                     ; blocks in the extent: 16, or 8 wide ones
    ld c,a
    ld a,(ld_wide)
    or a
    jr z,.n16
    srl c
.n16:
    ld a,c
    ld (ld_nal),a
.blk:
    ld hl,(ld_al)
    ld e,(hl)
    inc hl
    ld d,0
    ld a,(ld_wide)
    or a
    jr z,.b8
    ld d,(hl)
    inc hl
.b8:
    ld (ld_al),hl
    ld a,d
    or e
    ld a,6
    jp z,ld_fail                ; (a short extent: not LISP.IMG)
    ld hl,0                     ; the block's first sector: dir + DE * spb
    ld a,(ld_spb)
    ld b,a
.bs:
    add hl,de
    djnz .bs
    ld de,(ld_dir)
    add hl,de
    ld a,(ld_spb)
    ld de,(ld_dst)
    call ld_run
    ld a,7
    jp nc,ld_fail
    ld (ld_dst),de
    ld hl,ld_nal
    dec (hl)
    jr nz,.blk
    ld a,#80+BL_SCR0            ; a cell of the bar
    out (P_MAP1),a
    ld a,(ld_k)
    call ld_cell
    ld a,(ld_k)
    inc a
    cp 8
    jp c,.img
    ; THE RESIDENT PART: to block 4, told what it needs
    ld a,#80+BL_LO
    out (P_MAP1),a
    ld hl,LD_RES
    ld de,WINDOW
    ld bc,#800
    ldir
    ld a,(ld_nblk)
    ld (WINDOW+RS_NBLK),a
    ld hl,WINDOW+RS_RD          ; the RAM disc: 0, 2, 7, and 16-31 on an 8512
    ld (hl),#80
    inc hl
    ld (hl),#82
    inc hl
    ld (hl),#87
    inc hl
    ld b,RD_BLOCKS
    ld a,(ld_nblk)
    cp 32
    jr nz,.rdn
    ld a,#90
.rd:
    ld (hl),a
    inc hl
    inc b
    inc a
    cp #A0
    jr c,.rd
.rdn:
    ld a,b
    ld (WINDOW+RS_RDN),a
    jp bs_stub

;; ld_run: HL = a logical sector, A = how many, DE = where -> read, a
;; track's part at a time; carry if it went, DE past them
ld_run:
    ld (ld_n),a
    ld (ld_dst2),de
.l:
    ld a,(ld_n)
    or a
    jr z,.done
    ld (ld_ls),hl
    call ld_chs                 ; C, D, E: where; B: sectors left on the track
    ld a,(ld_n)
    cp b
    jr nc,.max                  ; (as many as are left, or the rest)
    ld b,a
.max:
    ld a,b
    ld (ld_cnt),a
    ld a,(ld_cyl)
    cp c
    jr z,.on
    push bc
    push de
    call fd_seek
    pop de
    pop bc
    ret nc
    ld a,c
    ld (ld_cyl),a
.on:
    ld a,(ld_cnt)
    ld b,a
    ld hl,(ld_dst2)
    call fd_read
    ret nc
    ld (ld_dst2),hl
    ld a,(ld_cnt)
    ld c,a
    ld b,0
    ld hl,(ld_ls)
    add hl,bc
    ld a,(ld_n)
    sub c
    ld (ld_n),a
    jr .l
.done:
    ld de,(ld_dst2)
    scf
    ret

;; ld_chs: HL = a logical sector -> C = cylinder, D = head, E = sector,
;; B = the sectors left on its track from it
ld_chs:
    ld a,(ld_spt)
    ld e,a
    ld d,0
    xor a                       ; A = the logical track
.t:
    or a
    sbc hl,de
    jr c,.tr
    inc a
    jr .t
.tr:
    add hl,de                   ; L = the sector in it, from 0
    ld c,a
    ld d,0
    ld a,(ld_sides)
    cp 2
    jr nz,.ss
    srl c                       ; alternate sides: cylinder, head
    rl d
.ss:
    ld a,(ld_spt)
    sub l
    ld b,a
    ld e,l
    inc e
    ret

;; ld_screen: the screen as Lisp has it (page.asm): the roller RAM in
;; block 3 at &1E00 -- &DE00 now -- each line's address there; rows 0-21
;; in block 1 (&4000), 22-31 in block 3 (&C000); all blank; on
ld_screen:
    ld hl,#4000
    ld de,#4001
    ld bc,SCR_SPLIT*720-1
    ld (hl),0
    ldir
    ld hl,#C000
    ld de,#C001
    ld bc,(32-SCR_SPLIT)*720-1
    ld (hl),0
    ldir
    ld ix,#C000+ROLLER
    ld b,0                      ; the line, 0-255
.l:
    ld a,b
    rrca
    rrca
    rrca
    and 31                      ; its row
    ld c,BL_SCR0*32             ; (the block, in bits 13-15: * 32 in H)
    cp SCR_SPLIT
    jr c,.lo
    sub SCR_SPLIT
    ld c,BL_SCR1*32
.lo:
    ld e,a
    ld d,0
    ld hl,0
    push bc
    ld b,a
    inc b
.m:
    dec b
    jr z,.md
    push de
    ld de,360                   ; a row's 720 bytes, halved
    add hl,de
    pop de
    jr .m
.md:
    pop bc
    ld a,b
    and 7
    or l
    ld (ix+0),a
    ld a,h
    or c
    ld (ix+1),a
    inc ix
    inc ix
    inc b
    jr nz,.l
    ld a,BL_SCR1*32+ROLLER/512
    out (P_ROLLER),a
    xor a
    out (P_ORIGIN),a
    ld a,#40
    out (P_VIDEO),a
    ret

;; ld_cell: A = 0-7 -> a cell of the bar lit: row 15, columns 41-48
ld_cell:
    add a,41
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,#4000+15*720
    add hl,de
    ld b,8
.c:
    ld (hl),#FF
    inc hl
    djnz .c
    ret

;; ld_fail: A = what went wrong -> the screen bright, A beeps, then wait
;; for the SPACE bar and boot afresh
ld_fail:
    di
    ld sp,#F000-2
    push af
    ld a,#C0                    ; inverse
    out (P_VIDEO),a
    pop af
    ld d,a
.beep:
    ld a,SC_BEEPON
    out (P_SYS),a
    call ld_wait
    ld a,SC_BEEPOFF
    out (P_SYS),a
    call ld_wait
    dec d
    jr nz,.beep
.key:
    ld a,(#FFF5)                ; the keyboard (block 3 at &C000): SPACE
    bit 7,a
    jr z,.key
    ld a,#80
    ld bc,SC_REBOOT*256+P_SYS
    out (c),b
    jr $
;; ld_wait: some 0.2 s
ld_wait:
    ld bc,0
.w:
    ex (sp),hl
    ex (sp),hl
    dec bc
    ld a,b
    or c
    jr nz,.w
    ret

ld_name:    db "LISP    IMG"
ld_nblk:    db 16
ld_sides:   db 1
ld_spt:     db 9
ld_spb:     db 2
ld_wide:    db 0
ld_dsec:    db 0
ld_k:       db 0
ld_nal:     db 0
ld_n:       db 0
ld_cyl:     db 0                ; the boot program left the head here
ld_cnt:     db 0
ld_dir:     dw 0
ld_dst:     dw 0
ld_dst2:    dw 0
ld_ls:      dw 0
ld_al:      dw 0
ld_ext:     defs 16,0           ; the extents' directory entries

ld_end:
    print "loader: ",ld_end-#2000," bytes"
    assert ld_end <= #2800
