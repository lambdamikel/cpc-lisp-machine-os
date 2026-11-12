;; CPC Lisp -- the plain 6128's loader, LISP.BIN: RUN"LISP from BASIC.
;;
;; It finds the second 64 KB, loads the five images LISP0.IMG-LISP4.IMG
;; (the core and library parts 0-3; no compiler) -- each into its block,
;; mapped at &4000 while AMSDOS reads it straight there: the core into
;; block 7 (C7), parts 0-2 into blocks 4-6 (C4-C6), part 3 into the main
;; RAM's own &4000 (C0) -- puts the resident part (mach/cpc512's
;; resident.asm, carried here) at RESIDENT, turns the ROMs off, maps block
;; 7 at &C000 (C1) and starts the core, as |LISP would. Without the second
;; 64 KB it says so and goes back to BASIC. BASIC's RUN of a binary file
;; restarts the firmware first, so it walks the ROMs itself.

    include "fwreal.asm"
    include "jumps.asm"

KL_U_ROM_DISABLE equ #B903
KL_L_ROM_DISABLE equ #B909
CAS_IN_DIRECT    equ #BC83
NIMAGES          equ 5
BUF              equ #8800      ; AMSDOS's 2 KB, while a file is read

    org #8000
start:
    ld de,#0040                 ; RUN of a binary file restarts the firmware:
    ld hl,#ABFF                 ;   the background ROMs (the disc's) are
    call KL_ROM_WALK            ;   ours to start, as a foreground ROM would
    ld de,RESIDENT_END-1        ; their workspace from the top down: it must
    or a                        ;   leave the resident part room
    sbc hl,de
    ld hl,m_rom
    jp c,.say
    ld hl,m_hello
    call puts
    ; the second 64 KB: a byte written at &4000 in C4 must not land in the
    ; main RAM (on a 464 without an expansion, C4 is C0)
    ld a,#5A
    ld (#4000),a
    ld bc,#7FC4
    out (c),c
    ld a,#A5
    ld (#4000),a
    ld c,#C0
    out (c),c
    ld a,(#4000)
    cp #5A
    jp nz,.none
    ld c,#C4
    out (c),c
    ld a,(#4000)
    ld c,#C0
    out (c),c
    cp #A5
    jp nz,.none
    ; the images, each into its block
    ld e,0
.load:
    ld a,e
    add a,"0"
    ld (n_img+4),a
    ld hl,n_img
    call puts
    ld a,32
    call TXT_OUTPUT
    push de
    ld hl,cfgs
    ld d,0
    add hl,de
    ld c,(hl)
    ld b,#7F
    out (c),c                   ; its block at &4000
    ld b,n_end-n_img
    ld hl,n_img
    ld de,BUF
    call CAS_IN_OPEN
    jr nc,.nofile
    ld hl,#4000
    call CAS_IN_DIRECT
    push af
    call CAS_IN_CLOSE
    pop af
    pop de
    jr nc,.bad
    inc e
    ld a,e
    cp NIMAGES
    jr c,.load
    call map_main
    ld a,13
    call TXT_OUTPUT
    ld a,10
    call TXT_OUTPUT
    ; the resident part, and the RAM disc's state cleared: no banks for it
    ld hl,res_bin
    ld de,RESIDENT
    ld bc,res_end-res_bin
    ldir
    ld hl,RS_RD
    ld b,RD_STATELEN
.clr:
    ld (hl),0
    inc hl
    djnz .clr
    ; the ROMs off: the code at &C000 and the low tables are RAM
    call KL_U_ROM_DISABLE
    call KL_L_ROM_DISABLE
    di
    ld bc,#7FC1                 ; block 7 at &C000: the core
    out (c),c
    ei
    jp #C006
.nofile:
    pop de
.bad:
    call map_main
    ld hl,m_nofile
    jr .say
.none:
    call map_main
    ld hl,m_none
.say:
    call puts
    ret

map_main:
    ld bc,#7FC0
    out (c),c
    ret

puts:
    ld a,(hl)
    or a
    ret z
    call TXT_OUTPUT
    inc hl
    jr puts

cfgs:     db #C7,#C4,#C5,#C6,#C0 ; each image's configuration: its block at &4000
m_hello:  db "CPC Lisp for the 6128: loading",13,10,0
m_none:   db 13,10,"No second 64 KB found: CPC Lisp needs a 6128,",13,10
          db "or a CPC with a 64 KB expansion.",13,10,0
m_nofile: db 13,10,"Cannot load it: is the CPC Lisp disc in?",13,10,0
m_rom:    db "Too many ROMs: their workspace is where CPC Lisp's",13,10
          db "resident part goes, under &A6F0.",13,10,0
n_img:    db "LISP0.IMG"
n_end:    db 0

res_bin:
    incbin "resident.bin"
res_end:
    assert res_end < BUF
