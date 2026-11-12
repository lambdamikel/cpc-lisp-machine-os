;; CPC Lisp -- the far arrays' way into the RAM disc (library part 1:
;; lib/farray.asm includes this): the directory's layout, as
;; mach/cpc512/ramdisc.asm keeps it in the expansion's free blocks, and
;; fa_xfer -- its rd_xfer and rd_cfg again: keep them in step.

FA_DIR0     equ 32              ; entry 0
FA_ESIZE    equ 32              ; [1 in use][name 12, blanks after][start 3]
FA_NENT     equ 31              ;   [length 3]
FA_USED     equ 0
FA_NAME     equ 1
FA_PAD      equ ' '
FA_START    equ 13
FA_LEN      equ 16
FA_W        equ 3

FX_DIR      equ FA_X            ; fa_xfer's own: the direction,
FX_RAM      equ FA_X+1          ;   the RAM's side,
FX_N        equ FA_X+3          ;   bytes left,
FX_K        equ FA_X+5          ;   bytes this time,
FX_PAGE     equ FA_X+7          ;   the block's configuration

;; fa_xfer: A = 0: BC bytes from the disc at FA_OFF to RAM at HL; 1: from
;; RAM at HL to the disc. Split where a block ends; FA_OFF moves on. Each
;; piece goes through RS_XFER (resident.asm), the block seen at &4000.
fa_xfer:
    if RAMDISC
    ld (FX_DIR),a
    ld (FX_RAM),hl
    ld (FX_N),bc
.l:
    ld hl,(FX_N)
    ld a,h
    or l
    ret z
    ld hl,(FA_OFF)
    ld a,h
    and #3F
    ld d,a
    ld e,l                      ; DE = where in the block
    ld a,h
    rlca
    rlca
    and 3
    ld c,a
    ld a,(FA_OFF+2)
    add a,a
    add a,a
    or c                        ; the 16 KB unit
    call fa_cfg
    ld (FX_PAGE),a
    ld hl,#4000
    or a
    sbc hl,de                   ; HL = what is left of the block
    ld bc,(FX_N)
    push hl
    or a
    sbc hl,bc
    pop hl
    jr c,.k
    ld h,b
    ld l,c
.k:
    ld (FX_K),hl
    ld hl,#4000
    add hl,de
    ex de,hl                    ; DE = the block's side
    ld hl,(FX_RAM)
    ld a,(FX_DIR)
    or a
    jr nz,.go
    ex de,hl                    ; from the block: HL there, DE the RAM
.go:
    ld bc,(FX_K)
    ld a,(FX_DIR)
    cp 1                        ; carry: from the block (HL its side)
    ld a,(FX_PAGE)
    call RS_XFER
    ld bc,(FX_K)
    ld hl,(FX_RAM)
    add hl,bc
    ld (FX_RAM),hl
    ld hl,(FX_N)
    or a
    sbc hl,bc
    ld (FX_N),hl
    ld hl,(FA_OFF)
    add hl,bc
    ld (FA_OFF),hl
    ld a,(FA_OFF+2)
    adc a,0
    ld (FA_OFF+2),a
    jr .l

;; fa_cfg: A = a 16 KB unit of the disc -> A = the configuration showing
;; it at &4000: units 0-17 are blocks 0-2 of banks 0-5, then the four
;; blocks of bank 6, of bank 7. BC lost.
fa_cfg:
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
    ld c,a
    ld a,b
    and 3
.go:
    ld b,a
    ld a,c
    add a,a
    add a,a
    add a,a
    or b
    or #C4
    ret
    else
    ld hl,fa_m_nodisc           ; (a plain 6128: its banks hold the code)
    ld de,UNBOUND
    jp lib_error
fa_m_nodisc: db "no RAM disc",0
    endif
