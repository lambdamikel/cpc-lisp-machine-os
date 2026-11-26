# CPC Lisp on FutureOS

*A Lisp machine for the Amstrad CPC* -- natively on TFM's
[FutureOS](https://futureos.de), new in 1.0. FutureOS stays resident,
its RAM untouched, and Lisp runs beside it, using FutureOS's own
functions where it has them: **loading** (LADE_N, from any FutureOS
drive), **files** (TEISI, SIDIR, EWEG) and **character output** (PR_2).
TFM asked for exactly that; Mike chose this way on 2026-11-19. (The
firmware island, [`mach/futureos`](../futureos/README.md), was the
first way: it starts the CPC's own firmware beside FutureOS.)

    CPC Lisp 1.2.1
    A Lisp machine for the Amstrad CPC on FutureOS
    library ROMs 1 2 3 4
    4713 cells free

**Ready-made: [`discs/cpclispfos-n.dsk`](../../discs/cpclispfos-n.dsk)**
(build 1000).

## What it needs

* A CPC **464, 664 or 6128 with FutureOS** -- its ROMs in a ROM board
  (Mike's: the LambdaSpeak 4 card's slots).
* **A 512K RAM expansion that does configuration C3 as the 6128 does**,
  which FutureOS needs anyway: Revaldinho's card, in configuration 8 (ON
  OFF OFF OFF) on a 464 and 0 on a 6128. Lisp takes the expansion's
  blocks FutureOS has free when it starts and gives them back at
  `(reset)`.
* `cpclispfos-n.dsk` in **any FutureOS drive**: a real or Gotek drive
  A or B, the LambdaSpeak card's drive (A at &FB7E, or E as a Vortex
  drive)... The images load from the drive `LISP.64K` came from.

## Using it

On FutureOS's desktop:

    SPACE, A        read drive A (SPACE, E for drive E...)
    LISP.64K        tag it: the pointer on it, COPY
    X               RUN -- the seven images load, and LISP> comes up
    (reset)         back to the desktop, the drives still read
    D, LISP.64K, X  start it again (M:'s files are still there)

Everything CPC Lisp has is there: the compiler, `compile-file`, the
line and function editors, floats (the lower ROM's maths package:
FutureOS has none), graphics in modes 0-2 and the sixteen inks, sound
with the firmware's envelopes, speech through the LambdaSpeak card, and
the disc's test, `(load "hwtest")`, `(hwtest)` -- 7 yes; after `(reset)`
and `LISP.64K` again, `(load "hwtest")`, `(hwtest2)`.

* **Files on any drive**: `(dir "e:")` lists a drive (reading its
  directory again: a swapped disc is seen), `(cd "e:")` makes it the
  drive for names without one, `(cd)` says which; `load`, `save`,
  `open`, `delete-file` take `e:name` as well. Files up to 48 KB.
* **The RAM disc `M:`** (191 KB) and **far arrays** live in the
  expansion's free blocks; `M:` outlasts `(reset)` and a new start,
  unless the desktop used those blocks meanwhile.
* **Memory**: 4713 cells at the start (the heap is &1500-&8FFF).
* **A damaged image** stops the start on the desktop: "CPC Lisp:
  LISP3.IMG came in damaged (its checksum). Try again."
* It is quicker than the firmware: text comes through FutureOS's PR_2,
  and graphics rows are written a byte at a time.

| where | what | result |
|---|---|---|
| MAME, 464 and 6128 | FutureOS's ROMs in the ROM box, 576K, `tools/fos/run.sh` | `(hwtest)` 7 yes, files, graphics, sound (the AY's writes timed against the firmware's), `M:`, `(reset)` and restarts |
| Mike's 6128 | Revaldinho's card in configuration 0; FutureOS from the LambdaSpeak 4 card's slots (its 664/6128 firmware); the disc on the card's drive E and on the Gotek as A | 2026-11-19: hwtest 7 yes, `(rose)`, `(tune)`, `(say)`, `save` and `load` on E and A, `cd`, `dir`, `(reset)`, `(hwtest2)` |
| Mike's 464 | the 1.0 ROM; Revaldinho's card in configuration 8; FutureOS from the card's slots (its 464 firmware); the disc in the card's drive as A | 2026-11-20: hwtest 7 yes, `(rose)`, `(say)`, three starts with `(reset)` between, `(hwtest2)`, `save` and `load` of everything hwtest defined; then the checksum's build too |

The 664 is untried.

## How it came about (2026-11-19/20)

**Phase 1** -- the REPL, the line editor, the function editor, floats,
ESC, scrolling, `(room)`, `(time)`, `(reset)` back to the desktop --
runs in MAME on a 464 and a 6128 and **passed on Mike's 6128** the same
day (build 30098, `cpclispfos-n.dsk` in the LambdaSpeak card's drive,
FutureOS's drive E; FutureOS from the card's slots, Revaldinho's card in
configuration 0): the banner, sums and floats, scrolling, a wrapped
line, the history, the function editor, ESC, `(room)`, `(reset)` -- "all
works, and much snappier".

**Phase 2, files through FutureOS**, runs in MAME on both: `load` (lazy
too), `save`, `compile-file` and loading the `.fas`, `open` and
`with-open-file` both ways, two files at once, `probe-file`,
`delete-file`, `(dir)`; files up to 48 KB (34 KB tried: three extents);
a full disc says so ("NAME.EXT not saved: disc full", then Lisp's "cannot
write the file"). Not on the real machine yet.

**Phase 3a, graphics** (MAME): text in modes 0, 1 and 2 (in mode 2
FutureOS's PR_2 draws the lower ROM's characters; anything else -- modes
0 and 1, user-defined characters, other inks -- our own renderer), all
sixteen inks, `plot`, `draw`, `test`, `move`, the origin, the ink modes
(XOR...), `clg`, `disc`, `fill-box`, `flood-fill`, the demos (`shapes`,
`rose`, `koch`, `tree`). A row is written a byte at a time (discs are
rows: 15 nested discs in mode 1 take 1257 ticks, the firmware 1619); a
slanted line a pixel at a time (twice the firmware's time).

**Phase 3b, sound** (MAME): the firmware's sound manager cut down --
three channels, a queue of four sounds each, noise, amplitude and tone
envelopes (`envelope`, `tone-envelope`, repeating and absolute sections
too), rendezvous between channels (a sound on several starts on all at
once), sounds held until `release` -- played on the AY by the page's
`snd_tick`, 100 times a second from the interrupt. `sound`, `play`, the
tunes, `sound-check`, `sound-hold`/`sound-continue`. **Timed as the
firmware plays them**: the AY's register writes logged with their times
(`LISP_AYLOG=file LISP_AYTIME=1`, emu/repl.lua; `tools/aytimes.py`) on the ROM version (the
464's own firmware) and here, and compared channel by channel -- the
same to within 1/100 s (the interrupts run at 300.48 Hz, so the stamps
jitter by one). What the firmware does, measured so: an envelope's
first step as the sound starts, then one every pause (0: 256); without
an amplitude envelope the volume is doubled (BASIC's 0-7: 8 is silent);
a duration of 0 is the amplitude envelope's length (or two seconds), a
negative one that many times over, the volume carrying on; a repeating
tone envelope carries the period on; a tone section of 240 steps or
more sets the period (its low four bits and the next byte).

**Phase 4, the RAM disc `M:` and far arrays** (MAME, both machines):
the 512K version's, in the expansion's blocks 0-2 of banks 1, 2, 4 and
5 -- 191 KB, those FutureOS has free when `LISP.64K` starts (it marks
them in use by a program while Lisp runs; `(reset)` gives them back).
test/discram and test/discfar come out as on the 512K but for the sizes.
`M:` outlasts `(reset)` and a new start of `LISP.64K` unless the desktop
used those blocks meanwhile (a copy may). The disc's own test is
`HWTEST.LSP` (`mach/fos/hwtest.lsp`): `(load "hwtest")`, `(hwtest)` --
7 yes in MAME on both -- and after `(reset)` and `LISP.64K` again,
`(load "hwtest")`, `(hwtest2)`: 2 yes.

**Fitting in with the desktop** (2026-11-19, after TFM's guides, "How
to create an Application for FutureOS" and "Programmieren unter
FutureOS in Assembler"): Lisp is a full-screen program, as the guides
describe them -- FutureOS has no overlapping windows; its desktop is the
icons above and the file window below, and a program that leaves the
icons alone goes back with KLICK, one that takes the screen with TUR_D
or TUR_E. Lisp's text is in **FutureOS's colours** now (its border and
inks 0 and 1, ROM B's table at &FE0B, read by `LISP.64K`; inks 2-15 stay
the firmware's, for the demos), and `(reset)` goes back through
**TUR_E**: the drives stay tagged and their directories read (TUR_D
forgot them), so to start Lisp again, D, tag `LISP.64K`, X -- or tag
another drive first (SPACE and its letter). **Any drive**: `(dir "e:")`
lists a drive's files, `(cd "e:")` makes it the drive for names without
one (`load`, `save`, `open`, `dir`; T, or NIL for no such drive) -- A to
L, M: being Lisp's RAM disc; `(cd)` says which, `(cd nil)` goes back to
`LISP.64K`'s (as on every port since: `drive.asm`, RS_DRIVE and
RS_START). `(dir)` reads a drive's directory (below), so after `(dir
"b:")` B's files load and save even if the desktop never read it. In MAME with a second disc in drive B
(read after a `(reset)`): `dir`, `cd`, `load`, `save`, `delete-file` on
B, and `(load "b:bar")` from A.

Every part of the plan is done, and **all of it passed on Mike's 6128**
(2026-11-19; FutureOS from the LambdaSpeak 4 card's slots, Revaldinho's
card in configuration 0, the disc on the card's drive E and on the
Gotek, drive A): FutureOS's colours, hwtest 7 yes, `(rose)`, `(tune)`,
`(say)`, `save` and `load` on E -- FutureOS's first writes to the card's
Vortex drive -- and on A, `(cd "a:")`, `(dir "a:")`, `(reset)` back to
the desktop and `(hwtest2)` after it. (A `(save)` of everything after
hwtest wrote its far array as `#S(...)`, which the reader could not read
back until that day's fix, on every machine.) **And on Mike's 464**
(2026-11-20, build 9475: the 1.0 ROM, Revaldinho's card in
configuration 8, the disc on the card's drive at &FB7E, FutureOS's
drive A): hwtest 7 yes, `(rose)`, `(say)`, three starts with `(reset)`
between, `(hwtest2)`. The desktop shows each
drive's buffered directory, so listing a drive there touches nothing --
and Mike's Gotek shows no activity when it is read.

**The third start that failed** (Mike's 6128, 2026-11-19: from the
card's drive E with `(reset)` before each, "unexpected end of text")
was the card: a status read in mid-sector now and then got &00, and
FutureOS's sector loop gave that sector up while `LADE_N` still said
the file loaded -- an image came in short. Fixed in the card's
firmware (lambdaspeak4 40b0fc3); three starts with `(reset)` passed.
Since then `LISP.64K` checks each image's checksum (the sum of its
16-bit words, written into it by the build) and stops at a damaged one
on the desktop: "CPC Lisp: LISP3.IMG came in damaged (its checksum).
Try again."

## Files

A name is `[d:]name[.ext]`, `d` a FutureOS drive A-L (`m:` is Lisp's
RAM disc); without one, the drive `LISP.64K` came from, or the one
`(cd "d:")` chose. Lisp reads FutureOS's **buffered directories**: the
drive `LISP.64K` came from, those tagged on the desktop -- and **`(dir)`
reads them again** (GET_DIR, ROM D, as the desktop's D: every tagged
drive's, the one listed tagged too), so after changing a disc, or for a
drive not read on the desktop, `(dir "b:")` first. Not while a file is
being written (GET_DIR takes a free block of the expansion for the low
16 KB, and bank 0's free blocks hold that file): then the buffered one
is listed. MAME: a disc changed while Lisp runs (repl.lua's `!disc N K
file`) was seen, read, written.

* **Reading**: the file is loaded whole by **LADE_N** into the
  expansion (bank 6's blocks 0-2, at most 48 KB), its length from the
  directory's extents ((EX + 32 S2) x 128 + RC records); FILE_GETC (the
  resident part) reads it from there, to that length or the first &1A.
* **Writing**: FILE_PUTC collects it in bank 0's blocks 0-2; closing
  pads the last record with &1A and calls **TEISI**, FutureOS's "save a
  file from the short-time buffers", then **SIDIR** to write the
  directory back. An old file of the name goes when it is opened
  (**EWEG**, in the buffered directory).
* **`delete-file`** finds `|ERA` as on a CPC (KL FIND COMMAND, KL FAR
  PCHL): the page answers with EWEG and SIDIR.

What TEISI needed, found by reading FutureOS's ROM C (TFM's label file is
not here) and in MAME:

* It writes from the **short-time buffers**: the expansion blocks whose
  XRAM mark (&B9D0, one byte a block) is &09, in XRAM order -- and first
  it calls FESB, which marks every *free* block so (&01 and &09 alike;
  anything else stays). So `LISP.64K` marks Lisp's own blocks &11 (in
  use by a program) -- the images, the page, its buffers -- and leaves
  the output file's, bank 0's blocks 0-2, free: the first in XRAM order.
  `(reset)` puts FutureOS's marks back. Without the marks TEISI wrote
  into the buffers' block and the return went astray.
* It writes in **&0000-&3FFF**, Lisp's symbols and cells: the gate keeps
  them in a block of its own for that call (bank 7's block 0).
* Its count of **blocks** is &B8C4, the last extent's **records**
  &BBCC and the last record's **bytes** &BBCD (G_BLK's, ROM C &FBD5,
  sets them so); the name at REG16_8 (&B8F4).
* A directory marked **changed** (bit 3 of its drive's tagging byte,
  which EWEG sets) is sorted in the first free block first: the bits are
  cleared for the call and put back after.
* FutureOS's functions may leave **its IM 2** (or its RET at &0038):
  the gate puts our IM 1 and &0038 back after each, and runs them on
  FutureOS's own stack (where `LISP.64K` found it), with &8000-&8FFF
  (Lisp's stack) kept aside: loads over 16 KB may use it.

## How it is arranged

* **LISP.64K** (`loader.asm`), started from the desktop, loads seven
  images through FutureOS's LADE_N from its own drive -- the core, the
  library's four parts, the VM ROM and the **machine page**
  (`page.asm`, LISP6.IMG) -- into block 3 of banks 0-2 and 4-7, puts the
  resident part at &9000, keeps FutureOS's &0000-&00FF in the page,
  takes the interrupts (IM 1, &0038), builds the maths jumpblock, sets
  FutureOS's 80 x 25 screen (S80X25) and starts the core.
* **The machine page** has a routine for each CPC firmware routine Lisp
  calls (82 names, `tools/fos/mkfw.py`), with the firmware's contract:
  the text screen (control codes, windows, hardware scrolling, the
  cursor, a copy of the characters for the copy cursor), the keys (the
  firmware's translation tables, the keyboard's scan), the screen's mode
  and inks, graphics, sound, files through FutureOS.
* **The resident part** (`resident.asm`, &9000-&9AFF) is what must be in
  the main RAM: a trampoline per firmware name into the page, the bank
  switch, the interrupt -- a 300 Hz tick, and every third the page's
  `p_tick`: the sound, the keyboard's matrix every other time --,
  drawing a character with **FutureOS's PR_2** (ROM A, the lower ROM's
  font), what else writes the screen, the maths call, the files' bytes
  (FILE_GETC, FILE_PUTC: M:'s in the library's bank, through `rd_far`),
  the RAM disc's copying (RS_XFER: a unit's block at &4000, the other
  side through a 64-byte buffer), and the way back to FutureOS (its
  restarts, XRAM marks and RAMCHAR, its font copy at &3800, its 64 x 32
  screen and colours, IM 2, TUR_E). About 110 bytes are left.
* **Floats**: FutureOS has none; the lower ROM's maths package is called
  at its real addresses (read from the lower ROM's own jumpblock table:
  &08AC on a 464, &08DE on a 6128), with the lower ROM in and the
  interrupts off, its RAM (&B8D0-&B8F7 on a 464, &B100-&B117 on a 6128,
  FutureOS's variables now) swapped with a copy of its own for the call.
* **Memory**: FutureOS keeps &A000-&BFFF; the fixed area is
  &9B00-&9FFF, the heap &1500-&8FFF (4713 cells at start, against 5497
  in the island).

## Building and testing

    MACH=fos tools/build.sh         # build/fos: the images, LISP.64K,
                                    #   cpclispfos-n.dsk
    tools/fos/run.sh [-m 6128] [-f frames] [-s shot.png] file.lsp

`run.sh` is `tools/futureos/run.sh`'s: FutureOS in MAME, drive A's
directory read, `LISP.64K` tagged and run; Lisp's output is caught at
its TXT OUTPUT trampoline (`LISP_TXTOUT`). After a change to
`mach/cpc/firmware.asm`'s names: `python3 tools/fos/mkfw.py`.
