# CPC Lisp 0.96 — working notes for Claude

*A Lisp machine for the Amstrad CPC.* Version 0.96 since 2026-11-12 (evening), 0.95 from 2026-11-12, 0.9 from 2026-11-07 (the
banner, the ROM headers' version bytes and the documents' titles say so).

A Lisp machine for the Amstrad CPC: **six ROMs** -- an auto-boot core and
five library ROMs -- that start a Lisp instead of BASIC. Mike's brief, 2026-11-06: a modern dialect
with Common Lisp syntax; speed is not the point and no byte-code compiler is
needed, though one would be nice later; closures; graphics, disc and sound.

These notes carry over what was learned on LambdaSpeak 4
(`~/git/lambdaspeak4`, private), so a session in this repo does not have to
rediscover it. That project's memory notes do not load here -- this file is
the bridge. Keep it current; put new lasting lessons here or in this repo's
own memory.

## The design

`docs/design.md` is the readable account of how it all works, and
`docs/internals.md` the deep end (the `%` names, closures, tail calls,
the speed work, the bootstrap step by step, with real listings); the
README, `docs/tutorial.md`, `docs/reference.md` are the user's side;
this file is the working notes behind it. Settled with Mike on 2026-11-06:

* **It must run on every CPC** (464, 664, 6128). Firmware is called **only
  through its vectors**, never at ROM-internal addresses. Past &BD37 the
  jumpblocks differ between the 464 and the 664/6128 -- see *CPC facts*.
* **Floats are wanted, through the firmware's maths package** (it is in the
  firmware ROM, not BASIC's, so it survives replacing BASIC).
* **Don't worry about ROM slots or numbers**: any number that does not
  collide with a built-in ROM (0 is BASIC, 7 the disc ROM). Development is
  in MAME; each build that passes the tests goes on the card, for the
  real 464.

What is built (`src/`, read `src/lisp.asm`'s header first):

* **ROM 0 is the core**, a foreground ROM: at 0 (ROMDIS) it replaces BASIC;
  at any other number `|LISP` starts it. It calls **KL ROM WALK** itself, as
  BASIC does, or no background ROM (disc!) is initialised.
* **Z80 assembly with rasm.** Common Lisp syntax and semantics where they
  fit: Lisp-2 (`#'`, `funcall`), symbols upcased, lexical closures, special
  variables (`defvar`), `defmacro` + backquote, `block`/`return-from`,
  `catch`/`throw`, `labels`/`flet`, `setf` on the usual places, `&optional`
  `&rest` `&body` `&key` `&aux` and destructuring. Unknown keys are
  ignored (as with `&allow-other-keys`); a plain key var X matches :X by
  name, so binding interns nothing.
* **Objects**: 16-bit words, tag in the low bits. Fixnums are 15-bit
  (-16384..16383). Symbols live in a fixed region (&0500-&14FF, 512 slots);
  cells (4 bytes) above; strings in a compacted block space; characters and
  markers are immediates below &0500. `src/defs.asm` has the layout.
* **Fixnums 512-639 have the markers' high byte** (&0401-&04FF; UNBOUND,
  EOFMARK... are &04xx with bit 0 clear): a test for a marker on H alone
  must look at bit 0 of L too. `check_real` did not, and `read` from a
  string or file said "syntax error" for 512-639 until 2026-11-12.
* **GC**: mark and sweep; marking is iterative with a 256-word mark stack
  and a heap rescan on overflow (not pointer reversal -- simpler, any depth).
  The machine stack is scanned **conservatively**, so native code may keep
  Lisp values on it; it must never hold a raw block-space pointer across an
  allocation (blocks move).
* **Eval** is a loop with proper tail calls; the Lisp has its own 4 KB
  machine stack (the firmware's is tiny), checked against overflow.
* **Input** is the library's line editor (below), or the firmware's EDIT
  without library 1; ESC is polled during evaluation (a counter, and the
  key buffer).
* **The library ROMs** (`lib/`, any numbers 1-6; MAME's ROM box makes them
  1-5, the VM ROM last) are up to four *parts*, each its own ROM: part 0
  (`lib/lib.asm`, LISPLIB.ROM) has graphics, sound, keys, the text screen,
  strings and characters (`lib/strings.asm`), the editors, pp, files, the
  RAM disc and the printers and readers (`lib/streams.asm`); part 1
  (`lib/lib2.asm`, LISPLIB2.ROM) floats, `format`, `sort` (`lib/seq.asm`),
  lists/sequences/`coerce` and what moved out of the core
  (`lib/lists.asm`), structures, the card; part 2 (`lib/lib3.asm`, LISPLIB3.ROM) the Lisp-defined
  functions and macros (`lib/lisp.lsp`) only -- nearly full; part 3
  (`lib/demo.asm`, LISPDEMO.ROM) `loop` (`lib/loop.lsp`, its expander
  `lib/loop.asm` -- a part may hold natives as well as text), more library
  Lisp (`lib/lisp2.lsp`) and the demos (`lib/demo.lsp`): new library code
  goes here or in part 1. **A fifth part is not possible as it is**: an
  LSUBR's or AUTOLOAD's data word keeps the part in two bits (the VM ROM,
  below, is no part). Space (2026-11-12, later): core 62 bytes free
  (TRS-80 102), parts 0-3 242, 127, 519, 444; the VM ROM 574 (512K:
  part 0 30, part 1 ~150; the TRS-80's part 0 2991).
  `src/xrom.asm` explains the arrangement: the core finds
  them by signature and build number (all ROMs come from one
  `tools/build.sh` run, and call each other by address), each says which
  part it is (header +22); calls cross through a trampoline in RAM using KL
  ROM SELECT; a library name costs nothing until the reader interns it, and
  a Lisp-defined function is read from the ROM's text on its first call
  (autoload). An LSUBR's or AUTOLOAD's data word is its ROM address with the
  part in the top two bits. Each part is assembled against the core's
  symbols (`build/core.inc`) and may use its constants and variables
  directly, its code only through `CORE`, and must hand the core RAM
  pointers only. **A part cannot call another part's code**: what they
  share is in `lib/common.asm`, a copy in each; a float met by part 0's
  `lint_hl` goes through the core (`num_int`). `tools/mklib.py` builds each
  part's table from its main file's includes and `;@lisp` lines, checking
  names across all parts. A new part: a main file like `lib/lib2.asm`, a
  line in `build.sh` and in the MAME scripts.
* **The line editor** (`lib/editor.asm`, asked for by Mike) replaces EDIT
  when the library is present: a typed `)` shows its `(` (beeps if there is
  none), continuation lines come indented Lisp-style, TAB, up-arrow history,
  and the CPC copy cursor. The REPL calls `EDHOOK` (a RET in RAM) before
  every line; the harness watches that, not EDIT.
* **Files** (`lib/disc.asm`): `(load "name")`, `(save "name" [symbols])`
  -- everything the user defined if none are named, pretty-printed --
  and `(dir)`, through the CAS vectors (AMSDOS, Parados, the card, tape).
  ".LSP" is added to a name without a ".". "Defined by the user" means not
  by library text: `lib_eval_text` sets `V_LIBDEF` while it evaluates, and
  `defun`/`defmacro`/`defvar` record that per symbol in the `LIBDEFS`
  bitmap (so a user's `TEST` is saved, an autoloaded `REMOVE` is not). The
  reader reads the open input
  file (`V_INSRC` 3), `putc` writes the output file (`V_OUTMODE` 3); the 2
  KB buffer is lent like the editor's, and toplevel abandons open files.
* **Streams** (`lib/streams.asm`, `open`/`close`/`with-open-file` in
  `lisp.lsp`): the printers and readers moved out of the core into part 0
  with CL's stream argument. NIL/T is the screen and keyboard, anything
  else the firmware's one input or one output file: `so_from`/`si_from`
  switch V_OUTMODE/V_INSRC for the call (the file's column and pushed-back
  character live in SO_FCOL/SO_FPEEK in between) and leave what to put
  back on the stack under the caller's return -- the native ends with
  `jp so_back`/`si_back`/`si_eof`. An input and an output file may be open
  at once: `fl_lend` lends a second 2 KB below the first, `fl_release`
  gives both back when neither is open (block space became 11/64 of the
  heap for that). A stream is `#S(FILE-STREAM name direction open-p)`.
  String streams (`lib/lisp2.lsp`, demo part): `#S(STRING-OUTPUT-STREAM
  chunks)` -- a printer prints into TOKBUF (mode 1) and `so_back` pushes
  the text as a string chunk -- and `#S(STRING-INPUT-STREAM string index)`
  read through V_INSRC 2, the index stored back by `si_back`. The natives
  tell the kinds apart by slot count (`so_kind`: 2, 3; a file stream has
  4). `*standard-output*` is a builtin special (S_STDOUT), NIL = screen.
  `so_kind` keeps IX: `so_from`/`si_from` hold their return in it, and a
  CORE call inside once sent it astray (the machine reset).
* **The RAM disc** (`mach/cpc/ramdisc.asm`): drive `M:` in the 6128's second
  64 KB, one linear space read and written a byte at a time through the
  gate array (configurations &C4-&C7 map a bank at &4000-&7FFF, &C0 maps
  it back at once -- the heap is there too; the code runs in the ROM at
  &C000 and the stack is above &8000). A 1 KB directory (63 entries), then
  the files packed; deleting moves the later ones down. `load`/`save` on an
  `M:` name swap three CAS vectors (close, abandon, char) for far calls
  into the library while the file is open, so the core's reader and putc
  need no change; close or abandon (toplevel, on an error) put the disc
  ROM's back. A 464 is recognised by a write under &C4 landing in main
  RAM. State: 64 bytes at `RDISK` (&B0C0), above the trampoline.
* **The function editor** (`lib/fed.asm`, Mike's idea): `(ed 'foo)` shows
  foo's definition pretty-printed (`lib/pp.asm`, also `pprint`) on a full
  screen; COPY or CTRL-S reads and evaluates it, ESC drops it; `(ed)`
  reopens the last text (kept in `V_EDITSTR`). Its buffer is lent from the
  top of block space (`V_BLKSAVE`; toplevel gives it back). The core's
  `putc` can print into memory or just count (`V_OUTMODE`), and the reader
  can read a string by index (`V_INSRC` 2), which the GC may move.
* **Floats** (`lib/float.asm`, part 1) are the firmware's 5-byte reals (about nine
  digits), kept in block space behind a typed cell (`HDR_FLOAT`) as a
  string's characters are. The core keeps the fixnum arithmetic: each
  numeric subr starts with `nums_v`/`nums_1`/`nums_2`, which hand the whole
  call to the library (`lnum_arith`, keyed by the `NUM_` label after the
  call) when an argument is not a fixnum -- and `num_ovf` does the same on
  integer overflow, so `(* 200 200)` is 40000.0. The reader and printer
  call `lnum_read`/`lnum_print`; a token too big for a fixnum reads as a
  float. `/` gives a fixnum only for a whole quotient of fixnums. Graphics
  and other natives taking integers round floats (`lint_hl`).
* **`format`** (`lib/format.asm`, its header lists the routines): all of
  CL's directives but `~/name/`, parameters, `:` and `@`, `~{` `~[` `~(`
  `~<` recursively. The destination: `t` (`*standard-output*`), a stream,
  or `nil` -- printed into TOKBUF through `to_string_ix` (255 characters at
  most). On the screen a lone LF in output is a new line (`putc` adds the
  CR).
* **`unwind-protect`** is a third frame kind (2) beside block and catch;
  `throw`/`return-from` run the cleanups of the frames they pass, and
  `toplevel` runs any left (an uncaught error, ESC), each frame taken off
  before its forms run (`run_cleanup`, `tl_state` resets the reader and
  printer first).
* **Errors can be caught**: `%catch-errors` (a special form) pushes frame
  kind 3, with the reader's and printer's state under it, and answers
  `(T . value)` or `(NIL . (message . objects))`. `error` (lisp.asm) and
  `%signal` unwind there (cleanups run) when such a frame is about --
  never for ESC, out of memory or stack overflow. `error`, `ignore-errors`,
  `handler-case` are Lisp (lisp.lsp); a condition is its message string.
* **Multiple values**: `values` (library) sets V_MVN/V_MV1/V_MV2/V_MVL;
  `apply_core` clears V_MVN at every call's start; `multiple-value-list`
  (a special form) takes them if the form's value is V_MV1 (else it is
  one value). `floor`/`truncate` (core) and the library's roundings set
  the remainder; the REPL prints every value.
* **The extended LOOP**: `loop` is a macro (`lib/loop.lsp`, in the demo
  part); a simple loop becomes the core's `%loop` special form, a keyword
  loop goes to `%loop-expand` (`lib/loop.asm`, in the demo part, native: a Lisp
  expander cost 2000 cells and 3 s an expansion). It parses the clauses
  into lists in an IX frame and builds forms from byte templates
  (`lp_build`: TQ_L/TQ_E a list, TQ_S a word, TQ_A/TQ_P an argument or its
  elements); temporaries are the interned `%0`, `%1`... (nested loops
  shadow them), keywords matched by name (`lp_kwt`) or, for builtins like
  IF, by address (`lp_kwb`). A for clause that ends does `(return-from
  %loop nil)`, so finally runs; a user's `return` leaves `%loop`'s own
  block and skips it.
* **Structures**: HDR_STRUCT, a vector by another header (the GC marks it
  as one, the printer shows `#S(...)`), element 0 the type. defstruct and
  the hash tables (`lib/structs.asm`, `lisp.lsp`) are built on it.
  `setf` on an unknown place calls the operator's SETF property with the
  arguments and the value (`defsetf`).
* **Vectors** (one-dimensional; `aref`, `svref`, `elt`, `vectorp` in
  `src/subrs.asm`, `make-array` and `vector` in part 1, `lib/structs.asm`,
  for the core's room): a typed cell
  (`HDR_VECTOR`) whose block holds the elements, a word each. Its header is
  "raw" (the data word is not a Lisp value), but `mark_value` and `rescan`
  follow the elements, and a block-less vector (mid-allocation) is skipped.
  `make-array` (`:initial-element`), `vector`, `aref`/`svref` (also on
  strings) with `setf`, `elt`, `length`, `vectorp`, `#(...)` both ways.
* **MIDI** (2026-11-12, Mike: "midi-note"): `midi-out` is each machine's
  native (mach/*/card.asm), `midi-note` and the rest Lisp
  (lib/lisp2.lsp), numbered as the card's own RSXs (channels 1-16,
  instruments 1-128, values masked to 0-127). On the CPC the card goes
  into its MIDI mode (&D0 &42 0) at the first MIDI byte, V_MIDI says so,
  and every native that writes &FBEE otherwise calls `cd_speech` first
  (&FF 20 out; it sends a System Reset down the wire). MAME has no card:
  `LISP_CARDLOG=file` logs the bytes written to &FBEE, and a test named
  `card*` gets them at the end of its transcript. On the TRS-80,
  `M_MIDI` (port 8, 470 us after each byte) copies them to the printer
  under `-ee`, as `<90>`.
* **Speed** (2026-11-06): `tools/run.sh -p prof.txt` counts every
  instruction fetched while lines run, `tools/profile.py prof.txt [-l]`
  sums them by routine. Done so far: arguments that are constants or
  variables skip `eval` (ev_cons), `FNBOUND` (a byte per symbol at &0300)
  spares calls the flet/labels search, two-fixnum `+ - <`... skip
  `nums_v`, ESC is polled per body (progn), not per eval, `sort` is native,
  plain lambda lists bind straight from the stack, `apply`/`mapcar`/
  `funcall` and the library's calls build no argument lists. fib 17 went
  from 1103 to 660 frames (197 compiled). The interrupt-time firmware is
  ~8% of any run; a cross-ROM call (KL ROM SELECT twice) is expensive.
* **The compiler** (Mike, 2026-11-07: "compile" and "compile-file" for
  bytecode). `lib/vm.asm` is a sixth ROM, the VM ROM (MAME rom5, the
  card's slot 1 as ROM 1): it says "part 4" in the library header, which
  `lib_try` takes as V_VMROM -- not a part: it has no names of its own.
  A compiled function is a typed cell, HDR_CODE (&8A: its data is a Lisp
  value), data = its code vector V ([0] the bytecode, a string; [1] the
  name; then the constants), (V . env) for a closure, or a fixnum k --
  the VM ROM's kth function (vmtab.asm: natives, and bytecode kept in
  that ROM). `apply_core` sends HDR_CODE to VMCALL (like LIBCALL, to
  VM_ENTRY = &C028 in the VM ROM); the VM calls anything else through
  `apply_n` (DE = function, HL = &arg 0, C = n: copies the call into a
  frame of its own). `lib/vm.asm`'s header explains the machine: a stack
  machine, DE = PC, IX = the frame, operation k = byte 3k = the low byte
  of its JP stub in a dispatch page; the frame has the same four words
  under the arguments whether the interpreter (apply_core + ROMCALL) or
  the VM called, so RET is `ld sp,ix`, pops and `ret`. Blocks move only
  in a GC (V_GCS counts them): after anything that allocates, `vm_fix`
  moves the PC along if the code moved. The VM's names (`;@vm` lines)
  are kind 3 entries in part 1's table: the symbol gets a HDR_CODE cell
  with the number.
* **The compiler is Lisp** (`lib/compiler.lsp`), too big to run
  interpreted on a CPC (5500 cells), so `tools/bootstrap.py` -- a small
  interpreter of the Lisp it uses, no library macros (no `do`, `loop`:
  `%loop`) -- runs it on itself at build time and writes its bytecode
  into the VM ROM (build/vmcode.asm). All of it shares one pool of
  constants (vm_pool, read from its text the first time, V_VMROOT;
  `compile` lets it go again, `%vm-release`); a constant that names one
  of the compiler's functions becomes a reference to it, so they cost no
  symbols. A change to the compiler is a change to the ROM: rebuild.
  The compiler's calls of its own functions become CALLR k n (no
  constant, no cell). How it works (variables, boxes, the restarts when
  a variable turns out to be captured) is at the top of compiler.lsp.
  Space: VM ROM 574 bytes free, core 22; the pool 178 of 256 constants;
  the dispatch page is full (85 operations: a new one must replace one).
* **What a compiled call costs**: a call of something not compiled goes
  out through ROMCALL (KL ROM SELECT twice) and apply_n -- some 2000
  T-states, more than the interpreter's own call. So the usual builtins
  are operations (car... list, +, *, <, oddp, aref and its setf), and
  `vm_fn` takes a symbol's function as it is (only an autoload goes to
  `coerce_fn`). Measured (MAME, frames): sum of a 300-list 18 -> 2,
  dotimes with oddp 67 -> 21, vector fill and sum 22 -> 3, fib 17
  660 -> 197.
* **`compile-file`** reads the whole source first (two open files take
  4 KB of string space; with the compiler's pool that does not fit on a
  464 with a disc ROM), then writes `(setf (symbol-function 'f) (%code
  '("hex"...) (list constants...) 'f))` per defun -- `%code` (a VM
  native) makes the function again, so `load` needs no compiler.
* **The machine layer** (2026-11-11, Mike: "start with the CPC abstract
  interface version"): everything CPC-specific is in `mach/cpc/` --
  `firmware.asm` (every firmware entry point, by name), `machine.asm`
  (the interface: `CON_` `KEY_` `VID_` `GFX_` `SND_` `FILE_` `FP_` `SYS_`
  names, each an equate to the firmware routine with that contract),
  `memmap.asm`, `mmacros.asm` (`MACH_START`, `MACH_INIT`, `FM`,
  `SYS_RESET`), `fp.asm` (fmcall), `fr.asm` (the fed's renderer:
  `VID_INIT`, `VID_CHAR`...), `ramdisc.asm` (`RDISC_*`), `card.asm`,
  `natives.asm` and `graphics.asm` (the CPC's own Lisp functions, which
  `lib/gfx.asm` includes where they were). `src/` and `lib/` name no
  firmware routine any more: use the interface names, and add one to
  `machine.asm` (and `mach/README.md`, the contract) when a new firmware
  call is needed. The build passes `-I mach/$MACH`; `tools/mklib.py`
  finds included machine files there and lists natives in assembly
  order. The split changed no byte of the ROMs: **check refactors with
  `BUILD_ID=n tools/build.sh`** before and after and `cmp` the ROMs.
* **Ports** (Mike, 2026-11-11), in this order: TRS-80 Model I/III with
  X-MEM/80 (Mike's own 512 KB card, `~/git/x-mem-80`: in X-MEM/80 mode 32
  pages of 16 KB, `out 65` maps one at &8000, `out 66` at &C000 -- the
  six images would run unchanged at &C000; Talker/80 and MIDI/80, also
  his, for speech and sound), then the ZX Spectrum 128/+2/+3 (banks 0,
  1, 3, 4, 6, 7 at &C000 are exactly six), the TRS-80 Model 4, MSX1, the
  TA alphatronic PC and the Sharp MZ-700. Mike has all of these; no PCW,
  MSX2 or Enterprise.
* **The TRS-80 port** (`mach/trs80/`, branch `trs80`; its README has the
  user's side). Lessons, each one cost a round:
  * trs80gp delivers `-i`/`-if` typed input only to a program waiting in
    the ROM's key routine at &0049, not to one polling &002B: KEY_WAIT
    waits there. `-iw` waits for screen text; a killed trs80gp writes no
    printer file, so tools/trs80/run.sh uses `-itime` and `-it -ix`.
  * `-ee`: write 255 to port &47, *read it back*: 1 means extensions
    (not the carry). 128 to &47 exits with BC.
  * LDOS finds SYS0-SYS13 by directory position (the first two entries of
    each directory sector), not by name: a file put there runs instead of
    the overlay (DIR, LIB ran LISP/CMD). tools/trs80/ldoswrite.py skips
    those entries.
  * The Level II ROM's single divide needs its helper copied to &4080
    (from &18F7, 14 bytes) as BASIC does at start: under LDOS it is not
    there and LOG, SIN, SQR... hang. The ROM's function table at &1608
    gives the entry points; the Model III's ROM has them at the same
    places.
  * The CPC's five-byte reals are Microsoft's binary form with a 32-bit
    mantissa: to and from the ROM's single and double is copying bytes.
  * float.asm counts on FP_MOVE and FP_CMP keeping BC and DE (a `djnz`
    after FP_MOVE); keep that in any machine's maths.
  * Block space and file buffers are machine choices (MACH_BLOCKS,
    FILE_BUFSIZE): with half a CPC's heap the CPC's 11/64 left too little
    string space for compiled code.
  * The RAM disc (`rdisc80.asm`, pages 9-31) is seen in the &C000
    window, where the machine page itself runs: `RS_XFER` (resident)
    maps a page for one LDIR to or from RAM below &C000 (the file's
    buffer). A machine call (`M_DELETE`...) is a line in mkjumps.py.
  * LDOS's ticks: a Model I's at &4040, 25 ms, a byte running on
    through the seconds (&4041 seconds, &4042 minutes, &4043 hours); a
    Model III's at &4216 count 30 down to 1 within each second (&4217).
    Measured in trs80gp with probe programs. (time) is built on them.
  * Talker/80 (2026-11-12, a real Model III): a TRS-80 reset resets it to
    its DIP switches' mode, while X-MEM/80 keeps RAM -- so the "DECtalk
    is on" flag (TK_MODE) is cleared at every Lisp start (m_init); plain
    text speaks in any mode, DECtalk's brackets do not. Each control byte
    makes its firmware wait 200 ms, set the chip up and EMPTY its text
    buffer, and a second control byte meanwhile is lost: `tk_ctl` waits
    until it says ready (bit 7) before anything else goes (sending &E9
    &EE before every line silenced every line). The firmware keeps the
    CR that starts speaking to itself, and DECtalk speaks a clause only
    once it ends (a full stop, a new line): `say` sends LF, then CR --
    without it, phonemes in [] stayed silent (its Daisy ends "]\n"). Its
    Epson chip is DECtalk 5.01: arpabet is two characters a phoneme, the
    L is `ll` (a bare `l` ends the song there); LambdaSpeak 4's DECtalk
    Mini takes both.
  * A TRS-80 has no COPY and no CTRL: SHIFT down-arrow then C is COPY
    (&E0), then S is CTRL-S (&13) -- the function editor's "done" was
    out of reach before (k_comp in page.asm). `(reset)` goes back to
    LDOS (SYS_RESET = M_QUIT): RST 0 with X-MEM/80's pages switched hung.
  * What works where is marked in docs/reference.md (**CPC only**,
    **TRS-80 only**, *TRS-80:*) and the tutorial; keep it so when adding a
    machine-specific function (mach/*/ natives are the list).
  * rasm evaluates `assert` and `repeat` where they stand: a symbol in
    them must be defined above (an equate after it is "not found").
  * The images are compressed (`tools/trs80/lz.py`, decoded by the
    loader) to fit one single-density disc: change the format in both.
  * To work while tests run on build/trs80: `MACH=trs80
    OUT=build/trs80-dev tools/build.sh`, `TRS80_BUILD=... run.sh`.
* **The 512K CPC** (`mach/cpc512/`, branch `cpc512`, 2026-11-12; Mike
  asked for it against Revaldinho's expansion, "the standard for the
  464"): the six images loaded from disc (`RUN"LISP`, LISP.BIN =
  `loader.asm`) into block 3 of banks 0-5, run at &C000 in configuration
  C1 (&C1 + 8 x bank); SYS_BANK is one OUT. Its README has the design.
  Lessons:
  * The CPU sees the screen's RAM only in C0, so a **resident part** in
    main RAM (`resident.asm`, &A160-&A6EF) holds a trampoline per
    firmware routine (`call fwc : dw addr`; `tools/cpc512/mkfw.py` makes
    `firmware.asm`/`fwtab.inc` from mach/cpc's -- the maths package and
    the KL ROM routines are called directly), the fed's renderer, the
    file routines' dispatch, RS_XFER. At &9800 it left too little string
    space (discstream failed): &A160 now, just room for it.
  * **BASIC's RUN of a binary restarts the firmware**: the cassette
    vectors were back ("Press PLAY"). The loader calls KL ROM WALK itself.
  * **Block space reaches below &8000**: the second file buffer (fl_lend)
    was at &4000-&7FFF, where RS_XFER maps the RAM disc's block, and an
    M: output with any input open wrote garbage. RS_XFER copies through a
    128-byte buffer of its own, each side in its configuration.
  * The file dispatchers (RS_FGETC...) keep everything but AF, as CAS IN
    CHAR / OUT CHAR do (DE was lost at first).
  * `(basic)` is a reset; |BOOTLISP is a stub (the images are no ROMs).
  * **On the real 464 with Revaldinho's universal 512K card**
    (2026-11-12): "No 512K expansion found" until its DIP switches
    went to configuration 4 (0100, DK'tronics mode, 512K): in shadow
    mode (8, 12) bank 3 shadows the base RAM, so only banks 0-2
    answer. The loader now says how many answer. Then it booted, and
    **everything passed** there: `HWTEST.LSP` on the disc --
    `(load "hwtest")`, `(hwtest)`: cells, two files at once (A: to M:),
    lazy loading through Parados, the RAM disc, far arrays into banks 6
    and 7, a far array, the compiler; by hand (rose), (ed), ESC, (say);
    after CTRL-SHIFT-ESC and RUN"LISP, `(hwtest2)`: the far array and
    M:'s file kept. (Its order matters: the checks that need a 2 KB disc
    buffer first, while there is string space.)
  * The plain 6128's version passed on the same 464 too (bank 0 of
    the Revaldinho card): hwtest's cells and lazy loading, (rose),
    (ed), ESC, (say), and COMPILE undefined, as it should be.
  * **String space is the tight resource** on the disc versions (5.3 KB
    at boot on the 512K): every library function's first use costs its
    symbols' names there, and a file open on a disc 2 KB of it. A file
    on M: is lent 512 bytes now (`fl_lend_f`, for load, save and
    %open; the RAM disc uses 320), not 2 KB. Making far arrays is slow
    on the real machine (each byte through rd_putc and a bank switch:
    test 5's 390 KB took minutes); a native 256-byte fill would help.
  * **The RAM disc's errors give the file buffer back** (fl_release
    before lib_error: an error caught by %catch-errors left it lent, and
    the next open said "a file buffer is in use already"). fl_release
    checks V_BLKSAVE first: fe_release sets V_BLKHI from it blindly, and
    `(dir "m:")` lends nothing -- without the check, string space ended
    at 0 after the first M: error on a 464 (the suite caught it).
  * **rd_close (the 512K's and the TRS-80's RAM disc) failed a file
    whose length was a multiple of 256** -- an empty one too: nothing
    left to flush, `call nz,rd_flush` fell through with carry clear,
    "cannot write the file", the file dropped. The TRS-80's hwtest
    found it (its M: probe writes an empty file).
  * **The TRS-80's hwtest** (`mach/trs80/hwtest.lsp`, put on lisp-a and
    lisp-m3 by mkdisk.py with comments and indentation squeezed out --
    the Model I's disc had 4 granules left) writes only to M:: it
    copies and lazily loads HWTEST/LSP itself. A write error inside
    %catch-errors (a full disc) leaves the output file marked open until
    toplevel: every later open says "a file is open that way already".
    `(hwtest-big)` is past 256 KB, for the real card only.
  * **`load` is Lisp since lazy loading**, so `%load` is called through
    `eval`: called directly, the file's forms were evaluated in `load`'s
    lexical environment, every loaded defun closing over NAME and LAZY
    (the compiler refused them: "closes over variables").
  * MAME: `-ramsize 576K` on cpc464 (with the DDI-1) or cpc6128, the
    stock romsets; the harness types `RUN"LISP` at BASIC's EDIT
    (`LISP_EDIT2` in repl.lua), then lines at EDHOOK. `tools/cpc512/
    run.sh`, `test.sh`; `test/NAME.cpc512.out` where the output differs.
* **The plain 6128** (`mach/cpc6128/`, 2026-11-12; Mike: "a version that
  would run on a plain CPC 6128 ... leave out the compiler"): five images
  -- the core in block 7 at &C000 (C1), parts 0-2 in blocks 4-6 at &4000
  (C4-C6), part 3 in the main RAM's &4000 (C0). Its README has the table.
  * **The parts are assembled at LIB_ORG = &4000** (memmap.asm; the
    default, src/defs.asm, is &C000): `lib_addr` and `lib_dispatch` put
    back &4000's top bits. The core stays at &C000, so its `cp #C0`
    tests (a SUBR is at &C000 and up) hold. The CPC's and the TRS-80's
    images came out byte for byte the same (BUILD_ID=77, cmp).
  * The main RAM's &4000-&7FFF is hidden while a part in 4-6 runs, so
    the cells end at CELL_TOP (&4000; src/lisp.asm's layout) and block
    space starts at BLK_LO (&8000, MACH_BLOCKS): 2430 cells, 5 KB of
    strings. **Two files open at once need 4352 bytes free** (2 KB each,
    fl_lend's 256 margin): discstream's copy was 16 bytes short until
    the stack went to 3.25 KB (STACK_SIZE in memmap.asm; ~250 calls deep,
    4 KB gives ~350) and the resident part, without the RAM disc's
    routines (`variant.asm`: RESIDENT, RAMDISC), to &A2F0.
  * The directory is **an overlay by symlinks** on mach/cpc512: rasm
    looks for an include beside the including file first (before -I),
    and beside the *link*, so the shared files get this machine's
    memmap.asm and mmacros.asm. NBANKS and BANK_CFGS (the configuration
    of each bank, r_bank's table) moved to memmap.asm for it.
  * `mach/$MACH/novm`: tools/build.sh leaves out the VM ROM and its names
    in part 1 (`compile` is then "undefined function COMPILE", not a
    HDR_CODE cell with nothing to run it). `test/skip.cpc6128` lists the
    tests the variant's runner skips (`tools/cpc6128/test.sh`).
  * The RAM disc refuses (rd_ready: RD_NBANKS < 6) -- else `M:` would
    write over the code in blocks 4-6.
* **The TRS-80 Model 4** (`mach/trs80m4/`, branch `trs80m4`,
  2026-11-13; Mike: "native. yes 128 kb.", LS-DOS 6.3.1, a FreHD, Ian
  Mavric's Improved Grafyx): six images in "slots" 2-7, half a 32 KB
  bank each (OPREG &84 bits 4-6: &20 bank 1, &30 bank 2 at &8000; slot
  s is bank s/2-1, odd slots at &C000; a ROM number of 0 is none, so
  find_library starts at 2). Its README has the map. Lessons:
  * **Write OFLAG$ before OPREG** (FLAGS$+'O'-'A', from @FLAGS$): LS-DOS's
    drivers map the keyboard and screen in from it in an interrupt and
    put it back -- so the interrupts stay on. LS-DOS is called through
    the resident gate (RS_SVC) with its bank 0 in.
  * **Anything LS-DOS reads through a pointer must be below &8000**: the
    file name buffer was in the machine page (bank 2) and @FSPEC read
    bank 0 there -- "cannot open" (FNAMEBUF, memmap.asm).
  * **In map 0 the ROM covers &0000-&37FF**, the resident part too:
    `ld a,(RS_P84)` to switch back read the ROM (fp_p84 in the page).
    trs80gp's -m4 has the Model III ROM there (an "I" at &0125); a 4P
    has not: fp_probe says so at the start, floats fail with no carry.
  * **LS-DOS's cursor blinks while @KEY waits**, at its own position,
    and puts back what it saved -- a character of the Lisp's lost at
    the bottom-left, a "_" now and then. *DO's code 15 turns it off
    (m_init), 14 on again at (quit).
  * **Passed on Mike's real Model 4** (2026-11-13): from the FreHD,
    build 25495, Improved Grafyx: hwtest 8 yes, the editor, F1, the
    tunes on the speaker, `say` through Talker/80 (MIDI untried); and
    from his HxC (Lotharek's: settings live in the device, its menu is
    "SD card out, both buttons", a reset to its defaults "right button
    at power-on, 5 s" -- his changed bitrate gave "Data record not
    found"). His Model 4 boots the FreHD: the HxC is drive :4 under his
    `lsdos`, `LISP` there. His
    cards: the FreHD's at /media/mike/FREHD (`cpclisp4`), the HxC's at
    /media/mike/7C24-AC2B (`cpclisp4_JV3.hfe`, `cpclisp4.JV3`) -- look
    at an image's directory before replacing it: he may have saved there.
  * The heap is the lower 32 KB beside LS-DOS (every image must see
    it): ~1900 cells, 2.7 KB of strings. Doubling it would mean the
    code in the lower half (OPREG bit 6) and the heap in the upper.
  * The hi-res board (`hires.asm`, trs80gp's default): ports &80 X byte,
    &81 Y, &82 data (bit 7 left), &83 options (bit 0 on, 2-3 count
    down, 4-7 *don't* count after read/write), &8E=1 text over
    graphics on the Tandy board. **Bit 1 of &83 is the Tandy's waits
    but the Grafyx's "no text"**: with it set, Mike's Improved Grafyx
    showed a black screen from m_init on (2026-11-13) -- it is 0 now.
    trs80gp `-gg`/`-gc` emulate the Grafyx (xtrs's grafyx_write_mode
    has the bits), `-is` screenshots what is shown (`-it` is only the
    text RAM); run.sh `M4HIRES=-gg`. g_cell must keep DE: the fill reuses it (columns past 255
    came back /8 -- the fill ran along row 119 for ever).
  * **fill-box stepped 2 y units** (a CPC pixel row): on the Model 4 a
    row is 5/3, and every fifth row was left out (APFEL's cells were
    striped). `M_NEXTY` (the Model 4's only: mkjumps.py's per-directory
    extra, so the Model I/III's numbers stay) gives the next y on
    another row; lib/gfx.asm uses it `ifdef M_NEXTY` -- every other
    machine's ROMs byte for byte the same (BUILD_ID=77).
  * `examples/apfel.lsp`, the Apfelmaennchen (Mike, 2026-11-13), is on
    the CPC discs and the Model 4's: fixnums times 64 (no floats: slow,
    and string space), coarse to fine with `test` reading the parent's
    colour. Lighting every other escape band flooded the picture (the
    bands near the set are wider than a cell); the set alone is it.
    Compiled on a 464: 33088 frames. A test of it in Python first
    (the same integer arithmetic) saved rounds in the emulators.
  * trs80gp's `-m4` is "2 wait states per instruction": some 2.77 M
    T-states a second, measured; the speaker's delays are tuned to it.
  * trs80gp input: `-id N` waits N frames, `-ik 6 4` holds BREAK (row 6
    bit 2), `-ik 6 0` lets go: run.sh plays the tests' `!esc`/`!type`.
    **`-ik`'s mask is hex** (`-ik 5 10` is the comma, row 5 bit 4).
    Measured under LS-DOS: CTRL @ is 0, CTRL and a digit the digit,
    CLEAR and a key the key, SHIFT @ a backquote at @KEY -- no brackets
    from CTRL (Mike tried CTRL , for `[`: a replacement ROM's, not
    LS-DOS's); SHIFT down-arrow composes them, as on the Model I/III.
    F1 (COPY) is "done" in the function editor -- Mike, 2026-11-13.
    `-ig` dumps the hi-res memory (128 bytes a row).
  * The suite: `tools/trs80m4/test.sh` (3 at a time, a disc copy each);
    build elsewhere meanwhile (`OUT=build/trs80m4-dev`,
    `TRS80M4_BUILD=...`): each test copies the disc as it starts.
  * **The FreHD** (Mike uses it and a Gotek): the build makes
    `lisp-m4.hdv` (`tools/trs80m4/mkhdv.py`) from a clean LS-DOS 6.3.1
    hard disc (`ls631-frehd.hdv.gz`, made with `--base` from the image on
    Mike's card: only LS-DOS's own files, the rest zeroed -- his card's
    images hold his and others' programs: never publish them). The
    FreHD's boot menu lists every file on the card's root with the
    xtrs/Reed header (56 CB) and byte 8 bit 0 set; its LS-DOS uses the
    Radio Shack driver (RSHARD6: the FreHD answers as that controller).
    **The geometry is not the header's**: 256 sectors a cylinder in the
    file, but LS-DOS uses the first 32 -- 8 granules of 4 sectors (from
    DIR/SYS, which fills its cylinder). Reading granule g at g*32 found
    zeros, and a wipe by that zeroed real files. **Cylinder 0 is the
    boot's**: sectors 4-13 hold boot code the GAT does not mark (zeroing
    them stopped the boot after the logo). trs80gp: `-frehd_dir DIR
    -frehd_patch -frehd_menu` boots its own FreHD menu; wait for "==>"
    (`-iw`), then ENTER -- a fixed `-id` lost the key. `M4DISC=hdv`
    run.sh/test.sh. Mike's card mounts at /media/mike/FREHD.
* **Dropping library functions** (2026-11-12, Mike asked how programs
  could use more memory): when `cons` finds no cell after a GC it calls
  `lnum` +15, `ln_short` (`lib/short.asm`, part 1). Pass 0 hides every
  closure on a LIBDEFS symbol whose name is an autoload in a part's
  table (pointer + 1: odd, a fixnum to the GC), a second GC runs, pass 1
  puts back the ones still held (their cell's car is not FREEMARK) and
  marks the freed ones 1, pass 2 gives those a HDR_AUTOLOAD stub
  (`ls_probe` finds the text again). Boot forms' functions, macros,
  compiled code and the user's own definitions (`mark_def`, also from
  `setf` of `symbol-function` now) are never touched. Its scratch is
  V_PEEKROM (saved) and the stack: LIBSCR+254/255 are SO_PTYPE/SO_DIR.
  `random` moved to part 1 (`lf_random`, float.asm) to make room in the
  core; a part's error with a core message goes through `CORE error`, not
  `lib_error` (it reads the message from its own ROM: `(random 0)` reset
  the machine).
* **Lazy loading** (2026-11-12, the same request): `(load name :lazy t)`
  (`lib/lazy.lsp`, part 1's first Lisp text; `load` is Lisp now, the
  native is `%LOAD`). The file is read through once: a defun becomes a
  stub closure `(lambda (&rest args) (%lazy-call name args))`, kept in
  the plist as `%LAZY` = (stub file . position); other forms are
  evaluated after the reading. The first call reads the defun from its
  position and marks the symbol the library's (`%libdef`), so `save`
  leaves it out and the dropper takes it back to the stub (`ls_lazy`
  finds %LAZY by name in the plist). The core's reader counts what it
  takes from the input file in V_FPOS (fl_in_open zeroes it; a pushed-
  back character, V_PEEK or SO_FPEEK, is not counted): `%file-pos`,
  `%file-skip` (lib/lazy.asm) and CL's `file-position` (forward only).
  A first call while an input file is open is an error (one input file).
  test/disclazy.lsp.
* **Far arrays** (2026-11-12, the same request; Mike's expansions):
  `make-far-array`, `far-array`, `far-ref` (setf: the SETF property, a
  boot form), `far-length`. A far array is a file NAME.FAR on M: --
  "F", the element type (0 T: the object's word, fixnums, characters, T,
  NIL; 1 (unsigned-byte 8); 2 character), the elements -- made through
  the RAM disc's output file (`%far-fill`, which stops at the first byte
  that cannot be written) and read and written in place. Natives in part
  1 (`lib/farray.asm`), the Lisp in part 3 (`lib/farray.lsp`: part 1 was
  full). `#S(FAR-ARRAY name entry type)`: the directory entry is read
  again at every access (files move down when one before them is
  deleted) and searched for by name if it changed. Each machine's
  `mach/$MACH/far.asm` (included by part 1) has its directory's layout
  and `fa_xfer` -- the CPC ROM's 64 KB format by the gate array (one LDIR
  per bank: per byte it was 20% slower), the 512K's and the TRS-80's
  copies of their `rd_xfer` through RS_XFER (keep them in step);
  cpc6128 links the 512K's and refuses (RAMDISC 0). `make-far-array`
  checks the result's length: a full M: drops the file (512K, TRS-80) or
  truncates it (the ROM's). Part 1 code must not call the core for
  trivia in a hot path: is_typed/vec_data/str_data inline in `fa_get`
  took a far-ref from 3.7 to 2.9 ms (aref 1.2). test/discfar.lsp.
  **M: past X-MEM page 16 reset the TRS-80 into LDOS** -- in trs80gp
  and on the real Model III alike (2026-11-12): with 16 page numbers
  (the card's 32 KB/SuperMem mode, Mike thinks his switch is there; or
  256 KB of SRAM; trs80gp's emulation) pages 16-31 are 0-15 again and
  page 17 is the Lisp's own RAM. `rd_pages` (rdisc80.asm) probes once
  -- page 25 against page 9 -- and keeps the RAM disc to pages 9-15
  (112 KB) then. **Passed on the real Model III in 16 KB mode**
  (2026-11-12: hwtest's 8 and hwtest-big; Mike's switch had been at 32
  KB pages); build 977, with rd_pages, again: hwtest 8, hwtest2 2,
  367K free. The TRS-80 discs are in `discs/` too. TRS-80 far-refs are
  slow too (100 setf in 3.7 s, not looked into). Don't probe trs80gp's
  options by running it by hand: it pops up windows on Mike's screen.
* **Still to come**: `docs/checklist.md` has the list, in Mike's order.

**Upper ROM caveat:** code running in an upper ROM sits at &C000-&FFFF, the
same addresses as screen RAM. Screen access from ROM code goes through the
firmware (or careful ROM/RAM banking). Likewise a ROM at another number
cannot be read while ROM 0's code runs: crossing ROMs needs RAM trampolines
or the firmware's FAR CALL.

## Hardware on Mike's bench

**CPC Lisp runs on the real 464** (2026-11-07, build 6078 from the card):
banner, speech and singing through the card, PlayCity, disc through
Parados, ESC, `(fib 17)` in about 13 s -- MAME's timing holds. "Disc
full" there was the card's drive holding a full disc (flash disc 29):
`tools/dskloader.py --list` names the drive's disc, `--get 0` copies it
off for a look (iDSK), and a blank `iDSK x.dsk -n` loaded into the drive
fixed it (the drive is PSRAM: lost at power-off; store it in a free slot,
8, with the CPC off, to keep it).

* **CPC 464, BASIC 1.0**, with **LambdaSpeak 4** (board 1). The card serves
  up to eight expansion ROMs from flash, uploaded over USB with no EPROM
  burning -- the reason this project is cheap to iterate. It also emulates
  the disc drive (54 flash discs) with **Parados as ROM 7**, and does speech,
  PlayCity (six more AY channels), MIDI, PCM drums and an RTC.
* **The 464 with BASIC 1.1 firmware** (an unofficial 1.1 ROM) **and a RAM
  expansion** (2026-11-07, build 22482): everything checked there --
  floats through the 664/6128 maths package, the line editor, ESC, the
  compiler, Parados; the RAM disc `M:` on the expansion under 1.0 and
  1.1 alike.
* **CPC 6128** with a Gotek on its own drive -- put away for now. The card
  runs a separate 664/6128 firmware build there.
* The 664 is untried.

Mike tests on the real machines. Tell him exactly what to type, and what he
should see.

## Toolchain (already on this machine)

| | |
|---|---|
| rasm 3.2.7 | `~/claude/midi80/toolchain/rasm/rasm` |
| iDSK | `~/claude/midi80/toolchain/idsk/iDSK` |
| hxcfe (HFE images) | `~/claude/midi80/toolchain/hxc/build/hxcfe` (with `LD_LIBRARY_PATH` that directory: `libhxcfe.so`; the Model 4's build makes its .hfe with it) |
| MAME | `/usr/games/mame`; CPC ROMs in `~/claude/cpc/mame-roms` (`-rompath`) |
| 464 OS/BASIC 1.0 ROM image | `~/claude/cpc/mame-roms/cpc464/cpc464.rom`; firmware jumpblock table at &08AC, two bytes an entry |

**rasm reports a failed assembly on stdout and still exits 0.** Check for
`Write binary file` in its output.

## Testing in MAME

    tools/build.sh                      assemble, splice into build/mame
    tools/run.sh [-m 464|6128] [-s shot.png] [-p prof.txt] file.lsp   type it, print the transcript
    LISP_DUMP="BC77-BC9F,B0C0-B0FF" tools/run.sh ...   and RAM in hex at the end
    tools/test.sh [-m 6128] [-u]        regression: test/*.lsp against test/*.out
    tools/mame.sh [-m 6128] [disc.mfi]  a MAME window to play in, with a disc

* **MAME writes .mfi floppy images back, not .dsk** (its CPC DSK format is
  read-only: a SAVE vanishes with the session). `tools/mame.sh` makes and
  uses `work.mfi`; `floptool flopconvert dsk mfi` converts (name the input
  format: `auto` takes a CPC .dsk for an Acorn one). Tests use a fresh .dsk,
  which is fine within one run; `run.sh -d` puts it in the 6128's drive, or
  a DDI-1's on the 464 with the ROM box behind it.

* **MAME's ROM box cannot answer ROM 0**: it numbers its *filled* sockets
  1, 2, 3... in order (rom1, rom2, rom8 became ROMs 1, 2, 3). So
  `tools/build.sh` builds private romsets in `build/mame` with BASIC's 16 KB
  replaced by LISP.ROM -- what ROMDIS does on the real machine. MAME warns
  about the checksum and runs it.
* `emu/repl.lua` catches output by tapping opcode fetches at &BB5A (TXT
  OUTPUT; A is the character) and types a line each time the ROM enters the
  EDIT vector. EDIT's own echo does not go through &BB5A, so the harness
  writes the typed line into the transcript itself.
* The first keys typed after power-up are lost: the harness waits 50
  frames before the first line, and posts every line with a leading space.
* Lines starting with `!` in a test are timed actions while the line before
  runs: `!press KEY[+KEY] N` holds CPC keys through the matrix (COPY is 9,
  ESC 66, CTRL 23, cursor up/right/down/left 0/1/2/8), `!type N text`,
  `!shot N`. natkeyboard has no `{RIGHT}` for the CPC, and a second
  `post_coded` too soon cuts the first one short.
* `screen:snapshot(path)` works with `-video none`; `-nothrottle` runs at
  about 14x. Long tests outlast a 2-minute tool timeout -- run in background.
* The LambdaSpeak 4 patterns (`~/git/lambdaspeak4/tools/run_rom.sh`,
  `emu/romtest.lua`, `emu/midipiano.lua`) are the reference for anything
  new: tap tokens in globals, the key matrix through `:kbrow.N` fields.

## CPC facts that cost time before

* **A foreground ROM is entered** (464 and 6128 alike) with DE = &0040,
  HL = &ABFF, BC = &B0FF, SP = &BFF8. After KL ROM WALK, HL is &ABFF on a
  bare 464 and &A6F7 on a 6128 (AMSDOS takes ~1.3 KB, and every background
  ROM 4 bytes more). &AC00-&B0FF is the foreground's own area on both.
* **The jumpblocks differ past &BD37.** The 664/6128 insert twelve entries
  at &BD3A, so EDIT (the line editor -- firmware ROM, not BASIC) is &BD3A on
  a 464 and &BD5E on a 664/6128, and the maths package starts at &BD3D
  (464, 49 entries) or &BD61 (6128, 32 entries). The real-number routines
  are at the same offsets in both (6128 = 464 + &24), except that only the
  464 has REAL SUBTRACTION (use REVERSE SUBTRACTION) and only the 6128 RND.
  A 464 is recognised by &EF (FIRM JUMP) at &BD3D; the 6128 has &CF.
* **The firmware maths routines** return carry set when all went well
  (clear on overflow), work only on RAM outside &0000-&3FFF (the lower ROM
  is in), use nothing of BASIC's, and clobber IX and IY. MOVE REAL returns
  HL = the destination. REAL FIX, INT and REAL TO BINARY say nothing about
  overflow: check the exponent first. The Firmware Guide's text is in
  `The_Amstrad_CPC_Firmware_Guide.pdf` (amstrad.eu), pages 76-81.
* **RST 3 (FAR CALL) in a jumpblock entry returns past its far address --
  into the next vector.** The routine it calls must take that return
  address off (AMSDOS does: one routine for all its CAS vectors, which
  tells it which one was called) or point it at a RET; `rd_fix` in
  `mach/cpc/ramdisc.asm` does the latter. Missing this ran CAS OUT DIRECT after
  every CAS OUT CHAR, and left AMSDOS writing broken files. The far call
  does hand the routine's flags back (it keeps them in AF').
* **Library code: the CORE macro takes IX** (it passes the routine in it).
  A routine keeping a frame in IX calls the core with SCORE, and saves IX
  around any helper of its own that calls the core (lq_tolist did). And
  **LDHLI takes A**: a flag kept in A does not survive it. Both cost a
  debugging round each.
* **A builtin symbol's name is in the core ROM**, which library code cannot
  read (it sees its own ROM at those addresses). Compare a builtin by
  address (`S_KW_KEY`...), and get a name through `CORE subr_string`
  (which may allocate). Library symbols' names are in RAM.
* **A macro call keeps its expansion**: the first evaluation rewrites the
  call to `(%EXPANDED (macro . expansion) op . args)` (mx_displace,
  sf_expanded); the printers show `(op . args)`. Redefining the macro
  makes the call expand afresh.
* **ROMCALL hands BC back as the callee left it.** A core routine that
  calls the library and needs B or C afterwards must save them itself
  (the reader's token length did not survive `lnum_read` at first).
* **The 464's ROM walk** went 3, 2, 1 in MAME. The docs say it only looks
  at ROMs 0-7 (the 664/6128 at 0-15): give library ROMs numbers 1-6.
* **rasm labels are case-insensitive**: `s_quote` and `S_QUOTE` collide.
  A label in front of a macro that starts with `align` is not aligned.
* **Reading screen memory from ROM code reads the ROM.** A ROM at &C000
  sees itself at &C000-&FFFF; only writes reach the screen RAM. The function
  editor draws straight into the screen (`mach/cpc/fr.asm`, ten times the
  firmware's speed) but never reads it back: its cursor is the character
  drawn again in inverse. (XORing the cell put the ROM's code on screen.)
* **The firmware's text output manages ~5 characters a frame** (TXT WR
  CHAR): fine for a line, far too slow to redraw a screen per key.
* **MAME's CPC keys** (emulated keyboard): COPY is End, DEL is Insert, CLR
  is Backspace, ESC is backquote, CTRL is Right Alt; Left Ctrl and Left Alt
  are joystick fire buttons (Left Ctrl + S typed an X). In natural mode, End
  is COPY too -- Mike's confirmed way to finish the function editor.
* **ROMDIS**: BASIC's ROM obeys it on all three machines, so a card ROM at 0
  replaces BASIC on the 464, 664 and 6128. **The 664/6128's internal AMSDOS
  ignores ROMDIS** -- never put anything at ROM 7 there (on a 6128, both
  drove the bus).
* **ROM 7** on the 464 with the card is the card's disc ROM (Parados now).
  Don't use 7 for Lisp.
* **Background ROMs reserve workspace at init**, near the top of RAM, and
  `MEMORY`/HIMEM does not move it. Every ROM the card serves lowers the free
  RAM -- measure HIMEM rather than trusting the arithmetic.
* **ESC / break**: the firmware's own key scan raises the break event from
  the interrupt, whatever the program reads (KM_BREAK_EVENT &1C90 queues an
  &EF marker after the ESC key). BASIC handles it; **our OS must handle the
  break event itself**. Don't "cancel" it with KM DISARM BREAK (&BB48). Drain
  the key buffer before returning to the REPL.
* **&F8FF** (the generic peripheral reset) is written by the firmware at boot
  **and** when `RUN"` starts machine code (&05E9, &061C on the 464). It
  resets the card's PlayCity chips, not its speech or MIDI mode.
* **BASIC 1.0 vs 1.1** differ in more than syntax; a `|` in a BASIC comment
  breaks 1.0. Any BASIC loader shipped with this must run on a 464.
* **An ASCII BASIC file loads through BASIC's editor** and is slow (172 lines
  is about 20 s); keys typed meanwhile are swallowed into the load.

## The LambdaSpeak 4 card, as a development tool

Everything is in `~/git/lambdaspeak4` (README: *The USB console*,
*Building and flashing*; `docs/rom-emulation.md`; `rom/README.md`).

* **Upload a ROM with `tools/romloader.py`** (GUI). **Never hand-roll an
  uploader**: on 2026-11-03 one that skipped the idle wait desynced, and the
  console executed 16 KB of ROM as keystrokes -- renumbering slots, one to
  ROM 0. If a command-line upload is wanted, reuse romloader's `wait_idle()`
  and `send_rom()` exactly (`ROM<slot><num>`, 16384 bytes in 256-byte chunks
  12 ms apart, wait for `stored`).
* **`N<slot><number>`** on the console renumbers a slot without re-uploading
  (255 = silent). `n` lists the slots. **Giving a slot ROM 0 means the CPC
  boots into it every time** -- to get BASIC back, set it to 255. Check `n`
  before Mike powers on after any change.
* Slots (2026-11-07 night): 0 LISPLIB2 (ROM 5), 1 LISPVM (ROM 1), 2
  Parados (ROM 7), 3 LISPDEMO (ROM 3), 4 LISP core (ROM 0), 5 LISPLIB
  (ROM 4), 6 LS AI (ROM 2), 7 LISPLIB3 (ROM 6) -- the README's
  installation section has the table. All six Lisp ROMs must come from
  one build: re-flash them together. Flashed: build 1944 (0.96, the release; build 31443 before it,
  the same but for the version -- 2026-11-12, evening:
  dropping library functions, lazy loading, far arrays, the fixes found
  on the hardware -- load's environment, M:'s 512-byte buffer, the RAM
  disc's errors giving the buffer back; checked on the 464 with the
  Revaldinho card: flash disc 54's HWTEST.LSP, 8 yes and 2 after a
  reset); build 28423 before it; build 1797
  before it, 0.95: the incf and 512-639 read fixes, MIDI, (basic), the
  machine layer); `roms/` is still 25063 (2026-11-07 night: version 0.9, the banner's subtitle; build 22482
  before it, checked on the 464: the compiler -- the VM ROM in slot 1 as
  ROM 1, the .FAS junk fixed,
  compile, compile-file, disassemble -- on top of build 8423's catchable
  errors, format, types, file streams (checked on the 464 through
  Parados), the extended loop, the editor's fixes, string streams,
  |symbols|, ~<). Mike keeps the CPC off: flash each build that passes
  the tests on both machines, no need to ask. Slot 1 held the vector
  head: Mike, 2026-11-07, "the vector head can go ... use the space
  instead for common lisp". Everything may be replaced **except
  Parados and the LS AI ROM**. `tools/card.py lisp` re-flashes the six
  Lisp ROMs (it checks the CPC is off and refuses slots 2 and 6);
  `tools/card.py basic` silences the core. From the CPC (2026-11-12,
  Mike): `(basic [slot])` silences it and resets, `|BOOTLISP[,slot]`
  (library ROM 2's RSX, entry 1 of its name table) makes it ROM 0 and
  resets -- the card's `&D0 slot number` (|ROMNUM), sent from code
  copied to &4000 (mach/cpc/card.asm). MAME checks the bytes; for BASIC,
  run MAME by hand on the stock romset with LISP_EDIT=0xBD3A.
  `docs/hardware-test.txt` is the sheet of what to type on the real
  machine (and what was checked).
* **Before flash writes or a firmware flash, the CPC should be off.** Check
  with `kitloader.cpc_is_off()` (`~/git/lambdaspeak4/tools/kitloader.py`):
  two `d` readings with `/IORQ /RD /WR` all zero. Counters standing still do
  NOT mean it is off.
* **Discs**: `tools/mkcpcdisk.py` builds a DSK and an HFE; `tools/dskloader.py`
  puts a `.dsk` in a flash slot or the drive (`--list`, `--slot N`,
  `--load N`, `--get N`). Flash disc 8 is the 512K disc version, 14 the plain
  6128's, 54 the ROM version's test disc -- each byte for byte the
  one in `discs/` (2026-11-13, with APFEL.LSP added, read back) -- (HWTEST.LSP; 54 was a
  slideshow, Mike's to give: ~/claude/cpc/card-backup/
  slot54-slideshow-35.dsk). No slot is free. To test the disc versions
  the six Lisp ROM slots are silenced (`tools/card.py number SLOT 255`:
  4, 5, 0, 7, 3, 1) -- too many background ROMs leave the disc version's
  resident part no room ("Too many ROMs") -- and `tools/card.py lisp`
  puts them back (|BOOTLISP cannot: it is in a silenced ROM). The drive
  saves itself back into its slot when another disc is loaded: what a
  test wrote stays on that disc.
* **The Gotek serves a cached image**: after copying a disc to its stick,
  Mike must re-select it. **AMSDOS caches the catalogue** too.

## Working rules with Mike

* Concise reports; say what was verified and how.
* **Never crawl the NAS**: no `find`/`grep -r` from `/` or over all of
  `~`. Look in known places; `find <dir> -xdev` with a timeout if needed.
* GitHub: repo `lambdamikel/cpc-lisp-machine-os`, **public** since
  2026-11-07 (Mike: "make it public!"; private before). Push when work is
  committed. `roms/` holds our six ROM images, ready to use (Mike: "not
  everybody wants to make their own"): copy them from `build/` -- one
  tested build -- when a release changes, and say the build in
  `roms/README.md`. Never commit Amstrad's ROMs (the MAME romsets in
  `build/mame`) or disc images -- except the two LDOS system discs the
  TRS-80 build starts from (`tools/trs80/ldos-m1.dsk`, `ldos-m3.dsk`:
  Mike, 2026-11-12, "publish them"), LS-DOS 6.3.1's (`discs/ld4-631.dsk`,
  and the FreHD base `tools/trs80m4/ls631-frehd.hdv.gz`: Mike, 2026-11-13,
  "put ldos under discs"), and our own discs in `discs/` (the
  disc versions and the hardware test discs: Mike, 2026-11-12, "add the
  hw test disks to the repo"; copy them from one tested build, and say
  the build in `discs/README.md`); `build/` is ignored. **GPL-3.0** since 2026-11-07 (`LICENSE`, Mike's
  choice, as LambdaSpeak 4), with a section 7 permission: programs
  written in CPC Lisp, and what `save`/`compile-file` make, are their
  authors' own (README, *Licence*). **Releases**: GitHub release `v0.9`
  = build 25063, the six ROMs and `cpc-lisp-0.9.zip` (the ROMs,
  `roms/README.md`, `LICENSE`); `v0.95` (2026-11-12) = build 1797, the
  same files, and the TRS-80 discs (`cpc-lisp-0.95-trs80-model1/3`,
  `.dsk` and `.hfe`, TRS-80 build 1685, replaced the same day by build 9066:
  the editor's SHIFT down-arrow S/C, `(reset)` to LDOS); `v0.96`
  (2026-11-12, evening) = ROMs build 1944, the disc versions
  `cpclisp512.dsk` (1975) and `cpclisp6128.dsk` (2538), the ROMs' test
  disc `cpclisp-hwtest.dsk`, `cpc-lisp-0.96.zip`, and the TRS-80 discs
  (`cpc-lisp-0.96-trs80-model1/3`, `.dsk` and `.hfe`, build 3059) --
  the same files as `roms/` and `discs/`. A new one: refresh `roms/` from one
  tested build, bump the version (banner, ROM headers, document
  titles), tag, `gh release create` with the same files.
* Commit with the attribution lines the session gives you.
