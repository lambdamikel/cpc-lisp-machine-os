;; CPC Lisp -- files on the TRS-80, through LDOS, in the machine page
;; (page.asm includes this).
;;
;; One file open for input and one for output, as on the CPC. The library
;; lends each a 2 KB buffer from block space: the file's control block
;; (FCB) goes at its start, LDOS's sector buffer 64 bytes on. A CPC name,
;; [drive:]NAME.EXT, becomes LDOS's NAME/EXT[:drive], drives A-D being
;; 0-3; without one, LDOS looks in every drive.

L_KILL      equ #442C           ; DE = an open FCB: the file deleted
ROM_GET     equ #0013           ; DE = an FCB -> A = a byte, Z if it went
ROM_PUT     equ #001B           ; DE = an FCB, A = a byte -> Z if it went

fi_fcb:     dw 0                ; the input file's FCB, 0 when none
fi_rd:      db 0                ;   1 if it is on the RAM disc
fo_fcb:     dw 0                ; the output file's
fo_rd:      db 0
fs_buf:     defs 24,0           ; a name as LDOS has it, ending in 13

;; f_spec: HL = a CPC name, B = its length -> fs_buf, LDOS's name
f_spec:
    ld de,fs_buf
    ld c,0                      ; the drive's digit, if there is one
    ld a,b
    cp 3
    jr c,.name
    inc hl
    ld a,(hl)
    dec hl
    cp ':'
    jr nz,.name
    ld a,(hl)
    and #DF                     ; upper case
    sub 'A'-'0'
    ld c,a
    inc hl
    inc hl
    dec b
    dec b
.name:
    ld a,b
    or a
    jr z,.drive
.ch:
    ld a,(hl)
    inc hl
    cp '.'
    jr nz,.nd
    ld a,'/'
.nd:
    cp 'a'
    jr c,.up
    cp 'z'+1
    jr nc,.up
    and #DF
.up:
    ld (de),a
    inc de
    djnz .ch
.drive:
    ld a,c
    or a
    jr z,.end
    ld a,':'
    ld (de),a
    inc de
    ld a,c
    ld (de),a
    inc de
.end:
    ld a,13
    ld (de),a
    ret

;; f_svc: call the LDOS routine at HL with BC, DE as they are; IX, IY kept
f_svc:
    push ix
    push iy
    call .go
    pop iy
    pop ix
    ret
.go:
    jp (hl)

;; FILE_IOPEN: B = the name's length, HL = the name, DE = a 2 KB buffer ->
;; carry if the file is open
m_file_iopen:
    xor a
    ld (fi_rd),a
    push de
    call f_spec
    pop de
    ld (fi_fcb),de
    call f_open
    ret c
    ld hl,0
    ld (fi_fcb),hl
    ret
;; f_open: DE = the FCB, fs_buf the name -> carry if it is open: with
;; L_OPEN, or (f_open_hl) HL = L_INIT, which makes it if it is not there
f_open:
    ld hl,L_OPEN
f_open_hl:
    ld (f_rt),hl
    push de
    ld hl,fs_buf
    push ix
    push iy
    call L_FSPEC                ; HL = the name, DE = the FCB
    pop iy
    pop ix
    pop de
    jr nz,f_fail
    push de
    ld hl,64
    add hl,de                   ; the sector buffer
    ld b,0                      ; records of 256
    push ix
    push iy
    call .rt
    pop iy
    pop ix
    pop de
    jr nz,f_fail
    scf
    ret
.rt:
    push hl
    ld hl,(f_rt)
    ex (sp),hl
    ret
f_fail:
    ld a,1
    or a                        ; no carry, NZ: it failed
    ret
f_rt:       dw 0

;; FILE_OOPEN: the same, for writing: a file of that name is replaced
m_file_oopen:
    xor a
    ld (fo_rd),a
    push de
    call f_spec
    pop de
    ld (fo_fcb),de
    push de
    call f_open                 ; there already? then it goes
    pop de
    jr nc,.new
    push de
    ld hl,L_KILL
    call f_svc
    pop de
.new:
    ld hl,L_INIT
    call f_open_hl
    ret c
    ld hl,0
    ld (fo_fcb),hl
    ret

;; FILE_GETC: -> carry and A = the next byte; NZ and no carry at the end
m_file_getc:
    push bc
    push de
    push hl
    ld a,(fi_rd)
    or a
    jr z,.ldos
    push ix
    ld ix,(fi_fcb)
    call rd_getc
    pop ix
    pop hl
    pop de
    pop bc
    ret
.ldos:
    ld de,(fi_fcb)
    ld a,d
    or e
    jr z,.end
    ld hl,ROM_GET
    call f_svc
    jr nz,.end
    pop hl
    pop de
    pop bc
    scf
    ret
.end:
    pop hl
    pop de
    pop bc
    jp f_fail

;; FILE_PUTC: A = a byte -> carry if it was written
m_file_putc:
    push bc
    push de
    push hl
    ld c,a
    ld a,(fo_rd)
    or a
    jr z,.ldos
    ld a,c
    push ix
    ld ix,(fo_fcb)
    call rd_putc
    pop ix
    pop hl
    pop de
    pop bc
    ret
.ldos:
    ld de,(fo_fcb)
    ld a,d
    or e
    jr z,.no
    ld a,c
    ld hl,ROM_PUT
    call f_svc
    jr nz,.no
    pop hl
    pop de
    pop bc
    scf
    ret
.no:
    pop hl
    pop de
    pop bc
    jp f_fail

;; FILE_ICLOSE, FILE_IABANDON: the input file closed, if one is open
m_file_iclose:
m_file_iabandon:
    ld a,(fi_rd)
    or a
    jr z,.ldos
    xor a
    ld (fi_rd),a
    ld hl,0
    ld (fi_fcb),hl
    scf
    ret
.ldos:
    ld hl,fi_fcb
    jr f_close
;; FILE_OCLOSE: the output file closed -> carry if it went; on the RAM
;; disc, its entry made
m_file_oclose:
    ld a,(fo_rd)
    or a
    jr z,m_file_oabandon
    xor a
    ld (fo_rd),a
    push ix
    ld ix,(fo_fcb)
    call rd_close
    pop ix
    ld hl,0
    ld (fo_fcb),hl
    ret
;; FILE_OABANDON: the output file closed; on the RAM disc, forgotten
m_file_oabandon:
    ld a,(fo_rd)
    or a
    jr z,.ldos
    xor a
    ld (fo_rd),a
    ld hl,0
    ld (fo_fcb),hl
    scf
    ret
.ldos:
    ld hl,fo_fcb
f_close:
    ld e,(hl)
    inc hl
    ld d,(hl)
    xor a
    ld (hl),a
    dec hl
    ld (hl),a
    ld a,d
    or e
    scf
    ret z                       ; none open
    ld hl,L_CLOSE
    call f_svc
    jp nz,f_fail
    scf
    ret

;; FILE_CAT: DE = a buffer -> each drive's files listed, three to a row,
;; with their sizes: LDOS's DIR/SYS read as a file. Record 0 is the
;; allocation table, 1 the hash table; then the entries, 32 bytes each:
;; [0] attributes (bit 4 in use, 3 invisible, 6 a system file, 7 an
;; extension), [3] the last record's length, [5] the name, [13] the
;; extension, [20] the records.
m_file_cat:
    ld (fc_buf),de
    ld a,'0'
.drive:
    ld (fc_drv),a
    ld (fc_name+8),a
    ld hl,fc_name
    ld de,fs_buf
    ld bc,10
    ldir
    ld de,(fc_buf)
    call f_open
    jr nc,.next
    ld hl,fc_m_drive
    call fc_str
    ld a,(fc_drv)
    call m_con_putc
    ld a,':'
    call m_con_putc
    call fc_nl
    xor a
    ld (fc_col),a
    ld b,2                      ; past the two tables
.skip:
    push bc
    call fc_read
    pop bc
    jr nz,.close
    djnz .skip
.rec:
    call fc_read
    jr nz,.close
    ld hl,(fc_buf)
    ld de,64
    add hl,de                   ; the record
    ld b,8
.ent:
    push bc
    push hl
    call fc_entry
    pop hl
    ld de,32
    add hl,de
    pop bc
    djnz .ent
    jr .rec
.close:
    ld a,(fc_col)
    or a
    call nz,fc_nl
    ld de,(fc_buf)
    ld hl,L_CLOSE
    call f_svc
.next:
    ld a,(fc_drv)
    inc a
    cp '4'
    jr c,.drive
    ret

;; fc_read: the next record of DIR/SYS -> Z if there was one
fc_read:
    ld de,(fc_buf)
    ld hl,L_READ
    jp f_svc

;; fc_entry: HL = an entry: shown if it is a file of the user's
fc_entry:
    ld a,(hl)
    and #D8
    cp #10                      ; in use; not invisible, a system file, an
    ret nz                      ;   extension
    push hl
    ld de,5
    add hl,de
    ld b,8
    call fc_part                ; the name
    ld a,(hl)
    cp ' '
    jr z,.noext
    ld a,'/'
    call fc_out
    ld b,3
    call fc_part
.noext:
    pop hl
    ld de,20
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = records: K = (records + 3) / 4
    ex de,hl
    inc hl
    inc hl
    inc hl
    srl h
    rr l
    srl h
    rr l
.pad:
    ld a,(fc_n)
    cp 14
    jr nc,.size
    ld a,' '
    call fc_out
    jr .pad
.size:
    call fc_num
    ld a,'K'
    call fc_out
    ld a,(fc_col)
    inc a
    cp 3
    jr c,.gap
    call fc_nl
    xor a
    ld (fc_col),a
    ret
.gap:
    ld (fc_col),a
.g:
    ld a,(fc_n)
    cp 21
    jr nc,.done
    ld a,' '
    call fc_out
    jr .g
.done:
    xor a
    ld (fc_n),a
    ret

;; fc_part: HL = B characters -> shown, spaces at the end left out; HL
;; past them
fc_part:
    ld a,(hl)
    inc hl
    cp ' '
    call nz,fc_out
    djnz fc_part
    ret

;; fc_num: HL = a number below 1000 -> it in decimal
fc_num:
    ld c,0                      ; no digit shown yet
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
;; fc_out: A to the screen, counted. All kept but AF.
fc_out:
    push hl
    ld hl,fc_n
    inc (hl)
    pop hl
    jp m_con_putc
fc_nl:
    ld a,13
    call m_con_putc
    ld a,10
    call m_con_putc
    xor a
    ld (fc_n),a
    ret
fc_str:
    ld a,(hl)
    or a
    ret z
    call m_con_putc
    inc hl
    jr fc_str

fc_buf:     dw 0
fc_drv:     db 0
fc_col:     db 0                ; files on this row so far
fc_n:       db 0                ; characters of this one so far
fc_name:    db "DIR/SYS:0",13
fc_m_drive: db "Drive ",0
