;; CPC Lisp -- the PCW's own Lisp functions, in library part 0
;; (lib/gfx.asm includes this).

;; *features* and anything else the machine has in Lisp
;@lisp mach.lsp

;; (quit): the boot program again (the disc in A boots) -- or, under the test
;; harness, out of ZEsarUX
;@ QUIT 0 0 lf_quit
lf_quit:
    jp M_QUIT
;; (ink-mode n): how graphics are drawn: 0 normally, 1 XOR, 2 AND, 3 OR
;@ INK-MODE 1 1 lf_ink_mode
lf_ink_mode:
    push hl
    call lint_hl
    ld a,l
    call M_INKMODE
    pop hl
    ret
;; the sound manager's own: envelopes, rendezvous, holding (as the CPC's,
;; machine page B's sound.asm doing the firmware's work)
;; (envelope n count step pause ...): volume envelope n (1-15), up to five
;; sections of three (BASIC's ENV)
;@ ENVELOPE 4 16 lf_envelope
lf_envelope:
    ld c,0
    jr sd_env
;; (tone-envelope n count step pause ...): tone envelope n (1-15), up to
;; five sections; a negative n repeats it (BASIC's ENT)
;@ TONE-ENVELOPE 4 16 lf_tone_envelope
lf_tone_envelope:
    ld c,1
sd_env:
    NEXTARG
    call lint_de                ; n
    push bc
    ld a,b                      ; the sections: (arguments - 1) / 3
    dec a
    ld b,0
.div:
    sub 3
    jr c,.divd
    inc b
    jr .div
.divd:
    add a,3
    jr nz,.bad                  ; not whole sections
    ld a,b
    ld (TOKBUF),a
    ld a,e                      ; a negative n: repeat
    bit 7,d
    jr z,.pos
    neg
    ld e,a
    ld a,(TOKBUF)
    or #80
    ld (TOKBUF),a
.pos:
    push de                     ; n
    ld de,TOKBUF+1
    ld a,b
    add a,a
    add a,b
    ld b,a                      ; 3 bytes a section
.sec:
    push de
    NEXTARG
    call lint_de
    ld a,e
    pop de
    ld (de),a
    inc de
    djnz .sec
    pop de
    pop bc
    ld a,e
    ld hl,TOKBUF
    bit 0,c
    jr nz,.tone
    ld a,(TOKBUF)
    and #7F
    ld (TOKBUF),a
    ld a,e
    call M_AMPENV
    jp lnil
.tone:
    call M_TONEENV
    jp lnil
.bad:
    ld de,(V_LIBFN)
    ld hl,m_nargs
    CORE error

;; (release channels): sound held for a rendezvous goes (1 A, 2 B, 4 C)
;@ RELEASE 1 1 lf_release
lf_release:
    push hl
    call lint_hl
    ld a,l
    call M_SNDREL
    pop hl
    ret

;; (sound-check channel) -> its queue's state, as BASIC's SQ (1 A, 2 B, 4 C)
;@ SOUND-CHECK 1 1 lf_sound_check
lf_sound_check:
    call lint_hl
    ld a,l
    call M_SNDCHECK
    ld l,a
    ld h,0
    add hl,hl
    inc hl
    ret

;; (sound-hold) -> T if any sound was playing: everything stops where it is
;@ SOUND-HOLD 0 0 lf_sound_hold
lf_sound_hold:
    call M_SNDHOLD
    jp c,lt
    jp lnil

;; (sound-continue): what sound-hold stopped goes on
;@ SOUND-CONTINUE 0 0 lf_sound_continue
lf_sound_continue:
    call M_SNDCONT
    jp lnil

;; (peek address) -> the byte there, as the core sees memory: Lisp's RAM
;; below &C000, and at &C000 library part 0's (the one running this)
;@ PEEK 1 1 lf_peek
lf_peek:
    call lint_hl
    ld l,(hl)
    ld h,0
    add hl,hl
    inc hl
    ret

;; (poke address byte) -> the byte
;@ POKE 2 2 lf_poke
lf_poke:
    call lint_hl
    push de
    call lint_de
    ld (hl),e
    pop hl
    ret
