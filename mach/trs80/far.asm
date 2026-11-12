;; CPC Lisp -- the far arrays' way into the RAM disc (library part 1:
;; lib/farray.asm includes this): the directory's layout, as
;; mach/trs80/rdisc80.asm keeps it in X-MEM/80's pages 9-31, and fa_xfer
;; -- its rd_xfer again: keep them in step.

FA_DIR0     equ 32              ; entry 0
FA_ESIZE    equ 32              ; [1 in use][name 12, blanks after][start 3]
FA_NENT     equ 31              ;   [length 3]
FA_USED     equ 0
FA_NAME     equ 1
FA_PAD      equ ' '
FA_START    equ 13
FA_LEN      equ 16
FA_W        equ 3
FA_PAGE0    equ 9               ; rdisc80.asm's RD_PAGE0

FX_DIR      equ FA_X            ; fa_xfer's own: the direction,
FX_RAM      equ FA_X+1          ;   the RAM's side,
FX_N        equ FA_X+3          ;   bytes left,
FX_K        equ FA_X+5          ;   bytes this time,
FX_PAGE     equ FA_X+7          ;   the page

;; fa_xfer: A = 0: BC bytes from the disc at FA_OFF to RAM at HL; 1: from
;; RAM at HL to the disc. Split where a page ends; FA_OFF moves on. Each
;; piece is one RS_XFER (resident.asm): the page mapped at &C000 for an
;; LDIR, then this one put back. The RAM is below &C000.
fa_xfer:
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
    ld e,l                      ; DE = where in the page
    ld a,h
    rlca
    rlca
    and 3
    ld c,a
    ld a,(FA_OFF+2)
    add a,a
    add a,a
    or c
    add a,FA_PAGE0
    ld (FX_PAGE),a
    ld hl,#4000
    or a
    sbc hl,de                   ; HL = what is left of the page
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
    ld hl,#C000
    add hl,de
    ex de,hl                    ; DE = the page's side
    ld hl,(FX_RAM)
    ld a,(FX_DIR)
    or a
    jr nz,.go
    ex de,hl                    ; from the page: HL there, DE the RAM
.go:
    ld bc,(FX_K)
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
