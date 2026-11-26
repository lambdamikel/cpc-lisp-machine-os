# CPC Lisp on the Amstrad PCW

*Runs in ZEsarUX (13.0, an emulated PCW 8256 and 8512): the regression
tests, 43 of 43 (27 as the CPC prints them, 16 with the PCW's own
expectations), and the hardware test, 10 yes on either machine. Not yet
on a real PCW.* The same Lisp as on the CPC -- the six images are built
from the same sources, the compiler included -- on an **Amstrad PCW 8256
or 8512** (the Schneider Joyce), booted from **a disc of its own**: no
CP/M, no ROM; the machine is Lisp's from the boot sector on.

## Building and starting

    MACH=pcw tools/build.sh          # build/pcw: the images, the machine
                                     #   pages, BOOT.BIN, RESIDENT.BIN,
                                     #   LISP.IMG, and the two discs
    tools/pcw/pcw.py file.lsp        # type a file at it in ZEsarUX
                                     #   (headless), print the transcript
    tools/pcw/test.sh                # the regression tests

`cpclisp-pcw.dsk` (or the repository's `discs/pcw/`, ready built) is the
disc that boots: put it in drive A (on a Gotek: the image, FlashFloppy
reads .dsk) and switch on, or press SHIFT, EXTRA and EXIT together. The
bar in the middle of the screen fills as the eight parts load; then the
banner. `cpclisp-pcw-classics.dsk` has the example programs (the
Apfelmaennchen, the classics); with one drive, `(load "a:eliza")` after
swapping discs. The boot disc carries `HWTEST.LSP` and `APFEL.LSP` too.

`(quit)` and `(reset)` boot whatever disc is in drive A again: a CP/M
disc goes back to CP/M, Lisp's to Lisp.

## How it is arranged

The PCW's memory is blocks of 16 KB (16 on an 8256, 32 on an 8512), four
seen at a time through ports &F0-&F3. Lisp uses them so:

| | |
|---|---|
| blocks 4, 5, 6 at &0000-&BFFF | Lisp's RAM: the resident part (&0000-&04FF), the symbols, cells, strings, the stack, the fixed area (&BB00-&BFFF) -- 6499 cells at the start, 11 KB of strings |
| blocks 8-13 at &C000 | the six images, one at a time |
| blocks 14, 15 at &C000 | machine page A (screen, keys, graphics) and B (discs, files, floats, sound, the RAM disc) while one of their routines runs -- in place of the image, which the return brings back |
| blocks 1 and 3 | the screen (character rows 0-21, and 22-31 with the roller RAM) |
| block 3's last 16 bytes | the keyboard |
| blocks 0, 2, 7 (and 16-31 on an 8512) | the RAM disc, M: -- 47 KB, or 303 KB |

A block is seen at &4000 (the WINDOW) for a moment when a machine
routine needs it -- the screen, the keyboard, the RAM disc -- RS_P1
saying which, so the interrupt puts it back. The interrupt (300 a second;
reading port &F4 answers it and says how many there were) counts the
clock (1/300 s, as the CPC's), reads the keys every sixth and runs the
sound every third.

**The boot.** The PCW's boot program (the printer controller hands it to
the Z80 at power-on) reads track 0's first sector to &F000 and starts it
if its bytes add up to &FF. Ours (`boot.asm`; its first 16 bytes are the
disc's specification, as on every PCW disc) reads the rest of track 0:
the loader and the resident part. The loader sets up the screen, sees
whether block 16 is block 0 again (an 8256), reads the CP/M directory,
finds LISP.IMG's eight extents and reads them into blocks 8-15, copies
the resident part to block 4 and starts it.

**Discs** are CP/M's (`fdc.asm`, `files.asm`): our own routines on the
uPD765A, polled, the interrupts off for each transfer (a byte every 32
microseconds) and its terminal count the transfer's end. A disc says its
format in its first sector: the 8256's 180 KB (one side, 40 tracks, 9
sectors of 512, 1 KB blocks, 64 directory entries), an 8512's 720 KB B:
(two sides, 80 tracks, 2 KB blocks -- untested: ZEsarUX's PCW has one
drive). Files are CP/M's -- CP/M reads what
Lisp saves; a text file ends at its first ^Z. `dir` lists a disc as
AMSDOS does, four to a row; a file that is not there gets AMSDOS's "NAME
.EXT not found".

## The screen

720 by 256, 90 columns by 32 rows of eight by eight -- the Spectrum's font
made bold (the PCW's pixels are twice as high as wide). Text scrolls by
the roller RAM: the row going off the top is cleared and shown at the
bottom (port &F6). Graphics: the CPC's logical 640 by 400 on the 640
pixels in the middle and all 256 lines -- a unit a pixel across, 25/16
units a line -- in one colour: any pen lights a pixel, pen 0 puts it out.
`ink` 0 brighter than `ink` 1 makes the screen inverse. `mode` clears the
screen. The function editor uses all 90 columns.

## The keys

| PCW | CPC Lisp |
|---|---|
| STOP, EXIT | ESC: interrupts |
| COPY, f1 | COPY: copies from the copy cursor; in the function editor, done |
| f2 (SHIFT f1), ALT and S | CTRL-S: in the function editor, done |
| <-DEL | DEL: the character to the left |
| DEL-> | CLR: the character under the cursor |
| TAB | TAB |
| RETURN, ENTER | RETURN |
| the cursor keys | the arrows; up and down, the history |
| SHIFT and a cursor key | the copy cursor |
| SHIFT LOCK | capitals until pressed again |
| ALT and a letter | its control code |

The characters are the PCW's (UK), SHIFT the upper ones -- but three
keys give a Lisp what it needs more: 1/2 is ` (SHIFT @), the paragraph
sign \ (SHIFT <), SHIFT 3 # (not the pound). EXTRA and the paragraph sign
is |, EXTRA and 1/2 ~, EXTRA and = ^. `key-down-p` takes the keyboard's
numbers -- byte * 8 + bit, bytes 0-11 of its map -- and 96 for STOP or
EXIT.

## What works, and what not yet

* The language, **the compiler**, the editors, `format`, the extended
  `loop`, structures, hash tables, string streams.
* **Files** on drives A and B: `load`, `save`, `open`, `with-open-file`,
  `probe-file`, `delete-file`, `compile-file`, lazy loading; `(cd "b:")`.
* **The RAM disc**, `M:`, and **far arrays** there.
* **Floats**, the CPC's five-byte reals, all our own: + - * / rounded as
  the CPC's firmware rounds them (the Spectrum's `fparith.asm`); `sqrt`,
  `exp`, `log`, `sin`, `cos`, `tan`, `atan` by series
  (`fpfun.asm`, `tools/pcw/mkfpconst.py`) -- the float test prints what
  the CPC prints.
* **Sound**: the CPC firmware's sound manager (the Spectrum's
  `sound.asm`) on a DKTronics sound generator's AY, if there is one (an
  8-bit register is read back through &A9 at start and at every note,
  so the card may be switched on while Lisp runs); without one
  the beeper sounds while a note plays (one pitch, its own). In MiSTer's
  PCW core switch *DKTronics I/F* on in its menu; its AY runs as one at
  1 MHz, ZEsarUX's at 1.77 MHz (what the periods are made for): the
  tunes come out some seven semitones lower there. The real card's clock
  is not known here.
* `peek`, `poke`; `time` (1/300 s); `*features*` is `(:pcw :cpc-lisp)`.
* **Not here**: speech (`say` is quiet), MIDI, PlayCity, colours, and the
  CPC's own `symbol`, `window`, `tag`, `transparent`, `flash-speed`,
  `text-cursor`, `joystick`; the printer.

## A test of the real machine

`(load "hwtest")`, `(hwtest)`: ten checks, yes or NO -- the cells, the
compiler, a file on the disc, lazy loading from it and from `M:`, two
files open at once, the RAM disc, far arrays across its blocks, the
maths, the screen's pixels.

## In ZEsarUX

`tools/pcw/pcw.py` runs ZEsarUX 13.0 (`~/claude/spectrum/zesarux`, as the
Spectrum's tests) with no video or sound, at ten times the speed: a test
takes some five seconds. ZEsarUX boots a PCW from its disc as the real
one does -- its own copy of the boot program -- so each run starts from a
disc made for it (`tools/pcw/mkdisk.py`: the boot disc, its resident
part's RS_HARN set, and the test's files). ZEsarUX's remote protocol: a
breakpoint at EDHOOK gives the next line to machine page A's paste buffer,
the transcript comes from a ring in page A (T_BUF, which the Lisp fills
and the harness empties), and RS_QUITF ends it ((quit)). `-S shot.png`
and `!shot` draw the screen from its memory (the roller RAM), green on
black, each line twice. ZEsarUX's PCW has one drive: B: is A again there.
MAME's PCW needs the printer and keyboard controllers' ROMs, which are
Amstrad's: not used.
