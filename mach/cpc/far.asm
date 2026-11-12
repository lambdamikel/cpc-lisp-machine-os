;; CPC Lisp -- the far arrays' way into the RAM disc (library part 1:
;; lib/farray.asm includes this): the directory's layout, as
;; mach/cpc/ramdisc.asm keeps it in the second 64 KB, and fa_xfer.

FA_DIR0     equ 16              ; entry 0
FA_ESIZE    equ 16              ; [name 12, 0-padded][start 2][length 2]
FA_NENT     equ 63
FA_USED     equ -1              ; (in use: its name is not empty)
FA_NAME     equ 0
FA_PAD      equ 0
FA_START    equ 12
FA_LEN      equ 14
FA_W        equ 2               ; bytes in a start and a length

;; fa_xfer: A = 0: BC bytes from the disc at FA_OFF to RAM at HL; 1: from
;; RAM at HL to the disc. FA_OFF moves on. The RAM is above &8000: each
;; piece within a 16 KB bank is one LDIR, the bank seen at &4000
;; (configurations C4-C7) meanwhile, the main RAM put back (C0) after.
fa_xfer:
    ld (FA_X),a
.l:
    ld a,b
    or c
    ret z
    push bc                     ; what is left to do
    push hl                     ; the RAM
    ld de,(FA_OFF)
    ld a,d
    or #C0
    ld h,a
    ld l,e
    xor a
    sub l
    ld l,a
    sbc a,a
    sub h
    ld h,a                      ; HL = what is left of its bank
    push hl
    or a
    sbc hl,bc
    pop hl
    jr c,.k                     ; less than wanted: that much
    ld h,b
    ld l,c
.k:
    ld b,h
    ld c,l                      ; BC = this piece
    ld a,d
    rlca
    rlca
    and 3
    or #C4
    ld (FA_X+1),a               ; its bank's configuration
    ld a,d
    and #3F
    or #40
    ld d,a                      ; DE = where &4000-&7FFF shows it
    pop hl                      ; the RAM
    push bc
    ld a,(FA_X)
    or a
    jr nz,.go
    ex de,hl                    ; from the disc: HL there, DE the RAM
.go:
    push bc
    ld a,(FA_X+1)
    ld b,#7F
    ld c,a
    out (c),c
    pop bc
    ldir
    ld bc,#7FC0
    out (c),c
    ld a,(FA_X)
    or a
    jr nz,.on
    ex de,hl                    ; HL = the RAM again
.on:
    pop bc                      ; this piece
    push hl
    ld hl,(FA_OFF)
    add hl,bc
    ld (FA_OFF),hl
    pop hl
    ex (sp),hl                  ; HL = what was left, the RAM kept
    or a
    sbc hl,bc
    ld b,h
    ld c,l
    pop hl
    jr .l
