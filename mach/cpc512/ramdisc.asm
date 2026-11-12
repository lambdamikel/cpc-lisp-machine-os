;; CPC Lisp -- the RAM disc: drive M: in the 6128's second 64 KB (library
;; ROM, part 0).
;;
;; (load "m:name"), (save "m:name" ...), (dir "m:"), (delete-file "m:name")
;; -- a file name starting "M:" goes here instead of to the disc ROM. The
;; second 64 KB keeps its contents across a reset (not a power-off), so what
;; was saved there survives a crash.
;;
;; The 64 KB are one linear space: address A is in bank A/16K, which the
;; gate array maps at &4000-&7FFF (RAM configuration &C4-&C7) for each byte
;; read or written, and maps back (&C0) at once -- the heap lives there too.
;; This code runs in the ROM at &C000 and its stack is above &8000, so the
;; switch never pulls anything from under it. A 464 has no such banks: the
;; gate array ignores the configuration, which is how one is recognised.
;;
;;   0       "CPCLISPM", then 8 bytes unused
;;   16      63 entries of 16 bytes: [name 12, 0-padded][start][length];
;;           name[0] = 0 is a free entry
;;   1024    the files, packed in the order of their starts: deleting one
;;           moves the ones after it down
;;
;; While a file is open, three of the firmware's CAS vectors (close, abandon,
;; char) are replaced with far calls (RST 3) to the routines here, as a disc
;; ROM does with all of them: the core's reader and putc call CAS IN CHAR
;; and CAS OUT CHAR whatever is behind them. Closing or abandoning -- an
;; error abandons, at toplevel -- puts the disc ROM's vectors back. One input
;; and one output file may be open at once, as with the firmware's.

RD_NENT     equ 63
RD_ESIZE    equ 16
RD_DIR      equ 16
RD_DATA     equ 1024


;; the state, in RAM above the trampoline
RD_FIN      equ RDISK           ; far addresses (3 bytes each): input close,
                                ;   abandon, char,
RD_FOUT     equ RDISK+9         ;   output close, abandon, char
RD_SAVIN    equ RDISK+18        ; the disc ROM's vectors while ours are in:
RD_SAVOUT   equ RDISK+27        ;   input (9 bytes), output (9 bytes)
RD_IPTR     equ RDISK+36        ; input: the next byte,
RD_ILEFT    equ RDISK+38        ;   how many are left
RD_OPTR     equ RDISK+40        ; output: the next byte,
RD_OSTART   equ RDISK+42        ;   where the file starts,
RD_OENT     equ RDISK+44        ;   its directory entry,
RD_ONAME    equ RDISK+46        ;   its name (12)
RD_FLAGS    equ RDISK+58        ; bit 0: the input vectors are ours, 1: output
RD_RET      equ RDISK+59        ; a RET (rd_fix)
RD_END      equ RDISK+60
    assert RD_END <= #B100
RD_FNAME     equ TOKBUF+32       ; a name, as the directory keeps it (12)
RD_DS       equ TOKBUF+48       ; rd_delete: the file's start,
RD_DL       equ TOKBUF+50       ;   its length,
RD_DEND     equ TOKBUF+52       ;   the end of all the files
RD_ERA      equ TOKBUF+64       ; delete-file on a disc: |ERA's name,
RD_DESC     equ TOKBUF+68       ;   the file name's descriptor,
RD_PARM     equ TOKBUF+71       ;   the parameter

rd_m_noram: db "no RAM disc (M: needs 128 KB)",0
rd_m_none:  db "no such file:",0
rd_m_head:  db 13,10,"Drive M: (RAM)",13,10,13,10,0
rd_m_free:  db " bytes free",13,10,0
rd_sig:     db "CPCLISPM"

;; RDISC_IS: TOKBUF holds a file name -> Z if it is on drive M:. A only.
RDISC_IS:
    or 1                        ; the 512K CPC: no RAM disc yet (its banks
    ret                         ;   hold the code; to come in the free ones)

;; ---------------------------------------------------------------------------
;; bytes

;; rd_map: HL = a linear address -> HL = where it appears at &4000-&7FFF,
;; C = the RAM configuration for its bank, B = &7F (the gate array)
rd_map:
    ld a,h
    rlca
    rlca
    and 3
    or #C4
    ld c,a
    ld b,#7F
    ld a,h
    and #3F
    or #40
    ld h,a
    ret

;; rd_peek: HL = a linear address -> A = the byte there. All else kept.
rd_peek:
    push hl
    push bc
    call rd_map
    out (c),c
    ld a,(hl)
    ld c,#C0
    out (c),c
    pop bc
    pop hl
    ret

;; rd_poke: HL = a linear address, A = a byte to put there. All kept.
rd_poke:
    push hl
    push bc
    push af
    call rd_map
    pop af
    out (c),c
    ld (hl),a
    ld c,#C0
    out (c),c
    pop bc
    pop hl
    ret

;; rd_peekw: HL = a linear address -> DE = the word there. HL kept.
rd_peekw:
    call rd_peek
    ld e,a
    inc hl
    call rd_peek
    ld d,a
    dec hl
    ret

;; rd_pokew: HL = a linear address, DE = a word to put there. All kept.
rd_pokew:
    ld a,e
    call rd_poke
    inc hl
    ld a,d
    call rd_poke
    dec hl
    ret

;; ---------------------------------------------------------------------------
;; the disc

;; rd_ready: error unless there is a second 64 KB; formats it the first time
rd_ready:
    ld hl,#4000
    ld bc,#7FC4
    ld e,(hl)                   ; main RAM's byte at &4000
    out (c),c
    ld d,(hl)                   ; bank 4's, if there is one
    ld a,e
    cpl
    ld (hl),a
    ld c,#C0
    out (c),c
    ld a,(hl)
    cp e
    ld (hl),e                   ; (main RAM as it was, whatever happened)
    jr nz,.none                 ; the write went to main RAM: no banks
    ld c,#C4
    out (c),c
    ld (hl),d
    ld c,#C0
    out (c),c
    ld hl,0                     ; formatted?
    ld de,rd_sig
    ld b,8
.sig:
    call rd_peek
    ex de,hl
    cp (hl)
    ex de,hl
    jr nz,.format
    inc hl
    inc de
    djnz .sig
    ret
.format:
    ld hl,0
    ld de,rd_sig
    ld b,8
.wsig:
    ld a,(de)
    call rd_poke
    inc hl
    inc de
    djnz .wsig
    ld hl,RD_DIR
    ld b,RD_NENT
    xor a
.wdir:
    call rd_poke                ; a free entry
    ld de,RD_ESIZE
    add hl,de
    djnz .wdir
    ret
.none:
    ld hl,rd_m_noram
    ld de,UNBOUND
    jp lib_error

;; rd_name: TOKBUF holds "M:name", B its length -> RD_FNAME holds name, upper
;; case, padded with zeros
rd_name:
    ld hl,RD_FNAME
    ld c,12
.clr:
    ld (hl),0
    inc hl
    dec c
    jr nz,.clr
    ld a,b
    sub 2
    jr z,.bad
    cp 13
    jr nc,.bad
    ld b,a
    ld hl,TOKBUF+2
    ld de,RD_FNAME
.c:
    ld a,(hl)
    cp "a"
    jr c,.up
    cp "z"+1
    jr nc,.up
    sub 32
.up:
    ld (de),a
    inc hl
    inc de
    djnz .c
    ret
.bad:
    ld hl,fl_m_name
    ld de,UNBOUND
    jp lib_error

;; rd_find: -> carry and HL = the entry named RD_FNAME, or NC
rd_find:
    ld hl,RD_DIR
    ld b,RD_NENT
.e:
    push hl
    ld de,RD_FNAME
    ld c,12
.c:
    call rd_peek
    ex de,hl
    cp (hl)
    ex de,hl
    jr nz,.next
    inc hl
    inc de
    dec c
    jr nz,.c
    pop hl
    scf
    ret
.next:
    pop hl
    ld de,RD_ESIZE
    add hl,de
    djnz .e
    or a
    ret

;; rd_free: -> carry and HL = a free entry, or NC if all are in use
rd_free:
    ld hl,RD_DIR
    ld b,RD_NENT
    ld de,RD_ESIZE
.e:
    call rd_peek
    or a
    scf
    ret z
    add hl,de
    djnz .e
    or a
    ret

;; rd_used -> HL = the end of the files (where a new one goes)
rd_used:
    ld hl,RD_DIR
    ld bc,RD_DATA
    ld a,RD_NENT
.e:
    push af
    call rd_peek
    or a
    jr z,.next
    push hl
    ld de,14
    add hl,de
    call rd_peekw               ; its length
    ex de,hl
    add hl,bc
    ld c,l
    ld b,h
    pop hl
.next:
    ld de,RD_ESIZE
    add hl,de
    pop af
    dec a
    jr nz,.e
    ld l,c
    ld h,b
    ret

;; rd_delete: HL = an entry in use -> the entry freed, the files after it
;; moved down over it, an open input file's place kept
rd_delete:
    push hl
    call rd_used
    ld (RD_DEND),hl
    pop hl
    xor a
    call rd_poke                ; the entry is free
    ld de,12
    add hl,de
    call rd_peekw
    ld (RD_DS),de
    inc hl
    inc hl
    call rd_peekw
    ld (RD_DL),de
    ld a,d
    or e
    ret z
    ld hl,RD_DIR+12             ; the files after it start lower
    ld b,RD_NENT
.e:
    push hl
    ld de,-12
    add hl,de
    call rd_peek
    pop hl
    or a
    jr z,.next                  ; a free entry
    call rd_peekw               ; DE = its start
    push hl
    ld hl,(RD_DS)
    or a
    sbc hl,de
    jr nc,.keep                 ; it starts before
    ld hl,(RD_DL)
    ex de,hl
    or a
    sbc hl,de
    ex de,hl
    pop hl
    call rd_pokew
    push hl
.keep:
    pop hl
.next:
    ld de,RD_ESIZE
    add hl,de
    djnz .e
    ld hl,(RD_DS)               ; the bytes after it, down
    ld de,(RD_DL)
    add hl,de
    ex de,hl                    ; DE = from
    ld hl,(RD_DEND)
    or a
    sbc hl,de
    ld c,l
    ld b,h                      ; BC = how many
    ld hl,(RD_DS)               ; HL = to
.mv:
    ld a,b
    or c
    jr z,.moved
    ex de,hl
    call rd_peek
    ex de,hl
    call rd_poke
    inc hl
    inc de
    dec bc
    jr .mv
.moved:
    ld a,(RD_FLAGS)             ; a file being read past it moved too
    rra
    ret nc
    ld hl,(RD_IPTR)
    ld de,(RD_DS)
    or a
    sbc hl,de
    ret c
    add hl,de
    ld de,(RD_DL)
    or a
    sbc hl,de
    ld (RD_IPTR),hl
    ret

;; ---------------------------------------------------------------------------
;; files

;; rd_hook: HL = three CAS vectors (close, abandon, char), DE = 9 bytes to
;; keep them in, BC = 9 bytes for far addresses, IX = the three routines ->
;; the vectors far-call those, in this ROM
rd_hook:
    ld a,#C9
    ld (RD_RET),a
    push bc
    push hl
    ld bc,9
    ldir                        ; the disc ROM's, for afterwards
    pop hl
    pop de
    ld b,3
.v:
    ld (hl),#DF                 ; RST 3, a far call through
    inc hl
    ld (hl),e                   ;   the far address at DE:
    inc hl
    ld (hl),d
    inc hl
    ld a,(ix+0)                 ;   the routine,
    ld (de),a
    inc de
    ld a,(ix+1)
    ld (de),a
    inc de
    ld a,(V_LIBS)               ;   this ROM (part 0's)
    ld (de),a
    inc de
    inc ix
    inc ix
    djnz .v
    ret

rd_unhook_in:
    ld hl,RD_FLAGS
    bit 0,(hl)
    ret z
    res 0,(hl)
    ld hl,RD_SAVIN
    ld de,CAS_IN_CLOSE
    ld bc,9
    ldir
    ret

rd_unhook_out:
    ld hl,RD_FLAGS
    bit 1,(hl)
    ret z
    res 1,(hl)
    ld hl,RD_SAVOUT
    ld de,CAS_OUT_CLOSE
    ld bc,9
    ldir
    ret

;; RDISC_IN: TOKBUF holds "M:name", B its length -> carry if it is open
;; for reading, NC if there is no such file
RDISC_IN:
    call rd_name
    call rd_ready
    call rd_find
    ret nc
    ld de,12
    add hl,de
    call rd_peekw
    ld (RD_IPTR),de
    inc hl
    inc hl
    call rd_peekw
    ld (RD_ILEFT),de
    ld hl,RD_FLAGS
    set 0,(hl)
    ld hl,CAS_IN_CLOSE
    ld de,RD_SAVIN
    ld bc,RD_FIN
    ld ix,rd_in_far
    call rd_hook
    scf
    ret
rd_in_far:
    dw rd_in_close,rd_in_abandon,rd_in_char

;; RDISC_OUT: TOKBUF holds "M:name", B its length -> carry if it is open
;; for writing (a file of that name is deleted), NC if the directory is full
RDISC_OUT:
    call rd_name
    call rd_ready
    call rd_find
    call c,rd_delete
    call rd_free
    ret nc
    ld (RD_OENT),hl
    ld hl,RD_FNAME
    ld de,RD_ONAME
    ld bc,12
    ldir
    call rd_used
    ld (RD_OSTART),hl
    ld (RD_OPTR),hl
    ld hl,RD_FLAGS
    set 1,(hl)
    ld hl,CAS_OUT_CLOSE
    ld de,RD_SAVOUT
    ld bc,RD_FOUT
    ld ix,rd_out_far
    call rd_hook
    scf
    ret
rd_out_far:
    dw rd_out_close,rd_out_abandon,rd_out_char

;; The vectors' routines. RST 3 in a jumpblock entry returns past its far
;; address -- into the next vector -- so each first points that return at a
;; RET (RD_RET): the call then returns to whoever called the vector. (AMSDOS
;; has one routine for all its vectors and takes that address off itself, as
;; it tells it which vector was called.)
macro RDFIX vector
    push de
    ld de,{vector}+3
    call rd_fix
    pop de
mend

;; rd_fix: DE = the address after a vector -> that return address, in the
;; far call's frame further up the stack, becomes RD_RET. All kept.
rd_fix:
    push af
    push hl
    push bc
    ld hl,10                    ; past BC, HL, AF, this call and the DE
    add hl,sp
    ld b,12
.f:
    ld a,(hl)
    inc hl
    cp e
    jr nz,.n
    ld a,(hl)
    cp d
    jr nz,.n
    ld (hl),RD_RET >> 8
    dec hl
    ld (hl),RD_RET and #FF
    jr .done
.n:
    inc hl
    djnz .f
.done:
    pop bc
    pop hl
    pop af
    ret

;; CAS IN CHAR: carry and A = the next byte, or NC NZ at the end
rd_in_char:
    RDFIX CAS_IN_CHAR
    push hl
    ld hl,(RD_ILEFT)
    ld a,h
    or l
    jr z,.end
    dec hl
    ld (RD_ILEFT),hl
    ld hl,(RD_IPTR)
    call rd_peek
    inc hl
    ld (RD_IPTR),hl
    pop hl
    scf
    ret
.end:
    pop hl
    ld a,#1A
    or a
    ret

;; CAS IN CLOSE, CAS IN ABANDON: the disc ROM's vectors back
rd_in_close:
    RDFIX CAS_IN_CLOSE
    jr rd_in_shut
rd_in_abandon:
    RDFIX CAS_IN_ABANDON
rd_in_shut:
    push hl
    push de
    push bc
    call rd_unhook_in
    pop bc
    pop de
    pop hl
    scf
    ret

;; CAS OUT CHAR: A = a byte -> carry, or NC if the RAM disc is full
rd_out_char:
    RDFIX CAS_OUT_CHAR
    push hl
    ld hl,(RD_OPTR)
    push af
    ld a,h
    or l
    jr z,.full                  ; past &FFFF
    pop af
    call rd_poke
    inc hl
    ld (RD_OPTR),hl
    pop hl
    scf
    ret
.full:
    pop af
    pop hl
    or a
    ret

;; CAS OUT ABANDON: the file is dropped, the disc ROM's vectors back
rd_out_abandon:
    RDFIX CAS_OUT_ABANDON
    push hl
    push de
    push bc
    call rd_unhook_out
    pop bc
    pop de
    pop hl
    scf
    ret

;; CAS OUT CLOSE: the file goes in the directory
rd_out_close:
    RDFIX CAS_OUT_CLOSE
    push hl
    push de
    push bc
    ld hl,(RD_OENT)
    ld de,RD_ONAME
    ld b,12
.n:
    ld a,(de)
    call rd_poke
    inc hl
    inc de
    djnz .n
    ld de,(RD_OSTART)
    call rd_pokew
    inc hl
    inc hl
    push hl
    ld hl,(RD_OPTR)
    or a
    sbc hl,de
    ex de,hl
    pop hl
    call rd_pokew
    call rd_unhook_out
    pop bc
    pop de
    pop hl
    scf
    ret

;; RDISC_CAT: the RAM disc's files and their lengths, and what is free
RDISC_CAT:
    call rd_ready
    ld hl,rd_m_head
    call lputs
    ld hl,RD_DIR
    ld b,RD_NENT
.e:
    call rd_peek
    or a
    jr z,.next
    push hl
    push bc
    ld c,0
.n:
    call rd_peek
    or a
    jr z,.pad
    call lputc
    inc hl
    inc c
    ld a,c
    cp 12
    jr c,.n
.pad:
    ld a," "
    call lputc
    inc c
    ld a,c
    cp 14
    jr c,.pad
    pop bc
    pop hl
    push hl
    push bc
    ld de,14
    add hl,de
    call rd_peekw
    ex de,hl
    call rd_putnum
    call rd_crlf
    pop bc
    pop hl
.next:
    ld de,RD_ESIZE
    add hl,de
    djnz .e
    call rd_crlf
    call rd_used
    ex de,hl
    ld hl,0
    or a
    sbc hl,de
    call rd_putnum
    ld hl,rd_m_free
    jp lputs

rd_crlf:
    ld a,13
    call lputc
    ld a,10
    jp lputc

;; rd_putnum: HL = an unsigned number, printed in decimal
rd_putnum:
    ld c,0                      ; no digit yet
    ld de,-10000
    call .d
    ld de,-1000
    call .d
    ld de,-100
    call .d
    ld de,-10
    call .d
    ld a,l
    add a,"0"
    jp lputc
.d:
    ld a,"0"-1
.l:
    inc a
    add hl,de
    jr c,.l
    sbc hl,de
    cp "0"
    jr nz,.p
    bit 0,c
    ret z                       ; a leading zero
.p:
    set 0,c
    jp lputc

;; (delete-file "name") -> T. On M:, from the RAM disc; else through the
;; disc ROM's |ERA (which says itself if there is no such file).
;@ DELETE-FILE 1 1 lf_delete_file
lf_delete_file:
    push hl
    call fl_name
    call RDISC_IS
    jr nz,.disc
    call rd_name
    call rd_ready
    call rd_find
    jr nc,.none
    call rd_delete
    pop hl
    jp lt
.none:
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
    jr nc,.none                 ; no disc ROM
    ld ix,RD_PARM
    ld a,1
    call KL_FAR_PCHL
    pop hl
    jp lt
