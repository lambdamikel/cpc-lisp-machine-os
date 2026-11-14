# CPC Lisp on the TRS-80 Model 4

*Runs on Mike's Model 4 (2026-11-13: 128 KB, LS-DOS 6.3.1 from the FreHD,
Ian Mavric's Improved Grafyx -- `(hwtest)` 8 yes), and in trs80gp from a
floppy and from the FreHD.* The
same Lisp as on the CPC -- the images are built from the same sources --
on a TRS-80 Model 4 with 128 KB, natively in its Model 4 mode, under
LS-DOS 6.3.1: 80 by 24 characters, and graphics on the high-resolution
board, 640 by 240.

## Building and running

    MACH=trs80m4 tools/build.sh   # build/trs80m4: the images, LISP/CMD,
                                  #   the discs lisp-m4.dsk, .hfe, .hdv
    tools/trs80m4/run.sh file.lsp # type a file at it in trs80gp (headless),
                                  #   print the transcript
    tools/trs80m4/test.sh         # the regression tests (test/skip.trs80m4
                                  #   lists the ones left out)
    M4DISC=hdv tools/trs80m4/...  # the same from the FreHD image

`lisp-m4.dsk` is LS-DOS 6.3.1's system disc (double density, 40 tracks)
with its utilities thinned out and `LISP/CMD`, the six images,
`HWTEST/LSP` and `APFEL/LSP` (the Apfelmaennchen, `examples/apfel.lsp`:
`(load "apfel")`, `(apfel)`) on it; `lisp-m4.hfe` the same for a Gotek or an HxC (made
with hxcfe, if it is there: `$HXCFE`). At `LS-DOS Ready`, `LISP` loads
them and starts; `(quit)` goes back. `tools/trs80m4/mkdisk.py` starts
from LS-DOS 6.3.1's own disc (`discs/ld4-631.dsk`, from the LS-DOS 6.3.1
distribution, which Roy Soltoff made free to use and pass on; or
`$LSDOS631`).

`lisp-m4.hdv` is the same on a hard disc for the **FreHD**: a bootable
LS-DOS 6.3.1 (`tools/trs80m4/ls631-frehd.hdv.gz`, `mkhdv.py`'s header
says what it is) with the Lisp's files added. On the FreHD's SD card
(`discs/frehd/cpclisp4`: copied to its root as it is named) the FreHD's
boot menu lists it; ENTER boots it, no date is asked, `LISP`. In trs80gp,
`run.sh` with `M4DISC=hdv` boots it through trs80gp's own FreHD and its
menu (`-frehd_dir`, `-frehd_patch`, `-frehd_menu`). LS-DOS on this disc
has 202 cylinders of 32 sectors (the file keeps 256 a cylinder),
granules of 4 sectors; `tools/trs80/ldoswrite.py` reads the granule size
off DIR/SYS. Its cylinder 0 is the boot's: sectors 4-13 hold boot code
the GAT does not mark, so no file goes there.

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
| F2 | delete: the character under the cursor (CLR) |
| F3 | backspace: the character to the left (DEL) |
| CTRL-S | in the function editor, done (BREAK leaves it unchanged) |
| SHIFT down, then a key | a character the keyboard has not got (below) |
| SHIFT down twice | the copy cursor down |
| SHIFT @ | output waits (LS-DOS's way) until another key; at the prompt, a backquote |

To delete: F3 or SHIFT <- the character to the left, F2 or CLEAR the
one under the cursor; <- and -> only move.

The Model 4 has no `[ ] { } \ | ~ ^ _` keys, and LS-DOS gives none for
CTRL with a key (CTRL @ is code 0, CTRL and a digit the digit; CTRL ,
for `[` is a replacement ROM's, not LS-DOS's). **SHIFT down-arrow,
pressed and let go, then a key** makes them, as on the Model I/III; the
key may be shifted or not:

| SHIFT down, then | gives | for |
|---|---|---|
| `8` or `(`, `9` or `)` | `[` `]` | `format`'s `~[ ~]` |
| `,` or `<`, `.` or `>` | `{` `}` | `format`'s `~{ ~}` |
| `-` or `=` | `~` | `format`'s directives: `"~A"` |
| `/` or `?` | `\` | characters: `#\a`; escapes in strings |
| `1` or `!` | `\|` | `\|odd names\|`, `#\| comments \|#` |
| `7` or `'` | `` ` `` | backquote |
| `@` | `^` | `format`'s `~^` |
| `0` | `_` | |
| `C` | COPY | the copy cursor's character; the function editor: done |
| `S` | CTRL-S | the function editor: done |
| down-arrow again | | the copy cursor down |

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
  Shack's 26-1126, the Grafyx Solution's Model 4 version and Ian
  Mavric's Improved Grafyx -- the same ports, but the text over the
  graphics is the Tandy board's undocumented port &8E, and on the
  Grafyx bit 1 of &83 clear (set, it shows the graphics alone: the
  Lisp's screen went black on Mike's Improved Grafyx). Tried in trs80gp
  with all three (`-gt`, `-gg`, `-gc`; `M4HIRES` in run.sh). 640 by 240 pixels from the
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
* **Speech** through Talker/80 (`say`, `mach/trs80/card.asm`): works on
  Mike's Model 4 (2026-11-13), as do the tunes on the speaker. **MIDI**
  (MIDI/80, `midi-out`, `midi-note`) is linked in, untried.
* **Not yet**: the RAM disc and far arrays (`M:` says "no RAM disc on a
  Model 4").
