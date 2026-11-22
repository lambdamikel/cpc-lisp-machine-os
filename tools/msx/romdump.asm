; ROMDUMP.COM -- saves an MSX's main ROM (the BIOS and BASIC, 32 KB at
; &0000-&7FFF of the slot EXPTBL names) to MAINROM.BIN in the current
; folder, for openMSX. Runs under MSX-DOS 2 (Nextor): A>ROMDUMP
;
;   rasm tools/msx/romdump.asm -o build/msx/romdump  ->  romdump.bin = ROMDUMP.COM
;
; The ROM is the machine maker's: a dump is for the emulator on the same
; desk, never for this repository.

BDOS    equ #0005
RDSLT   equ #000C       ; MSX-DOS's page 0: A = slot, HL = address -> A
EXPTBL  equ #FCC1       ; the main ROM's slot (bit 7: expanded, then its subslot)

_STROUT equ #09
_CREATE equ #44
_CLOSE  equ #45
_WRITE  equ #49
_TERM0  equ #00

CHUNKSZ equ 4096

        org #0100

start:  ld de,m_hello
        ld c,_STROUT
        call BDOS
        ld a,(EXPTBL)           ; "slot &xx"
        call hexout
        ld de,m_crlf
        ld c,_STROUT
        call BDOS

        ld de,fname             ; a new MAINROM.BIN (or over the old one)
        xor a
        ld b,a
        ld c,_CREATE
        call BDOS
        or a
        jr nz,failed
        ld a,b
        ld (handle),a

        ld hl,0                 ; HL = the next ROM address throughout
chunk:  ld de,buf
        ld bc,CHUNKSZ
byte:   push bc
        push de
        push hl
        ld a,(EXPTBL)
        call RDSLT              ; takes AF, BC, DE; leaves the interrupts off
        ei
        pop hl
        pop de
        pop bc
        ld (de),a
        inc hl
        inc de
        dec bc
        ld a,b
        or c
        jr nz,byte

        push hl
        ld a,(handle)
        ld b,a
        ld de,buf
        ld hl,CHUNKSZ
        ld c,_WRITE
        call BDOS
        pop hl
        or a
        jr nz,failed
        ld a,h                  ; up to &7FFF
        cp #80
        jr c,chunk

        ld a,(handle)
        ld b,a
        ld c,_CLOSE
        call BDOS
        or a
        jr nz,failed
        ld de,m_ok
        jr bye
failed: ld de,m_fail
bye:    ld c,_STROUT
        call BDOS
        ld c,_TERM0
        jp BDOS

hexout: push af                 ; A as two hex digits, through _STROUT
        rrca
        rrca
        rrca
        rrca
        call nibble
        pop af
nibble: and #0F
        add a,"0"
        cp "9"+1
        jr c,.dig
        add a,"A"-"9"-1
.dig:   ld (m_hex),a
        ld de,m_hex
        ld c,_STROUT
        jp BDOS

m_hello: db "ROMDUMP: the main ROM, slot &$"
m_crlf:  db 13,10,"$"
m_ok:    db "MAINROM.BIN written, 32768 bytes",13,10,"$"
m_fail:  db "could not write MAINROM.BIN",13,10,"$"
m_hex:   db "0$"
fname:   db "MAINROM.BIN",0
handle:  db 0

buf     equ #1000
        assert $ < buf
