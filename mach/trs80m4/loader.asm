;; CPC Lisp -- the Model 4's loader, LISP/CMD. Run from LS-DOS 6.3.1 Ready:
;; it checks that the machine has the 128 KB and the room, puts the
;; resident part (resident.asm, in the same /CMD file at RES_IMG) at
;; RESIDENT, loads the five images and the machine page into their slots,
;; adds the clock task, lets the machine page set itself up, and starts
;; the core.
;;
;; The images are compressed (tools/trs80/lz.py has the format): each is
;; read into &4000-&7FFF -- the heap's, free until the Lisp starts -- and
;; decoded into its slot, its bank brought in as the Lisp does (resident's
;; SYS_BANK: OFLAG$ and the port together), the interrupts left on.

    include "firmware.asm"
    include "machine.asm"
    include "memmap.asm"

LZ_BITS     equ 5               ; (as tools/trs80/lz.py has it)
RES_IMG     equ #3800           ; the resident part's image, in LISP/CMD
BUF         equ #4000           ; a compressed image, read in

    org #3000
start:
    ld hl,m_hello
    call dsply
    ; HIGH$ must be &FFFF: bank 0's upper half is the Lisp's
    ld b,0
    ld hl,0
    ld a,SV_HIGH
    rst #28
    ld a,h
    and l
    inc a
    ld hl,m_high
    jp nz,ld_fail
    ; the flags: OPREG's image
    ld a,SV_FLAGS
    rst #28
    push iy
    pop hl
    ld de,F_OFLAG
    add hl,de
    ld (rs_oflag_v),hl
    ld a,(hl)
    and #FF-OP_BANK
    ld (rs_base_v),a
    ; banks 1 and 2, there and free: reserve them
    ld c,1
    call bank_take
    ld c,2
    call bank_take
    ; the resident part in its place
    ld hl,RES_IMG
    ld de,RESIDENT
    ld bc,LINEBUF-RESIDENT
    ldir
    ld hl,(rs_oflag_v)
    ld (RESIDENT+12),hl         ; rs_oflag
    ld a,(rs_base_v)
    ld (RS_BASE),a
    ld (RS_P84),a
    ; both banks answer as two? (a 64 KB machine has no bank 1)
    ld c,4                      ; (slot 4: bank 1)
    call SYS_BANK
    ld a,#A5
    ld (#8000),a
    ld c,6                      ; (slot 6: bank 2)
    call SYS_BANK
    ld a,#5A
    ld (#8000),a
    ld c,4
    call SYS_BANK
    ld a,(#8000)
    push af
    ld c,CORESLOT
    call SYS_BANK
    pop af
    cp #A5
    ld hl,m_banks
    jp nz,ld_fail
    ; the images
    ld ix,images
.next:
    ld l,(ix+0)
    ld h,(ix+1)
    ld a,h
    or l
    jr z,.done
    ld a,(ix+2)
    ld (ld_slot),a
    push ix
    call load_file
    pop ix
    inc ix
    inc ix
    inc ix
    jr .next
.done:
    ; the clock: a medium task slot (8-10) that is free
    ld c,8
.task:
    push bc
    ld a,28                     ; @CKTSK
    rst #28
    pop bc
    jr z,.free
    inc c
    ld a,c
    cp 11
    jr c,.task
    jr .notask                  ; none free: no clock (time stands still)
.free:
    ld a,c
    ld (RS_TSLOT),a
    ld de,RS_TCB
    ld a,SV_ADTSK
    rst #28
.notask:
    ld c,MACHSLOT
    call SYS_BANK
    call #C000                  ; the machine page sets itself up
    ld c,CORESLOT
    call SYS_BANK
    jp #C006                    ; the core's start

;; bank_take: C = a bank -> reserved for the Lisp, or the reason why not
bank_take:
    push bc
    ld b,2                      ; in use?
    ld a,SV_BANK
    rst #28
    pop bc
    ld hl,m_used
    jp nz,ld_fail
    push bc
    ld b,3                      ; reserve it
    ld a,SV_BANK
    rst #28
    pop bc
    ld hl,m_used
    jp nz,ld_fail
    ret

;; load_file: HL = a name ending in 13 -> the file decoded into its slot
;; (ld_slot): at &C000 if the slot is odd, else &8000
load_file:
    push hl
    call dsply
    pop hl
    ld de,fcb
    ld a,SV_FSPEC
    rst #28
    jp nz,ld_bad
    ld hl,iobuf
    ld de,fcb
    ld b,0
    ld a,SV_OPEN
    rst #28
    jp nz,ld_bad
    ld hl,BUF
    ld (ld_dest),hl
.rec:
    ld de,fcb
    ld a,SV_READ
    rst #28
    jr nz,.end
    ld hl,iobuf
    ld de,(ld_dest)
    ld bc,256
    ldir
    ld (ld_dest),de
    ld a,d
    cp #80
    jr c,.rec                   ; up to 64 records
.end:
    ld de,fcb
    ld a,SV_CLOSE
    rst #28
    ld a,(ld_slot)
    ld c,a
    call SYS_BANK
    ld a,(ld_slot)
    ld de,#8000
    rra
    jr nc,.even
    ld d,#C0
.even:
    ld hl,(BUF)                 ; how long it is decoded
    add hl,de
    ld (lz_end),hl
    ld hl,BUF+2
    call lz_dec
    ld c,CORESLOT
    jp SYS_BANK

;; lz_dec: HL = the compressed bytes, DE = where they go, up to (lz_end)
lz_dec:
    ld a,#80                    ; the bits: none left, the marker
    ldi                         ; the first byte, as it is
.loop:
    push hl
    ld hl,(lz_end)
    or a
    sbc hl,de
    pop hl
    ret z
    call lz_bit
    jr c,.match
    ldi                         ; a literal
    jr .loop
.match:
    call lz_gamma
    inc bc
    ld (lz_len),bc              ; the length
    ld c,(hl)
    inc hl
    ld b,0
    bit 7,c
    jr z,.near                  ; 1-128 back
    res 7,c
    repeat LZ_BITS              ; the low bits
    call lz_bit
    rl c
    rl b
    rend
    push hl
    ld hl,128
    add hl,bc
    ld b,h
    ld c,l
    pop hl
.near:
    push hl
    ld h,d
    ld l,e
    scf
    sbc hl,bc                   ; back offset - 1, and one more
    ld bc,(lz_len)
    ldir
    pop hl
    jr .loop
;; lz_bit -> carry, the next bit; A holds them
lz_bit:
    add a,a
    ret nz
    ld a,(hl)
    inc hl
    rla
    ret
;; lz_gamma -> BC, a number from its bits
lz_gamma:
    ld bc,1
.l:
    call lz_bit
    ret c
    call lz_bit
    rl c
    rl b
    jr .l
lz_end:     dw 0
lz_len:     dw 0

dsply:
    ld a,SV_DSPLY
    rst #28
    ret
ld_bad:
    ld hl,m_nofile
ld_fail:
    call dsply
    ld c,1                      ; (the banks let go: an unreserved one
    ld b,1                      ;   is no harm)
    ld a,SV_BANK
    rst #28
    ld c,2
    ld b,1
    ld a,SV_BANK
    rst #28
    ld hl,0
    ld a,SV_EXIT
    rst #28

rs_oflag_v: dw 0
rs_base_v:  db 0
ld_slot:    db 0
ld_dest:    dw 0
images:
    dw n0 : db CORESLOT         ; the core: slot 3, bank 0, &C000
    dw n1 : db 2                ; part 0: bank 0, &8000
    dw n2 : db 4                ; part 1: bank 1, &8000
    dw n3 : db 5                ; part 2: bank 1, &C000
    dw n4 : db 6                ; part 3: bank 2, &8000
    dw nm : db MACHSLOT         ; the machine page: slot 7, bank 2, &C000
    dw 0
n0: db "LISP0/IMG",13
n1: db "LISP1/IMG",13
n2: db "LISP2/IMG",13
n3: db "LISP3/IMG",13
n4: db "LISP4/IMG",13
nm: db "LISPM/IMG",13
m_hello:  db "CPC Lisp for the TRS-80 Model 4: loading",13
m_nofile: db "Cannot load it: is the Lisp disc in a drive?",13
m_high:   db "Something is in high memory (HIGH$ is not X'FFFF'): CPC Lisp needs it all",13
m_used:   db "A 32K bank is in use (by the spooler?): CPC Lisp needs banks 1 and 2",13
m_banks:  db "No 128 KB: CPC Lisp needs the Model 4's 128 KB",13
fcb:      defs 50,0
iobuf:    defs 256,0
loader_end:
    print "loader: ",loader_end-#3000," bytes"
    assert loader_end <= RES_IMG
