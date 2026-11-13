;; CPC Lisp -- where this library part runs: PART_ORG, its header at
;; PART_HDR. As the core has it (LIB_ORG, LIBHDR), unless tools/build.sh
;; gives this part an address of its own (the Model 4's parts are at &8000
;; or &C000: mach/trs80m4/liborgs).
    ifndef PART_ORG
PART_ORG          equ LIB_ORG
    endif
    assert PART_ORG == #C000 || PART_ORG == #4000 || PART_ORG == #8000
PART_HDR          equ PART_ORG+#10
