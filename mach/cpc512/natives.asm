;; CPC Lisp -- the CPC's own Lisp functions, in library part 0 (lib/gfx.asm
;; includes this): graphics and text modes, the joystick, PEEK and POKE,
;; the sound envelopes. Another machine provides its own, or none.

;; *features* and anything else the machine has in Lisp
;@lisp mach.lsp

;; ---------------------------------------------------------------------------
;; GRAPHICS AND TEXT MODES

;; (ink-mode n): how graphics are drawn: 0 normally, 1 XOR, 2 AND, 3 OR
;@ INK-MODE 1 1 lf_ink_mode
lf_ink_mode:
    push hl
    call lint_hl
    ld a,l
    and 3
    call SCR_ACCESS
    pop hl
    ret

;; (window left right top bottom): the text window, from 1, as in BASIC
;@ WINDOW 4 4 lf_window
lf_window:
    ld c,4
    call gx_ints
    pop de                      ; E = bottom
    pop hl                      ; L = top
    pop bc
    ld d,c                      ; D = right
    pop bc
    ld h,c                      ; H = left
    dec h
    dec d
    dec l
    dec e
    call TXT_WIN_ENABLE
    jp lnil

;; (tag on): T sends text to the graphics cursor (BASIC's TAG), NIL back
;@ TAG 1 1 lf_tag
lf_tag:
    ld a,h
    or l
    push hl
    call TXT_SET_GRAPHIC
    pop hl
    ret

;; (transparent on): T draws text without its paper, NIL with
;@ TRANSPARENT 1 1 lf_transparent
lf_transparent:
    ld a,h
    or l
    jr z,.set
    ld a,1
.set:
    push hl
    call TXT_SET_BACK
    pop hl
    ret

;; (flash-speed on off): how long each colour of a flashing ink shows, in
;; 1/50 s (BASIC's SPEED INK)
;@ FLASH-SPEED 2 2 lf_flash_speed
lf_flash_speed:
    call lint_hl
    call lint_de
    ld h,l
    ld l,e
    call SCR_SET_FLASHING
    jp lnil

;; (text-cursor) -> (column row), from 1, as BASIC's POS and VPOS
;@ TEXT-CURSOR 0 0 lf_text_cursor
lf_text_cursor:
    call CON_GETCUR
    push hl
    ld l,h
    ld h,0
    add hl,hl
    inc hl                      ; the column
    ex (sp),hl
    ld h,0
    add hl,hl
    inc hl                      ; the row
    ld de,NIL
    CORE cons
    ex de,hl
    pop hl
    CORE cons
    ret

;; ---------------------------------------------------------------------------
;; THE MACHINE

;; (joystick [n]) -> joystick n's state (0 or 1): 1 up, 2 down, 4 left,
;; 8 right, 16 fire 2, 32 fire 1, added
;@ JOYSTICK 0 1 lf_joystick
lf_joystick:
    ld c,0
    ld a,b
    or a
    jr z,.read
    NEXTARG
    call lint_de
    ld c,e
.read:
    push bc
    call KM_GET_JOYSTICK
    pop bc
    ld a,c
    or a
    ld a,h
    jr z,.got
    ld a,l
.got:
    and #3F
    ld l,a
    ld h,0
    add hl,hl
    inc hl
    ret

;; (peek address) -> the byte in RAM there (0-65535; above 16383 the reader
;; makes a float of it, which is fine). RAM, not the ROMs: through the
;; firmware's RAM LAM.
;@ PEEK 1 1 lf_peek
lf_peek:
    call lint_hl
    call RS_RAMRD               ; A = (HL) in the main RAM (the screen's at
                                ;   &C000, not the code's bank)
    ld l,a
    ld h,0
    add hl,hl
    inc hl
    ret

;; (poke address byte) -> the byte. Writes always reach RAM.
;@ POKE 2 2 lf_poke
lf_poke:
    call lint_hl
    push de
    call lint_de
    ld a,e
    call RS_RAMWR               ; in the main RAM, &C000 up the screen's
    pop hl
    ret

;; ---------------------------------------------------------------------------
;; SOUND

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
    call SOUND_AMPL_ENVELOPE
    jp lnil
.tone:
    call SOUND_TONE_ENVELOPE
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
    call SOUND_RELEASE
    pop hl
    ret

;; (sound-check channel) -> its queue's state, as BASIC's SQ (1 A, 2 B, 4 C)
;@ SOUND-CHECK 1 1 lf_sound_check
lf_sound_check:
    call lint_hl
    ld a,l
    call SOUND_CHECK
    ld l,a
    ld h,0
    add hl,hl
    inc hl
    ret

;; (sound-hold) -> T if any sound was playing: everything stops where it is
;@ SOUND-HOLD 0 0 lf_sound_hold
lf_sound_hold:
    call SOUND_HOLD
    jp c,lt
    jp lnil

;; (sound-continue): what sound-hold stopped goes on
;@ SOUND-CONTINUE 0 0 lf_sound_continue
lf_sound_continue:
    call SOUND_CONTINUE
    jp lnil

