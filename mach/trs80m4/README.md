# CPC Lisp on the TRS-80 Model 4

*Runs in trs80gp (2026-11-13); not yet tried on a real Model 4.* The
same Lisp as on the CPC -- the images are built from the same sources --
on a TRS-80 Model 4 with 128 KB, natively in its Model 4 mode, under
LS-DOS 6.3.1: 80 by 24 characters, and graphics on the high-resolution
board, 640 by 240.

## Building and running

    MACH=trs80m4 tools/build.sh   # build/trs80m4: the images, LISP/CMD,
                                  #   the disc lisp-m4.dsk
    tools/trs80m4/run.sh file.lsp # type a file at it in trs80gp (headless),
                                  #   print the transcript
    tools/trs80m4/test.sh         # the regression tests (test/skip.trs80m4
                                  #   lists the ones left out)

`lisp-m4.dsk` is LS-DOS 6.3.1's system disc (double density, 40 tracks)
with its utilities thinned out and `LISP/CMD`, the six images and
`HWTEST/LSP` on it. At `LS-DOS Ready`, `LISP` loads them and starts;
`(quit)` goes back. `tools/trs80m4/mkdisk.py` starts from LS-DOS 6.3.1's
own disc (`ld4-631.dsk`, from the LS-DOS 6.3.1 distribution, which Roy
Soltoff and William Schroeder made free to use and pass on): `$LSDOS631`,
or `tools/trs80m4/ld4-631.dsk`.

The loader says why it will not start: something in high memory (HIGH$
must be X'FFFF'), a 32 KB bank in use (by the spooler, a RAM disc
driver: CPC Lisp needs banks 1 and 2), or no 128 KB.

## How it is arranged

The Model 4's 128 KB is a fixed lower 32 KB and three 32 KB banks for
the upper half (OPREG, port &84, bits 4-6): LS-DOS's bank 0 and the two
of the second 64 KB. Each bank holds two of the images, a *slot* each:

| | |
|---|---|
| &0000-&25FF | LS-DOS |
| &2600-&29FF | the resident part: SYS_BANK, the gate to LS-DOS, the jumpblock, the clock task (`resident.asm`) |
| &2A00-&33FF | the fixed variables and buffers, the mark stack, the symbol hash table (`memmap.asm`) |
| &3400-&3FFF | the machine stack |
| &4000-&41FF | the Model III ROM's RAM, for its floats |
| &4200-&7FFF | symbols, cells, strings |
| &8000-&FFFF | one bank: 0 (part 0 at &8000, the core at &C000), 1 (parts 1 and 2), 2 (part 3, the machine page at &C000) |

The parts are assembled for &8000 or &C000 (`liborgs`; `LIB_MIXED` in
the core tells them apart by their slot's number). A switch writes OPREG
and LS-DOS's image of it (OFLAG$) together, the image first: LS-DOS's
drivers map the keyboard and screen in from it during an interrupt, so
the interrupts stay on. LS-DOS itself is called through the resident
gate with its bank 0 in, whatever the Lisp had.

The Lisp runs in memory map 3 (all RAM). The machine page (`page.asm`)
opens windows onto the rest: map 2 for the screen and keyboard (at
&F400-&FFFF, over the bank, with the interrupts off: LS-DOS's own drivers
do it so), map 0 for the Model III ROM (`fp4.asm`: its floats, on a
stack of its own, since the ROM covers the Lisp's at &3400). In map 0
the ROM covers the resident part too: what the window needs to get out
again it keeps in the machine page. The clock is a task of LS-DOS's
(slot 8-10, 30 times a second), counting in the resident part.

**About 1900 cells are free at start, and 2.7 KB of strings** -- the
heap has to be in the lower 32 KB, beside LS-DOS, since every image
sees it. `gc`, `structs` and `vector` run out of room in the tests
(their `.trs80m4.out` say where); dropping library functions, lazy
loading and `room` help as on the CPC.

## The keys

| Model 4 | CPC Lisp |
|---|---|
| BREAK | ESC: interrupts |
| <- | cursor left |
| SHIFT <- | DEL: the character to the left |
| -> | cursor right |
| SHIFT -> | TAB |
| up, down | the history |
| SHIFT up | the copy cursor up |
| CLEAR | CLR: the character under the cursor |
| F1 | COPY: copies from the copy cursor; in the function editor, done |
| CTRL-S | in the function editor, done (BREAK leaves it unchanged) |
| SHIFT down, then a key | a character the keyboard has not got, as on the Model I/III (`mach/trs80/README.md`) |
| SHIFT down twice | the copy cursor down |
| SHIFT @ | output waits (LS-DOS's way) until another key |

Keys come through LS-DOS (@KEY, @KBD), so its type-ahead works.
`key-down-p` takes the matrix's numbers, row * 8 + bit: ENTER 48, CLEAR
49, BREAK 50, up 51, down 52, left 53, right 54, SPACE 55.

## What works, and what not yet

* The language, the editors, `format`, the extended `loop`, structures,
  hash tables, string streams. **No compiler**: the VM ROM would be a
  seventh image, and there is no slot for it (`novm`).
* **Floats** through the Model 4's Model III ROM, in map 0, as on the
  Model I/III: + - * / and `sqrt` as good as the CPC's; `exp`, `log`,
  `sin`, `cos`, `tan`, `atan` about seven digits.
* **Graphics** on the high-resolution board (`hires.asm`): Radio
  Shack's 26-1126, which trs80gp has; the Grafyx Solution's Model 4
  version is said to use the same ports, and the Improved Grafyx to be
  compatible with both (untried; the text over the graphics is an
  undocumented port of the Tandy board's). 640 by 240 pixels from the
  CPC's logical 640 by 400 (a pixel one unit wide, 5/3 high); the text
  over the graphics (port &8E); `ink-mode`; the turtle; circles, discs,
  boxes; `flood-fill`. One colour: a pen is lit or not. `cls` clears
  both, `clg` the graphics. Without a board, drawing does nothing and
  `test` answers 0.
* **Sound**: one voice, a square wave on the speaker (port &90); the
  note is played there and then (`sound`, `play`, the tunes).
* **Files** through LS-DOS 6: `load`, `save`, `open`, `with-open-file`,
  `probe-file`, `delete-file`, lazy loading; `dir` lists each drive's
  files (DIR/SYS, read as a file). A name `B:FOO.LSP` is LS-DOS's
  `FOO/LSP:1`.
* `(time)` counts 1/300 s, from LS-DOS's clock task.
* **Not yet**: the RAM disc and far arrays (`M:` says "no RAM disc on a
  Model 4"); speech, MIDI (`mach/trs80/card.asm` is linked in, untried).
