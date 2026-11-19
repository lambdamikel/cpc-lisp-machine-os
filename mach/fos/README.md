# CPC Lisp on FutureOS itself (in progress)

*A Lisp machine for the Amstrad CPC* -- natively on TFM's FutureOS: no
firmware island (that is [`mach/futureos`](../futureos/README.md), the
released version). FutureOS stays resident, its RAM untouched, and Lisp
runs beside it, using FutureOS's own functions where it has them:
**loading** (LADE_N, from any FutureOS drive) and **character output**
(PR_2, mode 2). TFM asked for exactly that; Mike chose this way on
2026-11-19.

    CPC Lisp 0.99
    A Lisp machine for the Amstrad CPC on FutureOS
    library ROMs 1 2 3 4
    4713 cells free

## State (2026-11-19)

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
three channels, a queue of four sounds each, noise, amplitude envelopes
(`envelope`; no tone envelopes or rendezvous yet) -- played on the AY by
the page's `snd_tick`, 100 times a second from the interrupt. `sound`,
`play`, the tunes, `sound-check`, `sound-hold`/`sound-continue`. Checked
by logging the AY's register writes (`LISP_AYLOG=file`, emu/repl.lua):
the periods, volumes, noise and mixer as asked.

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
L, M: being Lisp's RAM disc. FutureOS must have read that drive's
directory (tag it on the desktop: SPACE and its letter); else "No
directory read for this drive". In MAME with a second disc in drive B
(read after a `(reset)`): `dir`, `cd`, `load`, `save`, `delete-file` on
B, and `(load "b:bar")` from A.

Not yet: reading a directory from Lisp (GET_DIR, ROM D: it would want
expansion RAM the RAM disc has now), re-reading one after a disc is
changed, tone envelopes and rendezvous in the sound.

## Files

A name is `[d:]name[.ext]`, `d` a FutureOS drive A-L (`m:` is Lisp's
RAM disc); without one, the drive `LISP.64K` came from, or the one
`(cd "d:")` chose. FutureOS must have **read that drive's
directory** -- tagging `LISP.64K` did that for its own drive; for
another, tag it on the desktop before starting Lisp. Lisp reads
FutureOS's buffered directories, so a disc changed while Lisp runs is
not seen yet.

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
