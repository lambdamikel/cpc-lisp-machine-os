;; CPC Lisp -- the LambdaSpeak card: speech, and PlayCity's six more sound
;; channels (library ROM, part 1). ~/git/lambdaspeak4/docs has the card;
;; rsx-commands.md and playcity.md are what this follows.
;;
;; The card listens at &FBEE. Bytes go out one at a time, about 0.8 ms
;; apart, as the card's own ROM sends them (a faster burst has reset it).
;; The carriage return that ends a line of speech is special: it starts a
;; long piece of work on the card, while which a fetch from a ROM the card
;; serves -- and all of Lisp's ROMs may be on the card -- can be served
;; wrong. So that byte is written by a few bytes of code copied into RAM,
;; which then wait two frames in RAM before returning to the ROM.

CARD_PORT   equ #FBEE
PC_CLOCK    equ #F880           ; PlayCity: the clock (CTC channel 0)
PC_RSEL     equ #F984           ; the right chip: register select,
PC_RVAL     equ #F884           ;   value; the left chip is #F988, #F888
CARD_RAM    equ TOKBUF+200      ; where the carriage return's code goes

;; cd_send: A = a byte to the card, then a pause. BC, DE, HL kept.
cd_send:
    push bc
    ld bc,CARD_PORT
    out (c),a
    ld b,0
.p:
    djnz .p                     ; ~0.8 ms
    pop bc
    ret

;; cd_cr: the carriage return, from RAM, and two frames' wait there
cd_cr:
    ld hl,cd_crcode
    ld de,CARD_RAM
    ld bc,cd_crend-cd_crcode
    ldir
    jp CARD_RAM
cd_crcode:
    ld bc,CARD_PORT
    ld a,13
    out (c),a
    ld de,6000                  ; ~40 ms, all of it in RAM
    dec de
    ld a,d
    or e
    jr nz,$-3
    ret
cd_crend:

;; (say text): the card speaks it, in DECtalk (its own text-to-speech; the
;; voice, rate and volume below). It goes on speaking while Lisp goes on;
;; a second line waits its turn. -> T
;@ SAY 1 1 lf_say
lf_say:
    call sd_text                ; HL = the characters, BC = how many
    ld a,#EE                    ; DECtalk mode
    call cd_send
.l:
    ld a,b
    or c
    jr z,.cr
    ld a,(hl)
    cp 13
    jr nz,.ch
    ld a," "                    ; a line break inside: a blank
.ch:
    call cd_send
    inc hl
    dec bc
    jr .l
.cr:
    call cd_cr
    jp lt

;; sd_text: HL = a string designator -> its characters, BC = how many
sd_text:
    CORE subr_string
    CORE str_data
    ret

;; (speech-stop): the card stops speaking
;@ SPEECH-STOP 0 0 lf_speech_stop
lf_speech_stop:
    ld a,#DF
    call cd_send
    jp lnil

;; (speech-voice n): 1 Paul, 2 Harry, 3 Betty, 4 Ursula, 5 Dennis, 6 Kit,
;; 7 Frank, 8 Rita, 9 Wendy; 0 the default. (speech-rate n),
;; (speech-volume n): 0-15, 0 the default
;@ SPEECH-VOICE 1 1 lf_speech_voice
lf_speech_voice:
    ld c,#B0
    jr cd_setting
;@ SPEECH-RATE 1 1 lf_speech_rate
lf_speech_rate:
    ld c,#90
    jr cd_setting
;@ SPEECH-VOLUME 1 1 lf_speech_volume
lf_speech_volume:
    ld c,#A0
cd_setting:
    push hl
    call lint_hl
    ld a,l
    and 15
    or c
    call cd_send
    pop hl
    ret

;; ---------------------------------------------------------------------------
;; PLAYCITY: two more AY chips, three channels each. On the card it must be
;; switched on first; a real PlayCity needs nothing, and takes no harm.

;; (playcity on): T switches the card's PlayCity on, at the CPC's pitch,
;; all six channels silent; NIL off
;@ PLAYCITY 1 1 lf_playcity
lf_playcity:
    push hl
    ld a,#D0                    ; &D0 &43 n: the card's PlayCity on or off
    call cd_send
    ld a,#43
    call cd_send
    ld a,h
    or l
    jr z,.off
    ld a,1
    call cd_send
    ld bc,PC_CLOCK              ; the clock: 1 MHz, the CPC's AY
    ld a,#7F
    out (c),a
    ld a,1
    out (c),a
    ld e,0                      ; both chips: tones on, noise off
    call .mixer
    ld e,1
    call .mixer
    call pc_quiet
    pop hl
    ret
.off:
    xor a
    call cd_send
    pop hl
    ret
.mixer:
    ld d,7
    ld a,#38
    jp pc_reg

;; (pc-tone channel period [volume]): PlayCity channel 0-5 plays period (as
;; SOUND's: (note 'a4) is 284) at volume 0-15 (12), until it is changed;
;; volume 0 silences it
;@ PC-TONE 2 3 lf_pc_tone
lf_pc_tone:
    NEXTARG
    call lint_de
    ld a,e
    cp 6
    jr nc,.bad
    push de                     ; the channel
    NEXTARG
    call lint_de
    push de                     ; the period
    ld e,12
    ld a,b
    cp 3
    jr nz,.v
    NEXTARG
    call lint_de
.v:
    ld a,e
    and 15
    pop hl                      ; the period
    pop de                      ; E = the channel
    push af
    call pc_which               ; E = the chip, C = the voice
    ld d,c
    sla d                       ; its period's registers: 2v, 2v+1
    ld a,l
    call pc_reg
    inc d
    ld a,h
    and 15
    call pc_reg
    pop af
    ld d,c                      ; its volume: 8 + v
    set 3,d
    call pc_reg
    jp lnil
.bad:
    ld hl,m_index
    ld de,UNBOUND
    CORE error

;; (pc-off): all six silent
;@ PC-OFF 0 0 lf_pc_off
lf_pc_off:
    call pc_quiet
    jp lnil

pc_quiet:
    ld e,0
    call .chip
    ld e,1
.chip:
    ld d,8
    xor a
    call pc_reg
    inc d
    call pc_reg
    inc d
    jp pc_reg

;; pc_which: E = a channel 0-5 -> E = its chip (0 right, 1 left), C = its
;; voice 0-2
pc_which:
    ld a,e
    ld e,0
    cp 3
    jr c,.v
    sub 3
    inc e
.v:
    ld c,a
    ret

;; pc_reg: E = the chip (0 right, 1 left), D = a register, A = its value.
;; All kept.
pc_reg:
    push bc
    push af
    ld bc,PC_RSEL
    bit 0,e
    jr z,.r
    ld c,PC_RSEL+4 and #FF      ; the left chip: &F988
.r:
    out (c),d                   ; select,
    dec b                       ;   &F9xx -> &F8xx
    pop af
    out (c),a                   ;   write
    pop bc
    ret
