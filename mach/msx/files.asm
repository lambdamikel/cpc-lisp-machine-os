;; CPC Lisp -- files on the MSX, through MSX-DOS 2 (Nextor), in machine
;; page B (pageb.asm includes this).
;;
;; One file open for input and one for output, as on the CPC. The library
;; lends each a buffer of FILE_BUFSIZE bytes from block space -- in pages
;; 0 and 1, which DOS sees: for its calls (RS_DOS) its own segments are in
;; pages 2 and 3, and this page is not. The buffer: the file's handle, how
;; much of its data part is used, the name (an output file abandoned is
;; deleted by it), then 256 bytes of the file. A CPC name, [A:]NAME.EXT,
;; goes to DOS as it is, in capitals: in the current folder of its drive,
;; or of the current drive (cd's: DOS's own, _SELDSK).

FB_H        equ 0               ; DOS's handle
FB_N        equ 1               ; the data's bytes: read in, or to write (2)
FB_P        equ 3               ; the next to read (2)
FB_NAME     equ 5               ; the name, ending in 0 (up to 26 bytes)
FB_DATA     equ 32              ; the file's data, 256 bytes
    assert FB_DATA+256 <= FILE_BUFSIZE

fi_buf:     dw 0                ; the input file's buffer, 0 when none
fo_buf:     dw 0                ;   the output file's
fi_rd:      db 0                ; 1 if it is on the RAM disc
fo_rd:      db 0
f_sdrv:     db 0                ; the drive at the start (0 A:)
f_t:        dw 0

;; DOS fn: DOS's function fn, through the resident part (RS_DOS), with A,
;; B, DE, HL, IX as it takes them -> what it gives back; Z if it went (A =
;; its error, 0 for none)
macro DOS fn
    ld c,{fn}
    call RS_DOS
    or a
mend

;; f_init: from b_init: the drive Lisp started on
f_init:
    DOS D_CURDRV
    ld (f_sdrv),a
    ret

;; f_spec: HL = a CPC name, B = its length, DE = a place -> the name there
;; as DOS takes it, in capitals, ending in 0; no carry if it is too long.
;; DE past it.
f_spec:
    ld a,b
    cp 25
    jr nc,.bad
    or a
    jr z,.end
.ch:
    ld a,(hl)
    inc hl
    cp 'a'
    jr c,.up
    cp 'z'+1
    jr nc,.up
    and #DF
.up:
    ld (de),a
    inc de
    djnz .ch
.end:
    xor a
    ld (de),a
    scf
    ret
.bad:
    or a
    ret

;; f_open: IX = a buffer, its name in place, C = DOS's function (D_OPEN,
;; D_CREATE), A = the mode -> carry and the file open, its handle there
f_open:
    push ix
    pop hl
    ld de,FB_NAME
    add hl,de
    ex de,hl                    ; DE = the name
    ld b,0                      ; (D_CREATE: no attributes; replace one)
    push ix
    call RS_DOS
    pop ix
    or a
    jp nz,f_fail
    ld (ix+FB_H),b
    xor a
    ld (ix+FB_N),a
    ld (ix+FB_N+1),a
    ld (ix+FB_P),a
    ld (ix+FB_P+1),a
    scf
    ret
f_fail:
    ld a,1
    or a                        ; no carry, NZ: it failed
    ret

;; f_named: HL = a name, B = its length, DE = a buffer -> IX = the buffer,
;; the name in it; no carry if it is not a name for DOS
f_named:
    push de
    ex de,hl                    ; HL = the buffer, DE = the name
    push de
    ld de,FB_NAME
    add hl,de
    pop de
    ex de,hl                    ; HL = the name, DE = its place
    call f_spec
    pop ix
    ret

;; FILE_IOPEN: B = the name's length, HL = the name, DE = the buffer ->
;; carry if the file is open
b_file_iopen:
    xor a
    ld (fi_rd),a
    call f_named
    jp nc,f_fail
    ld a,1                      ; no writing
    ld c,D_OPEN
    call f_open
    ret nc
    ld (fi_buf),ix
    ret

;; FILE_OOPEN: the same, for writing: a file of that name is replaced
b_file_oopen:
    xor a
    ld (fo_rd),a
    call f_named
    jp nc,f_fail
    ld a,2                      ; no reading
    ld c,D_CREATE
    call f_open
    ret nc
    ld (fo_buf),ix
    ret

;; FILE_GETC: -> carry and A = the next byte; NZ and no carry at the end
b_file_getc:
    push bc
    push de
    push hl
    push ix
    ld a,(fi_rd)
    or a
    jr z,.dos
    ld ix,(fi_buf)
    call rd_getc
    jr .out
.dos:
    ld ix,(fi_buf)
    ld a,(fi_buf+1)
    or a
    jr z,.end
    ld l,(ix+FB_P)
    ld h,(ix+FB_P+1)
    ld e,(ix+FB_N)
    ld d,(ix+FB_N+1)
    or a
    sbc hl,de
    jr c,.have
    push ix                     ; all read: the next 256
    pop hl
    ld de,FB_DATA
    add hl,de
    ex de,hl
    ld b,(ix+FB_H)
    ld hl,256
    push ix
    DOS D_READ
    pop ix
    jr nz,.end                  ; (the end: DOS's .EOF)
    ld a,h
    or l
    jr z,.end
    ld (ix+FB_N),l
    ld (ix+FB_N+1),h
    xor a
    ld (ix+FB_P),a
    ld (ix+FB_P+1),a
.have:
    ld l,(ix+FB_P)
    ld h,(ix+FB_P+1)
    push hl
    inc hl
    ld (ix+FB_P),l
    ld (ix+FB_P+1),h
    pop de
    push ix
    pop hl
    add hl,de
    ld de,FB_DATA
    add hl,de
    ld a,(hl)
    scf
    jr .out
.end:
    call f_fail
.out:
    pop ix
    pop hl
    pop de
    pop bc
    ret

;; f_flush: IX = the output's buffer -> what is in its data written out;
;; carry if it went
f_flush:
    ld c,(ix+FB_N)
    ld b,(ix+FB_N+1)
    ld a,b
    or c
    scf
    ret z
    push ix
    pop hl
    ld de,FB_DATA
    add hl,de
    ex de,hl                    ; DE = the data
    ld h,b
    ld l,c                      ; HL = its bytes
    ld b,(ix+FB_H)
    push hl
    push ix
    DOS D_WRITE
    pop ix
    pop de                      ; (the bytes asked for)
    jp nz,f_fail
    or a                        ; all of them written?
    sbc hl,de
    jp nz,f_fail
    xor a
    ld (ix+FB_N),a
    ld (ix+FB_N+1),a
    scf
    ret

;; FILE_PUTC: A = a byte -> carry if it was written
b_file_putc:
    push bc
    push de
    push hl
    push ix
    ld c,a
    ld a,(fo_rd)
    or a
    jr z,.dos
    ld a,c
    ld ix,(fo_buf)
    call rd_putc
    jr .out
.dos:
    ld ix,(fo_buf)
    ld a,(fo_buf+1)
    or a
    jr z,.no
    ld e,(ix+FB_N)
    ld d,(ix+FB_N+1)
    push ix
    pop hl
    add hl,de
    push de
    ld de,FB_DATA
    add hl,de
    pop de
    ld (hl),c
    inc de
    ld (ix+FB_N),e
    ld (ix+FB_N+1),d
    ld a,d
    or a
    scf
    jr z,.out                   ; (fewer than 256)
    call f_flush
    jr .out
.no:
    call f_fail
.out:
    pop ix
    pop hl
    pop de
    pop bc
    ret

;; FILE_ICLOSE, FILE_IABANDON: the input file closed, if one is open
b_file_iclose:
b_file_iabandon:
    ld a,(fi_rd)
    or a
    jr z,.dos
    xor a
    ld (fi_rd),a
    ld hl,0
    ld (fi_buf),hl
    scf
    ret
.dos:
    ld hl,fi_buf
    jr f_close

;; FILE_OCLOSE: the output file's last bytes written, the file closed ->
;; carry if it all went; on the RAM disc, its entry made
b_file_oclose:
    ld a,(fo_rd)
    or a
    jr z,.dos
    xor a
    ld (fo_rd),a
    push ix
    ld ix,(fo_buf)
    call rd_close
    pop ix
    ld hl,0
    ld (fo_buf),hl
    ret
.dos:
    ld hl,(fo_buf)
    ld a,h
    or l
    scf
    ret z
    push ix
    push hl
    pop ix
    call f_flush
    pop ix
    push af
    ld hl,fo_buf
    call f_close
    pop bc
    ret nc
    push bc
    pop af
    ret

;; FILE_OABANDON: the output file closed and deleted; on the RAM disc,
;; forgotten
b_file_oabandon:
    ld a,(fo_rd)
    or a
    jr z,.dos
    xor a
    ld (fo_rd),a
    ld hl,0
    ld (fo_buf),hl
    scf
    ret
.dos:
    ld hl,(fo_buf)
    ld a,h
    or l
    scf
    ret z
    ld (f_t),hl
    ld hl,fo_buf
    call f_close
    push ix
    ld hl,(f_t)
    ld de,FB_NAME
    add hl,de
    ex de,hl
    DOS D_DELETE
    pop ix
    scf
    ret

;; f_close: HL = fi_buf or fo_buf -> that file closed, the word 0. Carry if
;; it went (or none was open).
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
    ex de,hl
    ld b,(hl)                   ; the handle
    push ix
    DOS D_CLOSE
    pop ix
    jp nz,f_fail
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
    call f_named
    jp nc,f_fail
    push ix
    pop hl
    ld de,FB_NAME
    add hl,de
    ex de,hl
    DOS D_DELETE
    jp nz,f_fail
    scf
    ret

;; M_DRIVE ((cd), drive.asm): A = a drive's letter -> carry if DOS has it:
;; it is the current drive from now on (DOS's own, _SELDSK); A = 0: back to
;; the start's; A = &FF -> A = the current drive's letter
b_m_drive:
    inc a
    jr z,.ask
    dec a
    jr nz,.l
    ld a,(f_sdrv)               ; none: the start's
    jr .set
.l:
    and #DF
    sub 'A'
    cp 8
    jp nc,f_fail
.set:
    ld (f_t),a
    DOS D_LOGIN                 ; HL: a bit for each drive there is
    ld a,(f_t)
    inc a
    ld b,a
.bit:
    srl h
    rr l
    djnz .bit                   ; carry: the drive's bit
    jp nc,f_fail
    ld a,(f_t)
    ld e,a
    DOS D_SELDSK
    scf
    ret
.ask:
    DOS D_CURDRV
    add a,'A'
    ret

;; FILE_CAT: DE = a buffer -> the current folder's files listed, two to a
;; row, with their sizes in K, a blank line before and after, as AMSDOS has
;; them: DOS's _FFIRST, _FNEXT, a FIB in the buffer -- +1 the name
;; (NAME.EXT, ending in 0), +14 the attributes (bit 4 a folder; 1, 2, 3
;; hidden, system, the volume's name), +21 the size (4) -- and "*.*" after
;; it.
FIB_NAME    equ 1
FIB_ATTR    equ 14
FIB_SIZE    equ 21
b_file_cat:
    ld (fc_buf),de
    ld hl,64
    add hl,de
    ld (fc_pat),hl
    ld (hl),'*'
    inc hl
    ld (hl),'.'
    inc hl
    ld (hl),'*'
    inc hl
    ld (hl),0
    xor a
    ld (fc_col),a
    call fc_nl
    ld de,(fc_pat)
    ld ix,(fc_buf)
    ld b,#10                    ; folders too
    DOS D_FFIRST
.next:
    jr nz,.end
    call fc_entry
    ld ix,(fc_buf)
    DOS D_FNEXT
    jr .next
.end:
    ld a,(fc_col)
    or a
    call nz,fc_nl
    call fc_nl
    ld e,0                      ; the current drive: what is free
    ld c,D_ALLOC                ;   (HL clusters of A sectors, 512 bytes)
    call RS_DOS
    ld b,a
    ex de,hl
    ld hl,0
    ld c,l
.m:
    add hl,de                   ; C:HL = clusters * sectors
    jr nc,.mc
    inc c
.mc:
    djnz .m
    srl c                       ; / 2: K
    rr h
    rr l
    ld (f_m32),hl
    ld l,c
    ld h,0
    ld (f_m32+2),hl
    call fc_big
    ld hl,rd_m_free
    call fc_str
    call fc_nl
    jp fc_nl

;; fc_big: f_m32 -> it in decimal (f_m32 lost)
fc_big:
    ld ix,mp_t
    call f_m2bcd
    ld hl,mp_t+1
    ld b,10
    ld c,0                      ; a digit shown yet
.d:
    ld a,(hl)
    bit 0,b
    jr z,.hi
    inc hl                      ; the byte's second digit: the next after
    jr .p
.hi:
    rrca
    rrca
    rrca
    rrca
.p:
    and 15
    jr nz,.show
    inc c
    dec c
    jr nz,.show                 ; a 0 after the first digit
    ld a,b
    dec a
    jr nz,.skip                 ; a leading 0 (not the last)
.show:
    ld c,1
    add a,'0'
    call fc_out
.skip:
    djnz .d
    ret

;; fc_entry: the entry in the FIB, shown if it is a file or a folder, as
;; AMSDOS shows them: NAME    .EXT, then the size, two to a row
fc_entry:
    ld hl,(fc_buf)
    ld de,FIB_ATTR
    add hl,de
    ld a,(hl)
    and #0E
    ret nz                      ; hidden, a system file, the volume
    ld c,(hl)                   ; C: its attributes
    ld hl,(fc_buf)
    inc hl                      ; FIB_NAME
    ld a,(hl)
    cp '.'
    ret z                       ; . and ..
    ld a,(fc_col)               ; the second on a row: three spaces first
    or a
    jr z,.name
    ld b,3
    call fc_to
    xor a
    ld (fc_n),a
.name:                          ; the name, to its dot
    ld a,(hl)
    or a
    jr z,.pad
    cp '.'
    jr z,.pad
    call fc_out
    inc hl
    jr .name
.pad:
    ld b,8
    call fc_to
    ld a,'.'
    call fc_out
    ld a,(hl)
    or a
    jr z,.ext
    inc hl                      ; past the dot: the extension
.e:
    ld a,(hl)
    or a
    jr z,.ext
    call fc_out
    inc hl
    jr .e
.ext:
    ld b,12
    call fc_to
    bit 4,c
    jr z,.file
    ld hl,fc_m_dir
.d:
    ld a,(hl)
    or a
    jp z,fc_next
    call fc_out
    inc hl
    jr .d
.file:
    ld hl,(fc_buf)
    ld de,FIB_SIZE
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld a,(hl)                   ; K = (size + 1023) / 1024, from bytes 0-2
    ld hl,1023
    add hl,de
    adc a,0
    ld l,h
    ld h,a
    srl h
    rr l
    srl h
    rr l
    jp fc_k

;; fc_k: HL = a size in K -> it shown right-aligned in five places, "nnnK";
;; then on to the next column (two to a row)
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
    cp 2
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

;; fc_to: spaces up to B characters of this entry. All kept but AF.
fc_to:
    ld a,(fc_n)
    cp b
    ret nc
    ld a,' '
    call fc_out
    jr fc_to
fc_m_dir:   db " DIR",0

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
    jp JB+4*J_CON_PUTC          ; CON_PUTC, through the jumpblock: page A
fc_nl:
    ld a,13
    call JB+4*J_CON_PUTC
    ld a,10
    call JB+4*J_CON_PUTC
    xor a
    ld (fc_n),a
    ret

fc_buf:     dw 0
fc_pat:     dw 0
fc_col:     db 0                ; files on this row so far
fc_n:       db 0                ; characters of this one so far
