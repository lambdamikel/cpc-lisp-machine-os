# CPC Lisp

A Lisp machine for the Amstrad CPC: an auto-boot ROM that starts a Lisp
instead of BASIC. Common Lisp syntax, lexical closures, macros, a garbage
collector -- in 16 KB of Z80 assembly. Graphics, disc and sound will come
through the CPC firmware, in a second ROM.

    CPC Lisp 0.1
    7288 cells free

    LISP> (defun fib (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
    FIB
    LISP> (fib 15)
    610
    LISP> (mapcar #'(lambda (x) (* x x)) '(1 2 3 4 5))
    (1 4 9 16 25)

## Status

The core ROM boots to `LISP>` in MAME on the 464 and the 6128 (ROM 0,
replacing BASIC), with integers, symbols, conses, strings, characters,
closures, special variables, `defmacro` and backquote, `block`/`catch`,
`labels`/`flet`, `setf`, tail calls, ESC to break, and a mark-and-sweep GC.
A second ROM, the library, adds graphics (`plot`, `draw`, `test`, ...),
`sound`, keys, the text screen, strings, and about forty CL functions and
macros written in Lisp (`sort`, `reduce`, `remove-if`, `do`, ...) that are
loaded from ROM the first time they are used. Not yet: floats, vectors,
`&key`, files. It has not been on a real CPC yet.

## Building and testing

Needs rasm and MAME with the CPC ROMs (paths in `tools/build.sh`).

    tools/build.sh                 # build/LISP.ROM, and MAME romsets with it at ROM 0
    tools/run.sh file.lsp          # type a file at it in MAME, print the transcript
    tools/test.sh                  # the regression tests in test/ (-m 6128 for a 6128)

On a real CPC the core ROM goes in at ROM 0 with ROMDIS asserted to replace
BASIC, or at any free number, where `|LISP` from BASIC starts it. The
library ROM goes at any free number from 1 to 6, and must come from the
same build as the core.

`CLAUDE.md` has the design, the memory layout, and what was learned about
the CPC and MAME along the way.
