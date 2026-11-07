;; CPC Lisp -- the demo ROM, library part 3: programs in Lisp (demo.lsp),
;; read from here the first time each is called; (demo) lists them. Like
;; the other parts it may be left out. lib/lib.asm explains the parts.

    include "core.inc"
    include "macros.asm"

    org #C000
    db 1                        ; a background ROM
    db 0,2,0
    dw lib_names
    jp lib_init                 ; the ROM walk: nothing to do

    defs LIBHDR-$,0
    db "CPCLISPLIB"
    dw BUILD_ID
    dw lib_buckets
    dw lib_boot
    dw lib_dispatch
    dw 0                        ; no line editor
    dw 0                        ; no number routines
    assert $ == LIBHDR+LH_PART
    db 3                        ; part 3

lib_names:
    db "LISP DEMO","S"+#80
    db 0

    include "common.asm"
;@lisp demo.lsp
    include "demotab.asm"

lib_end:
    print "DEMOS used: ",lib_end-#C000," bytes, free: ",#10000-lib_end
    assert lib_end <= #10000
    defs #10000-$,#FF
