;; CPC Lisp -- the library ROMs, seen from the core.
;;
;; The library is up to four more ROMs ("parts" 0-3), built with this one
;; (tools/build.sh): native functions, functions written in Lisp, the line
;; editor, the floats. Only one upper ROM is at &C000 at a time, so they talk
;; through a trampoline in RAM that selects the other ROM with KL ROM SELECT
;; (the firmware must know which ROM is in, for its interrupt-time calls) and
;; selects ours again on the way back.
;;
;; FINDING THEM: at boot, ROMs 1-15 are searched for the signature,
;; "CPCLISPLIB" and the build number, at &C010. A library from another build
;; is not used: the ROMs call each other by address. Each says which part it
;; is; V_LIBS has the ROM number of each part (0 if it is missing), its hash
;; table and dispatcher. Then the parts' boot forms run, part 0's first.
;;
;; THEIR SYMBOLS cost nothing until used. Each part has a hash table of its
;; names, bucketed exactly like the symbol table here; when intern makes a
;; new symbol it looks in each part, and a hit gets a function: an LSUBR
;; (native code in the library) or an AUTOLOAD (Lisp text in the library,
;; read and evaluated the first time the function is called). Their data
;; word is an address in the part's ROM, &C000-&FFFF, with the top two bits
;; replaced by the part's number (lib_addr undoes that).
;;
;; Library header, at &C010 in each ROM:
;;   +0  "CPCLISPLIB"       +10 build number
;;   +12 symbol hash table  +14 boot forms (list of text addresses, 0 ends)
;;   +16 dispatcher         +18 line editor, or 0 (called like EDIT: LINEBUF
;;                              to fill, carry set for ENTER, clear for ESC)
;;   +20 number routines, or 0: four jumps -- arithmetic, read, print, round
;;       (lnum)
;;   +22 the part, 0-3
;; The first part with an editor (or number routines) gives them.
;;
;; A symbol entry: [next][kind][min][max][address][length][name...]
;;   kind 1 native (address = code), 2 autoload (address = text); other
;;   kinds are skipped

LIBHDR            equ #C010
LH_PART           equ 22
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

;; CORECALL: IX = a routine of the core's, called from the library
CORECALL:
    ld a,(V_COREROM)
    jr ROMCALL

;; EDHOOK: called before every line is read from the keyboard. It does
;; nothing; the MAME harness watches for it (it is in RAM, so its address
;; means nothing else).
EDHOOK:
    ret

;; LIBPEEK: HL = an address in the library ROM V_PEEKROM -> A = the byte
;; there. BC, DE, HL kept.
LIBPEEK:
    ld a,(V_PEEKROM)
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

;; LIBCALL: a library function, called as a subr: V_LIBFN says which, HL =
;; &arg 0, B = how many. Into its part's dispatcher.
LIBCALL:
    push hl
    ld hl,(V_LIBFN)
    LDHLI                       ; its entry
    call lib_part               ; HL = its part in V_LIBS
    ld a,(hl)                   ; the ROM
    inc hl
    inc hl
    inc hl
    push af
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    pop af
    push hl
    pop ix                      ; the dispatcher
    pop hl
    jp ROMCALL

;; lib_part: H = the high byte of a library address, the part in its top
;; two bits -> HL = the part's place in V_LIBS. BC, DE kept.
lib_part:
    ld a,h
    rlca
    rlca
    and 3
    ld l,a
    add a,a
    add a,a
    add a,l
    add a,V_LIBS and #FF
    ld l,a
    ld h,V_LIBS >> 8
    ret
    assert (V_LIBS and #FF)+5*NLIBS <= #100

;; lib_addr: HL = a library address, with its part -> HL = the address in
;; its ROM, A = the ROM. BC, DE kept.
lib_addr:
    push hl
    call lib_part
    ld a,(hl)
    pop hl
    set 7,h
    set 6,h
    ret

;; lib_word: HL = an address in the library ROM V_PEEKROM -> DE = the word
;; there, HL + 2. BC kept.
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
    call nz,lib_try
    inc c
    ld a,c
    cp 16
    jr c,.try
    ld b,0                      ; the boot forms, part by part
.part:
    ld h,b
    call lib_part
    ld a,(hl)
    or a
    jr z,.next
    ld c,a                      ; C = its ROM
    ld (V_PEEKROM),a
    ld hl,LIBHDR+14
    call lib_word
    ex de,hl                    ; HL = its list of boot forms
.form:
    ld a,c
    ld (V_PEEKROM),a            ; (reading the last one interned)
    call lib_word
    ld a,d
    or e
    jr z,.next
    push hl
    push bc
    ex de,hl
    ld a,c
    call lib_eval_text
    pop bc
    pop hl
    jr .form
.next:
    ld a,b
    add a,#40
    ld b,a
    jr nz,.part
    ret

;; lib_try: C = a ROM -> taken as its part if it is a library from this
;; build. C kept.
lib_try:
    ld hl,LIBHDR
    ld de,lib_sig
    ld b,12
.cmp:
    ld a,c
    call ROMPEEK
    ex de,hl
    cp (hl)
    ex de,hl
    ret nz
    inc hl
    inc de
    djnz .cmp
    ld a,c
    ld (V_PEEKROM),a
    ld hl,LIBHDR+LH_PART
    call LIBPEEK
    cp NLIBS
    ret nc
    rrca
    rrca
    ld h,a
    call lib_part
    ld a,(hl)
    or a
    ret nz                      ; the part is there already
    ld (hl),c
    inc hl
    ex de,hl                    ; DE = where its hash table goes
    ld hl,LIBHDR+12
    call .copy                  ; the hash table
    inc hl
    inc hl
    call .copy                  ; the dispatcher
    call lib_word               ; the line editor
    ld a,d
    or e
    jr z,.noed
    ld a,(V_EDROM)
    or a
    jr nz,.noed
    ld (V_LIBEDIT),de
    ld a,c
    ld (V_EDROM),a
.noed:
    call lib_word               ; the number routines
    ld a,d
    or e
    ret z
    ld a,(V_NUMROM)
    or a
    ret nz
    ld (V_LIBNUM),de
    ld a,c
    ld (V_NUMROM),a
    ret
;; a word of the ROM at HL to DE; both + 2
.copy:
    call .byte
.byte:
    call LIBPEEK
    ld (de),a
    inc hl
    inc de
    ret

lib_sig:
    db "CPCLISPLIB"
    dw BUILD_ID

;; lib_find: a new symbol HL, named by TOKBUF and B, hashed to bucket A. If
;; a library part has the name, the symbol gets its function. HL, BC kept.
lib_find:
    push hl
    push bc
    ld c,a                      ; C = the bucket
    ld h,0                      ; H = the part, in the top two bits
.part:
    push hl
    call lib_part
    ld a,(hl)
    or a
    jr z,.next
    ld (V_PEEKROM),a
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl                    ; its hash table
    ld e,c
    ld d,0
    add hl,de
    add hl,de
    call lib_word               ; DE = the first entry
.walk:
    ld a,d
    or e
    jr z,.next
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
.next:
    pop hl
    ld a,h
    add a,#40
    ld h,a
    jr nz,.part
    jr .none
.found:
    pop bc                      ; B = the part
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
    ld a,d
    and #3F
    or b
    ld d,a                      ; with its part
    call alloc_typed
    ex de,hl
    pop bc
    pop hl
    push hl
    push bc
    ld bc,SY_FUNC
    add hl,bc
    ld (hl),e
    inc hl
    ld (hl),d
.none:
    pop bc
    pop hl
    ret

;; lib_eval_text: HL = text in library ROM A -> reads one form from it and
;; evaluates it. The reader's own state is put back first, so this can
;; happen in the middle of reading something else. Whatever the form
;; defines is marked as the library's (V_LIBDEF, mark_def).
lib_eval_text:
    ld de,(V_SRCPTR)
    push de
    ld e,a
    ld a,(V_SRCROM)
    ld d,a
    push de
    ld a,e
    ld (V_SRCROM),a
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
    ld a,d
    ld (V_SRCROM),a
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
    call lib_addr
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

;; Numbers other than fixnums -- floats -- are the library's: lnum_* call
;; its number routines with HL, DE, BC passed through; carry set if there is
;; no library.
;;   lnum_arith: HL = &arg 0, B = n, C as the subr had it, DE = its NUM_
;;               label -> HL = the result (see nums_v)
;;   lnum_read:  TOKBUF holds B characters -> NC and HL = a number, or C
;;   lnum_print: HL = a float -> printed
;; And num_int, for the library's natives: HL = a number that is not a
;; fixnum -> HL = it rounded, a plain 16-bit number (an error if it does not
;; fit, or is not a number). BC, DE kept.
lnum_arith:
    xor a
    jr lnum
lnum_read:
    ld a,3
    jr lnum
lnum_print:
    ld a,6
lnum:
    push hl
    push de
    ld hl,(V_LIBNUM)
    ld e,a
    ld d,0
    ld a,h
    or l
    jr z,.none
    add hl,de
    push hl
    pop ix
    pop de
    pop hl
    ld a,(V_NUMROM)
    jp ROMCALL
.none:
    pop de
    pop hl
    scf
    ret
num_int:
    ld a,9
    call lnum
    ret nc
    ex de,hl
    ld hl,m_notnum
    jp error

;; print_lsubr: HL = a library function -> #<SUBR name>
print_lsubr:
    push hl
    ld hl,str_subr
    call puts
    pop hl
    LDHLI                       ; its entry
    call lib_addr
    ld (V_PEEKROM),a
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
