;; CPC Lisp -- the library ROM, seen from the core.
;;
;; The library is a second ROM built with this one (tools/build.sh): native
;; functions, functions written in Lisp, and later the line editor. Only one
;; upper ROM is at &C000 at a time, so the two talk through a trampoline in
;; RAM that selects the other ROM with KL ROM SELECT (the firmware must know
;; which ROM is in, for its interrupt-time calls) and selects ours again on
;; the way back.
;;
;; FINDING IT: at boot, ROMs 1-15 are searched for the library's signature,
;; "CPCLISPLIB" and the build number, at &C010. A library from another build
;; is not used: the two ROMs call each other by address.
;;
;; ITS SYMBOLS cost nothing until used. The library has a hash table of its
;; names, bucketed exactly like the symbol table here; when intern makes a
;; new symbol it looks there, and a hit gets a function: an LSUBR (native
;; code in the library) or an AUTOLOAD (Lisp text in the library, read and
;; evaluated the first time the function is called).
;;
;; Library header, at &C010 in its ROM:
;;   +0  "CPCLISPLIB"       +10 build number
;;   +12 symbol hash table  +14 boot forms (list of text addresses, 0 ends)
;;   +16 dispatcher         +18 line editor, or 0 (called like EDIT: LINEBUF
;;                              to fill, carry set for ENTER, clear for ESC)
;;
;; A symbol entry: [next][kind][min][max][address][length][name...]
;;   kind 1 native (address = code), 2 autoload (address = text); other
;;   kinds are skipped

LIBHDR            equ #C010
LE_KIND           equ 2
LE_MIN            equ 3
LE_MAX            equ 4
LE_ADDR           equ 5
LE_LEN            equ 7
LE_NAME           equ 8

;; The trampoline, assembled to run at TRAMP and copied there at boot.
tramp_src:
    org TRAMP,tramp_src

;; ROMCALL: A = a ROM, IX = an address in it. HL, DE, BC go in and come
;; back out, and so do A and the flags.
ROMCALL:
    ld (V_RCBC),bc
    ld c,a
    call KL_ROM_SELECT          ; C = the ROM that was in
    ld a,c
    ld bc,(V_RCBC)
    push af
    call .jpix
    ld (V_RCBC),bc
    ex (sp),hl                  ; H = the ROM that was in
    push af
    ld c,h
    call KL_ROM_SELECT
    pop af
    pop hl
    ld bc,(V_RCBC)
    ret
.jpix:
    jp (ix)

;; LIBCALL: into the library's dispatcher, V_LIBFN saying which function
LIBCALL:
    ld ix,(V_LIBDISP)
    ld a,(V_LIBROM)
    jr ROMCALL

;; CORECALL: IX = a routine of the core's, called from the library
CORECALL:
    ld a,(V_COREROM)
    jr ROMCALL

;; EDHOOK: called before every line is read from the keyboard. It does
;; nothing; the MAME harness watches for it (it is in RAM, so its address
;; means nothing else).
EDHOOK:
    ret

;; LIBPEEK: HL = an address in the library -> A = the byte there. BC, DE,
;; HL kept.
LIBPEEK:
    ld a,(V_LIBROM)
;; ROMPEEK: the same in ROM A
ROMPEEK:
    push bc
    ld c,a
    call KL_ROM_SELECT
    ld a,(hl)
    push af
    call KL_ROM_SELECT
    pop af
    pop bc
    ret
tramp_end:
    org tramp_src+tramp_end-TRAMP
    assert tramp_end <= TRAMP+128

;; lib_word: HL = an address in the library -> DE = the word there, HL + 2
lib_word:
    call LIBPEEK
    ld e,a
    inc hl
    call LIBPEEK
    ld d,a
    inc hl
    ret

;; find_library: called at boot, after the trampoline is in place
find_library:
    call KL_CURR_SELECTION
    ld (V_COREROM),a
    ld c,1
.try:
    ld a,(V_COREROM)
    cp c
    jr z,.next
    ld hl,LIBHDR
    ld de,lib_sig
    ld b,12
.cmp:
    ld a,c
    call ROMPEEK
    ex de,hl
    cp (hl)
    ex de,hl
    jr nz,.next
    inc hl
    inc de
    djnz .cmp
    ld a,c
    ld (V_LIBROM),a
    ld hl,LIBHDR+12
    call lib_word
    ld (V_LIBBKT),de
    call lib_word
    push de                     ; the boot forms
    call lib_word
    ld (V_LIBDISP),de
    call lib_word
    ld (V_LIBEDIT),de
    pop hl
.boot:
    call lib_word
    ld a,d
    or e
    ret z
    push hl
    ex de,hl
    call lib_eval_text
    pop hl
    jr .boot
.next:
    inc c
    ld a,c
    cp 16
    jr c,.try
    ret

lib_sig:
    db "CPCLISPLIB"
    dw BUILD_ID

;; lib_find: a new symbol HL, named by TOKBUF and B, hashed to bucket A. If
;; the library has the name, the symbol gets its function. HL kept.
lib_find:
    push hl
    ld e,a
    ld a,(V_LIBROM)
    or a
    jr z,.none
    ld d,0
    ld hl,(V_LIBBKT)
    add hl,de
    add hl,de
    call lib_word               ; DE = the first entry
.walk:
    ld a,d
    or e
    jr z,.none
    ld hl,LE_LEN
    add hl,de
    call LIBPEEK
    cp b
    jr nz,.no
    push de
    push bc
    ld de,TOKBUF
.cmp:
    inc hl
    call LIBPEEK
    ex de,hl
    cp (hl)
    ex de,hl
    jr nz,.ne
    inc de
    djnz .cmp
    pop bc
    pop de
    jr .found
.ne:
    pop bc
    pop de
.no:
    ex de,hl
    call lib_word               ; the next entry
    jr .walk
.found:
    ld hl,LE_KIND
    add hl,de
    call LIBPEEK
    cp 1
    jr z,.native
    cp 2
    jr nz,.none
    ld hl,LE_ADDR
    add hl,de
    call lib_word               ; DE = the text
    ld hl,HDR_AUTOLOAD
    jr .set
.native:
    ld hl,HDR_LSUBR             ; DE = the entry
.set:
    call alloc_typed
    ex de,hl
    pop hl
    push hl
    ld bc,SY_FUNC
    add hl,bc
    ld (hl),e
    inc hl
    ld (hl),d
.none:
    pop hl
    ret

;; lib_eval_text: HL = text in the library -> reads one form from it and
;; evaluates it. The reader's own state is put back first, so this can
;; happen in the middle of reading something else. Whatever the form
;; defines is marked as the library's (V_LIBDEF, mark_def).
lib_eval_text:
    ld de,(V_SRCPTR)
    push de
    ld a,(V_INSRC)
    ld d,a
    ld a,(V_PEEK)
    ld e,a
    push de
    ld (V_SRCPTR),hl
    ld a,1
    ld (V_INSRC),a
    xor a
    ld (V_PEEK),a
    call read_obj
    pop de
    ld a,d
    ld (V_INSRC),a
    ld a,e
    ld (V_PEEK),a
    pop de
    ld (V_SRCPTR),de
    ld a,(V_LIBDEF)             ; what it defines is the library's
    push af
    ld a,1
    ld (V_LIBDEF),a
    call eval
    pop af
    ld (V_LIBDEF),a
    ret

;; resolve_fn: HL = a function cell's contents, DE = its symbol. An
;; AUTOLOAD is loaded first. DE kept.
resolve_fn:
    ld a,l
    and 3
    cp 2
    ret nz
    ld a,h
    cp CELL_LO >> 8
    ret c
    cp #C0
    ret nc
    push hl
    dec hl
    dec hl
    ld a,(hl)
    pop hl
    cp HDR_AUTOLOAD and #FF
    ret nz
    push de
    LDHLI                       ; the text
    call lib_eval_text
    pop de
    ld hl,SY_FUNC
    add hl,de
    LDHLI
    push hl
    dec hl
    dec hl
    ld a,(hl)
    pop hl
    cp HDR_AUTOLOAD and #FF
    ret nz
    ld hl,m_autoload            ; it did not define what it should have
    jp error

;; print_lsubr: HL = a library function -> #<SUBR name>
print_lsubr:
    push hl
    ld hl,str_subr
    call puts
    pop hl
    LDHLI                       ; its entry
    ld de,LE_LEN
    add hl,de
    call LIBPEEK
    ld b,a
.l:
    inc hl
    call LIBPEEK
    call putc
    djnz .l
    ld a,">"
    jp putc
