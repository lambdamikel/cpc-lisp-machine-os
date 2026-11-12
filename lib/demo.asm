;; CPC Lisp -- the demo ROM, library part 3: the extended LOOP (its macro in
;; loop.lsp, its expander native in loop.asm), more of the library in Lisp
;; (lisp2.lsp), and programs in Lisp (demo.lsp), read from here the first
;; time each is called; (demo) lists them. lib/lib.asm explains the parts.

    include "core.inc"
    include "macros.asm"

    org LIB_ORG
    db 1                        ; a background ROM
    db 0,9,5                    ; mark, version, modification: 0.95
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
    include "loop.asm"          ; the LOOP expander, native, beside its macro
;@lisp loop.lsp
;@lisp lisp2.lsp
;@lisp demo.lsp
    include "demotab.asm"

lib_end:
    print "DEMOS used: ",lib_end-LIB_ORG," bytes, free: ",LIB_ORG+#4000-lib_end
    assert lib_end <= LIB_ORG+#4000
    defs LIB_ORG+#4000-$,#FF
