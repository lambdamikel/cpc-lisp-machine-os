;; CPC Lisp -- the core ROM.
;;
;; A foreground ROM. At ROM 0, with ROMDIS silencing BASIC, the firmware
;; enters it at power-up; at any other number, |LISP from BASIC starts it.
;;
;;     tools/build.sh        -> build/LISP.ROM
;;
;; Files: defs (constants, memory map, object layout), mem (allocation and
;; the GC), sym (symbols, strings), read, print, eval (with the special
;; forms), subrs (builtin functions), symtab (the builtin symbols).
;;
;; REGISTERS: Lisp values travel in HL (results), DE and BC. Routines may
;; change any register unless they say otherwise; IX is scratch too, and a
;; routine that keeps something in IX across a call saves it. The alternate
;; registers and IY are never touched: the firmware's interrupt code owns
;; them.

    include "defs.asm"
    include "macros.asm"

    org #C000
    db 0                        ; foreground ROM
    db 0,1,0                    ; mark, version, modification
    dw rsx_names
    jp boot                     ; entry 0: power-up, or |LISP

rsx_names:
    db "LIS","P"+#80
    db 0

;; The firmware enters a foreground ROM with DE = first usable byte (&0040),
;; HL = last usable byte (&ABFF) and BC = top of the foreground's own area
;; (&B0FF), on the 464 and the 6128 alike. The background ROMs are not
;; initialised yet: that is the foreground program's job -- BASIC's first
;; instruction after LD SP,&C000 is this same CALL KL ROM WALK -- and without
;; it there is no disc.
boot:
    ld sp,#C000
    call KL_ROM_WALK            ; DE, HL in; HL out, lowered by each ROM
    push hl
    ; clear our areas
    ld hl,#0040
    ld de,#0041
    ld bc,SYM_LO-#0041
    ld (hl),0
    ldir
    ld hl,VARS
    ld de,VARS+1
    ld bc,V_END-VARS-1
    ld (hl),0
    ldir
    pop hl
    ld (V_MEMTOP),hl
    ; which machine: &BD3D is a FIRM JUMP (&EF) only on a 464
    ld hl,EDIT_6128
    ld a,(FIRM_464_PROBE)
    cp #EF
    jr nz,.not464
    ld hl,EDIT_464
.not464:
    ld (V_EDITV),hl

    ; THE LAYOUT, from the top down: the machine stack, block space (an
    ; eighth of what is left), the mark bitmap, the cells.
    ld hl,(V_MEMTOP)
    inc hl
    res 0,l
    ld (V_STKTOP),hl
    ld sp,hl
    ld (V_TOPSP),sp
    ld de,-STACK_SIZE
    add hl,de                   ; the bottom of the stack
    push hl
    ld de,STACK_MARGIN
    add hl,de
    ld (V_STKLIM),hl
    pop hl
    ld (V_BLKHI),hl
    push hl
    ld de,-CELL_LO
    add hl,de
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l
    res 0,l
    ex de,hl                    ; an eighth, for blocks
    pop hl
    or a
    sbc hl,de
    ld (V_BLKLO),hl
    ld (V_BLKTOP),hl
    ld de,-CELL_LO
    add hl,de                   ; R: for the cells and their bitmap
    push hl
    ld de,SYM_HI-SYM_LO
    add hl,de
    ld b,5
.div32:
    srl h
    rr l
    djnz .div32
    inc hl                      ; M: a bitmap big enough for R and the symbols
    ex de,hl
    pop hl
    or a
    sbc hl,de
    ld de,CELL_LO
    add hl,de
    ld a,l
    and #E0
    ld l,a                      ; the end of the cells, a multiple of 32
    ld (V_CELLHI),hl
    ld (V_BITMAP),hl
    ld de,-SYM_LO
    add hl,de
    ld b,5
.div32b:
    srl h
    rr l
    djnz .div32b
    ld (V_BMSIZE),hl

    ; the bitmap, the builtin symbols, the free lists
    ld hl,(V_BITMAP)
    ld bc,(V_BMSIZE)
    ld (hl),0
    ld e,l
    ld d,h
    inc de
    dec bc
    ldir
    call init_symbols
    call sweep_symbols
    call sweep_cells
    call intern_builtins
    ld a,r
    or #81
    ld l,a
    ld h,#5A
    ld (V_RAND),hl

    ld hl,banner
    call puts
    ld hl,(V_NFREE)
    call print_uint
    ld hl,banner2
    call puts
    jp toplevel

;; init_symbols: one slot per symtab entry, marked so the first sweep
;; keeps them
init_symbols:
    ld ix,symtab
    ld hl,SYM_LO
.loop:
    ld a,(ix+0)
    or (ix+1)
    ret z
    ld a,(ix+6)                 ; plist: none, and the flags
    ld (hl),a
    inc hl
    ld (hl),0
    inc hl
    push ix                     ; name: the entry's
    pop de
    ld a,e
    add a,8
    ld e,a
    jr nc,.n1
    inc d
.n1:
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld a,(ix+7)                 ; value
    ld de,UNBOUND
    or a
    jr z,.v
    ld de,NIL
    cp 2
    jr z,.v
    ld e,l                      ; itself: slot + 2
    ld d,h
    dec de
    dec de
.v:
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld de,UNBOUND               ; function: the entry, if it is one
    ld a,(ix+0)
    cp HDR_NOFN and #FF
    jr z,.f
    push ix
    pop de
    inc de
    inc de
.f:
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    push hl
    ld de,-8
    add hl,de
    call testset_mark
    ; the next entry: 10 + the name's length, rounded up to 4
    ld e,(ix+8)
    ld d,(ix+9)
    push ix
    pop hl
    add hl,de
    ld de,10+3
    add hl,de
    ld a,l
    and #FC
    ld l,a
    push hl
    pop ix
    pop hl
    jr .loop

;; intern_builtins: put every builtin symbol in its hash bucket
intern_builtins:
    ld hl,SYM_LO+2
.loop:
    push hl
    push hl
    call str_data
    ld b,c
    call hash_name
    add a,a
    ld e,a
    ld d,0
    ld hl,OBARRAY
    add hl,de
    ex (sp),hl                  ; HL = symbol, bucket address on the stack
    pop de
    push de
    ex de,hl
    LDHLI
    ex de,hl                    ; HL = symbol, DE = bucket list
    call cons
    ex de,hl
    pop hl
    ld (hl),e
    inc hl
    ld (hl),d
    pop hl
    ld de,8
    add hl,de
    ld de,SYM_LO+2+8*NBUILTIN
    call cmp_hl_de
    jr nz,.loop
    ret

;; ---------------------------------------------------------------------------
;; THE REPL

;; toplevel: where errors and breaks come back to
toplevel:
    ld sp,(V_TOPSP)
    ld de,NIL
    call unwind_specs
    ld hl,NIL
    ld (V_ENV),hl
    ld (V_T1),hl
    ld (V_T2),hl
    ld (V_T3),hl
    ld (V_T4),hl
    ld (V_BLOCKS),hl
    ld (V_INPTR),hl
    xor a
    ld (V_PEEK),a
    ld (V_DEPTH),a
repl:
    ld hl,prompt_main
    ld (V_PROMPT),hl
    call read
    ld a,h
    cp 4
    jr nz,.ev
    ld a,l
    cp CLOSEMARK and #FF
    jr z,repl                   ; a stray ")": ignored
    cp DOTMARK and #FF
    jr nz,.ev
    ERR m_syntax
.ev:
    call eval
    call fresh_line
    call prin1
    call newline
    jr repl

;; error: HL = message, DE = the object it is about, or UNBOUND
error:
    push de
    push hl
    call fresh_line
    ld hl,m_error
    call puts
    pop hl
    call puts
    pop hl
    ld de,UNBOUND
    call cmp_hl_de
    jr z,.nl
    ld a," "
    call putc
    call prin1
.nl:
    call newline
    jp toplevel

err_nomem:
    ERR m_nomem
err_nosyms:
    ERR m_nosyms
err_nostr:
    ERR m_nostr

    include "mem.asm"
    include "sym.asm"
    include "read.asm"
    include "print.asm"
    include "eval.asm"
    include "subrs.asm"

banner:      db "CPC Lisp 0.1",13,10,0
banner2:     db " cells free",13,10,13,10,0
prompt_main: db "LISP> ",0
prompt_cont: db "  ",0

m_error:     db "Error: ",0
m_stack:     db "stack overflow",0
m_break:     db "break",0
m_unbound:   db "unbound variable",0
m_undef:     db "undefined function",0
m_badcall:   db "illegal function call",0
m_toomany:   db "too many arguments",0
m_notfn:     db "not a function:",0
m_nargs:     db "wrong number of arguments for",0
m_few:       db "too few arguments",0
m_many:      db "too many arguments",0
m_nokey:     db "&KEY is not supported yet",0
m_badll:     db "bad lambda list",0
m_const:     db "cannot change a constant:",0
m_notvar:    db "not a variable:",0
m_notsym:    db "not a symbol:",0
m_notlist:   db "not a list:",0
m_notcons:   db "not a cons:",0
m_notnum:    db "not a number:",0
m_notstr:    db "not a string:",0
m_notchar:   db "not a character:",0
m_overflow:  db "integer overflow",0
m_div0:      db "division by zero",0
m_noblock:   db "no block or catch for",0
m_place:     db "cannot setf",0
m_syntax:    db "syntax error",0
m_toolong:   db "token too long",0
m_toobig:    db "integer too large",0
m_badchar:   db "unknown character name",0
m_nomem:     db "out of memory",0
m_nosyms:    db "out of symbols",0
m_nostr:     db "out of string space",0
m_index:     db "index out of range",0
m_cells:     db " cells, ",0
m_syms:      db " symbols, ",0
m_bytes:     db " string bytes free",13,10,0

    include "symtab.asm"

rom_end:
    print "ROM used: ",rom_end-#C000," bytes, free: ",#10000-rom_end
    assert rom_end <= #10000
    defs #10000-$,#FF
