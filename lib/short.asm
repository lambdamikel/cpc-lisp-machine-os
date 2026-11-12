;; CPC Lisp -- the library, part 1: when the cells run out.
;;
;; The core's cons calls ln_short (lib_numbers +15) when a GC has left no
;; cell free. A function that the library's text defined -- read in on its
;; first call (an autoload) -- can be read in again, so it is dropped if
;; nothing else holds it: the closure on such a symbol is hidden from a
;; second GC, its pointer made odd so that it looks like a fixnum; if that
;; GC frees it, the symbol gets its autoload stub back (a HDR_AUTOLOAD cell,
;; as lib_find made it); if not -- a call of it is running, or a variable
;; holds it -- the pointer is put back as it was. Only names a part's
;; table has as autoloads are touched (a boot form's functions are not:
;; they could not come back), only closures (not macros, not compiled
;; code), and only symbols whose LIBDEFS bit says the library defined them
;; (a user's own definition clears it, mark_def). A function that
;; (load name :lazy t) read in (lib/lazy.lsp) is dropped the same way: its
;; plist's %LAZY entry has the stub to put back.
;;
;; It allocates nothing until the second GC has run, and then one cell for
;; each closure that GC freed: so it never comes back into cons empty.

;; ln_short -> HL = V_FREE, Z if still no cell is free. BC, DE kept, and
;; V_PEEKROM (the part being searched is in it meanwhile).
ln_short:
    push bc
    push de
    ld a,(V_PEEKROM)
    push af
    ld c,0                      ; pass 1: hide them
    call ls_pass
    jr z,.none                  ; nothing to drop
    CORE gc
    ld c,1                      ; pass 2: alive again, or marked for a stub
    call ls_pass
    ld c,2                      ; pass 3: the stubs
    call ls_pass
.none:
    pop af
    ld (V_PEEKROM),a
    pop de
    pop bc
    ld hl,(V_FREE)
    ld a,h
    or l
    ret

;; ls_pass: C = the pass -> each symbol in the obarray that library text
;; defined, through ls_one. NZ after pass 0 if it hid any (ls_one's A,
;; ORed into a word on the stack).
ls_pass:
    ld hl,0
    push hl                     ; (hid any)
    ld b,0                      ; B = the bucket
.bucket:
    ld l,b
    ld h,0
    add hl,hl
    ld de,OBARRAY
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = its list of symbols
.sym:
    ld a,d
    or e
    jr z,.next
    ex de,hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = the symbol
    inc hl
    push hl                     ; (the cdr's place)
    push bc
    xor a
    call ls_one                 ; A = 1 if it hid it
    pop bc
    pop hl
    ex (sp),hl
    or l
    ld l,a
    ex (sp),hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; the rest of the list
    jr .sym
.next:
    inc b
    ld a,b
    cp NBUCKETS
    jr c,.bucket
    pop hl
    ld a,l
    or a
    ret

;; ls_one: DE = a symbol, B = its bucket, C = the pass
ls_one:
    ; library text defined it? (libdef_bit, the core's, done here)
    ld hl,-(SYM_LO+2)
    add hl,de                   ; 8 * the slot number
    ld a,l
    and #38
    rrca
    rrca
    rrca
    push bc
    ld b,a
    inc b
    ld a,#80
.bit:
    rlca
    djnz .bit                   ; A = 1 << (slot and 7)
    add hl,hl
    add hl,hl                   ; H = the slot / 8
    ld l,h
    ld h,0
    push de
    ld de,LIBDEFS
    add hl,de
    pop de
    and (hl)
    pop bc
    ret z                       ; (A = 0)
    ld hl,SY_FUNC
    add hl,de                   ; HL = its function's place
    ld a,c
    or a
    jr z,ls_hide
    dec a
    jr z,ls_sort
;; pass 2: a function of 1 (a fixnum 0) waits for its stub
    ld a,(hl)
    dec a
    inc hl
    or (hl)
    dec hl
    ret nz
    push hl
    call ls_probe               ; DE = the text
    pop hl
    jr nc,.lazy
    push hl
    ld hl,HDR_AUTOLOAD
    CORE alloc_typed
    ex de,hl
    pop hl
.set:
    ld (hl),e
    inc hl
    ld (hl),d
    ret
.lazy:
    push hl
    ld de,-SY_FUNC
    add hl,de
    ex de,hl
    call ls_lazy                ; DE = its stub
    pop hl
    jr c,.set
    ld de,0                     ; (cannot be: it was there in pass 0)
    jr .set

;; pass 0: a closure, its name an autoload in a part's table -> hidden
ls_hide:
    push hl
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a                      ; HL = the function
    and 3
    cp 2
    jr nz,.no                   ; not a typed cell
    ld a,h
    cp CELL_LO >> 8
    jr c,.no
    cp #C0
    jr nc,.no                   ; a builtin's
    dec hl
    dec hl
    ld a,(hl)
    cp HDR_CLOSURE and #FF
    jr nz,.no
    inc hl
    ld a,(hl)
    cp HDR_CLOSURE >> 8
    jr nz,.no
    inc hl                      ; HL = the function again
    push hl
    push de
    call ls_probe
    pop de
    jr c,.yes
    call ls_lazy                ; DE = its stub, if it was loaded lazily
    pop hl
    jr nc,.no
    or a
    sbc hl,de
    jr nz,.hide                 ; (not the stub itself)
.no:
    pop hl
    xor a
    ret
.yes:
    pop hl
.hide:
    pop hl
    inc (hl)                    ; odd: the GC takes it for a fixnum
    ld a,1
    ret

;; pass 1: hidden (odd, not 1) -> freed by the GC? 1, for a stub : as it was
ls_sort:
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; HL = the place + 1
    bit 0,e
    ret z                       ; not hidden
    ld a,d
    or a
    jr nz,.hidden
    ld a,e
    cp 1
    ret z                       ; (waiting already: cannot be)
.hidden:
    dec de                      ; DE = the closure again
    push hl
    ld h,d
    ld l,e
    dec hl
    dec hl                      ; its cell's car
    ld a,(hl)
    cp FREEMARK and #FF
    jr nz,.alive
    inc hl
    ld a,(hl)
    cp FREEMARK >> 8
.alive:
    pop hl                      ; (the flags kept)
    jr z,.freed
    ld (hl),d                   ; still held: put back
    dec hl
    ld (hl),e
    ret
.freed:
    ld (hl),0                   ; 1: a stub to come
    dec hl
    ld (hl),1
    ret

;; ls_probe: DE = a symbol, B = its bucket -> C if a part's table has its
;; name as an autoload: DE = the text, its part in the top two bits. NC if
;; not (or its name is a builtin's, in the core ROM). B kept.
ls_probe:
    ex de,hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = its name: [length][characters]
    ld a,d
    cp #C0
    ret nc                      ; in the core's ROM: NC
    ld a,(de)
    ld c,a                      ; C = the length
    inc de
    ld a,(de)
    or a
    ret nz                      ; (longer than any name in a table)
    inc de                      ; DE = the characters
    ld hl,V_LIBS
    push bc
    ld b,0                      ; B = the part, in the top two bits
.part:
    ld a,(hl)
    or a
    jr z,.nextpart
    ld (V_PEEKROM),a
    push hl
    inc hl
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a                      ; its hash table
    ex (sp),hl                  ; (the part's place kept)
    push hl
    ld hl,5
    add hl,sp
    ld a,(hl)                   ; the bucket: the B pushed above (C under it)
    pop hl
    ex (sp),hl
    push de
    ld e,a
    ld d,0
    add hl,de
    add hl,de
    call ls_word                ; HL = the first entry
    pop de
.walk:
    ld a,h
    or l
    jr z,.nextpop
    push hl
    push de
    ld de,LE_LEN
    add hl,de
    call ls_peek
    pop de
    cp c
    jr nz,.no
    push de
    push bc
    ld b,c
.cmp:
    inc hl
    call ls_peek
    ex de,hl
    cp (hl)
    ex de,hl
    jr nz,.ne
    inc de
    djnz .cmp
    pop bc
    pop de
    pop hl                      ; the entry: found
    pop af                      ; (the part's place)
    push hl
    ld de,LE_KIND
    add hl,de
    call ls_peek
    pop hl
    cp 2
    jr nz,.notauto
    ld de,LE_ADDR
    add hl,de
    call ls_word
    ld a,h
    and #3F
    or b
    ld d,a
    ld e,l
    pop bc
    scf
    ret
.notauto:
    pop bc
    or a
    ret
.ne:
    pop bc
    pop de
.no:
    pop hl
    call ls_word                ; the next entry
    jr .walk
.nextpop:
    pop hl
.nextpart:
    ld a,b
    add a,#40
    ld b,a
    jr z,.none
    inc hl
    inc hl
    inc hl
    inc hl
    inc hl
    jr .part
.none:
    pop bc
    or a
    ret

;; ls_lazy: DE = a symbol -> C if its plist has %LAZY, a list (stub ...):
;; DE = the stub. NC if not.
ls_lazy:
    ld hl,SY_PLIST
    add hl,de
    ld a,(hl)
    and #FC                     ; (the flags)
    ld e,a
    inc hl
    ld d,(hl)                   ; DE = the plist
.pair:
    ld a,d
    or e
    ret z                       ; (NC)
    ex de,hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = a key
    inc hl
    push hl
    call ls_islazy
    pop hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = (its value . the rest)
    jr z,.found                 ; (ls_islazy's Z)
    ld a,d
    or e
    ret z                       ; (NC)
    ex de,hl
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    jr .pair
.found:
    ld a,d
    or e
    ret z                       ; (NC)
    ex de,hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = the value
    ld a,e
    and 3
    ret nz                      ; not a list (NC)
    or d
    ret z                       ; NIL (NC)
    ex de,hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; the stub
    scf
    ret

;; ls_islazy: DE = an object -> Z if it is the symbol %LAZY
ls_islazy:
    ld hl,ls_lazyname
;; ls_named: DE = an object, HL = a name here ([length][0][characters]) ->
;; Z if it is the symbol of that name (not a builtin's). BC lost.
ls_named:
    ld a,e
    and 3
    cp 2
    ret nz
    ld a,d
    cp SYM_LO >> 8
    jr c,.no
    cp CELL_LO >> 8
    jr nc,.no
    push hl
    ex de,hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; its name
    pop hl
    ld a,d
    cp #C0
    jr nc,.no                   ; a builtin's
    ld a,(hl)
    add a,2
    ld b,a
.cmp:
    ld a,(de)
    cp (hl)
    ret nz
    inc de
    inc hl
    djnz .cmp
    ret
.no:
    or 1
    ret
ls_lazyname:
    db 5,0,"%LAZY"

;; ls_peek: HL = an address in the part V_PEEKROM says -> A = its byte.
;; All else kept. ls_word: -> HL = the word there.
ls_peek     equ LIBPEEK
ls_word:
    push de
    call ls_peek
    ld e,a
    inc hl
    call ls_peek
    ld h,a
    ld l,e
    pop de
    ret
