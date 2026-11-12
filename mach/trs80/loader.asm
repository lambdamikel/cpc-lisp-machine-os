;; CPC Lisp -- the TRS-80's loader, LISP/CMD. Run from LDOS: it loads the
;; six images and the machine page into their X-MEM/80 pages, lets the
;; machine page set itself up, and starts the core. The resident part
;; (resident.asm) comes in the same /CMD file, at RES.
;;
;; The images are compressed (tools/trs80/lz.py has the format), so that
;; they fit on one single-density disc: each is read into page 1 at &8000
;; -- the heap's, free until the Lisp starts -- and decoded into its page
;; at &C000.

    include "firmware.asm"
    include "jumps.asm"
    include "memmap.asm"

LZ_BITS     equ 5               ; (as tools/trs80/lz.py has it)

    org #7000
start:
    ld hl,m_hello
    call L_DSPLY
    ld a,HEAPPAGE
    out (XM_LO),a               ; &8000-&BFFF: the heap's, for good
    ; X-MEM/80, in its X-MEM mode? Then two pages at &C000 differ
    ld a,COREPAGE
    out (XM_HI),a
    ld a,#A5
    ld (#C000),a
    ld a,COREPAGE+1
    out (XM_HI),a
    ld a,#5A
    ld (#C000),a
    ld a,COREPAGE
    out (XM_HI),a
    ld a,(#C000)
    cp #A5
    jr z,.xmem
    ld hl,m_noxmem
    call L_DSPLY
    jp L_EXIT
.xmem:
    ld ix,images
.next:
    ld l,(ix+0)
    ld h,(ix+1)
    ld a,h
    or l
    jr z,.done
    ld a,(ix+2)
    ld (ld_page),a
    push ix
    call load_file
    pop ix
    inc ix
    inc ix
    inc ix
    jr .next
.done:
    ld a,MACHPAGE
    out (XM_HI),a
    call #C000                  ; the machine page sets itself up
    ld a,COREPAGE
    out (XM_HI),a
    jp #C006                    ; the core's start

;; load_file: HL = a name ending in 13 -> the file decoded into page
;; (ld_page) from &C000
load_file:
    push hl
    call L_DSPLY
    pop hl
    ld de,fcb
    call L_FSPEC
    jp nz,ld_bad
    ld hl,iobuf
    ld de,fcb
    ld b,0
    call L_OPEN
    jp nz,ld_bad
    ld hl,#8000
    ld (ld_dest),hl
.rec:
    ld de,fcb
    call L_READ
    jr nz,.end
    ld hl,iobuf
    ld de,(ld_dest)
    ld bc,256
    ldir
    ld (ld_dest),de
    ld a,d
    cp #C0
    jr c,.rec                   ; up to 64 records
.end:
    ld de,fcb
    call L_CLOSE
    ld a,(ld_page)
    out (XM_HI),a
    ld hl,(#8000)               ; how long it is decoded
    ld de,#C000
    add hl,de
    ld (lz_end),hl
    ld hl,#8002
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
ld_bad:
    ld hl,m_nofile
    call L_DSPLY
    jp L_EXIT

ld_page:    db 0
ld_dest:    dw 0
images:
    dw n0 : db COREPAGE
    dw n1 : db COREPAGE+1
    dw n2 : db COREPAGE+2
    dw n3 : db COREPAGE+3
    dw n4 : db COREPAGE+4
    dw n5 : db COREPAGE+5
    dw nm : db MACHPAGE
    dw 0
n0: db "LISP0/IMG",13
n1: db "LISP1/IMG",13
n2: db "LISP2/IMG",13
n3: db "LISP3/IMG",13
n4: db "LISP4/IMG",13
n5: db "LISP5/IMG",13
nm: db "LISPM/IMG",13
m_hello:  db "CPC Lisp for the TRS-80 with X-MEM/80: loading",13
m_nofile: db "Cannot load it: is the Lisp disc in a drive?",13
m_noxmem: db "No X-MEM/80 -- or its jumper is set to SuperMem mode",13
fcb:      defs 50,0
iobuf:    defs 256,0
loader_end:
    assert loader_end <= #8000
