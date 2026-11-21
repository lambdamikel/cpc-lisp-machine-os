;; CPC Lisp -- the far arrays' way into the RAM disc (library part 1:
;; lib/farray.asm includes this): the directory's layout, as
;; mach/spectrum/rdisc.asm keeps it in the DivMMC's pages, and fa_xfer --
;; its rd_xfer again: keep them in step.

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
FX_PAGE     equ FA_X+7          ;   the DivMMC's page

;; fa_xfer: A = 0: BC bytes from the disc at FA_OFF to RAM at HL; 1: from
;; RAM at HL to the disc. Split where a page ends; FA_OFF moves on. Each
;; piece is one RS_XFER (the resident part): the page mapped at &2000 for
;; an LDIR, then nothing there again. The RAM is above &4000.
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
    and #1F
    ld d,a
    ld e,l                      ; DE = where in the page
    ld a,(FA_OFF+2)             ; the page: the offset's bits 13-23 --
    ld c,h                      ;   pages 5-13, then 16 on (rdisc.asm)
    sla c
    rla
    sla c
    rla
    sla c
    rla
    cp 9
    jr nc,.hi
    add a,5
    jr .p
.hi:
    add a,16-9
.p:
    ld (FX_PAGE),a
    ld hl,#2000
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
    ld hl,MPAGE
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
