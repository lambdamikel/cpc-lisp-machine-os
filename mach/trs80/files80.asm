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
fo_fcb:     dw 0                ; the output file's
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
    ld de,(fo_fcb)
    ld c,a
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
    ld hl,fi_fcb
    jr f_close
;; FILE_OCLOSE, FILE_OABANDON: the output file closed -> carry if it went
m_file_oclose:
m_file_oabandon:
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

;; FILE_CAT: not yet
m_file_cat:
    ret
