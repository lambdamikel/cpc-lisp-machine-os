;; CPC Lisp -- the TRS-80's loader, LISP/CMD. Run from LDOS: it loads the
;; six images and the machine page into their X-MEM/80 pages, lets the
;; machine page set itself up, and starts the core. The resident part
;; (resident.asm) comes in the same /CMD file, at RES.

    include "firmware.asm"
    include "jumps.asm"
    include "memmap.asm"

    org #7000
start:
    ld hl,m_hello
    call L_DSPLY
    ld a,HEAPPAGE
    out (XM_LO),a               ; &8000-&BFFF: the heap's, for good
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

;; load_file: HL = a name ending in 13 -> the file in page (ld_page) from
;; &C000
load_file:
    push hl
    call L_DSPLY
    pop hl
    ld de,fcb
    call L_FSPEC
    jr nz,.bad
    ld hl,iobuf
    ld de,fcb
    ld b,0
    call L_OPEN
    jr nz,.bad
    ld a,(ld_page)
    out (XM_HI),a
    ld hl,#C000
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
    or e
    jr nz,.rec                  ; up to 64 records: the page is full
.end:
    ld de,fcb
    call L_CLOSE
    ret
.bad:
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
fcb:      defs 50,0
iobuf:    defs 256,0
loader_end:
    assert loader_end <= #8000
