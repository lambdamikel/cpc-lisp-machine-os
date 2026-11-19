# Pocket Lisp (in progress)

CPC Lisp's dialect on a 32-bit core in C, for a pocket computer: an
RP2350, a 4" 480 × 320 color screen, a keyboard made for Lisp. This is
step 1 of the plan: the core on Linux, run against CPC Lisp's own
regression tests before there is any board.

The core follows CPC Lisp's design ([docs/design.md](../docs/design.md))
widened to 32-bit words:

* **Objects** are 32-bit offsets into one heap, never C pointers, so the
  heap is the same on a 64-bit host and the RP2350: 31-bit fixnums (an
  integer past them becomes a float, as CPC Lisp's past 15 bits), conses
  in 8-byte cells, typed cells ([header][data]) for strings, doubles,
  vectors, structures, closures and macros, symbols in a table of their
  own, characters as immediates.
* **The GC** is CPC Lisp's: mark and sweep, the C stack scanned
  conservatively (a native may keep Lisp values in its locals), block
  space for strings and vectors compacted.
* **Eval** is a loop with proper tail calls; special variables are
  shallow-bound; `block`, `catch`, `unwind-protect` and `%catch-errors`
  are frames left by longjmp, cleanups run on the way; a macro call is
  rewritten in place as `(%EXPANDED (macro . expansion) op . args)`.
* **The library's Lisp text** -- `lib/lisp.lsp`, `lisp2.lsp`, `loop.lsp`,
  `lazy.lsp`, `farray.lsp`, `demo.lsp` -- is CPC Lisp's, unchanged; the
  natives (`format`, the pretty printer, strings, sequences, structures,
  hash tables, streams, files) are written anew in C.

## Building and testing

    make -C pocket
    pocket/pocket -l lib            # from the repository's root
    pocket/tools/test.sh [-v] [-u] [name...]

The tests are CPC Lisp's `test/*.lsp`, compared with `test/NAME.out`, or
`test/NAME.pocket.out` where Pocket Lisp rightly says something else: its
integers are 31 bits (`(* 200 200)` is 40000, not 40000.0), its floats
are doubles printed to the shortest form that reads back
(0.3333333333333333), `*features*` says `:POCKET`, hashes differ. In batch
mode the REPL echoes and spaces typed lines as the CPC's test harness and
line editor do, and the tests' `!esc` (ESC while a line runs) and `!type`
(keys for `read-char`) work; `POCKET_COLS=40` lays out `pprint` for the
CPC's 40 columns. `pocket/test.skip` lists the tests that need the CPC's
screen and keys.

## State (2026-11-19)

21 of the 36 tests pass. To come: the extended `loop` (`%loop-expand`),
files and the RAM disc for the `disc*` tests, the classics, the demos,
the bytecode machine for the compiler; then the RP2350.
