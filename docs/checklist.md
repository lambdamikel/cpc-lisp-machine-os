# CPC Lisp: what is done, what is to come

Version 0.3, 2026-11-07. Ticked items are built and covered by the regression
tests in MAME on a 464 and a 6128 (`tools/test.sh`) unless they say
otherwise. `docs/cpc-test.txt` is the sheet for trying it on a real CPC.

## The machine

- [x] Core ROM at ROM 0 replaces BASIC: the CPC boots into `LISP>`
- [x] Calls the firmware only through its vectors; knows the 464 and the
      664/6128 jump blocks apart
- [x] Starts the background ROMs itself (KL ROM WALK), so the disc ROM
      (AMSDOS, Parados) works
- [x] Library ROMs (three, and the demo ROM): up to four, at any ROM numbers 1-6, in any order, found
      by signature and build number. Any of them may be missing; their
      functions are then undefined, and the core alone still works.
- [x] Library names cost nothing until used; functions written in Lisp are
      read from the ROM on first use (autoload)
- [x] Runs on the 464 and the 6128 in MAME, with and without a disc drive
- [x] Flashed to the LambdaSpeak 4 card (`tools/card.py`), checksums verified
- [x] The real 464 (2026-11-07, build 6078 on the LambdaSpeak 4 card):
      boots to `LISP>`, speech and singing, PlayCity, disc through Parados,
      ESC, and `(fib 17)` in about 13 s -- as in MAME
- [ ] `|LISP` from BASIC, with the core at a ROM number other than 0: built
      in, not tried yet
- [ ] Real 6128, 664: not tried

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
- [x] ESC breaks any running program, including loops over circular lists
- [x] Mark-and-sweep garbage collector; about 7000 cells of 4 bytes, 512
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
      characters, vectors (one-dimensional), closures, built-in functions

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
`block` `return-from` `return` `catch` `throw` `dolist` `dotimes` `loop`
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
- **Characters, strings, vectors:** `char-code` `code-char` `char` `string`
  `make-array` (`:initial-element`) `vector` `aref` `svref` `elt`
- **Input, output, evaluation:** `print` `prin1` `princ` `terpri`
  `write-char` `read` `eval` `error`
- **System:** `gc`

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
- **Characters:** `char=` `char/=` `char<` `char>` `char<=` `char>=`
  `char-equal` `char-not-equal` `char-lessp` `char-greaterp`
  `char-not-greaterp` `char-not-lessp` (any number of arguments),
  `alpha-char-p` `upper-case-p` `lower-case-p` `both-case-p`
  `alphanumericp` `graphic-char-p` `digit-char-p` `digit-char`
- **Printing to and from strings:** `pprint` `prin1-to-string`
  `princ-to-string` `read-from-string`
- **Input and output, CL's names:** `read-line` `read-char`
  `read-char-no-hang` `peek-char` `unread-char` `listen` `write`
  `write-string` `write-line` `fresh-line`
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
- **Output:** `format` with `t` or `nil`: `~A` `~S` `~D` `~C` `~%` `~&` `~~`,
  with widths. The CPC has no `~` key: it is **CTRL + 2** (the firmware's
  own key table; in MAME, Right Alt + 2)
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
- **Music:** `note` (`'c4` is middle C, 239, `'a4` 440 Hz, 142 -- the AY
  runs at 1 MHz; `#` sharp, `B` flat), `play` (a list of notes, `R` a rest, `(G4 40)` a
  longer one)
- **Macros:** `pushnew` `psetq` `do` `do*`; the variable `*features*`
- **Multiple values:** `multiple-value-bind` `nth-value`
  `multiple-value-call` `multiple-value-prog1` `multiple-value-setq`
  `values-list`
- **Structures, hash tables, types:** `defstruct` `defsetf`
  `make-hash-table` `clrhash` `maphash` `hash-table-count`
  `hash-table-p` `hash-table-test` `type-of` `typep`

### The demo ROM

`(demo)` lists them: `shapes` `rose` `spiral` `moire` `bounce`
`sierpinski` `sketch` `koch` (the Koch snowflake) `tree` `tune` `talk`
`sing` `chords` (PlayCity) `hanoi` `queens` `primes` `fact`. They are
Lisp text in the ROM, read when first called, so `(ed 'rose)` shows one.

## Tools

- [x] `tools/build.sh`: the three ROMs, and MAME romsets with the core at ROM 0
- [x] `tools/test.sh`: 24 regression tests, on a 464 or a 6128
- [x] `tools/run.sh`: type a file at the REPL in MAME; screenshots,
      timings, an instruction profile (`tools/profile.py`)
- [x] `tools/mame.sh`: a MAME window to play in, with a disc
- [x] `tools/card.py`: the ROMs onto the LambdaSpeak 4 card

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
   - [ ] `apply` and `mapcar` without the general `bind`
   - [ ] More from the profiler (the core has ~840 bytes free again: some
         rarely used functions moved to library ROM 2)
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
   - [ ] `|...|` symbols in the reader
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
       and macro, the editors' keys, the differences from Common Lisp
8. [ ] Later, maybe: `*print-case*`; a byte-code compiler
