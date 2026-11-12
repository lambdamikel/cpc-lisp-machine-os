;; CPC Lisp -- the TRS-80's own Lisp functions in library part 1
;; (lib/lib2.asm includes this): speech through Talker/80, Michael
;; Wessel's voice synthesizer for the TRS-80, on port 11.
;;
;; Text goes to the port, a return makes it speak; bytes above 127 are
;; commands (&FE stop, &EE DECtalk mode, &E9 no spoken confirmations,
;; &Cn the voice, &An the rate, &Bn the volume); while it speaks, bits 6
;; and 7 of the port read 0. Without a Talker/80 the port reads &FF and
;; nothing is heard.

TK_PORT     equ 11

;; tk_out: A to Talker/80, then about half a millisecond: its firmware
;; takes each byte in an interrupt from the data bus latch, and one
;; written before it has will overwrite the last -- a lost "[" or "<" in
;; DECtalk's phoneme notation silences the rest of a song (the CPC paces
;; the LambdaSpeak card the same way). All kept but the flags.
tk_out:
    out (TK_PORT),a
    push bc
    ld b,70                     ; 70 * 13 T: 0.5 ms on a Model I, 0.45 on a III
.d:
    djnz .d
    pop bc
    ret

;; tk_wait: while Talker/80 speaks; BREAK lets out
tk_wait:
    in a,(TK_PORT)
    and #C0
    cp #C0
    ret z
    push hl
    push bc
    CORE poll_esc
    pop bc
    pop hl
    jr tk_wait

;; (say string): Talker/80 speaks it, DECtalk's way, as LambdaSpeak does
;; on the CPC (so its [:phoneme ...] singing works). A line waits for the
;; one before. -> T
;@ SAY 1 1 lf_say
lf_say:
    CORE subr_string
    CORE str_data               ; HL = the characters, BC = how many
    call tk_wait
    ld a,#E9                    ; no spoken confirmations, DECtalk -- each
    call tk_out                 ;   time, as on the CPC: a reset of the
    ld a,#EE                    ;   TRS-80 resets Talker/80 to its DIP
    call tk_out                 ;   switches' mode, and RAM remembers
.l:                             ;   nothing then (a flag did, wrongly)
    ld a,b
    or c
    jr z,.cr
    ld a,(hl)
    and #7F
    cp 13
    jr nz,.ch
    ld a," "                    ; a line break inside: a blank
.ch:
    call tk_out
    inc hl
    dec bc
    jr .l
.cr:
    ld a,13
    call tk_out
    jp lt

;; (speech-stop)
;@ SPEECH-STOP 0 0 lf_speech_stop
lf_speech_stop:
    ld a,#FE
    call tk_out
    jp lt

;; (speech-voice n), (speech-rate n), (speech-volume n): 0-15, 0 the
;; default
;@ SPEECH-VOICE 1 1 lf_speech_voice
lf_speech_voice:
    ld c,#C0
    jr tk_setting
;@ SPEECH-RATE 1 1 lf_speech_rate
lf_speech_rate:
    ld c,#A0
    jr tk_setting
;@ SPEECH-VOLUME 1 1 lf_speech_volume
lf_speech_volume:
    ld c,#B0
tk_setting:
    push hl
    call lint_hl
    ld a,l
    and 15
    or c
    call tk_out
    pop hl
    ret

;; ---------------------------------------------------------------------------
;; MIDI through MIDI/80, Michael Wessel's MIDI card for the TRS-80: a byte
;; to port 8 goes out of its MIDI OUT (and to its Waveblaster module, as its
;; DIP switches say). The machine page sends it and waits its time
;; (M_MIDI). midi-note and the rest are Lisp (lib/lisp2.lsp).

;; (midi-out byte...) -> NIL: the bytes as they are, out of MIDI OUT
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
