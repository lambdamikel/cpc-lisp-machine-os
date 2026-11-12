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

    ifndef BUILD_ID
BUILD_ID = 0                    ; tools/build.sh gives both ROMs the same one
    endif

    org #C000
    db 0                        ; foreground ROM
    db 0,9,5                    ; mark, version, modification: 0.95
    dw rsx_names
    jp boot                     ; entry 0: power-up, or |LISP

rsx_names:
    db "LIS","P"+#80
    db 0

boot:
    MACH_START                  ; the machine ready: mach/cpc/mmacros.asm
    ; clear our areas
    ld hl,LOWMEM
    ld de,LOWMEM+1
    ld bc,SYM_LO-LOWMEM-1
    ld (hl),0
    ldir
    ld hl,VARS
    ld de,VARS+1
    ld bc,V_END-VARS-1
    ld (hl),0
    ldir
    pop hl
    MACH_INIT                   ; V_MEMTOP, V_EDITV...

    ; THE LAYOUT, from the top down: the machine stack, block space (a
    ; share of what is left, MACH_BLOCKS's), the mark bitmap, the cells.
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
    MACH_BLOCKS                 ; HL: for block space
    res 0,l
    ex de,hl
    pop hl
    or a
    sbc hl,de
    ld (V_BLKLO),hl
    ld (V_BLKTOP),hl
    ifdef CELL_TOP              ; (the plain 6128: code between the cells
    ld hl,CELL_TOP              ;   and block space, memmap.asm)
    endif
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

    ; the library ROM, if there is one
    ld hl,tramp_src
    ld de,TRAMP
    ld bc,tramp_end-TRAMP
    ldir
    ld (V_TOPSP),sp             ; an error in its boot forms ends up at the REPL
    call find_library

    ld hl,banner
    call puts
    ld hl,banner_lib            ; and the library ROMs' numbers
    ld b,NLIBS
    ld de,V_LIBS
.lib:
    ld a,(de)
    or a
    jr z,.nolib
    push de
    push bc
    push af
    call puts                   ; ", library ROMs" the first time, then " "
    pop af
    ld l,a
    ld h,0
    call print_uint
    pop bc
    pop de
    ld hl,banner_sp
.nolib:
    inc de
    inc de
    inc de
    inc de
    inc de
    djnz .lib
    call newline
    call gc
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

;; tl_state: the reader, printer and editor as at a fresh prompt
tl_state:
    ld hl,NIL
    ld (V_INPTR),hl
    xor a
    ld (V_PEEK),a
    ld (V_DEPTH),a
    ld (V_INSRC),a
    ld (V_EDDEPTH),a
    ld (V_EDSTR),a
    ld (V_OUTMODE),a
    ld (V_LIBDEF),a
    ret

;; toplevel: where errors and breaks come back to. An unwind-protect still
;; on the stack has its cleanup forms run first, innermost first, as CL's
;; abort does; each frame is taken off before its forms run, so an error or
;; ESC in them only goes on outwards.
toplevel:
    ld ix,(V_BLOCKS)
.up:
    ld a,ixh
    or ixl
    jr z,.reset
    ld a,(ix+6)
    cp 2
    jr z,.protect
    ld a,(ix+8)
    ld b,(ix+9)
    ld ixl,a
    ld ixh,b
    jr .up
.protect:
    ld sp,ix
    call tl_state
    call run_cleanup
    jr toplevel
.reset:
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
    call tl_state
    ld a,(V_FILES)              ; a file left open by an error
    rra
    call c,FILE_IABANDON
    ld a,(V_FILES)
    and 2
    call nz,FILE_OABANDON
    xor a
    ld (V_FILES),a
    ld hl,(V_BLKSAVE)
    ld a,h
    or l
    jr z,repl
    ld (V_BLKHI),hl
    ld hl,0
    ld (V_BLKSAVE),hl
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
    xor a
    ld (V_MVN),a
    call eval
    ld de,(S_STAR2+SY_VALUE)    ; *** ** * as in CL
    ld (S_STAR3+SY_VALUE),de
    ld de,(S_TIMES+SY_VALUE)
    ld (S_STAR2+SY_VALUE),de
    ld (S_TIMES+SY_VALUE),hl
    call mv_list                ; every value, a line each
.pv:
    ld a,h
    or l
    jr z,repl
    push hl
    LDHLI
    call fresh_line
    call prin1
    call newline
    pop hl
    CDRHL
    jr .pv

;; error: HL = message, DE = the object it is about, or UNBOUND. With a
;; handler (%catch-errors) about, the error goes there instead, as a
;; message string and the object -- but not ESC, nor running out of memory
;; or stack: those always come back here.
error:
    push de
    push hl
    ld de,m_break
    call cmp_hl_de
    jr z,.print
    ld de,m_nomem
    call cmp_hl_de
    jr z,.print
    ld de,m_stack
    call cmp_hl_de
    jr z,.print
    call has_handler
    jr z,.print
    ld bc,0                     ; the message, a string
.len:
    ld a,(hl)
    or a
    jr z,.made
    inc hl
    inc bc
    jr .len
.made:
    pop hl                      ; its start
    call make_string
    pop de
    jp signal
.print:
    pop hl
    pop de
    push de
    push hl
    xor a
    ld (V_OUTMODE),a
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

;; (%signal message): an error, message a string: to a handler, or printed
;; and back to LISP>
subr_signal:
    ld de,UNBOUND
;; signal: HL = a message string, DE = an object or UNBOUND
signal:
    call has_handler
    jr z,.print
    push hl
    ld hl,NIL
    ld a,d
    cp UNBOUND >> 8
    jr nz,.obj
    ld a,e
    cp UNBOUND and #FF
    jr z,.none
.obj:
    ex de,hl
    ld de,NIL
    call cons                   ; (object)
.none:
    ex de,hl
    pop hl
    call cons                   ; (message . objects)
    ex de,hl
    ld hl,NIL
    call cons                   ; (NIL . condition): %catch-errors' answer
    ld de,NIL
    ld c,3
    jp unwind_to
.print:
    push de
    push hl
    xor a
    ld (V_OUTMODE),a
    call fresh_line
    ld hl,m_error
    call puts
    pop hl
    call princ
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

;; has_handler -> NZ if a %catch-errors frame is about. HL, DE kept.
has_handler:
    push hl
    push de
    ld hl,(V_BLOCKS)
.l:
    ld a,h
    or l
    jr z,.out
    push hl
    ld de,6
    add hl,de
    ld a,(hl)                   ; the frame's kind
    pop hl
    cp 3
    jr z,.yes
    ld de,8
    add hl,de
    LDHLI                       ; the one before
    jr .l
.yes:
    or a
.out:
    pop de
    pop hl
    ret

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
    include "xrom.asm"

banner:      db "CPC Lisp 0.95",13,10
             MACH_TITLE                 ; "A Lisp machine for ...": mmacros.asm
banner_lib:  db "library ROMs"
banner_sp:   db " ",0
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
m_badll:     db "bad lambda list",0
m_const:     db "cannot change a constant:",0
m_notvar:    db "not a variable:",0
m_notsym:    db "not a symbol:",0
m_notlist:   db "not a list:",0
m_notcons:   db "not a cons:",0
m_notnum:    db "not a number:",0
m_notstr:    db "not a string:",0
m_notvec:    db "not a vector:",0
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
m_eof:       db "unexpected end of text",0
m_autoload:  db "the library did not define",0
m_write:     db "cannot write the file",0

    include "symtab.asm"

rom_end:
    print "ROM used: ",rom_end-#C000," bytes, free: ",#10000-rom_end
    assert rom_end <= #10000
    defs #10000-$,#FF
