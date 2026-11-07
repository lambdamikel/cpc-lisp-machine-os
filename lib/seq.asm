;; CPC Lisp -- sequence functions in native code (library ROM, part 1).

;; SCORE: CORE, keeping IX (these routines keep a frame in it)
macro SCORE routine
    push ix
    ld ix,{routine}
    call CORECALL
    pop ix
mend

;; (sort sequence predicate [:key key]), and stable-sort, the same thing: a
;; merge sort, stable. A list is sorted by relinking its conses (use the
;; result, as in CL); a vector in place.
;;
;; The list's merge sort is bottom-up (no recursion): runs of 1, 2, 4...
;; are merged pass by pass until one pass merges once. Its state is a frame
;; on the machine stack, where the GC sees the Lisp values in it -- what is
;; merged so far, and the two runs, keep every cons reachable while the
;; predicate runs:
SRT_LIST   equ 0                 ; the merged list so far,
SRT_TAIL   equ 2                 ;   its last cons
SRT_P      equ 4                 ; the first run,
SRT_Q      equ 6                 ;   the second
SRT_IN     equ 8                 ; the runs' length this pass
SRT_PN     equ 10                ; left in the first run,
SRT_QN     equ 12                ;   in the second
SRT_MERGES equ 14                 ; merges this pass (stops at 255)
SRT_PRED   equ 16
SRT_KEY    equ 18                ; or NIL
SRT_SEQ    equ 20                ; the vector being sorted
SRT_SIZE   equ 22

;@ SORT 2 4 lf_sort
;@ STABLE-SORT 2 4 lf_sort
lf_sort:
    NEXTARG
    push de                     ; the sequence
    NEXTARG
    push de                     ; the predicate
    ld de,NIL                   ; no key
    ld a,b
    cp 2
    jr z,.args
    cp 4
    jr nz,.badkey
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; the keyword
    dec hl
    dec hl
    dec hl
    push hl
    call so_iskey
    pop hl
    jr nz,.badkey
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = the key
.args:
    pop hl                      ; the predicate
    pop bc                      ; the sequence
    ld ix,-SRT_SIZE
    add ix,sp
    ld sp,ix
    ld (ix+SRT_PRED),l
    ld (ix+SRT_PRED+1),h
    ld (ix+SRT_KEY),e
    ld (ix+SRT_KEY+1),d
    ld (ix+SRT_SEQ),c
    ld (ix+SRT_SEQ+1),b
    ld l,c
    ld h,b
    ld a,l
    and 3
    jr nz,.vector               ; not a list
    call so_list
.out:
    ex de,hl
    ld hl,SRT_SIZE
    add hl,sp
    ld sp,hl
    ex de,hl
    ret
.badkey:
    ld hl,so_m_key
    ld de,UNBOUND
    jp lib_error
.vector:
    SCORE is_vector
    jr z,.isvec
    ex de,hl
    ld hl,m_notlist
    CORE error
.isvec:
    SCORE vec_data              ; BC = how many
    xor a
    ld (ix+SRT_LIST),a           ; its elements as a list, from the last
    ld (ix+SRT_LIST+1),a
.vl:
    ld a,b
    or c
    jr z,.vsort
    dec bc
    ld (ix+SRT_PN),c
    ld (ix+SRT_PN+1),b
    ld l,(ix+SRT_SEQ)
    ld h,(ix+SRT_SEQ+1)
    SCORE vec_data              ; again: the cons before may have moved it
    ld c,(ix+SRT_PN)
    ld b,(ix+SRT_PN+1)
    add hl,bc
    add hl,bc
    LDHLI                       ; element BC
    ld e,(ix+SRT_LIST)
    ld d,(ix+SRT_LIST+1)
    SCORE cons
    ld (ix+SRT_LIST),l
    ld (ix+SRT_LIST+1),h
    ld c,(ix+SRT_PN)
    ld b,(ix+SRT_PN+1)
    jr .vl
.vsort:
    ld l,(ix+SRT_LIST)
    ld h,(ix+SRT_LIST+1)
    call so_list
    push hl                     ; (on the stack is enough: nothing allocates)
    ld l,(ix+SRT_SEQ)
    ld h,(ix+SRT_SEQ+1)
    SCORE vec_data
    pop de                      ; back into the vector
.wl:
    ld a,d
    or e
    jr z,.wdone
    ld a,(de)
    ld (hl),a
    inc de
    inc hl
    ld a,(de)
    ld (hl),a
    inc de
    inc hl
    ex de,hl
    LDHLI                       ; the next cons
    ex de,hl
    jr .wl
.wdone:
    ld l,(ix+SRT_SEQ)
    ld h,(ix+SRT_SEQ+1)
    jp .out

so_m_key: db "sort: :key only",0

;; so_iskey: DE -> Z if it is the keyword :KEY
so_iskey:
    ld a,e
    and 7
    cp 2
    ret nz
    ld a,d
    cp SYM_LO >> 8
    jr c,.no
    cp SYM_HI >> 8
    jr nc,.no
    ex de,hl
    SCORE str_data              ; HL = its name, BC = how long
    ld a,b
    or a
    ret nz
    ld a,c
    cp 4
    ret nz
    ld de,.name
    ld b,4
.c:
    ld a,(de)
    cp (hl)
    ret nz
    inc de
    inc hl
    djnz .c
    ret
.no:
    or 1
    ret
.name:
    db ":KEY"

;; so_list: HL = a list -> HL = it sorted (the frame at IX)
so_list:
    ld (ix+SRT_LIST),l
    ld (ix+SRT_LIST+1),h
    ld a,h
    or l
    ret z
    ld (ix+SRT_IN),1
    ld (ix+SRT_IN+1),0
.pass:
    ld l,(ix+SRT_LIST)
    ld h,(ix+SRT_LIST+1)
    ld (ix+SRT_P),l
    ld (ix+SRT_P+1),h
    xor a
    ld (ix+SRT_LIST),a
    ld (ix+SRT_LIST+1),a
    ld (ix+SRT_TAIL),a
    ld (ix+SRT_TAIL+1),a
    ld (ix+SRT_MERGES),a
.merge:
    ld l,(ix+SRT_P)
    ld h,(ix+SRT_P+1)
    ld a,h
    or l
    jp z,.passed
    ld a,(ix+SRT_MERGES)
    inc a
    jr z,.counted
    ld (ix+SRT_MERGES),a
.counted:
    ld e,(ix+SRT_IN)             ; the second run starts a run's length on
    ld d,(ix+SRT_IN+1)
    ld bc,0
.step:
    inc bc
    CDRHL
    ld a,h
    or l
    jr z,.stepped
    dec de
    ld a,d
    or e
    jr nz,.step
.stepped:
    ld (ix+SRT_Q),l
    ld (ix+SRT_Q+1),h
    ld (ix+SRT_PN),c
    ld (ix+SRT_PN+1),b
    ld a,(ix+SRT_IN)
    ld (ix+SRT_QN),a
    ld a,(ix+SRT_IN+1)
    ld (ix+SRT_QN+1),a
.pick:
    ld a,(ix+SRT_PN)
    or (ix+SRT_PN+1)
    jr z,.ponly                 ; the first run is used up
    ld a,(ix+SRT_QN)
    or (ix+SRT_QN+1)
    jr z,.fromp
    ld l,(ix+SRT_Q)
    ld h,(ix+SRT_Q+1)
    ld a,h
    or l
    jr z,.fromp                 ; so is the second
    LDHLI
    push hl                     ; the second's first
    ld l,(ix+SRT_P)
    ld h,(ix+SRT_P+1)
    LDHLI
    ex de,hl                    ; DE = the first's first
    pop hl
    call so_less                ; the second's only if it goes before
    jr nz,.fromq
.fromp:
    ld l,(ix+SRT_P)
    ld h,(ix+SRT_P+1)
    push hl
    CDRHL
    ld (ix+SRT_P),l
    ld (ix+SRT_P+1),h
    ld l,(ix+SRT_PN)
    ld h,(ix+SRT_PN+1)
    dec hl
    ld (ix+SRT_PN),l
    ld (ix+SRT_PN+1),h
    pop hl
    jr .append
.ponly:
    ld a,(ix+SRT_QN)
    or (ix+SRT_QN+1)
    jr z,.runs
    ld l,(ix+SRT_Q)
    ld h,(ix+SRT_Q+1)
    ld a,h
    or l
    jr z,.runs                  ; both used up
.fromq:
    ld l,(ix+SRT_Q)
    ld h,(ix+SRT_Q+1)
    push hl
    CDRHL
    ld (ix+SRT_Q),l
    ld (ix+SRT_Q+1),h
    ld l,(ix+SRT_QN)
    ld h,(ix+SRT_QN+1)
    dec hl
    ld (ix+SRT_QN),l
    ld (ix+SRT_QN+1),h
    pop hl
.append:                        ; HL = the cons taken
    ld e,(ix+SRT_TAIL)
    ld d,(ix+SRT_TAIL+1)
    ld a,d
    or e
    jr nz,.link
    ld (ix+SRT_LIST),l
    ld (ix+SRT_LIST+1),h
    jr .tail
.link:
    ex de,hl
    inc hl
    inc hl
    ld (hl),e
    inc hl
    ld (hl),d
    ex de,hl
.tail:
    ld (ix+SRT_TAIL),l
    ld (ix+SRT_TAIL+1),h
    jp .pick
.runs:
    ld l,(ix+SRT_Q)              ; the next two runs start where these ended
    ld h,(ix+SRT_Q+1)
    ld (ix+SRT_P),l
    ld (ix+SRT_P+1),h
    jp .merge
.passed:
    ld l,(ix+SRT_TAIL)
    ld h,(ix+SRT_TAIL+1)
    inc hl
    inc hl
    xor a
    ld (hl),a
    inc hl
    ld (hl),a
    ld a,(ix+SRT_MERGES)
    cp 2
    jr c,.done
    sla (ix+SRT_IN)
    rl (ix+SRT_IN+1)
    jp .pass
.done:
    ld l,(ix+SRT_LIST)
    ld h,(ix+SRT_LIST+1)
    ret

;; so_less: HL = x, DE = y -> NZ if (pred (key x) (key y))
so_less:
    push de
    call so_key
    ex (sp),hl                  ; (key x) on the stack, where the GC sees it
    call so_key
    ld de,NIL
    SCORE cons
    ex de,hl
    pop hl
    SCORE cons                  ; ((key x) (key y))
    ex de,hl
    ld l,(ix+SRT_PRED)
    ld h,(ix+SRT_PRED+1)
    SCORE apply_list
    ld a,h
    or l
    ret

;; so_key: HL = x -> HL = (key x), or x with no key
so_key:
    ld e,(ix+SRT_KEY)
    ld d,(ix+SRT_KEY+1)
    ld a,d
    or e
    ret z
    push de
    ld de,NIL
    SCORE cons
    ex de,hl
    pop hl
    SCORE apply_list
    ret
