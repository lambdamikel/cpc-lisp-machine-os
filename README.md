# CPC Lisp

A Lisp machine for the Amstrad CPC: an auto-boot ROM that starts a Lisp
instead of BASIC. Common Lisp syntax, lexical closures, macros, a garbage
collector -- in 16 KB of Z80 assembly, with graphics, sound, files, floats
and editors in four more ROMs, and a bytecode compiler in a fifth.

    CPC Lisp 0.3, library ROMs 1 2 3 4
    6658 cells free

    LISP> (defun fib (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
    FIB
    LISP> (fib 15)
    610
    LISP> (mapcar #'(lambda (x) (* x x)) '(1 2 3 4 5))
    (1 4 9 16 25)
    LISP> (compile 'fib)
    FIB

## Status

The core ROM boots to `LISP>` in MAME on the 464 and the 6128 (ROM 0,
replacing BASIC), with integers, floats, symbols, conses, strings, characters,
closures, special variables, `defmacro` and backquote, `block`/`catch`,
`labels`/`flet`, `setf`, tail calls, ESC to break, and a mark-and-sweep GC.
Also `&key`, `unwind-protect`, catchable errors (`handler-case`),
multiple values, vectors, structures and hash tables.

The library comes in four more ROMs. The first has graphics (`plot`,
`draw`, circles, flood fill, turtle graphics), `sound`, keys, the text
screen, strings and characters (the CL comparisons and predicates), the
printers and readers with CL's streams, files (`load`, `save`, `dir`,
`with-open-file`, a RAM disc on the 6128), a line editor and a full-screen
function editor. The second has the floats and maths functions (`sqrt`,
`sin`, `atan`, `log`, ...) through the firmware, all of `format`'s
directives, `sort`, the sequence functions with all their
keywords, hash tables, the expander of the extended `loop`, and speech and
PlayCity on the LambdaSpeak card. The third has about eighty CL functions
and macros written in Lisp (`reduce`, `map`, `defstruct`, `typep`,
`handler-case`, ...) that are read from ROM the first time they are used.
The fourth, the demo ROM, has `loop` and example programs: `(demo)` lists
them. The fifth, the VM ROM, runs compiled code: `(compile 'fib)` makes
`fib` bytecode, about three times faster -- the compiler is written in
Lisp, compiled by itself, and runs from that ROM too. It runs on a real
464 (`docs/cpc-test-5roms.txt`).

## Building and testing

Needs rasm and MAME with the CPC ROMs (paths in `tools/build.sh`).

    tools/build.sh                 # build/LISP.ROM, LISPLIB*.ROM, and
                                   # MAME romsets with the core at ROM 0
    tools/mame.sh                  # a MAME window to play in (-m 6128 for a 6128)
    tools/run.sh file.lsp          # type a file at it in MAME, print the transcript
    tools/test.sh                  # the regression tests in test/ (-m 6128 for a 6128)

On a real CPC the core ROM goes in at ROM 0 with ROMDIS asserted to replace
BASIC, or at any free number, where `|LISP` from BASIC starts it. The
library ROMs go at any free numbers from 1 to 6, in either order, and must
come from the same build as the core.

**Typing a tilde** (`format`'s `~A`, `~%`...): the CPC has no `~` key --
it is **CTRL + 2** (in MAME, Right Alt + 2).

## Documents

* [`docs/reference.md`](docs/reference.md): the reference manual -- the
  REPL, the editors, the syntax, and every function, form and macro
* [`docs/checklist.md`](docs/checklist.md): everything implemented, every
  built-in function by ROM, and what is still to come
* [`docs/cpc-test-5roms.txt`](docs/cpc-test-5roms.txt): what to type on a
  real CPC, and what it should answer
* `CLAUDE.md`: the design, the memory layout, and what was learned about the
  CPC and MAME along the way
