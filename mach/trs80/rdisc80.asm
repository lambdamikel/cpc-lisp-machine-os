;; CPC Lisp -- the RAM disc, drive M:, on the TRS-80, in the machine page
;; (page.asm includes this).
;;
;; X-MEM/80's pages 9-31 are one space of 368 KB, an offset of three
;; bytes into it. Its first KB is the directory: a header -- "CPCLISP
;; RAMDISC1" and where the files end -- and 31 entries of 32 bytes: [0]
;; 1 if in use, [1] the name (12 characters, upper case, blanks after),
;; [13] where the file starts, [16] its length. The files lie one after
;; the other from offset 1024; one saved again goes away first, the files
;; after it moving down, so the space stays in one piece. Without the
;; header the disc is made empty. The pages keep it while the power is on:
;; Lisp may quit and start again.
;;
;; The machine page is at &C000, where the disc's pages have to be seen,
;; so RS_XFER (resident.asm) does the copying, between a page and RAM
;; that is always there: the file's buffer, RD_E for an entry.
;;
;; A file open on M: has the library's buffer for its state: [0] where
;; its next bytes are, [3] its end (reading) or start (writing), [6] the
;; bytes in the buffer, [7] the next one's index, [8] the entry (writing),
;; [9] 1 once a write found the disc full, [16] the name (writing), and its
;; bytes from +64.

RD_PAGE0    equ 9               ; the first page
RD_CAPH     equ #05             ; 23 pages: &05C000 bytes
RD_CAPM     equ #C0
RD_DATA     equ 1024            ; where files start
RD_NENT     equ 31
RD_E        equ RDISK           ; 32 bytes of RAM: an entry, the header

rd_off:     db 0,0,0            ; the disc's offset for rd_xfer
rx_dir:     db 0
rx_ram:     dw 0
rx_n:       dw 0
rx_k:       dw 0
rx_page:    db 0
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
    or c
    add a,RD_PAGE0
    ld (rx_page),a
    ld hl,#4000
    or a
    sbc hl,de                   ; HL = what is left of the page
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
    ld hl,#C000
    add hl,de
    ex de,hl                    ; DE = the page's side
    ld hl,(rx_ram)
    ld a,(rx_dir)
    or a
    jr nz,.go
    ex de,hl                    ; from the page: HL there, DE the RAM
.go:
    ld bc,(rx_k)
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

;; rd_ready: the header read -> rd_end; the disc made empty if it has
;; none
rd_ready:
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

;; M_RDIN: TOKBUF = "M:name", B its length, DE = the buffer -> carry if
;; that file is open for reading
m_m_rdin:
    push de
    call rd_name
    call rd_ready
    call rd_find
    pop ix
    jp nc,f_fail
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
    push ix
    pop de
    ld (fi_fcb),de
    ld a,1
    ld (fi_rd),a
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
    jp c,f_fail
    jr nz,.full                 ; 64 KB or more: a bufferful
    ld a,h
    or l
    jp z,f_fail                 ; none
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

;; M_RDOUT: TOKBUF = "M:name", B its length, DE = the buffer -> carry if
;; a file of that name is open for writing (one there before goes)
m_m_rdout:
    push de
    call rd_name
    call rd_ready
    call rd_find
    pop ix
    push ix
    call c,rd_delete
    call rd_free
    pop ix
    jp nc,f_fail                ; the directory is full
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
    push ix
    pop de
    ld (fo_fcb),de
    ld a,1
    ld (fo_rd),a
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
    cp RD_CAPH
    jr c,.ok
    jr nz,.full
    ld a,h
    cp RD_CAPM
    jr c,.ok
    jr nz,.full
    ld a,l
    or a
    jr z,.ok
.full:
    ld (ix+9),1                 ; (its close says nothing more)
    jp f_fail
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

;; M_DELETE: TOKBUF = a file name, B its length, DE = a buffer -> carry if
;; that file was there and is deleted: on M:, from the RAM disc, the files
;; after it moving down; else through LDOS (@KILL)
m_m_delete:
    push ix
    call .go
    pop ix
    ret
.go:
    ld a,(TOKBUF+1)
    cp ':'
    jr nz,.ldos
    ld a,(TOKBUF)
    or #20
    cp 'm'
    jr nz,.ldos
    push de
    call rd_name
    call rd_ready
    call rd_find
    pop ix
    ret nc
    call rd_delete
    scf
    ret
.ldos:
    push de
    ld hl,TOKBUF
    call f_spec
    pop de
    call f_open
    ret nc
    ld hl,L_KILL
    call f_svc
    jp nz,f_fail
    scf
    ret

;; M_RDCAT: the RAM disc's files and their sizes, and what is free
m_m_rdcat:
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
    ld a,RD_CAPM
    sbc a,h
    ld l,a
    ld a,RD_CAPH
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
;; rd_size: HL = K -> padded, shown, three to a row
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

rd_m_head:  db "Drive M:",0
rd_m_free:  db "K free",0
