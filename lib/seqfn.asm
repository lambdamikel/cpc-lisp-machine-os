;; CPC Lisp -- the sequence functions (library ROM, part 1): find,
;; position, count, remove (delete), substitute, each with -if and -if-not,
;; on lists, strings and vectors, with CL's keywords :test :test-not :key
;; :start :end :from-end :count.
;;
;; One engine: the sequence is walked as a list (a string's or a vector's
;; elements are made one first), each element in [start, end) is matched
;; by lk_match (lists.asm, member's), and the operation does with it what
;; it does. A remove or substitute with :from-end and :count first counts
;; the matches, to know how many to pass over before it starts.

SQO_FIND    equ 0
SQO_POS     equ 1
SQO_COUNT   equ 2
SQO_REMOVE  equ 3
SQO_SUBST   equ 4

;; entries: D = the operation, E = 0 (item and test), 1 (-if), 2 (-if-not)
;@ FIND 2 255 lf_find
lf_find:
    ld de,SQO_FIND*256
    jr sq_go
;@ FIND-IF 2 255 lf_find_if
lf_find_if:
    ld de,SQO_FIND*256+1
    jr sq_go
;@ FIND-IF-NOT 2 255 lf_find_if_not
lf_find_if_not:
    ld de,SQO_FIND*256+2
    jr sq_go
;@ POSITION 2 255 lf_position
lf_position:
    ld de,SQO_POS*256
    jr sq_go
;@ POSITION-IF 2 255 lf_position_if
lf_position_if:
    ld de,SQO_POS*256+1
    jr sq_go
;@ POSITION-IF-NOT 2 255 lf_position_if_not
lf_position_if_not:
    ld de,SQO_POS*256+2
    jr sq_go
;@ COUNT 2 255 lf_count
lf_count:
    ld de,SQO_COUNT*256
    jr sq_go
;@ COUNT-IF 2 255 lf_count_if
lf_count_if:
    ld de,SQO_COUNT*256+1
    jr sq_go
;@ COUNT-IF-NOT 2 255 lf_count_if_not
lf_count_if_not:
    ld de,SQO_COUNT*256+2
    jr sq_go
;@ REMOVE 2 255 lf_remove
;@ DELETE 2 255 lf_remove
lf_remove:
    ld de,SQO_REMOVE*256
    jr sq_go
;@ REMOVE-IF 2 255 lf_remove_if
;@ DELETE-IF 2 255 lf_remove_if
lf_remove_if:
    ld de,SQO_REMOVE*256+1
    jr sq_go
;@ REMOVE-IF-NOT 2 255 lf_remove_if_not
;@ DELETE-IF-NOT 2 255 lf_remove_if_not
lf_remove_if_not:
    ld de,SQO_REMOVE*256+2
    jr sq_go
;@ SUBSTITUTE 3 255 lf_substitute
;@ NSUBSTITUTE 3 255 lf_substitute
lf_substitute:
    ld de,SQO_SUBST*256
    jr sq_go
;@ SUBSTITUTE-IF 3 255 lf_substitute_if
lf_substitute_if:
    ld de,SQO_SUBST*256+1
    jr sq_go
;@ SUBSTITUTE-IF-NOT 3 255 lf_substitute_if_not
lf_substitute_if_not:
    ld de,SQO_SUBST*256+2
sq_go:
    ld a,d
    ld c,e
    call lk_frame               ; (A, BC, HL kept)
    ld (ix+SQ_OP),a
    ld a,c
    or a
    jr z,.args
    ld (ix+SQ_IF),1             ; -if: the predicate in LK_TEST
    dec a
    jr z,.args
    ld (ix+LK_NOT),1            ; -if-not
.args:
    ld a,(ix+SQ_OP)
    cp SQO_SUBST
    jr nz,.item
    NEXTARG
    ld (ix+SQ_NEW),e            ; substitute: the new element first
    ld (ix+SQ_NEW+1),d
    dec b
.item:
    NEXTARG                     ; the item, or the predicate
    ld a,(ix+SQ_IF)
    or a
    jr nz,.pred
    ld (ix+LK_ITEM),e
    ld (ix+LK_ITEM+1),d
    jr .seq
.pred:
    ld (ix+LK_TEST),e
    ld (ix+LK_TEST+1),d
.seq:
    NEXTARG
    ld (ix+SQ_SEQ),e
    ld (ix+SQ_SEQ+1),d
    dec b
    dec b
    call lk_keys
    call sq_bounds              ; start, end, count as plain numbers
    ld a,(ix+SQ_OP)             ; remove, substitute with :from-end and
    cp SQO_REMOVE               ;   :count: count the matches first
    jr c,.walk
    ld a,(ix+SQ_FROMEND)
    or (ix+SQ_FROMEND+1)
    jr z,.walk
    ld a,(ix+SQ_COUNT+1)
    inc a
    jr z,.walk                  ; (no :count: all of them anyway)
    ld a,(ix+SQ_OP)
    push af
    ld (ix+SQ_OP),SQO_COUNT
    call sq_walk
    pop af
    ld (ix+SQ_OP),a
    ld l,(ix+SQ_N)              ; pass over all but the last count
    ld h,(ix+SQ_N+1)
    ld e,(ix+SQ_COUNT)
    ld d,(ix+SQ_COUNT+1)
    or a
    sbc hl,de
    jr nc,.skip
    ld hl,0
.skip:
    ld (ix+SQ_SKIP),l
    ld (ix+SQ_SKIP+1),h
    xor a
    ld (ix+SQ_N),a
    ld (ix+SQ_N+1),a
    ld (ix+SQ_I),a
    ld (ix+SQ_I+1),a
.walk:
    call sq_walk
    jp nc,sq_out                ; find, position: found on the way
    call sq_finish
sq_out:
    ex de,hl
    ld hl,LK_SIZE
    add hl,sp
    ld sp,hl
    ex de,hl
    ret

;; sq_bounds: :start (0), :end and :count (65535 if not given) as numbers
sq_bounds:
    ld l,(ix+SQ_START)
    ld h,(ix+SQ_START+1)
    ld de,0
    call .n
    ld (ix+SQ_START),e
    ld (ix+SQ_START+1),d
    ld l,(ix+SQ_END)
    ld h,(ix+SQ_END+1)
    ld de,-1
    call .n
    ld (ix+SQ_END),e
    ld (ix+SQ_END+1),d
    ld l,(ix+SQ_COUNT)
    ld h,(ix+SQ_COUNT+1)
    ld de,-1
    call .n
    ld (ix+SQ_COUNT),e
    ld (ix+SQ_COUNT+1),d
    ret
.n:                             ; HL = a fixnum or NIL -> DE
    ld a,h
    or l
    ret z
    call lfix_hl
    sra h
    rr l
    ex de,hl
    ret

;; sq_walk: the walk. NC and HL = the answer if find or position found it
;; (not :from-end); else C, and the frame says what was seen.
sq_walk:
    ld l,(ix+SQ_SEQ)
    ld h,(ix+SQ_SEQ+1)
    push ix
    call lq_tolist_fwd          ; (it calls the core: IX goes)
    pop ix
    ld (ix+LK_LIST),l
    ld (ix+LK_LIST+1),h
.l:
    ld l,(ix+LK_LIST)
    ld h,(ix+LK_LIST+1)
    ld a,h
    or l
    scf
    ret z                       ; the end
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = the element
    push de                     ; (kept for the GC while it is tested)
    ld l,(ix+SQ_I)              ; in [start, end)?
    ld h,(ix+SQ_I+1)
    ld c,(ix+SQ_START)
    ld b,(ix+SQ_START+1)
    or a
    sbc hl,bc
    jr c,.out                   ; before start
    add hl,bc
    ld c,(ix+SQ_END)
    ld b,(ix+SQ_END+1)
    or a
    sbc hl,bc
    jr nc,.out                  ; at or past end
    call lk_match
    pop de
    push de
    jr z,.out
    call sq_matched
    jr nc,.found
    jr .next
.out:
    ld a,(ix+SQ_OP)             ; not matched (or out of range)
    cp SQO_REMOVE
    jr c,.next
    pop de                      ; remove, substitute: kept
    push de
    call sq_keep
.next:
    pop de
    ld l,(ix+LK_LIST)
    ld h,(ix+LK_LIST+1)
    CDRHL
    ld (ix+LK_LIST),l
    ld (ix+LK_LIST+1),h
    ld l,(ix+SQ_I)
    ld h,(ix+SQ_I+1)
    inc hl
    ld (ix+SQ_I),l
    ld (ix+SQ_I+1),h
    jr .l
.found:
    pop de
    ret

;; sq_matched: DE = a matching element -> NC and HL = the answer to give now,
;; or C to go on
sq_matched:
    ld l,(ix+SQ_N)              ; one more match
    ld h,(ix+SQ_N+1)
    push hl                     ; (how many before it)
    inc hl
    ld (ix+SQ_N),l
    ld (ix+SQ_N+1),h
    pop hl
    ld a,(ix+SQ_OP)
    cp SQO_POS+1
    jr nc,.rest
    ld a,(ix+SQ_FROMEND)        ; find, position
    or (ix+SQ_FROMEND+1)
    jr nz,.last
    ld a,(ix+SQ_OP)
    ex de,hl
    or a
    ret z                       ; find: the element
    ld l,(ix+SQ_I)              ; position: its index
    ld h,(ix+SQ_I+1)
    add hl,hl
    inc hl
    or a
    ret
.last:                          ; :from-end: remember it, and go on
    ld (ix+SQ_HIT),e
    ld (ix+SQ_HIT+1),d
    ld a,(ix+SQ_I)
    ld (ix+SQ_HITI),a
    ld a,(ix+SQ_I+1)
    ld (ix+SQ_HITI+1),a
    scf
    ret
.rest:
    cp SQO_COUNT
    scf
    ret z
    ld c,(ix+SQ_SKIP)           ; remove, substitute: the m-th match goes if
    ld b,(ix+SQ_SKIP+1)         ;   skip <= m < skip + count
    or a
    sbc hl,bc
    jr c,.keep
    ld c,(ix+SQ_COUNT)
    ld b,(ix+SQ_COUNT+1)
    or a
    sbc hl,bc
    jr nc,.keep
    ld a,(ix+SQ_OP)
    cp SQO_SUBST
    scf
    ret nz                      ; removed: nothing kept
    ld e,(ix+SQ_NEW)            ; substituted: the new one kept
    ld d,(ix+SQ_NEW+1)
.keep:
    call sq_keep
    scf
    ret

;; sq_keep: DE = an element for the result
sq_keep:
    ex de,hl
    ld e,(ix+SQ_RES)
    ld d,(ix+SQ_RES+1)
    SCORE cons
    ld (ix+SQ_RES),l
    ld (ix+SQ_RES+1),h
    ret

;; sq_finish: the walk is over -> HL = the answer
sq_finish:
    ld a,(ix+SQ_OP)
    cp SQO_COUNT
    jr z,.count
    jr nc,.result
    ld a,(ix+SQ_FROMEND)        ; find, position: the last, with :from-end
    or (ix+SQ_FROMEND+1)
    jp z,lnil
    ld a,(ix+SQ_N)
    or (ix+SQ_N+1)
    jp z,lnil
    ld a,(ix+SQ_OP)
    or a
    jr nz,.pos
    ld l,(ix+SQ_HIT)
    ld h,(ix+SQ_HIT+1)
    ret
.pos:
    ld l,(ix+SQ_HITI)
    ld h,(ix+SQ_HITI+1)
    add hl,hl
    inc hl
    ret
.count:
    ld l,(ix+SQ_N)
    ld h,(ix+SQ_N+1)
    add hl,hl
    inc hl
    ret
.result:                        ; what was kept, in order, of the same kind
    ld l,(ix+SQ_RES)
    ld h,(ix+SQ_RES+1)
    ld de,NIL
    SCORE nreverse_onto
    ld e,(ix+SQ_SEQ)
    ld d,(ix+SQ_SEQ+1)
    ld a,e
    and 3
    ret z                       ; a list
    push hl
    ex de,hl
    CORE is_string
    pop hl
    jp z,lq_liststr
    jp lq_listvec
