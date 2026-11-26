;; CPC Lisp -- the PCW's machine page B: files, floats, sound, the RAM
;; disc (page.asm includes this, after page A). Assembled for &C000, where
;; the resident part maps it; in LISPM.ROM after page A. Its routines'
;; entries in the table (MTAB, in page A) have bit 14 clear: each name
;; m_... is its routine's address - &4000.

PB_DATA     equ #F800           ; this page's data: the sound's queues
PB_DATA_END equ #10000

    org #C000,#8000
    jp b_init                   ; rs_boot calls this once
    assert $ == PB_TICK
    jp b_tick                   ; the interrupt: the sound
    db "PCW MACHINE PAGE B",0

;; b_init: from rs_boot, once
b_init:
    call f_init
    call ay_init
    jp s_init

;; ---------------------------------------------------------------------------
;; FILES: the drives (fdc.asm), CP/M's file system (files.asm), the RAM
;; disc (rdisc.asm)

    include "fdc.asm"
    include "files.asm"
    include "rdisc.asm"

;; ---------------------------------------------------------------------------
;; SOUND: sound.asm (the Spectrum's: the CPC firmware's sound manager) on a
;; DKTronics sound generator's AY, if there is one -- and on the beeper,
;; which sounds while any channel has a note (one pitch: its own)

    include "sound.asm"

ay_regs:    defs 16,0           ; what the AY was told: the beeper's view
ay_beep:    db 0                ; 1: the beeper is on
ay_have:    db 0                ; 1: a DKTronics AY answers -- notes leave the beeper alone

;; ay_init: the beeper off; is there an AY? Register 0 (8 bits) is written
;; twice and read back through &A9 -- without the card the port says &FF
;; (MiSTer's PCW core) or nothing of the kind. With the AY there, the
;; beeper (one loud pitch of its own) stays out of the notes: the bell keeps
;; it. ay_pcw asks again at every write of an 8-bit register (0, 2, 4, 7):
;; MiSTer's card can be switched on and off while Lisp runs (Mike did).
ay_init:
    xor a
    ld (ay_beep),a
    ld (ay_have),a
    ld a,SC_BEEPOFF
    out (P_SYS),a
    xor a
    out (P_AYREG),a
    ld a,#5A
    out (P_AYDAT),a
    in a,(P_AYRD)
    cp #5A
    jr nz,.none
    ld a,#A5
    out (P_AYDAT),a
    in a,(P_AYRD)
    cp #A5
    jr nz,.none
    ld a,1
    ld (ay_have),a
.none:
    xor a
    out (P_AYDAT),a             ; register 0 back to 0, as ay_regs has it
    ret

;; ay_pcw: A = an AY register, C = a value -> to the DKTronics AY (ports
;; &AA, &AB) and noted; an 8-bit register read back (ay_have: the AY is
;; there -- not for &FF, the port's answer without the card); with no AY
;; the beeper on if a channel's tone is on (the mixer's bits 0-2 clear)
;; with a volume, else off. B kept; AF lost.
ay_pcw:
    and 15
    out (P_AYREG),a
    push af
    ld a,c
    out (P_AYDAT),a
    pop af
    push bc
    push hl
    ld b,a
    cp 7
    jr z,.chk
    cp 5
    jr nc,.nochk
    rra
    jr c,.nochk                 ; 1, 3: four bits
.chk:
    ld a,c
    inc a
    jr z,.nochk                 ; &FF: says nothing
    in a,(P_AYRD)
    cp c
    ld a,0
    jr nz,.hv
    inc a
.hv:
    ld (ay_have),a
.nochk:
    ld a,b
    ld hl,ay_regs
    add a,l
    ld l,a
    jr nc,.n
    inc h
.n:
    ld (hl),c
    ld c,0                      ; C: the beeper wanted
    ld a,(ay_have)
    or a
    jr nz,.set                  ; the AY sounds: the beeper off
    ld a,(ay_regs+7)            ; the mixer: a 0 bit is a tone on
    cpl
    ld b,a
    ld hl,ay_regs+8
    bit 0,b
    jr z,.b
    ld a,(hl)
    and 15
    jr nz,.on
.b:
    inc hl
    bit 1,b
    jr z,.c
    ld a,(hl)
    and 15
    jr nz,.on
.c:
    inc hl
    bit 2,b
    jr z,.set
    ld a,(hl)
    and 15
    jr z,.set
.on:
    inc c
.set:
    ld a,(ay_beep)
    cp c
    jr z,.same
    ld a,c
    ld (ay_beep),a
    or a
    ld a,SC_BEEPON
    jr nz,.out
    ld a,SC_BEEPOFF
.out:
    out (P_SYS),a
.same:
    pop hl
    pop bc
    ret

;; ---------------------------------------------------------------------------
;; FLOATS: fppcw.asm (fpfun.asm the functions)

    include "fppcw.asm"

page_b_end:
    print "machine page B: ",page_b_end-#C000," bytes"
    assert page_b_end <= PB_DATA

;; the names in the table: page B's routines, bit 14 clear
m_file_iopen    equ b_file_iopen-#4000
m_file_iclose   equ b_file_iclose-#4000
m_file_iabandon equ b_file_iabandon-#4000
m_file_getc     equ b_file_getc-#4000
m_file_oopen    equ b_file_oopen-#4000
m_file_oclose   equ b_file_oclose-#4000
m_file_oabandon equ b_file_oabandon-#4000
m_file_putc     equ b_file_putc-#4000
m_file_cat      equ b_file_cat-#4000
m_fp_move       equ b_fp_move-#4000
m_fp_int2r      equ b_fp_int2r-#4000
m_fp_bin2r      equ b_fp_bin2r-#4000
m_fp_r2int      equ b_fp_r2int-#4000
m_fp_r2bin      equ b_fp_r2bin-#4000
m_fp_fix        equ b_fp_fix-#4000
m_fp_int        equ b_fp_int-#4000
m_fp_exp10      equ b_fp_exp10-#4000
m_fp_add        equ b_fp_add-#4000
m_fp_rsub       equ b_fp_rsub-#4000
m_fp_mul        equ b_fp_mul-#4000
m_fp_div        equ b_fp_div-#4000
m_fp_cmp        equ b_fp_cmp-#4000
m_fp_neg        equ b_fp_neg-#4000
m_fp_sgn        equ b_fp_sgn-#4000
m_fp_angle      equ b_fp_angle-#4000
m_fp_pi         equ b_fp_pi-#4000
m_fp_sqr        equ b_fp_sqr-#4000
m_fp_pow        equ b_fp_pow-#4000
m_fp_log        equ b_fp_log-#4000
m_fp_exp        equ b_fp_exp-#4000
m_fp_sin        equ b_fp_sin-#4000
m_fp_cos        equ b_fp_cos-#4000
m_fp_tan        equ b_fp_tan-#4000
m_fp_atn        equ b_fp_atn-#4000
m_m_rdin        equ b_m_rdin-#4000
m_m_rdout       equ b_m_rdout-#4000
m_m_rdcat       equ b_m_rdcat-#4000
m_m_delete      equ b_m_delete-#4000
m_m_drive       equ b_m_drive-#4000
m_snd_queue     equ b_snd_queue-#4000
m_m_sndcheck    equ b_m_sndcheck-#4000
m_m_sndrel      equ b_m_sndrel-#4000
m_m_sndhold     equ b_m_sndhold-#4000
m_m_sndcont     equ b_m_sndcont-#4000
m_m_ampenv      equ b_m_ampenv-#4000
m_m_toneenv     equ b_m_toneenv-#4000

    defs #10000-$,0
