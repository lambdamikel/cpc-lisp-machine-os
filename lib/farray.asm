;; CPC Lisp -- the library, part 1: far arrays, kept in a file on the RAM
;; disc, outside the cells (lib/farray.lsp makes and opens them). The file
;; is "F", the element type -- 0: T (a fixnum, a character, T or NIL, two
;; bytes each: the object itself), 1: (unsigned-byte 8), 2: character (a
;; byte each) -- then the elements; it is written through the RAM disc's
;; output file (%far-fill), read and written in place by fa_xfer. A far
;; array is #S(FAR-ARRAY name entry type): the name "M:NAME.FAR", the
;; directory entry it was found in last. The entry is read again at every
;; access -- the files move when one before them is deleted -- and if it
;; no longer has the name, the directory is searched again.
;;
;; The machine's far.asm (mach/$MACH) has the directory's layout and
;; fa_xfer.

FA_OFF      equ TOKBUF          ; where on the disc (3 bytes)
FA_S        equ TOKBUF+3        ; the file's start (3),
FA_L        equ TOKBUF+6        ;   its length (3)
FA_K        equ TOKBUF+9        ;   its entry,
FA_T        equ TOKBUF+10       ;   the element type
FA_V        equ TOKBUF+12       ; an element's bytes (2)
FA_NM       equ TOKBUF+16       ; the name, as the directory has it (12)
FA_E        equ TOKBUF+32       ; an entry (32 at most)
FA_X        equ TOKBUF+64       ; fa_xfer's own (16)

    include "far.asm"

fa_m_none:  db "no such far array:",0
fa_m_elt:   db "a far array cannot hold:",0
fa_sym:     db 9,0,"FAR-ARRAY"

;; (far-ref a i) -> element i of the far array a
;@ FAR-REF 2 2 lf_far_ref
lf_far_ref:
    push de                     ; i
    call fa_get
    pop de
    push de
    call fa_index               ; B = the element's size
    pop de
    jr c,fa_range
    ld hl,FA_V
    ld c,b
    ld b,0
    xor a
    call fa_xfer
    ld a,(FA_T)
    dec a
    jr z,.byte
    dec a
    jr z,.char
    ld hl,(FA_V)                ; T: the object, if it is one that may be
    bit 0,l                     ;   there (else NIL: not written by us)
    ret nz                      ; a fixnum
    ld a,l
    and 3
    cp 2
    jr nz,.nil                  ; NIL, or a cons
    ld a,h
    cp 4
    ret c                       ; a character
    ld de,S_T
    or a
    sbc hl,de
    add hl,de
    ret z
.nil:
    ld hl,NIL
    ret
.byte:
    ld a,(FA_V)
    ld l,a
    ld h,0
    jp ltag
.char:
    ld a,(FA_V)
    jp lchar

fa_range:                       ; DE = the index
    ld hl,m_index
    CORE error

;; (%far-set a i v) -> v, now element i of a: (setf (far-ref a i) v)
;@ %FAR-SET 3 3 lf_far_set
lf_far_set:
    push bc                     ; v
    push de                     ; i
    call fa_get
    pop de
    push de
    call fa_index
    pop de
    jr c,fa_range
    pop hl                      ; v
    push hl
    ld a,(FA_T)
    dec a
    jr z,.byte
    dec a
    jr z,.char
    bit 0,l                     ; T: a fixnum,
    jr nz,.put
    ld a,h
    or l
    jr z,.put                   ;   NIL,
    ld de,S_T
    or a
    sbc hl,de
    add hl,de
    jr z,.put                   ;   T
.char:                          ;   or a character
    ld a,l
    and 3
    cp 2
    jr nz,.bad
    ld a,h
    cp 4
    jr nc,.bad
    ld a,(FA_T)
    or a
    jr z,.put
    srl h                       ; character: its code
    rr l
    srl h
    rr l
    jr .put
.byte:
    bit 0,l
    jr z,.bad
    sra h
    rr l
    ld a,h
    or a
    jr nz,.bad
.put:
    ld (FA_V),hl
    ld hl,FA_V
    ld c,b
    ld b,0
    ld a,1
    call fa_xfer
    pop hl
    ret
.bad:
    pop de
    ld hl,fa_m_elt
    jp lib_error

;; (far-length a) -> how many elements the far array a has
;@ FAR-LENGTH 1 1 lf_far_length
lf_far_length:
    call fa_get
    ld hl,(FA_L)
    ld a,(FA_L+2)
    ld de,-2
    add hl,de
    adc a,#FF                   ; A:HL = the length less the header
    ld c,a
    ld a,(FA_T)
    or a
    jr nz,.n
    srl c                       ; two bytes each
    rr h
    rr l
.n:
    ld a,h
    cp #40
    jp nc,ln_uint
    jp ltag

;; (%far-open "M:NAME.FAR") -> its element type (0-2), or NIL if there is no
;; such file, or it is not a far array
;@ %FAR-OPEN 1 1 lf_far_open
lf_far_open:
    call lstring                ; HL = the characters, BC = how many
    call fa_dirname
    xor a
    call fa_look
    jp nc,lnil
    ld hl,(FA_S)
    ld (FA_OFF),hl
    ld a,(FA_S+2)
    ld (FA_OFF+2),a
    ld hl,FA_V
    ld bc,2
    xor a
    call fa_xfer
    ld hl,(FA_V)
    ld a,l
    cp "F"
    jp nz,lnil
    ld a,h
    cp 3
    jp nc,lnil
    ld l,a
    ld h,0
    jp ltag

;; (%far-fill n type) -> T: a far array's header and n elements of 0 to
;; the file open for output (on M:); NIL as soon as a byte cannot be
;; written (the disc is full)
;@ %FAR-FILL 2 2 lf_far_fill
lf_far_fill:
    push de
    call lint_hl                ; HL = n
    pop de
    sra d
    rr e                        ; E = the type
    ld a,"F"
    call ff_put
    ld a,e
    call ff_put
.l:
    ld a,h
    or l
    jp z,lt
    dec hl
    xor a
    call ff_put
    ld a,e
    or a
    jr nz,.l
    xor a                       ; (type T: two bytes)
    call ff_put
    jr .l
ff_put:                         ; A -> written; if not, out with NIL
    push hl
    push de
    call FILE_PUTC
    pop de
    pop hl
    ret c
    pop hl                      ; (ff_put's return)
    jp lnil

;; fa_get: HL = a far array -> its file found: FA_S, FA_L, FA_T, its entry
;; kept in it for next time. An error if it is none, or its file is gone.
;; (What the core's is_typed, vec_data and str_data do is done here: a
;; call to the core costs more than the rest.)
fa_get:
    push hl                     ; (for an error)
    ld a,l
    and 3
    cp 2
    jr nz,.bad
    ld a,h
    cp CELL_LO >> 8
    jr c,.bad
    cp #C0
    jr nc,.bad
    dec hl
    dec hl
    ld a,(hl)
    cp HDR_STRUCT and #FF
    jr nz,.bad
    inc hl
    ld a,(hl)
    cp HDR_STRUCT >> 8
    jr nz,.bad
    inc hl
    LDHLI                       ; its block: [2 n][the elements]
    ld a,(hl)
    cp 8
    jr nz,.bad
    inc hl
    ld a,(hl)
    or a
    jr nz,.bad
    inc hl                      ; HL = element 0
    push hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; its type
    ld hl,fa_sym
    call ls_named
    pop hl
    jr nz,.bad
    inc hl
    inc hl
    push hl
    LDHLI                       ; slot 1, the name: a string
    LDHLI
    ld c,(hl)
    inc hl
    inc hl                      ; its characters, C of them
    call fa_dirname
    pop hl
    inc hl
    inc hl                      ; slot 2, the entry (a fixnum)
    push hl
    ld a,(hl)
    rra
    and #7F
    call fa_look
    pop hl
    jr nc,.none
    ld a,(FA_K)
    add a,a
    inc a
    ld (hl),a                   ; (where it is, for next time)
    inc hl
    ld (hl),0
    inc hl
    ld a,(hl)                   ; slot 3, the type
    rra
    and #7F
    ld (FA_T),a
    pop hl
    ret
.none:
    pop de
    ld hl,fa_m_none
    jp lib_error
.bad:
    pop de
    ld hl,st_m_type
    jp lib_error

;; fa_dirname: HL = "M:NAME"'s characters, C how many -> FA_NM, the name
;; as the directory has it
fa_dirname:
    ld de,FA_NM
    ld b,12
    ld a,FA_PAD
.pad:
    ld (de),a
    inc de
    djnz .pad
    ld de,FA_NM
    ld a,c
    sub 2                       ; (past the "M:")
    ret c
    ret z
    cp 13
    jr c,.n
    ld a,12
.n:
    ld b,a
    inc hl
    inc hl
.c:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    djnz .c
    ret

;; fa_look: A = the entry to try first -> C if an entry has FA_NM's name:
;; FA_K, FA_E, FA_S and FA_L say which, where and how long. NC if none.
fa_look:
    call fa_try
    ret c
    xor a
.l:
    push af
    call fa_try
    pop bc
    ret c
    ld a,b
    inc a
    cp FA_NENT
    jr c,.l
    or a
    ret

;; fa_try: A = an entry -> C if it is in use with FA_NM's name
fa_try:
    cp FA_NENT
    ret nc
    ld (FA_K),a
    ld hl,FA_DIR0
    ld de,FA_ESIZE
    or a
    jr z,.at
    ld b,a
.m:
    add hl,de
    djnz .m
.at:
    ld (FA_OFF),hl
    xor a
    ld (FA_OFF+2),a
    ld hl,FA_E
    ld bc,FA_ESIZE
    call fa_xfer
    if FA_USED >= 0
    ld a,(FA_E+FA_USED)
    or a
    ret z
    endif
    ld hl,FA_E+FA_NAME
    ld de,FA_NM
    ld b,12
.c:
    ld a,(de)
    cp (hl)
    jr nz,.no
    inc hl
    inc de
    djnz .c
    ld hl,FA_E+FA_START
    ld de,FA_S
    call .w
    ld hl,FA_E+FA_LEN
    call .w
    scf
    ret
.no:
    or a
    ret
.w:                             ; FA_W bytes at HL -> three at DE
    ld bc,FA_W
    ldir
    if FA_W == 2
    xor a
    ld (de),a
    inc de
    endif
    ret

;; fa_index: DE = an index -> FA_OFF at that element, B = its size; C if
;; it is out of range
fa_index:
    ex de,hl
    call lint_hl                ; HL = i
    xor a
    ld c,a                      ; C:HL = i * the size + 2 (the header)
    ld b,1
    ld a,(FA_T)
    or a
    jr nz,.one
    add hl,hl
    rl c
    inc b
.one:
    ld de,2
    add hl,de
    jr nc,.h
    inc c
.h:
    push hl                     ; in the file?
    push bc
    ld e,b
    ld d,0
    add hl,de
    ld a,c
    adc a,0
    ld c,a
    ex de,hl                    ; C:DE = past the element
    ld hl,(FA_L)
    or a
    sbc hl,de
    ld a,(FA_L+2)
    sbc a,c
    pop bc
    pop hl
    ret c
    ld de,(FA_S)
    add hl,de
    ld (FA_OFF),hl
    ld a,(FA_S+2)
    adc a,c
    ld (FA_OFF+2),a
    or a
    ret
