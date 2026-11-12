;; CPC Lisp -- the VM ROM: the machine that runs compiled functions.
;;
;; A compiled function is a typed cell, HDR_CODE, whose data is its code
;; vector V -- or (V . environment) for a closure, or a fixnum k for the
;; k-th function of this ROM (vmtab.asm: natives, and later bytecode kept
;; here). V is a vector:
;;
;;     V[0]  the bytecode: a string, or a fixnum: its offset in this ROM
;;     V[1]  the name, for messages
;;     V[2]. the constants
;;
;; The core calls VM_ENTRY for a HDR_CODE function (VMCALL, as LIBCALL calls
;; a library part), HL = &arg 0, B = how many, V_LIBFN = the function.
;; This ROM has no names of its own: tools/mklib.py gives its functions'
;; names (the ;@vm lines) to part 1 as kind 3 entries, which make the
;; symbol's function a HDR_CODE cell holding the number.
;;
;; THE MACHINE. A stack machine: DE = the program counter, IX = the frame,
;; the Z80 stack holds the operands (Lisp values, which the GC sees there),
;; the frame's own words and its locals. An operation is a byte, 3 times its
;; number: the byte is the low byte of its stub in the dispatch page, a
;; JP to its code (NEXT: 28 T-states, and the JP 10).
;;
;; THE FRAME, from IX up (the caller pushed the arguments, then four words
;; -- the interpreter's [bc][ret][af][ret] through apply_core and ROMCALL, or
;; the VM's own [bc][pc][pc][vm_ret] -- with B = n in the highest; the
;; entry pushes the rest):
;;
;;     ix+0  ENV   the closure's environment, a list (CLO k is its kth)
;;     ix+2  CB    &V[2], where the constants start   } a raw pointer into
;;     ix+4  PB    where the bytecode starts          } block space: good
;;     ix+6  GCN   V_GCS when CB and PB were found    } while GCN = V_GCS
;;     ix+8  V     the code vector
;;     ix+10 the caller's IX
;;     ix+12 the four words; n at ix+19
;;     ix+20 the arguments, the last first: arg i at ix + 20 + 2(n-1-i)
;;
;; Locals and temporaries are pushed below IX: the first at ix-2. The
;; compiler knows the depth of everything. RET restores SP from IX, so a
;; frame leaves no garbage. Blocks move only when the GC runs, which
;; counts in V_GCS: after anything that can allocate, vm_fix moves DE (and
;; CB, PB) along if it did. A raw PC kept on the stack meanwhile is no
;; Lisp value the GC would follow (block space is above the cells).
;;
;; Registers: IX and the alternates are kept as the core asks; IY is never
;; touched (the firmware's). The core is called with SCORE (CORE takes IX).

    include "core.inc"
    include "macros.asm"

    org LIB_ORG
    db 1                        ; a background ROM
    db 0,9,5                    ; mark, version, modification: 0.95
    dw vm_names
    jp vm_init                  ; the ROM walk: nothing to do

    defs LIBHDR-$,0
    db "CPCLISPLIB"
    dw BUILD_ID
    dw 0                        ; no names
    dw 0                        ; no boot forms
    dw 0                        ; no dispatcher
    dw 0                        ; no line editor
    dw 0                        ; no number routines
    assert $ == LIBHDR+LH_PART
    db 4                        ; "part 4": the VM ROM
    db 0
    assert $ == VM_ENTRY
    jp vm_core

vm_names:
    db "LISP V","M"+#80
    db 0

vm_init:
    scf
    ret

;; SCORE: a core routine, keeping IX
macro SCORE routine
    push ix
    ld ix,{routine}
    call CORECALL
    pop ix
mend

;; NEXT: the next operation
macro NEXT
    ld a,(de)
    inc de
    ld l,a
    ld h,vm_page >> 8
    jp (hl)
mend

F_ENV   equ 0
F_CB    equ 2
F_PB    equ 4
F_GCN   equ 6
F_V     equ 8
F_IX    equ 10
F_N     equ 19
F_ARGS  equ 20

;; the VM's scratch, V_VM: never a Lisp value, never kept across a call
VM_PC   equ V_VM+0              ; ARGS, MKCLO: the program counter
VM_NREQ equ V_VM+2              ; ARGS: its operands
VM_NOPT equ V_VM+3
VM_FLG  equ V_VM+4
VM_K    equ V_VM+5
VM_NK   equ V_VM+6
VM_N    equ V_VM+7              ;   the argument count
VM_XP   equ V_VM+8              ;   &the first argument past the optionals
VM_XN   equ V_VM+10             ;   how many there are
VM_FUN  equ V_VM+12             ; the function being entered (messages)
VM_TD   equ V_VM+14             ; TCALL: the data of the one called

;; ---------------------------------------------------------------------------
;; THE DISPATCH PAGE: operation k's stub at vm_page + 3k

    align 256
vm_page:
opnum = 0
macro OP lbl
    assert $ == vm_page+3*opnum
    jp {lbl}
opnum = opnum+1
mend
    OP op_bad                   ;  0
    OP op_const                 ;  1 CONST b      push constant b
    OP op_nil                   ;  2 NIL
    OP op_t                     ;  3 T
    OP op_fix                   ;  4 FIX s        push the fixnum s
    OP op_loc                   ;  5 LOC s        push the word at ix+s
    OP op_setloc                ;  6 SETLOC s     ix+s = the top (kept)
    OP op_locb                  ;  7 LOCB s       push the car of ix+s (a box)
    OP op_setlocb               ;  8 SETLOCB s    its car = the top (kept)
    OP op_clo                   ;  9 CLO b        push the env's bth
    OP op_clob                  ; 10 CLOB b       its car (a box)
    OP op_setclob               ; 11 SETCLOB b    its car = the top (kept)
    OP op_glob                  ; 12 GLOB b       constant b's value
    OP op_setglob               ; 13 SETGLOB b    = the top (kept)
    OP op_box                   ; 14 BOX          the top -> (top)
    OP op_a0                    ; 15 A0           LOC 20: the last argument
    OP op_a1                    ; 16 A1           LOC 22
    OP op_a2                    ; 17 A2           LOC 24
    OP op_a3                    ; 18 A3           LOC 26
    OP op_l0                    ; 19 L0           LOC -2: the first local
    OP op_l1                    ; 20 L1           LOC -4
    OP op_l2                    ; 21 L2           LOC -6
    OP op_l3                    ; 22 L3           LOC -8
    OP op_drop                  ; 23 DROP
    OP op_dup                   ; 24 DUP
    OP op_slide                 ; 25 SLIDE b      drop b words under the top
    OP op_jmp                   ; 26 JMP w        relative to after w
    OP op_jnil                  ; 27 JNIL w       pop, jump if NIL (vm_false
    OP op_jt                    ; 28 JT w         pop, jump if not  knows them)
    OP op_jnilk                 ; 29 JNILK w      NIL: jump, kept; else pop
    OP op_jtk                   ; 30 JTK w        not NIL: jump, kept; else pop
    OP op_call                  ; 31 CALL b       [fn][arg]*b -> value
    OP op_tcall                 ; 32 TCALL b      the same, in tail position
    OP op_ret                   ; 33 RET
    OP op_enter                 ; 34 ENTER b      exactly b arguments
    OP op_args                  ; 35 ARGS r o f [k nk]  a lambda list
    OP op_mkclo                 ; 36 MKCLO b c    constant b closed over c
    OP op_gfn                   ; 37 GFN b        constant b's function
    OP op_car                   ; 38 CAR
    OP op_cdr                   ; 39 CDR
    OP op_cons                  ; 40 CONS
    OP op_eq                    ; 41 EQ
    OP op_not                   ; 42 NOT
    OP op_consp                 ; 43 CONSP
    OP op_atom                  ; 44 ATOM
    OP op_add                   ; 45 ADD
    OP op_sub                   ; 46 SUB
    OP op_add1                  ; 47 ADD1
    OP op_sub1                  ; 48 SUB1
    OP op_lt                    ; 49 LT
    OP op_gt                    ; 50 GT
    OP op_le                    ; 51 LE
    OP op_ge                    ; 52 GE
    OP op_numeq                 ; 53 NUMEQ
    OP op_setcar                ; 54 SETCAR       [x][v]: (car x) = v -> v
    OP op_setcdr                ; 55 SETCDR
    OP op_cadr                  ; 56 CADR
    OP op_cddr                  ; 57 CDDR
    OP op_eql                   ; 58 EQL
    OP op_zerop                 ; 59 ZEROP
    OP op_specs                 ; 60 SPECS        push V_SPECS
    OP op_bind                  ; 61 BIND b       pop; bind constant b to it
    OP op_list                  ; 62 LIST b       the b values on the top, a list
    OP op_mvlist                ; 63 MVLIST       the top -> all its values
    OP op_symbolp               ; 64 SYMBOLP
    OP op_jsup                  ; 65 JSUP s w     jump if ix+s is not UNBOUND
    OP op_supp                  ; 66 SUPP s       T if ix+s is not UNBOUND
    OP op_mvclr                 ; 67 MVCLR        no multiple values
    OP op_unbindl               ; 68 UNBINDL s    back to the V_SPECS at ix+s
    OP op_spix                  ; 69 SPIX         drop all the locals
    OP op_poploc                ; 70 POPLOC s     pop into ix+s
    OP op_jmps                  ; 71 JMPS s       short jumps, the offset a
    OP op_jnils                 ; 72 JNILS s        byte: 26-30's
    OP op_jts                   ; 73 JTS s
    OP op_jnilks                ; 74 JNILKS s
    OP op_jtks                  ; 75 JTKS s
    OP op_callg                 ; 76 CALLG k n    [arg]*n: constant k's function
    OP op_tcallg                ; 77 TCALLG k n   the same in tail position
    OP op_callr                 ; 78 CALLR k n    this ROM's kth function
    OP op_tcallr                ; 79 TCALLR k n
    OP op_oddp                  ; 80 ODDP
    OP op_evenp                 ; 81 EVENP
    OP op_mul                   ; 82 MUL
    OP op_aref                  ; 83 AREF         [v][i]: a vector's (or SVREF)
    OP op_setaref               ; 84 SETAREF k    [v][i][x] -> x; else constant
                                ;                 k's function does it
VM_NOPS equ opnum
    assert opnum <= 85

;; ---------------------------------------------------------------------------
;; ENTERING A FUNCTION

;; vm_core: from VMCALL: V_LIBFN = the function, B = n, HL = &arg 0
vm_core:
    ld de,(V_LIBFN)
;; vm_enter: DE = a compiled function, B = n; below its arguments, the four
;; words of its caller
vm_enter:
    push ix
;; vm_enter2: the same, the caller's IX pushed already (a tail call)
vm_enter2:
    ld (VM_FUN),de
    ex de,hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = its data
;; vm_enter2d: DE = the data
vm_enter2d:
    ld hl,NIL                   ; HL = its environment
    ld a,e
    and 3
    jr nz,.one
    ex de,hl                    ; a closure: (V . env), (k . env)
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    LDHLI
.one:
    bit 0,e
    jr nz,vm_romfn              ; k: this ROM's
;; vm_enter3: DE = V, HL = the environment
vm_enter3:
    push de                     ; V
    ld bc,(V_GCS)
    push bc                     ; GCN
    push hl                     ; (ENV, for now)
    ex de,hl
    LDHLI                       ; [len][V0][V1][constants...]
    inc hl
    inc hl
    ld c,(hl)
    inc hl
    ld b,(hl)                   ; BC = V[0]: the bytecode, a string
    inc hl
    inc hl
    inc hl
    ex de,hl                    ; DE = CB
    ld h,b
    ld l,c
    LDHLI                       ; [len lo][len hi][bytes]
    inc hl
    inc hl
    pop bc                      ; ENV
    push hl                     ; PB
    push de                     ; CB
    push bc                     ; ENV
    ld ix,0
    add ix,sp
    ex de,hl                    ; DE = PC
;; vm_go: the frame is made, DE = the start
vm_go:
    xor a
    ld (V_MVN),a                ; a call starts with no multiple values
    ld hl,(V_STKLIM)
    or a
    sbc hl,sp
    jr nc,vm_deep
    ld hl,V_BRK
    dec (hl)
    jr z,vm_poll
    NEXT
vm_deep:
    SCORE err_stack
vm_poll:                        ; every 256th call or backward jump: ESC?
    push de
    SCORE poll_esc
    pop de
    NEXT

;; vm_romfn: DE = k as a fixnum: this ROM's kth function, HL = the
;; environment (a closure's); IX pushed
vm_romfn:
    push hl
    ex de,hl
    sra h
    rr l
    add hl,hl
    add hl,hl
    ld de,vm_fntab
    add hl,de                   ; [min][max][code]
    ld c,(hl)                   ; min
    inc hl
    ld a,c
    cp 255
    jr z,vm_romcode
    pop de                      ; (no environment)
    cp 254
    jp z,vm_text
    ld e,(hl)                   ; max
    inc hl
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    push hl
    ld hl,11
    add hl,sp                   ; [code][ix][w][w][w][bc]: B
    ld b,(hl)
    ld a,b
    cp c
    jr c,.nargs
    ld a,e
    cp b
    jr c,.nargs
    pop ix                      ; the code
    ld l,b
    ld h,0
    add hl,hl
    ld de,8
    add hl,de
    add hl,sp                   ; &arg 0
    call vm_jpix                ; HL = &arg 0, B = n -> HL = the value
    pop ix
    ret
.nargs:
    ld de,(VM_FUN)
    ld hl,m_nargs
    SCORE error
vm_jpix:
    jp (ix)

;; vm_romcode: HL = the entry + 1 of bytecode in this ROM, [env] pushed.
;; Its constants are the pool's (vm_pool), which never moves its code.
vm_romcode:
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = the bytecode
    push de
    call vm_pool                ; HL = the pool
    pop bc                      ; PB
    pop de                      ; ENV
    push hl                     ; V
    ld hl,(V_GCS)
    push hl                     ; GCN
    push bc                     ; PB
    ld hl,4
    add hl,sp
    LDHLI
    LDHLI
    ld bc,6
    add hl,bc
    push hl                     ; CB = &V[2]
    push de                     ; ENV
    ld ix,0
    add ix,sp
    ld e,(ix+F_PB)
    ld d,(ix+F_PB+1)
    jp vm_go

;; vm_pool: -> HL = the constants of this ROM's bytecode, a vector read the
;; first time from vm_pool's text: V[0] a fixnum (ROM code: vm_base leaves
;; its PB), V[1] NIL, then the constants; those that are this ROM's
;; functions are cells of HDR_CODE with their numbers.
vm_pool:
    ld hl,(V_VMROOT)
    ld a,h
    or l
    ret nz
    ld hl,(vm_pooldata)
    call vm_read                ; the constants, a list
    push hl
    call vm_length
    inc bc
    inc bc
    ld de,1
    SCORE make_vector           ; V
    pop de                      ; the list
    push hl
    LDHLI
    inc hl
    inc hl
    inc hl
    inc hl                      ; &V[1]
    xor a
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
.c:
    ld a,d
    or e
    jr z,.copied
    ld a,(de)
    ld (hl),a
    inc de
    inc hl
    ld a,(de)
    ld (hl),a
    inc de
    inc hl
    ex de,hl
    LDHLI
    ex de,hl
    jr .c
.copied:
    ld hl,vm_pooldata+2         ; the references
    ld b,(hl)
    inc hl
.r:
    ld a,b
    or a
    jr z,.done
    push bc
    ld c,(hl)                   ; the constant's index
    inc hl
    ld a,(hl)                   ; the function
    inc hl
    push hl
    push bc
    call vm_fixa
    ex de,hl
    ld hl,HDR_CODE
    SCORE alloc_typed
    pop bc
    ex de,hl                    ; DE = the cell
    ld hl,4
    add hl,sp
    LDHLI                       ; V
    LDHLI
    ld b,0
    inc c
    inc c
    inc c                       ; past [len], V[0], V[1]
    add hl,bc
    add hl,bc
    ld (hl),e
    inc hl
    ld (hl),d
    pop hl
    pop bc
    djnz .r
.done:
    pop hl
    ld (V_VMROOT),hl
    ret

;; vm_read: HL = Lisp text in this ROM -> HL = the object read from it.
;; The reader's state is put back.
vm_read:
    ld de,(V_SRCPTR)
    push de
    ld a,(V_SRCROM)
    ld e,a
    ld a,(V_INSRC)
    ld d,a
    push de
    ld a,(V_PEEK)
    push af
    ld (V_SRCPTR),hl
    ld a,(V_VMROM)
    ld (V_SRCROM),a
    ld a,1
    ld (V_INSRC),a
    xor a
    ld (V_PEEK),a
    SCORE read_obj
    pop af
    ld (V_PEEK),a
    pop de
    ld a,e
    ld (V_SRCROM),a
    ld a,d
    ld (V_INSRC),a
    pop de
    ld (V_SRCPTR),de
    ret

;; vm_text: HL = the entry + 1 of a function that is Lisp text in this
;; ROM; IX pushed, the call as vm_enter has it. The text is read and
;; evaluated (a defun: from now on the symbol has that function), and the
;; call goes to what it defined.
vm_text:
    inc hl
    LDHLI                       ; the text
    ld a,(V_VMROM)
    SCORE lib_eval_text         ; -> HL = the name
    ex de,hl
    ld hl,SY_FUNC
    add hl,de
    LDHLI                       ; its function now
    push hl
    call vm_iscode
    jr nz,.ok
    LDHLI
    bit 0,l
    jr z,.ok
    ld hl,m_autoload            ; still this ROM's: not defined
    SCORE error
.ok:
    ld hl,11
    add hl,sp                   ; [F][ix][w][w][w][bc]: B
    ld c,(hl)
    ld l,c
    ld h,0
    add hl,hl
    ld de,10
    add hl,de
    add hl,sp                   ; &arg 0
    pop de                      ; F
    SCORE apply_n
    pop ix
    ret

;; vm_base: CB, PB and GCN of the frame, from its V -> HL = PB. BC, DE lost
vm_base:
    ld l,(ix+F_V)
    ld h,(ix+F_V+1)
    LDHLI                       ; [len][V0][V1][constants...]
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = V[0]
    inc hl
    inc hl
    inc hl
    ld (ix+F_CB),l
    ld (ix+F_CB+1),h
    ld hl,(V_GCS)
    ld (ix+F_GCN),l
    ld (ix+F_GCN+1),h
    ex de,hl
    bit 0,l
    jr nz,.rom
    LDHLI                       ; a string: [len lo][len hi][bytes]
    inc hl
    inc hl
    ld (ix+F_PB),l
    ld (ix+F_PB+1),h
    ret
.rom:                           ; the pool: the code is in this ROM
    ld l,(ix+F_PB)
    ld h,(ix+F_PB+1)
    ret

;; vm_fix: DE = the PC, from before something that may have run the GC ->
;; moved along with the code if it did. All kept but AF.
vm_fix:
    push hl
    ld hl,(V_GCS)
    ld a,l
    cp (ix+F_GCN)
    jr nz,.moved
    ld a,h
    cp (ix+F_GCN+1)
    jr nz,.moved
    pop hl
    ret
.moved:
    push bc
    ex de,hl
    ld e,(ix+F_PB)
    ld d,(ix+F_PB+1)
    or a
    sbc hl,de
    push hl                     ; the offset
    call vm_base
    pop de
    add hl,de
    ex de,hl
    pop bc
    pop hl
    ret

;; ---------------------------------------------------------------------------
;; HELPERS

;; vm_constb: the operand byte b -> HL = constant b. DE moved on; BC lost
vm_constb:
    ld a,(de)
    inc de
vm_const:                       ; A = the index
    ld l,a
    ld h,0
    add hl,hl
    ld c,(ix+F_CB)
    ld b,(ix+F_CB+1)
    add hl,bc
    LDHLI
    ret

;; vm_disp: the operand byte s -> HL = IX + s. DE moved on; BC lost
vm_disp:
    ld a,(de)
    inc de
    push ix
    pop hl
    ld c,a
    add a,a
    sbc a,a
    ld b,a
    add hl,bc
    ret

;; vm_nth: the operand byte b -> HL = &the car of the env's bth cons
vm_nth:
    ld a,(de)
    inc de
    ld l,(ix+F_ENV)
    ld h,(ix+F_ENV+1)
    or a
    ret z
.l:
    inc hl
    inc hl
    ld c,(hl)
    inc hl
    ld h,(hl)
    ld l,c
    dec a
    jr nz,.l
    ret

;; vm_iscode: HL -> Z if it is a compiled function. HL, DE, BC kept
vm_iscode:
    ld a,l
    and 3
    cp 2
    ret nz
    ld a,h
    cp CELL_LO >> 8
    jr c,.no
    cp #C0
    jr nc,.no
    push hl
    dec hl
    dec hl
    ld a,(hl)
    pop hl
    cp HDR_CODE and #FF
    ret
.no:
    or 1
    ret

;; vm_fn: HL = a function, or a symbol naming a global one -> HL = the
;; function; Z if it is compiled. DE (the PC) kept, moved if need be; BC
;; kept.
vm_fn:
    ld a,l
    and 7
    cp 2
    jr nz,vm_iscode
    ld a,h
    cp SYM_LO >> 8
    jr c,vm_iscode
    cp SYM_HI >> 8
    jr nc,vm_iscode
    push hl
    ld a,l
    add a,SY_FUNC               ; (the slot is 8-aligned: no carry)
    ld l,a
    LDHLI
    call vm_iscode
    jr z,.code
    ld a,l                      ; a builtin, a library native, a closure:
    and 3                       ;   apply_core takes it as it is
    cp 2
    jr nz,.core
    ld a,h
    cp #C0
    jr nc,.done
    cp CELL_LO >> 8
    jr c,.core
    push hl
    dec hl
    dec hl
    ld a,(hl)
    pop hl
    cp HDR_AUTOLOAD and #FF
    jr nz,.done
.core:
    pop hl                      ; an autoload, or not a function: the core's
    push de                     ;   way
    SCORE coerce_fn
    pop de
    call vm_fix
    jr vm_iscode
.done:
    or 1                        ; NZ: not compiled
.code:
    inc sp                      ; (the symbol: not wanted)
    inc sp
    ret

;; vm_out: (jumped to) HL = a function, C = n arguments on the stack; B
;; bit 0: return the value (a tail call), else push it and go on; bit 1:
;; the call's slot is above them, to be dropped too. The core makes the
;; call (apply_n), so any function may be called.
vm_out:
    push de
    push bc
    ex de,hl                    ; DE = the function
    ld l,c
    ld h,0
    add hl,hl
    add hl,sp
    inc hl
    inc hl                      ; &arg 0
    SCORE apply_n
    pop bc
    pop de
    ex de,hl                    ; DE = the value
    ld (VM_PC),hl
    ld a,c
    bit 1,b
    jr z,.drop
    inc a
.drop:
    ld l,a
    ld h,0
    add hl,hl
    add hl,sp
    ld sp,hl                    ; the call dropped
    push de
    ld de,(VM_PC)
    call vm_fix
    bit 0,b
    jp nz,op_ret
    NEXT

;; vm_bin: HL = a builtin, the stack [a][b] -> it is called with them (the
;; operations' way when an argument is not a fixnum)
vm_bin:
    ld bc,2
    jr vm_out
;; vm_un: HL = a builtin, the stack [a]
vm_un:
    ld bc,1
    jr vm_out

;; vm_fix2: HL = a builtin, the stack [ret][a][b] -> HL = a, BC = b if both
;; are fixnums; else the builtin is called with them, and this does not
;; return
vm_fix2:
    ld (VM_PC),hl
    pop hl
    pop bc
    ex (sp),hl                  ; HL = a, [ret]
    ld a,c
    and l
    rra
    ret c
    inc sp
    inc sp
    push hl
    push bc
    ld hl,(VM_PC)
    jr vm_bin

;; vm_scmp: HL, BC two fixnums -> C if HL < BC, Z if they are equal
vm_scmp:
    ld a,h
    xor b
    jp p,.same
    ld a,h
    rla                         ; signs differ: C if HL is the negative one
    ret                         ;   (NZ from the XOR)
.same:
    or a
    sbc hl,bc
    ret

vm_false:                       ; NIL -- or, before a JNIL or JT, the jump
    ld a,(de)
    cp 3*72                     ; JNILS: taken
    jr z,.jumps
    cp 3*73                     ; JTS: not
    jr z,.skips
    cp 3*27                     ; JNIL
    jr z,.jump
    cp 3*28                     ; JT
    jr z,.skip
    ld hl,NIL
    push hl
    NEXT
.jumps:
    inc de
    jp op_jmps
.skips:
    inc de
    inc de
    NEXT
.jump:
    inc de
    jp op_jmp
.skip:
    inc de
    inc de
    inc de
    NEXT
vm_true:                        ; T, or the same
    ld a,(de)
    cp 3*73                     ; JTS: taken
    jr z,vm_false.jumps
    cp 3*72                     ; JNILS: not
    jr z,vm_false.skips
    cp 3*28                     ; JT
    jr z,vm_false.jump
    cp 3*27                     ; JNIL
    jr z,vm_false.skip
    ld hl,S_T
    push hl
    NEXT
;; vm_bool: Z -> T, else NIL
vm_bool:
    jr z,vm_true
    jr vm_false

;; ---------------------------------------------------------------------------
;; THE OPERATIONS

op_bad:
    dec de
    ld a,(de)
    ld l,a
    ld h,0
    add hl,hl
    inc hl
    ex de,hl
    ld hl,vm_m_bad
    SCORE error

op_const:
    call vm_constb
    push hl
    NEXT
op_nil:
    ld hl,NIL
    push hl
    NEXT
op_t:
    ld hl,S_T
    push hl
    NEXT
op_fix:
    ld a,(de)
    inc de
    ld l,a
    add a,a
    sbc a,a
    ld h,a
    add hl,hl
    inc hl
    push hl
    NEXT

op_loc:
    call vm_disp
    LDHLI
    push hl
    NEXT
op_setloc:
    call vm_disp
    pop bc
    push bc
    ld (hl),c
    inc hl
    ld (hl),b
    NEXT
op_locb:
    call vm_disp
    LDHLI
    LDHLI
    push hl
    NEXT
op_setlocb:
    call vm_disp
    LDHLI
    pop bc
    push bc
    ld (hl),c
    inc hl
    ld (hl),b
    NEXT

op_a0:
    ld l,(ix+20)
    ld h,(ix+21)
    push hl
    NEXT
op_a1:
    ld l,(ix+22)
    ld h,(ix+23)
    push hl
    NEXT
op_a2:
    ld l,(ix+24)
    ld h,(ix+25)
    push hl
    NEXT
op_a3:
    ld l,(ix+26)
    ld h,(ix+27)
    push hl
    NEXT
op_l0:
    ld l,(ix-2)
    ld h,(ix-1)
    push hl
    NEXT
op_l1:
    ld l,(ix-4)
    ld h,(ix-3)
    push hl
    NEXT
op_l2:
    ld l,(ix-6)
    ld h,(ix-5)
    push hl
    NEXT
op_l3:
    ld l,(ix-8)
    ld h,(ix-7)
    push hl
    NEXT

op_clo:
    call vm_nth
    LDHLI
    push hl
    NEXT
op_clob:
    call vm_nth
    LDHLI
    LDHLI
    push hl
    NEXT
op_setclob:
    call vm_nth
    LDHLI
    pop bc
    push bc
    ld (hl),c
    inc hl
    ld (hl),b
    NEXT

op_glob:
    call vm_constb
    push hl
    inc hl
    inc hl
    LDHLI                       ; its value
    ld bc,UNBOUND
    or a
    sbc hl,bc
    jr z,.unbound
    add hl,bc
    pop bc
    push hl
    NEXT
.unbound:
    pop de
    ld hl,m_unbound
    SCORE error
op_setglob:
    call vm_constb
    inc hl
    inc hl
    pop bc
    push bc
    ld (hl),c
    inc hl
    ld (hl),b
    NEXT

op_box:
    pop hl
    push de
    ld de,NIL
    SCORE cons
    pop de
    push hl
    call vm_fix
    NEXT

op_drop:
    pop hl
    NEXT
op_dup:
    pop hl
    push hl
    push hl
    NEXT
op_slide:
    ld a,(de)
    inc de
    pop bc
    ld l,a
    ld h,0
    add hl,hl
    add hl,sp
    ld sp,hl
    push bc
    NEXT

op_jmp:
    ld a,(de)
    ld c,a
    inc de
    ld a,(de)
    ld b,a
    inc de
    ex de,hl
    add hl,bc
    ex de,hl
    bit 7,b
    jr nz,vm_back
    NEXT
vm_back:                        ; a loop: ESC now and then
    ld hl,V_BRK
    dec (hl)
    jp z,vm_poll
    NEXT
op_jnil:
    pop hl
    ld a,h
    or l
    jr z,op_jmp
vm_skip2:
    inc de
    inc de
    NEXT
op_jt:
    pop hl
    ld a,h
    or l
    jr nz,op_jmp
    jr vm_skip2
op_jnilk:
    pop hl
    ld a,h
    or l
    jr nz,vm_skip2
    push hl
    jr op_jmp
op_jtk:
    pop hl
    ld a,h
    or l
    jr z,vm_skip2
    push hl
    jr op_jmp

op_jmps:
    ld a,(de)
    inc de
    ld l,a
    add a,a
    sbc a,a
    ld h,a
    add hl,de
    ex de,hl
    or a
    jp nz,vm_back
    NEXT
op_jnils:
    pop hl
    ld a,h
    or l
    jr z,op_jmps
vm_skip1:
    inc de
    NEXT
op_jts:
    pop hl
    ld a,h
    or l
    jr nz,op_jmps
    jr vm_skip1
op_jnilks:
    pop hl
    ld a,h
    or l
    jr nz,vm_skip1
    push hl
    jr op_jmps
op_jtks:
    pop hl
    ld a,h
    or l
    jr z,vm_skip1
    push hl
    jr op_jmps

op_jsup:
    call vm_disp
    LDHLI
    ld bc,UNBOUND
    or a
    sbc hl,bc
    jp nz,op_jmp
    jr vm_skip2
op_supp:
    call vm_disp
    LDHLI
    ld bc,UNBOUND
    or a
    sbc hl,bc
    jp z,vm_false
    jp vm_true

;; CALL n: [fn][arg]*n; CALLG k n: [arg]*n and constant k's function (a
;; symbol's global one). A compiled function runs here, anything else
;; through the core.
op_call:
    ld a,(de)
    inc de
    ld c,a
    ld l,a
    ld h,0
    add hl,hl
    add hl,sp
    LDHLI                       ; the slot
    ld b,2
;; vm_call: HL = the function, or a symbol; C = n; B = 2 with a slot, 0
;; without
vm_call:
    call vm_fn
    jr z,vm_callvm
    jp vm_out
;; CALLR k n, TCALLR k n: this ROM's kth function (the compiler's calls
;; of its own: no constant, no cell)
op_callr:
    ld a,(de)
    inc de
    call vm_fixa
    ld (VM_TD),hl
    ld a,(de)
    inc de
    ld b,a
    ld c,0                      ; [bc]: B = n, no slot
    push bc
    push de
    push de
    ld hl,vm_ret
    push hl
    push ix
    ld hl,NIL
    ld (VM_FUN),hl
    ld de,(VM_TD)
    jp vm_enter2d
op_tcallr:
    ld a,(de)
    inc de
    call vm_fixa
    ld a,(de)
    inc de
    ld c,a
    ld de,NIL
    ld (VM_FUN),de
    jp vm_taild
op_callg:
    call vm_constb
    ld a,(de)
    inc de
    ld c,a
    ld b,0
    jr vm_call
;; vm_callvm: HL = a compiled function, C = n, B = 2 with a slot: the
;; caller's four words ([bc]: B = n, C = 1 with a slot), and into it
vm_callvm:
    srl b
    ld a,b
    ld b,c
    ld c,a
    push bc
    push de
    push de
    ld de,vm_ret
    push de
    ex de,hl
    jp vm_enter

;; vm_ret: a compiled function called from here returned HL; IX is ours
;; again. The four words, the call, then on.
vm_ret:
    pop de
    pop de                      ; the PC
    pop bc                      ; B = n, C = 1 with a slot
    ld (VM_PC),de
    ex de,hl                    ; DE = the value
    ld a,b
    add a,c
    ld l,a
    ld h,0
    add hl,hl
    add hl,sp
    ld sp,hl
    push de
    ld de,(VM_PC)
    call vm_fix
    NEXT

;; RET: the top is the value
op_ret:
    pop hl
    ld sp,ix
    pop bc                      ; ENV
    pop bc                      ; CB
    pop bc                      ; PB
    pop bc                      ; GCN
    pop bc                      ; V
    pop ix
    ret                         ; to vm_ret, or the core (ROMCALL)

;; TCALL n: [fn][arg]*n in tail position. A compiled function takes this
;; frame's place: its arguments go where this one's were, under the slot
;; of this one's function, then the four words (B = n now: apply_core
;; drops what B says) and the caller's IX, and into it.
op_tcall:
    ld a,(de)
    inc de
    ld c,a
    ld l,a
    ld h,0
    add hl,hl
    add hl,sp
    LDHLI                       ; the slot
    ld b,3
vm_tcall:
    call vm_fn
    jr z,vm_tail
    jp vm_out
op_tcallg:
    call vm_constb
    ld a,(de)
    inc de
    ld c,a
    ld b,1
    jr vm_tcall
;; vm_tail: HL = a compiled function, C = n: it takes this frame's place
vm_tail:
    ld (VM_FUN),hl               ; the function
    LDHLI
;; vm_taild: HL = the data of a compiled function, C = n
vm_taild:
    ld (VM_TD),hl
    ld a,c
    ld (VM_N),a
    cp (ix+F_N)
    jr nz,vm_tother
    or a                        ; as many arguments as this frame has:
    jr z,.copied                ;   over its own
    ld l,a
    ld h,0
    add hl,hl
    ld b,h
    ld c,l                      ; 2n
    push ix
    pop hl
    ld de,F_ARGS-1
    add hl,de
    add hl,bc
    ex de,hl                    ; DE = the last byte of this frame's
    ld hl,-1
    add hl,bc
    add hl,sp                   ; HL = the new ones' last byte
    lddr
.copied:
    ld hl,(VM_TD)               ; its data
    ld e,(ix+F_V)
    ld d,(ix+F_V+1)
    or a
    sbc hl,de
    jr nz,.another
    ld sp,ix                    ; this very function (not a closure): from
    ld e,(ix+F_PB)              ;   its start again
    ld d,(ix+F_PB+1)
    xor a
    ld (V_MVN),a
    jp vm_back
.another:
    ld hl,F_IX
    push ix
    pop de
    add hl,de
    ld sp,hl                    ; down to the caller's IX
    ld de,(VM_TD)
    ld a,(VM_N)
    ld b,a
    jp vm_enter2d
vm_tother:
    ld l,(ix+18)                ; the four words and the caller's IX
    ld h,c                      ;   (B = n in the highest)
    push hl
    ld l,(ix+16)
    ld h,(ix+17)
    push hl
    ld l,(ix+14)
    ld h,(ix+15)
    push hl
    ld l,(ix+12)
    ld h,(ix+13)
    push hl
    ld l,(ix+10)
    ld h,(ix+11)
    push hl
    ld l,(ix+F_N)               ; T = the slot of this frame's function:
    ld h,0                      ;   ix + 20 + 2 * its n
    add hl,hl
    ld bc,F_ARGS
    add hl,bc
    push ix
    pop bc
    add hl,bc
    ld (VM_XP),hl
    ld a,(VM_N)
    or a
    jr z,.noargs
    dec hl                      ; the arguments: [SP+10, SP+10+2n) ->
    ex de,hl                    ;   [T-2n, T); DE = the last byte there
    ld l,a
    ld h,0
    add hl,hl
    ld b,h
    ld c,l                      ; BC = 2n
    ld hl,9
    add hl,bc
    add hl,sp                   ; the source's last byte
    lddr
.noargs:
    ld a,(VM_N)                 ; the five words: [SP, SP+10) ->
    ld l,a                      ;   [T-2n-10, T-2n)
    ld h,0
    add hl,hl
    ex de,hl
    ld hl,(VM_XP)
    or a
    sbc hl,de
    dec hl
    ex de,hl                    ; DE = T-2n-1
    ld hl,9
    add hl,sp
    ld bc,10
    lddr
    inc de                      ; T-2n-10: the new SP
    ex de,hl
    ld sp,hl
    ld de,(VM_TD)
    ld a,(VM_N)
    ld b,a
    jp vm_enter2d

;; ENTER n: exactly n arguments
op_enter:
    ld a,(de)
    inc de
    cp (ix+F_N)
    jr nz,vm_nargs
    NEXT
vm_nargs:
    ld l,(ix+F_CB)
    ld h,(ix+F_CB+1)
    dec hl
    ld d,(hl)
    dec hl
    ld e,(hl)                   ; V[1]: the function's name
    ld hl,m_nargs
    SCORE error

;; ARGS nreq nopt flags [k nk]: a lambda list beyond plain variables. Its
;; variables are pushed in order, locals from ix-2 down: the required and
;; optional arguments (UNBOUND for one not given); with flags bit 0 the rest
;; as a list; with bit 1 the value of each key (constants k...: keywords),
;; UNBOUND for one not given. Without either, more arguments than
;; nreq + nopt is an error; fewer than nreq always is. (Only balanced
;; pushes in between: what is pushed for good becomes a local.)
op_args:
    ld a,(de)
    ld (VM_NREQ),a
    inc de
    ld a,(de)
    ld (VM_NOPT),a
    inc de
    ld a,(de)
    ld (VM_FLG),a
    inc de
    bit 1,a
    jr z,.nokey
    ld a,(de)
    ld (VM_K),a
    inc de
    ld a,(de)
    ld (VM_NK),a
    inc de
.nokey:
    ld (VM_PC),de
    ld a,(ix+F_N)
    ld (VM_N),a
    ld b,a
    ld a,(VM_NREQ)
    ld c,a
    ld a,b
    cp c
    jp c,vm_nargs               ; too few
    ld a,(VM_NOPT)
    add a,c
    ld c,a                      ; C = nreq + nopt
    ld l,b                      ; &arg 0 = ix + 18 + 2n
    ld h,0
    add hl,hl
    ld de,18
    add hl,de
    push ix
    pop de
    add hl,de
    ld a,b                      ; min(n, C) arguments
    cp c
    jr c,.m
    ld a,c
.m:
    or a
    jr z,.pushed
    ld b,a
.pa:
    ld e,(hl)
    inc hl
    ld d,(hl)
    dec hl
    dec hl
    dec hl
    push de
    djnz .pa
.pushed:
    ld (VM_XP),hl
    ld a,(VM_N)                 ; C - n optionals missing, or n - C more
    ld b,a
    ld a,c
    sub b
    jr c,.more
    jr z,.none
    ld b,a
    ld de,UNBOUND
.pu:
    push de
    djnz .pu
.none:
    xor a
    jr .count
.more:
    neg
.count:
    ld (VM_XN),a
    ld a,(VM_FLG)
    and 3
    jr nz,.rk
    ld a,(VM_XN)
    or a
    jp nz,vm_nargs              ; too many
    jr .done
.rk:
    rra
    jr nc,.keys
    ld de,NIL                   ; the rest: a list of the VM_XN more, the
    ld a,(VM_XN)                ;   last consed first
    or a
    jr z,.rest
    ld b,a
    dec a
    add a,a
    ld l,a
    ld h,0
    ex de,hl
    ld hl,(VM_XP)
    or a
    sbc hl,de                   ; &the last one
    ld de,NIL
.rl:
    push hl
    LDHLI
    SCORE cons                  ; (B, DE kept)
    ex de,hl
    pop hl
    inc hl
    inc hl
    djnz .rl
.rest:
    push de
.keys:
    ld a,(VM_FLG)
    bit 1,a
    jr z,.done
    ld a,(VM_K)
    ld c,a
    ld a,(VM_NK)
    ld b,a
.kl:
    push bc
    ld a,c
    call vm_const               ; HL = the keyword
    ex de,hl
    ld hl,(VM_XP)
    ld a,(VM_XN)
.ks:
    cp 2
    jr c,.knot
    push af
    ld a,(hl)
    cp e
    jr nz,.kn
    inc hl
    ld a,(hl)
    dec hl
    cp d
    jr z,.kfound
.kn:
    pop af
    sub 2
    ld bc,-4
    add hl,bc
    jr .ks
.kfound:
    pop af
    dec hl
    dec hl
    LDHLI                       ; the value after it
    jr .kv
.knot:
    ld hl,UNBOUND
.kv:
    pop bc
    push hl
    inc c
    djnz .kl
.done:
    ld de,(VM_PC)
    call vm_fix
    NEXT

;; MKCLO b c: constant b, a compiled function, closed over the c values on
;; the top (the first pushed is its CLO 0) -> a closure
op_mkclo:
    call vm_constb              ; HL = the function
    ld a,(de)
    inc de
    or a
    jr nz,.closure
    push hl                     ; nothing to close over: the function
    NEXT
.closure:
    push de
    ld (V_T4),hl                ; (a constant too: the GC keeps it)
    ld b,a
    ld hl,2
    add hl,sp                   ; the last value
    ld de,NIL
.l:
    push hl
    LDHLI
    SCORE cons                  ; (B, DE kept)
    ex de,hl
    pop hl
    inc hl
    inc hl
    djnz .l
    pop bc                      ; the PC
    ld sp,hl                    ; the values dropped
    push bc
    ld hl,(V_T4)
    LDHLI                       ; its V
    SCORE cons                  ; (V . env)
    ex de,hl
    ld hl,HDR_CODE
    SCORE alloc_typed
    pop de
    push hl
    call vm_fix
    NEXT

;; GFN b: the global function of constant b, a symbol
op_gfn:
    call vm_constb
    push de
    SCORE coerce_fn
    pop de
    push hl
    call vm_fix
    NEXT

op_car:
    pop hl
    ld a,l
    and 3
    jr nz,vm_carerr
    ld a,h
    or l
    jr z,.nil
    LDHLI
.nil:
    push hl
    NEXT
vm_carerr:                      ; the core's CAR says what is wrong
    SCORE car
op_cdr:
    pop hl
    ld a,l
    and 3
    jr nz,vm_carerr
    ld a,h
    or l
    jr z,.nil
    CDRHL
.nil:
    push hl
    NEXT
op_cadr:
    pop hl
    ld a,l
    and 3
    jr nz,vm_carerr
    ld a,h
    or l
    jr z,.nil
    CDRHL
    ld a,l
    and 3
    jr nz,vm_carerr
    ld a,h
    or l
    jr z,.nil
    LDHLI
.nil:
    push hl
    NEXT
op_cddr:
    pop hl
    ld a,l
    and 3
    jr nz,vm_carerr
    ld a,h
    or l
    jr z,.nil
    CDRHL
    ld a,l
    and 3
    jr nz,vm_carerr
    ld a,h
    or l
    jr z,.nil
    CDRHL
.nil:
    push hl
    NEXT

op_cons:
    pop bc
    pop hl
    push de
    ld d,b
    ld e,c
    SCORE cons
    pop de
    push hl
    call vm_fix
    NEXT

op_setcar:
    pop bc                      ; v
    pop hl                      ; x
    call vm_iscons
    ld (hl),c
    inc hl
    ld (hl),b
    push bc
    NEXT
op_setcdr:
    pop bc
    pop hl
    call vm_iscons
    inc hl
    inc hl
    ld (hl),c
    inc hl
    ld (hl),b
    push bc
    NEXT
;; vm_iscons: HL must be a cons (not NIL)
vm_iscons:
    ld a,l
    and 3
    jr nz,.bad
    ld a,h
    or l
    ret nz
.bad:
    ex de,hl
    ld hl,m_notcons
    SCORE error

op_eq:
    pop bc
    pop hl
    or a
    sbc hl,bc
    jp vm_bool
op_eql:
    pop bc
    pop hl
    push de
    ld d,b
    ld e,c
    SCORE eql
    pop de
    jp vm_bool
op_not:
    pop hl
    ld a,h
    or l
    jp vm_bool
op_consp:
    pop hl
    ld a,l
    and 3
    jp nz,vm_false
    ld a,h
    or l
    jp z,vm_false
    jp vm_true
op_atom:
    pop hl
    ld a,l
    and 3
    jp nz,vm_true
    ld a,h
    or l
    jp vm_bool
op_symbolp:
    pop hl
    ld a,h
    or l
    jp z,vm_true
    ld a,l
    and 7
    cp 2
    jp nz,vm_false
    ld a,h
    cp SYM_LO >> 8
    jp c,vm_false
    cp SYM_HI >> 8
    jp nc,vm_false
    jp vm_true

op_add:
    pop bc
    pop hl
    ld a,c
    and l
    rra
    jr nc,.slow
    dec hl
    dec hl                      ; (the carry adds one back)
    adc hl,bc
    jp pe,.ovf
    push hl
    NEXT
.ovf:
    scf
    sbc hl,bc
    inc hl
    inc hl
.slow:
    push hl
    push bc
    ld hl,E_PLUS+2
    jp vm_bin
op_sub:
    pop bc
    pop hl
    ld a,c
    and l
    rra
    jr nc,.slow
    or a
    sbc hl,bc
    jp pe,.ovf
    inc hl
    push hl
    NEXT
.ovf:
    add hl,bc
.slow:
    push hl
    push bc
    ld hl,E_MINUS+2
    jp vm_bin
op_add1:
    pop hl
    bit 0,l
    jr z,.slow
    ld bc,2
    or a
    adc hl,bc
    jp pe,.ovf
    push hl
    NEXT
.ovf:
    or a
    sbc hl,bc
.slow:
    push hl
    ld hl,E_ONEPLUS+2
    jp vm_un
op_sub1:
    pop hl
    bit 0,l
    jr z,.slow
    ld bc,2
    or a
    sbc hl,bc
    jp pe,.ovf
    push hl
    NEXT
.ovf:
    add hl,bc
.slow:
    push hl
    ld hl,E_ONEMINUS+2
    jp vm_un
op_zerop:
    pop hl
    bit 0,l
    jr z,.slow
    dec hl
    ld a,h
    or l
    jp vm_bool
.slow:
    push hl
    ld hl,E_ZEROP+2
    jp vm_un

op_oddp:
    pop hl
    bit 0,l
    jr z,.slow
    bit 1,l                     ; 2v+1: v is odd if bit 1 is
    jp nz,vm_true
    jp vm_false
.slow:
    push hl
    ld hl,E_ODDP+2
    jp vm_un
op_evenp:
    pop hl
    bit 0,l
    jr z,.slow
    bit 1,l
    jp z,vm_true
    jp vm_false
.slow:
    push hl
    ld hl,E_EVENP+2
    jp vm_un

;; MUL: two fixnums, the smaller magnitude the multiplier; a result too
;; big for a fixnum (or anything else) is *'s
op_mul:
    pop bc
    pop hl
    ld a,c
    and l
    rra
    jp nc,.slow
    push hl
    push bc
    push de
    sra h
    rr l
    sra b
    rr c
    ld a,h
    xor b
    push af                     ; the sign of the product
    call .abs
    push hl
    ld h,b
    ld l,c
    call .abs
    pop de                      ; DE, HL: the magnitudes
    ld b,h
    ld c,l
    ld hl,0
.m:
    srl d
    rr e
    jr nc,.n
    add hl,bc
    jr c,.ovf
.n:
    ld a,d
    or e
    jr z,.done
    sla c
    rl b
    jr c,.ovf
    bit 6,b
    jr z,.m
.ovf:
    pop af
    pop de
    pop bc
    pop hl
.slow:
    push hl
    push bc
    ld hl,E_TIMES+2
    jp vm_bin
.done:
    ld a,h
    cp #40
    jr nc,.ovf                  ; 16384 and up
    pop af
    jp p,.pos
    ld a,h                      ; negative
    cpl
    ld h,a
    ld a,l
    cpl
    ld l,a
    inc hl
.pos:
    add hl,hl
    inc hl
    pop de
    pop bc
    pop bc
    push hl
    NEXT
.abs:
    bit 7,h
    ret z
    ld a,h
    cpl
    ld h,a
    ld a,l
    cpl
    ld l,a
    inc hl
    ret

;; AREF: [v][i], v a vector and i in range; anything else is AREF's
op_aref:
    pop bc
    pop hl
    push hl
    push bc
    call vm_vref
    jr c,.slow
    LDHLI
    pop bc
    pop bc
    push hl
    NEXT
.slow:
    ld hl,E_AREF+2
    jp vm_bin
;; SETAREF k: [v][i][x]
op_setaref:
    ld a,(de)
    inc de
    pop bc
    ld (VM_PC),bc               ; x
    pop bc
    pop hl
    push hl
    push bc
    push af
    call vm_vref
    jr c,.slow
    pop af
    ld bc,(VM_PC)
    ld (hl),c
    inc hl
    ld (hl),b
    pop hl
    pop hl
    push bc
    NEXT
.slow:
    pop af
    ld hl,(VM_PC)
    push hl
    call vm_const               ; the constant's function: (v i x)
    ld bc,3
    jp vm_call
;; vm_vref: HL = v, BC = i -> NC and HL = &its element if v is a vector
;; and i an index of it; C otherwise
vm_vref:
    bit 0,c
    jr z,.no
    ld a,l
    and 3
    cp 2
    jr nz,.no
    ld a,h
    cp CELL_LO >> 8
    jr c,.no
    cp #C0
    jr nc,.no
    push hl
    dec hl
    dec hl
    ld a,(hl)
    pop hl
    cp HDR_VECTOR and #FF
    jr nz,.no
    sra b
    rr c
    bit 7,b
    jr nz,.no
    LDHLI                       ; [len][elements]
    ld a,(hl)
    inc hl
    push hl
    ld h,(hl)
    ld l,a                      ; its length, in bytes
    srl h
    rr l                        ; how many
    scf
    sbc hl,bc                   ; len - i - 1: C if i >= len
    pop hl
    ret c
    inc hl
    add hl,bc
    add hl,bc
    or a
    ret
.no:
    scf
    ret

op_lt:
    ld hl,E_LT+2
    call vm_fix2
    call vm_scmp
    jp c,vm_true
    jp vm_false
op_gt:
    ld hl,E_GT+2
    call vm_fix2
    call vm_scmp
    jp c,vm_false
    jp z,vm_false
    jp vm_true
op_le:
    ld hl,E_LE+2
    call vm_fix2
    call vm_scmp
    jp c,vm_true
    jp vm_bool
op_ge:
    ld hl,E_GE+2
    call vm_fix2
    call vm_scmp
    jp c,vm_false
    jp vm_true
op_numeq:
    ld hl,E_NUMEQ+2
    call vm_fix2
    or a
    sbc hl,bc
    jp vm_bool

;; SPECS, BIND b, UNBIND: special variables, bound as the interpreter
;; binds them (V_SPECS: (symbol . old value) pairs). SPECS pushes where
;; V_SPECS was; UNBIND [specs][v] goes back there, leaving v.
op_specs:
    ld hl,(V_SPECS)
    push hl
    NEXT
op_bind:
    call vm_constb              ; HL = the symbol
    pop bc                      ; its new value
    push de
    push bc
    push hl
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; the old value
    pop hl
    push hl
    SCORE cons                  ; (symbol . old)
    ld de,(V_SPECS)
    SCORE cons
    ld (V_SPECS),hl
    pop hl
    pop bc
    inc hl
    inc hl
    ld (hl),c
    inc hl
    ld (hl),b
    pop de
    call vm_fix
    NEXT
;; LIST b: the last value pushed is the list's last; consed from there
op_list:
    ld a,(de)
    inc de
    or a
    jp z,vm_false               ; (list): NIL (or a JNIL's jump)
    push de
    ld b,a
    ld hl,2
    add hl,sp                   ; the last value
    ld de,NIL
.l:
    push hl
    LDHLI
    SCORE cons                  ; (B, DE kept)
    ex de,hl
    pop hl
    inc hl
    inc hl
    djnz .l
    pop bc                      ; the PC
    ld sp,hl                    ; the values dropped
    push de
    ld d,b
    ld e,c
    call vm_fix
    NEXT

op_mvclr:
    xor a
    ld (V_MVN),a
    NEXT
op_mvlist:
    pop hl
    push de
    SCORE mv_list
    pop de
    push hl
    call vm_fix
    NEXT

op_unbindl:
    call vm_disp
    push de
    ld e,(hl)
    inc hl
    ld d,(hl)
    SCORE unwind_specs
    pop de
    NEXT
op_spix:
    ld sp,ix
    NEXT
op_poploc:
    call vm_disp
    pop bc
    ld (hl),c
    inc hl
    ld (hl),b
    NEXT

vm_m_bad: db "bad bytecode",0

;; ---------------------------------------------------------------------------
;; THE ROM'S FUNCTIONS: natives get HL = &arg 0 and B = how many (checked
;; against vmtab.asm), IX free; the value in HL.

;; vm_length: HL = a proper list -> BC = its length. DE, HL kept
vm_length:
    push hl
    ld bc,0
.l:
    ld a,h
    or l
    jr z,.e
    inc bc
    CDRHL
    jr .l
.e:
    pop hl
    ret

;; (%make-code bytes constants name) -> a compiled function: bytes a list
;; of fixnums 0-255, constants a list
;@vm %MAKE-CODE 3 3 vf_make_code
vf_make_code:
    NEXTARG
    push de                     ; bytes
    NEXTARG
    push de                     ; constants
    NEXTARG
    push de                     ; name
    ld hl,4
    add hl,sp
    LDHLI
    call vm_length
    ld hl,LINEBUF               ; (what it is made from does not matter)
    SCORE make_string
    push hl                     ; [string][name][constants][bytes]
    LDHLI
    inc hl
    inc hl
    ex de,hl                    ; DE = its characters
    ld hl,6
    add hl,sp
    LDHLI                       ; the bytes
.f:
    ld a,h
    or l
    jr z,vm_mkcode
    ld c,(hl)
    inc hl
    ld a,(hl)                   ; a fixnum's high byte: its bit 0 is the
    inc hl                      ;   value's bit 7
    rra
    ld a,c
    rra
    ld (de),a
    inc de
    LDHLI
    jr .f
;; vm_mkcode: the stack [string][name][constants][x], the string the
;; bytecode -> HL = the function, the four dropped
vm_mkcode:
    ld hl,4
    add hl,sp
    LDHLI                       ; the constants
    call vm_length
    inc bc
    inc bc
    ld de,NIL
    SCORE make_vector           ; V
    pop de                      ; the string
    push hl                     ; [V][name][constants][bytes]
    LDHLI
    inc hl
    inc hl                      ; &V[0]
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ex de,hl
    ld hl,2
    add hl,sp
    ldi                         ; V[1] = the name
    ldi
    LDHLI                       ; the constants
    ex de,hl                    ; DE = them, HL = &V[2]
.c:
    ld a,d
    or e
    jr z,.copied
    ld a,(de)
    ld (hl),a
    inc de
    inc hl
    ld a,(de)
    ld (hl),a
    inc de
    inc hl
    ex de,hl
    LDHLI
    ex de,hl
    jr .c
.copied:
    pop de                      ; V
    pop hl
    pop hl
    pop hl
    ld hl,HDR_CODE
    SCORE alloc_typed
    ret

vm_nil:
    ld hl,NIL
    ret
vm_t:
    ld hl,S_T
    ret
vm_fixa:                        ; A -> HL = it, a fixnum
    ld l,a
    ld h,0
    add hl,hl
    inc hl
    ret

;; vm_codev: HL -> Z and HL = its code vector if it is a compiled function
;; (not one of this ROM's own)
vm_codev:
    call vm_iscode
    ret nz
    LDHLI                       ; its data
    bit 0,l
    jr nz,.no
    ld a,l
    and 3
    jr nz,.v
    LDHLI                       ; (V . env)
.v:
    cp a
    ret
.no:
    or 1
    ret

;; (%vm-release): the compiler's constants may go (the next call reads
;; them again)
;@vm %VM-RELEASE 0 0 vf_vm_release
vf_vm_release:
    ld hl,NIL
    ld (V_VMROOT),hl
    ret

;; (%fn-info x): what x, or a symbol's global function (loaded, if it is
;; the library's Lisp), is: 0 nothing, 1 a macro, 2 an interpreted
;; function, 3 a compiled one, 4 another function
;@vm %FN-INFO 1 1 vf_fn_info
vf_fn_info:
    LDHLI
    SCORE is_symbol
    jr nz,.fn
    ex de,hl
    ld hl,SY_FUNC
    add hl,de
    LDHLI
    SCORE resolve_fn
.fn:
    xor a
    ld c,a
    ld a,l
    and 3
    cp 2
    jr nz,.done
    ld a,h
    cp #C0
    jr nc,.rom
    cp CELL_LO >> 8
    jr c,.done
    push hl
    dec hl
    dec hl
    ld a,(hl)
    pop hl
    ld c,1
    cp HDR_MACRO and #FF
    jr z,.done
    inc c
    cp HDR_CLOSURE and #FF
    jr z,.done
    inc c
    cp HDR_CODE and #FF
    jr z,.done
    inc c
    cp HDR_LSUBR and #FF
    jr z,.done
    ld c,0
    jr .done
.rom:
    SCORE is_function           ; a subr; not a special form
    ld c,4
    jr z,.done
    ld c,0
.done:
    ld a,c
    jp vm_fixa

;; (%fn-data f): an interpreted function's (or macro's) (code . env),
;; code being (lambda-list . body); else NIL
;@vm %FN-DATA 1 1 vf_fn_data
vf_fn_data:
    LDHLI
    ld a,l
    and 3
    cp 2
    jp nz,vm_nil
    ld a,h
    cp #C0
    jp nc,vm_nil
    cp CELL_LO >> 8
    jp c,vm_nil
    push hl
    dec hl
    dec hl
    ld a,(hl)
    pop hl
    cp HDR_MACRO and #FF
    jr nz,.clo
    LDHLI                       ; its closure
    jr .data
.clo:
    cp HDR_CLOSURE and #FF
    jp nz,vm_nil
.data:
    LDHLI
    ret

;; (%symbol-flags s): 1 special, 2 constant, both, or 0
;@vm %SYMBOL-FLAGS 1 1 vf_symbol_flags
vf_symbol_flags:
    LDHLI
    ld a,h
    or l
    ld a,2
    jp z,vm_fixa                ; NIL
    SCORE is_symbol
    jp nz,vm_nil
    dec hl
    dec hl
    ld a,(hl)
    and SF_SPECIAL or SF_CONST
    jp vm_fixa

;; (%op-name k), (%op-kind k): for disassemble: operation k's name, a
;; string, and its operands' kind
;@vm %OP-NAME 1 1 vf_op_name
vf_op_name:
    LDHLI
    srl h
    rr l
    ld b,l                      ; k
    ld hl,vm_opnames
    inc b
.f:
    dec b
    jr z,.at
.s:
    bit 7,(hl)
    inc hl
    jr z,.s
    jr .f
.at:
    push hl
    ld bc,0
.n:
    inc bc
    bit 7,(hl)
    inc hl
    jr z,.n
    pop hl
    ld de,TOKBUF
    push bc
    push de
    ldir
    dec de
    ld a,(de)
    and #7F
    ld (de),a
    pop hl
    pop bc
    SCORE make_string
    ret
;@vm %OP-KIND 1 1 vf_op_kind
vf_op_kind:
    LDHLI
    srl h
    rr l
    ld de,vm_opkinds
    add hl,de
    ld a,(hl)
    sub "0"
    jp vm_fixa
macro OPNAME str,last
    db {str},{last}+#80
mend
vm_opnames:
    OPNAME "BA","D"
    OPNAME "CONS","T"
    OPNAME "NI","L"
    db "T"+#80
    OPNAME "FI","X"
    OPNAME "LO","C"
    OPNAME "SETLO","C"
    OPNAME "LOC","B"
    OPNAME "SETLOC","B"
    OPNAME "CL","O"
    OPNAME "CLO","B"
    OPNAME "SETCLO","B"
    OPNAME "GLO","B"
    OPNAME "SETGLO","B"
    OPNAME "BO","X"
    OPNAME "A","0"
    OPNAME "A","1"
    OPNAME "A","2"
    OPNAME "A","3"
    OPNAME "L","0"
    OPNAME "L","1"
    OPNAME "L","2"
    OPNAME "L","3"
    OPNAME "DRO","P"
    OPNAME "DU","P"
    OPNAME "SLID","E"
    OPNAME "JM","P"
    OPNAME "JNI","L"
    OPNAME "J","T"
    OPNAME "JNIL","K"
    OPNAME "JT","K"
    OPNAME "CAL","L"
    OPNAME "TCAL","L"
    OPNAME "RE","T"
    OPNAME "ENTE","R"
    OPNAME "ARG","S"
    OPNAME "MKCL","O"
    OPNAME "GF","N"
    OPNAME "CA","R"
    OPNAME "CD","R"
    OPNAME "CON","S"
    OPNAME "E","Q"
    OPNAME "NO","T"
    OPNAME "CONS","P"
    OPNAME "ATO","M"
    OPNAME "AD","D"
    OPNAME "SU","B"
    OPNAME "ADD","1"
    OPNAME "SUB","1"
    OPNAME "L","T"
    OPNAME "G","T"
    OPNAME "L","E"
    OPNAME "G","E"
    OPNAME "NUME","Q"
    OPNAME "SETCA","R"
    OPNAME "SETCD","R"
    OPNAME "CAD","R"
    OPNAME "CDD","R"
    OPNAME "EQ","L"
    OPNAME "ZERO","P"
    OPNAME "SPEC","S"
    OPNAME "BIN","D"
    OPNAME "LIS","T"
    OPNAME "MVLIS","T"
    OPNAME "SYMBOL","P"
    OPNAME "JSU","P"
    OPNAME "SUP","P"
    OPNAME "MVCL","R"
    OPNAME "UNBIND","L"
    OPNAME "SPI","X"
    OPNAME "POPLO","C"
    OPNAME "JMP","S"
    OPNAME "JNIL","S"
    OPNAME "JT","S"
    OPNAME "JNILK","S"
    OPNAME "JTK","S"
    OPNAME "CALL","G"
    OPNAME "TCALL","G"
    OPNAME "CALL","R"
    OPNAME "TCALL","R"
    OPNAME "ODD","P"
    OPNAME "EVEN","P"
    OPNAME "MU","L"
    OPNAME "ARE","F"
    OPNAME "SETARE","F"
;; operands: 0 none, 1 a constant, 2 a place, 3 a jump, 4 a count, 5 ARGS,
;; 6 MKCLO, 7 JSUP, 8 a short jump, 9 CALLG, a CALLR
vm_opkinds:
    db "0100222224441100000000000433333440456100000000000000000000000140072020288888999900001"
    assert $-vm_opkinds == VM_NOPS

;; (%code hex constants name): a compiled function from what compile-file
;; wrote: hex a list of strings of hex digits, two a byte. The bytes are
;; put in one string, made first, so nothing moves while they are.
;@vm %CODE 3 3 vf_code
vf_code:
    NEXTARG
    push de                     ; hex
    NEXTARG
    push de                     ; constants
    NEXTARG
    push de                     ; name
    ld hl,4
    add hl,sp
    LDHLI
    ld bc,0                     ; how many bytes
.n:
    ld a,h
    or l
    jr z,.counted
    push hl
    LDHLI
    LDHLI
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; its length
    srl d
    rr e
    ex de,hl
    add hl,bc
    ld b,h
    ld c,l
    pop hl
    CDRHL
    jr .n
.counted:
    ld hl,LINEBUF
    SCORE make_string
    push hl                     ; [string][name][constants][hex]
    LDHLI
    inc hl
    inc hl
    ex de,hl                    ; DE = where the bytes go
    ld hl,6
    add hl,sp
    LDHLI                       ; the strings
.s:
    ld a,h
    or l
    jp z,vm_mkcode
    push hl
    LDHLI
    LDHLI
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl                      ; HL = its digits, BC = how many
    srl b
    rr c
.b:
    ld a,b
    or c
    jr z,.next
    call .hex
    add a,a
    add a,a
    add a,a
    add a,a
    ld (de),a
    call .hex
    ex de,hl
    or (hl)
    ld (hl),a
    ex de,hl
    inc de
    dec bc
    jr .b
.next:
    pop hl
    CDRHL
    jr .s
.hex:
    ld a,(hl)
    inc hl
    sub "0"
    cp 10
    ret c
    sub "A"-"0"-10
    ret

;; (%code-bytes f): a compiled function's bytecode, a list of fixnums
;@vm %CODE-BYTES 1 1 vf_code_bytes
vf_code_bytes:
    LDHLI
    call vm_codev
    jp nz,vm_nil
    push hl                     ; V
    LDHLI
    inc hl
    inc hl
    LDHLI                       ; V[0]
    bit 0,l
    pop bc
    jp nz,vm_nil                ; in this ROM: (not yet)
    push hl                     ; the string
    LDHLI
    ld c,(hl)
    inc hl
    ld b,(hl)                   ; BC = its length
    ld de,NIL
.l:
    ld a,b
    or c
    jr z,.done
    dec bc
    pop hl
    push hl
    LDHLI
    inc hl
    inc hl
    add hl,bc
    ld a,(hl)                   ; byte BC
    call vm_fixa
    SCORE cons                  ; (BC, DE kept)
    ex de,hl
    jr .l
.done:
    pop hl
    ex de,hl
    ret

;; (%code-consts f): (name constant...)
;@vm %CODE-CONSTS 1 1 vf_code_consts
vf_code_consts:
    LDHLI
    call vm_codev
    jp nz,vm_nil
    push hl                     ; V
    LDHLI
    ld c,(hl)
    inc hl
    ld b,(hl)                   ; its length, in bytes
    srl b
    rr c                        ; BC = how many
    ld de,NIL
.l:
    dec bc
    ld a,c
    dec a
    or b
    jr z,.done                  ; down to V[2]
    pop hl
    push hl
    LDHLI
    inc hl
    inc hl
    add hl,bc
    add hl,bc
    LDHLI
    SCORE cons
    ex de,hl
    jr .l
.done:
    pop hl
    LDHLI
    inc hl
    inc hl
    inc hl
    inc hl
    LDHLI                       ; V[1], the name
    SCORE cons
    ret

    include "vmtab.asm"
    include "vmcode.asm"

vm_end:
    print "VM used: ",vm_end-LIB_ORG," bytes, free: ",LIB_ORG+#4000-vm_end
    assert vm_end <= LIB_ORG+#4000
    defs LIB_ORG+#4000-$,#FF
