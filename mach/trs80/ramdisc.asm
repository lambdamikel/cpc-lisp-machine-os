;; CPC Lisp -- the RAM disc, on the TRS-80: none yet (X-MEM/80's spare
;; pages may hold one). lib/disc.asm includes this.

;; RDISC_IS: TOKBUF holds a file name -> NZ: never ours
RDISC_IS:
    or 1
    ret
;; RDISC_IN, RDISC_OUT: never open
RDISC_IN:
RDISC_OUT:
    or a
    ret
;; RDISC_CAT: nothing to list
RDISC_CAT:
    ret
