;; CPC Lisp -- files: load, save, dir (library ROM).
;;
;; Through the firmware's CAS vectors, which a disc ROM (AMSDOS, Parados, the
;; LambdaSpeak card's) takes over -- or the tape, without one. The firmware
;; has one input and one output file, each needing a 2 KB buffer, lent from
;; the top of block space as the function editor's is; the reader reads the
;; input file (V_INSRC 3) and putc writes the output file (V_OUTMODE 3).
;; An error anywhere abandons whatever is open and gives the buffer back
;; (toplevel, in the core).
;;
;; A name without a "." gets ".LSP".

CAS_IN_OPEN   equ #BC77
CAS_IN_CLOSE  equ #BC7A
CAS_OUT_OPEN  equ #BC8C
CAS_OUT_CLOSE equ #BC8F
CAS_CATALOG   equ #BC9B
FL_BUF        equ 2048

fl_m_open:    db "cannot open",0
fl_m_busy:    db "a file buffer is in use already",0
fl_m_name:    db "bad file name:",0

;; fl_name: HL = a string -> TOKBUF holds the file name, B = its length
fl_name:
    push hl
    call lstring                ; HL = characters, BC = how many
    ld a,b
    or a
    jr nz,.bad
    ld a,c
    or a
    jr z,.bad
    cp 15                       ; A:NAME.EXT at most
    jr nc,.bad
    ld de,TOKBUF
    ld b,0
    push bc
    ldir
    pop bc                      ; C = the length, DE = past the name
    push de
    ld hl,TOKBUF
    ld b,c
.dot:
    ld a,(hl)
    cp "."
    jr z,.has
    inc hl
    djnz .dot
    pop de                      ; no "." in it: add ".LSP"
    ld hl,fl_ext
    push bc
    ld bc,4
    ldir
    pop bc
    ld a,c
    add a,4
    ld b,a
    pop hl
    ret
.has:
    pop de
    ld b,c
    pop hl
    ret
.bad:
    pop de
    ld hl,fl_m_name
    jp lib_error
fl_ext:
    db ".LSP"

;; fl_lend -> DE = a 2 KB buffer lent from block space
fl_lend:
    ld hl,(V_BLKSAVE)
    ld a,h
    or l
    jr z,.free
    ld hl,fl_m_busy
    ld de,UNBOUND
    jp lib_error
.free:
    call .room
    jr nc,.ok
    CORE gc
    call .room
    jr nc,.ok
    ld hl,m_nostr
    ld de,UNBOUND
    CORE error
.ok:
    ld hl,(V_BLKHI)
    ld (V_BLKSAVE),hl
    ld de,FL_BUF
    or a
    sbc hl,de
    ld (V_BLKHI),hl
    ex de,hl
    ret
;; NC if 2 KB and a little more are free
.room:
    ld hl,(V_BLKHI)
    ld de,(V_BLKTOP)
    or a
    sbc hl,de
    ld de,FL_BUF+256
    or a
    sbc hl,de
    ret

;; (load "name"): read and evaluate everything in the file -> T
;@ LOAD 1 1 lf_load
lf_load:
    push hl                     ; the name, for an error
    call fl_name
    push bc
    call fl_lend                ; DE = the buffer
    pop bc
    ld hl,TOKBUF
    call CAS_IN_OPEN
    jr c,.open
    call fe_release
    pop de
    ld hl,fl_m_open
    jp lib_error
.open:
    ld hl,V_FILES
    set 0,(hl)
    ld a,(V_INSRC)              ; the reader's state, for afterwards
    ld d,a
    ld a,(V_PEEK)
    ld e,a
    push de
    ld a,3
    ld (V_INSRC),a
    xor a
    ld (V_PEEK),a
.form:
    CORE read
    ld a,h
    cp 4
    jr nz,.eval
    ld a,l
    cp EOFMARK and #FF
    jr z,.end
    CORE check_real             ; a ")" or "." out of place
.eval:
    CORE eval
    jr .form
.end:
    pop de
    ld a,d
    ld (V_INSRC),a
    ld a,e
    ld (V_PEEK),a
    call CAS_IN_CLOSE
    ld hl,V_FILES
    res 0,(hl)
    call fe_release
    pop hl
    jp lt

;; (save "name" symbol...): their definitions, pretty-printed, into the file;
;; with no symbols, everything defined since the start (functions, macros,
;; DEFVAR and DEFPARAMETER variables). -> the symbols saved
;@ SAVE 1 255 lf_save
lf_save:
    NEXTARG
    push de                     ; the name
    dec b
    jr z,.all
    CORE args_to_list
    jr .have
.all:
    call fl_user_symbols
.have:
    ex (sp),hl                  ; the symbols on the stack, HL = the name
    push hl
    call fl_name
    push bc
    call fl_lend
    pop bc
    ld hl,TOKBUF
    call CAS_OUT_OPEN
    jr c,.open
    call fe_release
    pop de
    ld hl,fl_m_open
    jp lib_error
.open:
    pop hl                      ; (the name)
    ld hl,V_FILES
    set 1,(hl)
    ld a,3
    ld (V_OUTMODE),a
    xor a
    ld (V_OUTCOL),a
    ld a,72
    ld (PP_W),a
    pop hl                      ; the symbols
    push hl
.each:
    ld a,h
    or l
    jr z,.close
    push hl
    LDHLI
    call fl_write_def
    pop hl
    CDRHL
    jr .each
.close:
    xor a
    ld (V_OUTMODE),a
    call CAS_OUT_CLOSE
    jr c,.closed
    ld hl,m_write
    ld de,UNBOUND
    CORE error
.closed:
    ld hl,V_FILES
    res 1,(hl)
    call fe_release
    pop hl
    ret

;; fl_write_def: HL = a symbol -> its definition, as (defun ...),
;; (defmacro ...) or (defparameter name 'value), and a blank line
fl_write_def:
    push hl
    call fl_has_fn
    pop hl
    jr nz,.var
    call fe_definition
    jr .out
.var:
    push hl                     ; (defparameter name 'value)
    inc hl
    inc hl
    LDHLI                       ; the value
    ld de,NIL
    CORE cons
    ex de,hl
    ld hl,S_QUOTE
    CORE cons                   ; (quote value)
    ld de,NIL
    CORE cons
    ex de,hl
    pop hl
    CORE cons                   ; (name 'value)
    ex de,hl
    ld hl,S_DEFPARAMETER
    CORE cons
.out:
    call pp
    ld a,13
    call lputc
    ld a,10
    call lputc
    ld a,13
    call lputc
    ld a,10
    jp lputc

;; fl_has_fn: HL = a symbol -> Z if its function is a closure or a macro
fl_has_fn:
    ld de,SY_FUNC
    add hl,de
    LDHLI
    ld a,l
    and 3
    cp 2
    ret nz
    ld a,h
    cp CELL_LO >> 8
    jr c,.no
    cp #C0
    jr nc,.no
    dec hl
    dec hl
    ld a,(hl)
    cp HDR_CLOSURE and #FF
    ret z
    cp HDR_MACRO and #FF
    ret
.no:
    or 1
    ret

;; fl_user_symbols -> a list of the symbols the user defined: past the
;; builtins, not the library's own, with a function or a special value. The
;; list grows in V_T3, a GC root.
fl_user_symbols:
    ld hl,NIL
    ld (V_T3),hl
    ld hl,OBARRAY
.bucket:
    push hl
    LDHLI                       ; the bucket's symbols
.sym:
    ld a,h
    or l
    jr z,.nextb
    push hl
    LDHLI                       ; a symbol
    push hl
    call fl_is_user
    pop hl
    jr nz,.skip
    ld de,(V_T3)
    CORE cons
    ld (V_T3),hl
.skip:
    pop hl
    CDRHL
    jr .sym
.nextb:
    pop hl
    inc hl
    inc hl
    ld a,l
    cp OBARRAY_END and #FF
    jr nz,.bucket
    ld hl,(V_T3)
    ret

;; fl_is_user: HL = a symbol -> Z if the user defined it. HL kept.
fl_is_user:
    ld de,SYM_LO+2+8*NBUILTIN
    or a
    sbc hl,de
    add hl,de
    jr c,.no                    ; a builtin
    push hl
    call fl_has_fn
    pop hl
    jr z,.notlib
    push hl                     ; a special variable with a value?
    dec hl
    dec hl
    ld a,(hl)
    pop hl
    and SF_SPECIAL
    jr z,.no
    push hl
    inc hl
    inc hl
    LDHLI
    ld de,UNBOUND
    or a
    sbc hl,de
    pop hl
    jr z,.no
.notlib:
    call fl_libname
    jr z,.no                    ; the library's
    cp a
    ret
.no:
    or 1
    ret

;; fl_libname: HL = a symbol -> Z if the library has a name like it. HL kept.
fl_libname:
    push hl
    LDHLI                       ; its name: [length][characters]
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    ld a,b
    or a
    jr nz,.no
    ld b,c
    push hl
    push bc
    CORE hash_name              ; A = its bucket
    pop bc
    pop de                      ; DE = the characters, B = how many
    ld l,a
    ld h,0
    add hl,hl
    push de
    ld de,lib_buckets
    add hl,de
    pop de
    LDHLI                       ; the bucket's first entry
.walk:
    ld a,h
    or l
    jr z,.no
    push hl
    ld a,l
    add a,LE_LEN
    ld l,a
    jr nc,.nc
    inc h
.nc:
    ld a,(hl)
    cp b
    jr nz,.next
    push de
    push bc
.c:
    inc hl
    ld a,(de)
    cp (hl)
    jr nz,.ne
    inc de
    djnz .c
    pop bc
    pop de
    pop hl
    pop hl
    cp a
    ret
.ne:
    pop bc
    pop de
.next:
    pop hl
    LDHLI                       ; the next entry
    jr .walk
.no:
    pop hl
    or 1
    ret

;; (dir): the catalogue, as the disc ROM prints it -> NIL
;@ DIR 0 0 lf_dir
lf_dir:
    call fl_lend
    call CAS_CATALOG
    call fe_release
    jp lnil
