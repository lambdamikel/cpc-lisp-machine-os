;; CPC Lisp -- the RAM disc, drive M:, on the 512K CPC (library part 0:
;; lib/disc.asm includes this). The TRS-80's (mach/trs80/rdisc80.asm),
;; made for the CPC's banks; keep the two in step.
;;
;; The expansion's free blocks are one space, an offset of three bytes
;; into it: blocks 0-2 of banks 0-5 (block 3 of each holds an image), then
;; the four blocks of banks 6 and 7 -- 288 KB in six banks, 416 KB in
;; eight. Its first KB is the directory: a header -- "CPCLISP RAMDISC1" and
;; where the files end -- and 31 entries of 32 bytes: [0] 1 if in use, [1]
;; the name (12 characters, upper case, blanks after), [13] where the file
;; starts, [16] its length. The files lie one after the other from offset
;; 1024; one saved again goes away first, the files after it moving down.
;; Without the header the disc is made empty. The expansion keeps it while
;; the power is on: a reset and RUN"LISP find it again (the loader writes
;; only block 3 of each bank).
;;
;; A block is seen at &4000 (configuration C4-C7 with the bank's bits),
;; where the code at &C000 would go from under the copying: RS_XFER
;; (resident.asm) does each copy, between the block and the main RAM -- the
;; file's buffer (block space, which may reach below &8000: RS_XFER copies
;; through a buffer of its own), RD_E for an entry.
;;
;; The file routines are the resident part's (FILE_GETC...): for a file on
;; M: they call rd_getc, rd_putc and rd_close here, in this bank, as
;; RDISC_IN and RDISC_OUT tell them (rd_reg, RD_IN, RD_OUT, jumps.asm).
;;
;; A file open on M: has the library's buffer for its state: [0] where
;; its next bytes are, [3] its end (reading) or start (writing), [6] the
;; bytes in the buffer, [7] the next one's index, [8] the entry (writing),
;; [9] 1 once a write found the disc full, [16] the name (writing), and its
;; bytes from +64.

RD_DATA     equ 1024            ; where files start
RD_NENT     equ 31
RD_E        equ RDISK           ; 32 bytes of RAM: an entry, the header
RD_ERA      equ TOKBUF+64       ; delete-file on a disc: |ERA's name,
RD_DESC     equ TOKBUF+68       ;   the file name's descriptor,
RD_PARM     equ TOKBUF+71       ;   the parameter

;; RDISC_IS: TOKBUF holds a file name -> Z if it is on drive M:. A only.
RDISC_IS:
    ld a,(TOKBUF+1)
    cp ':'
    ret nz
    ld a,(TOKBUF)
    or #20
    cp 'm'
    ret

;; rd_reg: the resident part told where the RAM disc's routines are
rd_reg:
    call SYS_CURBANK
    ld (RD_BANK),a
    ld hl,rd_getc
    ld (RD_VGETC),hl
    ld hl,rd_putc
    ld (RD_VPUTC),hl
    ld hl,rd_close
    ld (RD_VCLOSE),hl
    ret

rd_fail:
    ld a,1
    or a                        ; no carry, NZ: it failed
    ret

rd_off:     db 0,0,0            ; the disc's offset for rd_xfer
rx_dir:     db 0
rx_ram:     dw 0
rx_n:       dw 0
rx_k:       dw 0
rx_page:    db 0                ; (the configuration, C4-C7 + 8 * bank)
rd_cap:     db 0,0,0            ; the capacity: (RD_NBANKS - 6) * 64 KB + 288 KB
rd_end:     db 0,0,0            ; where the files end
rd_nm:      defs 12,' '         ; a name, as the directory has it
rd_k:       db 0                ; an entry's number
rd_t:       db 0,0,0            ; three bytes to work with
rd_s:       db 0,0,0
rd_len:     db 0,0,0
rd_s0:      db 0,0,0            ; where the deleted file ended
rd_magic:   db "CPCLISP RAMDISC1"

;; rd_xfer: A = 0, from the disc at rd_off to RAM at HL; 1, from RAM at
;; HL to the disc. BC bytes, split where a page ends; rd_off moves on.
rd_xfer:
    ld (rx_dir),a
    ld (rx_ram),hl
    ld (rx_n),bc
.l:
    ld hl,(rx_n)
    ld a,h
    or l
    ret z
    ld hl,(rd_off)
    ld a,h
    and #3F
    ld d,a
    ld e,l                      ; DE = where in the page
    ld a,h
    rlca
    rlca
    and 3
    ld c,a
    ld a,(rd_off+2)
    add a,a
    add a,a
    or c                        ; the 16 KB unit
    call rd_cfg
    ld (rx_page),a
    ld hl,#4000
    or a
    sbc hl,de                   ; HL = what is left of the block
    ld bc,(rx_n)
    push hl
    or a
    sbc hl,bc
    pop hl
    jr c,.k                     ; less than asked: that much
    ld h,b
    ld l,c
.k:
    ld (rx_k),hl
    ld hl,#4000
    add hl,de
    ex de,hl                    ; DE = the block's side, at &4000
    ld hl,(rx_ram)
    ld a,(rx_dir)
    or a
    jr nz,.go
    ex de,hl                    ; from the page: HL there, DE the RAM
.go:
    ld bc,(rx_k)
    ld a,(rx_dir)
    cp 1                        ; carry: from the block (HL its side)
    ld a,(rx_page)
    call RS_XFER
    ld bc,(rx_k)
    ld hl,(rx_ram)
    add hl,bc
    ld (rx_ram),hl
    ld hl,(rx_n)
    or a
    sbc hl,bc
    ld (rx_n),hl
    ld hl,(rd_off)
    add hl,bc
    ld (rd_off),hl
    ld a,(rd_off+2)
    adc a,0
    ld (rd_off+2),a
    jr .l

;; rd_at: HL = an offset below 64 KB -> rd_off
rd_at:
    ld (rd_off),hl
    xor a
    ld (rd_off+2),a
    ret

;; rd_entry: A = an entry's number -> rd_off at it
rd_entry:
    inc a
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl                   ; 32 (k + 1)
    jr rd_at
;; rd_get, rd_put: A = an entry's number -> it read into RD_E, or written
;; from there
rd_get:
    call rd_entry
    xor a
    jr rd_32
rd_put:
    call rd_entry
    ld a,1
rd_32:
    ld hl,RD_E
    ld bc,32
    jp rd_xfer

;; rd_cfg: A = a 16 KB unit of the disc -> A = the configuration that
;; shows it at &4000: units 0-17 are blocks 0-2 of banks 0-5 (block 3 has
;; the code), then the four blocks of bank 6, of bank 7. BC lost.
rd_cfg:
    cp 18
    jr nc,.hi
    ld c,0
.d3:
    cp 3
    jr c,.go
    sub 3
    inc c
    jr .d3
.hi:
    sub 18
    ld b,a
    rrca
    rrca
    and #3F
    add a,6
    ld c,a                      ; bank 6 + unit / 4,
    ld a,b
    and 3                       ;   block unit mod 4
.go:
    ld b,a
    ld a,c
    add a,a
    add a,a
    add a,a
    or b
    or #C4
    ret

;; rd_ready: the capacity from the banks; the header read -> rd_end; the
;; disc made empty if it has none
rd_ready:
    ld a,(RD_NBANKS)            ; units: 18, and 4 a bank past six
    sub 6
    jr c,.noram                 ; (a plain 6128: its banks hold the code)
    add a,a
    add a,a
    add a,18
    ld b,a
    srl a
    srl a
    ld (rd_cap+2),a             ; * 16 KB: units / 4 ...
    ld a,b
    rrca
    rrca
    and #C0
    ld (rd_cap+1),a             ;   ... and units mod 4 * &4000
    xor a
    ld (rd_cap),a
    ld hl,0
    call rd_at
    xor a
    call rd_32                  ; (the header, as entry -1)
    ld hl,RD_E
    ld de,rd_magic
    ld b,16
.cmp:
    ld a,(de)
    cp (hl)
    jr nz,.new
    inc hl
    inc de
    djnz .cmp
    ld hl,(RD_E+16)
    ld (rd_end),hl
    ld a,(RD_E+18)
    ld (rd_end+2),a
    ret
.noram:
    call fl_release             ; (the buffer lent for the file: an error
    ld hl,rd_m_noram            ;   caught by %catch-errors left it lent)
    ld de,UNBOUND
    jp lib_error
.new:
    ld hl,RD_E                  ; empty entries
    ld b,32
.z:
    ld (hl),0
    inc hl
    djnz .z
    xor a
.ze:
    push af
    call rd_put
    pop af
    inc a
    cp RD_NENT
    jr c,.ze
    ld hl,RD_DATA
    ld (rd_end),hl
    xor a
    ld (rd_end+2),a
;; rd_header: the header written: the magic, rd_end
rd_header:
    ld hl,rd_magic
    ld de,RD_E
    ld bc,16
    ldir
    ld hl,(rd_end)
    ld (RD_E+16),hl
    ld a,(rd_end+2)
    ld (RD_E+18),a
    ld hl,0
    call rd_at
    ld a,1
    jp rd_32

;; rd_name: TOKBUF = "M:name", B its length -> rd_nm
rd_name:
    ld hl,rd_nm
    ld c,12
.bl:
    ld (hl),' '
    inc hl
    dec c
    jr nz,.bl
    ld a,b
    sub 2
    ret z
    ret c
    cp 13
    jr c,.n
    ld a,12
.n:
    ld b,a
    ld hl,TOKBUF+2
    ld de,rd_nm
.ch:
    ld a,(hl)
    cp 'a'
    jr c,.up
    cp 'z'+1
    jr nc,.up
    and #DF
.up:
    ld (de),a
    inc hl
    inc de
    djnz .ch
    ret

;; rd_find: -> carry and rd_k = the entry named rd_nm (it in RD_E), or no
;; carry
rd_find:
    xor a
.l:
    ld (rd_k),a
    call rd_get
    ld a,(RD_E)
    or a
    jr z,.next
    ld hl,RD_E+1
    ld de,rd_nm
    ld b,12
.c:
    ld a,(de)
    cp (hl)
    jr nz,.next
    inc hl
    inc de
    djnz .c
    scf
    ret
.next:
    ld a,(rd_k)
    inc a
    cp RD_NENT
    jr c,.l
    or a
    ret

;; rd_free: -> carry and rd_k = an entry not in use, or no carry
rd_free:
    xor a
.l:
    ld (rd_k),a
    call rd_get
    ld a,(RD_E)
    or a
    scf
    ret z
    ld a,(rd_k)
    inc a
    cp RD_NENT
    jr c,.l
    or a
    ret

;; RDISC_IN: TOKBUF = "M:name", B its length, DE = the buffer -> carry if
;; that file is open for reading
RDISC_IN:
    push de
    call rd_name
    call rd_ready
    call rd_find
    pop ix
    jp nc,rd_fail
    ld a,(RD_E+13)              ; where it starts,
    ld (ix+0),a
    ld a,(RD_E+14)
    ld (ix+1),a
    ld a,(RD_E+15)
    ld (ix+2),a
    ld hl,(RD_E+13)             ;   and ends: start + length
    ld de,(RD_E+16)
    add hl,de
    ld (ix+3),l
    ld (ix+4),h
    ld a,(RD_E+15)
    ld b,a
    ld a,(RD_E+18)
    adc a,b
    ld (ix+5),a
    xor a
    ld (ix+6),a
    ld (ix+7),a
    ld (RD_IBUF),ix
    call rd_reg
    ld a,1
    ld (RD_IN),a
    scf
    ret

;; rd_getc: IX = the state -> carry and A = the next byte; no carry, NZ at
;; the end
rd_getc:
    ld a,(ix+7)
    cp (ix+6)
    jr c,.have
    ld a,(ix+0)                 ; the buffer used up: the next bytes
    ld (rd_off),a
    ld a,(ix+1)
    ld (rd_off+1),a
    ld a,(ix+2)
    ld (rd_off+2),a
    ld l,(ix+3)                 ; how many are left: end - where
    ld h,(ix+4)
    ld e,(ix+0)
    ld d,(ix+1)
    or a
    sbc hl,de
    ld a,(ix+5)
    sbc a,(ix+2)
    jp c,rd_fail
    jr nz,.full                 ; 64 KB or more: a bufferful
    ld a,h
    or l
    jp z,rd_fail                 ; none
    ld a,h
    or a
    jr nz,.full
    ld a,l
    cp 255
    jr c,.part
.full:
    ld hl,255                   ; (a count that fits in a byte)
.part:
    ld b,h
    ld c,l
    push ix
    pop hl
    ld de,64
    add hl,de
    push bc
    xor a
    call rd_xfer
    pop bc
    ld a,(rd_off)               ; where the next ones are
    ld (ix+0),a
    ld a,(rd_off+1)
    ld (ix+1),a
    ld a,(rd_off+2)
    ld (ix+2),a
    ld a,c                      ; C: how many
    ld (ix+6),a
    xor a
    ld (ix+7),a
.have:
    ld e,(ix+7)
    inc (ix+7)
    ld d,0
    push ix
    pop hl
    add hl,de
    ld de,64
    add hl,de
    ld a,(hl)
    scf
    ret

;; RDISC_OUT: TOKBUF = "M:name", B its length, DE = the buffer -> carry if
;; a file of that name is open for writing (one there before goes)
RDISC_OUT:
    push de
    call rd_name
    call rd_ready
    call rd_find
    pop ix
    push ix
    call c,rd_delete
    call rd_free
    pop ix
    jp nc,rd_fail                ; the directory is full
    ld a,(rd_end)
    ld (ix+0),a
    ld (ix+3),a
    ld a,(rd_end+1)
    ld (ix+1),a
    ld (ix+4),a
    ld a,(rd_end+2)
    ld (ix+2),a
    ld (ix+5),a
    xor a
    ld (ix+7),a
    ld (ix+9),a
    ld a,(rd_k)
    ld (ix+8),a
    push ix
    pop de
    ld hl,16
    add hl,de
    ex de,hl
    ld hl,rd_nm
    ld bc,12
    ldir                        ; the name, in the state
    ld (RD_OBUF),ix
    call rd_reg
    ld a,1
    ld (RD_OUT),a
    scf
    ret

;; rd_putc: IX = the state, A = a byte -> carry if it is written
rd_putc:
    ld e,(ix+7)
    ld d,0
    push ix
    pop hl
    add hl,de
    ld de,64
    add hl,de
    ld (hl),a
    inc (ix+7)
    scf
    ret nz                      ; not yet 256
;; rd_flush: the buffer's bytes to the disc ((ix+7), 0 for 256) -> no
;; carry if the disc is full
rd_flush:
    ld c,(ix+7)
    ld b,0
    ld a,c
    or a
    jr nz,.n
    inc b                       ; 256
.n:
    ld a,(ix+0)
    ld (rd_off),a
    ld a,(ix+1)
    ld (rd_off+1),a
    ld a,(ix+2)
    ld (rd_off+2),a
    ld hl,(rd_off)              ; room? where + count <= the capacity
    add hl,bc
    ld a,(rd_off+2)
    adc a,0
    ld e,a
    ld a,(rd_cap+2)
    cp e
    jr c,.full
    jr nz,.ok
    ld a,(rd_cap+1)
    cp h
    jr c,.full
    jr nz,.ok
    ld a,l
    or a
    jr z,.ok
.full:
    ld (ix+9),1                 ; (its close says nothing more)
    jp rd_fail
.ok:
    push ix
    pop hl
    ld de,64
    add hl,de
    ld a,1
    call rd_xfer
    ld a,(rd_off)
    ld (ix+0),a
    ld a,(rd_off+1)
    ld (ix+1),a
    ld a,(rd_off+2)
    ld (ix+2),a
    xor a
    ld (ix+7),a
    scf
    ret

;; rd_close: IX = an output file's state: the rest written, its entry
;; and the header -> carry if it went. A file that did not fit is let go
;; (its write has said so).
rd_close:
    ld a,(ix+9)
    or a
    scf
    ret nz
    ld a,(ix+7)
    or a
    call nz,rd_flush
    ret nc
    ld hl,RD_E
    ld (hl),1
    inc hl
    ex de,hl
    push ix
    pop hl
    ld bc,16
    add hl,bc
    ld bc,12
    ldir                        ; its name, from the state
    ld a,(ix+3)
    ld (RD_E+13),a
    ld a,(ix+4)
    ld (RD_E+14),a
    ld a,(ix+5)
    ld (RD_E+15),a
    ld l,(ix+0)                 ; the length: where it got to - start
    ld h,(ix+1)
    ld e,(ix+3)
    ld d,(ix+4)
    or a
    sbc hl,de
    ld (RD_E+16),hl
    ld a,(ix+2)
    sbc a,(ix+5)
    ld (RD_E+18),a
    ld a,(ix+8)
    call rd_put
    ld a,(ix+0)
    ld (rd_end),a
    ld a,(ix+1)
    ld (rd_end+1),a
    ld a,(ix+2)
    ld (rd_end+2),a
    call rd_header
    scf
    ret

;; rd_delete: rd_k = an entry in use, RD_E it, IX = a buffer -> the
;; file gone, the files after it moved down, their entries too
rd_delete:
    ld hl,(RD_E+13)             ; s: where it starts
    ld (rd_s),hl
    ld a,(RD_E+15)
    ld (rd_s+2),a
    ld hl,(RD_E+16)             ; its length
    ld (rd_len),hl
    ld a,(RD_E+18)
    ld (rd_len+2),a
    xor a
    ld (RD_E),a
    ld a,(rd_k)
    call rd_put                 ; the entry free
    ; rd_t = s + length: what comes after it, moved to s
    ld hl,(rd_s)
    ld de,(rd_len)
    add hl,de
    ld (rd_t),hl
    ld a,(rd_s+2)
    ld b,a
    ld a,(rd_len+2)
    adc a,b
    ld (rd_t+2),a
    ld (rd_s0+2),a              ; (and where it ended)
    ld (rd_s0),hl
.move:
    ld hl,(rd_end)              ; left: end - t
    ld de,(rd_t)
    or a
    sbc hl,de
    ld a,(rd_end+2)
    ld b,a
    ld a,(rd_t+2)
    ld c,a
    ld a,b
    sbc a,c
    jr nz,.whole
    ld a,h
    or l
    jr z,.moved
    ld a,h
    or a
    jr z,.part
.whole:
    ld hl,256
.part:
    push hl
    ld hl,(rd_t)                ; read it from t
    ld (rd_off),hl
    ld a,(rd_t+2)
    ld (rd_off+2),a
    pop bc
    push bc
    push ix
    pop hl
    ld de,64
    add hl,de
    push hl
    xor a
    call rd_xfer
    ld hl,(rd_off)
    ld (rd_t),hl
    ld a,(rd_off+2)
    ld (rd_t+2),a
    ld hl,(rd_s)                ; and write it at s
    ld (rd_off),hl
    ld a,(rd_s+2)
    ld (rd_off+2),a
    pop hl
    pop bc
    ld a,1
    call rd_xfer
    ld hl,(rd_off)
    ld (rd_s),hl
    ld a,(rd_off+2)
    ld (rd_s+2),a
    jr .move
.moved:
    ld hl,(rd_s)                ; the end is where s got to
    ld (rd_end),hl
    ld a,(rd_s+2)
    ld (rd_end+2),a
    ; the entries after it: their start less the length
    xor a
.ent:
    ld (rd_t),a
    call rd_get
    ld a,(RD_E)
    or a
    jr z,.nx
    ld hl,(RD_E+13)             ; after it? a start at or past its end
    ld de,(rd_s0)
    or a
    sbc hl,de
    ld a,(RD_E+15)
    ld b,a
    ld a,(rd_s0+2)
    ld c,a
    ld a,b
    sbc a,c
    jr c,.nx
    ld hl,(RD_E+13)
    ld de,(rd_len)
    or a
    sbc hl,de
    ld (RD_E+13),hl
    ld a,(RD_E+15)
    ld b,a
    ld a,(rd_len+2)
    ld c,a
    ld a,b
    sbc a,c
    ld (RD_E+15),a
    ld a,(rd_t)
    call rd_put
.nx:
    ld a,(rd_t)
    inc a
    cp RD_NENT
    jr c,.ent
    jp rd_header

;; (delete-file "name") -> T: on M:, from the RAM disc (the files after it
;; moving down); else through the disc ROM's |ERA (which says itself if
;; there is no such file).
;@ DELETE-FILE 1 1 lf_delete_file
lf_delete_file:
    push hl
    call fl_name
    call RDISC_IS
    jr nz,.disc
    push bc
    call fl_lend                ; DE = a buffer, for the moving
    pop bc
    push de
    call rd_name
    call rd_ready
    call rd_find
    pop ix
    jr nc,.none
    call rd_delete
    call fl_release
    pop hl
    jp lt
.none:
    call fl_release
    pop de
    ld hl,rd_m_none
    jp lib_error
.disc:
    ld a,b
    ld (RD_DESC),a              ; the name's descriptor: length, address
    ld hl,TOKBUF
    ld (RD_DESC+1),hl
    ld hl,RD_DESC
    ld (RD_PARM),hl
    ld hl,"E"+256*"R"           ; |ERA, its name in RAM for the search
    ld (RD_ERA),hl
    ld a,"A"+#80
    ld (RD_ERA+2),a
    ld hl,RD_ERA
    call KL_FIND_COMMAND
    jr nc,.nodisc               ; no disc ROM
    ld ix,RD_PARM
    ld a,1
    call KL_FAR_PCHL
    pop hl
    jp lt
.nodisc:
    pop de
    ld hl,rd_m_none
    jp lib_error
rd_m_none:  db "no such file:",0
rd_m_noram: db "no RAM disc (M: needs a 512K expansion)",0

;; RDISC_CAT: the RAM disc's files and their sizes, and what is free
RDISC_CAT:
    call rd_ready
    ld hl,rd_m_head
    call fc_str
    call fc_nl
    xor a
    ld (fc_col),a
    ld (fc_n),a
.l:
    ld (rd_k),a
    call rd_get
    ld a,(RD_E)
    or a
    jr z,.next
    ld hl,RD_E+1
    ld b,12
    call fc_part
    ld hl,(RD_E+16)             ; K = (length + 1023) / 1024
    ld de,1023
    add hl,de
    ld a,(RD_E+18)
    adc a,0
    ld l,h
    ld h,a
    srl h
    rr l
    srl h
    rr l
    call rd_size
.next:
    ld a,(rd_k)
    inc a
    cp RD_NENT
    jr c,.l
    ld a,(fc_col)
    or a
    call nz,fc_nl
    ld hl,(rd_end)              ; free: (capacity - end) / 1024
    ld a,(rd_end+2)
    ld e,a
    ld a,0
    sub l
    ld a,(rd_cap+1)
    sbc a,h
    ld l,a
    ld a,(rd_cap+2)
    sbc a,e
    ld h,a                      ; HL = (capacity - end) >> 8
    srl h
    rr l
    srl h
    rr l
    call fc_num
    ld hl,rd_m_free
    call fc_str
    jp fc_nl
;; rd_size: HL = K -> padded, shown, two to a row (40 columns)
rd_size:
.pad:
    ld a,(fc_n)
    cp 14
    jr nc,.sz
    ld a,' '
    call fc_out
    jr .pad
.sz:
    call fc_num
    ld a,'K'
    call fc_out
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
.g:
    ld a,(fc_n)
    cp 20
    jr nc,.done
    ld a,' '
    call fc_out
    jr .g
.done:
    xor a
    ld (fc_n),a
    ret

rd_m_head:  db 13,10,"Drive M: (RAM)",0
rd_m_free:  db "K free",0

;; the listing's helpers (as mach/trs80/files80.asm's)
;; fc_part: HL = B characters -> shown, spaces left out; HL past them
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
    jp CON_PUTC
fc_nl:
    ld a,13
    call CON_PUTC
    ld a,10
    call CON_PUTC
    xor a
    ld (fc_n),a
    ret
fc_str:
    ld a,(hl)
    or a
    ret z
    call CON_PUTC
    inc hl
    jr fc_str
fc_col:     db 0                ; files on this row so far
fc_n:       db 0                ; characters of this one so far
