;; CPC Lisp -- sound on the Spectrum's AY-3-8912, in machine page B
;; (pageb.asm includes this): the CPC firmware's sound manager, as CPC Lisp
;; on FutureOS has it (mach/fos/page.asm, matched there against the 464's
;; firmware by logs of the AY's writes): three channels (A, B, C: 1, 2, 4),
;; a queue of four sounds each, amplitude and tone envelopes (15 each, of
;; up to five sections: steps, a step's size, the pause after each, in
;; 1/100 s; a tone section of 240 steps or more sets the period: its low
;; four bits and the next byte), rendezvous between channels, sounds held
;; until SOUND RELEASE; an envelope's first step as the sound starts, then
;; one every pause; without an amplitude envelope the volume doubled
;; (BASIC's 0-7). No hardware envelopes, no sound events.
;;
;; The Spectrum's: the AY at &FFFD (its register) and &BFFD (the value);
;; its clock 1.7734 MHz, the CPC's 1 MHz -- a period, tone or noise, is
;; made 227/128 times as long on its way to the AY (snd_per, snd_mix: the
;; same pitch; down to the AY's longest, 4095: below 27 Hz the notes stay
;; there); its port A an output (the 128K's RS232 and MIDI: the mixer's bit
;; 6 set). snd_tick runs twice from each of the interrupt's 50 a second
;; (b_tick, which the resident part's interrupt calls with this page in).
;; The queues and envelopes are in this page's data, past its code (s_init
;; clears them).

SQN         equ 4               ; sounds a channel's queue holds
    assert SQN == 4             ; (snd_slot)
;; a queued sound, 8 bytes: the period (2), noise, the volume (bits 0-3)
;; and its flags (4-6: rendezvous with A, B, C; 7: held), the duration
;; (2), the envelopes (bits 0-3 amplitude, 4-7 tone)
;; an envelope's state, each channel's two (IX):
ES          equ 8
ES_ENV      equ 0               ; its number (0: none, or ended)
ES_SEC      equ 1               ; the next section
ES_CNT      equ 2               ; steps left in this one
ES_STP      equ 3               ; a step's size
ES_PL       equ 4               ; the pause after a step
ES_PAU      equ 5               ; the pause now
ES_NSEC     equ 6               ; its sections (bit 7: over again)
ES_TONE     equ 7               ; 1: a tone envelope

;; SOUND QUEUE: HL = a sound, nine bytes (channels and flags, amplitude
;; envelope, tone envelope, period (2), noise, volume, duration (2)) ->
;; carry if it was queued on its channels, none if a queue was full
b_snd_queue:
    push bc
    push de
    push hl
    di
    ld a,(hl)
    bit 7,a                     ; flush: the channels' queues and sounds
    jr z,.nf
    push hl
    call snd_flush
    pop hl
    ld a,(hl)
.nf:
    and 7
    jr z,.ok
    ld (sq_ch),a
    ld c,a                      ; room on every channel?
    ld b,0
.room:
    rr c
    jr nc,.rn
    ld de,snd_cnt
    call snd_ix
    ld a,(de)
    cp SQN
    jr nc,.full
.rn:
    inc b
    ld a,b
    cp 3
    jr nz,.room
    ld a,(sq_ch)                ; then onto each
    ld c,a
    ld b,0
.each:
    rr c
    jr nc,.en
    pop hl
    push hl
    push bc
    call snd_put
    pop bc
.en:
    inc b
    ld a,b
    cp 3
    jr nz,.each
.ok:
    ei
    pop hl
    pop de
    pop bc
    scf
    ret
.full:
    ei
    pop hl
    pop de
    pop bc
    or a
    ret
;; snd_ix: DE = an array of three bytes, B = a channel -> DE = its byte.
;; AF kept.
snd_ix:
    push af
    ld a,e
    add a,b
    ld e,a
    adc a,d
    sub e
    ld d,a
    pop af
    ret
;; snd_put: HL = a sound, B = a channel with room -> queued. Its flags for
;; this channel: the rendezvous it asks for and the sound's other channels
;; (it starts on all at once), held
snd_put:
    push hl
    ld a,(hl)
    ld c,a
    rrca
    rrca
    rrca
    or c
    and 7
    ld e,a
    call snd_bit
    cpl
    and e                       ; (not with itself)
    ld e,a
    ld a,c
    and #40
    rrca
    rrca
    rrca
    or e
    add a,a
    add a,a
    add a,a
    add a,a
    ld (sp_flags),a
    inc hl
    ld a,(hl)                   ; the envelopes
    and 15
    ld e,a
    inc hl
    ld a,(hl)
    add a,a
    add a,a
    add a,a
    add a,a
    or e
    ld (sp_env),a
    ld de,snd_cnt
    call snd_ix
    ld a,(de)
    ld c,a
    inc a
    ld (de),a
    ld de,snd_rd
    call snd_ix
    ld a,(de)
    add a,c
    call snd_slot               ; HL = its slot
    pop de
    push de
    push hl
    ex de,hl
    ld bc,3
    add hl,bc
    ld bc,6                     ; the period, noise, volume, duration
    ldir
    ld a,(sp_env)
    ld (de),a
    pop hl
    inc hl
    inc hl
    inc hl
    ld a,(hl)
    and 15
    ld c,a
    ld a,(sp_flags)
    or c
    ld (hl),a
    pop hl
    ret
;; snd_slot: A = a place in a queue (taken mod SQN), B = the channel ->
;; HL = its 8 bytes. B kept
snd_slot:
    and SQN-1
    ld c,a
    ld a,b
    add a,a
    add a,a
    add a,c
    add a,a
    add a,a
    add a,a
    ld l,a
    ld h,0
    ld de,snd_q
    add hl,de
    ret
;; snd_head: B = a channel -> HL = the first sound waiting in its queue;
;; Z if there is none. B kept
snd_head:
    ld de,snd_cnt
    call snd_ix
    ld a,(de)
    or a
    ret z
    ld de,snd_rd
    call snd_ix
    ld a,(de)
    call snd_slot
    or 1
    ret
;; snd_bit: B = a channel -> A = its bit (1, 2, 4). All else kept
snd_bit:
    push bc
    ld a,1
    inc b
    jr .t
.l:
    add a,a
.t:
    djnz .l
    pop bc
    ret
;; snd_durp, snd_perp: B = a channel -> HL = its duration's, its period's
;; word. DE kept
snd_durp:
    ld hl,ch_dur
    jr snd_w
snd_perp:
    ld hl,ch_per
snd_w:
    ld a,b
    add a,a
    add a,l
    ld l,a
    ret nc
    inc h
    ret
;; snd_flush: A = channels: their queues emptied, their sounds stopped
snd_flush:
    and 7
    ld c,a
    ld b,0
.l:
    rr c
    jr nc,.n
    push bc
    ld de,snd_cnt
    call snd_ix
    xor a
    ld (de),a
    ld a,b
    add a,a
    ld e,a
    ld d,0
    ld hl,ch_dur
    add hl,de
    xor a
    ld (hl),a
    inc hl
    ld (hl),a
    ld de,ch_amp
    call snd_ix
    xor a
    ld (de),a
    ld a,b
    add a,8
    ld c,0
    call ay_w                   ; silent
    pop bc
.n:
    inc b
    ld a,b
    cp 3
    jr nz,.l
    ret
;; SOUND CHECK: A = a channel (1, 2, 4) -> A = its state: free places in
;; its queue (bits 0-2), the first waiting sound's rendezvous with A, B, C
;; (3-5) and held (6), playing (7)
b_m_sndcheck:
    push bc
    push de
    push hl
    ld b,0
    rra
    jr c,.c
    inc b
    rra
    jr c,.c
    inc b
.c:
    call snd_head
    ld e,0
    jr z,.f
    inc hl
    inc hl
    inc hl
    ld a,(hl)
    rrca
    and #78
    ld e,a
.f:
    push de
    ld de,snd_cnt
    call snd_ix
    ld a,(de)
    ld c,a
    ld a,SQN
    sub c
    pop de
    or e
    ld c,a
    call snd_durp
    ld a,(hl)
    inc hl
    or (hl)
    ld a,c
    jr z,.r
    or #80
.r:
    pop hl
    pop de
    pop bc
    ret
;; SOUND HOLD: everything stops where it is -> carry if anything played;
;; SOUND CONTINUE: on again
b_m_sndhold:
    push bc
    ld a,1
    ld (snd_hold),a
    xor a                       ; silent meanwhile
    ld c,a
    ld a,8
    call ay_w
    ld a,9
    call ay_w
    ld a,10
    call ay_w
    ld hl,(ch_dur)
    ld a,h
    or l
    ld hl,(ch_dur+2)
    or h
    or l
    ld hl,(ch_dur+4)
    or h
    or l
    pop bc
    ret z
    scf
    ret
b_m_sndcont:
    xor a
    ld (snd_hold),a
    ret
;; SOUND RELEASE: A = channels -> the sounds held at the heads of their
;; queues may start
b_m_sndrel:
    push bc
    push de
    push hl
    di
    ld c,a
    ld b,0
.l:
    rr c
    jr nc,.n
    push bc
    call snd_head
    jr z,.e
    inc hl
    inc hl
    inc hl
    res 7,(hl)
.e:
    pop bc
.n:
    inc b
    ld a,b
    cp 3
    jr nz,.l
    ei
    pop hl
    pop de
    pop bc
    ret
;; SOUND AMPL ENVELOPE, SOUND TONE ENVELOPE: A = an envelope (1-15), HL =
;; its sections' count (a tone envelope's bit 7: over again), then three
;; bytes a section: kept
b_m_ampenv:
    push de
    ld de,snd_env
    jr snd_envput
b_m_toneenv:
    push de
    ld de,snd_tenv
snd_envput:
    push bc
    push hl
    dec a
    and 15
    cp 15
    jr nc,.no
    add a,a
    add a,a
    add a,a
    add a,a
    add a,e
    ld e,a
    adc a,d
    sub e
    ld d,a
    ld bc,16
    ldir
.no:
    pop hl
    pop bc
    pop de
    scf
    ret

;; snd_tick: once every 1/100 s (the interrupt, the page mapped in): each
;; channel's sound on, its envelopes a step on, the next from its queue
;; when it ends. AF, BC, DE, HL saved by the interrupt; IX here.
snd_tick:
    ld a,(snd_hold)
    or a
    ret nz
    push ix
    xor a
    ld (snd_new),a
    ld b,0
.ch:
    push bc
    call snd_chan
    pop bc
    inc b
    ld a,b
    cp 3
    jr nz,.ch
    pop ix
    ret
;; snd_chan: B = a channel
snd_chan:
    call snd_bit
    ld hl,snd_new
    and (hl)
    ret nz                      ; started this tick, by a rendezvous
    call snd_durp
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,d
    or e
    jr z,.next                  ; idle: the next, if one may start
    dec de
    ld (hl),d
    dec hl
    ld (hl),e
    ld a,d
    or e
    jr z,.next
    call snd_esa                ; its envelopes a step on
    call env_tick
    jr nc,.tone
    ld de,ch_amp
    call snd_ix
    ld a,(de)
    add a,c
    and 15
    ld (de),a
    call snd_amp
.tone:
    call snd_est
    call env_tick
    ret nc
    jp snd_tstep
.next:
    call snd_head
    jr z,.quiet
    inc hl
    inc hl
    inc hl
    ld a,(hl)
    bit 7,a
    jr nz,.quiet                ; held, until SOUND RELEASE
    rrca
    rrca
    rrca
    rrca
    and 7
    jp z,snd_take               ; no rendezvous: on
    ld (sc_r),a
    call snd_bit
    ld (sc_me),a
    push bc                     ; (B: this channel)
    ld b,0
    ld a,(sc_r)
    ld c,a
.chk:                           ; each partner ready?
    rr c
    jr nc,.cn
    call snd_ready
    jr nz,.wait
.cn:
    inc b
    ld a,b
    cp 3
    jr nz,.chk
    ld b,0                      ; all of them: they start, and this one
    ld a,(sc_r)
    ld c,a
.go:
    rr c
    jr nc,.gn
    push bc
    call snd_take
    pop bc
    call snd_bit
    ld hl,snd_new
    or (hl)
    ld (hl),a
.gn:
    inc b
    ld a,b
    cp 3
    jr nz,.go
    pop bc
    jp snd_take
.wait:
    pop bc
.quiet:                         ; nothing: silent
    ld de,ch_amp
    call snd_ix
    ld a,(de)
    or a
    ret z
    xor a
    ld (de),a
    ld a,b
    add a,8
    ld c,0
    jp ay_w
;; snd_ready: B = a channel, sc_me another's bit -> Z if B is free and its
;; first waiting sound, not held, waits for that one. BC kept
snd_ready:
    push bc
    call snd_bit
    ld hl,snd_new
    and (hl)
    jr nz,.no
    call snd_durp
    ld a,(hl)
    inc hl
    or (hl)
    jr nz,.no                   ; still sounding
    call snd_head
    jr z,.no
    inc hl
    inc hl
    inc hl
    ld a,(hl)
    bit 7,a
    jr nz,.no                   ; held
    rrca
    rrca
    rrca
    rrca
    and 7
    ld hl,sc_me
    and (hl)
    jr z,.no
    pop bc
    xor a
    ret
.no:
    pop bc
    or 1
    ret
;; snd_take: B = a channel: its first waiting sound out of the queue and
;; on. B kept
snd_take:
    call snd_head
    ret z
    push hl
    ld de,snd_cnt
    call snd_ix
    ld a,(de)
    dec a
    ld (de),a
    ld de,snd_rd
    call snd_ix
    ld a,(de)
    inc a
    and SQN-1
    ld (de),a
    pop hl
;; snd_start: B = a channel, HL = a sound's 8 bytes -> on: the mixer, its
;; volume and period as the envelopes' first steps make them, how long.
;; B kept
snd_start:
    ld e,(hl)                   ; the period
    inc hl
    ld d,(hl)
    inc hl
    push hl
    call snd_perp
    ld (hl),e
    inc hl
    ld (hl),d
    pop hl
    ld a,d                      ; tone on if there is a period
    or e
    ld c,(hl)                   ; noise
    inc hl
    push hl
    call snd_mix
    pop hl
    ld a,(hl)                   ; the volume
    and 15
    ld (st_vol),a
    inc hl
    ld e,(hl)                   ; the duration
    inc hl
    ld d,(hl)
    inc hl
    ld (st_dur),de
    ld a,(hl)                   ; the envelopes
    ld (st_env),a
    ld hl,0
    ld (st_len),hl
    call snd_esa
    ld a,(st_env)
    and 15
    jr nz,.ae
    ld (ix+ES_ENV),a            ; none: the volume doubled (BASIC's 0-7,
    ld a,(st_vol)               ;   as the firmware does)
    add a,a
    and 15
    ld (st_vol),a
    jr .ad
.ae:
    push af
    call env_len
    ld (st_len),hl
    pop af
    ld c,0
    call env_start
    jr nc,.ad
    ld a,(st_vol)
    add a,c
    and 15
    ld (st_vol),a
.ad:
    ld de,ch_amp
    call snd_ix
    ld a,(st_vol)
    ld (de),a
    call snd_amp
    call snd_est                ; the tone envelope
    ld a,(st_env)
    rrca
    rrca
    rrca
    rrca
    ld c,1
    call env_start
    jr nc,.tn
    call snd_tstep
    jr .du
.tn:
    call snd_perp
    ld e,(hl)
    inc hl
    ld d,(hl)
    call snd_per
.du:
    ld de,(st_dur)              ; the duration: 0, the amplitude
    ld a,d                      ;   envelope's (or two seconds); -n, it
    or e                        ;   n times over
    jr z,.len
    bit 7,d
    jr z,.set
    xor a
    sub e
    ld e,a
    sbc a,a
    sub d
    ld d,a
    ld hl,(st_len)
    call mul16
    ex de,hl
    call snd_esa
    set 7,(ix+ES_NSEC)
    jr .z
.len:
    ld de,(st_len)
.z:
    ld a,d
    or e
    jr nz,.set
    ld de,200
.set:
    call snd_durp
    ld (hl),e
    inc hl
    ld (hl),d
    ret
;; mul16: HL x DE -> HL (its low 16 bits). BC kept
mul16:
    push bc
    ld b,h
    ld c,l
    ld hl,0
    ld a,16
.l:
    add hl,hl
    ex de,hl
    add hl,hl
    ex de,hl
    jr nc,.n
    add hl,bc
.n:
    dec a
    jr nz,.l
    pop bc
    ret
;; snd_esa, snd_est: B = a channel -> IX = its amplitude, its tone
;; envelope's state. B kept
snd_esa:
    ld ix,es_a
    jr snd_es
snd_est:
    ld ix,es_t
snd_es:
    push de
    ld a,b
    add a,a
    add a,a
    add a,a
    ld e,a
    ld d,0
    add ix,de
    pop de
    ret
;; snd_tstep: B = a channel; A = 0: C = a step's size (signed), A = 1: DE
;; = a period -> its period that, on the AY. B kept
snd_tstep:
    push af
    call snd_perp
    pop af
    or a
    jr nz,.abs
    ld e,(hl)
    inc hl
    ld d,(hl)
    dec hl
    push hl
    ld a,c
    ld l,a
    rla
    sbc a,a
    ld h,a
    add hl,de
    ex de,hl
    pop hl
.abs:
    ld a,d
    and 15
    ld d,a
    ld (hl),e
    inc hl
    ld (hl),d
;; snd_per: B = a channel, DE = a period, the CPC's -> on the AY, made
;; the AY's here (at most 4095). B kept
snd_per:
    ex de,hl
    call snd_scale
    ld a,h
    cp 16
    jr c,.ok
    ld hl,4095
.ok:
    ex de,hl
    ld a,b
    add a,a
    ld c,e
    call ay_w
    ld a,b
    add a,a
    inc a
    ld c,d
    jp ay_w

;; env_len: A = an amplitude envelope (1-15) -> HL = its length in 1/100
;; s: steps x pause (0: 256), each section. B kept
env_len:
    dec a
    add a,a
    add a,a
    add a,a
    add a,a
    ld e,a
    ld d,0
    ld hl,snd_env
    add hl,de
    ld a,(hl)                   ; its sections
    and #7F
    inc hl
    ld de,0
    or a
    jr z,.e
    push bc
    ld b,a
.s:
    ld a,(hl)                   ; steps
    and #7F
    inc hl
    inc hl
    ld c,(hl)                   ; the pause
    inc hl
    push hl
    ld l,c
    ld h,0
    inc c
    dec c
    jr nz,.p
    inc h                       ; (0: 256)
.p:
    or a
    jr z,.sn
.m:
    ex de,hl
    add hl,de
    ex de,hl
    dec a
    jr nz,.m
.sn:
    pop hl
    djnz .s
    pop bc
.e:
    ex de,hl
    ret
;; env_start: IX = an envelope's state, A = the envelope (bits 0-3; 0:
;; none), C = 1 for a tone envelope -> its first step, as env_step
env_start:
    and 15
    ld (ix+ES_ENV),a
    ret z                       ; (no carry)
    ld (ix+ES_TONE),c
    call env_addr
    ld a,(hl)
    ld (ix+ES_NSEC),a
    xor a
    ld (ix+ES_SEC),a
    ld (ix+ES_CNT),a
    jr env_step
;; env_tick: IX = an envelope's state -> its step, as env_step, if one is
;; due now
env_tick:
    ld a,(ix+ES_ENV)
    or a
    ret z                       ; (no carry)
    dec (ix+ES_PAU)
    ret nz
;; env_step: IX = an envelope's state -> carry and A = 0, C = a step's
;; size, or A = 1, DE = a period (a tone section's); no carry: no step (the
;; envelope is over, or a section without steps pauses)
env_step:
    ld a,(ix+ES_CNT)
    or a
    jr nz,.step
    ld a,(ix+ES_NSEC)           ; the next section
    and #7F
    ld c,a
    ld a,(ix+ES_SEC)
    cp c
    jr c,.sec
    bit 7,(ix+ES_NSEC)
    jr z,.end
    ld a,c                      ; over again
    or a
    jr z,.end
    xor a
.sec:
    ld c,a
    inc a
    ld (ix+ES_SEC),a
    call env_addr               ; its three bytes: HL + 1 + 3 x section
    inc hl
    ld a,c
    add a,a
    add a,c
    add a,l
    ld l,a
    adc a,h
    sub l
    ld h,a
    ld a,(hl)                   ; steps
    inc hl
    ld c,(hl)                   ; a step's size (a period's low byte)
    inc hl
    ld e,(hl)                   ; the pause
    ld (ix+ES_PL),e
    ld (ix+ES_PAU),e
    bit 0,(ix+ES_TONE)
    jr z,.amp
    cp #F0
    jr c,.rel
    and 15                      ; a period: steps' low bits, the byte
    ld d,a
    ld e,c
    xor a
    ld (ix+ES_CNT),a
    inc a
    scf
    ret
.amp:
    and #7F
.rel:
    ld (ix+ES_CNT),a
    ld (ix+ES_STP),c
    or a
    ret z                       ; (no steps: its pause only)
.step:
    dec (ix+ES_CNT)
    ld c,(ix+ES_STP)
    ld a,(ix+ES_PL)
    ld (ix+ES_PAU),a
    xor a
    scf
    ret
.end:
    xor a                       ; over: the volume or period stays
    ld (ix+ES_ENV),a
    ret
;; env_addr: IX = an envelope's state -> HL = the envelope's 16 bytes
env_addr:
    ld a,(ix+ES_ENV)
    dec a
    add a,a
    add a,a
    add a,a
    add a,a
    ld l,a
    ld h,0
    ld de,snd_env
    bit 0,(ix+ES_TONE)
    jr z,.a
    ld de,snd_tenv
.a:
    add hl,de
    ret
;; snd_mix: B = a channel, NZ: its tone on; C = noise (0: off) -> the
;; mixer (register 7) and the noise's period (6)
snd_mix:
    push af
    ld a,b
    ld hl,mix_bits
    add a,l
    ld l,a
    adc a,h
    sub l
    ld h,a
    pop af
    ld a,(snd_mixv)
    jr z,.toff
    ld e,a                      ; tone on: its bit clear
    ld a,(hl)
    cpl
    and e
    jr .t
.toff:
    or (hl)
.t:
    ld e,a
    ld a,(hl)
    rlca
    rlca
    rlca                        ; its noise bit
    ld d,a
    ld a,c
    or a
    ld a,e
    jr z,.noff
    ld a,d
    cpl
    and e
    ld e,a
    push bc
    push de
    ld l,c                      ; the noise's period, made the AY's
    ld h,0
    call snd_scale
    pop de
    ld a,h
    or a
    jr nz,.nmax
    ld a,l
    cp 32
    jr c,.ns
.nmax:
    ld a,31
.ns:
    ld c,a
    ld a,6
    call ay_w                   ; the noise's period
    pop bc
    jr .m
.noff:
    or d
    ld e,a
.m:
    ld a,e
    and #3F
    or #40                      ; (port A an output: the RS232 and MIDI)
    ld (snd_mixv),a
    push bc
    ld c,a
    ld a,7
    call ay_w
    pop bc
    ret
mix_bits:   db 1,2,4
;; snd_amp: B = a channel -> its volume on the AY
snd_amp:
    ld de,ch_amp
    call snd_ix
    ld a,(de)
    ld c,a
    ld a,b
    add a,8
;; ay_w: A = an AY register, C = a value: written. B kept... and A,
;; flags lost.
ay_w:
    push bc
    ld b,c
    ld c,P_AYREG and #FF
    push bc                     ; (B: the value)
    ld b,P_AYREG >> 8
    out (c),a
    pop af                      ; A = the value
    ld b,P_AYDAT >> 8
    out (c),a
    pop bc
    ret

;; snd_scale: HL = a period, the CPC's -> HL = the AY's here: * 227 / 128.
;; BC kept, DE lost.
snd_scale:
    push bc
    ld b,h
    ld c,l
    xor a                       ; A:HL = HL * 227 (24 bits)
    ld h,a
    ld l,a
    ld d,227
    ld e,8
.m:
    add hl,hl
    rla
    sla d
    jr nc,.n
    add hl,bc
    adc a,0
.n:
    dec e
    jr nz,.m
    ld e,7                      ; / 128
.d:
    srl a
    rr h
    rr l
    dec e
    jr nz,.d
    pop bc
    ret

sq_ch:      db 0
snd_hold:   db 0
snd_new:    db 0                ; channels started this tick (a rendezvous)
sc_r:       db 0                ; snd_chan: the rendezvous' other channels,
sc_me:      db 0                ;   this one's bit
sp_flags:   db 0                ; snd_put: the flags (bits 4-7),
sp_env:     db 0                ;   the envelopes
st_vol:     db 0                ; snd_start: the volume,
st_env:     db 0                ;   the envelopes,
st_dur:     dw 0                ;   the duration,
st_len:     dw 0                ;   the amplitude envelope's length
snd_mixv:   db #7F              ; the mixer: all off
snd_cnt:    db 0,0,0            ; sounds waiting, each channel
snd_rd:     db 0,0,0            ; the first of them
ch_dur:     dw 0,0,0            ; the sound on: 1/100 s to go,
ch_per:     dw 0,0,0            ;   its period,
ch_amp:     db 0,0,0            ;   its volume
snd_hold_end:
es_a        equ PB_DATA         ; the amplitude envelopes' states
es_t        equ es_a+3*ES       ; the tone envelopes'
snd_q       equ es_t+3*ES       ; the queues: 8 bytes a sound
snd_env     equ snd_q+3*SQN*8   ; the amplitude envelopes
snd_tenv    equ snd_env+15*16   ; the tone envelopes
snd_dend    equ snd_tenv+15*16
    assert snd_dend <= PB_DATA_END

;; s_init: the AY silent, the queues and the envelopes empty
s_init:
    ld hl,PB_DATA
    ld de,PB_DATA+1
    ld bc,snd_dend-PB_DATA-1
    ld (hl),0
    ldir
    ld hl,snd_cnt
    ld b,snd_hold_end-snd_cnt
.z:
    ld (hl),0
    inc hl
    djnz .z
    xor a
    ld (snd_hold),a
    ld c,a
    ld a,8
    call ay_w
    ld a,9
    call ay_w
    ld a,10
    call ay_w
    ld a,#7F
    ld (snd_mixv),a
    ld c,a
    ld a,7
    jp ay_w

;; b_tick: from the interrupt, 50 times a second: the firmware's 100 ticks
b_tick:
    call snd_tick
    jp snd_tick
