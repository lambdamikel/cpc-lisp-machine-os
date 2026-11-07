;; CPC Lisp -- the extended LOOP's expander (library ROM, part 1).
;;
;; (%loop-expand clauses) -> the expansion; the macro LOOP (lib/loop.lsp)
;; calls it when its first form is a symbol. The clauses are parsed into
;; lists in a frame on the stack (IX; the GC sees them there): LET*
;; bindings, initially forms, the forms at the top of each pass (the for
;; clauses' end tests and variables), the body in clause order, the steps
;; at the end of a pass, the finally forms. Then:
;;
;;   (block name
;;     (let* bindings
;;       initially...
;;       (block %loop (return-from name (%loop top... body... steps...)))
;;       finally...
;;       result))
;;
;; A for clause that runs out leaves the inner block (%LOOP is its name),
;; so the finally forms run and the result is returned; (return x) in the
;; body leaves %LOOP's own block and returns x, past them, as in CL.
;;
;; Forms are built from templates (lp_build). Temporaries are the interned
;; symbols %0, %1... -- the same in every expansion: a nested loop's
;; shadow its outer one's, and no symbols pile up. Loop keywords are known
;; by name (or as keywords, :FOR), builtin ones (IF, AND, =...) by address.

LP_L      equ 0                 ; the clauses left
LP_BINDS  equ 2                 ; the lists, last first
LP_PRE    equ 4
LP_TOP    equ 6
LP_BODY   equ 8
LP_STEP   equ 10
LP_POST   equ 12
LP_RES    equ 14                ; the result (T for always, never)
LP_ACC    equ 16                ; the accumulator of collect, sum... without into
LP_ACCS   equ 18                ; ((variable . its tail) ...)
LP_FIRST  equ 20                ; the first-pass flag (for x = a then b)
LP_V      equ 22                ; the clause's variable,
LP_W      equ 24                ;   and working values
LP_W1     equ 26
LP_W2     equ 28
LP_W3     equ 30
LP_A      equ 32                ; template arguments A0-A7:
LP_STOP   equ LP_A+12           ;   A6 the stop form (A6 the result at the end),
LP_NAME   equ LP_A+14           ;   A7 the block's name
LP_NT     equ LP_A+16           ; temporaries made so far
LP_FL     equ LP_A+17           ; for ... from: bit 0 down, bit 1 the end left out
LP_SIZE   equ LP_A+18

LP_TP     equ LIBSCR+0          ; lp_build: where it is in the template

;; template codes; anything else is a byte of a word (after TQ_S)
TQ_L      equ #F0               ; a list begins
TQ_E      equ #F1               ;   and ends
TQ_S      equ #F2               ; the next word: a symbol, NIL, a fixnum
TQ_A      equ #E0               ; + n: argument n
TQ_P      equ #E8               ; + n: argument n's elements, spliced in

macro SETA n
    ld (ix+LP_A+2*{n}),l
    ld (ix+LP_A+2*{n}+1),h
mend
macro GETA n
    ld l,(ix+LP_A+2*{n})
    ld h,(ix+LP_A+2*{n}+1)
mend
macro GETF slot
    ld l,(ix+{slot})
    ld h,(ix+{slot}+1)
mend
macro PUTF slot
    ld (ix+{slot}),l
    ld (ix+{slot}+1),h
mend
macro BUILD t
    ld hl,{t}
    call lp_build
mend
macro PUSHTO slot
    ld c,{slot}
    call lp_push
mend

;; the keywords' codes. FROM to BY, and COLLECT to MIN, run on.
K_FOR     equ 1
K_IN      equ 2
K_ON      equ 3
K_ACROSS  equ 4
K_EQ      equ 5
K_THEN    equ 6
K_BEING   equ 7
K_FROM    equ 8
K_DOWNFROM equ 9
K_TO      equ 10
K_BELOW   equ 11
K_DOWNTO  equ 12
K_ABOVE   equ 13
K_BY      equ 14
K_WITH    equ 15
K_AND     equ 16
K_REPEAT  equ 17
K_WHILE   equ 18
K_UNTIL   equ 19
K_NAMED   equ 20
K_INITIALLY equ 21
K_FINALLY equ 22
K_DO      equ 23
K_COLLECT equ 24
K_APPEND  equ 25
K_NCONC   equ 26
K_SUM     equ 27
K_COUNT   equ 28
K_MAX     equ 29
K_MIN     equ 30
K_INTO    equ 31
K_WHEN    equ 32
K_UNLESS  equ 33
K_ELSE    equ 34
K_END     equ 35
K_RETURN  equ 36
K_ALWAYS  equ 37
K_NEVER   equ 38
K_THEREIS equ 39
K_EACH    equ 40
K_HKEY    equ 41
K_HVAL    equ 42
K_OF      equ 43
K_USING   equ 44

lp_m_short:  db "LOOP: a clause is cut short",0
lp_m_bad:    db "LOOP: not a clause I know:",0
lp_m_for:    db "LOOP: what FOR does not know:",0

;@ %LOOP-EXPAND 1 1 lf_loop_expand
lf_loop_expand:
    ex de,hl                    ; DE = the clauses
    ld hl,NIL
    ld b,LP_SIZE/2
.z:
    push hl
    djnz .z
    ld ix,0
    add ix,sp
    ld (ix+LP_L),e
    ld (ix+LP_L+1),d
    BUILD lt_stop
    PUTF LP_STOP
.main:
    ld a,(ix+LP_L)
    or (ix+LP_L+1)
    jp z,.done
    call lp_next
    call lp_kw
    cp K_NAMED
    jr z,.named
    cp K_WITH
    jp z,.with
    cp K_FOR
    jr z,.for
    cp K_REPEAT
    jr z,.repeat
    cp K_WHILE
    ld de,lt_unlessstop
    jp z,.test
    cp K_UNTIL
    ld de,lt_whenstop
    jp z,.test
    cp K_ALWAYS
    ld de,lt_always
    jp z,.tf
    cp K_NEVER
    ld de,lt_never
    jp z,.tf
    cp K_THEREIS
    ld de,lt_thereis
    jp z,.thereis
    cp K_INITIALLY
    ld c,LP_PRE
    jp z,.forms
    cp K_FINALLY
    ld c,LP_POST
    jp z,.forms
    call lp_clause              ; a body clause
.body:
    PUSHTO LP_BODY
    jr .main
.named:
    call lp_next
    PUTF LP_NAME
    jr .main
.for:
    call lp_for
    ld a,K_AND
    call lp_take
    jr z,.for
    jr .main
.repeat:                        ; (when (<= %n 0) stop) (setq %n (1- %n))
    call lp_temp
    PUTF LP_W1
    call lp_next
    ex de,hl
    GETF LP_W1
    call lp_bind
    GETF LP_W1
    SETA 0
    ld hl,1                     ; 0
    SETA 1
    ld hl,S_LE
    SETA 2
    BUILD lt_cmpstop
    PUSHTO LP_TOP
    ld hl,S_ONEMINUS
    SETA 2
    BUILD lt_call1
    SETA 1
    BUILD lt_setq
    PUSHTO LP_TOP
    jp .main
.tf:                            ; always, never: the result is T then
    ld hl,S_T
    PUTF LP_RES
.thereis:
.test:                          ; DE = the template for the form after it
    push de
    call lp_next
    SETA 0
    call lp_symc
    SETA 3
    pop hl
    call lp_build
    jp .body
.forms:                         ; C = the list they go on
    push bc
    call lp_forms
.f:
    ld a,h
    or l
    jr z,.fe
    pop bc
    push bc
    push hl
    LDHLI
    call lp_push
    pop hl
    CDRHL
    jr .f
.fe:
    pop bc
    jp .main
.with:
    call lp_next
    PUTF LP_W1                  ; the variable (or a pattern)
    ld a,K_EQ
    call lp_take
    jr nz,.wnil
    call lp_next
    ex de,hl                    ; DE = its value
    GETF LP_W1
    ld a,l
    and 3
    jr nz,.wsym
    ld a,h
    or l
    jr z,.wsym
    push de                     ; a pattern: bound to NIL, set before the
    call lp_bindvars            ;   first pass
    pop de
    GETF LP_W1
    call lp_dset
    PUSHTO LP_PRE
    jr .wand
.wsym:
    call lp_bind
    jr .wand
.wnil:
    GETF LP_W1
    call lp_bindvars
.wand:
    ld a,K_AND
    call lp_take
    jr z,.with
    jp .main
.done:
    GETF LP_FIRST               ; the first pass is over at its end
    ld a,h
    or l
    jr z,.nofirst
    SETA 0
    ld hl,NIL
    SETA 1
    BUILD lt_setq
    PUSHTO LP_STEP
.nofirst:
    ld bc,LP_BINDS*256+0        ; the lists in order: A0-A5
.rev:
    push bc
    ld c,b
    ld b,0
    push ix
    pop hl
    add hl,bc
    LDHLI
    ld de,NIL
    SCORE nreverse_onto
    pop bc
    push bc
    ld a,c
    add a,a
    add a,LP_A
    ld e,a
    ld d,0
    push ix
    pop bc
    ex de,hl
    add hl,bc
    ld (hl),e
    inc hl
    ld (hl),d
    pop bc
    inc b
    inc b
    inc c
    ld a,c
    cp 6
    jr nz,.rev
    GETF LP_ACC                 ; A6: the result
    ld a,h
    or l
    jr nz,.res
    GETF LP_RES
.res:
    SETA 6
    BUILD lt_final
    ex de,hl
    ld hl,LP_SIZE
    add hl,sp
    ld sp,hl
    ex de,hl
    ret

;; ---------------------------------------------------------------------------
;; FOR CLAUSES

lp_for:
    call lp_next
    PUTF LP_V
    call lp_next
    call lp_kw
    cp K_IN
    jr z,.in
    cp K_ON
    jr z,.in
    cp K_ACROSS
    jp z,.across
    cp K_EQ
    jp z,.eq
    cp K_BEING
    jp z,.being
    cp K_FROM
    jr c,.bad
    cp K_BY+1
    jp c,.num
.bad:
    ld de,lp_m_for
    ex de,hl
    jp lib_error
.in:                            ; for v in list [by f], for v on list
    push af
    call lp_temp
    PUTF LP_W1                  ; the tail
    call lp_next
    ex de,hl
    GETF LP_W1
    call lp_bind
    ld hl,NIL
    PUTF LP_W2
    ld a,K_BY
    call lp_take
    jr nz,.noby
    call lp_next
    PUTF LP_W2
.noby:
    GETF LP_V
    call lp_bindvars
    GETF LP_W1                  ; (when (atom tail) stop)
    SETA 0
    BUILD lt_atomstop
    PUSHTO LP_TOP
    pop af
    GETF LP_W1
    cp K_ON
    jr z,.on
    SETA 0
    BUILD lt_car                ; in: (car tail)
.on:
    ex de,hl
    GETF LP_V
    call lp_dset
    PUSHTO LP_TOP
    GETF LP_W1                  ; (setq tail (cdr tail)), or (funcall f tail)
    SETA 0
    GETF LP_W2
    ld a,h
    or l
    jr z,.cdr
    SETA 1
    BUILD lt_funcall
    jr .step
.cdr:
    BUILD lt_cdr
.step:
    SETA 1
    GETF LP_W1
    SETA 0
    BUILD lt_setq
    PUSHTO LP_STEP
    ret
.across:                        ; for v across vector
    call lp_temp
    PUTF LP_W1                  ; the vector
    call lp_temp
    PUTF LP_W2                  ; the index
    call lp_next
    ex de,hl
    GETF LP_W1
    call lp_bind
    ld de,1
    GETF LP_W2
    call lp_bind
    GETF LP_V
    call lp_bindvars
    GETF LP_W2                  ; (when (>= i (length vector)) stop)
    SETA 0
    GETF LP_W1
    SETA 1
    BUILD lt_lenstop
    PUSHTO LP_TOP
    ld hl,S_AREF                ; v = (aref vector i)
    SETA 2
    GETF LP_W1
    SETA 0
    GETF LP_W2
    SETA 1
    BUILD lt_call2
    ex de,hl
    GETF LP_V
    call lp_dset
    PUSHTO LP_TOP
    ld hl,S_ONEPLUS             ; (setq i (1+ i))
    SETA 2
    GETF LP_W2
    SETA 0
    BUILD lt_call1
    SETA 1
    BUILD lt_setq
    PUSHTO LP_STEP
    ret
.eq:                            ; for v = a [then b]
    call lp_next
    PUTF LP_W1
    GETF LP_V
    call lp_bindvars
    ld a,K_THEN
    call lp_take
    jr nz,.plain
    call lp_next
    PUTF LP_W2
    GETF LP_FIRST
    ld a,h
    or l
    jr nz,.hasfirst
    call lp_temp
    PUTF LP_FIRST
    ld de,S_T
    call lp_bind
.hasfirst:
    GETF LP_FIRST               ; (if first a b)
    SETA 0
    GETF LP_W1
    SETA 1
    GETF LP_W2
    SETA 2
    BUILD lt_if3
    jr .set
.plain:
    GETF LP_W1
.set:
    ex de,hl
    GETF LP_V
    call lp_dset
    PUSHTO LP_TOP
    ret
.being:                         ; for k being the hash-keys of h [using
    call lp_next                ;   (hash-value v)], or hash-values
    call lp_next
    call lp_kw
    cp K_HKEY
    jr z,.hk
    cp K_HVAL
    jp nz,.bad
.hk:
    cp K_HKEY                   ; W3: what v is: (caar tail) for a key
    ld hl,S_CAAR
    jr z,.which
    ld hl,S_CDAR
.which:
    PUTF LP_W3
    call lp_next                ; of, in
    call lp_next
    SETA 0                      ; (%hash-pairs h)
    ld hl,lp_s_hpairs
    call lp_sym
    SETA 2
    BUILD lt_call1
    push hl
    call lp_temp
    PUTF LP_W1                  ; the tail
    pop de
    call lp_bind
    ld hl,NIL
    PUTF LP_W2
    ld a,K_USING
    call lp_take
    jr nz,.nousing
    call lp_next                ; (hash-value v)
    CDRHL
    LDHLI
    PUTF LP_W2
    call lp_bindvars
.nousing:
    GETF LP_V
    call lp_bindvars
    GETF LP_W1
    SETA 0
    BUILD lt_atomstop
    PUSHTO LP_TOP
    GETF LP_W3                  ; v = (caar tail) or (cdar tail)
    ld de,LP_V
    call .pair
    GETF LP_W2
    ld a,h
    or l
    jr z,.hstep
    GETF LP_W3                  ; and the other: cdar for caar, caar for cdar
    ld de,S_CAAR
    or a
    sbc hl,de
    ld hl,S_CAAR
    jr nz,.other
    ld hl,S_CDAR
.other:
    ld de,LP_W2
    call .pair
.hstep:
    GETF LP_W1
    SETA 0
    BUILD lt_cdr
    SETA 1
    GETF LP_W1
    SETA 0
    BUILD lt_setq
    PUSHTO LP_STEP
    ret
.pair:                          ; HL = caar or cdar, DE = the slot of the
    SETA 2                      ;   variable: set from the tail
    push de
    GETF LP_W1
    SETA 0
    BUILD lt_call1
    pop bc
    ex de,hl
    push ix
    pop hl
    add hl,bc
    LDHLI
    call lp_dset
    PUSHTO LP_TOP
    ret
.num:                           ; for v from a to b by c, and the rest
    ex de,hl                    ; the preposition goes back
    GETF LP_L
    ex de,hl
    SCORE cons
    PUTF LP_L
    ld hl,1                     ; from 0
    PUTF LP_W1
    ld hl,NIL                   ; no end
    PUTF LP_W2
    ld hl,3                     ; by 1
    PUTF LP_W3
    ld (ix+LP_FL),0
.prep:
    GETF LP_L
    ld a,h
    or l
    jr z,.nums
    LDHLI
    call lp_kw
    cp K_FROM
    jr c,.nums
    cp K_BY+1
    jr nc,.nums
    push af
    call lp_next
    call lp_next                ; its value
    pop af
    cp K_FROM
    jr z,.from
    cp K_DOWNFROM
    jr z,.downfrom
    cp K_BY
    jr z,.by
    PUTF LP_W2                  ; to, below, downto, above
    cp K_TO
    jr z,.prep
    cp K_BELOW
    jr z,.excl
    set 0,(ix+LP_FL)            ; downto, above
    cp K_DOWNTO
    jr z,.prep
.excl:
    set 1,(ix+LP_FL)
    jr .prep
.downfrom:
    set 0,(ix+LP_FL)
.from:
    PUTF LP_W1
    jr .prep
.by:
    PUTF LP_W3
    jr .prep
.nums:
    GETF LP_W1                  ; (v start)
    ex de,hl
    GETF LP_V
    call lp_bind
    GETF LP_W2
    ld a,h
    or l
    jr z,.noend
    call lp_temp                ; (%n end), (when (> v %n) stop)
    PUTF LP_W
    GETF LP_W2
    ex de,hl
    GETF LP_W
    call lp_bind
    ld a,(ix+LP_FL)
    ld hl,lp_cmps
    ld e,a
    ld d,0
    add hl,de
    add hl,de
    LDHLI
    SETA 2
    GETF LP_V
    SETA 0
    GETF LP_W
    SETA 1
    BUILD lt_cmpstop
    PUSHTO LP_TOP
.noend:
    GETF LP_W3                  ; a by that is not a number: its value once
    bit 0,l
    jr nz,.byn
    call lp_temp
    PUTF LP_W
    GETF LP_W3
    ex de,hl
    GETF LP_W
    call lp_bind
    GETF LP_W
    PUTF LP_W3
.byn:
    ld hl,S_PLUS                ; (setq v (+ v by))
    bit 0,(ix+LP_FL)
    jr z,.up
    ld hl,S_MINUS
.up:
    SETA 2
    GETF LP_V
    SETA 0
    GETF LP_W3
    SETA 1
    BUILD lt_call2
    SETA 1
    GETF LP_V
    SETA 0
    BUILD lt_setq
    PUSHTO LP_STEP
    ret
lp_cmps:                        ; stop when: up, down; past the end, at it
    dw S_GT, S_LT, S_GE, S_LE

;; ---------------------------------------------------------------------------
;; BODY CLAUSES: A = the keyword's code (HL the keyword) -> HL = a form

lp_clause1:                     ; the next clause, keyword and all
    call lp_next
    call lp_kw
lp_clause:
    cp K_DO
    jr z,.do
    cp K_COLLECT
    jr c,.bad
    cp K_MIN+1
    jp c,lp_accum
    cp K_WHEN
    jp z,lp_cond
    cp K_UNLESS
    jp z,lp_cond
    cp K_RETURN
    jr z,.ret
.bad:
    ld de,lp_m_bad
    ex de,hl
    jp lib_error
.do:
    call lp_forms
    SETA 0
    BUILD lt_progn
    ret
.ret:
    call lp_next
    SETA 0
    BUILD lt_ret
    ret

;; lp_accum: collect, append, nconc, sum, count, maximize, minimize x
;; [into v]
lp_accum:
    push af
    call lp_next
    PUTF LP_W1                  ; x
    ld hl,NIL
    PUTF LP_W2
    ld a,K_INTO
    call lp_take
    jr nz,.noin
    call lp_next
    PUTF LP_W2
.noin:
    GETF LP_W2                  ; the variable: into's, or the loop's own
    ld a,h
    or l
    jr nz,.var
    GETF LP_ACC
    ld a,h
    or l
    jr nz,.var
    call lp_temp
    PUTF LP_ACC
.var:
    PUTF LP_W2
    call lp_tail                ; its tail, if it has been met
    jr nz,.known
    pop af                      ; new: (v 0) or (v nil), (tail nil)
    push af
    ld de,NIL
    cp K_SUM
    jr z,.zero
    cp K_COUNT
    jr nz,.init
.zero:
    ld de,1
.init:
    GETF LP_W2
    call lp_bind
    call lp_temp
    PUTF LP_W3
    ld de,NIL
    call lp_bind
    GETF LP_W3                  ; (v . tail) onto the list of them
    ex de,hl
    GETF LP_W2
    SCORE cons
    PUSHTO LP_ACCS
    GETF LP_W3
.known:
    SETA 1                      ; A0 v, A1 its tail, A2 x, A3 %C
    GETF LP_W2
    SETA 0
    GETF LP_W1
    SETA 2
    call lp_symc
    SETA 3
    pop af
    cp K_COLLECT
    ld hl,lt_collect
    jr z,.b
    cp K_SUM
    ld hl,lt_sum
    jr z,.b
    cp K_COUNT
    ld hl,lt_count
    jr z,.b
    cp K_NCONC
    ld hl,lt_nconc
    jr z,.b
    cp K_APPEND
    jr z,.append
    ld hl,S_GT                  ; maximize, minimize
    cp K_MAX
    jr z,.mm
    ld hl,S_LT
.mm:
    SETA 4
    ld hl,lt_max
.b:
    jp lp_build
.append:                        ; nconc of (append x nil): a copy
    BUILD lt_append1
    SETA 2
    ld hl,lt_nconc
    jr .b

;; lp_tail: LP_W2 = an accumulator -> NZ and HL = its tail if known, else Z
lp_tail:
    GETF LP_ACCS
.l:
    ld a,h
    or l
    ret z
    push hl
    LDHLI
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld a,e
    cp (ix+LP_W2)
    jr nz,.n
    ld a,d
    cp (ix+LP_W2+1)
    jr nz,.n
    LDHLI
    pop de
    ld a,1
    or a
    ret
.n:
    pop hl
    CDRHL
    jr .l

;; lp_cond: when (if), unless: test clause {and clause} [else clause {and
;; clause}] [end]
lp_cond:
    push af
    call lp_next
    push hl                     ; the test
    ld hl,NIL
    push hl                     ; the clauses if true
.then:
    call lp_clause1
    pop de
    SCORE cons
    push hl
    ld a,K_AND
    call lp_take
    jr z,.then
    ld hl,NIL
    push hl                     ; the clauses if false
    ld a,K_ELSE
    call lp_take
    jr nz,.end
.else:
    call lp_clause1
    pop de
    SCORE cons
    push hl
    ld a,K_AND
    call lp_take
    jr z,.else
.end:
    ld a,K_END
    call lp_take
    pop hl
    ld de,NIL
    SCORE nreverse_onto
    SETA 2
    pop hl
    ld de,NIL
    SCORE nreverse_onto
    SETA 1
    pop hl
    SETA 0
    pop af
    cp K_UNLESS
    jr nz,.if
    BUILD lt_not
    SETA 0
.if:
    BUILD lt_if
    ret

;; ---------------------------------------------------------------------------
;; HELPERS

;; lp_next -> HL = the next clause element; an error if there is none
lp_next:
    GETF LP_L
    ld a,h
    or l
    jr z,.short
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI
    PUTF LP_L
    ex de,hl
    ret
.short:
    ld hl,lp_m_short
    ld de,UNBOUND
    jp lib_error

;; lp_take: A = a keyword's code -> Z if it is next, and it is taken; NZ
;; if not (nothing taken)
lp_take:
    ld c,a
    GETF LP_L
    ld a,h
    or l
    jr z,.no
    LDHLI
    push bc
    call lp_kw
    pop bc
    cp c
    ret nz
    call lp_next
    xor a
    ret
.no:
    inc a                       ; NZ
    ret

;; lp_forms -> HL = the compound forms that come next, in order
lp_forms:
    ld hl,NIL
    push hl
.l:
    GETF LP_L
    ld a,h
    or l
    jr z,.e
    LDHLI
    ld a,h
    or l
    jr z,.e
    ld a,l
    and 3
    jr nz,.e
    call lp_next
    pop de
    SCORE cons
    push hl
    jr .l
.e:
    pop hl
    ld de,NIL
    SCORE nreverse_onto
    ret

;; lp_push: C = a list's slot, HL = a form -> the form onto the list
lp_push:
    ex de,hl
    ld b,0
    push ix
    pop hl
    add hl,bc
    push hl
    LDHLI                       ; HL = the list
    ex de,hl                    ; HL = the form, DE = the list
    SCORE cons
    ex de,hl
    pop hl
    ld (hl),e
    inc hl
    ld (hl),d
    ret

;; lp_bind: HL = a variable, DE = its first value -> (v value) onto the
;; bindings
lp_bind:
    SETA 0
    ex de,hl
    SETA 1
    BUILD lt_pair
    PUSHTO LP_BINDS
    ret

;; lp_bindvars: HL = a variable, or a pattern of them -> each bound to NIL
lp_bindvars:
    ld a,h
    or l
    ret z
    ld a,l
    and 3
    jr nz,.sym
    push hl
    LDHLI
    call lp_bindvars
    pop hl
    CDRHL
    jr lp_bindvars
.sym:
    ld de,NIL
    jr lp_bind

;; lp_dset: HL = a variable or a pattern, DE = a form -> HL = a form that
;; sets it (them) from the form's value
lp_dset:
    ld a,l
    and 3
    jr z,.tree
.sym:
    SETA 0                      ; (setq v form)
    ex de,hl
    SETA 1
    BUILD lt_setq
    ret
.tree:
    ld a,h
    or l
    jr z,.sym                   ; (NIL: (setq nil ...) is an error, as CL's)
    push de
    push hl
    ld hl,NIL
    PUTF LP_W
    call lp_symd
    ex de,hl                    ; DE = %D, what the pattern takes apart
    pop hl
    push de
    call lp_walk
    GETF LP_W                   ; (let ((%D form)) (setq v1 f1 v2 f2...))
    ld de,NIL
    SCORE nreverse_onto
    SETA 1
    pop hl
    SETA 3
    pop hl
    SETA 0
    BUILD lt_dlet
    ret

;; lp_walk: HL = a pattern, DE = the form for its value -> each variable
;; and the form for its part onto LP_W (backwards)
lp_walk:
    ld a,h
    or l
    ret z
    ld a,l
    and 3
    jr z,.cons
    push de
    PUSHTO LP_W                 ; the variable,
    pop hl
    PUSHTO LP_W                 ;   then its form
    ret
.cons:
    push hl
    push de
    ex de,hl
    SETA 0
    BUILD lt_car
    ex de,hl                    ; DE = (car form)
    pop bc
    pop hl
    push hl
    push bc
    LDHLI
    call lp_walk
    pop hl                      ; the form
    SETA 0
    BUILD lt_cdr
    ex de,hl                    ; DE = (cdr form)
    pop hl
    CDRHL
    jr lp_walk

;; lp_temp -> HL = the next temporary, %0, %1...
lp_temp:
    ld a,(ix+LP_NT)
    inc (ix+LP_NT)
    ld hl,TOKBUF
    ld (hl),"%"
    inc hl
    cp 10
    jr c,.one
    ld b,"0"-1
.t:
    inc b
    sub 10
    jr nc,.t
    add a,10
    ld (hl),b
    inc hl
.one:
    add a,"0"
    ld (hl),a
    inc hl
    ld a,l
    sub TOKBUF and #FF
    ld b,a
    SCORE intern
    ret

;; lp_sym: HL = a name in this ROM (zero-terminated) -> HL = that symbol.
;; lp_symc, lp_symd: %C and %D, the let variables of the templates
lp_symc:
    ld hl,lp_s_c
    jr lp_sym
lp_symd:
    ld hl,lp_s_d
lp_sym:
    ld de,TOKBUF
    ld b,0
.c:
    ld a,(hl)
    or a
    jr z,.e
    ld (de),a
    inc hl
    inc de
    inc b
    jr .c
.e:
    SCORE intern
    ret
lp_s_c:      db "%C",0
lp_s_d:      db "%D",0
lp_s_hpairs: db "%HASH-PAIRS",0

;; lp_kw: HL = an object -> A = its code as a loop keyword, 0 if it is
;; none. BC, DE, HL kept.
lp_kw:
    push hl
    push de
    push bc
    call .find
    pop bc
    pop de
    pop hl
    ret
.find:
    ld a,l
    and 3
    cp 2
    jr nz,.none
    ld a,h
    cp SYM_LO/256
    jr c,.none
    cp SYM_HI/256
    jr nc,.none
    ld de,SYM_LO+2+8*NBUILTIN
    or a
    sbc hl,de
    add hl,de
    jr nc,.ram
    ld de,lp_kwb                ; a builtin: by its address
.b:
    ld a,(de)
    ld c,a
    inc de
    ld a,(de)
    ld b,a
    inc de
    or c
    ret z                       ; (A = 0: none)
    ld a,(de)
    inc de
    push af
    ld a,l
    cp c
    jr nz,.bn
    ld a,h
    cp b
    jr nz,.bn
    pop af
    ret
.bn:
    pop af
    jr .b
.none:
    xor a
    ret
.ram:                           ; by its name, a ":" in front or not
    LDHLI
    ld c,(hl)
    inc hl
    inc hl
    ld a,(hl)
    cp ":"
    jr nz,.n
    inc hl
    dec c
.n:
    ld de,lp_kwt
.t:
    ld a,(de)
    or a
    ret z
    inc de
    push af
    push hl
    push bc
.ch:
    ld a,(de)
    and #7F
    cp (hl)
    jr nz,.skip
    ld a,(de)
    inc de
    inc hl
    dec c
    rla
    jr c,.last
    inc c
    dec c
    jr nz,.ch
    jr .skip
.last:
    inc c
    dec c
    jr nz,.next                 ; (DE is past this word already)
    pop bc
    pop hl
    pop af
    ret
.skip:
    ld a,(de)
    inc de
    rla
    jr nc,.skip
.next:
    pop bc
    pop hl
    pop af
    jr .t

lp_kwb:
    dw S_IF : db K_WHEN
    dw S_WHEN : db K_WHEN
    dw S_UNLESS : db K_UNLESS
    dw S_AND : db K_AND
    dw S_APPEND : db K_APPEND
    dw S_NUMEQ : db K_EQ
    dw S_RETURN : db K_RETURN
    dw S_THE : db K_EACH
    dw 0

lp_kwt:
    db K_FOR : str "FOR"
    db K_FOR : str "AS"
    db K_IN : str "IN"
    db K_ON : str "ON"
    db K_ACROSS : str "ACROSS"
    db K_EQ : str "="
    db K_THEN : str "THEN"
    db K_BEING : str "BEING"
    db K_FROM : str "FROM"
    db K_FROM : str "UPFROM"
    db K_DOWNFROM : str "DOWNFROM"
    db K_TO : str "TO"
    db K_TO : str "UPTO"
    db K_BELOW : str "BELOW"
    db K_DOWNTO : str "DOWNTO"
    db K_ABOVE : str "ABOVE"
    db K_BY : str "BY"
    db K_WITH : str "WITH"
    db K_AND : str "AND"
    db K_REPEAT : str "REPEAT"
    db K_WHILE : str "WHILE"
    db K_UNTIL : str "UNTIL"
    db K_NAMED : str "NAMED"
    db K_INITIALLY : str "INITIALLY"
    db K_FINALLY : str "FINALLY"
    db K_DO : str "DO"
    db K_DO : str "DOING"
    db K_COLLECT : str "COLLECT"
    db K_COLLECT : str "COLLECTING"
    db K_APPEND : str "APPEND"
    db K_APPEND : str "APPENDING"
    db K_NCONC : str "NCONC"
    db K_NCONC : str "NCONCING"
    db K_SUM : str "SUM"
    db K_SUM : str "SUMMING"
    db K_COUNT : str "COUNT"
    db K_COUNT : str "COUNTING"
    db K_MAX : str "MAXIMIZE"
    db K_MAX : str "MAXIMIZING"
    db K_MIN : str "MINIMIZE"
    db K_MIN : str "MINIMIZING"
    db K_INTO : str "INTO"
    db K_WHEN : str "WHEN"
    db K_WHEN : str "IF"
    db K_UNLESS : str "UNLESS"
    db K_ELSE : str "ELSE"
    db K_END : str "END"
    db K_RETURN : str "RETURN"
    db K_ALWAYS : str "ALWAYS"
    db K_NEVER : str "NEVER"
    db K_THEREIS : str "THEREIS"
    db K_EACH : str "EACH"
    db K_EACH : str "THE"
    db K_HKEY : str "HASH-KEY"
    db K_HKEY : str "HASH-KEYS"
    db K_HVAL : str "HASH-VALUE"
    db K_HVAL : str "HASH-VALUES"
    db K_OF : str "OF"
    db K_USING : str "USING"
    db 0

;; ---------------------------------------------------------------------------
;; TEMPLATES

;; lp_build: HL = a template -> HL = the form it makes, with the arguments
;; A0-A7 from the frame
lp_build:
    ld (LP_TP),hl
lp_item:                        ; the next item -> HL, NC; at its list's end C
    ld hl,(LP_TP)
    ld a,(hl)
    inc hl
    ld (LP_TP),hl
    cp TQ_E
    scf
    ret z
    cp TQ_L
    jr z,.list
    cp TQ_S
    jr z,.word
    call lp_arg
    or a
    ret
.word:
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld (LP_TP),hl
    ex de,hl
    or a
    ret
.list:
    ld hl,NIL
    push hl                     ; its items so far, the last first
.li:
    ld hl,(LP_TP)
    ld a,(hl)
    and #F8
    cp TQ_P
    jr z,.splice
    call lp_item
    jr c,.end
    pop de
    SCORE cons
    push hl
    jr .li
.splice:
    ld a,(hl)
    inc hl
    ld (LP_TP),hl
    call lp_arg                 ; HL = the list to splice in
.sp:
    ld a,h
    or l
    jr z,.li
    ld e,(hl)
    inc hl
    ld d,(hl)
    dec hl
    ex (sp),hl                  ; HL = the items, (SP) = the list
    ex de,hl
    SCORE cons
    ex (sp),hl
    CDRHL
    jr .sp
.end:
    pop hl
    ld de,NIL
    SCORE nreverse_onto
    or a
    ret

;; lp_arg: A = a code, its low three bits n -> HL = argument n
lp_arg:
    and 7
    add a,a
    add a,LP_A
    ld e,a
    ld d,0
    push ix
    pop hl
    add hl,de
    LDHLI
    ret

lt_stop:        ; (return-from %loop nil)
    db TQ_L,TQ_S : dw S_RETURN_FROM : db TQ_S : dw S_PLOOP : db TQ_S : dw NIL : db TQ_E
lt_pair:        ; (A0 A1)
    db TQ_L,TQ_A+0,TQ_A+1,TQ_E
lt_setq:        ; (setq A0 A1)
    db TQ_L,TQ_S : dw S_SETQ : db TQ_A+0,TQ_A+1,TQ_E
lt_car:         ; (car A0)
    db TQ_L,TQ_S : dw S_CAR : db TQ_A+0,TQ_E
lt_cdr:         ; (cdr A0)
    db TQ_L,TQ_S : dw S_CDR : db TQ_A+0,TQ_E
lt_call1:       ; (A2 A0)
    db TQ_L,TQ_A+2,TQ_A+0,TQ_E
lt_call2:       ; (A2 A0 A1)
    db TQ_L,TQ_A+2,TQ_A+0,TQ_A+1,TQ_E
lt_funcall:     ; (funcall A1 A0)
    db TQ_L,TQ_S : dw S_FUNCALL : db TQ_A+1,TQ_A+0,TQ_E
lt_atomstop:    ; (when (atom A0) A6)
    db TQ_L,TQ_S : dw S_WHEN : db TQ_L,TQ_S : dw S_ATOM : db TQ_A+0,TQ_E,TQ_A+6,TQ_E
lt_cmpstop:     ; (when (A2 A0 A1) A6)
    db TQ_L,TQ_S : dw S_WHEN : db TQ_L,TQ_A+2,TQ_A+0,TQ_A+1,TQ_E,TQ_A+6,TQ_E
lt_lenstop:     ; (when (>= A0 (length A1)) A6)
    db TQ_L,TQ_S : dw S_WHEN : db TQ_L,TQ_S : dw S_GE : db TQ_A+0
    db TQ_L,TQ_S : dw S_LENGTH : db TQ_A+1,TQ_E,TQ_E,TQ_A+6,TQ_E
lt_if3:         ; (if A0 A1 A2)
    db TQ_L,TQ_S : dw S_IF : db TQ_A+0,TQ_A+1,TQ_A+2,TQ_E
lt_whenstop:    ; (when A0 A6)
    db TQ_L,TQ_S : dw S_WHEN : db TQ_A+0,TQ_A+6,TQ_E
lt_unlessstop:  ; (unless A0 A6)
    db TQ_L,TQ_S : dw S_UNLESS : db TQ_A+0,TQ_A+6,TQ_E
lt_always:      ; (unless A0 (return-from A7 nil))
    db TQ_L,TQ_S : dw S_UNLESS : db TQ_A+0
    db TQ_L,TQ_S : dw S_RETURN_FROM : db TQ_A+7,TQ_S : dw NIL : db TQ_E,TQ_E
lt_never:       ; (when A0 (return-from A7 nil))
    db TQ_L,TQ_S : dw S_WHEN : db TQ_A+0
    db TQ_L,TQ_S : dw S_RETURN_FROM : db TQ_A+7,TQ_S : dw NIL : db TQ_E,TQ_E
lt_thereis:     ; (let ((A3 A0)) (when A3 (return-from A7 A3)))
    db TQ_L,TQ_S : dw S_LET : db TQ_L,TQ_L,TQ_A+3,TQ_A+0,TQ_E,TQ_E
    db TQ_L,TQ_S : dw S_WHEN : db TQ_A+3
    db TQ_L,TQ_S : dw S_RETURN_FROM : db TQ_A+7,TQ_A+3,TQ_E,TQ_E,TQ_E
lt_ret:         ; (return-from A7 A0)
    db TQ_L,TQ_S : dw S_RETURN_FROM : db TQ_A+7,TQ_A+0,TQ_E
lt_progn:       ; (progn . A0)
    db TQ_L,TQ_S : dw S_PROGN : db TQ_P+0,TQ_E
lt_not:         ; (not A0)
    db TQ_L,TQ_S : dw S_NOT : db TQ_A+0,TQ_E
lt_if:          ; (if A0 (progn . A1) (progn . A2))
    db TQ_L,TQ_S : dw S_IF : db TQ_A+0
    db TQ_L,TQ_S : dw S_PROGN : db TQ_P+1,TQ_E
    db TQ_L,TQ_S : dw S_PROGN : db TQ_P+2,TQ_E,TQ_E
lt_dlet:        ; (let ((A3 A0)) (setq . A1))
    db TQ_L,TQ_S : dw S_LET : db TQ_L,TQ_L,TQ_A+3,TQ_A+0,TQ_E,TQ_E
    db TQ_L,TQ_S : dw S_SETQ : db TQ_P+1,TQ_E,TQ_E
lt_collect:     ; (setq A1 (if A1 (cdr (rplacd A1 (list A2))) (setq A0 (list A2))))
    db TQ_L,TQ_S : dw S_SETQ : db TQ_A+1
    db TQ_L,TQ_S : dw S_IF : db TQ_A+1
    db TQ_L,TQ_S : dw S_CDR : db TQ_L,TQ_S : dw S_RPLACD : db TQ_A+1
    db TQ_L,TQ_S : dw S_LIST : db TQ_A+2,TQ_E,TQ_E,TQ_E
    db TQ_L,TQ_S : dw S_SETQ : db TQ_A+0,TQ_L,TQ_S : dw S_LIST : db TQ_A+2,TQ_E,TQ_E
    db TQ_E,TQ_E
lt_append1:     ; (append A2 nil)
    db TQ_L,TQ_S : dw S_APPEND : db TQ_A+2,TQ_S : dw NIL : db TQ_E
lt_nconc:       ; (let ((A3 A2)) (when A3 (setq A1 (last (if A1 (cdr (rplacd A1 A3))
                ;   (setq A0 A3))))))
    db TQ_L,TQ_S : dw S_LET : db TQ_L,TQ_L,TQ_A+3,TQ_A+2,TQ_E,TQ_E
    db TQ_L,TQ_S : dw S_WHEN : db TQ_A+3
    db TQ_L,TQ_S : dw S_SETQ : db TQ_A+1,TQ_L,TQ_S : dw S_LAST
    db TQ_L,TQ_S : dw S_IF : db TQ_A+1
    db TQ_L,TQ_S : dw S_CDR : db TQ_L,TQ_S : dw S_RPLACD : db TQ_A+1,TQ_A+3,TQ_E,TQ_E
    db TQ_L,TQ_S : dw S_SETQ : db TQ_A+0,TQ_A+3,TQ_E
    db TQ_E,TQ_E,TQ_E,TQ_E,TQ_E
lt_sum:         ; (setq A0 (+ A0 A2))
    db TQ_L,TQ_S : dw S_SETQ : db TQ_A+0
    db TQ_L,TQ_S : dw S_PLUS : db TQ_A+0,TQ_A+2,TQ_E,TQ_E
lt_count:       ; (when A2 (setq A0 (1+ A0)))
    db TQ_L,TQ_S : dw S_WHEN : db TQ_A+2
    db TQ_L,TQ_S : dw S_SETQ : db TQ_A+0,TQ_L,TQ_S : dw S_ONEPLUS : db TQ_A+0,TQ_E,TQ_E
    db TQ_E
lt_max:         ; (let ((A3 A2)) (when (or (null A0) (A4 A3 A0)) (setq A0 A3)))
    db TQ_L,TQ_S : dw S_LET : db TQ_L,TQ_L,TQ_A+3,TQ_A+2,TQ_E,TQ_E
    db TQ_L,TQ_S : dw S_WHEN
    db TQ_L,TQ_S : dw S_OR : db TQ_L,TQ_S : dw S_NULL : db TQ_A+0,TQ_E
    db TQ_L,TQ_A+4,TQ_A+3,TQ_A+0,TQ_E,TQ_E
    db TQ_L,TQ_S : dw S_SETQ : db TQ_A+0,TQ_A+3,TQ_E
    db TQ_E,TQ_E
lt_final:       ; (block A7 (let* A0 ,@A1 (block %loop (return-from A7
                ;   (%loop ,@A2 ,@A3 ,@A4))) ,@A5 A6))
    db TQ_L,TQ_S : dw S_BLOCK : db TQ_A+7
    db TQ_L,TQ_S : dw S_LETSTAR : db TQ_A+0,TQ_P+1
    db TQ_L,TQ_S : dw S_BLOCK : db TQ_S : dw S_PLOOP
    db TQ_L,TQ_S : dw S_RETURN_FROM : db TQ_A+7
    db TQ_L,TQ_S : dw S_PLOOP : db TQ_P+2,TQ_P+3,TQ_P+4,TQ_E
    db TQ_E,TQ_E
    db TQ_P+5,TQ_A+6,TQ_E,TQ_E
