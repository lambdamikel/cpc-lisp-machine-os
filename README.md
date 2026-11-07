# CPC Lisp

A Lisp machine for the Amstrad CPC: an auto-boot ROM that starts a Lisp
instead of BASIC. Common Lisp syntax, lexical closures, macros, a garbage
collector -- in 16 KB of Z80 assembly, with graphics, sound, files, floats
and editors in two more ROMs.

    CPC Lisp 0.3, library ROMs 1 2 3 4
    7119 cells free

    LISP> (defun fib (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
    FIB
    LISP> (fib 15)
    610
    LISP> (mapcar #'(lambda (x) (* x x)) '(1 2 3 4 5))
    (1 4 9 16 25)

## Status

The core ROM boots to `LISP>` in MAME on the 464 and the 6128 (ROM 0,
replacing BASIC), with integers, floats, symbols, conses, strings, characters,
closures, special variables, `defmacro` and backquote, `block`/`catch`,
`labels`/`flet`, `setf`, tail calls, ESC to break, and a mark-and-sweep GC.
Also `format` (~A ~S ~D ~% ...), `&key`, `unwind-protect` and vectors.

The library comes in three more ROMs. The first has graphics (`plot`,
`draw`, `test`, ...), `sound`, keys, the text screen, strings and characters
(the CL comparisons and predicates), files (`load`, `save`, `dir`, a RAM
disc on the 6128), a line editor and a full-screen function editor. The
second has the floats and maths functions (`sqrt`, `sin`, `atan`, `log`,
...) through the firmware, `format`, `sort`, `coerce`, and `member`/`assoc`
with `:test` and `:key`. The third has about seventy CL functions and macros
written in Lisp (the sequence functions on lists, strings and vectors,
`reduce`, `map`, `do`, ...) that are loaded from ROM the first time they are
used. A fourth, the demo ROM, has example programs: `(demo)` lists them.
Without one, its functions are undefined and the rest works. It is being
tried on a real 464 (`docs/cpc-test.txt`).

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

## Documents

* [`docs/checklist.md`](docs/checklist.md): everything implemented, every
  built-in function by ROM, and what is still to come
* [`docs/cpc-test.txt`](docs/cpc-test.txt): what to type on a real CPC, and
  what it should answer
* `CLAUDE.md`: the design, the memory layout, and what was learned about the
  CPC and MAME along the way
