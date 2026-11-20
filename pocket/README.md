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

All 36 tests pass (the other 7 need the CPC's keys and screen): the
language, lists, sequences, strings, format, the pretty printer,
structures, hash tables, values, errors and unwinding, loop, string and
file streams, files on the disc and on the RAM disc M: (kept in memory,
PSRAM on the device; far arrays there), lazy loading, the classics
(ELIZA, the animals, tic-tac-toe...), the demos, and **the compiler**:
`compile`, `compile-file`, `disassemble`.

**The compiler** is CPC Lisp's `lib/compiler.lsp`, unchanged, run as
library text (the CPC needs it bootstrapped into a ROM; here the cells
are plenty), and `src/vm.c` is CPC Lisp's bytecode machine
(`lib/vm.asm`): the same 85 operations, the same frame -- the Z80's
byte offsets halved, a place a 32-bit word -- so the code is byte for
byte the CPC's (`disassemble` shows the same listing, compile-file
writes the same hex). Compiled tail calls take the caller's frame.
(fib 25): 30 ms interpreted, 23 ms compiled on a PC -- the interpreter
is quick here; the machine has room to be made faster.

The tests' disc is a directory; `POCKET_DISC_K=178` and
`POCKET_RAMDISC_K=400` give it and M: the CPC's sizes, so `dir`'s
"free" lines compare. `(room)`'s figures are compared blanked: they
depend on what the C stack holds (it is scanned conservatively).

Next: the RP2350B (step 2 of the plan) on a **Waveshare Core2350B** --
LambdaSpeak 4's module: 16 MB flash, 8 MB PSRAM (chip select GP47; the
heap, M: and far arrays live there), the module's LED on GP39. It has no
USB socket and no buttons: a perfboard carrier with four 2 x 8 sockets
(its pin rows are on the 0.1" grid), a USB breakout, RUN and BOOTSEL.
Then the 4" ST7796S screen and a keyboard. A first pin map is in the
proposal: LCD on SPI1 (GP10 SCK, 11 MOSI, 13 CS, 14 DC, 15 reset, 16
backlight), microSD on SPI0 (GP2-5), keys rows GP17-21 and columns
GP26-35, sound PWM on GP22, I2C0 GP0/1, UART1 GP8/9 (MIDI), the battery
on GP40.
