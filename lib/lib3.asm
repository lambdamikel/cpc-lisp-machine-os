;; CPC Lisp -- the library ROMs, part 2: the functions and macros written in
;; Lisp (lisp.lsp), read from here the first time each is used. lib/lib.asm
;; explains the parts.

    include "core.inc"
    include "macros.asm"
    include "part.asm"

    org PART_ORG
    db 1                        ; a background ROM
    db 0,9,7                    ; mark, version, modification: 0.97
    dw lib_names
    jp lib_init                 ; the ROM walk: nothing to do

    defs PART_HDR-$,0
    db "CPCLISPLIB"
    dw BUILD_ID
    dw lib_buckets
    dw lib_boot
    dw lib_dispatch
    dw 0                        ; no line editor
    dw 0                        ; no number routines
    assert $ == PART_HDR+LH_PART
    db 2                        ; part 2

lib_names:
    db "LISP LIBRARY ","3"+#80
    db 0

    include "common.asm"
;@lisp lisp.lsp
    include "lib3tab.asm"

lib_end:
    print "LIBRARY 3 used: ",lib_end-PART_ORG," bytes, free: ",PART_ORG+#4000-lib_end
    assert lib_end <= PART_ORG+#4000
    defs PART_ORG+#4000-$,#FF
