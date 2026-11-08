;; CPC Lisp -- lists, sequences, symbols and bits (library ROM, part 1).
;;
;; Some of these were in the core and moved out to make room there:
;; member, assoc, reverse, nreverse, the log functions, ash, gensym,
;; intern, remprop, room. Out here they grew what CL gives them: :test,
;; :test-not and :key on member, assoc and rassoc; strings and vectors for
;; reverse and nreverse. coerce converts between lists, vectors and
;; strings (and to characters and floats).

;; ---------------------------------------------------------------------------
;; MEMBER, ASSOC, RASSOC with keywords

;; the frame, on the machine stack where the GC sees it, at IX; the
;; sequence functions (seqfn.asm) use the same one, larger
LK_ITEM     equ 0               ; what is looked for
LK_TEST     equ 2               ; the test, NIL for eql (the predicate, for -if)
LK_KEY      equ 4               ; the key, NIL for none
LK_NOT      equ 6               ; 1 for :test-not or -if-not (a word: the GC
                                ;   skips it)
LK_LIST     equ 8               ; the list, as far as it has been searched
LK_MODE     equ 10              ; 0 member, 1 assoc, 2 rassoc
SQ_START    equ 12              ; :start, :end, :from-end, :count as given
SQ_END      equ 14
SQ_FROMEND  equ 16
SQ_COUNT    equ 18
SQ_IF       equ 20              ; 1: the predicate takes the element alone
SQ_OP       equ 22              ; seqfn.asm's operation
SQ_NEW      equ 24              ; substitute's new element
SQ_I        equ 26              ; the index
SQ_HIT      equ 28              ; :from-end: the last match,
SQ_HITI     equ 30              ;   its index
SQ_N        equ 32              ; matches seen
SQ_RES      equ 34              ; remove, substitute: what is kept, reversed
SQ_SKIP     equ 36              ; matches to keep before dropping
SQ_SEQ      equ 38              ; the sequence as given
LK_SIZE     equ 40

;@ MEMBER 2 255 lf_member
lf_member:
    xor a
    jr lk_go
;@ ASSOC 2 255 lf_assoc
lf_assoc:
    ld a,1
    jr lk_go
;@ RASSOC 2 255 lf_rassoc
lf_rassoc:
    ld a,2
lk_go:
    call lk_frame
    ld (ix+LK_MODE),a
    NEXTARG
    ld (ix+LK_ITEM),e
    ld (ix+LK_ITEM+1),d
    NEXTARG
    ld (ix+LK_LIST),e
    ld (ix+LK_LIST+1),d
    dec b
    dec b
    call lk_keys
.l:
    ld l,(ix+LK_LIST)
    ld h,(ix+LK_LIST+1)
    ld a,h
    or l
    jr z,.out                   ; not there: NIL
    ld a,l
    and 3
    jr nz,.notlist
    LDHLI                       ; the element
    ld a,(ix+LK_MODE)
    or a
    jr z,.match                 ; member: the element itself
    ld a,h
    or l
    jr z,.next                  ; assoc and rassoc skip a NIL in the alist
    ld a,(ix+LK_MODE)
    dec a
    jr nz,.cdr
    LDHLI                       ; assoc: its car
    jr .match
.cdr:
    CDRHL                       ; rassoc: its cdr
.match:
    ex de,hl
    call lk_match
    jr nz,.found
.next:
    ld l,(ix+LK_LIST)
    ld h,(ix+LK_LIST+1)
    CDRHL
    ld (ix+LK_LIST),l
    ld (ix+LK_LIST+1),h
    jr .l
.found:
    ld l,(ix+LK_LIST)
    ld h,(ix+LK_LIST+1)
    ld a,(ix+LK_MODE)
    or a
    jr z,.out                   ; member: the tail
    LDHLI                       ; assoc, rassoc: the pair
.out:
    ex de,hl
    ld hl,LK_SIZE
    add hl,sp
    ld sp,hl
    ex de,hl
    ret
.notlist:
    ex de,hl
    ld hl,m_notlist
    CORE error

;; lk_frame: a frame of LK_SIZE below the caller's return address, all
;; NIL, at IX (the caller pops it: LK_SIZE bytes). A, BC, HL kept.
lk_frame:
    pop de                      ; the return address
    ld ix,-LK_SIZE
    add ix,sp
    ld sp,ix
    push de
    push hl
    push bc
    push ix
    pop hl
    ld b,LK_SIZE
.z:
    ld (hl),0
    inc hl
    djnz .z
    pop bc
    pop hl
    ret

;; lk_keys: IX = the frame, HL = &the first keyword argument, B = how many
;; words are left -> :test, :test-not, :key (and :start, :end, :from-end,
;; :count) in the frame. Others are let be, as &key does.
lk_keys:
    ld a,b
    cp 2
    ret c
    dec b
    dec b
    NEXTARG                     ; DE = a keyword
    push de
    NEXTARG                     ; DE = its value
    ex (sp),hl                  ; HL = the keyword, the argument pointer kept
    push bc
    ex de,hl                    ; DE = the keyword, HL = the value
    push hl
    ld c,LK_KEY
    ld hl,S_KW_KEY
    or a
    sbc hl,de
    jr z,.set
    ld c,LK_TEST
    ld hl,S_KW_TEST
    or a
    sbc hl,de
    jr z,.set
    ld c,SQ_START
    ld hl,S_KW_START
    or a
    sbc hl,de
    jr z,.set
    ld c,SQ_END
    ld hl,S_KW_END
    or a
    sbc hl,de
    jr z,.set
    ld c,SQ_FROMEND
    ld hl,S_KW_FROM_END
    or a
    sbc hl,de
    jr z,.set
    ld c,SQ_COUNT
    ld hl,S_KW_COUNT
    or a
    sbc hl,de
    jr z,.set
    ld hl,S_KW_TEST_NOT
    or a
    sbc hl,de
    jr nz,.skip
    pop hl
    push hl
    ld a,h
    or l
    jr z,.skip                  ; :test-not nil: as if not given
    ld (ix+LK_NOT),1
    ld c,LK_TEST
.set:
    push ix
    pop hl
    ld b,0
    add hl,bc
    pop de
    ld (hl),e
    inc hl
    ld (hl),d
    jr .done
.skip:
    pop de
.done:
    pop bc
    pop hl
    jr lk_keys

;; lk_match: IX = the frame, DE = an element -> NZ if it matches the item:
;; (test item (key element)), or not for :test-not
lk_match:
    ld l,(ix+LK_KEY)
    ld h,(ix+LK_KEY+1)
    ld a,h
    or l
    jr z,.keyed
    SCORE apply1                ; (key element)
    ex de,hl
.keyed:
    ld a,(ix+SQ_IF)
    or a
    jp nz,.pred
    ld l,(ix+LK_TEST)
    ld h,(ix+LK_TEST+1)
    ld a,h
    or l
    jr z,.eql
    push de
    ld de,E_EQL+2               ; the usual tests, called directly
    or a
    sbc hl,de
    jr z,.eql1
    ld de,E_EQ-E_EQL
    or a
    sbc hl,de
    jr z,.eq1
    ld de,E_EQUAL-E_EQ
    or a
    sbc hl,de
    jr z,.equal1
    pop bc                      ; any other: (test item element)
    ld e,(ix+LK_ITEM)
    ld d,(ix+LK_ITEM+1)
    ld l,(ix+LK_TEST)
    ld h,(ix+LK_TEST+1)
    SCORE apply2
    ld a,h
    or l
    ld a,0
    jr z,.r
    inc a
    jr .r
.eq1:
    pop de
    ld l,(ix+LK_ITEM)
    ld h,(ix+LK_ITEM+1)
    or a
    sbc hl,de
    jr .z
.equal1:
    pop de
    ld l,(ix+LK_ITEM)
    ld h,(ix+LK_ITEM+1)
    SCORE equal
    jr .z
.eql1:
    pop de
.eql:
    ld l,(ix+LK_ITEM)
    ld h,(ix+LK_ITEM+1)
    SCORE eql
.z:
    ld a,0
    jr nz,.r
    inc a
.r:
    xor (ix+LK_NOT)
    ret
.pred:                          ; -if: (predicate element)
    ld l,(ix+LK_TEST)
    ld h,(ix+LK_TEST+1)
    SCORE apply1
    ld a,h
    or l
    ld a,0
    jr z,.r
    inc a
    jr .r

;; ---------------------------------------------------------------------------
;; REVERSE, NREVERSE

;@ REVERSE 1 1 lf_reverse
lf_reverse:
    ld a,l
    and 3
    jr nz,lq_reverse            ; a string or a vector
    CORE reverse                ; a list (or an error)
    ret

;@ NREVERSE 1 1 lf_nreverse
lf_nreverse:
    ld a,l
    and 3
    jr nz,.inplace
    ld a,h
    or l
    ret z
    ld de,NIL
    CORE nreverse_onto
    ret
.inplace:                       ; a string or a vector, reversed where it is
    push hl
    call lq_data                ; HL = the first, BC = how many, A = width
    push hl
    dec bc                      ; DE = the last
    ld e,c
    ld d,b
    cp 2
    jr nz,.bytes
    ex de,hl
    add hl,hl
    ex de,hl
.bytes:
    ex de,hl
    add hl,de
    ex de,hl
    pop hl
.swap:                          ; HL from the front, DE from the back
    or a
    push hl
    sbc hl,de
    pop hl
    jr nc,.done
    ld c,(hl)
    ex de,hl
    ld b,(hl)
    ld (hl),c
    ex de,hl
    ld (hl),b
    inc hl
    cp 2
    jr nz,.one
    ld c,(hl)                   ; a vector's words: the high bytes too
    inc de
    ex de,hl
    ld b,(hl)
    ld (hl),c
    ex de,hl
    ld (hl),b
    inc hl
    dec de
    dec de
.one:
    dec de
    jr .swap
.done:
    pop hl
    ret

;; lq_reverse: HL = a string or a vector -> a new one, reversed
lq_reverse:
    push hl
    CORE is_string
    pop hl
    jr nz,.vector
    call lstring                ; HL = the characters, BC = how many
    call lq_short
    ld de,TOKBUF-1
    ex de,hl
    add hl,bc
    ld a,c
    or a
    jr z,.empty
    ld b,c
.c:
    ld a,(de)
    ld (hl),a
    inc de
    dec hl
    djnz .c
.empty:
    jp lstr_result
.vector:
    call lq_tolist              ; its elements, reversed, as a list,
    jp lq_listvec               ;   then as a vector

;; lq_data: HL = a string or a vector -> HL = its first element, BC = how
;; many, A = their width (1 or 2). An error for anything else.
lq_data:
    push hl
    CORE is_string
    pop hl
    jr nz,.vec
    CORE str_data
    ld a,1
    ret
.vec:
    push hl
    CORE is_vector
    pop hl
    jr nz,lq_notseq
    CORE vec_data
    ld a,2
    ret

lq_notseq:
    ex de,hl
    ld hl,lq_m_seq
    jp lib_error
lq_m_seq:   db "not a sequence:",0
lq_m_long:  db "too long for a string",0
lq_m_type:  db "cannot coerce to",0

;; lq_short: BC = a length -> an error unless it fits in a string (255)
lq_short:
    ld a,b
    or a
    ret z
    ld hl,lq_m_long
    ld de,UNBOUND
    jp lib_error

;; ---------------------------------------------------------------------------
;; COERCE, and the conversions behind it

;; lq_tolist: HL = a sequence -> a list of its elements; a string's and a
;; vector's come out REVERSED (lq_tolist_fwd puts them right)
lq_tolist:
    ld a,l
    and 3
    ret z                       ; a list already (not reversed)
    push hl                     ; the sequence, while the list is built
    ld de,NIL
    push de                     ; the list so far
    ld bc,0                     ; the index
.l:
    ld hl,2
    add hl,sp
    LDHLI                       ; the sequence again: the GC may have moved it
    push bc
    call lq_data                ; HL = the first, BC = how many, A = width
    pop de                      ; DE = the index
    push de
    ex de,hl
    or a
    sbc hl,bc
    jr nc,.done                 ; past the end
    add hl,bc
    ex de,hl                    ; HL = the first, DE = the index
    add hl,de
    cp 2
    jr nz,.char
    add hl,de
    LDHLI                       ; a vector's element
    jr .got
.char:
    ld l,(hl)                   ; a character: 4 * code + 2
    ld h,0
    add hl,hl
    add hl,hl
    inc hl
    inc hl
.got:
    pop bc
    pop de                      ; the list so far
    SCORE cons
    push hl
    inc bc
    jr .l
.done:
    pop bc
    pop hl                      ; the list
    pop de
    ret

;; lq_tolist_fwd: HL = a sequence -> a list of its elements, in order
lq_tolist_fwd:
    ld a,l
    and 3
    ret z
    call lq_tolist
    ld de,NIL
    CORE nreverse_onto
    ret

;; lq_listvec: HL = a list -> a new vector of its elements
lq_listvec:
    push hl
    ld bc,0
.n:
    ld a,h
    or l
    jr z,.counted
    inc bc
    CDRHL
    jr .n
.counted:
    ld de,NIL
    CORE make_vector            ; HL = the vector
    pop de                      ; the list (reachable from the stack until now)
    push hl
    push de
    CORE vec_data               ; HL = its elements: nothing allocates now
    pop de
.f:
    ld a,d
    or e
    jr z,.filled
    ex de,hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    LDHLI                       ; the next cons
    ex de,hl
    ld (hl),c
    inc hl
    ld (hl),b
    inc hl
    jr .f
.filled:
    pop hl
    ret

;; lq_liststr: HL = a list of characters -> a new string of them
lq_liststr:
    ld de,TOKBUF
    ld c,0
.l:
    ld a,h
    or l
    jr z,.done
    ld a,l
    and 3
    jr nz,.bad
    push hl
    LDHLI                       ; a character: 4 * code + 2, below &0400
    ld a,l
    and 3
    cp 2
    jr nz,.badc
    ld a,h
    cp 4
    jr nc,.badc
    srl h
    rr l
    srl h
    rr l
    ld a,l
    ld (de),a
    inc de
    pop hl
    CDRHL
    inc c
    jr nz,.l
    ld bc,256
    jp lq_short
.done:
    jp lstr_result
.badc:
    pop de
    ex de,hl
    ld hl,m_notchar
    CORE error
.bad:
    jp lq_notseq

;; (coerce object type): to LIST, VECTOR, SIMPLE-VECTOR, STRING,
;; SIMPLE-STRING, CHARACTER, FLOAT, SINGLE-FLOAT, DOUBLE-FLOAT, or T
;@ COERCE 2 2 lf_coerce
lf_coerce:
    ex de,hl                    ; HL = the type, DE = the object
    push de
    ld de,S_T
    call lq_is
    jr z,.same
    ld de,S_LIST
    call lq_is
    jr z,.list
    ld de,lq_n_vec
    call lq_named
    jr z,.vector
    ld de,lq_n_svec
    call lq_named
    jr z,.vector
    ld de,S_STRING
    call lq_is
    jr z,.string
    ld de,lq_n_sstr
    call lq_named
    jr z,.string
    ld de,lq_n_char
    call lq_named
    jr z,.char
    ld de,lq_n_float
    call lq_named
    jp z,.float
    ld de,lq_n_single
    call lq_named
    jp z,.float
    ld de,lq_n_double
    call lq_named
    jp z,.float
    ex de,hl
    ld hl,lq_m_type
    jp lib_error
.same:
    pop hl
    ret
.list:
    pop hl
    jp lq_tolist_fwd
.vector:
    pop hl
    push hl
    CORE is_vector
    pop hl
    ret z
    call lq_tolist_fwd
    jp lq_listvec
.string:
    pop hl
    push hl
    CORE is_string
    pop hl
    ret z
    call lq_tolist_fwd
    jp lq_liststr
.char:
    pop hl                      ; a character, or a string or symbol of one
    ld a,l
    and 3
    cp 2
    jr nz,.cbad
    ld a,h
    cp 4
    ret c                       ; a character
    push hl
    CORE is_symbol
    jr z,.cname
    CORE is_string
    jr nz,.cbad0
.cname:
    CORE str_data               ; its name, or its characters
    pop de
    ld a,b
    or a
    jr nz,.cbad1
    dec c
    jr nz,.cbad1
    ld l,(hl)                   ; the one character
    ld h,0
    add hl,hl
    add hl,hl
    inc hl
    inc hl
    ret
.cbad0:
    pop hl
    jr .cbad
.cbad1:
    ex de,hl
.cbad:
    ex de,hl
    ld hl,lq_m_type
    jp lib_error
.float:
    pop hl
    jp lf_float

;; lq_is: HL = a type, DE = a symbol -> Z if they are the same. HL kept.
lq_is:
    push hl
    or a
    sbc hl,de
    pop hl
    ret

;; lq_named: HL = a type, DE = a name in this ROM (length first) -> Z if
;; it is a symbol of that name. HL kept.
lq_named:
    push hl
    push de
    CORE is_symbol
    jr nz,.no
    ld de,SYM_LO+2+8*NBUILTIN   ; a builtin's name is in the core ROM: none
    or a                        ;   of these names is one
    sbc hl,de
    add hl,de
    jr c,.no1
    CORE str_data               ; its name: HL = the characters, C = how many
    pop de
    push de
    ld a,b
    or a
    jr nz,.no
    ld a,(de)
    cp c
    jr nz,.no
    ld b,c
.c:
    inc de
    ld a,(de)
    cp (hl)
    jr nz,.no
    inc hl
    djnz .c
.no:
    pop de
    pop hl
    ret
.no1:
    or 1
    jr .no

lq_n_svec:   db 13,"SIMPLE-VECTOR"
lq_n_vec:    db 6,"VECTOR"
lq_n_sstr:   db 13,"SIMPLE-STRING"
lq_n_char:   db 9,"CHARACTER"
lq_n_float:  db 5,"FLOAT"
lq_n_single: db 12,"SINGLE-FLOAT"
lq_n_double: db 12,"DOUBLE-FLOAT"

;; ---------------------------------------------------------------------------
;; MULTIPLE VALUES: the core keeps them (V_MVN, V_MV1, V_MV2, V_MVL) and
;; multiple-value-list reads them

;; (values ...) -> the first (NIL if there is none); all of them for
;; multiple-value-list and what is built on it
;@ VALUES 0 255 lf_values
lf_values:
    ld a,b
    inc a
    ld (V_MVN),a                ; how many, plus one
    ld de,NIL
    ld (V_MV1),de
    ld (V_MV2),de
    ld (V_MVL),de
    ld a,b
    or a
    jr z,.done
    NEXTARG
    ld (V_MV1),de
    dec b
    jr z,.done
    NEXTARG
    ld (V_MV2),de
    dec b
    jr z,.done
    CORE args_to_list           ; the third on, as a list
    ld (V_MVL),hl
.done:
    ld hl,(V_MV1)
    ret

;; ---------------------------------------------------------------------------
;; BITS

;@ LOGAND 0 255 lf_logand
lf_logand:
    ld c,0
    ld de,#FFFF                 ; -1
    jr lg_go
;@ LOGIOR 0 255 lf_logior
lf_logior:
    ld c,1
    ld de,1                     ; 0
    jr lg_go
;@ LOGXOR 0 255 lf_logxor
lf_logxor:
    ld c,2
    ld de,1
lg_go:
    ld a,b
    or a
    jr z,.done
    push de                     ; the result so far
    NEXTARG
    call lfix_de
    ex (sp),hl                  ; HL = so far, the argument pointer kept
    ld a,c
    or a
    jr nz,.or
    ld a,l
    and e
    ld l,a
    ld a,h
    and d
    jr .next
.or:
    dec a
    jr nz,.xor
    ld a,l
    or e
    ld l,a
    ld a,h
    or d
    jr .next
.xor:
    ld a,l
    xor e
    or 1                        ; still a fixnum
    ld l,a
    ld a,h
    xor d
.next:
    ld h,a
    ex de,hl
    pop hl
    dec b
    jr lg_go
.done:
    ex de,hl
    ret

;@ LOGNOT 1 1 lf_lognot
lf_lognot:
    call lfix_hl
    ld a,l
    cpl
    or 1
    ld l,a
    ld a,h
    cpl
    ld h,a
    ret

;; (ash n count): n shifted left by count, right if it is negative
;@ ASH 2 2 lf_ash
lf_ash:
    call lfix_hl
    call lfix_de
    sra h
    rr l
    ex de,hl
    sra h
    rr l
    ex de,hl
    bit 7,d
    jr nz,.right
.left:
    ld a,d
    or e
    jr z,.tag
    ld a,h
    and #C0
    jr z,.ok
    cp #C0
    jr nz,.ovf
.ok:
    add hl,hl
    dec de
    jr .left
.right:
    ld a,d
    or e
    jr z,.tag
    sra h
    rr l
    inc de
    jr .right
.tag:
    ld a,h                      ; back to a fixnum, if it is one
    and #C0
    jr z,.t
    cp #C0
    jr nz,.ovf
.t:
    add hl,hl
    inc hl
    ret
.ovf:
    ld hl,m_overflow
    ld de,UNBOUND
    CORE error

;; ---------------------------------------------------------------------------
;; SYMBOLS

;; (gensym [prefix]): a new symbol nobody else has, G1, G2... (or prefix1)
;@ GENSYM 0 1 lf_gensym
lf_gensym:
    ld de,TOKBUF
    ld a,b
    or a
    jr z,.g
    LDHLI                       ; the prefix: a string
    call lstring
    call lq_short
    ld a,c
    cp 200
    jr nc,.g
    or a
    jr z,.p
    ldir
    jr .p
.g:
    ld a,"G"
    ld (de),a
    inc de
.p:
    ld hl,(V_GENSYM)
    inc hl
    ld (V_GENSYM),hl
    call lq_utoa
    ld a,e
    sub TOKBUF and #FF
    ld b,a
    CORE make_symbol
    ret

;; lq_utoa: HL = 0..65535 -> its digits at DE, DE moved past them
lq_utoa:
    push de
    pop ix                      ; where the digits go
    ld c,0                      ; no digit yet
    ld de,-10000
    call .d
    ld de,-1000
    call .d
    ld de,-100
    call .d
    ld de,-10
    call .d
    ld a,l
    add a,"0"
    ld (ix+0),a
    inc ix
    push ix
    pop de
    ret
.d:
    ld a,"0"-1
.l:
    inc a
    add hl,de
    jr c,.l
    sbc hl,de
    cp "0"
    jr nz,.p
    bit 0,c
    ret z                       ; a leading zero
.p:
    set 0,c
    ld (ix+0),a
    inc ix
    ret

;; (intern string) -> the symbol of that name, made if there is none
;@ INTERN 1 1 lf_intern
lf_intern:
    call lstring
    call lq_short
    ld b,c
    ld de,TOKBUF
    ld a,c
    or a
    jr z,.e
    push bc
    ld b,0
    ldir
    pop bc
.e:
    CORE intern
    ret

;; (remprop symbol indicator) -> T if it had that property, else NIL
;@ REMPROP 2 2 lf_remprop
lf_remprop:
    CORE sym_slot
    dec hl
    dec hl                      ; the plist word (its low bits are flags)
    push hl
    LDHLI
    ld a,l
    and #FC
    ld l,a
    ld bc,0                     ; the cons before, none yet
.l:
    ld a,h
    or l
    jr z,.no
    push hl
    LDHLI                       ; this pair's indicator
    or a
    sbc hl,de
    pop hl
    jr z,.found
    CDRHL
    ld c,l
    ld b,h                      ; the value's cons
    CDRHL
    jr .l
.found:
    CDRHL
    CDRHL                       ; what follows the pair
    ld a,b
    or c
    jr z,.first
    ex de,hl
    ld l,c
    ld h,b
    inc hl
    inc hl
    ld (hl),e
    inc hl
    ld (hl),d
    pop hl
    jp lt
.first:
    ex de,hl
    pop hl
    ld a,(hl)
    and 3
    or e
    ld (hl),a
    inc hl
    ld (hl),d
    jp lt
.no:
    pop hl
    jp lnil

;; (room): collects, then says what is free
;@ ROOM 0 1 lf_room
lf_room:
    CORE gc
    ld hl,(V_NFREE)
    CORE print_uint
    ld hl,lq_m_cells
    call lputs
    ld hl,(V_SYMFREE)
    ld de,0
.s:
    ld a,h
    or l
    jr z,.sd
    inc de
    inc hl
    inc hl
    LDHLI
    jr .s
.sd:
    ex de,hl
    CORE print_uint
    ld hl,lq_m_syms
    call lputs
    ld hl,(V_BLKHI)
    ld de,(V_BLKTOP)
    or a
    sbc hl,de
    CORE print_uint
    ld hl,lq_m_bytes
    call lputs
    jp lnil
lq_m_cells: db " cells, ",0
lq_m_syms:  db " symbols, ",0
lq_m_bytes: db " string bytes free",13,10,0
