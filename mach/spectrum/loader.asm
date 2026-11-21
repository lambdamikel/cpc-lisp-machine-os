;; CPC Lisp -- the Spectrum's loader: the code block of LISP.TAP
;; (tools/spectrum/mktap.py), which its BASIC line loads at LOADER and
;; starts. It looks at the machine -- a 128K one with its paging free (128
;; BASIC or the Loader, not 48 BASIC, which locks it), a DivMMC with 128 KB
;; of RAM -- then reads the tape's next blocks with the ROM's LD-BYTES
;; (esxDOS's tape emulation, or a real tape): the machine pages into the
;; DivMMC's pages MP_A and MP_B (through &8000), the resident part at
;; IM2TAB, the six images into their banks; and starts it all (RS_BOOT).
;; If something is wrong it says so and goes back to BASIC.

    include "firmware.asm"
    include "jumps.asm"
    include "memmap.asm"

LOADER      equ #7000           ; (in the symbols' and cells' RAM: free
                                ;   until the Lisp starts)
LD_BYTES    equ #0556           ; 48 BASIC's: A = the flag, IX = where, DE
                                ;   = how many, carry -> carry if it loaded
CHAN_OPEN   equ #1601           ; A = a stream
BUF         equ #8000           ; the machine pages on their way

    org LOADER
start:
    ld (ret_sp),sp
    ld sp,LOADER
    ld a,2
    call CHAN_OPEN              ; print to the screen
    ld hl,m_hello
    call ld_print
    ; the paging: banks 1 and 3 at &C000 must differ (48 BASIC locks it)
    ld a,(BANK_M)               ; (BASIC's USR runs in 48 BASIC's ROM:
    or PG_7FFD                  ;   whatever its variables say, so
    ld (ret_7ffd),a             ;   esxDOS's 48 BASIC leaves them 0)
    ld a,(BANK678)
    or PG_1FFD
    ld (ret_1ffd),a
    di
    ld bc,P_7FFD
    ld a,PG_7FFD+1
    out (c),a
    ld a,#A5
    ld (#C000),a
    ld a,PG_7FFD+3
    out (c),a
    ld a,#5A
    ld (#C000),a
    ld a,PG_7FFD+1
    out (c),a
    ld a,(#C000)
    cp #A5
    ld hl,m_locked
    jp nz,ld_fail
    ; which machine: with &7FFD's bit 4 set (it is) and &1FFD's bit 2, a
    ; +2A shows 48 BASIC; a 128 takes the write to &1FFD for one to &7FFD
    ; (bit 4 clear: its ROM 0), and shows 48 BASIC as &7FFD's bit 4 is set
    ; again. (Its ROM 1 says nothing: esxDOS starts a +2A in 48 BASIC
    ; with &1FFD's bit 2 set already.)
    xor a
    ld (model),a
    ld a,PG_1FFD
    ld bc,P_1FFD
    out (c),a
    call is48
    jr z,.plus                  ; a +2A
    ld a,1
    ld (model),a                ; a 128 (ld_fail then leaves &1FFD alone)
    ld a,PG_7FFD+1
    ld b,P_7FFD >> 8
    out (c),a
    call is48
    ld hl,m_rom
    jp nz,ld_fail
.plus:
    ; a DivMMC with 128 KB of RAM: page 14 is RAM, and not page 6 again
    ; (on a 64 KB one it is); the bytes there put back after
    ld a,E3_A
    out (P_DIVMMC),a
    ld hl,MPAGE
    ld c,(hl)
    ld (hl),#A5
    ld a,(hl)
    ld (hl),c
    cp #A5
    ld hl,m_nodiv
    jp nz,ld_fail
    ld a,CONMEM+6
    out (P_DIVMMC),a
    ld hl,MPAGE
    ld c,(hl)                   ; page 6's byte
    ld (hl),#5A
    ld a,E3_A
    out (P_DIVMMC),a
    ld a,(hl)                   ; page 14's
    ld b,a
    ld a,CONMEM+6
    out (P_DIVMMC),a
    ld (hl),c
    xor a
    out (P_DIVMMC),a
    ld a,b
    cp #5A
    ld hl,m_small
    jp z,ld_fail
    ei
    ; the machine pages, through &8000
    ld hl,m_loading
    call ld_print
    ld ix,BUF
    ld de,16384
    call block
    di
    ld a,E3_A
    out (P_DIVMMC),a
    ld hl,BUF
    ld de,MPAGE
    ld bc,8192
    ldir
    ld a,E3_B
    out (P_DIVMMC),a
    ld de,MPAGE
    ld bc,8192
    ldir
    xor a
    out (P_DIVMMC),a
    ei
    ; the images, each into its bank
    ld hl,banks
.img:
    ld a,(hl)
    cp #FF
    jr z,.res
    inc hl
    push hl
    or PG_7FFD
    ld bc,P_7FFD
    out (c),a
    ld ix,#C000
    ld de,16384
    call block
    pop hl
    jr .img
.res:
    ; the resident part, last: it lies over BASIC's program
    ld ix,IM2TAB
    ld de,RES_LEN
    call block
    ld a,(model)
    ld (RS_MODEL),a
    jp RS_BOOT

;; block: IX = where, DE = how many -> the tape's next block there (a
;; headerless one, flag &FF), a dot on the screen; if it fails, back to
;; BASIC
block:
    ld a,#FF
    scf
    call LD_BYTES
    ld hl,m_tape
    jr nc,ld_fail
    ld a,'.'
    rst #10
    ret

;; is48: -> Z if the ROM at &0000 is 48 BASIC's (DI, XOR A, LD DE,&FFFF)
is48:
    ld hl,0
    ld a,(hl)
    cp #F3
    ret nz
    inc hl
    ld a,(hl)
    cp #AF
    ret nz
    inc hl
    ld a,(hl)
    cp #11
    ret nz
    inc hl
    ld a,(hl)
    and (hl)
    inc hl
    and (hl)
    cp #FF
    ret

;; ld_fail: HL = a message -> it shown, the paging as BASIC had it, back to it
ld_fail:
    di
    push hl
    ld a,(ret_7ffd)
    ld bc,P_7FFD
    out (c),a
    ld a,(model)
    or a
    jr nz,.p
    ld a,(ret_1ffd)
    ld b,P_1FFD >> 8
    out (c),a
.p:
    xor a
    out (P_DIVMMC),a
    pop hl
    ei
    call ld_print
    ld sp,(ret_sp)
    ret

;; ld_print: HL = a message ending in 0 -> on the screen (RST 10)
ld_print:
    ld a,(hl)
    or a
    ret z
    rst #10
    inc hl
    jr ld_print

ret_sp:     dw 0
ret_7ffd:   db 0
ret_1ffd:   db 0
model:      db 0
banks:      db 0,1,3,4,6,7,#FF  ; the core, parts 0-3, the VM: the tape's order
m_hello:    db "CPC Lisp for the ZX Spectrum",13,0
m_loading:  db "Loading",0
m_locked:   db "The paging is locked: start it",13
            db "from 128 BASIC or the Loader,",13,"not 48 BASIC.",13,0
m_rom:      db "This is no 128K Spectrum.",13,0
m_nodiv:    db "It needs a DivMMC (or DivIDE)",13,"with its RAM.",13,0
m_small:    db "It needs 128 KB of RAM on the",13,"DivMMC.",13,0
m_tape:     db 13,"Tape loading error.",13,0
ld_end:
    assert ld_end <= BUF
