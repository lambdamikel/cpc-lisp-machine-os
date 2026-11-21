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
