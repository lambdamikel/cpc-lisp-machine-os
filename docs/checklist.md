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
- [x] Library ROMs: up to four, at any ROM numbers 1-6, in any order, found
      by signature and build number. Any of them may be missing; their
      functions are then undefined, and the core alone still works.
- [x] Library names cost nothing until used; functions written in Lisp are
      read from the ROM on first use (autoload)
- [x] Runs on the 464 and the 6128 in MAME, with and without a disc drive
- [x] Flashed to the LambdaSpeak 4 card (`tools/card.py`), checksums verified
- [ ] First run on the real 464 (2026-11-07: ROMs on the card, awaiting
      `docs/cpc-test.txt`)
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
      float, so `(* 200 200)` is `40000.0`
- [x] Floats: the firmware's 5-byte reals, about nine digits
- [x] Errors print a message and the object and return to `LISP>`; the stack
      is checked for overflow
- [x] ESC breaks any running program, including loops over circular lists
- [x] Mark-and-sweep garbage collector; about 7000 cells of 4 bytes, 512
      symbols, strings and vectors in a compacted block space
- [ ] Multiple values (`values`, `multiple-value-bind`)
- [ ] `defstruct`, hash tables
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
      reopens the last text

## Built-in functions

### Core ROM: special forms

`quote` `function` `lambda` `if` `when` `unless` `cond` `case` `and` `or`
`progn` `prog1` `setq` `setf` `incf` `decf` `push` `pop` `let` `let*`
`flet` `labels` `defun` `defmacro` `defvar` `defparameter` `defconstant`
`block` `return-from` `return` `catch` `throw` `dolist` `dotimes` `loop`
`declare` `the` `unwind-protect`

### Core ROM: functions

- **Lists:** `car` `cdr` `first` `rest` `second` `third` `caar` `cadr` `cdar`
  `cddr` `caddr` `cdddr` `cons` `list` `list*` `append` `reverse`
  `nreverse` `length` `nth` `nthcdr` `last` `member` `assoc` `rplaca`
  `rplacd`
- **Functions:** `mapcar` `mapc` `apply` `funcall`
- **Predicates:** `null` `not` `atom` `consp` `listp` `symbolp` `numberp`
  `integerp` `stringp` `characterp` `functionp` `keywordp` `vectorp` `eq`
  `eql` `equal`
- **Numbers:** `+` `-` `*` `1+` `1-` `truncate` `floor` `mod` `rem` `abs`
  `max` `min` `<` `>` `<=` `>=` `=` `/=` `zerop` `plusp` `minusp` `evenp`
  `oddp` `logand` `logior` `logxor` `lognot` `ash` `random`
- **Symbols:** `symbol-name` `symbol-value` `symbol-function` `symbol-plist`
  `set` `boundp` `fboundp` `makunbound` `fmakunbound` `get` `remprop`
  `gensym` `intern`
- **Characters, strings, vectors:** `char-code` `code-char` `char` `string=`
  `string` `make-array` (`:initial-element`) `vector` `aref` `svref` `elt`
- **Input, output, evaluation:** `print` `prin1` `princ` `terpri`
  `write-char` `read` `eval` `error`
- **System:** `gc` `room`

### Library ROM 1

- **Text screen:** `cls` `mode` `locate` `pen` `paper` `ink` (with a second
  colour, flashing) `border` `reset`
- **Graphics:** `plot` `plotr` `draw` `drawr` `move` `mover` `test` `testr`
  `origin` `clg` `graphics-pen` `graphics-paper` `xpos` `ypos`
- **Sound:** `sound` (channels, period, duration, volume, envelopes, noise:
  BASIC's SOUND)
- **Keys and time:** `inkey` `wait-key` `key-down-p` `frame` `time`
- **Strings:** `string-upcase` `string-downcase` `char-upcase`
  `char-downcase` `concatenate` `subseq` `parse-integer` `nreconc`
- **Printing to and from strings:** `pprint` `prin1-to-string`
  `princ-to-string` `read-from-string`
- **Function editor:** `ed`
- **Files** (through the firmware's cassette vectors, so with any disc ROM;
  tested with AMSDOS in MAME, tape not tried): `load`, `save` (what you
  defined, or the symbols named, pretty-printed), `dir`

### Library ROM 2

- **Floats:** `/` `round` `ceiling` `float` `floatp` `sqrt` `exp` `sin` `cos`
  `tan` `log` `atan` `expt` and the constant `pi`
- **Output:** `format` with `t` or `nil`: `~A` `~S` `~D` `~C` `~%` `~&` `~~`,
  with widths
- **Sorting:** `sort`, `stable-sort` (lists and vectors, `:key`)
- **Written in Lisp** (loaded from the ROM when first used): `identity`
  `complement` `nconc` `copy-list` `make-list` `butlast` `acons` `pairlis`
  `rassoc` `subst` `remove` `remove-if` `remove-if-not` `find` `find-if`
  `position` `position-if` `count` `count-if` `member-if` `every` `some`
  `notany` `notevery` `reduce` `mapcan` `maplist` `adjoin` `union`
  `intersection` `set-difference` `subsetp` `gcd` `signum` and the macros
  `pushnew` `psetq` `do` `do*`; the variable `*features*`

## Tools

- [x] `tools/build.sh`: the three ROMs, and MAME romsets with the core at ROM 0
- [x] `tools/test.sh`: 14 regression tests, on a 464 or a 6128
- [x] `tools/run.sh`: type a file at the REPL in MAME; screenshots,
      timings, an instruction profile (`tools/profile.py`)
- [x] `tools/mame.sh`: a MAME window to play in, with a disc
- [x] `tools/card.py`: the ROMs onto the LambdaSpeak 4 card

## Still to come, in this order

1. [ ] **The real 464**: go through `docs/cpc-test.txt`, fix what differs
2. [ ] **Speed**
   - [x] Arguments that are constants or variables skip `eval`; `+` `-`
         and comparisons have a fast path for two integers; ESC is checked
         once per function body; plain lambda lists are bound straight
         from the stack. Together: `(fib 17)` 1103 → 641 frames, `sort` ~7×
   - [ ] ESC: catch a tap that falls inside a garbage collection
   - [ ] `funcall`/`apply` without building an argument list
   - [ ] More from the profiler; rarely used core functions moved to a
         library ROM to make room (the core has ~200 bytes free)
3. [ ] **The 6128's extra 64 KB**: a RAM disc for `save` and `load`
4. [ ] **More Common Lisp**
   - [ ] `string<` `string>` `string-equal` and the other string comparisons;
         `char=` `char<` `char-equal` and the other character comparisons
   - [ ] More strings: `string-trim`, `search`, `position` and `find` on
         strings, `string-left-trim`, `string-right-trim`
   - [ ] `coerce`
   - [ ] `:test` and `:key` on `member`, `assoc`, `remove`, `find`,
         `position`, `count`
   - [ ] `defstruct`, hash tables, multiple values
5. [ ] **More graphics and sound**: envelopes (BASIC's ENV and ENT),
       `release`, the sound queue, text windows, filled shapes, circles,
       user-defined characters, text at the graphics cursor, ink flash speed
6. [ ] **A demo ROM** with example programs
7. [ ] **A reference manual**: every function and capability, with examples
8. [ ] Later, maybe: `*print-case*`; a byte-code compiler
