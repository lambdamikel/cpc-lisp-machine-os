# CPC Lisp on the ZX Spectrum 128K with a DivMMC

*Runs in ZEsarUX (a +2A, a DivMMC with esxDOS 0.8.5); not tried on a real
Spectrum yet.* The same Lisp as on the CPC -- the six images are built
from the same sources, the compiler included -- on a ZX Spectrum +2A,
+2B or +3 (or a 128 or grey +2: the loader tells them apart, untried) with
a **DivMMC** (or a compatible interface) that has **128 KB of RAM** and
runs **esxDOS**.

## Building, installing and starting

    MACH=spectrum tools/build.sh     # build/spectrum: the images, the machine
                                     #   pages, LISP.TAP, and sd/ -- the files
                                     #   for the SD card
    tools/spectrum/zx.py file.lsp    # type a file at it in ZEsarUX (headless),
                                     #   print the transcript
    tools/spectrum/test.sh           # the regression tests

Copy what is in `build/spectrum/sd/` to the SD card: `LISP.TAP`,
`HWTEST.LSP` and the examples (`APFEL.LSP`, the classics). Lisp's files are
esxDOS's current folder's: keep them together.

To start it, load `LISP.TAP` as a tape: **press the DivMMC's NMI button,
choose `LISP.TAP`** (esxDOS mounts it and loads it), or in 128 BASIC type
`.tapein lisp.tap` and then `LOAD ""`. Not from 48 BASIC: it locks the
128K's paging, and the loader says so. The loader says, too, if there is no
DivMMC, or less than 128 KB on it. It loads in a few seconds from the SD
card; the same tape played on a real cassette would take some ten minutes,
and work the same (the DivMMC is needed either way: its RAM holds the
machine's routines).

`(quit)` or `(reset)` start the Spectrum afresh, into its menu.

## How it is arranged

The 128K's eight RAM banks are all in use: six for the images, two for
the Lisp's RAM. The machine's own routines -- the screen, the keys, files,
floats -- live in the DivMMC's RAM.

| | |
|---|---|
| &0000-&3FFF | 48 BASIC's ROM (its calculator); while a machine routine runs, the DivMMC's EEPROM and one of its pages |
| &4000-&5AFF | the screen (bank 5) |
| &5B00-&5CFF | the 128K ROMs' and 48 BASIC's variables (the calculator needs them), its stack |
| &5D00-&60FF | the interrupt's table (IM 2), the resident part: SYS_BANK, the jumpblock, the ways to esxDOS and the ROM (`resident.asm`) |
| &6100-&BAFF | the Lisp's RAM: tables, symbols, cells, strings, the stack (`memmap.asm`) |
| &BB00-&BFFF | the fixed variables and buffers |
| &C000-&FFFF | one bank at a time: the core (bank 0), library parts 0-3 (1, 3, 4, 6), the VM (7) |
| DivMMC pages 14, 15 | the machine pages A and B (`page.asm`, `pageb.asm`), seen at &2000 only while one of their routines runs |
| DivMMC pages 5-13 (16 on) | the RAM disc `M:` |

A call of a machine routine goes to the resident jumpblock, which maps
the DivMMC's page in at &2000 (its CONMEM), calls the routine and maps out
again (`mfar`, `resident.asm`). With the page in, &0000-&1FFF is the
DivMMC's EEPROM, so what needs the ROM -- the calculator (RST 28), esxDOS
(RST 8) -- goes through the resident part, which maps the page out for it.
esxDOS has pages 0-4 of the DivMMC's RAM; it sets the DivMMC's port its own
way at each call (the resident part puts back what was there after). The
interrupt is IM 2 (the DivMMC would map itself in at &0038), 50 times a
second: the clock, the keys, the sound. No machine page may have code at
&3D00-&3DFF: a fetch there maps the DivMMC in by itself (its TR-DOS trap).

**About 1800 cells are free at start, and some 5 KB of strings** -- the
Lisp's RAM is what 32 KB leaves after the screen and the tables; `gc` runs
out of room in the tests (`test/gc.spectrum.out` says where). Dropping
library functions, lazy loading (`(load "name" :lazy t)`) and `(room)`
help as on the CPC.

## The screen

40 columns and 24 rows -- the CPC's mode 1 -- in a font of our own (5 by
7 in 6 by 8 pixels, `font.inc`, from `tools/spectrum/mkfont.py`), centred
on the 256 pixels; yellow on blue, as the CPC starts. `ink` 0 and 1 colour
the paper and the text, `border` the border. Graphics are the screen's
256 by 192 pixels, from the CPC's logical 640 by 400 (a pixel is 2.5 units
wide and 25/12 high: the CPC's proportions). A pen lights a pixel in its
colour -- the colour of its ink, the CPC's defaults made the Spectrum's --
and gives its 8 by 8 cell that colour, the Spectrum's way (colour clash:
text in the cell takes it too); `test` answers the pen whose colour the
cell has. `mode` only clears the screen.

## The keys

| Spectrum | CPC Lisp |
|---|---|
| BREAK (CAPS SHIFT and SPACE) | ESC: interrupts |
| EDIT (CAPS SHIFT 1) | COPY: copies from the copy cursor; in the function editor, done |
| GRAPH (CAPS SHIFT 9) | CTRL-S: in the function editor, done |
| DELETE (CAPS SHIFT 0) | DEL: the character to the left |
| INV VIDEO (CAPS SHIFT 4) | CLR: the character under the cursor |
| TRUE VIDEO (CAPS SHIFT 3) | TAB |
| the cursor keys (CAPS SHIFT 5-8) | the arrows; up and down, the history |
| EXTEND MODE, then a cursor key | the copy cursor (SHIFT and an arrow on the CPC) |
| CAPS LOCK (CAPS SHIFT 2) | capitals until pressed again |

SYMBOL SHIFT gives the symbols on the keys, and on the keys whose symbol
is a BASIC keyword the ones Lisp wants: Y `[`, U `]`, F `{`, G `}`, A
`~`, S `|`, D `\`, X `` ` `` (the backquote: the Spectrum's £), H `^`.
(EXTEND MODE and SYMBOL SHIFT with them gives the same, as in BASIC.)

`key-down-p` takes the matrix's numbers: half-row * 8 + bit, the
half-rows &FEFE (CAPS SHIFT Z X C V) as 0 to &7FFE (SPACE, SYMBOL SHIFT M
N B) as 7, and 64 for BREAK.

## What works, and what not yet

* The language, **the compiler**, the editors, `format`, the extended
  `loop`, structures, hash tables, string streams.
* **Files** through esxDOS on the SD card: `load`, `save`, `open`,
  `with-open-file`, `probe-file`, `delete-file`, `compile-file`, lazy
  loading; `dir` lists the current folder as AMSDOS lists a disc. There is
  only `A:` (esxDOS's current drive); `(cd "a:")` is T, any other NIL.
* **The RAM disc**, drive `M:`, in the DivMMC's RAM that esxDOS and the
  machine pages leave: 72 KB on a 128 KB one, 200 or 456 KB on a 256 or 512
  KB one -- `(save "m:work")`, `(dir "m:")`, streams, and **far arrays**
  there. The DivMMC keeps it while the power is on.
* **Floats**, the CPC's five-byte reals: + - * / here, rounded as the
  CPC's firmware rounds them (`fparith.asm`); `sqrt`, `exp`, `log`, `sin`,
  `cos`, `tan`, `atan` by 48 BASIC's calculator. The float tests give what
  the CPC gives.
* **Sound** on the 128K's AY: `sound`'s three channels, each a queue of
  four, the periods made the AY's (it runs at 1.7734 MHz, the CPC's at 1);
  `play`, the tunes. Not yet: `envelope`, `tone-envelope` (taken, not
  heard), rendezvous and holding.
* `peek`, `poke`; `time` (the interrupt's count, in 1/300 s).
* `*features*` is `(:zx-spectrum :cpc-lisp)`.
* **Not here**: speech (`say` is quiet), MIDI (`midi-out` sends nothing
  yet: the +2A's MIDI socket is the AY's port, to come), and the CPC's own
  `symbol`, `window`, `tag`, `transparent`, `flash-speed`, `text-cursor`,
  `joystick`, `release`, `sound-check`, `sound-hold`, `sound-continue`,
  PlayCity.

## A test of the real machine

`(load "hwtest")`, `(hwtest)`: ten checks, yes or NO -- the cells, the
compiler, a file on the SD card, lazy loading from it and from `M:`, two
files open at once, the RAM disc, far arrays over five of its pages, the
ROM's calculator, the colour pens. Then `(quit)`, load `LISP.TAP` again,
`(load "hwtest")`, `(hwtest2)`: that the RAM disc kept its files.

## In ZEsarUX

`tools/spectrum/zx.py` starts ZEsarUX 13.0 (`~/claude/spectrum/zesarux`,
or `$ZESARUX_DIR`) with no video or sound, a +2A, the DivMMC's paging and
esxDOS's calls served from a folder of the PC's (`-d`), and its remote
protocol (ZRCP). It loads the images into their banks over ZRCP and starts
the resident part -- or, with `-T LISP.TAP`, loads the tape as a user
does, ENTER on the menu's Loader. A breakpoint at EDHOOK tells it when the
Lisp wants a line; the line goes into machine page A's paste buffer, which
KEY_READ reads as if typed; everything printed goes to ZEsarUX's debug
byte file (its debug ports, which the machine page looks for at the
start): the transcript. `-S shot.png` draws the screen's memory into a
picture at the end.
