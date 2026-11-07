;; CPC Lisp -- symbols and strings.
;;
;; A symbol's name and a string's characters are both "raw strings":
;; [len lo][len hi][chars], pointed at by the word the object's pointer
;; addresses. Builtin symbols' names are in ROM; everything else is in block
;; space and moves when the GC compacts it.

;; hash_name: HL = chars, B = length -> A = bucket. BC, DE kept; HL moved.
hash_name:
    push bc
    ld c,0
    ld a,b
    or a
    jr z,.done
.l:
    ld a,c
    rlca
    add a,(hl)
    ld c,a
    inc hl
    djnz .l
.done:
    ld a,c
    and NBUCKETS-1
    pop bc
    ret

;; intern: the name in TOKBUF, B = its length -> HL = the symbol (NIL for
;; "NIL"). Creates it if it is new; a name starting with ":" is a keyword,
;; constant, and its own value.
intern:
    ld hl,TOKBUF
    call hash_name
    add a,a
    ld l,a
    ld h,0
    ld de,OBARRAY
    add hl,de
    push hl                     ; bucket address (low area: not a value)
    LDHLI
.walk:
    ISNIL
    jr z,.create
    push hl
    LDHLI                       ; the symbol
    push hl
    call name_equal
    pop de
    pop hl
    jr z,.found
    CDRHL
    jr .walk
.found:
    pop hl                      ; bucket address
    ex de,hl
    ld de,NILSLOT
    or a
    sbc hl,de
    add hl,de
    ret nz
    ld hl,NIL
    ret
.create:
    call make_symbol
    pop de                      ; bucket address
    push de
    ex de,hl
    LDHLI                       ; HL = bucket list
    ex de,hl                    ; HL = symbol, DE = list
    call cons
    ex de,hl                    ; DE = new list
    pop hl
    ld (hl),e
    inc hl
    ld (hl),d
    ex de,hl
    LDHLI                       ; the symbol again: car of the new list
    ret

;; make_symbol: TOKBUF holds B characters -> HL = a new symbol of that
;; name, not interned. A name starting with ":" makes a keyword: constant,
;; and its own value.
make_symbol:
    call new_symbol             ; BC kept
    push hl                     ; reachable while the name is allocated
    ld c,b
    ld b,0
    push bc
    call blk_alloc              ; owner = the symbol's name word
    pop bc
    inc hl
    inc hl
    ex de,hl
    ld hl,TOKBUF
    ld a,b
    or c
    jr z,.nocopy
    ldir
.nocopy:
    pop hl
    ld a,(TOKBUF)
    cp ":"
    ret nz
    push hl
    ld e,l
    ld d,h
    inc hl
    inc hl
    ld (hl),e                   ; value: itself
    inc hl
    ld (hl),d
    pop hl
    dec hl
    dec hl
    ld (hl),SF_CONST
    inc hl
    inc hl
    ret

;; name_equal: HL = symbol, TOKBUF holds B characters -> Z if the names match.
;; B kept.
name_equal:
    LDHLI                       ; raw name
    ld a,(hl)
    cp b
    ret nz
    inc hl
    ld a,(hl)
    or a
    ret nz
    inc hl
    ld de,TOKBUF
    ld c,b
    inc c
.l:
    dec c
    ret z
    ld a,(de)
    cp (hl)
    ret nz
    inc hl
    inc de
    jr .l

;; sym_slot: HL = a symbol or NIL -> HL = a pointer to its slot (NILSLOT for
;; NIL). Errors if it is not a symbol. BC, DE kept.
sym_slot:
    ld a,h
    or l
    jr nz,.not0
    ld hl,NILSLOT
    ret
.not0:
    call is_symbol
    ret z
    ex de,hl
    ld hl,m_notsym
    jp error

;; is_symbol: HL -> Z if it is a symbol other than NIL. HL, BC, DE kept.
is_symbol:
    ld a,l
    and 7
    cp 2
    ret nz
    ld a,h
    cp SYM_LO >> 8
    jr c,.no
    cp SYM_HI >> 8
    jr nc,.no
    cp a
    ret
.no:
    or 1
    ret

;; str_data: HL = a string or a symbol's slot pointer -> HL = its characters,
;; BC = their number. DE kept.
str_data:
    LDHLI
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    ret

;; make_string: HL = characters (not in block space), BC = how many ->
;; HL = a new string.
make_string:
    push hl
    push bc
    ld hl,HDR_STRING
    ld de,0
    call alloc_typed
    pop bc
    push hl                     ; the string, reachable
    call blk_alloc              ; owner = its data word
    inc hl
    inc hl
    ex de,hl
    pop hl
    ex (sp),hl                  ; HL = source, the string on the stack
    ld a,b
    or c
    jr z,.empty
    ldir
.empty:
    pop hl
    ret

;; is_string: HL -> Z if it is a string. HL, BC, DE kept.
is_string:
    ld a,l
    and 3
    cp 2
    ret nz
    ld a,h
    cp CELL_LO >> 8
    jr c,.no
    cp #C0
    jr nc,.no
    push hl
    dec hl
    dec hl
    ld a,(hl)
    cp HDR_STRING and #FF
    jr nz,.pop
    inc hl
    ld a,(hl)
    cp HDR_STRING >> 8
.pop:
    pop hl
    ret
.no:
    or 1
    ret
