;; CPC Lisp -- the 512K CPC's loader, LISP.BIN: RUN"LISP from BASIC.
;;
;; It finds the expansion, loads the six images LISP0.IMG-LISP5.IMG into
;; block 3 of banks 0-5 -- each bank's block mapped at &4000 in
;; configuration C7 while AMSDOS reads it straight there -- puts the
;; resident part (resident.asm, carried here) at RESIDENT, turns the ROMs
;; off, maps bank 0 at &C000 (C1) and starts the core, as |LISP would.
;; Without the expansion it says so and goes back to BASIC. BASIC's RUN of
;; a binary file restarts the firmware first, so it walks the ROMs itself.

    include "fwreal.asm"
    include "jumps.asm"

KL_U_ROM_DISABLE equ #B903
KL_L_ROM_DISABLE equ #B909
CAS_IN_DIRECT    equ #BC83
NIMAGES          equ 6
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
    ; the expansion: a mark in block 3 of each bank, then each read back
    ; -- the byte there kept and put back, for banks 6 and 7 hold the RAM
    ; disc's files. The banks that answer, from 0, are counted.
    ld a,#5A
    ld (#4000),a                ; (the main RAM's own, to see it untouched)
    ld e,0
.save:
    call map_bank
    ld a,(#4000)
    ld hl,saved
    ld d,0
    add hl,de
    ld (hl),a
    inc e
    ld a,e
    cp 8
    jr c,.save
    ld e,0
.mark:
    call map_bank
    ld a,e
    or #A0
    ld (#4000),a
    inc e
    ld a,e
    cp 8
    jr c,.mark
    ld e,0
.check:
    call map_bank
    ld a,e
    or #A0
    ld hl,#4000
    cp (hl)
    jr nz,.counted
    inc e
    ld a,e
    cp 8
    jr c,.check
.counted:
    ld a,e
    ld (nbanks),a
    ld e,0
.restore:
    call map_bank
    ld hl,saved
    ld d,0
    add hl,de
    ld a,(hl)
    ld (#4000),a
    inc e
    ld a,e
    cp 8
    jr c,.restore
    call map_main
    ld a,(nbanks)
    cp NIMAGES
    jp c,.none                  ; fewer than six banks
    ld a,(#4000)
    cp #5A
    jp nz,.none                 ; the writes went to the main RAM
    ; the images, each into its bank
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
    call map_bank
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
    ; the resident part, and the RAM disc's state cleared
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
    ld a,(nbanks)
    ld (RD_NBANKS),a
    ; the ROMs off: the code at &C000 and the low tables are RAM
    call KL_U_ROM_DISABLE
    call KL_L_ROM_DISABLE
    di
    ld bc,#7FC1                 ; bank 0 at &C000: the core
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

;; map_bank: E = a bank -> its block 3 at &4000 (configuration C7). BC lost.
map_bank:
    ld a,e
    add a,a
    add a,a
    add a,a
    or #C7
    ld b,#7F
    ld c,a
    out (c),c
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

m_hello:  db "CPC Lisp for the 512K expansion: loading",13,10,0
m_none:   db 13,10,"No 512K expansion found: CPC Lisp needs",13,10
          db "banks 0-5 of a DK'tronics-type expansion.",13,10,0
m_nofile: db 13,10,"Cannot load it: is the CPC Lisp disc in?",13,10,0
m_rom:    db "Too many ROMs: their workspace is where CPC Lisp's",13,10
          db "resident part goes, under &A6F0.",13,10,0
saved:    defs 8,0               ; each bank's byte under the mark
nbanks:   db 0
n_img:    db "LISP0.IMG"
n_end:    db 0

res_bin:
    incbin "resident.bin"
res_end:
    assert res_end < BUF
