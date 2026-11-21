;; CPC Lisp -- sound on the Spectrum's AY-3-8912, in machine page A
;; (page.asm includes this).
;;
;; SND_QUEUE takes the CPC's sound record: [0] the channels (bits 0-2: A,
;; B, C; bit 7 flushes them first), [1] the volume envelope, [2] the tone
;; envelope, [3] the period, [5] the noise period, [6] the volume, [7] the
;; duration in 1/100 s. Each channel has a queue of S_QN sounds; the
;; interrupt (s_tick) plays them one after the other, a fiftieth of a
;; second at a time. The CPC's AY runs at 1 MHz, the Spectrum's at 1.7734:
;; a period is made 227/128 times as long, the same pitch (down to the
;; AY's longest, 4095: below about 27 Hz the notes stay there). Without a
;; volume envelope the volume is doubled, as the CPC's firmware does it (8
;; is silent). Not yet: the envelopes themselves (a note keeps its volume),
;; rendezvous and holding (a sound starts when its channel is free).

S_QN        equ 4               ; sounds queued a channel
S_ESIZE     equ 6               ; a sound: period (2), noise, volume,
                                ;   duration (2), in 1/100 s
;; a channel: [0] the sounds in its queue, [1] 1 while one plays, [2-3]
;; its time left, then the queue, S_QN of S_ESIZE
S_CSIZE     equ 4+S_QN*S_ESIZE

s_chan:     defs 3*S_CSIZE,0
s_mix:      db #7F              ; the mixer's register as last written
s_new:      defs S_ESIZE,0      ; the sound being queued

;; s_ay: A = a register, E = its value -> into the AY. BC, DE, HL kept.
s_ay:
    push bc
    ld bc,P_AYREG
    out (c),a
    ld b,P_AYDAT >> 8
    out (c),e
    pop bc
    ret

;; s_init: the AY silent, the queues empty
s_init:
    ld hl,s_chan
    ld de,s_chan+1
    ld bc,3*S_CSIZE-1
    ld (hl),0
    ldir
    ld e,0
    ld a,8
    call s_ay
    ld a,9
    call s_ay
    ld a,10
    call s_ay
    ld a,#7F                    ; port A out (the 128K's RS232 and MIDI),
    ld (s_mix),a                ;   no tone, no noise
    ld e,a
    ld a,7
    jp s_ay

;; s_chp: A = a channel, 0-2 -> IX = its block. All but IX kept.
s_chp:
    ld ix,s_chan
    or a
    ret z
    push af
    push de
    ld de,S_CSIZE
.l:
    add ix,de
    dec a
    jr nz,.l
    pop de
    pop af
    ret

;; s_scale: HL = a period, the CPC's -> HL = the Spectrum's: * 227 / 128.
;; BC kept, DE lost.
s_scale:
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

;; SND_QUEUE: HL = a sound record -> carry if it was queued; no carry if a
;; channel's queue is full (the caller tries again)
m_snd_queue:
    push bc
    push de
    push hl
    push ix
    push hl
    ; the sound as the queue keeps it
    inc hl
    ld b,(hl)                   ; B = the volume envelope
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = the period
    inc hl
    push hl
    ex de,hl
    call s_scale
    ld a,h
    cp 16
    jr c,.p
    ld hl,4095
.p:
    ld (s_new),hl
    pop hl
    ld a,(hl)                   ; the noise
    inc hl
    push hl
    ld l,a
    ld h,0
    call s_scale
    ld a,h
    or a
    jr nz,.nmax
    ld a,l
    cp 32
    jr c,.ns
.nmax:
    ld a,31
.ns:
    ld (s_new+2),a
    pop hl
    ld a,(hl)                   ; the volume
    inc hl
    inc b
    dec b
    jr nz,.v                    ; with an envelope: as it is
    add a,a
    cp 16
    jr c,.v
    xor a                       ; (8 and more without one: silent)
.v:
    and 15
    ld (s_new+3),a
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; the duration
    ld a,d
    or e
    jr z,.d0
    bit 7,d
    jr z,.d
.d0:
    ld de,20                    ; none, or the envelope's: 0.2 s
.d:
    ld (s_new+4),de
    pop hl
    ld c,(hl)                   ; C = the channels
    di
    bit 7,c
    jr z,.room
    ld b,0                      ; flushed first: queues emptied, sounds
.fl:                            ;   stopped (s_tick silences them)
    ld a,b
    call s_ch_in
    jr z,.fn
    call s_chp
    ld (ix+0),0
    ld (ix+2),0
    ld (ix+3),0
.fn:
    inc b
    ld a,b
    cp 3
    jr c,.fl
.room:
    ld b,0                      ; room in every channel's queue?
.r:
    ld a,b
    call s_ch_in
    jr z,.rn
    call s_chp
    ld a,(ix+0)
    cp S_QN
    jr nc,.full
.rn:
    inc b
    ld a,b
    cp 3
    jr c,.r
    ld b,0                      ; into each
.q:
    ld a,b
    call s_ch_in
    jr z,.qn
    call s_chp
    ld a,(ix+0)
    inc (ix+0)
    ld e,a
    add a,a
    add a,e
    add a,a                     ; * S_ESIZE
    add a,4
    ld e,a
    ld d,0
    push ix
    pop hl
    add hl,de
    ex de,hl
    ld hl,s_new
    push bc
    ld bc,S_ESIZE
    ldir
    pop bc
.qn:
    inc b
    ld a,b
    cp 3
    jr c,.q
    ei
    scf
    jr .out
.full:
    ei
    or a
.out:
    pop ix
    pop hl
    pop de
    pop bc
    ret

;; s_ch_in: A = a channel, C = the record's channels -> NZ if it is one of
;; them. BC kept.
s_ch_in:
    push bc
    inc a
    ld b,a
    ld a,c
.s:
    rrca
    djnz .s
    rlca
    and 1
    pop bc
    ret

;; s_tick: from the interrupt, 50 times a second: each channel's sound
;; counts down, and when it ends the next begins (or the channel goes
;; quiet)
s_tick:
    ld b,0
.ch:
    ld a,b
    call s_chp
    ld a,(ix+1)
    or a
    jr z,.start
    ld l,(ix+2)
    ld h,(ix+3)
    ld de,3
    or a
    sbc hl,de
    jr c,.start                 ; 2/100 s or less was left: it ends
    inc hl
    ld (ix+2),l
    ld (ix+3),h
    jp .next
.start:
    ld a,(ix+0)
    or a
    jp z,.quiet
    dec (ix+0)
    ld (ix+1),1
    push bc
    push ix
    pop hl
    ld de,4
    add hl,de                   ; HL = the first in the queue
    ld a,b
    add a,a
    ld e,(hl)
    call s_ay                   ; the period: fine,
    inc hl
    inc a
    ld e,(hl)
    call s_ay                   ;   coarse
    inc hl
    ld c,(hl)                   ; C = the noise
    inc hl
    ld a,b
    add a,8
    ld e,(hl)
    call s_ay                   ; the volume
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (ix+2),e
    ld (ix+3),d
    ld a,c
    or a
    jr z,.nn
    ld e,a
    ld a,6
    call s_ay                   ; the noise's period
.nn:
    ; the mixer: tone on if the period is not 0, noise on if there is some
    ld a,b
    call s_bit                  ; E = the channel's tone bit
    ld a,(s_mix)
    or e
    ld d,a
    ld a,e
    rlca
    rlca
    rlca                        ; its noise bit
    or d
    ld d,a                      ; D: both off
    ld l,(ix+4)
    ld h,(ix+5)
    ld a,h
    or l
    jr z,.nt
    ld a,e
    cpl
    and d
    ld d,a                      ; the tone on
.nt:
    inc c
    dec c
    jr z,.nz
    ld a,e
    rlca
    rlca
    rlca
    cpl
    and d
    ld d,a                      ; the noise on
.nz:
    ld a,d
    ld (s_mix),a
    ld e,a
    ld a,7
    call s_ay
    ; the queue moves up
    push ix
    pop hl
    ld de,4
    add hl,de
    ld d,h
    ld e,l
    ld bc,S_ESIZE
    add hl,bc
    ld bc,(S_QN-1)*S_ESIZE
    ldir
    pop bc
    jr .next
.quiet:
    ld a,(ix+1)
    or a
    jr z,.next
    ld (ix+1),0
    ld a,b
    add a,8
    ld e,0
    call s_ay                   ; its volume 0
.next:
    inc b
    ld a,b
    cp 3
    jp c,.ch
    ret

;; s_bit: A = a channel -> A = E = its tone bit in the mixer (1, 2, 4)
s_bit:
    ld e,1
    or a
    jr z,.d
.l:
    sla e
    dec a
    jr nz,.l
.d:
    ld a,e
    ret
