;; CPC Lisp -- constants: firmware vectors, the memory map, the object tags.
;;
;; FIRMWARE: only through the jumpblock, which is the same on the 464, 664 and
;; 6128 from &BB00 to &BD37. Past that the machines differ: the 664/6128 add
;; twelve entries at &BD3A, which moves EDIT (the BASIC line editor, in the
;; firmware ROM) from &BD3A to &BD5E and the maths package from &BD3D to
;; &BD61 -- with a different set of entries, 49 on the 464 against 32. Code
;; that calls past &BD37 looks the address up at boot (V_EDITV).

KM_WAIT_CHAR      equ #BB06
KM_READ_CHAR      equ #BB09
KM_CHAR_RETURN    equ #BB0C
KM_TEST_KEY       equ #BB1E
TXT_OUTPUT        equ #BB5A
TXT_WR_CHAR       equ #BB5D
TXT_CLEAR_WINDOW  equ #BB6C
TXT_SET_CURSOR    equ #BB75
TXT_GET_CURSOR    equ #BB78
TXT_SET_PEN       equ #BB90
TXT_SET_PAPER     equ #BB96
SCR_SET_INK       equ #BC32
SCR_SET_BORDER    equ #BC38
TXT_CUR_ON        equ #BB81
TXT_CUR_OFF       equ #BB84
SCR_SET_MODE      equ #BC0E
KL_ROM_WALK       equ #BCCB
CAS_IN_ABANDON    equ #BC7D         ; the file vectors: a disc ROM takes them
CAS_IN_CHAR       equ #BC80         ; over, so they work with AMSDOS, Parados
CAS_OUT_ABANDON   equ #BC92         ; or a tape
CAS_OUT_CHAR      equ #BC95
KL_ROM_SELECT     equ #B90F         ; C = ROM -> C = the one before. AF, B corrupt
KL_CURR_SELECTION equ #B912         ; -> A = the ROM selected now
MC_WAIT_FLYBACK   equ #BD19
EDIT_464          equ #BD3A
EDIT_6128         equ #BD5E
FIRM_464_PROBE    equ #BD3D         ; &EF (FIRM JUMP) on a 464, &CF on a 664/6128

KEY_ESC           equ 66            ; KM TEST KEY number

;; ---------------------------------------------------------------------------
;; MEMORY MAP
;;
;;   &0040-&04FF  low system area: mark stack, symbol hash table, LIBDEFS,
;;                FNBOUND.
;;                The firmware sees its ROM here, so nothing the firmware reads goes here.
;;                Words below &0500 are also the immediates (characters,
;;                markers, headers), which is why no object lives here.
;;   &0500-&14FF  symbols: 512 slots of 8 bytes
;;   &1500-       cells: 4 bytes each, conses and typed cells
;;   then         the mark bitmap, block space (strings), the machine stack,
;;                sized at boot from what the ROM walk left (V_MEMTOP)
;;   &AC00-&B0FF  fixed variables and buffers. The firmware enters ROM 0 with
;;                HL=&ABFF and BC=&B0FF on every model: this is the area BASIC
;;                keeps for itself, and it is ours now.

MARKSTK           equ #0040         ; 256 words
MARKSTK_END       equ #0240
OBARRAY           equ #0240         ; NBUCKETS words, each a list of symbols
NBUCKETS          equ 64
OBARRAY_END       equ OBARRAY+2*NBUCKETS
LIBDEFS           equ OBARRAY_END   ; NSYMS bits: the symbol's definition came
LIBDEFS_END       equ LIBDEFS+NSYMS/8 ;   from library text (SAVE leaves it out)

FNBOUND           equ #0300         ; NSYMS bytes: non-zero if flet or labels
                                    ;   ever bound the symbol (ev_cons)
SYM_LO            equ #0500
NSYMS             equ 512
SYM_HI            equ SYM_LO+8*NSYMS   ; #1500
                  assert LIBDEFS_END <= FNBOUND
                  assert FNBOUND+NSYMS <= SYM_LO
                  assert (FNBOUND and #FF) == 0
CELL_LO           equ SYM_HI

STACK_SIZE        equ 4096
STACK_MARGIN      equ 256           ; eval refuses to go deeper than this

LINEBUF           equ #AC00         ; 256: the EDIT buffer
TOKBUF            equ #AD00         ; 256: the reader's token
VARS              equ #AE00         ; the variables, below
LIBSCR            equ #AF00         ; 256: scratch for the library ROM
HISTBUF           equ #B000         ; 128: the line editor's history
TRAMP             equ #B080         ; 58: the cross-ROM trampoline, copied at boot
RDISK             equ #B0C0         ; 64: the RAM disc's state (lib/ramdisc.asm)
VARS_END          equ LIBSCR
NLIBS             equ 4             ; library ROMs: parts 0-3 (src/xrom.asm)

;; Variables. The first block holds Lisp values and is a GC root, scanned
;; word by word; everything after ROOTS_END is not.
                  nocode
                  org VARS
V_ENV             defs 2            ; the lexical environment, an alist
V_SPECS           defs 2            ; special bindings: list of (sym . old value)
V_T1              defs 2            ; temporaries natives can park values in
V_T2              defs 2
V_T3              defs 2
V_T4              defs 2
V_SRCOBJ          defs 2            ; reader: the string it reads from (source 2)
V_EDITSTR         defs 2            ; the function editor's last text, a string
V_MV1             defs 2            ; multiple values: the first,
V_MV2             defs 2            ;   the second,
V_MVL             defs 2            ;   the rest, a list (V_MVN says how many)
ROOTS_END
V_BLOCKS          defs 2            ; innermost block/catch frame (a stack address)
V_FREE            defs 2            ; free cell list
V_SYMFREE         defs 2            ; free symbol slots
V_CELLHI          defs 2            ; end of the cell region (a multiple of 32)
V_BITMAP          defs 2            ; mark bitmap: one bit per 4 bytes from SYM_LO
V_BMSIZE          defs 2            ;   and its size in bytes
V_BLKLO           defs 2            ; block space: start,
V_BLKTOP          defs 2            ;   allocation pointer,
V_BLKHI           defs 2            ;   end
V_STKTOP          defs 2            ; machine stack: top,
V_STKLIM          defs 2            ;   lowest SP eval accepts
V_MEMTOP          defs 2            ; last usable byte, from the ROM walk
V_TOPSP           defs 2            ; SP of the REPL, for errors
V_EDITV           defs 2            ; EDIT vector for this machine
V_INPTR           defs 2            ; reader: next character in LINEBUF, 0 = none
V_PROMPT          defs 2            ; reader: prompt for the next line
V_PEEK            defs 1            ; reader: pushed-back character, 0 = none
V_BRK             defs 1            ; eval: polls ESC when this wraps
V_ESC             defs 1            ; printer: 1 = readably (prin1), 0 = princ
V_DEPTH           defs 1            ; reader: list nesting
V_MSOVF           defs 1            ; GC: the mark stack overflowed
V_MSP             defs 2            ; GC: mark stack pointer
V_GCS             defs 2            ; GC: collections so far
V_NFREE           defs 2            ; GC: cells free after the last one
V_GENSYM          defs 2            ; gensym counter
V_RAND            defs 2            ; random state
V_COREROM         defs 1            ; this ROM's number
V_LIBS            defs 5*NLIBS      ; library ROMs, by part: [ROM, 0 = none]
                                    ;   [symbol hash table][dispatcher]
V_PEEKROM         defs 1            ; the ROM LIBPEEK reads
V_SRCROM          defs 1            ; reader: the ROM of the library text
V_EDROM           defs 1            ; the line editor's ROM,
V_NUMROM          defs 1            ;   the number routines'
V_LIBFN           defs 2            ; the library function being called
V_RCBC            defs 2            ; trampoline: BC in passing
V_INSRC           defs 1            ; reader: 0 the keyboard, 1 library text,
                                    ;   2 a string, 3 the file open for input
V_FILES           defs 1            ; files open: bit 0 input, bit 1 output
V_LIBEDIT         defs 2            ; a library's line editor, 0 = none
V_EDDEPTH         defs 1            ; line editor: open parens it remembers
V_EDSTR           defs 1            ; line editor: the last line ended in a string
V_SRCPTR          defs 2            ; reader: next character of library text,
                                    ;   or the index into V_SRCOBJ
V_OUTMODE         defs 1            ; printer: 0 the screen, 1 memory, 2 count
                                    ;   only, 3 the file open for output
V_OUTPTR          defs 2            ;   memory: where the next character goes
V_OUTEND          defs 2            ;   and where it must stop
V_OUTCNT          defs 2            ;   characters printed (memory and count)
V_OUTCOL          defs 1            ;   the column, from 0, kept in every mode
V_BLKSAVE         defs 2            ; V_BLKHI while space is lent out, else 0
V_LIBDEF          defs 1            ; 1 while library text is evaluated
V_LIBNUM          defs 2            ; a library's number routines, 0 = none
V_NUMARGS         defs 2            ; numeric subr: &arg 0,
V_NUMBC           defs 2            ;   B = how many, C,
V_NUMOP           defs 2            ;   its NUM_ label,
V_NUMSP           defs 2            ;   SP for its return (num_ovf)
V_FA              defs 5            ; firmware reals: the library's accumulators
V_FB              defs 5
V_FC              defs 5
V_FD              defs 5
V_FBUF            defs 12           ; digits, printing a float
V_FOP             defs 2            ; the operation a fold applies
V_FMA             defs 1            ; A, while fmcall finds the routine
V_MVN             defs 1            ; multiple values: 0 none (one value), else
                                    ;   how many plus one, for V_MV1 (each call
                                    ;   clears it; VALUES, FLOOR... set it)
V_S1              defs 2            ; scratch for routines that call nothing
V_S2              defs 2
V_S3              defs 2
V_END
                  code
    assert V_END <= VARS_END

;; ---------------------------------------------------------------------------
;; OBJECTS. A Lisp value is one 16-bit word.
;;
;;   ...1         fixnum: the value times 2, plus 1 (15 bits, -16384..16383)
;;   &0000        NIL
;;   ...00        a cons: the address of a 4-byte cell [car][cdr]
;;   ...10        anything else, by address:
;;     &0002-&03FE  character c is c*4+2
;;     &04xx        markers (UNBOUND, EOF) and cell headers -- never objects
;;     &0500-&14FF  symbol: slot address + 2
;;     &1500-       typed cell: cell address + 2. The cell is [header][data]
;;     &C000-       a ROM object: [header][...] in this ROM

UNBOUND           equ #0402
EOFMARK           equ #0406
DOTMARK           equ #040A         ; the reader's "." in a list
CLOSEMARK         equ #040E         ; the reader's ")"

;; Headers: the car of a typed cell, or the first word of a ROM object. Low
;; byte &80-&BF: the data word is a Lisp value the GC follows. &C0-&FB: the
;; data is raw (a pointer into block space or ROM). &FE marks a free cell.
;; Like every non-fixnum they end in binary 10: the fixnums 576..639 are
;; &0481..&04FF, and only the low bit tells a cons holding one from a header.
HDR_CLOSURE       equ #0482         ; data: (code . env), code = (lambda-list . body)
HDR_MACRO         equ #0486         ; data: a closure
HDR_STRING        equ #04C2         ; data: pointer to [len lo][len hi][chars]
HDR_VECTOR        equ #04C6         ; data: pointer to [len][elements, a word each]
HDR_SUBR          equ #04CA         ; ROM: [hdr][code][min][max]
HDR_FSUBR         equ #04CE         ; ROM: [hdr][code] -- a special form
HDR_NOFN          equ #04D2         ; ROM: a symbol entry with no function
HDR_LSUBR         equ #04D6         ; data: its entry in the library ROM
HDR_AUTOLOAD      equ #04DA         ; data: its definition's text in the library ROM
HDR_FLOAT         equ #04DE         ; data: pointer to [5][0][a firmware real]
FREEMARK          equ #04FE
HDR_RAW_L         equ #C0

;; Symbol slot: [plist|flags][name][value][function]; the pointer is slot+2,
;; so the name -- like a string's data -- is the word the pointer points at.
SY_PLIST          equ -2            ; a list, so its low two bits are free:
SY_NAME           equ 0             ;   bit 0 special (dynamic), bit 1 constant
SY_VALUE          equ 2
SY_FUNC           equ 4
SF_SPECIAL        equ 1
SF_CONST          equ 2

NIL               equ 0
NILSLOT           equ SYM_LO+2      ; symbol 0 holds NIL's name, plist, function

;; Block in block space: [owner][len lo][len hi][chars..][pad to even]. The
;; owner is the address of the word that points at the length (a string's
;; data word or a symbol's name), so compaction can find and move it.
