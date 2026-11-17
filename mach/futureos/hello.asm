;; A first FutureOS program built by this repository's toolchain: prints a
;; line in the desktop's lower part and goes back to the desktop, as TFM's
;; HELLO.MAX does. `rasm hello.asm` -> hello.bin, run at &9000 (the
;; desktop's RUN, 3: jump into RAM, &9000, configuration &C0).

    include "fos.asm"

    org #9000
start:
    ld bc,(FOS_ROMNUM_A)        ; ROM A in
    out (c),c
    ld bc,#7F82                 ; mode 2, both ROMs on: the lower ROM's
    out (c),c                   ;   charset at &3800
    ld (RAMCHAR),bc
    ld hl,text
    call TERM_2
    ld hl,KLICK
    jp ROM_D

text:
    db #1E,#15,#1A              ; TFM's: the cursor to the lower part
    db "CPC Lisp's toolchain says hello",0
