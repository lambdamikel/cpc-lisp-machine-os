;; CPC Lisp -- the library ROMs, part 1: floats, format, sort, lists and
;; sequences, coerce, and what is dropped when the cells run out (short).
;; lib/lib.asm explains the parts.

    include "core.inc"
    include "macros.asm"
    include "part.asm"

    org PART_ORG
    db 1                        ; a background ROM
    db 0,9,7                    ; mark, version, modification: 0.97
    dw lib_names
    jp lib_init                 ; the ROM walk: nothing to do
    jp rsx_bootlisp             ; |BOOTLISP, from BASIC (mach/cpc/card.asm)

    defs PART_HDR-$,0
    db "CPCLISPLIB"
    dw BUILD_ID
    dw lib_buckets
    dw lib_boot
    dw lib_dispatch
    dw 0                        ; no line editor
    dw lib_numbers              ; the number routines
    assert $ == PART_HDR+LH_PART
    db 1                        ; part 1

lib_names:
    db "LISP LIBRARY ","2"+#80
    db "BOOTLIS","P"+#80
    db 0

    include "common.asm"
    include "float.asm"
    include "short.asm"
    include "lazy.asm"
    include "farray.asm"
    include "format.asm"
    include "seq.asm"
    include "lists.asm"
    include "structs.asm"
    include "seqfn.asm"
    include "card.asm"
;@lisp lazy.lsp
    include "lib2tab.asm"

lib_end:
    print "LIBRARY 2 used: ",lib_end-PART_ORG," bytes, free: ",PART_ORG+#4000-lib_end
    assert lib_end <= PART_ORG+#4000
    defs PART_ORG+#4000-$,#FF
