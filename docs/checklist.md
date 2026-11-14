# CPC Lisp 0.96 -- what is done, what is to come

*A Lisp machine for the Amstrad CPC*

Version 0.96, 2026-11-12. Ticked items are built and covered by the regression
tests in MAME on a 464 and a 6128 (`tools/test.sh`) unless they say
otherwise. `docs/hardware-test.txt` is the sheet for trying it on a real
CPC; the README says how to install the ROMs.

## The machine

- [x] Core ROM at ROM 0 replaces BASIC: the CPC boots into `LISP>`
- [x] Calls the firmware only through its vectors; knows the 464 and the
      664/6128 jump blocks apart
- [x] Starts the background ROMs itself (KL ROM WALK), so the disc ROM
      (AMSDOS, Parados) works
- [x] Five library ROMs -- four parts (library 1-3 and the demo ROM) and
      the VM ROM -- at any ROM numbers 1-6, in any order, found by
      signature and build number. Any of them may be missing; their
      functions are then undefined, and the core alone still works.
- [x] Library names cost nothing until used; functions written in Lisp are
      read from the ROM on first use (autoload)
- [x] Runs on the 464 and the 6128 in MAME, with and without a disc drive;
      the disc tests run under AMSDOS (the 6128's own, a DDI-1 on the 464)
- [x] Flashed to the LambdaSpeak 4 card (`tools/card.py`), checksums verified
- [x] The real 464 (2026-11-07, build 6078 on the LambdaSpeak 4 card):
      boots to `LISP>`, speech and singing, PlayCity, disc through Parados,
      ESC, and `(fib 17)` in about 13 s -- as in MAME
- [ ] `|LISP` from BASIC, with the core at a ROM number other than 0: built
      in, not tried yet
- [x] The 664/6128 firmware (BASIC 1.1) on the real 464 (2026-11-07,
      build 22482): floats through its maths package, the line editor,
      ESC, the compiler, Parados -- and the RAM disc `M:` on a RAM
      expansion, under the 1.0 firmware too
- [ ] A real 6128, 664: not tried

## The language (Common Lisp syntax and semantics where they fit)

- [x] Lisp-2: functions and values apart, `#'`, `funcall`, `apply`
- [x] Lexical closures; special (dynamic) variables with `defvar`,
      `defparameter`, `defconstant`
- [x] Proper tail calls: tail-recursive loops run in constant stack
- [x] `defmacro`, backquote with `,` and `,@`, `macroexpand`, `macroexpand-1`
- [x] Lambda lists: `&optional` (defaults, supplied-p), `&rest`, `&body`,
      `&key` (defaults, `((:keyword var))`, unknown keys ignored), `&aux`,
      destructuring
- [x] `block`, `return-from`, `return`, `catch`, `throw`, `unwind-protect`
      (its cleanups run however the form is left: a throw, an error, ESC)
- [x] `flet`, `labels`
- [x] `setf` on `car` `cdr` `first` `rest` `second` `cadr` `nth`
      `symbol-value` `symbol-function` `symbol-plist` `get` `char` `aref`
      `svref`, and on variables; `incf`, `decf`, `push`, `pop` on places
- [x] Integers are 15 bits (-16384..16383); a result that overflows becomes a
      float, so `(* 200 200)` is `40000.0`; `round` takes halves to the
      even integer, as CL
- [x] Floats: the firmware's 5-byte reals, about nine digits
- [x] Errors print a message and the object and return to `LISP>`; the stack
      is checked for overflow
- [x] Errors can be caught: `ignore-errors`, `handler-case`; `error` with a
      format string, `warn`, `assert`
- [x] ESC breaks any running program, including loops over circular lists
- [x] Mark-and-sweep garbage collector; about 6400-6660 cells of 4 bytes, 512
      symbols, strings and vectors in a compacted block space
- [x] Multiple values: `values`, `multiple-value-list` (built in),
      `multiple-value-bind`, `nth-value`, `multiple-value-call`,
      `multiple-value-prog1`, `multiple-value-setq`, `values-list`; `floor`
      `truncate` `round` `ceiling` return the remainder too, and the REPL
      prints every value
- [x] `defstruct` (`:conc-name`, `:constructor`, `:predicate`, `:copier`,
      slot defaults; accessors work with `setf`; instances print as
      `#S(POINT 1 2)`), `copy-structure`, `type-of`, `typep`
- [x] Hash tables: `make-hash-table` (`:test` `eq` `eql` `equal`, `:size`),
      `gethash` (two values, `setf`), `remhash`, `clrhash`, `maphash`,
      `hash-table-count`, `hash-table-p`, `sxhash`
- [x] `defsetf`: `setf` on places the library or the user defines
- [ ] `*print-case*` (all output is upper case, as in CL)

### Data types

- [x] Integers, floats, symbols, keywords, conses and lists, strings,
      characters, vectors (one-dimensional), structures, hash tables,
      closures, compiled functions, built-in functions

### The reader and printer

- [x] `'` `` ` `` `,` `,@` `#'` `#(...)` `#\a` (and `#\Space` `#\Newline`
      `#\Tab` `#\Return` `#\Linefeed` `#\Page` `#\Backspace` `#\Escape`
      `#\Rubout` `#\Nul`), `#x` `#b`, strings with `\` escapes, `;` and
      `#| |#` comments, dotted pairs
- [x] Symbols are upcased; `prin1` writes what `read` reads back

### The REPL

- [x] `*`, `**`, `***`: the last three values printed
- [x] Line editor: `)` shows its `(`, an unmatched one beeps;
      continuation lines are indented Lisp-style; TAB; cursor up brings back
      the last line; SHIFT + arrows and COPY as on the CPC
- [x] Function editor: `(ed 'name)` shows a definition pretty-printed on a
      full screen; COPY or CTRL-S reads it back, ESC leaves it; `(ed)`
      reopens the last text. SHIFT + up/down a page, CTRL + up/down the
      top/bottom, CTRL + left/right the start/end of a line

## Built-in functions

### Core ROM: special forms

`quote` `function` `lambda` `if` `when` `unless` `cond` `case` `and` `or`
`progn` `prog1` `setq` `setf` `incf` `decf` `push` `pop` `let` `let*`
`flet` `labels` `defun` `defmacro` `defvar` `defparameter` `defconstant`
`block` `return-from` `return` `catch` `throw` `dolist` `dotimes` `%loop`
`declare` `the` `unwind-protect` `multiple-value-list`

### Core ROM: functions

- **Lists:** `car` `cdr` `first` `rest` `second` `third` `caar` `cadr` `cdar`
  `cddr` `caddr` `cdddr` `cons` `list` `list*` `append` `length` `nth`
  `nthcdr` `last` `rplaca` `rplacd`
- **Functions:** `mapcar` `mapc` `apply` `funcall`
- **Predicates:** `null` `not` `atom` `consp` `listp` `symbolp` `numberp`
  `integerp` `stringp` `characterp` `functionp` `keywordp` `vectorp` `eq`
  `eql` `equal`
- **Numbers:** `+` `-` `*` `1+` `1-` `truncate` `floor` `mod` `rem` `abs`
  `max` `min` `<` `>` `<=` `>=` `=` `/=` `zerop` `plusp` `minusp` `evenp`
  `oddp` `random`
- **Symbols:** `symbol-name` `symbol-value` `symbol-function` `symbol-plist`
  `set` `boundp` `fboundp` `makunbound` `fmakunbound` `get`
- **Characters, strings, vectors:** `char-code` `char` `string`
  `aref` `svref` `elt`
- **Evaluation:** `eval` `macroexpand` `macroexpand-1`
- **System:** `gc`, and the variables `*standard-output*`, `*` `**` `***`

### Library ROM 1

- **Text screen:** `cls` `mode` `locate` `pen` `paper` `ink` (with a second
  colour, flashing) `border` `reset` `window` (BASIC's WINDOW) `tag` (text
  at the graphics cursor) `transparent` `flash-speed` (SPEED INK)
  `text-cursor` (POS and VPOS)
- **Graphics:** `plot` `plotr` `draw` `drawr` `move` `mover` `test` `testr`
  `origin` `clg` `graphics-pen` `graphics-paper` `xpos` `ypos`, and
  `circle` `disc` (filled) `box` `fill-box` `ink-mode` (0 normal, 1 XOR,
  2 AND, 3 OR, as BASIC 1.1's) `flood-fill` `symbol` (user-defined
  characters 240-255)
- **Sound:** `sound` (channels, period, duration, volume, envelopes, noise:
  BASIC's SOUND), `envelope` (ENV) `tone-envelope` (ENT, negative number
  repeats) `release` `sound-check` (SQ) `sound-hold` `sound-continue`
- **Turtle graphics:** `forward` `back` `left` `right` `pen-up`
  `pen-down` `home` `set-position` `set-heading` `turtle-position`
  `heading` (native, a sine table, positions to 1/256)
- **Keys, time, the machine:** `inkey` `wait-key` `key-down-p` `joystick`
  `frame` `time` `peek` `poke` (all 64 KB of RAM: `#xC000` reads as a
  float, which addresses take)
- **Strings:** `string-upcase` `string-downcase` `string-capitalize`
  `char-upcase` `char-downcase` `string-trim` `string-left-trim`
  `string-right-trim` `make-string` `parse-integer` `nreconc`
- **String comparisons** (strings, symbols or characters; the index where
  they differ, as in CL): `string=` `string/=` `string<` `string>`
  `string<=` `string>=` `string-equal` `string-not-equal` `string-lessp`
  `string-greaterp` `string-not-greaterp` `string-not-lessp`
- **Characters:** `code-char` `char=` `char/=` `char<` `char>` `char<=` `char>=`
  `char-equal` `char-not-equal` `char-lessp` `char-greaterp`
  `char-not-greaterp` `char-not-lessp` (any number of arguments),
  `alpha-char-p` `upper-case-p` `lower-case-p` `both-case-p`
  `alphanumericp` `graphic-char-p` `digit-char-p` `digit-char`
- **Printing to and from strings:** `pprint` `prin1-to-string`
  `princ-to-string` `read-from-string`
- **Input and output, with a stream argument** (`lib/streams.asm`; the
  screen and keyboard, or a file): `print` `prin1` `princ` `terpri`
  `write-char` `write-string` `write-line` `fresh-line` `pprint`; `read`
  `read-line` `read-char` `read-char-no-hang` `peek-char` `unread-char`
  `listen`, with `eof-error-p` and `eof-value`; `write`
- **Function editor:** `ed`
- **Files** (through the firmware's cassette vectors, so with any disc ROM;
  tested with AMSDOS in MAME, tape not tried): `load`, `save` (what you
  defined, or the symbols named, pretty-printed), `dir`, `delete-file`
- **RAM disc** on a 6128: drive `M:` in the second 64 KB, for `load`,
  `save`, `(dir "m:")` and `delete-file`; it survives a reset, not a
  power-off. On a 464 an `M:` name says there is none.

### Library ROM 2

- **Floats:** `/` `round` `ceiling` `float` `floatp` `sqrt` `exp` `sin` `cos`
  `tan` `log` `atan` `expt` and the constant `pi`
- **Output:** `format` to `t`, `nil` or a stream, with CL's directives: `~A` `~S`
  `~D` `~B` `~O` `~X` `~R` (radix, words, ordinals, Roman) `~F` `~E` `~G`
  `~$` `~C` `~P` `~%` `~&` `~|` `~~` `~T` `~*` `~?` `~{~}` `~[~;~]` `~(~)`
  `~^` `~<~>` and `~` newline, with parameters (`V`, `#`, `'c`) and the
  `:` `@` modifiers. The CPC has no `~` key: it is **CTRL + 2**
  (the firmware's own key table; in MAME, Right Alt + 2)
- **Sorting:** `sort`, `stable-sort` (lists and vectors, `:key`)
- **Lists:** `member` `assoc` `rassoc` (with `:test`, `:test-not`, `:key`),
  `reverse` `nreverse` (lists, strings, vectors)
- **Sequences:** `find` `position` `count` `remove` `delete` `substitute`
  `nsubstitute`, each with `-if` and `-if-not`: lists, strings, vectors;
  `:test` `:test-not` `:key` `:start` `:end` `:from-end` `:count`
- **Conversion:** `coerce` (to `list`, `vector`, `string`, `character`,
  `float`)
- **Bits:** `logand` `logior` `logxor` `lognot` `ash`
- **Multiple values:** `values`
- **Vectors:** `make-array` (`:initial-element`) `vector`
- **Structures and hashing:** `copy-structure` `gethash` `remhash` `sxhash`
  (and the `%` functions `defstruct` and the hash tables use)
- **Symbols, system:** `gensym` `intern` `remprop` `room`
- **The LambdaSpeak card:** `say` (DECtalk; it sings too) `speech-stop`
  `speech-voice` `speech-rate` `speech-volume`; PlayCity: `playcity`
  `pc-tone` (six channels) `pc-off`

### Library ROM 3: written in Lisp

Read from the ROM the first time each is used. The sequence functions take
lists, strings and vectors, and `:test`, `:test-not`, `:key` (and
`:count` for the removes).

- **Sequences:** `remove-duplicates` `delete-duplicates` `search`
  `subseq` `copy-seq` `concatenate` `fill` `map` `reduce` (`:key`
  `:from-end` `:initial-value`) `every` `some` `notany` `notevery` (any
  number of sequences)
- **Lists:** `identity` `complement` `nconc` `copy-list` `make-list`
  `butlast` `acons` `pairlis` `subst` `member-if` `member-if-not`
  `assoc-if` `rassoc-if` `mapcan` `maplist` `adjoin` `union`
  `intersection` `set-difference` `subsetp`
- **Numbers:** `expt` `gcd` `signum`
- **Questions:** `y-or-n-p` `yes-or-no-p`
- **Errors:** `error` `warn` `assert` `ignore-errors` `handler-case`
- **Files as streams:** `open` `close` `with-open-file` `probe-file`
- **Music:** `note` (`'c4` is middle C, 239, `'a4` 440 Hz, 142 -- the AY
  runs at 1 MHz; `#` sharp, `B` flat), `play` (a list of notes, `R` a rest, `(G4 40)` a
  longer one)
- **Macros:** `pushnew` `psetq` `do` `do*`; the variable `*features*`
- **Multiple values:** `multiple-value-bind` `nth-value`
  `multiple-value-call` `multiple-value-prog1` `multiple-value-setq`
  `values-list`
- **Structures, hash tables, types:** `defstruct` `defsetf`
  `make-hash-table` `clrhash` `maphash` `hash-table-count`
  `hash-table-p` `hash-table-test` `type-of` `typep` (compound types:
  `or` `and` `not` `member` `eql` `satisfies` `mod`, ranges) `deftype`
  `check-type` `typecase` `etypecase`

### The demo ROM

- **`loop`**, simple and extended (its expander native), `loop-finish`,
  `endp`
- **String streams:** `with-output-to-string` `make-string-output-stream`
  `get-output-stream-string` `with-input-from-string`
  `make-string-input-stream` `streamp` `input-stream-p` `output-stream-p`
  `open-stream-p`
- What compiled code calls for `catch`, `throw`, `unwind-protect` and some
  `setf` places (`%catch`, `%set-aref`...)
- **The demos:** `(demo)` lists them: `shapes` `rose` `spiral` `moire`
  `bounce` `sierpinski` `sketch` `koch` (the Koch snowflake) `tree` `tune`
  `talk` `sing` `chords` (PlayCity) `hanoi` `queens` `primes` `fact`.
  They are Lisp text in the ROM, read when first called, so `(ed 'rose)`
  shows one.

### The VM ROM

`compile` `compile-file` `disassemble`, and the machine that runs
compiled code (`docs/design.md` describes both)

## Tools

- [x] `tools/build.sh`: the six ROMs, and MAME romsets with the core at ROM 0
- [x] `tools/bootstrap.py`: the compiler compiled by itself, for the VM ROM;
      `tools/mklib.py`: the library ROMs' symbol tables
- [x] `tools/test.sh`: 34 regression tests, on a 464 or a 6128
- [x] `tools/run.sh`: type a file at the REPL in MAME; screenshots,
      timings, an instruction profile (`tools/profile.py`)
- [x] `tools/mame.sh`: a MAME window to play in, with a disc
- [x] `tools/card.py`: the ROMs onto the LambdaSpeak 4 card
- [x] `BUILD_ID=n tools/build.sh`: a fixed build number, so two builds can
      be compared byte for byte; `MACH=<machine>` picks `mach/<machine>/`

## Still to come, in this order

1. [x] **The real 464**: it all checks out (2026-11-07)
2. [ ] **Speed**
   - [x] Arguments that are constants or variables skip `eval`; `+` `-`
         and comparisons have a fast path for two integers; ESC is checked
         once per function body; plain lambda lists are bound straight
         from the stack. Together: `(fib 17)` 1103 → 641 frames, `sort` ~7×
   - [x] ESC: a tap that falls inside a garbage collection is caught too
   - [x] `funcall` without building an argument list (28% faster on a
         built-in, 11% on a closure)
   - [x] `apply`, `mapcar`, `funcall` (as a function) and the library's
         calls (sort's predicate, `:test`, `:key`) lay calls out on the
         stack: no argument lists. Closures through `mapcar` a third
         faster, builtins twice, `apply` of a lambda 3.3x, `sort` 40%;
         a multiply that stops when the smaller factor runs out
   - [x] The compiler (below): 3-9x on compiled code
   - [ ] More from the profiler (the ROMs are nearly full: the core has
         10 bytes free, the VM ROM 574)
   - [x] `pprint` fills data -- a list that is not a call, and anything
         quoted -- as many to a line as fit: saved data a third the size
   - [x] `do` expands to special forms only (it used `psetq`, a macro,
         expanded again on every pass): loops with `do` 4-5x faster
   - [x] A macro call keeps its expansion (displacing macros): a user
         macro in a loop 2.4x faster
3. [x] **The 6128's extra 64 KB**: a RAM disc, drive `M:`
4. [ ] **More Common Lisp**
   - [x] `string<` `string>` `string-equal` and the other string comparisons;
         `char=` `char<` `char-equal` and the other character comparisons;
         the character predicates
   - [x] More strings: `string-trim` (left, right), `string-capitalize`,
         `make-string`; `search`, `position`, `find` on strings
   - [x] `coerce`
   - [x] `:test`, `:test-not` and `:key` on `member`, `assoc`, `rassoc`,
         `remove`, `find`, `position`, `count` and the rest; the sequence
         functions on lists, strings and vectors; `map`, `remove-duplicates`,
         `substitute`, `fill`
   - [x] `:start`, `:end`, `:from-end`, `:count` on find, position, count,
         remove, delete, substitute (native now: 4-14x faster)
   - [x] Multiple values
   - [x] `defstruct`, hash tables, `defsetf`, `type-of`, `typep`
   - [x] Errors can be caught (`ignore-errors`, `handler-case`);
         `unwind-protect`'s cleanups run on errors and ESC too
   - [x] `format`: all of CL's directives, `~<...~>` justification too
   - [x] Files as streams: `open`, `close`, `with-open-file`,
         `probe-file`; every printer and reader (and `format`) takes a
         stream; an input and an output file at once (block space is 11/64
         of the heap now, room for both buffers)
   - [x] The extended `loop`: `for` (in, on, across, from/to/below/
         downto/by, =/then, hash-keys), `with`, `repeat`, `while`,
         `until`, `collect` `append` `nconc` `sum` `count` `maximize`
         `minimize` (`into`), `do`, `when`/`if`/`unless`/`else`/`and`,
         `return`, `always` `never` `thereis`, `initially` `finally`,
         `named`, destructuring -- expanded by native code (the demo
         ROM) once
   - [x] String streams (`with-output-to-string`,
         `with-input-from-string`, `make-string-output-stream`...) and
         `*standard-output*` (printers without a stream, `format t`)
   - [x] `|...|` and `\` in symbols; `prin1` puts bars round a name that
         needs them (and `make-array` moved to library ROM 2 for room)
5. [x] **More graphics and sound**: circles, discs, boxes, XOR drawing,
       text windows, text at the graphics cursor, envelopes, the sound
       queue, notes and `play`, joystick, `peek`/`poke`
   - [x] Turtle graphics, native; the Koch snowflake and a tree in the
         demos
   - [x] PlayCity's six channels (on the card: `(playcity t)`), checked
         in MAME by recording and measuring the notes; LambdaSpeak speech
         and singing (`say`)
   - [x] User-defined characters (`symbol`, 240-255) and `flood-fill`
         (a paint bucket of its own: the 464's firmware has no fill)
6. [x] **A demo ROM** with example programs: `(demo)` lists them --
       pictures (shapes, a rose in floats, a spiral, XOR moire, a bouncing
       ball, the chaos game, a sketcher on the cursor keys), Ode to Joy,
       Hanoi, n queens, a sieve, 20!
7. [x] **A reference manual**: `docs/reference.md` -- every function, form
       and macro, the editors' keys, the differences from Common Lisp;
       a tutorial (`docs/tutorial.md`), the design (`docs/design.md`), and
       how to install the ROMs (the README)
8. [x] **A byte-code compiler**: `compile`, `compile-file`,
       `disassemble` -- the VM ROM (lib/vm.asm, the sixth ROM) runs the
       code; the compiler (lib/compiler.lsp) is compiled by itself at
       build time (tools/bootstrap.py) and runs from that ROM too
   - [ ] `save` of compiled functions; `ed` of them
9. [ ] Later, maybe: `*print-case*`
10. [ ] **Other Z80 machines** (Mike, 2026-11-11), in this order: the
        TRS-80 Model I and III with X-MEM/80, the ZX Spectrum
        128/+2/+3, the TRS-80 Model 4, MSX1, the TA alphatronic PC and
        the Sharp MZ-700 (these two need banked memory added)
    - [x] The machine layer: everything CPC-specific in `mach/cpc/`
          behind an interface (`mach/README.md`); the CPC's ROMs byte for
          byte what they were (2026-11-11)
    - [x] TRS-80 Model I with X-MEM/80, in trs80gp (branch `trs80`,
          `mach/trs80/README.md`): the language, compiler, editors,
          floats (through the ROM), files and `dir` through LDOS,
          graphics in blocks, sound on the cassette port, the demos;
          speech through Talker/80; the RAM disc `M:` in X-MEM/80's
          spare pages, `delete-file`; `flood-fill`; the images
          compressed onto one Model I disc; `(time)` from LDOS's ticks;
          MIDI through MIDI/80 (2026-11-12)
    - [x] The Model III, real, with X-MEM/80, Talker/80 (speech and
          singing) and MIDI/80 (2026-11-12)
    - [x] The Model I, real, with X-MEM/80 (2026-11-12, from the HxC: it
          runs; the clock, (sleep 2) 675 the first time -- the definition
          read too)
    - [x] On the Model I: MIDI/80 and sound
    - [x] On the Model I: Talker/80, with its U1 reprogrammed
          (Talker80-decoder-xmem.jed: the original decoder answers
          X-MEM/80's ports 64-67 too)
11. [x] **MIDI** (Mike, 2026-11-12): `midi-note`, `midi-program`,
        `midi-control`, `midi-panic`, `midi-out`, `midi-off`, `sleep`,
        and the `(midi-tune)` demo -- the LambdaSpeak card's MIDI mode
        on a CPC, MIDI/80 on a TRS-80; the bytes checked in MAME
        (test/card.lsp) and trs80gp; `(midi-tune)` heard on the real 464
        through the card (2026-11-12); MIDI/80 not tried yet
12. [x] **CPC Lisp from disc** (Mike, 2026-11-12): with a **512K
        expansion** (`mach/cpc512`: the six images in the expansion's
        banks, the compiler, a RAM disc of 415 KB) and on a **plain
        6128** (`mach/cpc6128`: no compiler, no RAM disc); both checked
        on the real 464 with Revaldinho's 512K card in DIP configuration
        4 (`HWTEST.LSP` on their discs, all yes)
13. [x] **More memory for programs** (Mike, 2026-11-12: "can some of the
        extra memory ... be used for lisp programs?"):
    - [x] Library functions dropped when the cells run out, read in again
          when next called (every version)
    - [x] `(load "big" :lazy t)`: a program's functions read from the file
          when first called, dropped like the library's; CL's
          `file-position`
    - [x] Far arrays on the RAM disc: `make-far-array`, `far-array`,
          `far-ref`, `far-length` (ROMs, 512K, TRS-80)
    - [x] Checked on the real 464: the 512K disc version and the ROMs
          with Revaldinho's card (the test discs in `discs/`)
    - [x] TRS-80, real (the Model III with X-MEM/80, 2026-11-12): far
          arrays, lazy loading, the RAM disc past 256 KB -- with X-MEM/80
          in its 16 KB mode (in 32 KB mode it has 16 page numbers, and
          the RAM disc keeps to 112 KB since)
    - [ ] A write error inside `%catch-errors` (`ignore-errors`,
          `handler-case`) -- a full disc -- leaves the output file marked
          open until toplevel, so every later `open` in the same form
          fails; save's and putc's error paths could abandon it first
    - [ ] Maybe: a faster fill for `make-far-array` (each byte goes
          through the RAM disc's putc: 390 KB took minutes); the 512K
          card's shadow modes (skip the missing bank 3); far arrays
          beyond 65535 elements; more string space on the disc versions
14. [ ] **The TRS-80 Model 4, native** (Mike, 2026-11-12: next, before the
        Spectrum). Mike's machine: a Model 4 (not 4P/4D), 128 KB, LS-DOS
        6.3.1, a FreHD, Ian Mavric's "Improved Grafyx" board.
    - [x] In trs80gp (branch `trs80m4`, 2026-11-13,
          `mach/trs80m4/README.md`): six images in slots of the three
          32 KB banks (parts at &8000 or &C000: LIB_MIXED, liborgs), a
          resident part at &2600 (banks, the LS-DOS gate, the jumpblock,
          a clock task), the Lisp's RAM in the lower 32 KB beside
          LS-DOS -- about 1900 cells, 2.7 KB of strings; 80 x 24 text in
          map-2 windows; floats through the Model III ROM in map-0
          windows (a 4P without it says so); files through LS-DOS 6's
          SVCs; graphics on the hi-res board, 640 x 240 (`hires.asm`);
          the speaker; BREAK. The suite passes in trs80gp
          (`tools/trs80m4/test.sh`, `test/*.trs80m4.out`,
          `test/skip.trs80m4`); `mach/trs80m4/hwtest.lsp` 8 yes
    - [x] The discs (2026-11-13, Mike: "a FreHD version and a Gotek /
          HxC version"): `lisp-m4.dsk` and `.hfe`, and `lisp-m4.hdv`, a
          bootable LS-DOS 6.3.1 hard disc for the FreHD's menu
          (`tools/trs80m4/mkhdv.py`); hwtest 8 yes from both in trs80gp.
          In `discs/`, with LS-DOS 6.3.1's own disc (Mike: "put ldos
          under discs")
    - [x] On the real Model 4 (2026-11-13): the FreHD menu, LISP loads
          -- then a black screen: bit 1 of &83 is the Grafyx's "no
          text". Fixed (0); trs80gp -gt -gg -gc show the text
    - [x] On the real Model 4 (2026-11-13, Mike): hwtest 8 yes from the
          FreHD (build 25495) with the Improved Grafyx -- the text over
          the graphics; the editor works, F1 confirms. Asked for and
          added: F2 delete, F3 backspace, the SHIFT down-arrow table in
          the Model 4's docs (CTRL , is no `[` under LS-DOS)
    - [x] The Apfelmaennchen (Mike: "can you add an appleman program",
          and for the CPC in mode 2): `examples/apfel.lsp` on the CPC
          discs and the Model 4's -- fixnums times 64, coarse to fine,
          compiled where there is a compiler (11 min on a 464). On the
          way: fill-box on the Model 4 left every fifth pixel row out
          (it stepped 2 units, a CPC row): M_NEXTY steps there
    - [x] On the real Model 4 (2026-11-13, Mike): `(tune)` on the
          speaker, `(say)` through Talker/80, the graphics -- "the
          graphics are nice"
    - [ ] On the real Model 4: from the HxC (`cpclisp4_JV3.hfe`); MIDI
          through MIDI/80 (untried); `(apfel)` there
    - [ ] More room: the heap in the upper 32 KB and the code in the
          lower (OPREG's bit 6 puts banks 1 and 2 there) would about
          double it -- the core's "a SUBR is at &C000 and up" tests,
          interrupts with LS-DOS's low memory out, the ROM's RAM at
          &4000
    - [ ] No compiler (no seventh slot), no RAM disc yet
15. [ ] **The ZX Spectrum +2 with DivMMC** (Mike's: a +2, not a +3): the
        128's banks 0, 1, 3, 4, 6, 7 at &C000 for the six images; files
        through esxDOS; the DivMMC's own RAM for M: and far arrays,
        maybe. To find out: grey +2 or +2A/B, the DivMMC's RAM, the
        esxDOS version, an emulator with DivMMC that can be scripted.

