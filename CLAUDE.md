# CPC Lisp 0.95 — working notes for Claude

*A Lisp machine for the Amstrad CPC.* Version 0.95 since 2026-11-12, 0.9 from 2026-11-07 (the
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
  below, is no part). Space (2026-11-12): core 22 bytes free,
  parts 0-3 251, 3489, 636, 3103; the VM ROM 574.
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
| hxcfe (HFE images) | `~/claude/midi80/toolchain/hxc/build/hxcfe` |
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
  one build: re-flash them together. Flashed: build 1797 (2026-11-12,
  0.95: the incf and 512-639 read fixes, MIDI, (basic), the
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
  `--load N`, `--get N`). Free flash disc slots: 8, 14, 50-54.
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
  Mike, 2026-11-12, "publish them"); `build/` is ignored. **GPL-3.0** since 2026-11-07 (`LICENSE`, Mike's
  choice, as LambdaSpeak 4), with a section 7 permission: programs
  written in CPC Lisp, and what `save`/`compile-file` make, are their
  authors' own (README, *Licence*). **Releases**: GitHub release `v0.9`
  = build 25063, the six ROMs and `cpc-lisp-0.9.zip` (the ROMs,
  `roms/README.md`, `LICENSE`); `v0.95` (2026-11-12) = build 1797, the
  same files, and the TRS-80 discs (`cpc-lisp-0.95-trs80-model1/3`,
  `.dsk` and `.hfe`, TRS-80 build 1685, replaced the same day by build 9066:
  the editor's SHIFT down-arrow S/C, `(reset)` to LDOS). A new one: refresh `roms/` from one
  tested build, bump the version (banner, ROM headers, document
  titles), tag, `gh release create` with the same files.
* Commit with the attribution lines the session gives you.
