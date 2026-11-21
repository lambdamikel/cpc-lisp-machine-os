;; CPC Lisp -- the Spectrum's own Lisp functions, in library part 0
;; (lib/gfx.asm includes this).

;; *features* and anything else the machine has in Lisp
;@lisp mach.lsp

;; (quit): back to the machine's menu (a reset) -- or, in ZEsarUX with its
;; debug ports, out of the emulator
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
;; (envelope n ...), (tone-envelope n ...): taken and not heard yet
;@ ENVELOPE 4 16 lf_envelope
;@ TONE-ENVELOPE 4 16 lf_envelope
lf_envelope:
    jp lnil

;; (peek address) -> the byte there, as the core sees memory: the 48 BASIC
;; ROM below &4000, the screen from &4000, and at &C000 library part 0's
;; bank (the one running this)
;@ PEEK 1 1 lf_peek
lf_peek:
    call lint_hl
    ld l,(hl)
    ld h,0
    add hl,hl
    inc hl
    ret

;; (poke address byte) -> the byte. Below &4000 it goes nowhere (the ROM).
;@ POKE 2 2 lf_poke
lf_poke:
    call lint_hl
    push de
    call lint_de
    ld (hl),e
    pop hl
    ret
