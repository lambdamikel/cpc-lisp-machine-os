;; CPC Lisp -- the library ROMs, part 1: floats, format, sort, lists and
;; sequences, coerce. lib/lib.asm explains the parts.

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
    dw lib_numbers              ; the number routines
    assert $ == LIBHDR+LH_PART
    db 1                        ; part 1

lib_names:
    db "LISP LIBRARY ","2"+#80
    db 0

    include "common.asm"
    include "float.asm"
    include "format.asm"
    include "seq.asm"
    include "lists.asm"
    include "structs.asm"
    include "seqfn.asm"
    include "lib2tab.asm"

lib_end:
    print "LIBRARY 2 used: ",lib_end-#C000," bytes, free: ",#10000-lib_end
    assert lib_end <= #10000
    defs #10000-$,#FF
