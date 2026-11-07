;; CPC Lisp -- allocation and the garbage collector.
;;
;; Three kinds of storage:
;;
;;   cells    4 bytes, [car][cdr]: conses, and typed cells [header][data].
;;            Free ones are [FREEMARK][next] on V_FREE.
;;   symbols  8-byte slots in &0500-&14FF. Free ones have name 0 and the
;;            next free slot in their value word, on V_SYMFREE.
;;   blocks   variable length, bump-allocated in block space and compacted
;;            by the GC: [owner][len lo][len hi][bytes][pad]. The owner is
;;            the word that points at the length -- a string's data word or
;;            a symbol's name -- and is updated when the block moves.
;;
;; THE COLLECTOR is mark and sweep with a mark bitmap (one bit per 4 bytes
;; from SYM_LO; symbols use every other bit). Marking is iterative: a cdr is
;; followed in a loop and a car is pushed on a 256-word mark stack. If that
;; overflows, the push is dropped -- its parent is marked, the child is not --
;; and once the stack drains the heap is rescanned for marked objects with
;; unmarked children. Deep car-nesting costs time, never correctness or stack.
;;
;; ROOTS: the symbol hash table, the root variables (V_ENV..ROOTS_END), and
;; the machine stack from SP to its top, scanned CONSERVATIVELY: any word
;; there that has the shape of a heap pointer keeps its object alive. Native
;; code can therefore keep Lisp values on the stack, or in HL/DE/BC across an
;; allocation (cons pushes them). What it must not do is keep a raw pointer
;; into block space across an allocation: blocks move.

;; cons: HL = car, DE = cdr -> HL = the new cell. BC and DE preserved.
cons:
    push de
    push hl
    ld hl,(V_FREE)
    ld a,h
    or l
    jr nz,.have
    call gc
    ld hl,(V_FREE)
    ld a,h
    or l
    jp z,err_nomem
.have:
    ld e,l
    ld d,h
    inc hl
    inc hl
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld (V_FREE),hl
    ex de,hl
    pop de
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    pop de
    ld (hl),e
    inc hl
    ld (hl),d
    dec hl
    dec hl
    dec hl
    ret

;; alloc_typed: HL = header, DE = data -> HL = the typed object (cell + 2)
alloc_typed:
    call cons
    inc hl
    inc hl
    ret

;; new_symbol -> HL = a fresh symbol: no name yet, unbound, no function, no
;; plist. BC preserved.
new_symbol:
    ld hl,(V_SYMFREE)
    ld a,h
    or l
    jr nz,.have
    call gc
    ld hl,(V_SYMFREE)
    ld a,h
    or l
    jp z,err_nosyms
.have:
    push hl
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (V_SYMFREE),de
    pop hl
    push hl
    dec hl
    dec hl
    xor a
    ld (hl),a                   ; plist
    inc hl
    ld (hl),a
    inc hl
    ld (hl),a                   ; name
    inc hl
    ld (hl),a
    inc hl
    ld (hl),UNBOUND and #FF     ; value
    inc hl
    ld (hl),UNBOUND >> 8
    inc hl
    ld (hl),UNBOUND and #FF     ; function
    inc hl
    ld (hl),UNBOUND >> 8
    pop hl
    ret

;; blk_alloc: BC = length, HL = owner -> HL = the block's length field, which
;; is also stored in the owner. The owner's object must be reachable from
;; the stack or a root while this runs (it may collect).
blk_alloc:
    push hl
    push bc
    call .try
    jr nc,.ok
    call gc
    pop bc
    push bc
    call .try
    jp c,err_nostr
.ok:
    pop bc
    pop de
    ld (hl),e                   ; owner
    inc hl
    ld (hl),d
    inc hl
    ld (hl),c                   ; length
    inc hl
    ld (hl),b
    dec hl
    ex de,hl
    ld (hl),e                   ; the owner points at the length
    inc hl
    ld (hl),d
    ex de,hl
    ret
;; BC = length -> NC and HL = new block, or C if it does not fit
.try:
    ld hl,5
    add hl,bc
    res 0,l                     ; owner + length + bytes, rounded to even
    ex de,hl
    ld hl,(V_BLKTOP)
    push hl
    add hl,de
    jr c,.full
    ex de,hl                    ; DE = new top
    ld hl,(V_BLKHI)
    or a
    sbc hl,de
    jr c,.full
    ld (V_BLKTOP),de
    pop hl
    or a
    ret
.full:
    pop hl
    scf
    ret

;; ===========================================================================
;; THE COLLECTOR

gc:
    push af
    push bc
    push de
    push hl
    push ix
    ld hl,(V_GCS)
    inc hl
    ld (V_GCS),hl
    ; clear the bitmap
    ld hl,(V_BITMAP)
    ld bc,(V_BMSIZE)
    ld (hl),0
    ld e,l
    ld d,h
    inc de
    dec bc
    ldir
    xor a
    ld (V_MSOVF),a
    ; roots
    ld hl,NILSLOT
    call mark_value
    ld hl,OBARRAY
    ld b,NBUCKETS
    call mark_words
    ld hl,VARS
    ld b,(ROOTS_END-VARS)/2
    call mark_words
    ld hl,0
    add hl,sp
.stack:
    ld de,(V_STKTOP)
    ld a,l
    cp e
    jr nz,.word
    ld a,h
    cp d
    jr z,.rescan
.word:
    push hl
    LDHLI
    call mark_value
    pop hl
    inc hl
    inc hl
    jr .stack
.rescan:
    ld a,(V_MSOVF)
    or a
    jr z,.marked
    call rescan
    jr .rescan
.marked:
    call compact_blocks
    call sweep_symbols
    call sweep_cells
    pop ix
    pop hl
    pop de
    pop bc
    pop af
    ret

;; mark_words: HL = address of B words to mark
mark_words:
    push bc
    push hl
    LDHLI
    call mark_value
    pop hl
    pop bc
    inc hl
    inc hl
    djnz mark_words
    ret

;; mark_value: HL = any word. Marks everything it reaches.
mark_value:
    ld de,MARKSTK
    ld (V_MSP),de
.obj:
    ld a,l
    rrca
    jr c,.next                  ; fixnum
    rrca
    jr c,.tag10
    ; tag 00: a cons if it is in the cell region
    ld a,h
    cp CELL_LO >> 8
    jr c,.next                  ; NIL
    call below_cellhi
    jr nc,.next
    jr .cell
.tag10:
    ld a,h
    cp SYM_LO >> 8
    jr c,.next                  ; character, marker, header
    cp CELL_LO >> 8
    jr c,.sym
    call below_cellhi
    jr nc,.next                 ; block space, stack, ROM: not ours
    dec hl
    dec hl
    ; What a cell is, is decided by its car, not by the pointer: a word on
    ; the stack may be the address of a cons's cdr, and that cons must still
    ; have its car traced.
.cell:
    call testset_mark
    jr nz,.next
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = car, or a header
    inc hl
    ld a,d
    cp 4
    jr nz,.cons
    ld a,e
    cp #80
    jr c,.cons
    bit 0,e
    jr nz,.cons                 ; a fixnum 576..639 looks like this too
    cp HDR_RAW_L
    jr nc,.next                 ; raw data, or a free cell
    LDHLI                       ; the data word is a Lisp value
    jp .obj
.cons:
    LDHLI                       ; HL = cdr
    call mpush_de
    jp .obj
.sym:
    ld a,l
    and 7
    cp 2
    jr nz,.next
    dec hl
    dec hl
    call testset_mark
    jr nz,.next
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = plist and flags
    inc hl
    ld a,(hl)
    inc hl
    or (hl)                     ; name 0: a free slot
    inc hl
    jr z,.next
    ld a,e
    and #FC
    ld e,a
    call mpush_de
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; value
    inc hl
    call mpush_de
    LDHLI                       ; function
    jp .obj
.next:
    ld hl,(V_MSP)
    ld de,MARKSTK
    or a
    sbc hl,de
    ret z
    add hl,de
    dec hl
    ld d,(hl)
    dec hl
    ld e,(hl)
    ld (V_MSP),hl
    ex de,hl
    jp .obj

;; push DE on the mark stack if it could be a heap object. HL, BC preserved.
mpush_de:
    bit 0,e
    ret nz
    ld a,d
    cp SYM_LO >> 8
    ret c
    push hl
    ld hl,(V_MSP)
    ld a,l
    cp MARKSTK_END and #FF
    jr nz,.room
    ld a,h
    cp MARKSTK_END >> 8
    jr nz,.room
    ld a,1
    ld (V_MSOVF),a
    pop hl
    ret
.room:
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld (V_MSP),hl
    pop hl
    ret

;; carry if HL < V_CELLHI. HL, BC, DE preserved.
below_cellhi:
    push de
    ld de,(V_CELLHI)
    ld a,h
    cp d
    jr nz,.r
    ld a,l
    cp e
.r:
    pop de
    ret

;; mark_bit: HL = address of a cell or slot -> HL = its bitmap byte, C = the
;; bit as a mask. DE preserved.
mark_bit:
    ld a,l
    rrca
    rrca
    and 7
    ld b,a                      ; bit number: (address / 4) mod 8
    ld a,h
    sub SYM_LO >> 8
    ld h,a                      ; address - SYM_LO (whose low byte is 0)
    ld a,l
    rlca
    rlca
    rlca
    and 7
    ld c,a                      ; low byte / 32
    ld l,h
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld a,l
    or c
    ld l,a                      ; (address - SYM_LO) / 32
    push de
    ld de,(V_BITMAP)
    add hl,de
    pop de
    ld a,1
    inc b
.sh:
    dec b
    jr z,.got
    add a,a
    jr .sh
.got:
    ld c,a
    ret

;; testset_mark: HL = address. NZ if it was marked; marks it. HL, DE, BC kept.
testset_mark:
    push hl
    push bc
    call mark_bit
    ld a,c
    and (hl)
    jr nz,.was
    ld a,c
    or (hl)
    ld (hl),a
    xor a
.was:
    pop bc
    pop hl
    ret

;; test_mark: HL = address. NZ if marked. HL, DE, BC kept.
test_mark:
    push hl
    push bc
    call mark_bit
    ld a,c
    and (hl)
    pop bc
    pop hl
    ret

;; rescan: after a mark-stack overflow, find marked objects whose children
;; are not and mark from them.
rescan:
    xor a
    ld (V_MSOVF),a
    ld hl,CELL_LO
.cell:
    call below_cellhi
    jr nc,.syms
    call test_mark
    jr z,.cnext
    push hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = car or header
    inc hl
    ld a,d
    cp 4
    jr nz,.cons
    ld a,e
    cp #80
    jr c,.cons
    bit 0,e
    jr nz,.cons                 ; a fixnum, not a header
    cp HDR_RAW_L
    jr nc,.cdone                ; raw data, or free
    LDHLI
    call mark_value
    jr .cdone
.cons:
    push hl
    ex de,hl
    call mark_value
    pop hl
    LDHLI
    call mark_value
.cdone:
    pop hl
.cnext:
    inc hl
    inc hl
    inc hl
    inc hl
    jr .cell
.syms:
    ld hl,SYM_LO
.sym:
    call test_mark
    jr z,.snext
    push hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; plist and flags
    inc hl
    ld a,(hl)
    inc hl
    or (hl)
    inc hl
    jr z,.sdone                 ; free slot
    push hl
    ld a,e
    and #FC
    ld l,a
    ld h,d
    call mark_value
    pop hl
    push hl
    LDHLI                       ; value
    call mark_value
    pop hl
    inc hl
    inc hl
    LDHLI                       ; function
    call mark_value
.sdone:
    pop hl
.snext:
    ld de,8
    add hl,de
    ld a,h
    cp SYM_HI >> 8
    jr c,.sym
    ret

;; compact_blocks: slide the live blocks down and update their owners. A
;; block is live if its owner word is inside a marked object and still
;; points at it.
compact_blocks:
    ld hl,(V_BLKLO)
    ld (V_S1),hl                ; source
    ld (V_S2),hl                ; destination
.loop:
    ld hl,(V_S1)
    ld de,(V_BLKTOP)
    or a
    sbc hl,de
    jr nc,.end
    ld hl,(V_S1)
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = owner
    inc hl
    ld c,(hl)
    inc hl
    ld b,(hl)                   ; BC = length
    ld hl,5
    add hl,bc
    res 0,l
    ld (V_S3),hl                ; size of the block
    ; owner inside the heap, past the first symbol's name?
    ld a,d
    cp SYM_LO >> 8
    jr c,.dead
    ex de,hl
    call below_cellhi
    jr nc,.dead
    ; still pointing here?
    push hl
    LDHLI
    ld de,(V_S1)
    inc de
    inc de
    or a
    sbc hl,de
    pop hl
    jr nz,.dead
    ; its object marked?
    dec hl
    dec hl
    call test_mark
    jr z,.dead
    inc hl
    inc hl                      ; HL = owner again
    ; move it and update the owner
    ld de,(V_S2)
    inc de
    inc de
    ld (hl),e
    inc hl
    ld (hl),d
    ld hl,(V_S1)
    ld de,(V_S2)
    ld bc,(V_S3)
    or a
    sbc hl,de
    add hl,de
    jr z,.same
    ldir
    jr .moved
.same:
    ex de,hl
    add hl,bc
    ex de,hl
.moved:
    ld (V_S2),de
.dead:
    ld hl,(V_S1)
    ld de,(V_S3)
    add hl,de
    ld (V_S1),hl
    jr .loop
.end:
    ld hl,(V_S2)
    ld (V_BLKTOP),hl
    ret

;; sweep_symbols: unmarked slots go on V_SYMFREE
sweep_symbols:
    ld hl,0
    ld (V_SYMFREE),hl
    ld de,(V_BITMAP)
    ld hl,SYM_LO+2
.byte:
    ld a,(de)
    ld c,a
    ld b,4
.slot:
    bit 0,c
    jr nz,.used
    push de
    ld de,(V_SYMFREE)
    push hl
    xor a
    ld (hl),a                   ; name 0: free
    inc hl
    ld (hl),a
    inc hl
    ld (hl),e                   ; value: the next free slot
    inc hl
    ld (hl),d
    pop hl
    ld (V_SYMFREE),hl
    pop de
.used:
    srl c
    srl c
    ld a,l
    add a,8
    ld l,a
    jr nc,.nc
    inc h
.nc:
    djnz .slot
    inc de
    ld a,h
    cp SYM_HI >> 8
    jr c,.byte
    ret

;; sweep_cells: unmarked cells go on V_FREE, counted in V_NFREE
sweep_cells:
    ld hl,0
    ld (V_FREE),hl
    ld (V_NFREE),hl
    ld hl,(V_BITMAP)
    ld de,(CELL_LO-SYM_LO)/32
    add hl,de
    ld (V_S1),hl
    ld hl,CELL_LO
.byte:
    call below_cellhi
    ret nc
    ld de,(V_S1)
    ld a,(de)
    inc de
    ld (V_S1),de
    ld c,a
    ld b,8
.bit:
    srl c
    jr c,.used
    ld de,(V_FREE)
    ld (hl),FREEMARK and #FF
    inc hl
    ld (hl),FREEMARK >> 8
    inc hl
    ld (hl),e
    inc hl
    ld (hl),d
    dec hl
    dec hl
    dec hl
    ld (V_FREE),hl
    ld de,(V_NFREE)
    inc de
    ld (V_NFREE),de
.used:
    inc hl
    inc hl
    inc hl
    inc hl
    djnz .bit
    jr .byte
