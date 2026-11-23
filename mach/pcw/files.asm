;; CPC Lisp -- files on the PCW, in machine page B (pageb.asm includes
;; this): CP/M's own file system, on the drives through fdc.asm, read and
;; written by us -- the discs are CP/M's (and LocoScript's), and CP/M reads
;; what Lisp saves.
;;
;; A DISC says its format in its first sector's first 16 bytes (the
;; specification: sides, tracks, sectors a track, the reserved tracks, the
;; block's size, the directory's blocks); logging a drive in reads them
;; into its DPB (a disc whose first byte is not 0 or 3 is taken for the
;; 8256's 180 KB one). After the reserved tracks come the blocks (1 or 2
;; KB), the directory in the first: 32 bytes an entry -- [0] the user (0;
;; &E5 free), [1] the name (8) and type (3), [12] EX, [14] S2: the extent
;; (16 KB of the file) is S2 * 32 + EX; [15] RC: its records of 128 bytes;
;; [16] its blocks, a byte each (or a word, past 255 blocks on the disc).
;; A text file ends at its first ^Z (&1A): what Lisp writes is padded with
;; them to the record's end.
;;
;; One file open for input and one for output, as on the CPC; the library
;; lends each a buffer of FILE_BUFSIZE bytes from block space: its state
;; (FB_...), then the sector it is in. Every open logs its drive in again
;; (a disc may have been changed); writing builds a map of the blocks in
;; use first (f_map) and takes the first free ones; an extent's entry is
;; written once it is full, and the last one at the close.

FB_NAME     equ 0               ; 11: the name, as the directory has it
FB_DRV      equ 11              ; its drive: 0 A, 1 B
FB_EXT      equ 12              ; 2: the extent the position is in
FB_ENT      equ 14              ; 2: its directory entry (writing)
FB_AL       equ 16              ; 16: its blocks
FB_RC       equ 32              ; its records (reading)
FB_POS      equ 33              ; 2: the position in the extent (0-16384)
FB_SEC      equ 35              ; 2: the sector in FB_DATA, &FFFF none
FB_EOF      equ 37              ; 1: the end has been read
FB_DATA     equ 64              ; the sector, 512 bytes
    assert FB_DATA+512 <= FILE_BUFSIZE

;; a drive's DPB: what its disc's specification says
DP_SIDES    equ 0               ; 1 or 2 (alternate)
DP_SPT      equ 1               ; sectors a track (512 bytes)
DP_OFF      equ 2               ; reserved tracks
DP_BSH      equ 3               ; a block is 128 << BSH bytes
DP_SPB      equ 4               ; sectors a block
DP_DSEC     equ 5               ; the directory's sectors
DP_DIRLS    equ 6               ; 2: its first sector (logical)
DP_DSM      equ 8               ; 2: the blocks on the disc
DP_WIDE     equ 10              ; 1: two-byte block numbers
DP_BLM      equ 11              ; 2: a block's bytes - 1
DP_DIRB     equ 13              ; the directory's blocks
DP_LEN      equ 16

fi_buf:     dw 0                ; the input file's buffer, 0 when none
fo_buf:     dw 0                ;   the output file's
fi_rd:      db 0                ; 1 if it is on the RAM disc
fo_rd:      db 0
f_drive:    db 0                ; the current drive: (cd)'s
f_dpbs:     defs 2*DP_LEN,0     ; drive A's, B's
f_dp:       dw f_dpbs           ; the drive in use: its DPB,
f_drv:      db 0                ;   its number
f_secls:    dw #FFFF            ; the sector in f_sec, &FFFF none,
f_secdrv:   db 0                ;   its drive
f_nm:       defs 11,' '         ; a name, as the directory has it
f_ext:      dw 0                ; an extent wanted
f_ent:      dw 0                ; an entry's number
fs_n:        dw 0
fs_t:        dw 0
fs_k:        db 0
f_map:      defs 64,0           ; the blocks in use (writing), a bit each
f_sec:      defs 512,0          ; a sector of the directory

;; f_init: from b_init
f_init:
    xor a
    ld (f_drive),a
    ld hl,0
    ld (fi_buf),hl
    ld (fo_buf),hl
    ld hl,#FFFF
    ld (f_secls),hl
    ld a,#FF
    ld (fd_cyls),a
    ld (fd_cyls+1),a
    ret

;; f_fail: no carry, NZ: it failed
f_fail:
    ld a,1
    or a
    ret

;; ---------------------------------------------------------------------------
;; DRIVES

;; f_use: A = a drive -> it in use: its DPB (f_dp), the controller's
;; geometry (fd_unit, fd_spt, fd_sides). All but AF kept.
f_use:
    ld (f_drv),a
    ld (fd_unit),a
    push hl
    ld hl,f_dpbs
    or a
    jr z,.a
    ld hl,f_dpbs+DP_LEN
.a:
    ld (f_dp),hl
    ld a,(hl)                   ; DP_SIDES
    ld (fd_sides),a
    inc hl
    ld a,(hl)                   ; DP_SPT
    ld (fd_spt),a
    pop hl
    ret

;; f_login: A = a drive -> in use (f_use), its disc's specification read
;; into its DPB; carry if it could be read
f_login:
    push ix
    call f_use
    ld a,1                      ; the first sector: the same in any format
    ld (fd_sides),a
    ld a,9
    ld (fd_spt),a
    ld hl,#FFFF
    ld (f_secls),hl
    ld hl,0
    ld de,f_sec
    ld a,1
    call fd_rd
    jp nc,.out
    ld a,(f_sec)                ; 0 or 3: a PCW's (or +3's) specification
    or a
    jr z,.spec
    cp 3
    jr z,.spec
    ld hl,f_180                 ;   else the 8256's own
    jr .fmt
.spec:
    ld hl,f_sec
.fmt:
    ld ix,(f_dp)
    inc hl
    ld a,(hl)                   ; sidedness: 0 one side, else alternate
    and 3
    ld a,1
    jr z,.one
    inc a
.one:
    ld (ix+DP_SIDES),a
    inc hl
    ld c,(hl)                   ; tracks a side
    inc hl
    ld a,(hl)
    ld (ix+DP_SPT),a
    inc hl
    inc hl                      ; (the sector size: 512)
    ld a,(hl)
    ld (ix+DP_OFF),a
    inc hl
    ld a,(hl)
    ld (ix+DP_BSH),a
    inc hl
    ld a,(hl)
    ld (ix+DP_DIRB),a
    ; sectors a block: 1 << (BSH - 2); BLM: 128 << BSH, - 1
    ld a,(ix+DP_BSH)
    sub 2
    ld b,a
    ld a,1
.spb:
    add a,a
    djnz .spb
    ld (ix+DP_SPB),a
    ld l,0
    ld h,a
    add hl,hl                   ; * 512
    dec hl
    ld (ix+DP_BLM),l
    ld (ix+DP_BLM+1),h
    ; the directory's first sector: reserved * spt; its sectors
    ld b,(ix+DP_OFF)
    ld e,(ix+DP_SPT)
    ld d,0
    ld hl,0
    inc b
.dl:
    dec b
    jr z,.dlx
    add hl,de
    jr .dl
.dlx:
    ld (ix+DP_DIRLS),l
    ld (ix+DP_DIRLS+1),h
    ld b,(ix+DP_DIRB)
    xor a
.ds:
    add a,(ix+DP_SPB)
    djnz .ds
    ld (ix+DP_DSEC),a
    ; the blocks: (tracks * sides - reserved) * spt / spb
    ld a,(ix+DP_SIDES)
    cp 2
    jr nz,.ts
    sla c
.ts:
    ld a,c
    sub (ix+DP_OFF)
    ld e,a
    ld d,0
    ld hl,0
    ld b,(ix+DP_SPT)
.mul:
    add hl,de
    djnz .mul
    ld a,(ix+DP_SPB)
.div:
    rrca
    jr c,.divd
    srl h
    rr l
    jr .div
.divd:
    ld (ix+DP_DSM),l
    ld (ix+DP_DSM+1),h
    ld a,h
    or a
    ld a,0
    jr z,.narrow
    inc a
.narrow:
    ld (ix+DP_WIDE),a
    ld a,(f_drv)
    call f_use
    scf
.out:
    pop ix
    ret
f_180:      db 0,0,40,9,2,1,3,2 ; the 8256's: 180 KB, one side

;; ---------------------------------------------------------------------------
;; THE DIRECTORY

;; f_dirsec: HL = a sector of the directory (from its first) -> in f_sec;
;; carry if it is
f_dirsec:
    push ix
    ld ix,(f_dp)
    ld e,(ix+DP_DIRLS)
    ld d,(ix+DP_DIRLS+1)
    add hl,de
    pop ix
    ld de,(f_secls)
    or a
    sbc hl,de
    add hl,de
    jr nz,.read
    ld a,(f_secdrv)
    push hl
    ld hl,f_drv
    cp (hl)
    pop hl
    scf
    ret z
.read:
    ld (f_secls),hl
    ld a,(f_drv)
    ld (f_secdrv),a
    ld de,f_sec
    ld a,1
    call fd_rd
    ret c
    ld hl,#FFFF
    ld (f_secls),hl
    ld a,1                      ; (NZ: the disc would not read)
    or a
    ret

;; f_wrdir: f_sec written back to its sector; carry if it went
f_wrdir:
    ld hl,(f_secls)
    ld de,f_sec
    ld a,1
    jp fd_wr

;; f_entry: HL = an entry's number -> IX = it, in f_sec; carry if it could
;; be read
f_entry:
    ld (f_ent),hl
    push hl
    ld a,l
    and 15
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,f_sec
    add hl,de
    ex (sp),hl
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l                        ; / 16: its sector
    call f_dirsec
    pop ix
    ret

;; f_count: -> HL = the directory's entries (sectors * 16)
f_count:
    push ix
    ld ix,(f_dp)
    ld l,(ix+DP_DSEC)
    ld h,0
    pop ix
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ret

;; f_same: IX = an entry -> Z if it is f_nm's, user 0
f_same:
    ld a,(ix+0)
    or a
    ret nz
    push bc
    push hl
    push ix
    pop hl
    inc hl
    ld de,f_nm
    ld b,11
.c:
    ld a,(hl)
    and #7F
    ex de,hl
    cp (hl)
    ex de,hl
    jr nz,.x
    inc hl
    inc de
    djnz .c
.x:
    pop hl
    pop bc
    ret

;; f_extof: IX = an entry -> HL = its extent (S2 * 32 + EX)
f_extof:
    ld a,(ix+14)
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld a,(ix+12)
    and 31
    or l
    ld l,a
    ret

;; f_find: f_nm, f_ext -> IX = its entry (f_ent its number); carry if
;; there is one
f_find:
    call f_count
    ld (fs_n),hl
    ld hl,0
.l:
    push hl
    call f_entry
    pop hl
    ret nc
    call f_same
    jr nz,.next
    push hl
    call f_extof
    ld de,(f_ext)
    or a
    sbc hl,de
    pop hl
    scf
    ret z
.next:
    inc hl
    ld de,(fs_n)
    or a
    sbc hl,de
    add hl,de
    jr c,.l
    xor a                       ; (none: Z)
    ret

;; f_freeent: -> HL = the first free entry's number; carry if there is one
f_freeent:
    call f_count
    ld (fs_n),hl
    ld hl,0
.l:
    push hl
    call f_entry
    pop hl
    ret nc
    ld a,(ix+0)
    cp #E5
    scf
    ret z
    inc hl
    ld de,(fs_n)
    or a
    sbc hl,de
    add hl,de
    jr c,.l
    or a
    ret

;; f_delete: f_nm -> every entry of it freed; carry if there was one
f_delete:
    xor a
    ld (fs_k),a
    call f_count
    ld (fs_n),hl
    ld hl,0
.l:
    push hl
    call f_entry
    pop hl
    ret nc
    call f_same
    jr nz,.next
    ld (ix+0),#E5
    push hl
    call f_wrdir
    pop hl
    ret nc
    ld a,1
    ld (fs_k),a
.next:
    inc hl
    ld de,(fs_n)
    or a
    sbc hl,de
    add hl,de
    jr c,.l
    ld a,(fs_k)
    or a
    ret z
    scf
    ret

;; ---------------------------------------------------------------------------
;; THE BLOCKS

;; f_bit: DE = a block -> HL = its byte in f_map, A = its bit. DE kept.
f_bit:
    push de
    ld a,e
    and 7
    ld b,a
    ld a,1
    inc b
.s:
    dec b
    jr z,.d
    add a,a
    jr .s
.d:
    srl d
    rr e
    srl d
    rr e
    srl d
    rr e
    ld hl,f_map
    add hl,de
    pop de
    ret

;; f_mark: DE = a block -> it in use. All but AF, B, HL kept.
f_mark:
    ld a,d
    cp 2
    ret nc                      ; (past 511: none such)
    call f_bit
    or (hl)
    ld (hl),a
    ret

;; f_mapit: f_map made: the directory's blocks, every entry's (writing)
f_mapit:
    ld hl,f_map
    ld b,64
.z:
    ld (hl),0
    inc hl
    djnz .z
    ld ix,(f_dp)
    ld b,(ix+DP_DIRB)
    ld de,0
.d:
    push bc
    call f_mark
    pop bc
    inc de
    djnz .d
    call f_count
    ld (fs_n),hl
    ld hl,0
.l:
    push hl
    call f_entry
    pop hl
    ret nc
    ld a,(ix+0)
    cp 16
    jr nc,.next                 ; free (or not a file's)
    push hl
    push ix
    pop hl
    ld de,16
    add hl,de                   ; its blocks
    ld ix,(f_dp)
    ld a,(ix+DP_WIDE)
    ld b,16
    or a
    jr z,.al
    ld b,8
.al:
    ld e,(hl)
    inc hl
    ld d,0
    or a
    jr z,.n8
    ld d,(hl)
    inc hl
.n8:
    push af
    push bc
    push hl
    ld a,d
    or e
    call nz,f_mark
    pop hl
    pop bc
    pop af
    djnz .al
    pop hl
.next:
    inc hl
    ld de,(fs_n)
    or a
    sbc hl,de
    add hl,de
    jr c,.l
    scf
    ret

;; f_alloc: -> DE = a free block, marked in use; carry if there was one
f_alloc:
    ld ix,(f_dp)
    ld de,0
.l:
    ld l,(ix+DP_DSM)
    ld h,(ix+DP_DSM+1)
    or a
    sbc hl,de
    ret z                       ; (no carry: none left)
    ld a,d
    cp 2
    jr nc,.full                 ; (past 511: f_map has none)
    push de
    call f_bit
    pop de
    ld b,a
    and (hl)
    jr z,.free
    inc de
    jr .l
.free:
    ld a,b
    or (hl)
    ld (hl),a
    scf
    ret
.full:
    or a
    ret

;; f_free: -> HL = the blocks not in use, from f_map (built for it)
f_free:
    ld ix,(f_dp)
    ld c,(ix+DP_DSM)
    ld b,(ix+DP_DSM+1)
    ld de,0
    ld hl,0
.l:
    ld a,d
    cp b
    jr nz,.go
    ld a,e
    cp c
    ret z
.go:
    push hl
    push de
    push bc
    call f_bit
    and (hl)
    pop bc
    pop de
    pop hl
    jr nz,.used
    inc hl
.used:
    inc de
    jr .l

;; ---------------------------------------------------------------------------
;; A FILE'S SECTORS

;; f_lsn: IX = a file's buffer, HL = a position in its extent -> HL = the
;; logical sector it is in, DE = where its block's number is in FB_AL; Z
;; if that block is not there yet (its number 0). IY = the drive's DPB.
f_lsn:
    ld iy,(f_dp)
    ld (fs_t),hl
    ld a,(iy+DP_BSH)
    add a,7
    ld b,a
.sh:
    srl h
    rr l
    djnz .sh                    ; HL = the block's index in the extent
    ld a,(iy+DP_WIDE)
    or a
    jr z,.b8
    add hl,hl                   ; (two bytes each)
.b8:
    ld de,FB_AL
    add hl,de
    push ix
    pop de
    add hl,de
    ex de,hl                    ; DE -> its number
    ld a,(de)
    ld l,a
    ld h,0
    ld a,(iy+DP_WIDE)
    or a
    jr z,.n
    inc de
    ld a,(de)
    dec de
    ld h,a
.n:
    ld a,h
    or l
    ret z                       ; no block yet
    push de
    ld b,(iy+DP_SPB)            ; its first sector: * spb + the directory's
    ld d,h
    ld e,l
    ld hl,0
.m:
    add hl,de
    djnz .m
    ld e,(iy+DP_DIRLS)
    ld d,(iy+DP_DIRLS+1)
    add hl,de
    ex de,hl
    ld a,(fs_t+1)                ; + the sector in the block: the position
    and (iy+DP_BLM+1)           ;   AND BLM, / 512
    srl a
    ld l,a
    ld h,0
    add hl,de
    pop de
    ld a,1
    or a                        ; (NZ)
    ret

;; ---------------------------------------------------------------------------
;; NAMES

;; f_name: HL = a CPC name ([A:]NAME.EXT), B = its length, IX = a buffer ->
;; FB_NAME, FB_DRV; f_nm the same; no carry if it is not a CP/M name
f_name:
    ld a,(f_drive)
    ld (ix+FB_DRV),a
    ld a,b
    cp 2
    jr c,.nod
    inc hl
    ld a,(hl)
    dec hl
    cp ':'
    jr nz,.nod
    ld a,(hl)
    and #DF
    sub 'A'
    cp 2
    jp nc,f_fail                ; A: and B: only
    ld (ix+FB_DRV),a
    inc hl
    inc hl
    dec b
    dec b
.nod:
    push ix
    pop de                      ; DE = FB_NAME
    push de
    ld c,8                      ; the name: up to 8, to a dot
    call .part
    jr nc,.bad
    ld a,b
    or a
    jr z,.notype
    ld a,(hl)
    cp '.'
    jr nz,.bad
    inc hl
    dec b
.notype:
    ld c,3
    call .part
    jr nc,.bad
    ld a,b
    or a
    jr nz,.bad                  ; more after the type
    pop hl
    ld de,f_nm
    ld bc,11
    ldir
    scf
    ret
.bad:
    pop de
    or a
    ret
;; .part: up to C characters from HL (B left) to DE, upper case, blanks
;; after to C; no carry if one is not allowed
.part:
    ld a,b
    or a
    jr z,.pad
    ld a,(hl)
    cp '.'
    jr z,.pad
    cp ' '+1
    jr c,.no
    cp '*'
    jr z,.no
    cp '?'
    jr z,.no
    cp ':'
    jr z,.no
    cp 'a'
    jr c,.up
    cp 'z'+1
    jr nc,.up
    and #DF
.up:
    ld (de),a
    inc de
    inc hl
    dec b
    dec c
    jr nz,.part
    ld a,b                      ; full: the next must be a dot (or none)
    or a
    scf
    ret z
    ld a,(hl)
    cp '.'
    scf
    ret z
.no:
    or a
    ret
.pad:
    ld a,c
    or a
    scf
    ret z
.p:
    ld a,' '
    ld (de),a
    inc de
    dec c
    jr nz,.p
    scf
    ret

;; f_say: IX = a buffer -> its name shown as AMSDOS shows one, NAME    .EXT
f_say:
    push ix
    pop hl
    ld b,8
.n:
    ld a,(hl)
    call f_out
    inc hl
    djnz .n
    ld a,'.'
    call f_out
    ld b,3
.t:
    ld a,(hl)
    call f_out
    inc hl
    djnz .t
    ret

;; f_out: A to the screen (CON_PUTC, through the jumpblock: page A). All
;; kept but AF.
f_out:
    jp JB+4*J_CON_PUTC
f_nl:
    ld a,13
    call f_out
    ld a,10
    jr f_out
f_str:
    ld a,(hl)
    or a
    ret z
    call f_out
    inc hl
    jr f_str

;; ---------------------------------------------------------------------------
;; THE FILE ROUTINES

;; FILE_IOPEN: B = the name's length, HL = the name, DE = the buffer ->
;; carry if the file is open; if it is not there, AMSDOS's message
b_file_iopen:
    xor a
    ld (fi_rd),a
    push de
    pop ix
    call f_name
    ret nc
    ld a,(ix+FB_DRV)
    call f_login
    jp nc,f_fail
    ld hl,0
    ld (ix+FB_EXT),l
    ld (ix+FB_EXT+1),h
    call f_getext
    jr nc,.none
    ld (fi_buf),ix
    scf
    ret
.none:
    ret nz                      ; (the disc would not read)
    call f_nl                   ; "NAME    .EXT not found"
    call f_say
    ld hl,f_m_nf
    call f_str
    call f_nl
    jp f_fail
f_m_nf:     db " not found",0

;; f_getext: IX = an input file's buffer -> its extent FB_EXT's entry's
;; blocks and records in it, the position its start; carry if there is
;; one (else Z: there is none, NZ: the disc would not read)
f_getext:
    push ix
    pop hl
    ld de,f_nm
    ld bc,11
    ldir
    ld l,(ix+FB_EXT)
    ld h,(ix+FB_EXT+1)
    ld (f_ext),hl
    push ix
    call f_find
    jr nc,.no
    push ix
    pop hl
    pop ix
    ld de,15
    add hl,de
    ld a,(hl)                   ; RC
    ld (ix+FB_RC),a
    inc hl
    push ix
    pop de
    ex de,hl
    ld bc,FB_AL
    add hl,bc
    ex de,hl
    ld bc,16
    ldir
    xor a
    ld (ix+FB_POS),a
    ld (ix+FB_POS+1),a
    ld (ix+FB_EOF),a
    dec a
    ld (ix+FB_SEC),a
    ld (ix+FB_SEC+1),a
    scf
    ret
.no:
    pop ix
    ret

;; FILE_GETC: -> carry and A = the next byte; NZ and no carry at the end
b_file_getc:
    push bc
    push de
    push hl
    push ix
    push iy
    ld a,(fi_rd)
    or a
    jr z,.disc
    ld ix,(fi_buf)
    call rd_getc
    jp .out
.disc:
    ld ix,(fi_buf)
    ld a,(fi_buf+1)
    or a
    jp z,.end
    ld a,(ix+FB_EOF)
    or a
    jp nz,.end
    ld a,(ix+FB_DRV)
    call f_use
.at:
    ld l,(ix+FB_POS)            ; the extent's records read?
    ld h,(ix+FB_POS+1)
    ld e,0
    ld d,(ix+FB_RC)
    srl d
    rr e                        ; DE = RC * 128
    or a
    sbc hl,de
    jr c,.have
    ld a,(ix+FB_RC)
    cp 128
    jr c,.eof                   ; a part extent: the file's last
    ld l,(ix+FB_EXT)
    ld h,(ix+FB_EXT+1)
    inc hl
    ld (ix+FB_EXT),l
    ld (ix+FB_EXT+1),h
    call f_getext
    jr nc,.eof
    jr .at
.have:
    ld l,(ix+FB_POS)
    ld h,(ix+FB_POS+1)
    call f_lsn                  ; HL = its sector
    jr z,.eof                   ; (no block: none)
    ld e,(ix+FB_SEC)
    ld d,(ix+FB_SEC+1)
    or a
    sbc hl,de
    add hl,de
    jr z,.in
    ld (ix+FB_SEC),l
    ld (ix+FB_SEC+1),h
    push ix
    pop de
    push hl
    ld hl,FB_DATA
    add hl,de
    ex de,hl
    pop hl
    ld a,1
    push ix
    call fd_rd
    pop ix
    jr nc,.err
.in:
    ld l,(ix+FB_POS)
    ld h,(ix+FB_POS+1)
    push hl
    inc hl
    ld (ix+FB_POS),l
    ld (ix+FB_POS+1),h
    pop hl
    ld a,h
    and 1
    ld h,a                      ; the byte in the sector
    push ix
    pop de
    add hl,de
    ld de,FB_DATA
    add hl,de
    ld a,(hl)
    cp #1A                      ; ^Z: the text's end
    jr z,.eof
    scf
    jr .out
.err:
    ld a,#FF
    ld (ix+FB_SEC),a
    ld (ix+FB_SEC+1),a
.eof:
    ld (ix+FB_EOF),1
.end:
    call f_fail
.out:
    pop iy
    pop ix
    pop hl
    pop de
    pop bc
    ret

;; FILE_ICLOSE, FILE_IABANDON: the input file closed, if one is open
b_file_iclose:
b_file_iabandon:
    xor a
    ld (fi_rd),a
    ld hl,0
    ld (fi_buf),hl
    scf
    ret

;; FILE_OOPEN: the same, for writing: a file of that name is replaced
b_file_oopen:
    xor a
    ld (fo_rd),a
    push de
    pop ix
    call f_name
    ret nc
    ld a,(ix+FB_DRV)
    call f_login
    jp nc,f_fail
    push ix
    call f_delete               ; (the one there was, if any)
    pop ix
    ld a,(fd_r+1)
    and 2
    jp nz,f_fail                ; not writable
    push ix
    call f_mapit
    pop ix
    jp nc,f_fail
    ld hl,0
    ld (ix+FB_EXT),l
    ld (ix+FB_EXT+1),h
    call f_newext
    ret nc
    ld (fo_buf),ix
    scf
    ret

;; f_newext: IX = an output file's buffer -> a free entry for its extent
;; FB_EXT, its blocks none yet, the position its start; carry if there
;; was one
f_newext:
    push ix
    call f_freeent
    pop ix
    ret nc
    ld (ix+FB_ENT),l
    ld (ix+FB_ENT+1),h
    push ix
    pop hl
    ld de,FB_AL
    add hl,de
    ld b,16
.z:
    ld (hl),0
    inc hl
    djnz .z
    xor a
    ld (ix+FB_POS),a
    ld (ix+FB_POS+1),a
    scf
    ret

;; f_putent: IX = an output file's buffer -> its extent's entry written:
;; user 0, the name, EX and S2, RC from the position, the blocks; carry if
;; it went
f_putent:
    ld l,(ix+FB_ENT)
    ld h,(ix+FB_ENT+1)
    push ix
    call f_entry                ; IX = the entry in f_sec
    pop iy                      ; IY = the buffer
    ret nc
    ld (ix+0),0
    push iy
    pop hl
    push ix
    pop de
    inc de
    ld bc,11
    ldir                        ; the name
    ld a,(iy+FB_EXT)
    ld l,a
    and 31
    ld (ix+12),a                ; EX
    ld (ix+13),0
    ld h,(iy+FB_EXT+1)
    add hl,hl
    add hl,hl
    add hl,hl                   ; S2: the extent / 32
    ld (ix+14),h
    ld l,(iy+FB_POS)            ; RC: (position + 127) / 128
    ld h,(iy+FB_POS+1)
    ld de,127
    add hl,de
    add hl,hl
    ld (ix+15),h
    push iy
    pop hl
    ld de,FB_AL
    add hl,de
    push ix
    pop de
    ld a,e
    add a,16
    ld e,a
    jr nc,.n
    inc d
.n:
    ld bc,16
    ldir
    push iy
    call f_wrdir
    pop ix
    ret

;; f_flush: IX = an output file's buffer, its position at a sector's end ->
;; that sector written (its block taken first, if it is the block's first);
;; carry if it went
f_flush:
    ld l,(ix+FB_POS)
    ld h,(ix+FB_POS+1)
    dec hl
    call f_lsn                  ; HL = its sector, DE -> its block's number
    jr nz,.have                 ; the block is there
    push de                     ; (where its number goes)
    push ix
    call f_alloc                ; DE = a free block
    pop ix
    pop hl
    ret nc                      ; the disc is full
    ld (hl),e
    ld iy,(f_dp)
    ld a,(iy+DP_WIDE)
    or a
    jr z,.b8
    inc hl
    ld (hl),d
.b8:
    ld l,(ix+FB_POS)
    ld h,(ix+FB_POS+1)
    dec hl
    call f_lsn
.have:
    push ix
    pop de
    push hl
    ld hl,FB_DATA
    add hl,de
    ex de,hl
    pop hl
    ld a,1
    push ix
    call fd_wr
    pop ix
    ret

;; FILE_PUTC: A = a byte -> carry if it was written
b_file_putc:
    push bc
    push de
    push hl
    push ix
    push iy
    ld c,a
    ld a,(fo_rd)
    or a
    jr z,.disc
    ld a,c
    ld ix,(fo_buf)
    call rd_putc
    jr .out
.disc:
    ld ix,(fo_buf)
    ld a,(fo_buf+1)
    or a
    jr z,.no
    ld a,(ix+FB_DRV)
    call f_use
    ld a,(ix+FB_POS+1)          ; the extent full: its entry, then the next
    cp #40
    jr c,.room
    push bc
    call f_putent
    pop bc
    jr nc,.no
    ld l,(ix+FB_EXT)
    ld h,(ix+FB_EXT+1)
    inc hl
    ld (ix+FB_EXT),l
    ld (ix+FB_EXT+1),h
    push bc
    call f_newext
    pop bc
    jr nc,.no
.room:
    ld l,(ix+FB_POS)
    ld h,(ix+FB_POS+1)
    push hl
    inc hl
    ld (ix+FB_POS),l
    ld (ix+FB_POS+1),h
    pop hl
    ld a,h
    and 1
    ld h,a
    push ix
    pop de
    add hl,de
    ld de,FB_DATA
    add hl,de
    ld (hl),c
    ld a,(ix+FB_POS)            ; a sector full: written
    or a
    scf
    jr nz,.out
    ld a,(ix+FB_POS+1)
    and 1
    scf
    jr nz,.out
    call f_flush
    jr .out
.no:
    call f_fail
.out:
    pop iy
    pop ix
    pop hl
    pop de
    pop bc
    ret

;; FILE_OCLOSE: the output file's last sector (^Z after its end) and its
;; last extent's entry written -> carry if it all went; on the RAM disc,
;; its entry made
b_file_oclose:
    ld a,(fo_rd)
    or a
    jr z,.disc
    xor a
    ld (fo_rd),a
    push ix
    ld ix,(fo_buf)
    call rd_close
    pop ix
    ld hl,0
    ld (fo_buf),hl
    ret
.disc:
    ld hl,(fo_buf)
    ld a,h
    or l
    scf
    ret z
    push ix
    push iy
    push hl
    pop ix
    ld a,(ix+FB_DRV)
    call f_use
    ld l,(ix+FB_POS)
    ld h,(ix+FB_POS+1)
    ld a,l
    or a
    jr nz,.part
    ld a,h
    and 1
    jr z,.ent                   ; at a sector's end: all written
.part:
    push hl                     ; ^Z to the sector's end, which is written
    ld a,h
    and 1
    ld h,a
    ex de,hl                    ; DE = where in the sector
    ld hl,512
    or a
    sbc hl,de
    ld b,h
    ld c,l                      ; BC = what is left of it
    push ix
    pop hl
    add hl,de
    ld de,FB_DATA
    add hl,de
.z:
    ld (hl),#1A
    inc hl
    dec bc
    ld a,b
    or c
    jr nz,.z
    pop hl
    push hl
    ld a,h                      ; the position at the sector's end for f_flush
    or 1
    ld h,a
    ld l,#FF
    inc hl
    ld (ix+FB_POS),l
    ld (ix+FB_POS+1),h
    call f_flush
    pop hl
    ld (ix+FB_POS),l            ; (back: RC is the data's)
    ld (ix+FB_POS+1),h
    jr nc,.fail
.ent:
    call f_putent
    jr nc,.fail
    ld hl,0
    ld (fo_buf),hl
    pop iy
    pop ix
    scf
    ret
.fail:
    ld hl,0
    ld (fo_buf),hl
    pop iy
    pop ix
    jp f_fail

;; FILE_OABANDON: the output file forgotten, what was written of it
;; deleted; on the RAM disc, forgotten
b_file_oabandon:
    ld a,(fo_rd)
    or a
    jr z,.disc
    xor a
    ld (fo_rd),a
    ld hl,0
    ld (fo_buf),hl
    scf
    ret
.disc:
    ld hl,(fo_buf)
    ld a,h
    or l
    scf
    ret z
    push ix
    push hl
    pop ix
    ld a,(ix+FB_DRV)
    call f_use
    push ix
    pop hl
    ld de,f_nm
    ld bc,11
    ldir
    call f_delete
    ld hl,0
    ld (fo_buf),hl
    pop ix
    scf
    ret

;; M_DELETE ((delete-file name), ramdisc.asm): TOKBUF holds the name, B its
;; length, DE = a buffer -> carry if the file was there and is gone
b_m_delete:
    ld hl,TOKBUF
    push bc
    push de
    call rd_is                  ; on M:?
    pop de
    pop bc
    jp z,rd_del
    push ix
    push de
    pop ix
    call f_name
    jr nc,.no
    ld a,(ix+FB_DRV)
    call f_login
    jr nc,.no
    call f_delete
    pop ix
    ret
.no:
    pop ix
    jp f_fail

;; M_DRIVE ((cd), drive.asm): A = a drive's letter -> carry if there is
;; such a drive (its disc reads): it is the current one from now on; A = 0:
;; back to the start's (A); A = &FF -> A = the current drive's letter
b_m_drive:
    inc a
    jr z,.ask
    dec a
    jr z,.set
    and #DF
    sub 'A'
    cp 2
    jp nc,f_fail
    push af
    call f_login
    pop bc
    jp nc,f_fail
    ld a,b
.set:
    ld (f_drive),a
    scf
    ret
.ask:
    ld a,(f_drive)
    add a,'A'
    ret

;; FILE_CAT: DE = a buffer (2 KB) -> the current drive's files listed as
;; AMSDOS lists them: "Drive A: user  0", the names in order, four to a
;; row, with their sizes in K, then what is free
FC_LEN      equ 13              ; in the buffer: the name, its records (2)
FC_MAX      equ 2048/FC_LEN
b_file_cat:
    ld (fc_buf),de
    push ix
    push iy
    ld a,(f_drive)
    call f_login
    jp nc,.fail
    xor a
    ld (fc_cnt),a
    ; every entry of user 0: its name noted, its records added
    call f_count
    ld (fs_n),hl
    ld hl,0
.e:
    push hl
    call f_entry
    pop hl
    jp nc,.fail
    ld a,(ix+0)
    or a
    jr nz,.enext
    push hl
    call fc_add
    pop hl
.enext:
    inc hl
    ld de,(fs_n)
    or a
    sbc hl,de
    add hl,de
    jr c,.e
    call fc_sort
    call f_nl
    ld hl,fc_m_drv
    call f_str
    ld a,(f_drive)
    add a,'A'
    call f_out
    ld hl,fc_m_user
    call f_str
    call f_nl
    call f_nl
    xor a
    ld (fc_col),a
    ld a,(fc_cnt)
    or a
    jr z,.end
    ld b,a
    ld ix,(fc_buf)
.show:
    push bc
    call fc_entry
    ld de,FC_LEN
    add ix,de
    pop bc
    djnz .show
.end:
    ld a,(fc_col)
    or a
    call nz,f_nl
    call f_nl
    call f_mapit                ; what is free: K
    call f_free
    ld iy,(f_dp)
    ld b,(iy+DP_BSH)
.k:
    ld a,b
    cp 3
    jr z,.kk
    add hl,hl                   ; (2 KB blocks: twice)
    dec b
    jr .k
.kk:
    call fc_num
    ld hl,fc_m_free
    call f_str
    call f_nl
    call f_nl
    pop iy
    pop ix
    scf
    ret
.fail:
    pop iy
    pop ix
    jp f_fail
fc_m_drv:   db "Drive ",0
fc_m_user:  db ": user  0",0
fc_m_free:  db "K free",0

;; fc_add: IX = an entry, user 0 -> its name in the list (once), its
;; records added: RC, and 128 for each extent before the last in it (EX's
;; low bits: none here, but as CP/M has it)
fc_add:
    ld a,(fc_cnt)
    ld b,a
    ld iy,(fc_buf)
    or a
    jr z,.new
.f:
    push bc
    push iy
    pop hl
    push ix
    pop de
    inc de
    ld b,11
.c:
    ld a,(de)
    and #7F
    cp (hl)
    jr nz,.ne
    inc hl
    inc de
    djnz .c
    pop bc
    jr .add
.ne:
    pop bc
    ld de,FC_LEN
    add iy,de
    djnz .f
.new:
    ld a,(fc_cnt)
    cp FC_MAX
    ret nc                      ; (too many: the rest not shown)
    inc a
    ld (fc_cnt),a
    push iy
    pop de
    push ix
    pop hl
    inc hl
    ld b,11
.cp:
    ld a,(hl)
    and #7F
    ld (de),a
    inc hl
    inc de
    djnz .cp
    xor a
    ld (iy+11),a
    ld (iy+12),a
.add:
    ld l,(iy+11)
    ld h,(iy+12)
    ld e,(ix+15)
    ld d,0
    add hl,de
    ld (iy+11),l
    ld (iy+12),h
    ret

;; fc_sort: the list in order of the names (an insertion sort)
fc_sort:
    ld a,(fc_cnt)
    cp 2
    ret c
    ld c,1                      ; C: the next to place
.next:
    ld a,(fc_cnt)
    cp c
    ret z
    ld b,c                      ; B: where it is now
.down:
    ld a,b
    or a
    jr z,.placed
    push bc
    call fc_at                  ; HL = item B
    push hl
    ld de,-FC_LEN
    add hl,de                   ; the one before it
    pop de                      ; DE = item B
    push de
    push hl
    ld b,11
.cmp:
    ld a,(de)
    cp (hl)
    jr nz,.diff
    inc hl
    inc de
    djnz .cmp
.diff:
    pop hl
    pop de
    jr nc,.inord                ; item B >= the one before: in order
    ld b,FC_LEN
.sw:
    ld a,(de)
    push af
    ld a,(hl)
    ld (de),a
    pop af
    ld (hl),a
    inc hl
    inc de
    djnz .sw
    pop bc
    dec b
    jr .down
.inord:
    pop bc
.placed:
    inc c
    jr .next
;; fc_at: B = an item -> HL = it
fc_at:
    ld hl,(fc_buf)
    ld de,FC_LEN
    inc b
.l:
    dec b
    ret z
    add hl,de
    jr .l

;; fc_entry: IX = an item -> shown as AMSDOS shows one: NAME    .EXT,
;; its size in K, three blanks between, four to a row
fc_entry:
    ld a,(fc_col)
    or a
    jr z,.name
    ld b,3
    call fc_to
    xor a
    ld (fc_n),a
.name:
    push ix
    pop hl
    ld b,8
.n:
    ld a,(hl)
    call fc_out
    inc hl
    djnz .n
    ld a,'.'
    call fc_out
    ld b,3
.t:
    ld a,(hl)
    call fc_out
    inc hl
    djnz .t
    ld l,(ix+11)                ; K = records / 8, up
    ld h,(ix+12)
    ld de,7
    add hl,de
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l
    ld iy,(f_dp)                ; (2 KB blocks: an even number)
    ld a,(iy+DP_BSH)
    cp 4
    jr c,fc_k
    inc hl
    res 0,l
;; fc_k: HL = a size in K -> it shown right-aligned in five places, "nnnK";
;; then on to the next column (four to a row). (The RAM disc's too.)
fc_k:
    ld a,' '
    call fc_out
    ld a,h
    or a
    jr nz,.n
    ld a,l
    cp 100
    jr nc,.n
    ld a,' '
    call fc_out
    ld a,l
    cp 10
    jr nc,.n
    ld a,' '
    call fc_out
.n:
    call fc_num
    ld a,'K'
    call fc_out
fc_next:
    ld a,(fc_col)
    inc a
    cp 4
    jr c,.gap
    call fc_nl
    xor a
    ld (fc_col),a
    ret
.gap:
    ld (fc_col),a
    xor a
    ld (fc_n),a
    ret

;; fc_to: blanks up to B characters of this entry. All kept but AF.
fc_to:
    ld a,(fc_n)
    cp b
    ret nc
    ld a,' '
    call fc_out
    jr fc_to

;; fc_num: HL = a number below 10000 -> it in decimal
fc_num:
    ld c,0                      ; no digit shown yet
    ld de,-1000
    call .d
    ld de,-100
    call .d
    ld de,-10
    call .d
    ld a,l
    add a,'0'
    jr fc_out
.d:
    ld a,'0'-1
.l:
    inc a
    add hl,de
    jr c,.l
    sbc hl,de                   ; (carry clear: one subtraction undone)
    cp '0'
    jr nz,.show
    inc c
    dec c
    ret z                       ; a leading zero
.show:
    ld c,1
;; fc_out: A to the screen, counted (fc_n). All kept but AF.
fc_out:
    push hl
    ld hl,fc_n
    inc (hl)
    pop hl
    jp JB+4*J_CON_PUTC          ; CON_PUTC, through the jumpblock: page A
;; fc_nl: a new line, the count 0
fc_nl:
    ld a,13
    call JB+4*J_CON_PUTC
    ld a,10
    call JB+4*J_CON_PUTC
    xor a
    ld (fc_n),a
    ret

fc_buf:     dw 0
fc_cnt:     db 0                ; the files in the list
fc_col:     db 0                ; files on this row so far
fc_n:       db 0                ; characters of this one so far
