;; CPC Lisp -- the evaluator.
;;
;; eval is a loop: forms in tail position (the last of a body, an if's
;; branch, a macro's expansion, a closure's body) are not recursed into but
;; jumped to, so a tail-recursive function runs in constant stack.
;;
;; THE EVAL FRAME: eval pushes the caller's V_ENV, and ev_done pops it back
;; before returning. Inside, anything may replace V_ENV -- a closure call
;; does -- without saving it. Special forms are jumped to with this frame on
;; the stack and HL = their argument forms, and leave by jp ev_done (value
;; in HL) or jp ev_loop (a form to evaluate in tail position).
;;
;; A CALL evaluates the function (for a symbol, its lexical or global
;; definition), pushes it, then pushes each argument's value, left to right:
;;
;;     [arg n-1] ... [arg 0] [function] [saved env] [return]
;;
;; and apply_core takes it from there with C = n. A subr with fixed arity up
;; to 3 gets its arguments in HL, DE, BC; any other gets HL = address of
;; arg 0 (the rest below it, see NEXTARG) and B = n. A closure gets them as
;; a list, bound by bind.
;;
;; The environment is an alist: (symbol . value) for a variable, and
;; ((symbol) . function) for flet/labels.

;; check_stack: error if the stack is nearly used up. Flags only.
check_stack:
    push hl
    ld hl,(V_STKLIM)
    or a
    sbc hl,sp
    pop hl
    ret c
err_stack:
    ERR m_stack

;; poll_break: count down, and every 256th call look at the ESC key
poll_break:
    push hl
    ld hl,V_BRK
    dec (hl)
    pop hl
    ret nz
;; poll_esc: was ESC pressed? Then break. All registers kept. A press
;; puts ESC's character (&FC, then the break marker &EF) in the key buffer,
;; so even a tap that came and went during a GC is seen: the first character
;; waiting is looked at and put back if it is anything else. Held down, ESC
;; is seen by KM TEST KEY too, behind typed-ahead keys.
poll_esc:
    push af
    push bc
    push de
    push hl
    call KM_READ_CHAR
    jr nc,.key
    cp #FC
    jr z,.esc
    cp #EF
    jr z,.esc
    call KM_CHAR_RETURN
.key:
    ld a,KEY_ESC
    call KM_TEST_KEY
    jr .test
.esc:
    or a                        ; NZ: A is &FC or &EF
.test:
    pop hl
    pop de
    pop bc
    jr nz,do_break
    pop af
    ret
do_break:
    pop af
    ; wait for the key to come up, then empty the buffer of what it typed
.up:
    ld a,KEY_ESC
    call KM_TEST_KEY
    jr nz,.up
    call drain_keys
    ERR m_break

drain_keys:
    call KM_READ_CHAR
    jr c,drain_keys
    ret

;; eval: HL = form -> HL = value
eval:
    ex de,hl
    ld hl,(V_STKLIM)
    or a
    sbc hl,sp
    jr nc,err_stack
    ex de,hl
    ld de,(V_ENV)
    push de
ev_loop:
    bit 0,l
    jr nz,ev_done               ; fixnum
    ld a,l
    and 2
    jr nz,.tag10
    ld a,h
    or l
    jr z,ev_done                ; NIL
    jp ev_cons
.tag10:
    ld a,h
    cp SYM_LO >> 8
    jr c,ev_done                ; character
    cp SYM_HI >> 8
    jr nc,ev_done               ; string, function...
    call sym_value
ev_done:
    pop de
    ld (V_ENV),de
    ret

err_unbound:
    ld hl,m_unbound
    jp error

;; sym_value: HL = a symbol -> HL = its value: its lexical binding, else its
;; global value (an error if it has none). DE = the symbol; BC corrupt.
sym_value:
    ex de,hl
    ld hl,(V_ENV)
.walk:
    ld a,h
    or l
    jr z,.global
    ld c,(hl)
    inc hl
    ld b,(hl)                   ; BC = an entry (symbol . value)
    inc hl
    ld a,(bc)
    cp e
    jr nz,.next
    inc bc
    ld a,(bc)
    cp d
    jr z,.found
.next:
    LDHLI
    jr .walk
.found:
    inc bc
    ld a,(bc)
    ld l,a
    inc bc
    ld a,(bc)
    ld h,a
    ret
.global:
    ld hl,SY_VALUE
    add hl,de
    LDHLI
    ld a,h
    cp UNBOUND >> 8
    ret nz
    ld a,l
    cp UNBOUND and #FF
    ret nz
    jr err_unbound

;; env_lookup: HL = symbol -> HL = its binding (symbol . value) in V_ENV, or
;; NIL. BC, DE kept.
env_lookup:
    push de
    push bc
    ex de,hl
    ld hl,(V_ENV)
.walk:
    ld a,h
    or l
    jr z,.done
    ld c,(hl)
    inc hl
    ld b,(hl)                   ; BC = entry
    inc hl
    ld a,(bc)
    cp e
    jr nz,.next
    inc bc
    ld a,(bc)
    dec bc
    cp d
    jr nz,.next
    ld l,c
    ld h,b
    jr .done
.next:
    LDHLI
    jr .walk
.done:
    pop bc
    pop de
    ret

;; env_fn_entry: DE = symbol -> HL = its flet/labels binding ((sym) . fn),
;; or NIL. BC, DE kept.
env_fn_entry:
    push bc
    ld hl,(V_ENV)
.walk:
    ld a,h
    or l
    jr z,.done
    ld c,(hl)
    inc hl
    ld b,(hl)                   ; BC = entry
    inc hl
    push hl
    ld l,c
    ld h,b
    LDHLI                       ; key
    ld a,l
    and 3
    jr nz,.next                 ; a symbol: a variable
    ld a,(hl)
    cp e
    jr nz,.next
    inc hl
    ld a,(hl)
    cp d
    jr nz,.next
    pop hl
    ld l,c
    ld h,b
    jr .done
.next:
    pop hl
    LDHLI
    jr .walk
.done:
    pop bc
    ret

ev_cons:
    ld (V_MFORM),hl             ; (for .macro)
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = operator
    inc hl
    ld c,(hl)
    inc hl
    ld b,(hl)                   ; BC = argument forms
    ld a,e                      ; a symbol? (is_symbol)
    and 7
    cp 2
    jp nz,.notsym
    ld a,d
    cp SYM_LO >> 8
    jp c,.notsym
    cp SYM_HI >> 8
    jp nc,.notsym
    ; a local function (flet, labels) -- if it ever was one: FNBOUND
    sub SYM_LO >> 8
    ld h,a
    ld a,e
    srl h
    rra
    srl h
    rra
    srl h
    rra
    ld l,a
    ld a,h
    add a,FNBOUND >> 8
    ld h,a
    ld a,(hl)
    or a
    jr z,.global
    call env_fn_entry
    ld a,h
    or l
    jr z,.global
    CDRHL
    jp .call
.global:
    ld hl,SY_FUNC
    add hl,de
    LDHLI
.fn:
    ld a,h
    cp #C0
    jr c,.notrom
    dec hl
    dec hl
    ld a,(hl)
    inc hl
    inc hl
    cp HDR_FSUBR and #FF
    jr nz,.call
    ; a special form: its code, with HL = the argument forms
    LDHLI
    push hl
    ld l,c
    ld h,b
    ret
.notrom:
    cp CELL_LO >> 8
    jr c,.undef
    dec hl
    dec hl
    ld a,(hl)
    inc hl
    inc hl
    cp HDR_CLOSURE and #FF
    jr z,.call
    cp HDR_MACRO and #FF
    jr z,.macro
    cp HDR_AUTOLOAD and #FF
    jr nz,.call
    push bc                     ; Lisp text in the library: read it first
    ld bc,(V_MFORM)             ;   (resolve_fn wants DE, the symbol)
    push bc
    call resolve_fn
    pop bc
    ld (V_MFORM),bc
    pop bc
    jr .fn
.macro:
    ; a macro: expand, keep the expansion in the call (mx_displace), and
    ; evaluate it here
    ld de,(V_MFORM)
    push de                     ; the call, while the macro runs
    push hl                     ; the macro
    LDHLI                       ; its closure
    ld e,c
    ld d,b
    call apply_list             ; the expansion
    pop de
    ex (sp),hl                  ; it on the stack, HL = the call
    call mx_displace
    pop hl
    jp ev_loop
.undef:
    ld hl,m_undef
    jp error
.notsym:
    ; ((lambda ...) args)
    ld a,e
    and 3
    jr nz,.bad
    ld a,d
    or e
    jr z,.bad
    ex de,hl
    push hl
    LDHLI
    ld de,S_LAMBDA
    or a
    sbc hl,de
    pop hl
    jr nz,.bad1
    CDRHL
    push bc
    call make_closure
    pop bc
.call:
    ; HL = function, BC = argument forms
    push hl
    ld l,c
    ld h,b
    ld c,0
.args:
    ld a,h
    or l
    jr z,.apply
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI                       ; DE = form, HL = rest
    ; what evaluates to itself, and a variable, without eval
    bit 0,e
    jr nz,.self                 ; a fixnum
    ld a,e
    and 2
    jr z,.cons
    ld a,d
    cp SYM_LO >> 8
    jr c,.self                  ; a character
    cp SYM_HI >> 8
    jr nc,.self                 ; a string, a function...
    push bc
    push hl
    ex de,hl
    call sym_value
    jr .value
.cons:
    ld a,d
    or e
    jr z,.self                  ; NIL
    push bc
    push hl
    ex de,hl
    call eval
.value:
    pop de
    pop bc
    push hl
    inc c
    jr z,.many
    ex de,hl
    jr .args
.self:
    push de
    inc c
    jr nz,.args
    jr .many
.apply:
    jp apply_core
.bad1:
    ex de,hl
.bad:
    ld hl,m_badcall
    jp error
.many:
    ERR m_toomany

;; apply_core: C = n, with the call laid out on the stack as above. A call
;; starts with no multiple values: VALUES (or FLOOR...) sets them as it ends.
apply_core:
    xor a
    ld (V_MVN),a
    ld l,c
    ld h,0
    add hl,hl
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = function
    ld a,e
    and 3
    cp 2
    jp nz,.notfn
    ld a,d
    cp #C0
    jr nc,.rom
    cp CELL_LO >> 8
    jp c,.notfn
    ld h,d
    ld l,e
    dec hl
    dec hl
    ld a,(hl)
    inc hl
    ld b,(hl)
    dec b
    dec b
    dec b
    dec b
    jp nz,.notfn                ; the header's high byte is 4
    cp HDR_CLOSURE and #FF
    jp z,apply_closure_stack
    cp HDR_LSUBR and #FF
    jp nz,.notfn
    ; a library function: its dispatcher checks the arguments
    ld (V_LIBFN),de
    ld de,LIBCALL
    ld a,255
    ld b,0
    jr .check
.rom:
    ld a,e                      ; FUNCALL: its first argument is the function
    cp (E_FUNCALL+2) and #FF    ; -- the arguments move up one, over FUNCALL,
    jr nz,.subr                 ; and the call is that one's (no list built)
    ld a,d
    cp (E_FUNCALL+2) >> 8
    jr nz,.subr
    ld a,c
    or a
    jr z,.subr                  ; (funcall): FUNCALL says what is wrong
    dec hl
    dec hl
    ld a,(hl)                   ; arg 0's high byte
    inc hl
    inc hl
    cp CELL_LO >> 8
    jr c,.subr                  ; a symbol: FUNCALL looks it up
    ld d,h
    ld e,l                      ; to the function's high byte,
    dec hl
    dec hl                      ;   from arg 0's
    push bc
    ld b,0
    sla c
    rl b
    lddr
    pop bc
    inc sp
    inc sp
    dec c
    jp apply_core
.subr:
    ld h,d
    ld l,e
    dec hl
    dec hl
    ld a,(hl)
    cp HDR_SUBR and #FF
    jp nz,.notfn
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = code
    inc hl
    ld b,(hl)                   ; min
    inc hl
    ld a,(hl)                   ; max
.check:                         ; DE = code, B = min, A = max, C = n
    cp c
    jr c,.args
    ld h,a
    ld a,c
    cp b
    jr c,.args
    ld a,h
    cp b
    jr nz,.variadic
    cp 4
    jr nc,.variadic
    push de
    pop ix
    ld a,c
    or a
    jr z,.c0
    dec a
    jr z,.c1
    dec a
    jr z,.c2
    pop bc
.c2:
    pop de
.c1:
    pop hl
.c0:
    inc sp
    inc sp                      ; the function
    call jp_ix
    jp ev_done
.variadic:
    push de
    pop ix
    ld b,c
    ld l,c
    ld h,0
    add hl,hl
    add hl,sp
    dec hl
    dec hl                      ; HL = &arg 0
    push bc
    call jp_ix
    pop bc
    ex de,hl
    ld l,b
    ld h,0
    inc hl
    add hl,hl
    add hl,sp
    ld sp,hl                    ; drop the arguments and the function
    ex de,hl
    jp ev_done
.notfn:
    ld hl,m_notfn
    jp error
.args:
    ld l,c
    ld h,0
    add hl,hl
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld hl,m_nargs
    jp error

jp_ix:
    jp (ix)

;; apply_closure_stack: DE = closure, C = n, arguments on the stack.
;; A lambda list of plain lexical variables only (the usual case) is bound
;; straight from the stack: no argument list, no bind. Anything else -- a
;; keyword, a special or constant, a destructuring list, a dotted list, the
;; wrong count -- goes the general way, which also reports the errors.
apply_closure_stack:
    ld b,c                      ; B = n, C = arguments left
    ex de,hl
    LDHLI                       ; (code . env)
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = code
    inc hl
    LDHLI
    ld (V_ENV),hl
    ex de,hl
    LDHLI                       ; HL = the lambda list
.fl:
    ld a,h
    or l
    jr z,.fend
    ld a,l
    and 3
    jr nz,.slow                 ; dotted
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI
    push hl                     ; the rest
    ex de,hl                    ; HL = the parameter
    ld a,l
    and 7
    cp 2
    jr nz,.slow1
    ld a,h
    cp SYM_LO >> 8
    jr c,.slow1
    cp SYM_HI >> 8
    jr nc,.slow1
    dec hl
    dec hl
    ld a,(hl)
    inc hl
    inc hl
    and SF_SPECIAL or SF_CONST  ; (the &-keywords are constants)
    jr nz,.slow1
    ld a,c
    or a
    jr z,.slow1                 ; more parameters than arguments
    dec c
    ex de,hl                    ; DE = the parameter
    ld l,c
    ld h,0
    add hl,hl
    add hl,sp
    inc hl
    inc hl                      ; past the rest: &the argument
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ex de,hl                    ; HL = parameter, DE = value
    call cons
    ld de,(V_ENV)
    call cons
    ld (V_ENV),hl
    pop hl
    jr .fl
.fend:
    ld a,c
    or a
    jr nz,.slow                 ; more arguments than parameters
    ld l,b
    ld h,a
    add hl,hl
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; the closure
    inc hl
    ld sp,hl                    ; drop the arguments and the function
    ex de,hl
    LDHLI
    LDHLI                       ; its code
    CDRHL                       ; the body
    jp ev_progn
.slow1:
    pop hl
.slow:
    ld c,b
    ld l,b
    ld h,0
    add hl,hl
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = the closure again
    push de
    ld de,NIL
    ld a,c
    or a
    jr z,.built
    ld b,c
    ld hl,2
    add hl,sp                   ; the last argument
.l:
    push hl
    LDHLI
    call cons
    ex de,hl
    pop hl
    inc hl
    inc hl
    djnz .l
.built:
    pop hl                      ; the closure
    ld (V_T1),hl
    ld (V_T2),de
    ld l,c
    ld h,0
    inc hl
    add hl,hl
    add hl,sp
    ld sp,hl                    ; drop the arguments and the function
    ld de,(V_T1)
    ld hl,(V_T2)
    ; fall through

;; apply_closure_tail: DE = closure, HL = argument list, under an eval frame
apply_closure_tail:
    push hl
    ex de,hl
    LDHLI                       ; (code . env)
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = code: (lambda-list . body)
    inc hl
    LDHLI
    ld (V_ENV),hl
    pop bc                      ; the arguments
    push de
    ld hl,(V_SPECS)
    push hl
    ex de,hl
    LDHLI                       ; the lambda list
    call bind
    pop de
    pop hl
    CDRHL                       ; the body
    jp let_body

;; let_body: HL = body, DE = V_SPECS before the bindings. Without special
;; bindings the body is a tail; with them it is run, and they are undone.
let_body:
    push hl
    ld hl,(V_SPECS)
    or a
    sbc hl,de
    pop hl
    jp z,ev_progn
    push de
    call progn
    pop de
    call unwind_specs
    jp ev_done

;; apply_list: HL = function (or a symbol naming one), DE = list of
;; arguments -> HL = value. For natives that call functions. The arguments
;; go onto the stack as a call's do, so a closure binds them from there.
apply_list:
    ld bc,(V_ENV)
    push bc                     ; an eval frame
    call coerce_fn
    push hl
    ex de,hl
    ld c,0
.spread:
    ld a,h
    or l
    jr z,.go
    ld a,l
    and 3
    jr nz,.go
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI
    push de
    inc c
    jr nz,.spread
    jp ev_cons.many             ; 256 or more
.go:
    jp apply_core

;; apply1: HL = function, DE = one argument -> HL = value. apply2: and BC
;; a second. No list is made.
apply1:
    push de
    call coerce_fn
    pop de
    push hl
    ld hl,(V_ENV)
    ex (sp),hl                  ; an eval frame
    push hl                     ; the function
    push de
    ld c,1
    jp apply_core
apply2:
    push bc
    push de
    call coerce_fn
    pop de
    pop bc
    push hl
    ld hl,(V_ENV)
    ex (sp),hl
    push hl
    push de
    push bc
    ld c,2
    jp apply_core

;; coerce_fn: HL = a function or a symbol with a global one -> HL = the
;; function. Errors on anything else. BC, DE kept.
coerce_fn:
    push hl                     ; for the error
    call is_symbol
    jr nz,.check
    push bc
    push de
    ex de,hl
    ld hl,SY_FUNC
    add hl,de
    LDHLI
    call resolve_fn
    pop de
    pop bc
.check:
    call is_function
    jr nz,.bad
    inc sp
    inc sp
    ret
.bad:
    pop de
    ld hl,m_notfn
    jp error

;; is_function: HL -> Z if it is a subr or a closure. All kept.
is_function:
    ld a,l
    and 3
    cp 2
    ret nz
    ld a,h
    cp CELL_LO >> 8
    jr c,.no
    push hl
    dec hl
    dec hl
    ld a,(hl)
    pop hl
    cp HDR_SUBR and #FF
    jr z,.rom
    cp HDR_LSUBR and #FF
    jr z,.cell
    cp HDR_CLOSURE and #FF
    ret nz
.cell:
    ld a,h
    cp #C0
    jr nc,.no
    cp a
    ret
.rom:
    ld a,h
    cp #C0
    jr c,.no
    cp a
    ret
.no:
    or 1
    ret

;; make_closure: HL = (lambda-list . body) -> HL = a closure over V_ENV
make_closure:
    ld de,(V_ENV)
    call cons
    ex de,hl
    ld hl,HDR_CLOSURE
    jp alloc_typed

;; ===========================================================================
;; BINDING

;; bind: HL = lambda list, BC = list of argument values. Adds the bindings to
;; V_ENV (and V_SPECS for special variables). A list where a variable is
;; expected is matched against its argument, recursively.
bind:
    push ix
    ld ix,-8
    add ix,sp
    ld sp,ix
    ld (ix+0),l                 ; lambda list still to do
    ld (ix+1),h
    ld (ix+2),c                 ; arguments still to bind
    ld (ix+3),b
    ld (ix+4),0                 ; 0 required, 1 &optional, 2 &rest, 3 &aux,
                                ; 4 after &rest, 5 &key; (ix+6) the keys
.loop:
    ld l,(ix+0)
    ld h,(ix+1)
    ld a,h
    or l
    jp z,.end
    ld a,l
    and 3
    jp nz,.dotted
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI
    ld (ix+0),l
    ld (ix+1),h
    ex de,hl                    ; HL = the parameter
    ld a,h                      ; a lambda-list keyword? (they are together)
    cp S_AMP_OPTIONAL >> 8
    jr nz,.k4
    ld a,l
    cp S_AMP_OPTIONAL and #FF
    jr c,.k4
    cp (S_AMP_AUX and #FF)+1
    jr nc,.k4
    ld de,S_AMP_OPTIONAL
    call cmp_hl_de
    jr nz,.k1
    ld (ix+4),1
    jr .loop
.k1:
    ld de,S_AMP_REST
    call cmp_hl_de
    jr z,.krest
    ld de,S_AMP_BODY
    call cmp_hl_de
    jr nz,.k2
.krest:
    ld (ix+4),2
    jr .loop
.k2:
    ld de,S_AMP_AUX
    call cmp_hl_de
    jr nz,.k3
    ld (ix+4),3
    jr .loop
.k3:
    ld de,S_AMP_KEY
    call cmp_hl_de
    jr nz,.k4
    ld a,(ix+4)                 ; the keys: what &rest took, or the rest
    cp 4
    jr z,.krest2
    ld a,(ix+2)
    ld (ix+6),a
    ld a,(ix+3)
    ld (ix+7),a
    ld (ix+2),0
    ld (ix+3),0
.krest2:
    ld (ix+4),5
    jp .loop
.k4:
    ld a,(ix+4)
    or a
    jr z,.req
    dec a
    jr z,.opt
    dec a
    jp z,.rest
    dec a
    jp z,.aux
    dec a
    jp z,.badll
    jp .key
.req:
    call .take
    jp c,.few
    ld a,l
    and 3
    jr nz,.var
    ld a,h
    or l
    jr z,.var
    ld c,e                      ; destructure
    ld b,d
    push ix
    call bind
    pop ix
    jp .loop
.var:
    call bind_var
    jp .loop
.opt:
    push hl                     ; the spec: var, or (var [default [svar]])
    call .take
;; the spec on the stack, DE = the value given, or carry if none was
.optkey:
    jr nc,.optval
    pop hl
    push hl
    ld de,NIL
    call is_symbol
    jr z,.optnil
    call cdr
    call car
    push ix
    call eval
    pop ix
    ex de,hl
.optnil:
    ld bc,NIL
    jr .optbind
.optval:
    ld bc,S_T
.optbind:
    pop hl
    push bc                     ; supplied-p
    push hl                     ; the spec
    call is_symbol
    jr z,.optsym
    call car
    call .kvar
.optsym:
    call bind_var
    pop hl
    pop de
    call is_symbol
    jp z,.loop
    call cdr
    call cdr
    call car                    ; svar
    ld a,h
    or l
    jp z,.loop
    call bind_var
    jp .loop
.rest:
    ld e,(ix+2)
    ld d,(ix+3)
    ld (ix+6),e                 ; for &key after it
    ld (ix+7),d
    ld (ix+2),0
    ld (ix+3),0
    ld (ix+4),4
    call bind_var
    jp .loop
.aux:
    push hl
    ld de,NIL
    call is_symbol
    jr z,.auxsym
    call cdr
    call car
    push ix
    call eval
    pop ix
    ex de,hl
    pop hl
    push hl
    call car
    jr .auxbind
.auxsym:
.auxbind:
    pop bc
    call bind_var
    jp .loop
.dotted:
    ld e,(ix+2)
    ld d,(ix+3)
    ld (ix+2),0
    ld (ix+3),0
    call bind_var
.end:
    ld a,(ix+2)
    or (ix+3)
    jp nz,.many
    ld hl,8
    add hl,sp
    ld sp,hl
    pop ix
    ret
;; the next argument -> DE, or carry if there is none. HL kept.
.take:
    ld e,(ix+2)
    ld d,(ix+3)
    ld a,d
    or e
    scf
    ret z
    push hl
    ex de,hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI
    ld (ix+2),l
    ld (ix+3),h
    pop hl
    or a
    ret
;; &key: the spec is var, (var [default [svar]]) or ((keyword var) ...).
;; The value follows the first keyword in the keys that matches: one given
;; is compared by eq, else the name must be ":" and var's. Keys nobody asks
;; for are let be (as if &allow-other-keys); so is that word itself.
.key:
    push hl                     ; the spec
    call is_symbol
    jr z,.ks
    call car                    ; var, or (keyword var)
.ks:
    ld a,l
    and 3
    jr nz,.kname
    call car                    ; the keyword
    ex de,hl
    ld c,0
    jr .kfind
.kname:
    push hl                     ; &allow-other-keys: nothing to bind
    LDHLI
    inc hl
    inc hl
    ld a,(hl)
    pop hl
    cp "&"
    jr nz,.kn
    pop hl
    jp .loop
.kn:
    ex de,hl                    ; DE = var
    ld c,1
.kfind:
    ld l,(ix+6)
    ld h,(ix+7)
.kl:
    ld a,l
    and 3
    scf
    jr nz,.kdone
    ld a,h
    or l
    scf
    jr z,.kdone                 ; not there
    push hl
    LDHLI
    call .kmatch
    pop hl
    CDRHL                       ; (value . rest)
    jr z,.kfound
    ld a,h
    or l
    scf
    jr z,.kdone
    CDRHL
    jr .kl
.kfound:
    ld a,h
    or l
    scf
    jr z,.kdone
    LDHLI
    ex de,hl
    or a
.kdone:
    jp .optkey
;; .kmatch: HL = a key given, DE = the keyword (C = 0) or the var (C = 1)
;; -> Z if they match. BC, DE kept
.kmatch:
    bit 0,c
    jp z,cmp_hl_de
    call is_symbol
    ret nz
    push de
    push bc
    push hl
    ex de,hl
    call str_data               ; the var's name
    ex (sp),hl
    push bc
    call str_data               ; the key's
    pop de
    inc de
    ex de,hl
    or a
    sbc hl,bc
    ex de,hl
    pop de
    jr nz,.kmno
    ld a,(hl)
    cp ":"
    jr nz,.kmno
    inc hl
    dec bc
.kmc:
    ld a,b
    or c
    jr z,.kmno                  ; all the same: Z
    ld a,(de)
    cp (hl)
    jr nz,.kmno
    inc hl
    inc de
    dec bc
    jr .kmc
.kmno:
    pop bc
    pop de
    ret
;; .kvar: HL = var, or (keyword var) -> the var
.kvar:
    ld a,l
    and 3
    ret nz
    ld a,h
    or l
    ret z
    call cdr
    jp car
.few:
    ERR m_few
.many:
    ERR m_many
.badll:
    ERR m_badll

;; bind_var: HL = symbol, DE = value. Lexical unless the symbol is special.
bind_var:
    call check_var
    push hl
    dec hl
    dec hl
    ld a,(hl)
    pop hl
    and SF_SPECIAL
    jr nz,.special
    call cons
    ld de,(V_ENV)
    call cons
    ld (V_ENV),hl
    ret
.special:
    push de
    push hl
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; the old value
    pop hl
    push hl
    call cons                   ; (sym . old)
    ld de,(V_SPECS)
    call cons
    ld (V_SPECS),hl
    pop hl
    pop de
    inc hl
    inc hl
    ld (hl),e
    inc hl
    ld (hl),d
    ret

;; check_var: HL must be a symbol that is not a constant. All kept.
check_var:
    call is_symbol
    jr nz,.bad
    push hl
    dec hl
    dec hl
    ld a,(hl)
    pop hl
    and SF_CONST
    ret z
    ex de,hl
    ld hl,m_const
    jp error
.bad:
    ex de,hl
    ld hl,m_notvar
    jp error

;; set_var: HL = symbol, DE = value. The innermost lexical binding, or else
;; the global value.
set_var:
    call check_var
    push hl
    call env_lookup
    ld a,h
    or l
    jr z,.global
    pop bc
    inc hl
    inc hl
    jr .store
.global:
    pop hl
    inc hl
    inc hl
.store:
    ld (hl),e
    inc hl
    ld (hl),d
    ret

;; unwind_specs: DE = the V_SPECS to go back to. Restores the old values of
;; everything bound since. HL kept.
unwind_specs:
    push hl
.loop:
    ld hl,(V_SPECS)
    or a
    sbc hl,de
    add hl,de
    jr z,.done
    push de
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = (sym . old)
    inc hl
    LDHLI
    ld (V_SPECS),hl
    ex de,hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = sym
    inc hl
    LDHLI                       ; HL = old
    ex de,hl
    inc hl
    inc hl
    ld (hl),e
    inc hl
    ld (hl),d
    pop de
    jr .loop
.done:
    pop hl
    ret

cmp_hl_de:
    or a
    sbc hl,de
    add hl,de
    ret

;; ===========================================================================
;; BODIES

;; progn: HL = forms -> HL = value of the last, NIL if none
progn:
    ld a,(V_BRK)
    dec a
    ld (V_BRK),a
    and 31
    call z,poll_esc
    ld a,h
    or l
    ret z
.loop:
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI
    push hl
    ex de,hl
    call eval
    pop de
    ld a,d
    or e
    ret z
    ex de,hl
    jr .loop

;; ev_progn: the same, from inside eval, with the last form a tail
ev_progn:
    ld a,(V_BRK)                ; ESC is looked at in every 32nd body: all
    dec a                       ; recursion and every loop runs one
    ld (V_BRK),a
    and 31
    call z,poll_esc
    ld a,h
    or l
    jp z,ev_done
.loop:
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI
    ld a,h
    or l
    jr z,.last
    push hl
    ex de,hl
    call eval
    pop hl
    jr .loop
.last:
    ex de,hl
    jp ev_loop

;; ===========================================================================
;; SPECIAL FORMS. Each is entered with HL = the argument forms, under the
;; eval frame.

;; mx_displace: HL = a macro call (op . args), DE = its macro, the
;; expansion under the return address -> the call becomes
;; (%EXPANDED (macro . expansion) op . args): the next time it is evaluated
;; the expansion is used as it is, while op is still that macro. The
;; printers show (op . args), as it was written.
mx_displace:
    push de
    push hl                     ; [call][macro][ret][expansion]
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI
    ex de,hl
    call cons                   ; (op . args): the call as it was
    ex (sp),hl
    push hl                     ; [call][copy][macro][ret][expansion]
    ld hl,8
    add hl,sp
    LDHLI
    ex de,hl                    ; DE = the expansion
    ld hl,4
    add hl,sp
    LDHLI                       ; HL = the macro
    call cons                   ; (macro . expansion)
    pop bc                      ; the call
    pop de                      ; the copy
    call cons                   ; ((macro . expansion) . copy)
    ex de,hl
    ld l,c
    ld h,b
    ld (hl),S_EXPANDED and #FF
    inc hl
    ld (hl),S_EXPANDED >> 8
    inc hl
    ld (hl),e
    inc hl
    ld (hl),d
    pop de
    ret

;; (%EXPANDED (macro . expansion) op . args): a macro call mx_displace has
;; seen. Its expansion, if op is that macro still; else the call as it was
;; (which is expanded afresh, and cached again)
sf_expanded:
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = (macro . expansion)
    inc hl
    LDHLI                       ; HL = (op . args)
    push hl
    LDHLI                       ; op
    ld bc,SY_FUNC
    add hl,bc
    LDHLI                       ; its function now
    ex de,hl
    push hl
    LDHLI                       ; the macro then
    or a
    sbc hl,de
    pop hl
    jr nz,.changed
    pop de
    CDRHL                       ; the expansion
    jp ev_loop
.changed:
    pop hl
    jp ev_loop

;; (multiple-value-list form): all the values form returns, as a list
sf_mvlist:
    call car
    xor a
    ld (V_MVN),a
    call eval
    call mv_list
    jp ev_done

;; mv_list: HL = a value just returned -> a list of all the values it came
;; with: those VALUES left, if it is their first (else they are from
;; something before it, and it is a single value)
mv_list:
    ld a,(V_MVN)
    or a
    jr z,.one
    push hl
    ld de,(V_MV1)
    or a
    sbc hl,de
    pop hl
    jr nz,.one
    dec a                       ; how many
    ld hl,NIL
    ret z                       ; (values): none
    ld de,(V_MVL)               ; the third on,
    cp 3
    jr nc,.two
    ld de,NIL
.two:
    cp 2
    jr c,.first
    ld hl,(V_MV2)               ;   the second,
    call cons
    ex de,hl
.first:
    ld hl,(V_MV1)               ;   the first
    jp cons
.one:
    ld de,NIL
    jp cons

sf_quote:
    call car
    jp ev_done

sf_function:
    call car
    call is_symbol
    jr nz,.lambda
    ex de,hl
    call env_fn_entry
    ld a,h
    or l
    jr z,.global
    CDRHL
    jp ev_done
.global:
    ld hl,SY_FUNC
    add hl,de
    LDHLI
    call resolve_fn
    call is_function
    jp z,ev_done
    ld hl,m_undef
    jp error
.lambda:
    ld a,l
    and 3
    jr nz,.bad
    ld a,h
    or l
    jr z,.bad
    push hl
    LDHLI
    ld de,S_LAMBDA
    or a
    sbc hl,de
    pop hl
    jr nz,.bad
    CDRHL
    jr sf_lambda
.bad:
    ex de,hl
    ld hl,m_notfn
    jp error
sf_lambda:
    call make_closure
    jp ev_done

sf_progn:
    jp ev_progn

sf_if:
    push hl
    call car
    call eval
    ex de,hl
    pop hl
    call cdr
    ld a,d
    or e
    jr z,.else
    call car
    jp ev_loop
.else:
    call cdr
    call car
    jp ev_loop

sf_when:
    ld c,0
    jr when_common
sf_unless:
    ld c,1
when_common:
    push hl
    push bc
    call car
    call eval
    pop bc
    ld a,h
    or l
    pop hl
    jr z,.false
    dec c
    jr z,.no
.yes:
    call cdr
    jp ev_progn
.false:
    dec c
    jr z,.yes
.no:
    ld hl,NIL
    jp ev_done

sf_and:
    ld a,h
    or l
    jr nz,.loop
    ld hl,S_T
    jp ev_done
.loop:
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI
    ld a,h
    or l
    jr z,.last
    push hl
    ex de,hl
    call eval
    ld a,h
    or l
    pop de
    jp z,ev_done
    ex de,hl
    jr .loop
.last:
    ex de,hl
    jp ev_loop

sf_or:
    ld a,h
    or l
    jp z,ev_done
.loop:
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI
    ld a,h
    or l
    jr z,.last
    push hl
    ex de,hl
    call eval
    ld a,h
    or l
    pop de
    jp nz,ev_done
    ex de,hl
    jr .loop
.last:
    ex de,hl
    jp ev_loop

sf_cond:
.loop:
    ld a,h
    or l
    jp z,ev_done
    push hl
    call car                    ; the clause
    push hl
    call car
    call eval                   ; its test
    pop de
    ld a,h
    or l
    jr z,.next
    pop bc
    ex de,hl
    call cdr
    ld a,h
    or l
    jp nz,ev_progn
    ex de,hl                    ; (test) alone: the test's value
    jp ev_done
.next:
    pop hl
    call cdr
    jr .loop

sf_setq:
    ld de,NIL
.loop:
    ld a,h
    or l
    jr z,.end
    push hl
    call cdr
    call car
    call eval
    ex de,hl
    pop hl
    push de
    push hl
    call car
    call set_var
    pop hl
    call cdr
    call cdr
    pop de
    jr .loop
.end:
    ex de,hl
    jp ev_done

sf_let:
    push hl
    ld de,(V_SPECS)
    push de
    call car
    ld c,0
.ev:
    ld a,h
    or l
    jr z,.bind
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI
    push bc
    push hl
    ex de,hl
    call is_symbol
    jr z,.sym
    push hl
    call cdr
    call car
    call eval
    ex (sp),hl
    call car
    ex de,hl
    pop hl
    jr .push
.sym:
    ex de,hl
    ld hl,NIL
.push:
    ld (V_T1),hl
    pop hl
    pop bc
    push de                     ; symbol
    ld de,(V_T1)
    push de                     ; value
    inc c
    jr .ev
.bind:
    ld a,c
    or a
    jr z,.body
.b:
    pop de
    pop hl
    push bc
    call bind_var
    pop bc
    dec c
    jr nz,.b
.body:
    pop de
    pop hl
    call cdr
    jp let_body

sf_letstar:
    push hl
    ld de,(V_SPECS)
    push de
    call car
.loop:
    ld a,h
    or l
    jr z,.body
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI
    push hl
    ex de,hl
    call is_symbol
    jr z,.sym
    push hl
    call cdr
    call car
    call eval
    ex (sp),hl
    call car
    pop de
    jr .bind
.sym:
    ld de,NIL
.bind:
    call bind_var
    pop hl
    jr .loop
.body:
    pop de
    pop hl
    call cdr
    jp let_body

;; (defun name lambda-list . body). The body is wrapped in (block name ...)
;; only if it mentions RETURN-FROM: a block frame would end tail calls.
sf_defun:
    ld c,0
    jr defun_common
sf_defmacro:
    ld c,1
defun_common:
    push bc
    push hl
    call car
    call is_symbol
    jr nz,.bad
    pop hl
    push hl
    call cdr                    ; (lambda-list . body)
    push hl
    call cdr                    ; body
    push hl
    ld de,S_RETURN_FROM
    call tree_has
    pop de                      ; body
    jr nz,.plain
    pop bc
    pop hl
    push hl
    push bc
    call car                    ; name
    call cons                   ; (name . body)
    ex de,hl
    ld hl,S_BLOCK
    call cons
    ld de,NIL
    call cons                   ; ((block name . body))
    ex de,hl
.plain:
    pop hl
    call car                    ; lambda list
    call cons                   ; (lambda-list . body)
    call make_closure
    pop de                      ; args
    pop bc
    dec c
    jr nz,.fn
    push de
    ex de,hl
    ld hl,HDR_MACRO
    call alloc_typed
    pop de
.fn:
    ex de,hl
    call car                    ; name
    push hl
    ld bc,SY_FUNC
    add hl,bc
    ld (hl),e
    inc hl
    ld (hl),d
    pop hl
    call mark_def
    jp ev_done
.bad:
    ex de,hl
    ld hl,m_notsym
    jp error

;; mark_def: HL = a symbol just defined -> its LIBDEFS bit set if library
;; text defined it (V_LIBDEF), cleared if anything else did. AF lost.
mark_def:
    push bc
    push hl
    call libdef_bit
    ld a,(V_LIBDEF)
    or a
    ld a,c
    jr z,.user
    or (hl)
    jr .put
.user:
    cpl
    and (hl)
.put:
    ld (hl),a
    pop hl
    pop bc
    ret

;; libdef_bit: HL = a symbol -> HL = its byte in LIBDEFS, C = its bit.
;; DE kept.
libdef_bit:
    push de
    ld de,-(SYM_LO+2)
    add hl,de                   ; 8 * the slot number
    ld a,l
    rrca
    rrca
    rrca
    and 7
    inc a
    ld b,a
    ld c,#80
.bit:
    rlc c
    djnz .bit                   ; C = 1 << (slot and 7)
    add hl,hl
    add hl,hl                   ; H = the slot / 8
    ld e,h
    ld d,0
    ld hl,LIBDEFS
    add hl,de
    pop de
    ret

;; tree_has: HL = tree, DE = an atom -> Z if it occurs in the tree
tree_has:
    call check_stack
.loop:
    call cmp_hl_de
    ret z
    ld a,l
    and 3
    jr nz,.no
    ld a,h
    or l
    jr z,.no
    push hl
    LDHLI
    call tree_has
    pop hl
    ret z
    CDRHL
    jr .loop
.no:
    or 1
    ret

sf_defvar:
    ld c,0
    jr defvar_common
sf_defparameter:
    ld c,1
    jr defvar_common
sf_defconstant:
    ld c,2
defvar_common:
    push hl
    call car
    call check_var
    push hl
    dec hl
    dec hl
    set 0,(hl)                  ; special
    pop hl
    ex de,hl
    pop hl
    push hl
    call cdr
    ld a,h
    or l
    jr z,.done
    ld a,c
    or a
    jr nz,.set
    push hl
    ld hl,SY_VALUE
    add hl,de
    LDHLI
    ld de,UNBOUND
    or a
    sbc hl,de
    pop hl
    jr nz,.done
.set:
    push bc
    call car
    call eval
    ex de,hl
    pop bc
    pop hl
    push hl
    call car
    push hl
    inc hl
    inc hl
    ld (hl),e
    inc hl
    ld (hl),d
    pop hl
    call mark_def
    ld a,c
    cp 2
    jr nz,.done
    dec hl
    dec hl
    set 1,(hl)                  ; constant
.done:
    pop hl
    call car
    jp ev_done

sf_quasiquote:
    call car
    call qq
    jp ev_done

;; qq: HL = a backquote template -> HL = it filled in
qq:
    call check_stack
    ld a,l
    and 3
    ret nz
    ld a,h
    or l
    ret z
    push hl
    LDHLI
    ld de,S_UNQUOTE
    or a
    sbc hl,de
    pop hl
    jr nz,.list
    call cdr
    call car
    jp eval
.list:
    push ix
    ld de,NIL
    push de
    ld ix,0
    add ix,sp                   ; (ix) = the result so far, reversed
.loop:
    ld a,h
    or l
    jr z,.finish
    ld a,l
    and 3
    jr nz,.finish               ; a dotted atom tail is itself
    push hl
    LDHLI
    ld de,S_UNQUOTE
    or a
    sbc hl,de
    pop hl
    jr z,.uqtail
    push hl
    LDHLI                       ; the element
    call is_splice
    jr z,.splice
    push ix
    call qq
    pop ix
    call .add
    pop hl
    CDRHL
    jr .loop
.splice:
    push ix
    call eval
    pop ix
.sp:
    ld a,h
    or l
    jr z,.spdone
    ld a,l
    and 3
    jr nz,.spdone
    push hl
    LDHLI
    call .add
    pop hl
    CDRHL
    jr .sp
.spdone:
    pop hl
    CDRHL
    jr .loop
.uqtail:
    call cdr
    call car
    push ix
    call eval
    pop ix
.finish:
    ex de,hl
    ld l,(ix+0)
    ld h,(ix+1)
    call nreverse_onto
    pop de
    pop ix
    ret
.add:
    ld e,(ix+0)
    ld d,(ix+1)
    call cons
    ld (ix+0),l
    ld (ix+1),h
    ret

;; is_splice: HL -> Z and HL = x if it is (unquote-splicing x)
is_splice:
    ld a,l
    and 3
    jr nz,.no
    ld a,h
    or l
    jr z,.no
    push hl
    LDHLI
    ld de,S_UNQUOTE_SPLICING
    or a
    sbc hl,de
    pop hl
    ret nz
    call cdr
    call car
    cp a
    ret
.no:
    or 1
    ret

;; nreverse_onto: HL = list, DE = tail -> HL = the list reversed in place,
;; ending in tail
nreverse_onto:
    ld a,h
    or l
    jr z,.done
.l:
    push hl
    inc hl
    inc hl
    ld c,(hl)
    ld (hl),e
    inc hl
    ld b,(hl)
    ld (hl),d
    pop de
    ld l,c
    ld h,b
    ld a,h
    or l
    jr nz,.l
.done:
    ex de,hl
    ret

;; ---------------------------------------------------------------------------
;; BLOCK, RETURN-FROM, CATCH, THROW, UNWIND-PROTECT. A frame on the stack,
;; innermost in V_BLOCKS:   SP -> [specs][env][tag][kind][previous frame]
;; kind 0 is a block, 1 a catch, 2 an unwind-protect (tag: the cleanup
;; forms, run by whatever leaves through it: a throw, a return-from, an
;; error, ESC -- toplevel runs those left), 3 an error handler.

macro PUSHFRAME                 ; BC = kind, DE = tag. HL kept.
    push hl
    ld hl,(V_BLOCKS)
    ex (sp),hl
    push bc
    push de
    ld bc,(V_ENV)
    push bc
    ld bc,(V_SPECS)
    push bc
    ld (V_BLOCKS),sp
mend

sf_block:
    push hl
    call car
    ex de,hl
    pop hl
    call cdr
    ld bc,0
    PUSHFRAME
    call progn
;; block_exit: SP = the frame, HL = the value
block_exit:
    pop de
    call unwind_specs
    pop de
    ld (V_ENV),de
    pop de
    pop de
    pop de
    ld (V_BLOCKS),de
    jp ev_done

sf_catch:
    push hl
    call car
    call eval
    ex de,hl
    pop hl
    call cdr
    ld bc,1
    PUSHFRAME
    call progn
    jr block_exit

;; (%catch-errors form): (T . its value), or (NIL . (message . objects))
;; if an error was signalled in it (see error). What the reader and printer
;; were doing is put back either way.
sf_catch_errors:
    call car
    ld a,(V_OUTMODE)
    ld b,a
    ld a,(V_INSRC)
    ld c,a
    push bc
    ld a,(V_PEEK)
    push af
    ld bc,3
    ld de,NIL
    PUSHFRAME
    call eval
    ex de,hl
    ld hl,S_T
    call cons                   ; (T . value)
catch_exit:
    pop de
    call unwind_specs
    pop de
    ld (V_ENV),de
    pop de
    pop de
    pop de
    ld (V_BLOCKS),de
    pop af
    ld (V_PEEK),a
    pop bc
    ld a,c
    ld (V_INSRC),a
    ld a,b
    ld (V_OUTMODE),a
    jp ev_done

sf_return:
    ld de,NIL
    jr return_common
sf_return_from:
    push hl
    call car
    ex de,hl
    pop hl
    call cdr
return_common:
    push de
    call car
    call eval
    pop de
    ld c,0
    jr unwind_to

sf_throw:
    push hl
    call car
    call eval
    ex (sp),hl
    call cdr
    call car
    call eval
    pop de
    ld c,1
;; unwind_to: DE = tag, C = kind, HL = value. Finds the frame and leaves
;; through it.
unwind_to:
    ld ix,(V_BLOCKS)
.find:
    ld a,ixh
    or ixl
    jr z,.none
    ld a,(ix+6)
    cp 2
    jr z,.protect
    cp c
    jr nz,.next
    ld a,(ix+4)
    cp e
    jr nz,.next
    ld a,(ix+5)
    cp d
    jr z,.found
.next:
    ld a,(ix+8)
    ld b,(ix+9)
    ld ixl,a
    ld ixh,b
    jr .find
.found:
    ld sp,ix
    ld a,c
    cp 3
    jp z,catch_exit             ; an error caught
    jp block_exit
.none:
    ld hl,m_noblock
    jp error
;; an unwind-protect on the way: leave through it, run its cleanup forms,
;; then on from the frame before it
.protect:
    ld sp,ix
    push hl                     ; the value, the tag, the kind
    push de
    push bc
    call run_cleanup
    pop bc
    pop de
    pop hl
    jr unwind_to

;; run_cleanup: IX = an unwind-protect's frame (SP at or below it) -> the
;; frame taken off, its cleanup forms run in the scope it was made in
run_cleanup:
    ld l,(ix+8)
    ld h,(ix+9)
    ld (V_BLOCKS),hl
    ld l,(ix+2)
    ld h,(ix+3)
    ld (V_ENV),hl
    ld l,(ix+4)
    ld h,(ix+5)
    push hl
    ld e,(ix+0)
    ld d,(ix+1)
    call unwind_specs
    pop hl
    jp progn

;; (unwind-protect form cleanup...): form's value, the cleanup forms run
;; however it is left
sf_unwind_protect:
    push hl
    call cdr
    ex de,hl                    ; the tag: the cleanup forms
    pop hl
    call car
    ld bc,2
    PUSHFRAME
    call eval
    pop de
    call unwind_specs
    pop de
    ld (V_ENV),de
    pop de                      ; the cleanup forms
    pop bc
    pop bc
    ld (V_BLOCKS),bc
    push hl
    ex de,hl
    call progn
    pop hl
    jp ev_done

sf_dolist:
    ld bc,0
    ld de,NIL
    PUSHFRAME
    push hl
    call cdr                    ; body
    ex (sp),hl
    call car                    ; (var list [result])
    push hl
    call car                    ; var
    ex (sp),hl                  ; [body][var]
    push hl
    call cdr
    call car
    call eval                   ; the list
    ex (sp),hl                  ; [body][var][list]
    call cdr
    call cdr
    call car                    ; result form
    push hl                     ; [body][var][list][result]
    ld ix,0
    add ix,sp
    ld l,(ix+4)
    ld h,(ix+5)
    ld de,NIL
    call bind_var
.loop:
    ld l,(ix+2)
    ld h,(ix+3)
    ld a,h
    or l
    jr z,.end
    ld a,l
    and 3
    jp nz,err_notlist_hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI
    ld (ix+2),l
    ld (ix+3),h
    ld l,(ix+4)
    ld h,(ix+5)
    call set_var
    ld l,(ix+6)
    ld h,(ix+7)
    push ix
    call progn
    pop ix
    jr .loop
.end:
    ld l,(ix+4)
    ld h,(ix+5)
    ld de,NIL
    call set_var
dotimes_result:
    ld l,(ix+0)
    ld h,(ix+1)
    call eval
    ld sp,(V_BLOCKS)
    jp block_exit

sf_dotimes:
    ld bc,0
    ld de,NIL
    PUSHFRAME
    push hl
    call cdr                    ; body
    ex (sp),hl
    call car                    ; (var count [result])
    push hl
    call car                    ; var
    ex (sp),hl                  ; [body][var]
    push hl
    call cdr
    call car
    call eval                   ; the count
    call fixnum_hl
    ex (sp),hl                  ; [body][var][count]
    call cdr
    call cdr
    call car
    push hl                     ; [body][var][count][result]
    ld ix,0
    add ix,sp
    ld l,(ix+4)
    ld h,(ix+5)
    ld de,1                     ; 0
    call bind_var
    ld hl,1
    push hl                     ; i, at (ix-2)
.loop:
    pop de
    push de
    ld l,(ix+2)
    ld h,(ix+3)                 ; count
    ld a,h
    xor #80
    ld h,a
    ld a,d
    xor #80
    ld d,a
    or a
    sbc hl,de                   ; count - i, signed
    jr c,.end
    jr z,.end
    pop de
    push de
    ld l,(ix+4)
    ld h,(ix+5)
    call set_var
    ld l,(ix+6)
    ld h,(ix+7)
    push ix
    call progn
    pop ix
    pop hl
    inc hl
    inc hl                      ; i + 1
    push hl
    jr .loop
.end:
    pop de
    ld l,(ix+4)
    ld h,(ix+5)
    ld e,(ix+2)
    ld d,(ix+3)
    call set_var
    jp dotimes_result

sf_loop:
    ld bc,0
    ld de,NIL
    PUSHFRAME
.l:
    call poll_break             ; (loop) with nothing to eval still breaks
    push hl
    call progn
    pop hl
    jr .l

sf_prog1:
    push hl
    call car
    call eval
    ex (sp),hl
    call cdr
    call progn
    pop hl
    jp ev_done

;; (flet ((name lambda-list . body) ...) . body), and labels, where the
;; functions see each other
sf_flet:
    push hl
    call car
    ld c,0
.ev:
    ld a,h
    or l
    jr z,.bind
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI
    push bc
    push hl
    ex de,hl
    push hl
    call cdr
    call make_closure
    ex (sp),hl
    call car                    ; name
    ex de,hl
    pop hl                      ; closure
    ld (V_T1),hl
    pop hl
    pop bc
    push de
    ld de,(V_T1)
    push de
    inc c
    jr .ev
.bind:
    ld a,c
    or a
    jr z,.body
.b:
    pop de                      ; closure
    pop hl                      ; name
    push bc
    call bind_fn
    pop bc
    dec c
    jr nz,.b
.body:
    pop hl
    call cdr
    jp ev_progn

sf_labels:
    push hl
    call car
    push hl
.pass1:
    ld a,h
    or l
    jr z,.p2
    push hl
    call car
    call car                    ; name
    ld de,NIL
    call bind_fn
    pop hl
    call cdr
    jr .pass1
.p2:
    pop hl
.pass2:
    ld a,h
    or l
    jr z,.body
    push hl
    call car
    push hl
    call cdr
    call make_closure           ; sees the new bindings
    ex (sp),hl
    call car
    ex de,hl
    call env_fn_entry
    pop de
    inc hl
    inc hl
    ld (hl),e
    inc hl
    ld (hl),d
    pop hl
    call cdr
    jr .pass2
.body:
    pop hl
    call cdr
    jp ev_progn

;; bind_fn: HL = name, DE = function. V_ENV gets ((name) . function).
bind_fn:
    call is_symbol
    jr nz,.bad
    push hl                     ; it is a local function now: FNBOUND
    push de
    ld de,-(SYM_LO+2)
    add hl,de
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l
    ld de,FNBOUND
    add hl,de
    ld (hl),1
    pop de
    pop hl
    push de
    ld de,NIL
    call cons
    pop de
    call cons
    ld de,(V_ENV)
    call cons
    ld (V_ENV),hl
    ret
.bad:
    ex de,hl
    ld hl,m_notsym
    jp error

;; (case key (keys . body)... (t . body))
sf_case:
    push hl
    call car
    call eval
    ex de,hl                    ; DE = the key
    pop hl
    call cdr
.loop:
    ld a,h
    or l
    jp z,ev_done
    push hl
    call car
    push hl                     ; the clause
    call car                    ; its keys
    push de
    ld de,S_T
    call cmp_hl_de
    jr z,.hit
    ld de,S_OTHERWISE
    call cmp_hl_de
    jr z,.hit
    pop de
    push de
    call cmp_hl_de
    jr z,.hit
    ld a,l
    and 3
    jr nz,.miss
.keys:
    ld a,h
    or l
    jr z,.miss
    push hl
    LDHLI
    call cmp_hl_de
    pop hl
    jr z,.hit
    CDRHL
    jr .keys
.miss:
    pop de
    pop hl
    pop hl
    call cdr
    jr .loop
.hit:
    pop de
    pop hl
    pop bc
    call cdr
    jp ev_progn

sf_declare:
    ld hl,NIL
    jp ev_done

sf_the:
    call cdr
    call car
    jp ev_loop

;; ---------------------------------------------------------------------------
;; SETF and friends. A place is a variable or (accessor args...); the value
;; is computed first, then the accessor's arguments, then its setter is
;; called with HL = the arguments as a list, DE = the value.

sf_setf:
    ld de,NIL
.loop:
    ld a,h
    or l
    jr z,.end
    push hl
    call cdr
    call car
    call eval
    ex de,hl                    ; DE = value
    pop hl
    push hl
    push de
    call car                    ; the place
    call setf_place
    pop de
    pop hl
    call cdr
    call cdr
    jr .loop
.end:
    ex de,hl
    jp ev_done

;; setf_place: HL = place, DE = value
setf_place:
    call check_stack
    call is_symbol
    jp z,set_var
    ld a,l
    and 3
    jr nz,.bad
    ld a,h
    or l
    jr z,.bad
    push de
    push hl
    LDHLI                       ; accessor
    ex de,hl
    ld hl,setf_table
.find:
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    ld a,b
    or c
    jr z,.macro
    ld a,c
    cp e
    jr nz,.nx
    ld a,b
    cp d
    jr z,.found
.nx:
    inc hl
    inc hl
    jr .find
.found:
    LDHLI
    ex (sp),hl                  ; the setter on the stack, HL = place
    call cdr
    call eval_args              ; HL = the argument values
    pop bc
    pop de
    push bc
    ret                         ; to the setter
.macro:
    ; not one of these: a SETF property (defsetf) names a function given
    ; the place's arguments and the new value
    push de
    ex de,hl
    ld de,S_SETF
    call get_prop
    pop de
    jr nz,.expand
    ex (sp),hl                  ; the setter on the stack, HL = the place
    call cdr
    call eval_args              ; the arguments' values, a new list
    pop bc
    pop de                      ; the new value
    push bc
    push hl
    ex de,hl
    ld de,NIL
    call cons                   ; (value)
    ex de,hl
    pop hl
    ld a,h
    or l
    jr z,.only
    push hl
.last:
    ld c,l
    ld b,h
    CDRHL
    ld a,h
    or l
    jr nz,.last
    ld l,c
    ld h,b
    inc hl
    inc hl
    ld (hl),e                   ; (arg ... value)
    inc hl
    ld (hl),d
    pop de
    jr .apply
.only:
.apply:
    pop hl
    jp apply_list
.expand:
    ; a macro form: expand it and try again
    pop hl
    call macroexpand1
    jr nc,.nomac
    pop de
    jp setf_place
.nomac:
    pop de
.bad:
    ex de,hl
    ld hl,m_place
    jp error

;; eval_args: HL = forms -> HL = list of their values
eval_args:
    push ix
    ld de,NIL
    push de
    ld ix,0
    add ix,sp
.l:
    ld a,h
    or l
    jr z,.done
    push hl
    LDHLI
    push ix
    call eval
    pop ix
    ld e,(ix+0)
    ld d,(ix+1)
    call cons
    ld (ix+0),l
    ld (ix+1),h
    pop hl
    CDRHL
    jr .l
.done:
    pop hl
    ld de,NIL
    call nreverse_onto
    pop ix
    ret

setf_table:
    dw S_CAR,setf_car
    dw S_FIRST,setf_car
    dw S_CDR,setf_cdr
    dw S_REST,setf_cdr
    dw S_SECOND,setf_second
    dw S_CADR,setf_second
    dw S_NTH,setf_nth
    dw S_SYMBOL_VALUE,setf_symval
    dw S_SYMBOL_FUNCTION,setf_symfn
    dw S_SYMBOL_PLIST,setf_plist
    dw S_GET,setf_get
    dw S_CHAR,setf_char
    dw S_AREF,setf_aref
    dw S_SVREF,setf_aref
    dw 0

setf_car:
    call car                    ; the cons
    jp set_car
setf_cdr:
    call car
    jp set_cdr
setf_second:
    call car
    call cdr
    jp set_car
setf_nth:
    push de
    push hl
    call cdr
    call car                    ; the list
    ex (sp),hl
    call car                    ; n
    pop de
    call nthcdr_hl_de
    pop de
    jp set_car
setf_symval:
    call car
;; set_global: HL = symbol, DE = value: its global (dynamic) value
set_global:
    call check_var
    inc hl
    inc hl
    ld (hl),e
    inc hl
    ld (hl),d
    ret
setf_symfn:
    call car
    call sym_slot
    ld bc,SY_FUNC
    add hl,bc
    ld (hl),e
    inc hl
    ld (hl),d
    ret
setf_plist:
    call car
    call sym_slot
    dec hl
    dec hl
    ld a,(hl)
    and 3
    or e
    ld (hl),a
    inc hl
    ld (hl),d
    ret
setf_get:
    push de
    push hl
    call cdr
    call car                    ; indicator
    ex (sp),hl
    call car                    ; symbol
    pop de
    pop bc
    jp put_prop
setf_char:
    push de
    push hl
    call cdr
    call car
    ex (sp),hl
    call car                    ; string
    pop de                      ; index
    pop bc                      ; the character
    jp set_char

setf_aref:
    push de
    push hl
    call cdr
    call car
    ex (sp),hl
    call car                    ; the vector (or string)
    pop de                      ; index
    pop bc                      ; the value
    call is_string
    jp z,set_char
    push bc
    call vec_index
    pop de
    ld (hl),e
    inc hl
    ld (hl),d
    ret

;; set_car / set_cdr: HL = a cons, DE = value
set_car:
    call check_cons
    ld (hl),e
    inc hl
    ld (hl),d
    ret
set_cdr:
    call check_cons
    inc hl
    inc hl
    ld (hl),e
    inc hl
    ld (hl),d
    ret

;; check_cons: HL must be a cons. All kept.
check_cons:
    ld a,l
    and 3
    jr nz,.bad
    ld a,h
    or l
    ret nz
.bad:
    ex de,hl
    ld hl,m_notcons
    jp error

;; (incf place [delta]) is (setf place (+ place delta)); decf, push and pop
;; likewise. The place's own arguments are evaluated twice. On a variable
;; they are done directly: no form is built.
sf_incf:
    ld bc,S_PLUS
    jr incf_common
sf_decf:
    ld bc,S_MINUS
incf_common:
    push hl
    call car
    call is_symbol
    pop hl
    jr nz,incf_general
    push bc
    push hl
    call cdr
    ld de,3                     ; delta 1
    ld a,h
    or l
    jr z,.one
    call car
    call eval
    call fixnum_hl
    ex de,hl
.one:
    pop hl
    push hl
    push de
    call car
    call eval                   ; the variable's value
    call fixnum_hl
    pop de
    pop bc                      ; the form's arguments
    ex (sp),hl                  ; HL = + or -, value on the stack
    push bc
    ld bc,S_PLUS
    or a
    sbc hl,bc
    pop bc
    pop hl
    jr nz,.minus
    dec hl
    or a
    adc hl,de
    jp pe,err_overflow
    jr .set
.minus:
    or a
    sbc hl,de
    jp pe,err_overflow
    inc hl
.set:
    ex de,hl
    ld l,c
    ld h,b
    call car
    push de
    call set_var
    pop hl
    jp ev_done
incf_general:
    push bc
    push hl
    call cdr
    ld a,h
    or l
    jr nz,.delta
    ld hl,3                     ; 1
    ld de,NIL
    call cons
.delta:
    pop de
    push de
    ex de,hl
    call car                    ; place
    call cons                   ; (place delta)
    pop de
    pop bc
    push de
    ex de,hl
    ld l,c
    ld h,b
    call cons                   ; (+ place delta)
    jr setf_form
sf_push:
    push hl
    call cdr
    call car                    ; place
    call is_symbol
    jr nz,.general
    pop hl
    push hl
    call car
    call eval                   ; the item
    ex (sp),hl
    call cdr
    call car                    ; the variable
    push hl
    call eval
    ex de,hl                    ; DE = its value
    pop bc
    pop hl                      ; the item
    push bc
    call cons
    ex de,hl
    pop hl
    push de
    call set_var
    pop hl
    jp ev_done
.general:
    ld de,NIL
    call cons
    ex de,hl
    pop hl
    push hl
    call car                    ; item
    call cons                   ; (item place)
    ex de,hl
    ld hl,S_CONS
    call cons                   ; (cons item place)
    ex de,hl
    pop hl
    call cdr
    push hl
    ex de,hl
;; setf_form: HL = the value form, (SP) = a list whose car is the place ->
;; evaluate (setf place form) as a tail
setf_form:
    ld de,NIL
    call cons
    ex de,hl
    pop hl
    call car
    call cons
    ex de,hl
    ld hl,S_SETF
    call cons
    jp ev_loop
sf_pop:
    ; (prog1 (car place) (setf place (cdr place)))
    call car
    call is_symbol
    jr nz,.general
    push hl
    call eval
    push hl                     ; the list
    call cdr
    ex de,hl
    pop bc
    pop hl
    push bc
    call set_var
    pop hl
    call car
    jp ev_done
.general:
    push hl                     ; place
    ld de,NIL
    call cons
    ex de,hl
    ld hl,S_CDR
    call cons                   ; (cdr place)
    ld de,NIL
    call cons
    ex de,hl
    pop hl
    push hl
    call cons                   ; (place (cdr place))
    ex de,hl
    ld hl,S_SETF
    call cons
    ld de,NIL
    call cons                   ; ((setf place (cdr place)))
    ex de,hl
    pop hl
    push de
    ld de,NIL
    call cons
    ex de,hl
    ld hl,S_CAR
    call cons                   ; (car place)
    pop de
    call cons
    ex de,hl
    ld hl,S_PROG1
    call cons
    jp ev_loop

;; macroexpand1: HL = form -> C and HL = its expansion if it is a macro
;; call; NC and HL unchanged if not
macroexpand1:
    ld a,l
    and 3
    jr nz,.no
    ld a,h
    or l
    jr z,.no
    push hl
    LDHLI
    call is_symbol
    jr nz,.no1
    ex de,hl
    call env_fn_entry
    ld a,h
    or l
    jr nz,.no1                  ; a local function, not a macro
    ld hl,SY_FUNC
    add hl,de
    LDHLI
    call resolve_fn
    ld a,h
    cp CELL_LO >> 8
    jr c,.no1
    cp #C0
    jr nc,.no1
    push hl
    dec hl
    dec hl
    ld a,(hl)
    pop hl
    cp HDR_MACRO and #FF
    jr nz,.no1
    LDHLI                       ; the closure
    pop de
    ex de,hl
    call cdr
    ex de,hl
    call apply_list
    scf
    ret
.no1:
    pop hl
.no:
    or a
    ret
