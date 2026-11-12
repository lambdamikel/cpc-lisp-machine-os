# CPC Lisp 0.95 -- how it is made

*A Lisp machine for the Amstrad CPC*

CPC Lisp is a Common Lisp dialect for a 4 MHz Z80 with 64 KB of RAM, in
six 16 KB ROMs. This document explains how it works: the ROMs and how
they talk to each other, the memory and the objects in it, the garbage
collector and the evaluator, the library, and the bytecode machine and the
compiler that runs on it -- the compiler that is compiled by itself at
build time. The source is the final word; each part of it starts with a
header that says what it does, and this document says where to look.
[The internals](internals.md) go deeper: the `%` names, closures, tail
calls, the speed work, and the bootstrap step by step.

## The constraints

* **Every CPC.** The 464, 664 and 6128 differ in their firmware: past
  &BD37 the jumpblocks are not the same, the maths package has other
  entries, EDIT moved. Everything goes through the firmware's vectors,
  and the few that differ are looked up at boot (`mach/cpc/mmacros.asm`:
  a FIRM JUMP at &BD3D means a 464).
* **One upper ROM at a time.** A ROM is seen at &C000-&FFFF, on top of the
  screen memory, and only one is selected. Code in one ROM cannot call
  code in another, nor read its bytes, without switching -- and the
  switching must go through the firmware (`KL ROM SELECT`), which has to
  know what is selected for its own interrupt-time work.
* **Little RAM.** What is left after the firmware, the disc ROM and the
  screen is about 40 KB: everything -- cells, symbols, strings, the stack
  -- has to fit there.
* **No BASIC.** The core replaces BASIC (ROM 0, ROMDIS), so nothing of
  BASIC's may be used; the floats come from the firmware's maths package,
  which is in the firmware ROM.

## The machine layer

Everything that depends on the CPC is in `mach/cpc/`: the firmware's
entry points, the memory map, start-up, the maths call, the function
editor's fast screen, the RAM disc, the LambdaSpeak card, and the Lisp
functions only a CPC has (`ink`, `envelope`, `symbol`, `flood-fill`,
`say`...). The rest, `src/` and `lib/`, reaches the machine only through
about ninety interface names -- `CON_PUTC`, `KEY_READ`, `GFX_LINE`,
`FILE_GETC`, `FP_ADD`, `SYS_BANK`... -- each bound on the CPC to the
firmware routine with the same contract, so it costs nothing.

A port to another Z80 machine is another directory beside it, built with
`MACH=<machine> tools/build.sh`. [`mach/README.md`](../mach/README.md) is
the interface, and what a machine must offer: six 16 KB banks of code at
&C000, and some 40 KB of RAM below that is always there.

**The first port is the TRS-80 Model I and III with X-MEM/80**
(`mach/trs80/`, [its README](../mach/trs80/README.md)). X-MEM/80 maps
any of 32 pages of 16 KB at &C000 with one `OUT`, so the six images run
there unchanged, loaded from LDOS discs by a small `LISP/CMD`. The
TRS-80 has no firmware with the CPC's contracts, so its routines --
console, keys, graphics, sound, files, floats -- are a seventh page, the
*machine page*; each interface name is an entry of a jumpblock in RAM
that is always there, which maps the machine page in, calls the routine
and maps the caller's page back. Floats go through the Level II ROM: the
CPC's five-byte reals turned out to be Microsoft's binary form with a
longer mantissa. With half the CPC's RAM for the heap, block space's
share and the file buffers' size became the machine's choice too
(`MACH_BLOCKS`, `FILE_BUFSIZE`).

## The ROMs

| ROM | source | |
|---|---|---|
| core | `src/` | a foreground ROM: the objects, the GC, the reader and printer, the evaluator and special forms, the builtin functions |
| library 1 | `lib/lib.asm` | part 0: screen, graphics, sound, keys, strings, streams, editors, files |
| library 2 | `lib/lib2.asm` | part 1: floats, `format`, sequences, structures, hash tables, the card |
| library 3 | `lib/lib3.asm` | part 2: Lisp text (`lib/lisp.lsp`) |
| demo | `lib/demo.asm` | part 3: `loop`, string streams, demos -- natives and Lisp text |
| VM | `lib/vm.asm` | the bytecode machine and the compiled compiler |

**The core** is entered by the firmware at power-up (at ROM 0) or by
`|LISP`. Like BASIC, it calls `KL ROM WALK` first -- without that no
background ROM, not even the disc, is initialised -- then lays out memory
and looks for the rest.

**BASIC and back.** On the LambdaSpeak card the core is a slot that
answers as ROM 0, and asserts ROMDIS: BASIC's ROM is switched off.
`(basic [slot])` sends the card `&D0 slot 255` -- its own `|ROMNUM`,
the slot made silent -- and resets: the CPC comes up in BASIC.
`|BOOTLISP[,slot]`, an RSX of library ROM 2 (a background ROM, still
there in BASIC), sends `&D0 slot 0` and resets into Lisp. Both run their
last bytes from code copied to &4000: once the slot changes, what was at
&C000 is another ROM. (`mach/cpc/card.asm`; CPC only.)

**Finding the library.** Each library ROM has a header at &C010:
`CPCLISPLIB`, a build number, its symbol table, its boot forms, its
dispatcher, and which *part* it is. The core searches ROMs 1-15 for the
signature with its own build number: all the ROMs come from one build and
call each other by address. A part from another build is left out.

**Crossing.** Calls between ROMs go through a trampoline in RAM
(`src/xrom.asm`, copied to &B080 at boot): `ROMCALL` selects the other
ROM with `KL ROM SELECT`, calls the address, and selects the first again,
passing HL, DE and BC through. The library calls the core with the `CORE`
macro; the core calls a library function through `LIBCALL`, which finds
its part's dispatcher. `ROMPEEK` reads a byte of another ROM. Everything
handed across must be in RAM: a library sees itself, not the core, at
&C000.

**Names.** A library name costs nothing until it is needed. Each part
has a hash table of its names in its ROM, bucketed like the core's symbol
table; when the reader interns a new symbol, `lib_find` looks it up in
each part, and a hit gives the symbol its function:

* an **LSUBR** (kind 1), a native in the library: a typed cell whose data
  is the address of its table entry, with the part in the top two bits
  (ROM addresses always start with binary 11, so those bits are free);
* an **AUTOLOAD** (kind 2), a function written in Lisp: the address of
  its text. The first call reads the text from ROM and evaluates it --
  a `defun` -- and calls what it defined. When the cells run out
  (`cons` finds none free after a GC), `ln_short` (`lib/short.asm`,
  part 1) drops such functions again: it hides each from a second GC
  (the pointer made odd, a fixnum to the GC) and gives the ones that GC
  freed their autoload stub back. `(load name :lazy t)` (`lib/lazy.lsp`)
  gives a program's defuns the same life: a stub per function, its
  file and position (the reader counts characters in V_FPOS) in its
  plist, the definition read on the first call and marked the
  library's (`%libdef`), so the dropper takes it back to the stub;
* a **VM function** (kind 3), the VM ROM's: a compiled function (below)
  holding its number.

Two bits for the part are why there are at most four parts. The VM ROM is
not a part: it has no names of its own (its names are kind 3 entries in
part 1's table), and the core reaches it through a hook, `VMCALL`.
`tools/mklib.py` builds every table from the parts' sources: a native is
declared by a `;@ NAME MIN MAX label` line, Lisp text by `;@lisp
file.lsp` (each `defun` an autoload entry, other forms boot forms run at
start-up).

A part cannot call another part's code -- only the core's. What they
share is in `lib/common.asm`, a copy in each.

## Memory

    &0040  mark stack, symbol hash table (64 buckets), LIBDEFS, FNBOUND
    &0500  symbols: 512 slots of 8 bytes
    &1500  cells: 4 bytes each, conses and typed cells
           the mark bitmap
           block space: strings, vectors, floats, symbol names
           the machine stack, 4 KB (the firmware's is far too small)
    &AC00  the Lisp's own: the line buffer, the reader's token buffer,
           the variables, scratch for the library, the editor's history,
           the trampoline, the RAM disc's state
    &B100  the firmware

The layout is made at boot from what the ROM walk left: the stack at the
top, block space below it (11/64 of the rest: room for two 2 KB file
buffers), then the cells and their bitmap. A 464 has about 6660 cells,
5.8 KB of block space and 512 symbols (some 160 builtin); a disc ROM
takes about a kilobyte of that (some 250 cells).

## Objects

A Lisp value is a 16-bit word; its low bits say what it is:

| | |
|---|---|
| `...1` | a fixnum: the value times 2 plus 1, so -16384..16383 |
| `&0000` | NIL |
| `...00` | a cons: the address of a cell, [car][cdr] |
| `...10` below &0400 | a character: code × 4 + 2 |
| `&04xx` | markers (UNBOUND, EOF) and cell headers -- never values |
| `&0500-&14FF` | a symbol: its slot + 2 |
| `&1500-` | a typed cell: the cell + 2 |
| `&C000-` | a ROM object: a builtin's entry in the core's symbol table |

**A symbol** is an 8-byte slot, [plist and flags][name][value][function];
its pointer addresses the name, so a symbol's name and a string's
characters are found the same way. The two low bits of the plist word are
the flags *special* and *constant*. The builtin symbols are a table in the
core ROM (`src/symtab.asm`), copied into the first slots at boot; each
entry is also the builtin's function object -- a SUBR (a native with its
argument counts) or an FSUBR (a special form).

**A typed cell** is [header][data]. The header tells the type: a closure
(data: (code . environment)), a macro, a compiled function, a string, a
vector, a structure, a float, a library function. A header's low byte
says whether the data is a Lisp value the GC follows (&80-&BF) or raw (a
pointer into block space, or a ROM address).

**Block space** holds what is not a word: a string's characters, a
vector's elements, a float's five bytes, a symbol's name. A block is
[owner][length][bytes]; the owner is the address of the word that points
at the length, so when the GC compacts block space it can move a block
and put the new address in its owner.

## The garbage collector

Mark and sweep (`src/mem.asm`), with a bitmap of a bit per 4 bytes. The
roots are the symbol table's buckets, a block of root variables, and the
machine stack -- scanned **conservatively**: any word there that looks
like a pointer to a cell keeps the cell alive. That is what makes native
code simple: a Lisp value may sit on the stack or in a register pair
across an allocation (`cons` pushes its arguments). The one rule is that
no raw pointer *into block space* may be held across an allocation,
because blocks move.

Marking is iterative: a cdr is followed in a loop, a car pushed on a
256-word mark stack. If the stack overflows, the push is dropped (the
parent is marked, the child not) and, once it has drained, the heap is
scanned for marked objects with unmarked children -- so any depth of
nesting costs time, never correctness or stack. Then block space is
compacted, unreferenced symbols (uninterned ones) are swept, and free
cells go on the free list. `V_GCS` counts the collections; the VM uses it
to know whether code has moved.

## The evaluator

`eval` (`src/eval.asm`) is a loop with proper tail calls: a form in tail
position -- the last of a body, a branch of `if`, a macro's expansion, a
closure's body -- is not called but jumped to, so tail recursion runs in
constant stack. The stack is checked: too deep a recursion is an error.

**A call** evaluates the function, pushes it, then each argument's value,
left to right, under an *eval frame* (the caller's environment); constants
and variables skip `eval` altogether. `apply_core` takes it from there by
the function's type:

* a builtin with a fixed number of arguments up to three gets them in HL,
  DE and BC; any other gets the address of the first and a count;
* a closure whose lambda list is plain variables binds them straight from
  the stack; anything else (`&optional`, `&key`, destructuring...) goes
  through `bind`;
* a library function goes to its part (`LIBCALL`), a compiled one to the
  VM ROM (`VMCALL`).

The lexical **environment** is an alist, `(symbol . value)` for a
variable and `((symbol) . function)` for `flet` and `labels`. **Special
variables** are shallow-bound: the symbol's value cell holds the current
value, and `V_SPECS` a list of (symbol . old value) to put back.

**Special forms** are FSUBRs: they get their unevaluated arguments and the
eval frame, and end by returning a value or jumping back into the loop
with a form in tail position. **Macros** are expanded the first time a
call is evaluated, and the call is rewritten in place to
`(%EXPANDED (macro . expansion) op . args)`, so the expansion is reused --
unless the macro has been redefined since. The printers show the call as
it was written.

**Leaving early.** `block`, `catch`, `unwind-protect` and
`%catch-errors` push a frame on the machine stack -- [V_SPECS][env][tag]
[kind][the frame before] -- linked from `V_BLOCKS`. `return-from` and
`throw` find their frame, run the cleanups of the unwind-protect frames
on the way, restore the special variables and the stack, and go on after
it. An error looks for a `%catch-errors` frame (which `ignore-errors` and
`handler-case` are made of); without one it goes back to the REPL, which
runs the cleanups still on the stack first. ESC is polled every so often
(a counter, and the key buffer, so a tap during a GC is not lost) and
breaks the same way.

**Multiple values**: `values` leaves the extra ones in variables, with
their count; every call clears the count as it starts, and
`multiple-value-list` takes them only if the value it got is still the
first of them.

In detail: [closures](internals.md#in-the-interpreter),
[tail calls](internals.md#tail-calls),
[what made it faster](internals.md#the-interpreter).

## Numbers

Fixnums are the core's: the arithmetic and comparisons have a fast path
for two fixnums. Anything else -- a float, or an overflow -- is handed to
library 2 (`lib/float.asm`), which keeps floats as the firmware's five-
byte reals in block space and calls the maths package. The reader hands
it any number that is not a fixnum (a float, or an integer too big). Where the maths package is depends on
the firmware: 464 or 664/6128.

## Reading and printing

The reader (`src/read.asm`) reads from one of four sources: the keyboard
a line at a time (the library's line editor, or the firmware's EDIT
without it), Lisp text in a library ROM (autoloads and boot forms), a
string (the function editor, string streams), or the file open for input.
`putc` (`src/print.asm`) writes to the screen, to memory (for `format
nil`, string streams and the pretty printer), to nowhere but counting
(the pretty printer measures), or to the file open for output.

The printers and readers of CL -- `print`, `format`, `read-line`... --
are in library 1 (`lib/streams.asm`) and take a stream: they switch the
reader's source or `putc`'s destination for the call and put it back
after. A file stream is the firmware's one input or one output file; a
string stream is a structure the natives recognise. `format`
(`lib/format.asm`) parses its directives with their parameters and
modifiers and runs them on its arguments, recursively for `~{`, `~[`,
`~(` and `~<`.

## The editors

**The line editor** (`lib/editor.asm`) replaces the firmware's EDIT when
library 1 is there. It knows Lisp: a typed `)` shows its `(`, a
continuation line is indented as Lisp indents it, TAB indents. It keeps
the screen positions of the line as row minus the firmware's *roll
count*, which changes when the screen scrolls by hardware, so a line that
wraps at the bottom stays right; and it has the CPC's copy cursor.

**The function editor** (`lib/fed.asm`, `(ed 'f)`) pretty-prints a
definition (`lib/pp.asm`) into a buffer lent from the top of block space,
edits it on the whole screen and reads it back as a string. It draws
straight into the screen memory, ten times faster than the firmware --
but writes only: a ROM reading &C000-&FFFF reads itself, not the screen,
so its cursor is a character drawn again in inverse, not an XOR.

## Files, the RAM disc and the card

**Files** go through the firmware's cassette vectors, which a disc ROM
takes over: AMSDOS, Parados, or a tape. The 2 KB buffer the firmware
needs is lent from block space while a file is open (two when an input
and an output file are open together). `save` writes what the user
defined: `defun`, `defmacro` and `defvar` mark each symbol in a bitmap
as defined by library text or not.

**The RAM disc** (`mach/cpc/ramdisc.asm`) keeps files in a 6128's second 64 KB
(or a RAM expansion's), one byte at a time through the gate array's
banking. For a file on `M:` it swaps three cassette vectors for its own,
so the core's reader and `putc` work unchanged. (A lesson from it: a far
call in a jumpblock returns past its own address, into the next vector --
the routine it calls must take care of that.)

**The LambdaSpeak card** (`mach/cpc/card.asm`) listens on port &FBEE: text for
its DECtalk speech, and PlayCity's two sound chips. The byte that starts a
sentence is sent from a few bytes of code copied into RAM, which wait
there a moment: while the card is busy starting to speak, a fetch from a
ROM it serves -- and all of Lisp's may be on it -- can go wrong.

## The bytecode machine

The interpreter walks lists: every variable is looked up in an alist,
every binding conses. The VM ROM (`lib/vm.asm`) runs compiled code
instead, three to nine times faster.

**A compiled function** is a typed cell (`HDR_CODE`) whose data is its
*code vector* -- a vector of the bytecode (a string), the name, and the
constants -- or, for a closure, (code vector . environment). The
compiler's own functions are kept in the VM ROM, and their cells hold
just their number there.

**The machine** is a stack machine. DE is the program counter, IX the
frame, and the Z80 stack holds the operands, so the GC sees every value
there. An operation is a byte: operation k is the byte 3k, which is the
low byte of its `JP` in a dispatch page -- so going to the next
operation is

    ld a,(de) : inc de : ld l,a : ld h,page : jp (hl)

five instructions and a jump. 85 operations fit in the page; they are all
used.

**The frame.** The arguments are pushed by the caller, the first first;
below them four words of the caller's, then the entry pushes the frame's
own: the caller's IX, the code vector, where the constants and the code
start, the GC count when they were found, and the closure's environment.
The four words are the same whether the interpreter called (through
`apply_core` and `ROMCALL`: [count][return][ROM][return]) or the VM did
([count][PC][PC][`vm_ret`]), so returning is the same: `ld sp,ix`, pop
the frame, `ret` -- into the interpreter, or into `vm_ret`. Locals and
temporaries are pushed below IX; the compiler knows where each one is.
Up to four arguments and four locals have their own one-byte operations.

**Calls.** `CALL n` calls the function in the slot under its n
arguments; `CALLG k n` the global function of constant k, a symbol;
`CALLR k n` the VM ROM's function k (the compiler's calls of its own). A
compiled function is entered directly. Anything else goes out through the
core: `apply_n` copies the call into a frame of the interpreter's. That
costs two ROM switches -- some 2000 T-states, more than the interpreter's
own call -- so the common builtins are operations of the machine: `car`,
`cdr`, `cons`, `list`, `eq`, `eql`, `not`, `+`, `-`, `*`, `1+`, `1-`, the
comparisons, `zerop`, `oddp`, `evenp`, `aref` and its `setf`, on fixnums
and vectors, falling back to the builtin for anything else (a float, an
overflow, a string).

**Tail calls.** `TCALL` replaces the frame: a call with as many arguments
as the frame has copies them over its own; another moves the arguments
and the four words. The compiler turns a function's call of itself in
tail position into a jump, so such a loop costs nothing at all.

**The GC.** Compiled code is in block space, which moves. The frame
keeps where its code and constants start and the GC count then; after
anything that may allocate, `vm_fix` compares the count and, if a
collection happened, moves the program counter along with the code.

The operations: constants and literals (`CONST` `NIL` `T` `FIX`), locals
and arguments (`LOC` `SETLOC` `POPLOC`, `A0`-`A3` `L0`-`L3`), boxes
(`BOX` `LOCB` `SETLOCB`), the closure's variables (`CLO` `CLOB`
`SETCLOB`), globals (`GLOB` `SETGLOB` `GFN`), the stack (`DROP` `DUP`
`SLIDE` `SPIX`), jumps, long and short (`JMP` `JNIL` `JT`, and `JNILK`
`JTK` that keep the value for `and`/`or`), calls and returns, lambda
lists (`ENTER` `ARGS` `JSUP` `SUPP`), closures (`MKCLO`), special
variables (`SPECS` `BIND` `UNBINDL`), multiple values (`MVCLR`
`MVLIST`), and the builtins above. `(disassemble 'f)` shows them.

## The compiler

The compiler (`lib/compiler.lsp`, about 780 lines) is written in the Lisp
it compiles. It makes one pass over a function, emitting into a list of
items -- bytes, labels, jumps -- and keeping count of how deep the stack
is under the frame, which is where every local lives.

**Variables.** A plain lambda list's arguments stay where the caller put
them (`ENTER n` checks the count); any other (`&optional`, `&rest`,
`&key`) is turned into locals by `ARGS`, and the defaults are code that
runs if an argument is missing. `let` pushes its values: each becomes a
local where it lands, and `SLIDE` drops them under the result at the end.
A special variable is bound instead (`BIND`), and unbound at the end or
on the way out of a `return-from`.

**Closures** are flat: an inner function gets, when it is made, the
values of the outer variables it uses, in a list -- its environment.
That is right as long as nobody assigns the variable afterwards. A
variable that is both used from an inner function and assigned somewhere
is *boxed*: its place holds a cons around the value, and the closure gets
the box. Whether a variable needs a box is known only when all its uses
have been seen; the compiler records what it learns per binding (keyed by
the cons in the source where the variable is bound) and, if something it
already compiled assumed wrong, compiles the whole function again with
what it knows now. Most functions take one pass, closures two.

**Blocks.** `block`, `dolist`, `dotimes` and `loop` are labels:
`return-from` drops what is on the stack above the block, unbinds special
variables bound since, and jumps. A `return-from` from inside a `lambda`
cannot jump: such a block is compiled as a `catch` of a fresh tag, which
the `lambda` closes over -- known, again, only after it is seen, so it
costs a second pass.

**The rest.** Macros are expanded once and remembered. `setf`, `incf`,
`push` and `pop` evaluate a place's arguments once, into hidden locals.
`catch`, `throw`, `unwind-protect` and `%catch-errors` call small Lisp
functions (in the demo ROM) with the body as a closure: the interpreter's
frames do the work. Backquote becomes `cons`, `list` and `append`. What
cannot be compiled -- a function that closes over an interpreted
environment, `defun` inside a function -- is reported, and the function
stays as it was.

The last step assembles the items: jumps start short (a byte of offset)
and are made long where they do not reach, until nothing changes; then
`%make-code` (a native in the VM ROM) makes the code vector.

**`compile-file`** reads a source file whole, compiles each `defun`, and
writes `(setf (symbol-function 'f) (%code '("hex"...) (list
constants...) 'f))`: `load` reads that back, and `%code` makes the
function again, without the compiler.

In detail, with listings: [compiled closures and their
boxes](internals.md#in-the-compiler), [tail calls in the
VM](internals.md#in-the-vm), [the compiler's
optimizations](internals.md#the-compiler-and-the-machine).

## The bootstrap

Run interpreted on a CPC, the compiler would take 5500 of its 6600 cells
and 170 symbols before compiling anything. So it is compiled once, at
build time, by itself, and its bytecode goes into the VM ROM, where it
runs without costing any heap.

`tools/bootstrap.py` is a small interpreter of the Lisp the compiler is
written in -- a CL reader, an evaluator with closures, special variables,
`block` and `catch`, and the builtins the compiler uses -- in about 870
lines of Python. It loads `compiler.lsp`, then runs the compiler on each
of the compiler's own `defun`s. What comes out is written into the VM ROM
(`build/vmcode.asm`):

* each function -- an inner `lambda` too -- becomes one of the VM ROM's
  numbered functions, its bytecode in the ROM;
* all of them share **one pool of constants**, kept as Lisp text in the
  ROM and read into a vector the first time the compiler runs (and given
  back when it is done);
* a call of one of the compiler's own functions becomes `CALLR`, by
  number: no symbol and no cell for the compiler's eighty functions. Only
  `compile`, `compile-file` and `disassemble` have names.

The result is about 7.8 KB of bytecode and 2.3 KB of constants. A change
to the compiler is a change to the ROM; `tools/build.sh` runs the
bootstrap every time. The Python interpreter only has to agree with CPC
Lisp on the subset the compiler uses (no library macros: `%loop` instead
of `loop`), and the tests check the compiler's results on the CPC.
[The bootstrap, step by step](internals.md#the-bootstrap): the Python
Lisp, the eight steps, what `build/vmcode.asm` holds, what happens on
the CPC, and what to mind when changing the compiler.

## Building and testing

`tools/build.sh` assembles the core with rasm, extracts its symbols
(`build/core.inc`) for the library to assemble against, runs the
bootstrap, builds the parts' symbol tables (`tools/mklib.py`), assembles
the five other ROMs, and makes private MAME romsets in which the core
replaces BASIC -- what ROMDIS does on a real CPC, since MAME's ROM box
cannot answer ROM 0. `MACH` picks the machine (`cpc`); `BUILD_ID` fixes
the build number, so that two builds can be compared byte for byte --
which is how the machine layer was split off without changing a byte of
the CPC's ROMs.

The tests run in MAME, headless and fast. `emu/repl.lua` types each line
of a test file when the REPL asks for one (it watches a `RET` the REPL
calls in RAM before reading a line) and catches everything printed
through the firmware's text output; lines starting with `!` hold keys or
take screenshots. `tools/test.sh` runs every `test/*.lsp` against its
expected transcript on a 464 and on a 6128, with a blank disc for the
disc tests. `tools/run.sh -p` counts every instruction executed by
routine, which is how the speed work was guided. `tools/card.py` puts the
ROMs on the LambdaSpeak 4 card, which serves them to the real 464.
