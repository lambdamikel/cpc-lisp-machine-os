;; CPC Lisp -- characters and strings the CL way (library ROM, part 0):
;; the string and character comparisons, the character predicates,
;; string-trim, string-capitalize, make-string.
;;
;; A string designator is a string, a symbol (its name) or a character.
;; Strings made here are at most 255 characters, built in TOKBUF.

LS_ALEN     equ TOKBUF+240      ; scratch: the first string's length,
LS_BLEN     equ TOKBUF+242      ;   the second's,
LS_MODE     equ TOKBUF+244      ;   what the comparison accepts (below)
LS_BAG      equ TOKBUF+246      ; string-trim: the bag

;; LS_MODE: bit 0 true when less, 1 when equal, 2 when greater; bit 3 case
;; folded; bit 4 the answer is T, not the index; bit 5 (char/=) every pair
;; must differ

;; sd_data: HL = a string designator -> HL = its characters, BC = how
;; many. Through the core's STRING, which can read a builtin symbol's name
;; (in the core ROM) -- and may allocate, so no other string's characters
;; may be held across it.
sd_data:
    CORE subr_string
    CORE str_data
    ret

;; ls_fold: A = a character -> upcased if LS_MODE says fold. All else kept.
ls_fold:
    push hl
    ld hl,LS_MODE
    bit 3,(hl)
    pop hl
    ret z
    cp "a"
    ret c
    cp "z"+1
    ret nc
    sub #20
    ret

;@ STRING= 2 2 ls_eq
ls_eq:
    ld a,2+16
    jr ls_cmp
;@ STRING/= 2 2 ls_ne
ls_ne:
    ld a,1+4
    jr ls_cmp
;@ STRING< 2 2 ls_lt
ls_lt:
    ld a,1
    jr ls_cmp
;@ STRING> 2 2 ls_gt
ls_gt:
    ld a,4
    jr ls_cmp
;@ STRING<= 2 2 ls_le
ls_le:
    ld a,1+2
    jr ls_cmp
;@ STRING>= 2 2 ls_ge
ls_ge:
    ld a,4+2
    jr ls_cmp
;@ STRING-EQUAL 2 2 ls_eqf
ls_eqf:
    ld a,2+8+16
    jr ls_cmp
;@ STRING-NOT-EQUAL 2 2 ls_nef
ls_nef:
    ld a,1+4+8
    jr ls_cmp
;@ STRING-LESSP 2 2 ls_ltf
ls_ltf:
    ld a,1+8
    jr ls_cmp
;@ STRING-GREATERP 2 2 ls_gtf
ls_gtf:
    ld a,4+8
    jr ls_cmp
;@ STRING-NOT-GREATERP 2 2 ls_lef
ls_lef:
    ld a,1+2+8
    jr ls_cmp
;@ STRING-NOT-LESSP 2 2 ls_gef
ls_gef:
    ld a,4+2+8
;; ls_cmp: HL, DE = the strings, A = LS_MODE -> T or the index where they
;; differ if the comparison holds, else NIL
ls_cmp:
    ld (LS_MODE),a
    push de
    CORE subr_string            ; both as strings first (that may allocate)
    ex (sp),hl
    CORE subr_string
    CORE str_data               ; the second's characters
    ld (LS_BLEN),bc
    ex (sp),hl                  ;   on the stack
    CORE str_data               ; the first's
    ld (LS_ALEN),bc
    pop de                      ; HL, DE: the characters; BC: the index
    ld bc,0
.l:
    push hl
    ld hl,(LS_ALEN)
    or a
    sbc hl,bc
    ld a,h
    or l
    ld hl,(LS_BLEN)
    jr z,.aend
    or a
    sbc hl,bc
    ld a,h
    or l
    pop hl
    jr z,.gt                    ; the second has ended, not the first
    push bc
    ld a,(de)
    call ls_fold
    ld b,a
    ld a,(hl)
    call ls_fold
    cp b
    pop bc
    jr c,.lt
    jr nz,.gt
    inc hl
    inc de
    inc bc
    jr .l
.aend:
    or a
    sbc hl,bc
    ld a,h
    or l
    pop hl
    jr nz,.lt                   ; the first has ended, not the second
    ld a,2
    jr .res
.lt:
    ld a,1
    jr .res
.gt:
    ld a,4
.res:
    ld hl,LS_MODE
    and (hl)
    jp z,lnil
    bit 4,(hl)
    jp nz,lt
    ld l,c
    ld h,b
    add hl,hl
    inc hl
    ret

;; the character comparisons, any number of arguments
;@ CHAR= 1 255 lc_eq
lc_eq:
    ld a,2
    jr lc_cmp
;@ CHAR/= 1 255 lc_ne
lc_ne:
    ld a,32
    jr lc_cmp
;@ CHAR< 1 255 lc_lt
lc_lt:
    ld a,1
    jr lc_cmp
;@ CHAR> 1 255 lc_gt
lc_gt:
    ld a,4
    jr lc_cmp
;@ CHAR<= 1 255 lc_le
lc_le:
    ld a,1+2
    jr lc_cmp
;@ CHAR>= 1 255 lc_ge
lc_ge:
    ld a,4+2
    jr lc_cmp
;@ CHAR-EQUAL 1 255 lc_eqf
lc_eqf:
    ld a,2+8
    jr lc_cmp
;@ CHAR-NOT-EQUAL 1 255 lc_nef
lc_nef:
    ld a,32+8
    jr lc_cmp
;@ CHAR-LESSP 1 255 lc_ltf
lc_ltf:
    ld a,1+8
    jr lc_cmp
;@ CHAR-GREATERP 1 255 lc_gtf
lc_gtf:
    ld a,4+8
    jr lc_cmp
;@ CHAR-NOT-GREATERP 1 255 lc_lef
lc_lef:
    ld a,1+2+8
    jr lc_cmp
;@ CHAR-NOT-LESSP 1 255 lc_gef
lc_gef:
    ld a,4+2+8
;; lc_cmp: HL = &the first argument, B = how many, A = LS_MODE
lc_cmp:
    ld (LS_MODE),a
    bit 5,a
    jr nz,.ne
    NEXTARG
    call lc_code
    ld c,a                      ; the one before
    dec b
.l:
    ld a,b
    or a
    jp z,lt                     ; every pair holds
    NEXTARG
    call lc_code
    ld d,a
    ld a,c
    cp d
    ld c,d
    ld a,1
    jr c,.o
    ld a,2
    jr z,.o
    ld a,4
.o:
    push hl
    ld hl,LS_MODE
    and (hl)
    pop hl
    jp z,lnil
    dec b
    jr .l
.ne:                            ; char/=: no two the same
    ld a,b
    or a
    jp z,lt
    NEXTARG
    call lc_code
    ld c,a
    dec b
    push hl
    push bc
.inner:
    ld a,b
    or a
    jr z,.next
    NEXTARG
    call lc_code
    cp c
    jr z,.same
    dec b
    jr .inner
.next:
    pop bc
    pop hl
    jr .ne
.same:
    pop bc
    pop hl
    jp lnil

;; lc_code: DE = a character -> A = its code, folded if LS_MODE says. An
;; error for anything else. All else kept.
lc_code:
    ld a,e
    and 3
    cp 2
    jr nz,.bad
    ld a,d
    cp 4
    jr nc,.bad
    push de
    srl d
    rr e
    srl d
    rr e
    ld a,e
    pop de
    jp ls_fold
.bad:
    ld hl,m_notchar
    CORE error

;; lp_code: HL = a character -> A = its code (not folded)
lp_code:
    ex de,hl
    xor a
    ld (LS_MODE),a
    jr lc_code

;; carry if A is upper case, lower case, a letter, a digit
lp_upper:
    cp "A"
    ccf
    ret nc
    cp "Z"+1
    ret
lp_lower:
    cp "a"
    ccf
    ret nc
    cp "z"+1
    ret
lp_alpha:
    call lp_upper
    ret c
    jr lp_lower
lp_digit:
    cp "0"
    ccf
    ret nc
    cp "9"+1
    ret

;@ UPPER-CASE-P 1 1 lf_upper_case_p
lf_upper_case_p:
    call lp_code
    call lp_upper
    jr lp_bool
;@ LOWER-CASE-P 1 1 lf_lower_case_p
lf_lower_case_p:
    call lp_code
    call lp_lower
    jr lp_bool
;@ ALPHA-CHAR-P 1 1 lf_alpha_char_p
;@ BOTH-CASE-P 1 1 lf_alpha_char_p
lf_alpha_char_p:
    call lp_code
    call lp_alpha
    jr lp_bool
;@ ALPHANUMERICP 1 1 lf_alphanumericp
lf_alphanumericp:
    call lp_code
    call lp_alpha
    call nc,lp_digit
    jr lp_bool
;@ GRAPHIC-CHAR-P 1 1 lf_graphic_char_p
lf_graphic_char_p:
    call lp_code
    cp 127
    jp z,lnil
    cp " "
    ccf
lp_bool:
    jp c,lt
    jp lnil

;; (digit-char-p char [radix]) -> its weight, or NIL if it is no digit
;@ DIGIT-CHAR-P 1 2 lf_digit_char_p
lf_digit_char_p:
    NEXTARG
    push de                     ; the character
    call lp_radix               ; C = the radix
    pop hl
    call lp_code
    sub "0"
    cp 10
    jr c,.w
    add a,"0"
    or #20                      ; a letter, in lower case
    sub "a"
    cp 26
    jp nc,lnil
    add a,10
.w:
    cp c
    jp nc,lnil
    ld l,a
    ld h,0
    add hl,hl
    inc hl
    ret

;; (digit-char weight [radix]) -> the character, or NIL
;@ DIGIT-CHAR 1 2 lf_digit_char
lf_digit_char:
    NEXTARG
    push de
    call lp_radix
    pop hl
    call lfix_hl
    ld a,h
    or a
    jp nz,lnil
    ld a,l
    rra
    cp c
    jp nc,lnil
    cp 10
    jr c,.d
    add a,"A"-"0"-10
.d:
    add a,"0"
    jp lchar

;; lp_radix: HL = &the next argument, B = how many there were -> C = the
;; radix given (2 to 36), or 10
lp_radix:
    ld c,10
    ld a,b
    cp 2
    ret c
    NEXTARG
    ex de,hl
    call lfix_hl
    sra h
    rr l
    ld a,h
    or a
    jr nz,.bad
    ld a,l
    cp 2
    jr c,.bad
    cp 37
    jr nc,.bad
    ld c,a
    ret
.bad:
    add hl,hl
    inc hl
    ex de,hl
    ld hl,m_index
    CORE error

;; (string-trim bag string), string-left-trim, string-right-trim: the
;; string without the characters in bag (a string or a list) at its ends
;@ STRING-TRIM 2 2 lf_string_trim
lf_string_trim:
    ld a,3
    jr ls_trim
;@ STRING-LEFT-TRIM 2 2 lf_string_left_trim
lf_string_left_trim:
    ld a,1
    jr ls_trim
;@ STRING-RIGHT-TRIM 2 2 lf_string_right_trim
lf_string_right_trim:
    ld a,2
ls_trim:
    push af
    ld (LS_BAG),hl
    ex de,hl
    call sd_data                ; HL = the characters, BC = how many
    pop af
    push af
    rra
    jr nc,.right
.left:
    ld a,b
    or c
    jr z,.right
    ld a,(hl)
    call ls_inbag
    jr nz,.right
    inc hl
    dec bc
    jr .left
.right:
    pop af
    and 2
    jr z,.copy
.r:
    ld a,b
    or c
    jr z,.copy
    push hl
    add hl,bc
    dec hl
    ld a,(hl)
    pop hl
    call ls_inbag
    jr nz,.copy
    dec bc
    jr .r
.copy:
    ld a,b
    or a
    jp nz,str_long
    ld de,TOKBUF
    ld a,c
    or a
    jr z,.e
    push bc
    ldir
    pop bc
.e:
    jp lstr_result

;; ls_inbag: A = a character -> Z if it is in LS_BAG. HL, BC, DE kept.
ls_inbag:
    push hl
    push bc
    push de
    ld e,a
    ld hl,(LS_BAG)
    push hl
    CORE is_string
    pop hl
    jr nz,.list
    CORE str_data               ; (nothing has moved: no allocation)
    ld a,b
    or c
    jr z,.no
.s:
    ld a,(hl)
    cp e
    jr z,.out
    inc hl
    dec bc
    ld a,b
    or c
    jr nz,.s
    jr .no
.list:
    ld a,h
    or l
    jr z,.no
    ld a,l
    and 3
    jr nz,.no
    push hl
    LDHLI                       ; a character: 4 * code + 2
    ld a,l
    and 3
    cp 2
    jr nz,.nl
    ld a,h
    cp 4
    jr nc,.nl
    srl h
    rr l
    srl h
    rr l
    ld a,l
    cp e
    jr nz,.nl
    pop hl
    jr .out
.nl:
    pop hl
    CDRHL
    jr .list
.no:
    or 1
.out:
    pop de
    pop bc
    pop hl
    ret

;; (string-capitalize string): each word's first letter upper case, the
;; rest lower; a word is a run of letters and digits
;@ STRING-CAPITALIZE 1 1 lf_string_capitalize
lf_string_capitalize:
    call sd_data
    ld a,b
    or a
    jp nz,str_long
    push bc
    ld de,TOKBUF
    ld b,c
    ld c,0                      ; 1 inside a word
    inc b
    jr .next
.l:
    ld a,(hl)
    call lp_alpha
    call nc,lp_digit
    jr nc,.gap
    push bc
    bit 0,c
    ld c,0                      ; a word's first: up
    jr z,.case
    inc c                       ; the rest: down
.case:
    call case_char
    pop bc
    ld c,1
    jr .put
.gap:
    ld c,0
.put:
    ld (de),a
    inc hl
    inc de
.next:
    djnz .l
    pop bc
    jp lstr_result

;; (make-string n [:initial-element char]) -> n of them (blanks), n <= 255
;@ MAKE-STRING 1 3 lf_make_string
lf_make_string:
    NEXTARG
    ex de,hl
    call lfix_hl
    sra h
    rr l
    ld a,h
    or a
    jp nz,str_long
    ld c,l                      ; C = n
    ex de,hl
    ld a,b
    ld b," "
    cp 3
    jr nz,.fill
    NEXTARG                     ; the keyword (only :initial-element there is)
    NEXTARG
    push bc
    call lc_code0
    pop bc
    ld b,a
.fill:
    ld hl,TOKBUF
    ld a,c
    or a
    jr z,.e
    push bc
.f:
    ld (hl),b
    inc hl
    dec c
    jr nz,.f
    pop bc
.e:
    jp lstr_result

;; lc_code0: DE = a character -> A = its code, not folded
lc_code0:
    xor a
    ld (LS_MODE),a
    jp lc_code
