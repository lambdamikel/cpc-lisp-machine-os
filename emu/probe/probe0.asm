;; Foreground probe for ROM 0: print the registers the firmware enters with.
TXT_OUTPUT        equ #BB5A
KL_ROM_WALK       equ #BCCB

    org #C000
    db 0,0,1,0
    dw names
    jp entry

names:
    db "PROBE","0"+#80
    db 0

entry:
    ld (save_sp),sp
    ld sp,#C000
    push hl
    push de
    push bc
    call KL_ROM_WALK          ; DE/HL in, updated out
    push hl
    push de
    ld hl,msg
    call puts
    ld b,5                    ; BC DE HL at entry, DE HL after the walk -- popped in reverse
    ld hl,(save_sp)
    call hex4
    ld a,13
    call TXT_OUTPUT
    ld a,10
    call TXT_OUTPUT
.l: pop hl
    call hex4
    djnz .l
.halt:
    jr .halt

hex4:
    push bc
    ld a,h
    call hex2
    ld a,l
    call hex2
    ld a," "
    call TXT_OUTPUT
    pop bc
    ret

puts:
    ld a,(hl)
    or a
    ret z
    inc hl
    call TXT_OUTPUT
    jr puts

hex2:
    push af
    rrca
    rrca
    rrca
    rrca
    call hex1
    pop af
hex1:
    and 15
    add a,"0"
    cp "9"+1
    jr c,.out
    add a,7
.out:
    jp TXT_OUTPUT

msg: db "PROBE0 SP:",0
save_sp equ #0080       ; scratch, just for the probe

    defs #4000-($-#C000),#FF
