;; CPC Lisp -- builtin functions.
;;
;; Fixed arity up to 3: arguments in HL, DE, BC. Otherwise HL = &arg 0 and
;; B = count, read with NEXTARG. Return the value in HL.

ret_t:
    ld hl,S_T
    ret
ret_nil:
    ld hl,NIL
    ret
;; T if Z, else NIL
bool_z:
    ld hl,S_T
    ret z
    ld hl,NIL
    ret
;; T if NZ, else NIL
bool_nz:
    ld hl,NIL
    ret z
    ld hl,S_T
    ret

;; ---------------------------------------------------------------------------
;; type checks: error unless the object is right. All registers kept.

fixnum_hl:
    bit 0,l
    ret nz
    ex de,hl
    jr err_notnum
fixnum_de:
    bit 0,e
    ret nz
err_notnum:
    ld hl,m_notnum
    jp error

check_char:
    ld a,l
    and 3
    cp 2
    jr nz,.bad
    ld a,h
    cp 4
    ret c
.bad:
    ex de,hl
    ld hl,m_notchar
    jp error

check_string:
    call is_string
    ret z
    ex de,hl
    ld hl,m_notstr
    jp error

;; ---------------------------------------------------------------------------
;; LISTS

;; car, cdr: HL = a list. NIL gives NIL. BC, DE kept.
car:
    ld a,h
    or l
    ret z
    ld a,l
    and 3
    jr nz,err_notlist_hl
    LDHLI
    ret
cdr:
    ld a,h
    or l
    ret z
    ld a,l
    and 3
    jr nz,err_notlist_hl
    CDRHL
    ret
err_notlist_hl:
    ex de,hl
    ld hl,m_notlist
    jp error

subr_caar:
    call car
    jr car
subr_cadr:
    call cdr
    jr car
subr_cdar:
    call car
    jr cdr
subr_cddr:
    call cdr
    jr cdr
subr_caddr:
    call cdr
    call cdr
    jr car
subr_cdddr:
    call cdr
    call cdr
    jr cdr

;; args_to_list: HL = &arg 0, B = n -> HL = them as a list
args_to_list:
    ld de,NIL
;; args_onto: the same, onto the tail DE
args_onto:
    ld a,b
    or a
    jr z,.done
    push de
    ld e,b
    dec e
    ld d,0
    ex de,hl
    add hl,hl
    ex de,hl
    or a
    sbc hl,de                   ; the last of them
    pop de
.l:
    push hl
    LDHLI
    call cons
    ex de,hl
    pop hl
    inc hl
    inc hl
    djnz .l
.done:
    ex de,hl
    ret

;; (list* a ... tail), and apply's argument spreading: HL = &first, B >= 1
liststar_args:
    push hl
    ld e,b
    dec e
    ld d,0
    ex de,hl
    add hl,hl
    ex de,hl
    or a
    sbc hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    pop hl
    dec b
    jr args_onto

;; reverse: HL = list -> a fresh reversed copy
reverse:
    ld de,NIL
.l:
    ld a,h
    or l
    jr z,.done
    ld a,l
    and 3
    jp nz,err_notlist_hl
    push hl
    LDHLI
    call cons
    ex de,hl
    pop hl
    CDRHL
    jr .l
.done:
    ex de,hl
    ret

;; append2: HL = list, DE = tail -> a copy of the list ending in tail
append2:
    push de
    call reverse
    pop de
    jp nreverse_onto

subr_append:
    ld a,b
    or a
    jp z,ret_nil
    ld e,b
    dec e
    ld d,0
    ex de,hl
    add hl,hl
    ex de,hl
    or a
    sbc hl,de                   ; the last argument: shared, not copied
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    dec b
    jr z,.done
.l:
    push hl
    push bc
    LDHLI
    call append2
    ex de,hl
    pop bc
    pop hl
    inc hl
    inc hl
    djnz .l
.done:
    ex de,hl
    ret

subr_length:
    call is_string
    jr z,.str
    call is_vector
    jr z,.vec
    ld de,0
.l:
    ld a,h
    or l
    jr z,.done
    ld a,l
    and 3
    jp nz,err_notlist_hl
    call poll_break
    inc de
    CDRHL
    jr .l
.done:
    ex de,hl
    add hl,hl
    inc hl
    ret
.str:
    call str_data
    jr .n
.vec:
    call vec_data
.n:
    ld l,c
    ld h,b
    add hl,hl
    inc hl
    ret

;; ---------------------------------------------------------------------------
;; VECTORS: a typed cell (HDR_VECTOR) whose block in block space holds the
;; elements, a word each. The GC follows them (mark_value) and moves the
;; block as it moves a string's.

;; is_vector: HL -> Z if it is a vector. All kept but AF.
is_vector:
    push bc
    ld c,HDR_VECTOR and #FF
    call is_typed
    pop bc
    ret

;; vec_data: HL = a vector -> HL = its first element, BC = how many. DE kept
vec_data:
    LDHLI
    jp vec_words

;; make_vector: BC = how many, DE = what each is -> HL = a new vector
make_vector:
    push de
    push bc
    ld hl,HDR_VECTOR
    ld de,0
    call alloc_typed
    pop bc
    push hl                     ; the vector, reachable
    sla c
    rl b
    jp c,err_nostr
    call blk_alloc              ; owner = its data word
    inc hl
    inc hl
    pop de
    ex (sp),hl                  ; the elements on the stack, HL = the value
    ex de,hl
    ex (sp),hl                  ; the vector on the stack, HL = the elements
    srl b
    rr c
.f:
    ld a,b
    or c
    jr z,.done
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    dec bc
    jr .f
.done:
    pop hl
    ret

;; vec_index: HL = a vector, DE = an index -> HL = that element's address
vec_index:
    call is_vector
    jr nz,.notvec
    call fixnum_de
    push de
    sra d
    rr e
    push de
    call vec_data
    pop de
    ex de,hl
    or a
    sbc hl,bc
    jr nc,.bad                  ; past the end (or negative: huge)
    add hl,bc
    add hl,hl
    add hl,de
    pop de
    ret
.bad:
    pop de
    ld hl,m_index
    jp error
.notvec:
    ex de,hl
    ld hl,m_notvec
    jp error

;; list_to_vector: HL = a list -> HL = a vector of its elements
list_to_vector:
    push hl
    ld bc,0
    ld d,h
    ld e,l
.c:
    ld a,d
    or e
    jr z,.n
    inc bc
    ex de,hl
    CDRHL
    ex de,hl
    jr .c
.n:
    ld de,NIL
    call make_vector
    pop de                      ; the list
    push hl
    LDHLI
    inc hl
    inc hl
.f:
    ld a,d
    or e
    jr z,.done
    ex de,hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    LDHLI
    ex de,hl
    ld (hl),c
    inc hl
    ld (hl),b
    inc hl
    jr .f
.done:
    pop hl
    ret

;; (aref v i), (svref v i): an element; of a string, a character
subr_aref:
    call is_string
    jp z,subr_char
    call vec_index
    LDHLI
    ret

;; (elt sequence i): of a list, a vector or a string
subr_elt:
    call is_string
    jp z,subr_char
    call is_vector
    jr z,subr_aref
    ex de,hl
    jp subr_nth

subr_vectorp:
    call is_vector
    jp z,ret_t
    call is_string
    jp bool_z

subr_nth:
    call nthcdr_hl_de
    jp car
subr_nthcdr:
;; nthcdr_hl_de: HL = n, DE = list -> HL = its nth cdr
nthcdr_hl_de:
    call fixnum_hl
    sra h
    rr l
    bit 7,h
    jr nz,.bad
    ex de,hl
.l:
    ld a,d
    or e
    ret z
    ld a,h
    or l
    ret z
    call cdr
    dec de
    jr .l
.bad:
    ex de,hl
    ld hl,m_index
    jp error

subr_last:
    ld a,h
    or l
    ret z
.l:
    push hl
    call cdr
    ld a,l
    and 3
    jr nz,.end
    ld a,h
    or l
    jr z,.end
    pop de
    jr .l
.end:
    pop hl
    ret

subr_rplaca:
    push hl
    call set_car
    pop hl
    ret
subr_rplacd:
    push hl
    call set_cdr
    pop hl
    ret

;; (mapcar f list...) and (mapc f list...). Each call is laid out on the
;; stack as eval lays out one (map_call): no list of the arguments is made.
subr_mapcar:
    ld a,1
    jr map_common
subr_mapc:
    xor a
map_common:
    push af                     ; (ix+9): 1 = collect; (ix+8): map_call's count
    ld e,(hl)
    inc hl
    ld d,(hl)
    dec hl
    ex de,hl
    call coerce_fn              ; (once, not for every element)
    ex de,hl
    push de                     ; (ix+6) f
    dec hl
    dec hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    dec hl
    push de                     ; (ix+4) the first list, mapc's value
    dec b
    call args_to_list
    push hl                     ; (ix+2) the lists, advanced as we go
    ld de,NIL
    push de                     ; (ix+0) results, reversed
    ld ix,0
    add ix,sp
.loop:
    ld l,(ix+2)                 ; one of the lists at its end: done
    ld h,(ix+3)
.chk:
    ld a,h
    or l
    jr z,.call
    push hl
    LDHLI
    ld a,l
    and 3
    jr nz,.end
    ld a,h
    or l
    jr z,.end
    pop hl
    CDRHL
    jr .chk
.end:
    pop hl
    jr .done
.call:
    push ix
    call map_call
    pop ix
    ld a,(ix+9)
    or a
    jr z,.loop
    ld e,(ix+0)
    ld d,(ix+1)
    call cons
    ld (ix+0),l
    ld (ix+1),h
    jr .loop
.done:
    ld l,(ix+0)
    ld h,(ix+1)
    ld de,NIL
    call nreverse_onto
    ld a,(ix+9)
    or a
    jr nz,.ret
    ld l,(ix+4)
    ld h,(ix+5)
.ret:
    ld de,10
    ex de,hl
    add hl,sp
    ld sp,hl
    ex de,hl
    ret

;; map_call: IX = map's frame -> f applied to the lists' first elements,
;; each list moved on one
map_call:
    ld bc,(V_ENV)
    push bc                     ; an eval frame
    ld l,(ix+6)
    ld h,(ix+7)
    push hl                     ; the function
    ld (ix+8),0
    ld l,(ix+2)
    ld h,(ix+3)
.a:
    ld e,(hl)
    inc hl
    ld d,(hl)
    dec hl                      ; DE = one list
    ex de,hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    push bc                     ; its first element: an argument
    ld c,(hl)
    inc hl
    ld b,(hl)                   ; BC = the rest of it
    ex de,hl
    ld (hl),c
    inc hl
    ld (hl),b
    inc hl
    inc (ix+8)
    LDHLI                       ; the next list
    ld a,h
    or l
    jr nz,.a
    ld c,(ix+8)
    jp apply_core

;; (funcall f arg...), (apply f arg... list) called as functions (from
;; mapcar, apply...; eval itself passes funcall's arguments on): the call
;; laid out on the stack, no list made
subr_funcall:
    call fn_frame               ; the eval frame and the function pushed
    ld b,a
    dec b                       ; the arguments after f
    ld c,b
    jr z,.go
.p:
    dec hl
    dec hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    dec hl
    push de
    djnz .p
.go:
    jp apply_core

subr_apply:
    call fn_frame
    ld c,0
    sub 2
    jr z,.list
    ld b,a
.p:
    dec hl
    dec hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    dec hl
    push de
    inc c
    djnz .p
.list:
    dec hl
    dec hl
    LDHLI                       ; the list: its elements, each an argument
.s:
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
    jr nz,.s
    jp ev_cons.many
.go:
    jp apply_core

;; fn_frame: HL = &arg 0, the function (or a symbol), B = how many ->
;; pushed under the caller's return: an eval frame, the function. HL kept,
;; A = how many
fn_frame:
    ld a,b
    pop bc                      ; the return
    ld e,(hl)
    inc hl
    ld d,(hl)
    dec hl
    push bc
    push af
    push hl
    ex de,hl
    call coerce_fn              ; (an autoload may run: all is on the stack)
    ex de,hl                    ; DE = the function
    pop hl
    pop af
    pop bc                      ; the return again
    push hl
    ld hl,(V_ENV)
    ex (sp),hl                  ; an eval frame
    push de                     ; the function
    push bc
    ret

;; ---------------------------------------------------------------------------
;; PREDICATES AND EQUALITY

subr_null:
    ld a,h
    or l
    jp bool_z
subr_atom:
    ld a,l
    and 3
    jp nz,ret_t
    ld a,h
    or l
    jp bool_z
subr_consp:
    ld a,l
    and 3
    jp nz,ret_nil
    ld a,h
    or l
    jp bool_nz
subr_listp:
    ld a,l
    and 3
    jp bool_z
subr_symbolp:
    ld a,h
    or l
    jp z,ret_t
    call is_symbol
    jp bool_z
subr_numberp:
    bit 0,l
    jp nz,ret_t
    call is_float
    jp bool_z
subr_integerp:
    bit 0,l
    jp bool_nz
subr_stringp:
    call is_string
    jp bool_z
subr_characterp:
    ld a,l
    and 3
    cp 2
    jp nz,ret_nil
    ld a,h
    cp 4
    jp nc,ret_nil
    jp ret_t
subr_functionp:
    call is_function
    jp bool_z
subr_keywordp:
    call is_symbol
    jp nz,ret_nil
    LDHLI
    inc hl
    inc hl
    ld a,(hl)
    cp ":"
    jp bool_z
subr_eq:
    call cmp_hl_de
    jp bool_z
subr_eql:
    call eql
    jp bool_z

;; eql: HL, DE -> Z if they are the same object, or floats of one value.
;; All kept but AF.
eql:
    call cmp_hl_de
    ret z
    call is_float
    ret nz
    ex de,hl
    call is_float
    ex de,hl
    ret nz
    push hl
    push de
    push bc
    call str_equal
    pop bc
    pop de
    pop hl
    ret
subr_equal:
    call equal
    jp bool_z

;; equal: HL, DE -> Z if they are the same structure
equal:
    call check_stack
.loop:
    call cmp_hl_de
    ret z
    ld a,l
    or e
    and 3
    jr nz,.atoms
    ld a,h
    or l
    jr z,.ne
    ld a,d
    or e
    jr z,.ne
    push hl
    push de
    LDHLI
    ex de,hl
    LDHLI
    ex de,hl
    call equal
    pop de
    pop hl
    ret nz
    CDRHL
    ex de,hl
    CDRHL
    ex de,hl
    jr .loop
.atoms:
    call is_string
    jr nz,eql
    ex de,hl
    call is_string
    ex de,hl
    ret nz
    jr str_equal
.ne:
    or 1
    ret
;; str_equal: HL, DE = strings (or symbols' slots) -> Z if the same characters
str_equal:
    push de
    call str_data
    ex (sp),hl
    push bc
    call str_data
    pop de
    ex de,hl
    or a
    sbc hl,bc
    pop hl
    ret nz
.l:
    ld a,b
    or c
    ret z
    ld a,(de)
    cp (hl)
    ret nz
    inc hl
    inc de
    dec bc
    jr .l

;; ---------------------------------------------------------------------------
;; NUMBERS: fixnums, value*2+1

;; tag_hl: HL = a plain 16-bit number -> the fixnum, or an overflow error
tag_hl:
    ld a,h
    and #C0
    jr z,.ok
    cp #C0
    jp nz,err_overflow
.ok:
    add hl,hl
    inc hl
    ret
err_overflow:
    ERR m_overflow

;; Number prologues. A numeric subr starts by calling one, which returns if
;; the arguments are all fixnums. If not, the whole call is handed to the
;; library's float arithmetic (lnum_arith), named by the address the call
;; returns to -- a NUM_ label after it -- and what that gives back is the
;; subr's result. Without the library, a float cannot exist: the argument
;; that is not a fixnum is "not a number".
;;
;; nums_v: a variadic subr, HL = &arg 0, B = n, C its own. It notes where
;; the arguments are, so that an integer overflow can start the call again
;; in floats (num_ovf) -- or report it, without the library.
nums_v:
    ld (V_NUMARGS),hl
    ld (V_NUMBC),bc
    pop de
    ld (V_NUMOP),de
    ld (V_NUMSP),sp             ; the subr's own return on top
    push de
    ld a,b
    or a
    ret z
    push hl
    push bc
.l:
    ld a,(hl)
    rra
    jr nc,.float
    dec hl
    dec hl
    djnz .l
    pop bc
    pop hl
    ret
.float:
num_ovf:
    ld sp,(V_NUMSP)
    ld hl,(V_NUMARGS)
    ld bc,(V_NUMBC)
    ld de,(V_NUMOP)
;; float_go: HL = &arg 0, B = n, C, DE = a NUM_ label -> the library's
;; result, returned for the subr
float_go:
    ld a,(V_NUMROM)
    or a
    jp nz,lnum_arith
    ld a,b                      ; no library
    or a
    jr z,.ovf
.l:
    NEXTARG
    bit 0,e
    jp z,err_notnum
    djnz .l
.ovf:
    jp err_overflow

;; nums_1: a subr of one argument, HL
nums_1:
    bit 0,l
    ret nz
    pop de
;; num_ovf1: HL = the argument of a one-argument subr, DE = its NUM_ label
num_ovf1:
    push hl
    ld b,1
    call float_stk
    pop de
    ret

;; nums_2: a subr of two arguments, HL and DE
nums_2:
    ld a,l
    and e
    rra
    ret c
    ex (sp),hl                  ; the first argument where the return was
    push de
    ex de,hl
    ld b,2
    call float_stk
    pop de
    pop de
    ret

;; float_stk: B arguments pushed just before the call -> float_go
float_stk:
    ld l,b
    ld h,0
    add hl,hl
    add hl,sp
    jr float_go

;; abs_hl, neg_hl: on a plain number. DE, BC kept.
abs_hl:
    bit 7,h
    ret z
neg_hl:
    ld a,l
    cpl
    ld l,a
    ld a,h
    cpl
    ld h,a
    inc hl
    ret

;; fix_pair: HL = &arg 0 of two -> DE = arg 0, HL = arg 1, carry set if
;; both are fixnums. BC kept.
fix_pair:
    ld e,(hl)
    inc hl
    ld d,(hl)
    dec hl
    dec hl
    ld a,(hl)
    dec hl
    ld l,(hl)
    ld h,a
    ld a,l
    and e
    rra
    ret

subr_plus:
    ld a,b                      ; two fixnums: at once
    cp 2
    jr nz,.gen
    push hl
    call fix_pair
    jr nc,.gen1
    dec hl
    or a
    adc hl,de
    jp pe,.gen1                 ; overflow: the general way
    pop de
    ret
.gen1:
    pop hl
.gen:
    call nums_v
NUM_PLUS:
    ld ix,1
    ld a,b
    or a
    jr z,.done
.l:
    NEXTARG
    call fixnum_de
    push hl
    push ix
    pop hl
    dec hl
    or a
    adc hl,de
    jp pe,num_ovf
    push hl
    pop ix
    pop hl
    djnz .l
.done:
    push ix
    pop hl
    ret

subr_minus:
    ld a,b                      ; two fixnums: at once
    cp 2
    jr nz,.gen
    push hl
    call fix_pair
    jr nc,.gen1
    ex de,hl
    or a
    sbc hl,de
    jp pe,.gen1
    inc hl
    pop de
    ret
.gen1:
    pop hl
.gen:
    call nums_v
NUM_MINUS:
    NEXTARG
    dec b
    jr nz,.sub
    ld hl,2
    or a
    sbc hl,de
    jp pe,num_ovf
    ret
.sub:
    push de
    pop ix
.l:
    NEXTARG
    push hl
    push ix
    pop hl
    or a
    sbc hl,de
    jp pe,num_ovf
    inc hl
    push hl
    pop ix
    pop hl
    djnz .l
    push ix
    pop hl
    ret

subr_times:
    call nums_v
NUM_TIMES:
    ld ix,3
    ld a,b
    or a
    jr z,.done
.l:
    NEXTARG
    call fixnum_de
    push hl
    push bc
    push ix
    pop hl
    call mul_fix
    push hl
    pop ix
    pop bc
    pop hl
    djnz .l
.done:
    push ix
    pop hl
    ret

;; mul_fix: HL, DE = fixnums -> HL = their product
mul_fix:
    sra h
    rr l
    ex de,hl
    sra h
    rr l
    ld a,h
    xor d
    push af                     ; the sign of the product
    call abs_hl
    ex de,hl
    call abs_hl
    ld b,h
    ld c,l
    call umul
    jr c,.ovf
    bit 7,h
    jr nz,.ovf
    ld a,h
    and #C0
    jr z,.fits
    pop af                      ; 16384 or more: only -16384 fits
    push af
    jp p,.ovf
    ld a,h
    cp #40
    jr nz,.ovf
    ld a,l
    or a
    jr nz,.ovf
.fits:
    pop af
    jp m,.neg
    jp tag_hl
.neg:
    call neg_hl
    jp tag_hl
.ovf:
    pop af
    jp num_ovf

;; umul: BC * DE -> HL, C if it does not fit 16 bits. The smaller one is
;; the multiplier, taken a bit at a time from the bottom until none are
;; left: (* 7 9) takes 4 rounds, not 16.
umul:
    ld h,b
    ld l,c
    or a
    sbc hl,de
    jr nc,.l0                   ; DE the smaller
    ld h,b
    ld l,c
    ld b,d
    ld c,e
    ex de,hl
.l0:
    ld hl,0
.l:
    srl d
    rr e
    jr nc,.n
    add hl,bc
    ret c                       ; too big
.n:
    ld a,d
    or e
    ret z                       ; (NC) done
    sla c
    rl b
    jr nc,.l
    scf                         ; bits left and the multiplicand past 16
    ret

;; udiv16: HL / DE (unsigned) -> HL = quotient, DE = remainder
udiv16:
    ld b,h
    ld c,l
    ld hl,0
    ld a,16
.l:
    sla c
    rl b
    adc hl,hl
    or a
    sbc hl,de
    jr nc,.ok
    add hl,de
    jr .n
.ok:
    inc c
.n:
    dec a
    jr nz,.l
    ex de,hl
    ld h,b
    ld l,c
    ret

;; divide: HL, DE = fixnums -> HL = the quotient truncated toward zero,
;; DE = the remainder, both plain numbers
divide:
    call fixnum_hl
    call fixnum_de
    sra h
    rr l
    ex de,hl
    sra h
    rr l
    ex de,hl
    ld a,d
    or e
    jr z,.zero
    ld a,h
    or a                        ; (ld sets no flags)
    push af                     ; the sign of the remainder: the dividend's
    xor d
    push af                     ; the sign of the quotient
    call abs_hl
    ex de,hl
    call abs_hl
    ex de,hl
    call udiv16
    pop af
    call m,neg_hl
    pop af
    ret p
    ex de,hl
    call neg_hl
    ex de,hl
    ret
.zero:
    ERR m_div0

;; floor_div: HL, DE = fixnums -> HL = quotient rounded down, DE = remainder
floor_div:
    push de
    call divide
    pop bc
    ld a,d
    or e
    ret z
    ld a,d
    xor b
    ret p
    dec hl
    push hl
    ld l,c
    ld h,b
    sra h
    rr l
    add hl,de
    ex de,hl
    pop hl
    ret

;; two_nums: a variadic (x [y]) -> HL = x, DE = y or 1
two_nums:
    NEXTARG
    push de
    ld de,3
    dec b
    jr z,.one
    NEXTARG
.one:
    pop hl
    ret

subr_truncate:
    call nums_v
NUM_TRUNCATE:
    call two_nums
    call divide
    jr mv_qr
subr_floor:
    call nums_v
NUM_FLOOR:
    call two_nums
    call floor_div
;; mv_qr: HL = a quotient, DE = the remainder (untagged) -> the quotient,
;; and both as the multiple values
mv_qr:
    ex de,hl
    add hl,hl
    inc hl                      ; (smaller than the divisor: a fixnum)
    ld (V_MV2),hl
    ex de,hl
    call tag_hl
    ld (V_MV1),hl
    ld a,3
    ld (V_MVN),a
    ret
subr_mod:
    call nums_2
NUM_MOD:
    call floor_div
    ex de,hl
    jp tag_hl
subr_rem:
    call nums_2
NUM_REM:
    call divide
    ex de,hl
    jp tag_hl

subr_inc:
    call nums_1
NUM_INC:
    ld de,2
    or a
    adc hl,de
    ret po
    ld hl,#7FFF                 ; 16383 + 1: again, in floats
    ld de,NUM_INC
    jp num_ovf1
subr_dec:
    call nums_1
NUM_DEC:
    ld de,2
    or a
    sbc hl,de
    ret po
    ld hl,#8001                 ; -16384 - 1
    ld de,NUM_DEC
    jp num_ovf1
subr_abs:
    call nums_1
NUM_ABS:
    bit 7,h
    ret z
    ex de,hl
    ld hl,2
    or a
    sbc hl,de
    ret po
    ld hl,#8001                 ; (abs -16384)
    ld de,NUM_ABS
    jp num_ovf1

subr_max:
    ld c,0
    jr maxmin
subr_min:
    ld c,1
maxmin:
    call nums_v
NUM_MAXMIN:
    NEXTARG
    push de
    pop ix
    dec b
    jr z,.done
.l:
    NEXTARG
    push hl
    push ix
    pop hl
    push de
    ld a,h
    xor #80
    ld h,a
    ld a,d
    xor #80
    ld d,a
    or a
    sbc hl,de                   ; C: so far < this one
    pop de
    push af
    ld a,c
    or a
    jr nz,.min
    pop af
    jr c,.take
    jr .keep
.min:
    pop af
    jr c,.keep
    jr z,.keep
.take:
    push de
    pop ix
.keep:
    pop hl
    djnz .l
.done:
    push ix
    pop hl
    ret

;; comparisons: C = which outcomes of x vs y pass, as bits: 1 less,
;; 2 equal, 4 greater
subr_lt:
    ld c,1
    jr compare
subr_gt:
    ld c,4
    jr compare
subr_le:
    ld c,3
    jr compare
subr_ge:
    ld c,6
    jr compare
subr_numeq:
    ld c,2
    jr compare
subr_numne:
    ld c,5
compare:
    ld a,b                      ; two fixnums: at once
    cp 2
    jr nz,.gen
    push hl
    call fix_pair
    jr nc,.gen1
    pop af
    ex de,hl
    call NUM_COMPARE.cmp
    jp z,ret_nil
    jp ret_t
.gen1:
    pop hl
.gen:
    call nums_v
NUM_COMPARE:
    NEXTARG
    dec b
    jp z,ret_t
.l:
    push de
    NEXTARG
    ex (sp),hl
    push de
    call .cmp
    pop de
    pop hl
    jp z,ret_nil
    djnz .l
    jp ret_t
;; HL against DE, fixnums -> NZ if C's relation holds (1 <, 2 =, 4 >)
.cmp:
    ld a,h
    xor #80
    ld h,a
    ld a,d
    xor #80
    ld d,a
    or a
    sbc hl,de
    ld a,1
    jr c,.got
    ld a,2
    jr z,.got
    ld a,4
.got:
    and c
    ret

subr_zerop:
    call nums_1
NUM_ZEROP:
    dec hl
    ld a,h
    or l
    jp bool_z
subr_plusp:
    call nums_1
NUM_PLUSP:
    bit 7,h
    jp nz,ret_nil
    dec hl
    ld a,h
    or l
    jp bool_nz
subr_minusp:
    call nums_1
NUM_MINUSP:
    bit 7,h
    jp bool_nz
subr_evenp:
    call fixnum_hl
    bit 1,l
    jp bool_z
subr_oddp:
    call fixnum_hl
    bit 1,l
    jp bool_nz

;; (random n): 0 <= result < n
subr_random:
    call nums_1
NUM_RANDOM:
    sra h
    rr l
    ld a,h
    or l
    jr z,.bad
    bit 7,h
    jr nz,.bad
    ex de,hl
    call rand16
    res 7,h
    call udiv16
    ex de,hl
    jp tag_hl
.bad:
    ex de,hl
    ld hl,m_index
    jp error

;; rand16 -> HL: a 16-bit xorshift
rand16:
    ld hl,(V_RAND)
    ld a,h
    rra
    ld a,l
    rra
    xor h
    ld h,a
    ld a,l
    rra
    ld a,h
    rra
    xor l
    ld l,a
    xor h
    ld h,a
    ld (V_RAND),hl
    ret

;; ---------------------------------------------------------------------------
;; SYMBOLS

subr_symbol_name:
    call sym_to_tokbuf
    ld hl,TOKBUF
    jp make_string

;; sym_to_tokbuf: HL = a symbol -> its name copied to TOKBUF, BC = length
sym_to_tokbuf:
    call sym_slot
    call str_data
    ld de,TOKBUF
    push bc
    ld a,b
    or c
    jr z,.e
    ldir
.e:
    pop bc
    ret

subr_symbol_value:
    call sym_slot
    push hl
    inc hl
    inc hl
    LDHLI
    pop de
    push hl
    ld bc,UNBOUND
    or a
    sbc hl,bc
    pop hl
    ret nz
    jp err_unbound

subr_symbol_function:
    call sym_slot
    push hl
    ld bc,SY_FUNC
    add hl,bc
    LDHLI
    pop de
    call resolve_fn
    ld a,h
    cp 4
    ret nz
    ld hl,m_undef
    jp error

subr_symbol_plist:
    call sym_slot
    dec hl
    dec hl
    LDHLI
    ld a,l
    and #FC
    ld l,a
    ret

subr_set:
    push de
    call set_global
    pop hl
    ret

subr_boundp:
    call sym_slot
    inc hl
    inc hl
    LDHLI
    ld de,UNBOUND
    call cmp_hl_de
    jp bool_nz
subr_fboundp:
    call sym_slot
    ld de,SY_FUNC
    add hl,de
    LDHLI
    ld a,h
    cp 4
    jp bool_nz
subr_makunbound:
    push hl
    ld de,UNBOUND
    call set_global
    pop hl
    ret
subr_fmakunbound:
    push hl
    call sym_slot
    ld de,SY_FUNC
    add hl,de
    ld (hl),UNBOUND and #FF
    inc hl
    ld (hl),UNBOUND >> 8
    pop hl
    ret

;; (get symbol indicator [default])
subr_get:
    NEXTARG
    push de                     ; the symbol
    NEXTARG
    push de                     ; the indicator
    ld de,NIL
    dec b
    dec b
    jr z,.nodef
    NEXTARG
.nodef:
    ld (V_T1),de
    pop de
    pop hl
    call get_prop
    ret z
    ld hl,(V_T1)
    ret

;; get_prop: HL = symbol, DE = indicator -> Z and HL = the value, or NZ
get_prop:
    call sym_slot
    dec hl
    dec hl
    LDHLI
    ld a,l
    and #FC
    ld l,a
.l:
    ld a,h
    or l
    jr z,.no
    push hl
    LDHLI
    call cmp_hl_de
    pop hl
    jr z,.found
    call cdr
    call cdr
    jr .l
.found:
    call cdr
    call car
    cp a
    ret
.no:
    or 1
    ret

;; put_prop: HL = symbol, DE = indicator, BC = value
put_prop:
    push bc
    call sym_slot
    push hl
    dec hl
    dec hl
    LDHLI
    ld a,l
    and #FC
    ld l,a
.l:
    ld a,h
    or l
    jr z,.add
    push hl
    LDHLI
    call cmp_hl_de
    pop hl
    jr z,.found
    call cdr
    call cdr
    jr .l
.found:
    call cdr
    pop de
    pop de
    jp set_car
.add:
    pop hl                      ; the symbol's slot pointer
    pop bc                      ; the value
    push hl
    push de                     ; the indicator
    dec hl
    dec hl
    LDHLI
    ld a,l
    and #FC
    ld l,a
    ex de,hl
    ld l,c
    ld h,b
    call cons                   ; (value . plist)
    ex de,hl
    pop hl
    call cons                   ; (indicator value . plist)
    ex de,hl
    pop hl
    dec hl
    dec hl
    ld a,(hl)
    and 3
    or e
    ld (hl),a
    inc hl
    ld (hl),d
    ret

;; ---------------------------------------------------------------------------
;; CHARACTERS AND STRINGS

subr_char_code:
    call check_char
    srl h
    rr l
    set 0,l
    ret
subr_code_char:
    call fixnum_hl
    bit 7,h
    jr nz,.bad
    add hl,hl
    ld a,h
    cp 4
    ret c
.bad:
    ex de,hl
    ld hl,m_notchar
    jp error

;; (char string index)
subr_char:
    call string_index
    ld l,(hl)
    ld h,0
    add hl,hl
    add hl,hl
    inc hl
    inc hl
    ret

;; set_char: HL = string, DE = index, BC = character
set_char:
    push bc
    call string_index
    pop de
    ex de,hl
    call check_char
    srl h
    rr l
    srl h
    rr l
    ex de,hl
    ld (hl),e
    ret

;; string_index: HL = string, DE = index -> HL = address of that character
string_index:
    call check_string
    call fixnum_de
    sra d
    rr e
    bit 7,d
    jr nz,.bad
    push de
    call str_data
    pop de
    push hl
    ld l,c
    ld h,b
    scf
    sbc hl,de                   ; length - 1 - index
    pop hl
    jr c,.bad
    add hl,de
    ret
.bad:
    ld de,UNBOUND
    ld hl,m_index
    jp error

;; (string x): a string, a symbol's name, or a character
subr_string:
    call is_string
    ret z
    ld a,l
    and 3
    cp 2
    jr nz,.sym
    ld a,h
    cp 4
    jr nc,.sym
    srl h
    rr l
    srl h
    rr l
    ld a,l
    ld (TOKBUF),a
    ld hl,TOKBUF
    ld bc,1
    jp make_string
.sym:
    jp subr_symbol_name

;; ---------------------------------------------------------------------------
;; EVALUATION

subr_eval:
    ld de,(V_ENV)
    push de
    ld de,NIL
    ld (V_ENV),de
    call eval
    pop de
    ld (V_ENV),de
    ret

subr_macroexpand_1:
    jp macroexpand1
subr_macroexpand:
.l:
    call macroexpand1
    jr c,.l
    ret

;; ---------------------------------------------------------------------------
;; THE SYSTEM

subr_gc:
    call gc
    ld hl,(V_NFREE)
    add hl,hl
    inc hl
    ret
