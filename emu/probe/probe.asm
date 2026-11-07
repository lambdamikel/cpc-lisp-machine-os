;; Probe ROM: which ROM number does MAME give each ROM-box socket?
;; A background ROM whose init prints the number it was selected as (KL CURR
;; SELECTION) and the memory limits the ROM walk handed it.
;;
;;     rasm -DTAG=0x41 probe.asm -o ../build/PROBEA     (TAG is the letter shown)

KL_CURR_SELECTION equ #B912
TXT_OUTPUT        equ #BB5A

    org #C000
    db 1,0,1,0
    dw names
    jp init

names:
    db "PROBE RO","M"+#80
    db 0

init:
    push hl
    push de
    ld a,TAG
    call TXT_OUTPUT
    ld hl,msg1
    call puts
    call KL_CURR_SELECTION
    call hex2
    ld hl,msg2
    call puts
    pop de
    push de
    ld a,d
    call hex2
    ld a,e
    call hex2
    ld hl,msg3
    call puts
    pop de
    pop hl
    push hl
    push de
    ld a,h
    call hex2
    ld a,l
    call hex2
    ld a,13
    call TXT_OUTPUT
    ld a,10
    call TXT_OUTPUT
    pop de
    pop hl
    scf
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

msg1: db " ROM=",0
msg2: db " DE=",0
msg3: db " HL=",0

    defs #4000-($-#C000),#FF
