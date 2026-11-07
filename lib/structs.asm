;; CPC Lisp -- structures and hashing (library ROM, part 1): what defstruct
;; and the hash tables (Lisp, in lisp.lsp) stand on.
;;
;; A structure is a vector by another header (HDR_STRUCT): element 0 is its
;; type, a symbol, and slot i is element i. The GC treats it as a vector;
;; the printer shows #S(type slot...).

st_m_type:  db "not the structure it should be:",0

;; st_is: HL -> Z if it is a structure. HL, DE kept.
st_is:
    push bc
    ld c,HDR_STRUCT and #FF
    CORE is_typed
    pop bc
    ret

;; (make-array n [:initial-element x]): a vector of n, each x (NIL). Other
;; keywords (:element-type...) are let be.
;@ MAKE-ARRAY 1 255 lf_make_array
lf_make_array:
    NEXTARG
    push de                     ; n
    ld de,NIL
    dec b
.k:
    ld a,b
    cp 2
    jr c,.go
    push de
    NEXTARG
    ld a,e
    cp S_KW_INITIAL_ELEMENT and #FF
    jr nz,.skip
    ld a,d
    cp S_KW_INITIAL_ELEMENT >> 8
.skip:
    pop de
    jr nz,.other
    NEXTARG
    jr .n
.other:
    dec hl
    dec hl
.n:
    dec b
    dec b
    jr .k
.go:
    pop hl
    push de
    call lfix_hl
    pop de
    sra h
    rr l
    bit 7,h
    jr nz,.bad
    ld b,h
    ld c,l
    CORE make_vector
    ret
.bad:
    add hl,hl
    inc hl
    ex de,hl
    ld hl,m_index
    CORE error

;; (%make-struct type value...) -> a new structure of them
;@ %MAKE-STRUCT 1 255 lf_make_struct
lf_make_struct:
    CORE args_to_list
    call lq_listvec             ; a vector of them,
st_mark:                        ;   made a structure
    dec hl
    dec hl
    ld (hl),HDR_STRUCT and #FF
    inc hl
    inc hl
    ret

;; st_slot: HL = a structure, DE = an index (a fixnum), BC = its type ->
;; HL = the slot's address. An error unless it is that and the index fits.
st_slot:
    push hl                     ; for the error
    call st_is
    jr nz,.bad
    push de
    push bc
    CORE vec_data               ; HL = element 0, BC = how many
    pop de                      ; the type
    ld a,(hl)
    cp e
    jr nz,.bad1
    inc hl
    ld a,(hl)
    cp d
    jr nz,.bad1
    dec hl
    pop de                      ; the index
    bit 0,e
    jr z,.bad
    sra d
    rr e
    ld a,d
    or a
    jr nz,.bad
    ld a,e
    or a
    jr z,.bad
    push hl
    ld l,e
    ld h,0
    or a
    sbc hl,bc
    pop hl
    jr nc,.bad
    add hl,de
    add hl,de
    pop de
    ret
.bad1:
    pop de
.bad:
    pop de
    ld hl,st_m_type
    jp lib_error

;; (%struct-ref s i type) -> slot i of s, which must be a type
;@ %STRUCT-REF 3 3 lf_struct_ref
lf_struct_ref:
    call st_slot
    LDHLI
    ret

;; (%struct-set s i value type) -> value, now in slot i
;@ %STRUCT-SET 4 4 lf_struct_set
lf_struct_set:
    NEXTARG
    push de                     ; s
    NEXTARG
    push de                     ; i
    NEXTARG
    ld (V_S1),de                ; the value (nothing allocates till it is in)
    NEXTARG
    ld c,e
    ld b,d                      ; the type
    pop de
    pop hl
    call st_slot
    ld de,(V_S1)
    ld (hl),e
    inc hl
    ld (hl),d
    ex de,hl
    ret

;; (%struct-is x type) -> T if x is a structure of that type
;@ %STRUCT-IS 2 2 lf_struct_is
lf_struct_is:
    call st_is
    jp nz,lnil
    push de
    CORE vec_data
    pop de
    ld a,(hl)
    cp e
    jp nz,lnil
    inc hl
    ld a,(hl)
    cp d
    jp nz,lnil
    jp lt

;; (%struct-type x) -> its type if it is a structure, else NIL
;@ %STRUCT-TYPE 1 1 lf_struct_type
lf_struct_type:
    call st_is
    jp nz,lnil
    CORE vec_data
    LDHLI
    ret

;; (copy-structure s) -> a new structure with the same slots
;@ COPY-STRUCTURE 1 1 lf_copy_structure
lf_copy_structure:
    call st_is
    jr nz,.bad
    push hl
    CORE vec_data               ; BC = how many
    ld de,NIL
    CORE make_vector
    pop de                      ; the old one
    push hl
    push de
    CORE vec_data               ; the new one's elements (nothing moves now)
    ex (sp),hl
    CORE vec_data               ; the old one's, BC = how many
    pop de
    sla c
    rl b
    ldir
    pop hl
    jp st_mark
.bad:
    ex de,hl
    ld hl,st_m_type
    jp lib_error

;; ---------------------------------------------------------------------------
;; HASHING

;; (sxhash x) -> a fixnum, the same for any two things equal: strings by
;; their characters, conses by their parts (four deep), floats by value,
;; anything else by itself
;@ SXHASH 1 1 lf_sxhash
lf_sxhash:
    ld b,4
    call sx_hash
    jr sx_fix

;; (%eqhash x) -> a fixnum, the same for any two things eql: floats by
;; value, anything else by itself (not by its contents: it may change)
;@ %EQHASH 1 1 lf_eqhash
lf_eqhash:
    ld b,0
    call sx_hash
sx_fix:
    ex de,hl                    ; DE -> a fixnum 0..16383
    res 7,h
    res 6,h
    add hl,hl
    inc hl
    ret

;; sx_hash: HL = an object, B = how deep conses are followed (0: not, nor
;; strings) -> DE = its hash. B kept.
sx_hash:
    ld a,l
    and 3
    jr nz,.atom
    ld a,h
    or l
    jr z,.word                  ; NIL
    ld a,b
    or a
    jr z,.word                  ; a cons, by itself
    dec b
    push hl
    LDHLI
    call sx_hash                ; its car,
    pop hl
    push de
    CDRHL
    call sx_hash                ;   its cdr
    inc b
    pop hl
    add hl,hl                   ; car * 2 + cdr, a little mixed
    add hl,hl
    add hl,hl
    add hl,de
    ex de,hl
    ret
.atom:
    push hl
    CORE is_float
    pop hl
    jr z,.bytes
    ld a,b
    or a
    jr z,.word
    push hl
    CORE is_string
    pop hl
    jr nz,.word
.bytes:                         ; a string's characters, a float's bytes
    push bc
    CORE str_data               ; (a float's block is read the same way)
    ld de,0
.c:
    ld a,b
    or c
    jr z,.cd
    push hl
    ld l,e                      ; * 31 + the byte
    ld h,d
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    or a
    sbc hl,de
    ex de,hl
    pop hl
    ld a,(hl)
    add a,e
    ld e,a
    jr nc,.nc
    inc d
.nc:
    inc hl
    dec bc
    jr .c
.cd:
    pop bc
    ret
.word:
    ld e,l                      ; the word itself, its halves mixed
    ld a,h
    xor l
    ld d,a
    srl d
    rr e
    ret

;; ---------------------------------------------------------------------------
;; HASH TABLES: a structure [HASH-TABLE test count buckets], test EQ, EQL or
;; EQUAL, buckets a vector of alists. make-hash-table, maphash and the rest
;; are Lisp (lisp.lsp); these three are here for speed.

HT_MODE     equ V_S2            ; 0 eq, 1 eql, 2 equal (while nothing allocates)
HT_KEY      equ V_S3            ; the key (it is among the arguments, for the GC)

ht_m_bad:   db "not a hash table:",0

;; ht_find: HL = a hash table, DE = a key -> HL = the address of the key's
;; bucket in the buckets' block (good until something allocates), DE = the
;; entry (key . value), or NIL
ht_find:
    ld (HT_KEY),de
    push hl
    call st_is
    jp nz,.bad
    CORE vec_data               ; [type test count buckets]
    ld a,c
    cp 4
    jp nz,.bad
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; the test
    inc hl
    inc hl
    inc hl
    push hl
    ld a,2
    ld hl,S_EQUAL
    or a
    sbc hl,de
    jr z,.mode
    xor a
    ld hl,S_EQ
    sbc hl,de
    jr z,.mode
    ld a,1
.mode:
    ld (HT_MODE),a
    pop hl
    LDHLI                       ; the buckets
    push hl
    ld hl,(HT_KEY)
    ld b,0                      ; EQ and EQL: by itself
    ld a,(HT_MODE)              ; (LDHLI took A)
    cp 2
    jr nz,.hash
    ld b,4                      ; EQUAL: by its contents
.hash:
    call sx_hash                ; DE = the hash
    pop hl
    push de
    CORE vec_data               ; HL = the buckets, C = how many
    ex (sp),hl
    call ht_mod                 ; A = the hash modulo that
    pop hl
    ld e,a
    ld d,0
    add hl,de
    add hl,de                   ; the bucket's address
    pop de                      ; (the table)
    push hl
    LDHLI                       ; its alist
.l:
    ld a,h
    or l
    jr z,.none
    push hl
    LDHLI                       ; an entry
    ld a,h
    or l
    jr z,.next
    push hl
    LDHLI                       ; its key
    ld de,(HT_KEY)
    call ht_same
    pop de
    jr z,.found
.next:
    pop hl
    CDRHL
    jr .l
.found:
    pop hl
    pop hl
    ret
.none:
    ld de,NIL
    pop hl
    ret
.bad:
    pop de
    ld hl,ht_m_bad
    jp lib_error

;; ht_same: HL, DE -> Z if they are the same key, by HT_MODE
ht_same:
    ld a,(HT_MODE)
    or a
    jr nz,.eql
    sbc hl,de
    ret
.eql:
    dec a
    jr nz,.equal
    CORE eql
    ret
.equal:
    CORE equal
    ret

;; ht_mod: HL = a number, C = 1..255 -> A = HL modulo C
ht_mod:
    xor a
    ld b,16
.l:
    add hl,hl
    rla
    jr c,.s
    cp c
    jr c,.n
.s:
    sub c
.n:
    djnz .l
    ret

;; ht_count: HL = a hash table, DE = 2 or -2 -> its count up or down one
ht_count:
    push de
    CORE vec_data
    ld de,4
    add hl,de                   ; element 2
    pop de
    ld a,(hl)
    inc hl
    push hl
    ld h,(hl)
    ld l,a
    add hl,de
    ex de,hl
    pop hl
    ld (hl),d
    dec hl
    ld (hl),e
    ret

;; (gethash key table [default]) -> its value and T, or default and NIL
;@ GETHASH 2 3 lf_gethash
lf_gethash:
    NEXTARG
    push de                     ; the key
    NEXTARG
    push de                     ; the table
    ld de,NIL
    ld a,b
    cp 3
    jr nz,.nd
    NEXTARG
.nd:
    ld (V_S1),de                ; the default
    pop hl
    pop de
    call ht_find
    ld a,d
    or e
    jr z,.none
    ex de,hl
    CDRHL
    ld de,S_T
    jr .mv
.none:
    ld hl,(V_S1)
.mv:
    ld (V_MV1),hl
    ld (V_MV2),de
    ld a,3
    ld (V_MVN),a
    ret

;; (%puthash key table [default] value) -> value: (setf (gethash ...)).
;; The two conses a new entry needs are made first, before a bucket's
;; address is held.
;@ %PUTHASH 3 4 lf_puthash
lf_puthash:
    NEXTARG
    push de                     ; the key
    NEXTARG
    push de                     ; the table
    ld a,b
    cp 4
    jr nz,.v
    NEXTARG                     ; (the default: nothing to do with it)
.v:
    NEXTARG
    ld (V_S1),de                ; the value (among the arguments too)
    ld hl,2
    add hl,sp
    LDHLI                       ; the key
    CORE cons                   ; (key . value)
    ld de,NIL
    CORE cons                   ; ((key . value))
    push hl                     ; [cell][table][key]
    ld hl,4
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; the key
    ld hl,2
    add hl,sp
    LDHLI                       ; the table
    call ht_find
    ld a,d
    or e
    jr nz,.update
    pop bc                      ; the cell: in front of the bucket's list
    push hl
    LDHLI
    ex de,hl
    ld l,c
    ld h,b
    inc hl
    inc hl
    ld (hl),e
    inc hl
    ld (hl),d
    pop hl
    ld (hl),c
    inc hl
    ld (hl),b
    pop hl                      ; the table
    pop de
    ld de,2
    call ht_count
    ld hl,(V_S1)
    ret
.update:                        ; there already: a new value
    pop hl
    pop hl
    pop hl
    ex de,hl
    inc hl
    inc hl
    ld de,(V_S1)
    ld (hl),e
    inc hl
    ld (hl),d
    ex de,hl
    ret

;; (remhash key table) -> T if it was there (it is not now), else NIL
;@ REMHASH 2 2 lf_remhash
lf_remhash:
    ex de,hl
    push hl                     ; the table
    call ht_find
    ld a,d
    or e
    jr z,.no
    ld (V_S1),de                ; the entry
.l:                             ; HL = a word holding the rest of the list
    push hl
    LDHLI                       ; a cons
    push hl
    LDHLI
    ld de,(V_S1)
    or a
    sbc hl,de
    pop hl
    jr z,.unlink
    pop de
    inc hl
    inc hl                      ; its cdr's word
    jr .l
.unlink:
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; what follows it
    pop hl
    ld (hl),e
    inc hl
    ld (hl),d
    pop hl
    ld de,-2
    call ht_count
    jp lt
.no:
    pop hl
    jp lnil
