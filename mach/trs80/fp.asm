;; CPC Lisp -- calling the maths routines on the TRS-80 (lib/float.asm
;; includes this): they are entries of the jumpblock, so FM is a plain
;; call, and fp_callix jumps to the one in IX.
fp_callix:
    jp (ix)
