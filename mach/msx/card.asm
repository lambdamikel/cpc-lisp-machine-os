;; CPC Lisp -- the MSX's own Lisp functions in library part 1
;; (lib/lib2.asm includes this): MIDI out -- nowhere, an MSX1 has none (the
;; machine page's M_MIDI; under the test harness the bytes go to the
;; transcript). midi-note and the rest are Lisp (lib/lisp2.lsp).

;; (midi-out byte...) -> NIL: the bytes as they are, out of the socket
;@ MIDI-OUT 0 255 lf_midi_out
lf_midi_out:
    ld a,b
    or a
    jp z,lnil
.l:
    NEXTARG
    call lint_de                ; (B kept)
    ld a,e
    call M_MIDI
    djnz .l
    jp lnil

;; (midi-off) -> NIL: nothing to do here (on the CPC it takes the
;; LambdaSpeak card out of its MIDI mode)
;@ MIDI-OFF 0 0 lf_midi_off
lf_midi_off:
    jp lnil

;; |BOOTLISP is the CPC's, from BASIC (lib/lib2.asm's ROM header names it)
rsx_bootlisp:
    ret
