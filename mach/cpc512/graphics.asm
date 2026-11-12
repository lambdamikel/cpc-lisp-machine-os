;; CPC Lisp -- SYMBOL and FLOOD-FILL on the CPC, in library part 0 (the end
;; of lib/gfx.asm includes this). FLOOD-FILL works on the screen bytes
;; through the firmware's screen pack; another machine can do it with
;; GFX_TEST and GFX_LINE, or leave it out.

;; ---------------------------------------------------------------------------
;; USER-DEFINED CHARACTERS


;; (symbol code row...): character code, 240-255, drawn from up to eight
;; rows, the top first, each a byte (#b00111100...): BASIC's SYMBOL, with
;; its SYMBOL AFTER 240. The table is the 128 bytes the core keeps under the
;; top of memory (V_UDG), set up the first time.
;@ SYMBOL 1 9 lf_symbol
lf_symbol:
    NEXTARG
    call lint_de
    ld a,d
    or a
    jr nz,.bad
    ld a,e
    cp 240
    jr c,.bad
    push de                     ; the code
    push hl
    push bc
    call TXT_GET_M_TABLE        ; ours already?
    jr nc,.set
    ld de,(V_UDG)
    or a
    sbc hl,de
    jr z,.have
.set:
    ld de,240
    ld hl,(V_UDG)
    call TXT_SET_M_TABLE        ; (it copies the present shapes in)
.have:
    pop bc
    pop hl
    ld de,TOKBUF                ; the rows, missing ones blank
    push de
    ld a,8
.z:
    ex de,hl
    ld (hl),0
    inc hl
    ex de,hl
    dec a
    jr nz,.z
    pop de
    dec b
    jr z,.rows
.r:
    push de
    NEXTARG
    call lint_de
    ld a,e
    pop de
    ld (de),a
    inc de
    djnz .r
.rows:
    pop de
    ld a,e
    ld hl,TOKBUF
    call TXT_SET_MATRIX
    jp lnil
.bad:
    ld hl,m_index
    ld de,UNBOUND
    CORE error

;; ---------------------------------------------------------------------------
;; FLOOD FILL


FF_TARGET   equ TOKBUF+200      ; the colour being filled over
FF_DX       equ TOKBUF+202      ; a pixel's width in x (1, 2 or 4)
FF_SP       equ TOKBUF+204      ; the seed stack: next free,
FF_BASE     equ TOKBUF+206      ;   bottom,
FF_LIMIT    equ TOKBUF+208      ;   full
FF_XL       equ TOKBUF+210      ; the span: left,
FF_XR       equ TOKBUF+212      ;   right,
FF_Y        equ TOKBUF+214      ;   its y
FF_IN       equ TOKBUF+216      ; scanning: in a run of the target colour
FF_PEN      equ TOKBUF+217
FF_BITS     equ TOKBUF+218      ; the target colour, encoded in every pixel
FF_SHIFT    equ TOKBUF+219      ; x to a pixel: shifted right this much
FF_OX       equ TOKBUF+220      ; the graphics origin
FF_OY       equ TOKBUF+222
FF_XMIN     equ TOKBUF+224      ; the screen's edges, in user coordinates
FF_XMAX     equ TOKBUF+226
FF_YMIN     equ TOKBUF+228
FF_YMAX     equ TOKBUF+230
FC_ADDR     equ TOKBUF+232      ; the cursor along a row: its byte,
FC_MASK     equ TOKBUF+234      ;   its pixel's bits
FF_M0       equ TOKBUF+235      ; the leftmost pixel's bits in a byte,
FF_ML       equ TOKBUF+236      ;   the rightmost's

;; (flood-fill x y [pen]): the area around (x, y) that is the colour of
;; (x, y), to where any other colour starts, painted with pen (the graphics
;; pen) -- a paint bucket. (BASIC 1.1's FILL, the 664/6128 firmware's, stops
;; only at the pen's colour; this works the same on every CPC.) A pixel row
;; at a time, reading the screen through RAM LAM: a whole screen in mode 1
;; takes about half a minute.
;@ FLOOD-FILL 2 3 lf_flood_fill
lf_flood_fill:
    ld c,2
    call gx_ints                ; x y
    ld a,b
    ld c,3
    call gx_pen
    pop hl
    pop de
    push de
    push hl
    call gx_move                ; the cursor there
    call GRA_GET_PEN
    ld (FF_PEN),a
    call fl_lend                ; DE = 2 KB for a stack
    ld (FF_BASE),de
    ld (FF_SP),de
    ld hl,2048-4
    add hl,de
    ld (FF_LIMIT),hl
    call SCR_GET_MODE           ; a pixel: mode 0 4 wide, 1 2, 2 1
    ld hl,4
    ld c,2
    or a
    jr z,.w
    ld l,2
    dec c
    dec a
    jr z,.w
    ld l,1
    dec c
.w:
    ld (FF_DX),hl
    ld a,c
    ld (FF_SHIFT),a
    ld hl,#0180                 ; a pixel's bits: shift 0, mode 2 &80..&01,
    or a
    jr z,.m
    ld hl,#1188                 ;   shift 1, mode 1 &88..&11,
    dec a
    jr z,.m
    ld hl,#55AA                 ;   shift 2, mode 0 &AA..&55
.m:
    ld (FF_M0),hl               ; (FF_ML after it)
    call GRA_GET_ORIGIN         ; DE, HL: added to x and y
    ld (FF_OX),de
    ld (FF_OY),hl
    ld bc,0                     ; the edges, in user coordinates
    call .edge
    ld (FF_XMIN),hl
    ld bc,639
    call .edge
    ld (FF_XMAX),hl
    ex de,hl
    ld de,(FF_OY)
    ld bc,0
    call .edge
    ld (FF_YMIN),hl
    ld bc,399
    call .edge
    ld (FF_YMAX),hl
    jr .edged
.edge:                          ; HL = BC - DE
    ld l,c
    ld h,b
    or a
    sbc hl,de
    ret
.edged:
    pop hl                      ; y
    pop de                      ; x
    push de
    push hl
    call gx_test
    ld (FF_TARGET),a
    push af
    call SCR_INK_ENCODE         ; that colour in every pixel of a byte
    ld (FF_BITS),a
    pop af
    ld b,a
    ld a,(FF_PEN)
    cp b
    pop hl
    pop de
    jr z,.done                  ; already that colour
    call ff_push
.next:
    ld hl,(FF_SP)
    ld de,(FF_BASE)
    or a
    sbc hl,de
    jr z,.done
    call ff_pop                 ; DE = x, HL = y
    call ff_span
    jr .next
.done:
    call fe_release
    jp lnil

;; gx_test: DE = x, HL = y -> A = the pen there. IX kept.
gx_test:
    push ix
    call GFX_TEST
    pop ix
    ret

;; ff_push: DE = x, HL = y -> a seed (if there is room)
ff_push:
    push hl
    ld hl,(FF_SP)
    ld bc,(FF_LIMIT)
    or a
    sbc hl,bc
    add hl,bc
    pop bc
    ret nc                      ; full: this part is left
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld (hl),c
    inc hl
    ld (hl),b
    inc hl
    ld (FF_SP),hl
    ret

;; ff_pop -> DE = x, HL = y
ff_pop:
    ld hl,(FF_SP)
    dec hl
    ld b,(hl)
    dec hl
    ld c,(hl)
    dec hl
    ld d,(hl)
    dec hl
    ld e,(hl)
    ld (FF_SP),hl
    ld l,c
    ld h,b
    ret

;; ff_is: DE = x, HL = y -> Z if it is on the screen and the target colour.
;; DE, HL kept. Fast: the screen byte itself, through SCR DOT POSITION and
;; RAM LAM (from a ROM, &C000 up reads the ROM), against FF_BITS.
ff_is:
    push hl
    push de
    ld bc,(FF_OX)               ; to standard coordinates
    ex de,hl
    add hl,bc
    ex de,hl
    ld bc,(FF_OY)
    add hl,bc
    bit 7,d
    jr nz,.no
    bit 7,h
    jr nz,.no
    push hl
    ld bc,640
    ex de,hl
    or a
    sbc hl,bc
    add hl,bc
    ex de,hl
    pop hl
    jr nc,.no
    ld bc,400
    or a
    sbc hl,bc
    add hl,bc
    jr nc,.no
    srl h                       ; to pixels: y / 2, x / the pixel's width
    rr l
    ld a,(FF_SHIFT)
    or a
    jr z,.px
.sh:
    srl d
    rr e
    dec a
    jr nz,.sh
.px:
    call SCR_DOT_POSITION       ; HL = its byte, C = its mask
    call RS_RAMRD               ; A = (HL), the screen's RAM
    and c
    ld b,a
    ld a,(FF_BITS)
    and c
    cp b
    pop de
    pop hl
    ret
.no:
    pop de
    pop hl
    or 1
    ret

;; fc_at: DE = x, HL = y, on the screen -> the cursor on that pixel
fc_at:
    push hl
    push de
    ld bc,(FF_OX)
    ex de,hl
    add hl,bc
    ex de,hl
    ld bc,(FF_OY)
    add hl,bc
    srl h
    rr l
    ld a,(FF_SHIFT)
    or a
    jr z,.px
.sh:
    srl d
    rr e
    dec a
    jr nz,.sh
.px:
    call SCR_DOT_POSITION
    ld (FC_ADDR),hl
    ld a,c
    ld (FC_MASK),a
    pop de
    pop hl
    ret

;; fc_test -> Z if the cursor's pixel is the target colour. DE, HL kept.
fc_test:
    push hl
    ld hl,(FC_ADDR)
    call RS_RAMRD               ; the screen's RAM
    ld b,a
    ld a,(FC_MASK)
    ld c,a
    and b
    ld b,a
    ld a,(FF_BITS)
    and c
    cp b
    pop hl
    ret

;; fc_right, fc_left: the cursor a pixel on. DE kept.
fc_right:
    ld a,(FC_MASK)
    ld hl,FF_ML
    cp (hl)
    jr z,.byte
    srl a
    ld (FC_MASK),a
    ret
.byte:
    ld a,(FF_M0)
    ld (FC_MASK),a
    ld hl,(FC_ADDR)
    push de
    call SCR_NEXT_BYTE
    pop de
    ld (FC_ADDR),hl
    ret
fc_left:
    ld a,(FC_MASK)
    ld hl,FF_M0
    cp (hl)
    jr z,.byte
    sla a
    ld (FC_MASK),a
    ret
.byte:
    ld a,(FF_ML)
    ld (FC_MASK),a
    ld hl,(FC_ADDR)
    push de
    call SCR_PREV_BYTE
    pop de
    ld (FC_ADDR),hl
    ret

;; ff_span: DE = x, HL = y, a seed -> its row's run painted, and seeds for
;; the runs above and below it
ff_span:
    call ff_is
    ret nz
    ld (FF_Y),hl
    ld (FF_XL),de
    ld (FF_XR),de
    call fc_at
    ld hl,(FC_ADDR)             ; the seed's place, for the right
    push hl
    ld a,(FC_MASK)
    push af
.left:
    ld hl,(FF_XL)               ; x - dx, if on the screen
    ld bc,(FF_DX)
    or a
    sbc hl,bc
    push hl
    ld bc,(FF_XMIN)
    or a
    sbc hl,bc
    pop hl
    jp m,.lend
    push hl
    call fc_left
    call fc_test
    pop hl
    jr nz,.lend
    ld (FF_XL),hl
    jr .left
.lend:
    pop af
    ld (FC_MASK),a
    pop hl
    ld (FC_ADDR),hl
.right:
    ld hl,(FF_XR)               ; x + dx, if on the screen
    ld bc,(FF_DX)
    add hl,bc
    push hl
    ld bc,(FF_XMAX)
    scf
    sbc hl,bc                   ; x' - xmax - 1: negative if x' <= xmax
    pop hl
    jp p,.rend
    push hl
    call fc_right
    call fc_test
    pop hl
    jr nz,.rend
    ld (FF_XR),hl
    jr .right
.rend:
    ld de,(FF_XL)               ; paint it
    ld hl,(FF_Y)
    call gx_move
    ld de,(FF_XR)
    ld hl,(FF_Y)
    call gx_line
    ld hl,(FF_Y)                ; the rows above and below
    inc hl
    inc hl
    call ff_row
    ld hl,(FF_Y)
    dec hl
    dec hl
;; ff_row: HL = a y -> a seed at the start of each run of the target
;; colour in it, from FF_XL to FF_XR
ff_row:
    push hl                     ; on the screen?
    ld bc,(FF_YMIN)
    or a
    sbc hl,bc
    pop hl
    ret m
    push hl
    ld bc,(FF_YMAX)
    scf
    sbc hl,bc
    pop hl
    ret p
    xor a
    ld (FF_IN),a
    ld de,(FF_XL)
    call fc_at
.x:
    call fc_test
    jr nz,.out
    ld a,(FF_IN)
    or a
    jr nz,.step
    inc a
    ld (FF_IN),a
    push hl
    push de
    call ff_push
    pop de
    pop hl
    jr .step
.out:
    xor a
    ld (FF_IN),a
.step:
    push hl
    ld hl,(FF_DX)               ; x + dx, up to the right end
    add hl,de
    ex de,hl
    ld hl,(FF_XR)
    or a
    sbc hl,de
    pop hl
    ret m
    push hl
    call fc_right
    pop hl
    jr .x
