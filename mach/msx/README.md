# CPC Lisp on the MSX

*Runs in openMSX (a Toshiba HX-10 -- Mike's ROM --, a 512 KB memory
mapper, Nextor 2.1.0 on a Sunrise IDE): the regression tests, 43 of 43,
and the hardware test, 10 yes. Not yet tried on a real machine.* The same
Lisp as on the CPC -- the six images are built from the same sources, the
compiler included -- on an **MSX1** (or any later MSX) with a **memory
mapper** that has **144 KB free** under **MSX-DOS 2 or Nextor**: say an
MSX SD Mapper & Megaram 512 KB cartridge (its switches at ON and MP: the
RAM on, a mapper), which brings both.

## Building, installing and starting

    MACH=msx tools/build.sh          # build/msx: the images, the machine
                                     #   pages, LISP.COM, LISP.IMG, and sd/
                                     #   -- the files for the SD card
    tools/msx/msx.py file.lsp        # type a file at it in openMSX
                                     #   (headless), print the transcript
    tools/msx/test.sh                # the regression tests

Copy what is in `build/msx/sd/` to the SD card, into a folder of its own
(`LISP`, say): `LISP.COM`, `LISP.IMG` (the images, 128 KB), `HWTEST.LSP`
and the examples (`APFEL.LSP`, the classics). Switch on, and at DOS's
prompt:

    A>CD LISP
    A:\LISP>LISP

`LISP.COM` finds `LISP.IMG` beside itself (DOS's `PROGRAM`), wherever it
is started from; Lisp's files are DOS's current folder's. It says what is
missing if it cannot start: MSX-DOS 2, a mapper with 144 KB free, room in
DOS's memory, `LISP.IMG`. `(quit)` -- and `(reset)` -- go back to DOS's
prompt, on its own screen, the mapper's segments given back.

## How it is arranged

The memory mapper gives Lisp eight segments of 16 KB: the six images and
two machine pages; the RAM disc has the rest. DOS's own four segments are
the Lisp's RAM and DOS's.

| | |
|---|---|
| &0000-&00FF | DOS's: its jumps, the interrupt's at &0038 (ours while Lisp runs), the command line |
| &0100-&04FF | the resident part: SYS_BANK, the jumpblock, the interrupt, the ways to DOS and the ROM (`resident.asm`); `LISP.COM` starts here, the loader after it |
| &0500-&19FF | the low system area, the symbols (`memmap.asm`) |
| &1A00-&7AFF | the Lisp's RAM: cells, strings, the stack -- 2899 cells at the start, 7.6 KB of strings |
| &7B00-&7FFF | the fixed variables and buffers |
| &8000-&BFFF | machine page A or B (`page.asm`, `pageb.asm`) while one of their routines runs; a RAM disc segment for one copy; else DOS's segment |
| &C000-&FFFF | one image at a time: the core, library parts 0-3, the VM; DOS's segment -- the BIOS's and DOS's variables -- only while the resident part calls DOS or the ROM |

A call of a machine routine goes to the resident jumpblock, which maps the
machine page at &8000, calls the routine and maps back what was there
(`mfar`). DOS is called through the resident part (`RS_DOS`), which puts
DOS's segments back in pages 2 and 3 and its interrupt, on a stack of its
own in DOS's page 3; the Math-Pack the same way (`RS_MATH`), with the main
ROM in pages 0 and 1 too. The mapper's ports cannot be read: `RS_P2` says
what page 2 holds. The interrupt (the VDP's, 50 or 60 a second: the main
ROM says which) is ours while Lisp runs -- DOS's jump at &0038 points at
`r_int` -- and runs page A's tick (the clock, the keys), then page B's
(the sound, 100 times a second). If DOS meets an error in a call -- a disc
error, CTRL-STOP -- it calls `r_abort`, which returns from that call with
the error (`D_DEFAB`, `D_DEFER`).

## The screen

The VDP's screen 2, 256 by 192, in 40 columns and 24 rows -- the CPC's
mode 1 -- in the Spectrum's font (5 by 7 in 6 by 8, `font.inc`), centred;
yellow on blue, as the CPC starts. It is seen only through the VDP's
ports: a character is its cell's bytes read, changed and written back; a
scroll moves each row through a buffer -- some 0.1 s, about the CPC's
firmware's speed for a line. `ink` 0 and 1 colour the paper and the text,
`border` the border, in the VDP's fifteen colours (the CPC's 27 made the
nearest). A graphics pen lights a pixel in its colour and gives that
colour to its 8 pixels across (screen 2's way: finer than the Spectrum's 8
by 8 cells; text there takes it too). Graphics are the screen's pixels,
from the CPC's logical 640 by 400 (a pixel is 2.5 units wide and 25/12
high). `mode` only clears the screen.

## The keys

| MSX | CPC Lisp |
|---|---|
| ESC, STOP | ESC: interrupts |
| F1, SELECT | COPY: copies from the copy cursor; in the function editor, done |
| F2 (or CTRL and S) | CTRL-S: in the function editor, done |
| BS | DEL: the character to the left |
| DEL | CLR: the character under the cursor |
| TAB | TAB |
| the cursor keys | the arrows; up and down, the history |
| SHIFT and a cursor key | the copy cursor |
| CAPS | capitals until pressed again (its lamp says so) |
| CTRL and a letter | its control code |

The characters are the international layout's, SHIFT the upper ones:
`[ ] { } ~ | \ `` ` are on their own keys. GRAPH and CODE give nothing.
`key-down-p` takes the matrix's numbers -- row * 8 + bit, rows 0-8 -- and
72 for ESC or STOP.

## What works, and what not yet

* The language, **the compiler**, the editors, `format`, the extended
  `loop`, structures, hash tables, string streams.
* **Files** through DOS on the SD card: `load`, `save`, `open`,
  `with-open-file`, `probe-file`, `delete-file`, `compile-file`, lazy
  loading; `dir` lists the current folder as AMSDOS lists a disc, with
  what is free. A name may have a drive (`b:name`) or a path: DOS takes it
  as it is. `(cd "b:")` makes B: DOS's current drive (if there is one),
  `(cd)` says which, `(cd nil)` the start's again.
* **The RAM disc**, drive `M:`, in the mapper's segments that are left: 271
  KB with a 512 KB mapper (up to 32 segments, 512 KB) -- `(save
  "m:work")`, `(dir "m:")`, streams, and **far arrays** there. DOS frees
  the segments when Lisp ends: `M:` lasts while Lisp runs.
* **Floats**, the CPC's five-byte reals: + - * / here, rounded as the
  CPC's firmware rounds them (the Spectrum's `fparith.asm`); `sqrt`, `exp`,
  `log`, `sin`, `cos`, `tan`, `atan` by the main ROM's Math-Pack (BASIC's
  maths, 14 decimal digits: `fpmsx.asm` turns a real into its numbers and
  back). The float tests print what the CPC prints.
* **Sound** on the PSG, the CPC firmware's sound manager (the Spectrum's
  `sound.asm`, shared): `sound`'s three channels, each a queue of four,
  `envelope` and `tone-envelope`, rendezvous, `release`, `sound-check`,
  `sound-hold`, `sound-continue`; `play`, the tunes. The periods are made
  the PSG's (it runs at 1.7898 MHz, the CPC's at 1): the same pitch.
* `peek`, `poke` (&8000-&BFFF is DOS's spare segment then); `time` (the
  interrupt's count, in 1/300 s); `*features*` is `(:msx :cpc-lisp)`.
* **Not here**: speech (`say` is quiet), MIDI (an MSX1 has none: the bytes
  go nowhere), PlayCity, and the CPC's own `symbol`, `window`, `tag`,
  `transparent`, `flash-speed`, `text-cursor`, `joystick`.

## A test of the real machine

`(load "hwtest")`, `(hwtest)`: ten checks, yes or NO -- the cells, the
compiler, a file on the SD card, lazy loading from it and from `M:`, two
files open at once, the RAM disc, far arrays across its segments, the
Math-Pack, the colour pens.

## In openMSX

`tools/msx/msx.py` runs openMSX (19.1, Ubuntu's) with no video or sound
(`SDL_VIDEODRIVER=dummy`, `set renderer none`), its throttle off -- a test
takes about a second. Its machine is in `~/claude/msx` (`MSX_DIR`):
`home/` is its `OPENMSX_HOME`, whose system ROMs are Mike's HX-10's (his
dump: `tools/msx/romdump.asm`, A:\LISP\ROMDUMP.COM on his card, saves the
main ROM as MAINROM.BIN; openMSX's `Toshiba_HX-10` knows it by its SHA1)
and Nextor 2.1.0's Sunrise IDE ROM; `files/` has NEXTOR.SYS and
COMMAND2.COM (Konamiman's release). None of it is ours: never in this
repository. C-BIOS, openMSX's free BIOS, cannot start a disc ROM (it has
no BASIC): a real machine's ROM is needed for DOS.

Each run makes a hard disc afresh (`tools/spectrum/mkmmc.py`, FAT16):
DOS's files, an AUTOEXEC.BAT that starts Lisp, and the folder LISP. openMSX
runs a Tcl script made by `msx.py`, in step with the emulation: a
watchpoint on port &2F writes the transcript (Lisp sends what it prints
there when started as `LISP /T`), one on &2E ends it ((quit)); a
breakpoint at EDHOOK gives the next line to machine page A's paste
buffer, written through openMSX's debuggable of the mapper's RAM. `-S
shot.png` and `!shot` draw the VDP's memory into a picture; `-x file.tcl`
adds Tcl of one's own (a log of the PSG's writes, say).
