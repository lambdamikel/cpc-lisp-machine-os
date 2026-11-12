;; CPC Lisp -- the library, part 1: the natives under lazy loading
;; (lib/lazy.lsp): where the input file has got to, reading on to a
;; place in it, and marking a function as the library's.
;;
;; The core's reader counts the characters it takes from the input file in
;; V_FPOS (fl_in_open sets it to 0); one pushed back is not read yet. It is
;; in V_PEEK while the reader reads the file (load), else in SO_FPEEK.

;; (%file-pos) -> the characters of the input file read so far: a fixnum,
;; or a float past 16383. NIL if no file is open for input.
;@ %FILE-POS 0 0 lf_fpos
lf_fpos:
    ld a,(V_FILES)
    rra
    jp nc,lnil
    call fp_peek
    ld a,(hl)
    ld hl,(V_FPOS)
    or a
    jr z,.at
    dec hl                      ; (one pushed back)
.at:
    ld a,h
    cp #40
    jp nc,ln_uint
    jp ltag

;; (%file-skip n) -> T, the input file read on to position n; NIL if it is
;; past n already, or ends (or none is open)
;@ %FILE-SKIP 1 1 lf_fskip
lf_fskip:
    call lint_hl
    ex de,hl                    ; DE = n
    ld a,(V_FILES)
    rra
    jp nc,lnil                  ; no input file
    call fp_peek
    ld a,(hl)
    or a
    jr z,.skip
    ld hl,(V_FPOS)              ; one pushed back: it is at n already?
    dec hl
    or a
    sbc hl,de
    jp z,lt
    jp nc,lnil
    call fp_peek
    ld (hl),0                   ; no: it goes, it was counted
.skip:
    ld hl,(V_FPOS)
    or a
    sbc hl,de
    jp z,lt
    jp nc,lnil
    ld a,(V_FILES)
    and 4
    jp nz,lnil                  ; at its end already
    push de
    call FILE_GETC
    pop de
    jr nc,.end
    ld hl,(V_FPOS)
    inc hl
    ld (V_FPOS),hl
    cp #1A                      ; CTRL-Z ends an ASCII file
    jr z,.eof
    jr .skip
.end:
    jr nz,.eof                  ; NC, NZ: the end
    ld hl,m_break               ; NC, Z: ESC
    ld de,UNBOUND
    CORE error
.eof:
    ld hl,V_FILES
    set 2,(hl)
    jp lnil

;; fp_peek -> HL = &the input file's pushed-back character
fp_peek:
    ld hl,V_PEEK
    ld a,(V_INSRC)
    cp 3
    ret z
    ld hl,SO_FPEEK
    ret

;; (%libdef symbol) -> symbol, its definition counted as the library's
;; (LIBDEFS): save leaves it out, and it may be dropped (lib/short.asm)
;@ %LIBDEF 1 1 lf_libdef
lf_libdef:
    push hl
    CORE libdef_bit
    ld a,(hl)
    or c
    ld (hl),a
    pop hl
    ret
