# CPC Lisp under FutureOS -- the firmware island

**Since 1.0 there is a native version**, which runs on FutureOS itself,
through its own routines and from any of its drives:
[`mach/fos`](../fos/README.md), `discs/cpclispfos-n.dsk`. This one
still works and stays available.

CPC Lisp started from FutureOS's desktop, on a CPC 464, 664 or 6128
with a 512 KB RAM expansion; `(reset)` goes back to the desktop. It is
the 512K disc version, run as a *firmware island*: Lisp puts FutureOS's
RAM aside, starts the CPC's own firmware for itself, and gives FutureOS
everything back at the end. TFM, FutureOS's author, asked for it; Mike
set it as the goal for 2026-11-17, and it passed on his 464 and his 6128
that evening. **Video:** [CPC LISP running on the CPC 6128 with FutureOS -- Vortex Floppy Emulation with LambdaSpeak AI](https://youtu.be/s4BsQOroQUc) (5:08).

    CPC Lisp 1.2.1
    A Lisp machine for the Amstrad CPC, 512K
    library ROMs 1 2 3 4
    5497 cells free

Nothing of FutureOS is in this repository. TFM's ROMs, discs and
documents are free for non-commercial use from futureos.de.

Contents: [What it needs](#what-it-needs) · [Building](#building) ·
[Installing](#installing) · [Starting it](#starting-it) ·
[How it works](#how-it-works-a-firmware-island) ·
[The lower ROMs](#the-lower-roms) · [Memory](#memory) ·
[The screen](#the-screen) ·
[The disc ROM and the images](#the-disc-rom-and-the-images) ·
[FutureOS while Lisp runs](#futureos-while-lisp-runs) ·
[What was tested where](#what-was-tested-where) ·
[Testing in MAME](#testing-in-mame) · [Further](#further)

## What it needs

* **A CPC 464, 664 or 6128 with FutureOS**, its ROMs on a ROM board or
  in the LambdaSpeak 4's slots.
* **A 512 KB RAM expansion** that banks the DK'tronics way (configurations
  &C0-&C7 on port &7Fxx, bits 3-5 the bank), and does configuration &C3 as
  a 6128 does -- FutureOS needs that. **Revaldinho's universal RAM card:
  configuration 8 on a 464** (DIP 1234 = 1000: bank 3 shadows the base
  RAM, which gives a 464 the 6128's C3), **configuration 0 on a 6128**
  (DIP 1234 = 0000: the 6128 does C3 itself). Lisp uses banks 0-2 and 4-7
  (below); bank 3 it leaves alone on every machine.
* **A disc with this version on it, in drive A**, and the machine's disc
  ROM as ROM 7 to read it: AMSDOS (a 6128's or 664's own, a 464's DDI-1)
  or Parados; VDOS 2.0 with a Vortex disc in principle (below).
* **With the LambdaSpeak 4 card, the card's firmware for the machine.**
  On a 464 the card's own 464 firmware. On a 664 or 6128 its 664/6128
  build, **flashed before the card goes in**: the 464 firmware's drive
  at &FB7E and its disc ROM at 7 would fight the machine's own
  controller and AMSDOS for the data bus. The 664/6128 build never
  answers ROM 7, keeps its drive at the Vortex controller's &FBF6/&FBF7
  from power-up (FutureOS's drive E), has no flash discs, and restores
  the fast ROM select FutureOS needs from the 464's settings.
  lambdaspeak4's `docs/two-firmwares.md` has why and how; its
  `docs/futureos.md` FutureOS on the card.

## Building

    MACH=futureos tools/build.sh

makes, in `build/futureos/`:

| file | |
|---|---|
| `LISP.64K` | what FutureOS starts: loaded at &8000, started at &9000 (its AMSDOS header says so) -- the stub (`loader.asm`) and the 512K version's loader carrying the resident part (`loader512.asm`, a link to `mach/cpc512/loader.asm`) |
| `LISP0.IMG`-`LISP5.IMG` | the six images: the core, the library's four parts, the VM ROM |
| `cpclispfos.dsk` | a data-format disc with `LISP.64K`, the six images, `HWTEST.LSP` (the 512K version's test, check 5 sized for this version's smaller RAM disc) and `APFEL.LSP` |
| `cpclispfos-vortex.dsk` | the same files on a Vortex disc (80 tracks, 2 sides, 9 sectors of 512 bytes; `tools/futureos/vortexdisk.py`), for VDOS -- see below |

Everything but `variant.asm`, `loader.asm`, `fosback.asm`, `fos.asm`,
`hwtest.lsp` and `post-build.sh` is a link to `mach/cpc512`; the parts
that differ there are `ifdef FUTUREOS`, and the 512K and plain-6128
versions build byte for byte the same with or without them (checked
with `BUILD_ID=77` before and after each change).

**Ready-made: [`discs/cpclispfos.dsk`](../../discs/cpclispfos.dsk)**,
build 4236, the one that passed on Mike's 6128.

## Installing

Put `cpclispfos.dsk` where the machine's drive A reads it:

* **A Gotek** (FlashFloppy): copy it to the stick and select it.
* **The LambdaSpeak card's drive**, from the PC:
  `~/git/lambdaspeak4/tools/dskloader.py cpclispfos.dsk`. The disc then
  lives in the card's PSRAM and is lost when the card loses power (the
  CPC off with the card's USB unplugged): keep the USB in. On a 464 the
  card's drive is drive A with Parados as ROM 7 -- type `|DDI1,4` at
  BASIC if the card is in its Vortex setup. On a 6128 the card's drive is
  FutureOS's drive E: `LISP.64K` loads the images from there too,
  through FutureOS (since 2026-11-19). Lisp's own files -- `load`,
  `save`, `(dir)` -- still go through AMSDOS, which knows only A and B:
  for those the disc must be in drive A as well.
* **A real disc**: write the .dsk with any CPC disc tool.

## Starting it

On FutureOS's desktop:

    |OS             (at BASIC) FutureOS's desktop
    SPACE, A, D     "Medium: A-M?" -- drive A's directory
    LISP.64K        tag it: the pointer on it, COPY
    X               RUN

The screen turns blue: "CPC Lisp for the 512K expansion: loading",
"LISP0.IMG-LISP5.IMG through FutureOS", the banner, `LISP>`. To check
the machine:

    (load "hwtest")
    (hwtest)        seven checks, each yes or NO; check 5 takes minutes

**`(reset)` goes back to the desktop.** What goes wrong at the start is
said on the blue screen, and a key then goes back to the desktop:

* `Too many ROMs: their workspace is where CPC Lisp's resident part goes,
  under &A6B0.` -- the disc ROM wants more workspace than there is room
  for (below);
* `No 512K expansion found ... Banks of 64K that answer: n (of 8).` --
  fewer than six banks answer (a shadow mode where it should not be, a
  smaller expansion);
* `Cannot load it: is the CPC Lisp disc in?` -- FutureOS did not find
  the images on the drive `LISP.64K` came from, and the disc ROM found
  no `LISP0.IMG` in drive A either.

If the lower ROM is none of the three below, `LISP.64K` goes straight
back to the desktop without a blue screen.

## How it works: a firmware island

FutureOS keeps its variables, tables and stack at &A000-&BFFF -- where
the CPC's firmware keeps its own -- and its restarts at &0000-&00FF. The
firmware is still there, in the lower ROM, so Lisp takes the RAM back
for a while:

1. **FutureOS loads `LISP.64K`** at &8000 and starts it at &9000.
2. **The stub loads the six images through FutureOS** -- its LADE_N,
   "load a file of defined name from a defined medium" (ROM C) -- from
   the drive `LISP.64K` came from (FutureOS's REG_PC+1), each into the
   main RAM at &4000 (load type 2, which takes the AMSDOS header off),
   then copies it into its bank's block 3, mapped at &C000
   (configuration &C1 + 8 × bank). Meanwhile `LISP.64K`'s first 4 KB,
   the loader, waits in bank 7's block 3: a load into the main RAM may
   write past a file's end, a sector at a time. Then the drive motors
   off: FutureOS, which would stop them, is off from here on.
3. **The stub puts FutureOS aside** in bank 7's block 3, mapped at &4000
   (configuration &FF): &A000-&BFFF, &0000-&00FF, the way back
   (`fosback.asm`) and the numbers of FutureOS's ROMs B and D, read from
   its API page (&FF07, &FF13).
4. **It finds the firmware**: MC START PROGRAM's body in the lower ROM,
   at &060E, &061F or &0609 (below), checked by its first seven bytes.
5. **It gives the screen the firmware's geometry** (below).
6. **It jumps into MC START PROGRAM's body** with DE = its next routine,
   as the firmware starts a program: the firmware's RAM is cleared,
   every pack initialised (screen, text, graphics, keys, sound, cassette
   vectors), IM 1, EI -- and then the routine is called. There is no
   ROM walk and no BASIC.
7. **The 512K version's loader** starts ROM 7 only, through KL INIT
   BACK: the disc ROM. A ROM walk would start FutureOS's four ROMs too,
   whose workspace would take the resident part's room. It checks the
   disc ROM left the resident part room, counts the expansion's banks,
   puts the resident part at &A100 and starts Lisp. If FutureOS could
   not load the images (step 2), it reads them through the disc ROM
   first, from drive A.
8. **Lisp is then the 512K version**: the firmware for text, graphics,
   sound and keys, the disc ROM for files, the expansion for its code,
   the RAM disc and far arrays.
9. **`(reset)`** -- the resident part's reset -- maps bank 7's block 3,
   copies the way back (192 bytes, `FOS_BACK_LEN`) to &8000 and runs it:
   FutureOS's RAM and restarts back over the firmware's, its colours
   (ROM B's table at &FE0B, which its desktop does not set), its screen
   geometry and start, the main RAM in, mode 2, ROM D, IM 2 with I = &BD,
   SP = &C000, and TUR_D (ROM D &FEA0), which draws the desktop afresh.

If the firmware is not found, or the loader fails, the stub runs the
same way back.

## The lower ROMs

The same routine -- MC START PROGRAM's body, entered with DE the routine
to call once the firmware is up -- sits at a different address in each
lower ROM. `LISP.64K` checks for its first seven bytes (`di : im 1 : exx
: ld bc,&DF00`) at each address in turn and jumps to the first that
matches:

| lower ROM | address | checked |
|---|---|---|
| 464 (BASIC 1.0) | &060E | Mike's 464; MAME |
| 6128 -- also a 464 with the 1.1 firmware, which is the 6128's lower ROM | &061F | Mike's 6128; MAME. The English, French, FW 3.15 (EN, ES, FR) and megaflash 6128 ROMs all have it there |
| 664 | &0609 | by disassembly only (no 664 here, nor its romset in MAME) |

The 6128's version also sets the RAM configuration to &C0 and stops the
disc motor first. The 6128 Plus's lower ROM has the routine at &0621;
it is not in the table.

## Memory

The main RAM while Lisp runs (the 512K version's layout,
`mach/cpc512/memmap.asm`):

| | |
|---|---|
| &0000-&003F | the firmware's restarts (FutureOS's are in the save block) |
| &0040-&04FF | Lisp's low system area: mark stack, symbol hash table, LIBDEFS, FNBOUND |
| &0500-&14FF | the symbols, 512 slots of 8 bytes |
| &1500-&A0FF | the cells, the mark bitmap, block space (strings) and Lisp's machine stack, sized at start -- `LISP.64K` at &8000-&91D8 is overwritten once it has done its work |
| &A100-&A6AF | the resident part: bank switching, the RAM disc's transfers, the file routines' dispatch, a trampoline per firmware routine, the reset (`mach/cpc512/resident.asm`) |
| &A6B0-&ABFF | the disc ROM's workspace (AMSDOS takes &0500 bytes, VDOS 2.0 &052E) |
| &AC00-&B0FF | Lisp's fixed variables and buffers |
| &B100-&BFFF | the firmware's RAM and jumpblocks |
| &C000-&FFFF | the screen; Lisp's images are banked in here (configuration &C1 + 8 × bank) |

The expansion:

| | |
|---|---|
| banks 0, 1, 2, 4, 5, 6, block 3 | the six images, one each (`BANK_CFGS`: bank 3 skipped) |
| blocks 0-2 of banks 0-2 and 4-6, blocks 0-1 of bank 7 | the RAM disc M:, 320 KB (its banks 3-6 are banks 4-7: `RS_XFER` translates) |
| bank 7, block 2 | the disc files' buffers, at &4000 when mapped (configuration &FE) for each call of the disc ROM that uses one: an input file's 2 KB at &4000, an output file's at &4800, CAS CATALOG's 4 KB at &5000 -- so a file open on a disc takes no string space |
| bank 7, block 3 | **the save block**, at &4000 when mapped (configuration &FF): |

| in the save block | |
|---|---|
| &4000-&5FFF | FutureOS's &A000-&BFFF |
| &6000-&60FF | FutureOS's &0000-&00FF |
| &6100-&61BF | the way back, `fosback.asm`, at most 192 bytes |
| &61C0, &61C2 | the numbers of ROMs D and B (each with &DF, for `out (c),c`) |
| &7000-&7FFF | only while FutureOS loads the images: `LISP.64K`'s first 4 KB, the loader |

**Bank 3 is never used.** In its configurations 8 and 12, Revaldinho's
card makes bank 3 a shadow of the base RAM -- which is how a 464 gets the
6128's C3 that FutureOS needs. No configuration of bank 3 is ever
written, in MAME or on the machine.

## The screen

FutureOS's desktop is 64 bytes by 256 lines (CRTC R1 = &20, R2 = &2A,
R6 = &20, R7 = &22, logged in MAME with an I/O tap on &BCxx/&BDxx); the
firmware's screen is 80 by 200 (&28, &2E, &19, &1E). MC START PROGRAM
sets only R12 and R13, the screen's start, so Lisp's text and graphics
came out jumbled on Mike's 464 at first. Now the stub sets the
firmware's four before it starts the firmware, and the way back sets
FutureOS's again; the CRTC's registers cannot be read back, so both are
constants. Checked on the 464 and the 6128: Lisp's text, `(rose)`, the
desktop after `(reset)`.

## The disc ROM and the images

**The images come through FutureOS** (since 2026-11-19): `LISP.64K`
calls LADE_N for each, with the drive FutureOS loaded `LISP.64K` from
-- A-D, E-H on a Vortex controller, the M4's SD card... whatever
FutureOS reads, in whatever format it reads there. LADE_N needs that
drive's directory read, which tagging `LISP.64K` there has done. It
is several times faster than AMSDOS: in MAME `LISP.64K` reaches the
banner some 16 s sooner.

If FutureOS cannot load them -- `LISP.64K` started from the RUN menu as
a RAM program, with no directory read, or the images not on that drive
-- the loader reads them through the cassette vectors, so through
whichever ROM 7 KL INIT BACK has just started: CAS IN OPEN, one CAS IN
DIRECT of the whole 16 KB file into the bank's block 3 mapped at &4000,
CAS IN CLOSE. **Lisp's own files always go that way** (for now), so for
them **the disc must be one the disc ROM reads, in drive A**:

* **AMSDOS** -- a 6128's or 664's own (with the internal drive, or a
  Gotek in its place), a 464's DDI-1. Its workspace: &0500 bytes.
* **Parados**, e.g. the LambdaSpeak card's on a 464 (`|DDI1,4`). It fits.
* **VDOS 2.0**, the Vortex controller's ROM, as the card serves it on a
  464 after `|VORTEX,7`, reads only Vortex-format discs: given the
  data-format disc it hung on Mike's 464. With a Vortex disc it has not
  been tried end to end -- FutureOS itself hung loading `LISP.64K` from
  one (below). Its workspace, &052E bytes, is why the resident part ends
  at &A6B0: at &A6F0, as in the 512K version, it said "Too many ROMs".
  VDOS 2.0 also assumes BASIC's RAM: its catalogue fills 4 KB where Lisp
  lent 2 KB, so CAS CATALOG's trampoline is `r_catalog`, which hands it
  4 KB in the buffers' block (`tools/cpc512/mkfw.py`), and `(dir)` lends
  no string space; and it zeroes &AC01, where its 50 Hz ticker waits for
  BASIC's &C9 before it patches &AC01-&AC06 and &BF00 -- &AC00 is Lisp's
  line buffer, which holds only typed text.

FutureOS loads `LISP.64K` and the images with its own disc manager,
which drives both controllers itself: drives A-D on the internal one at
&FB7E, E-H on the Vortex controller's at &FBF6.

## FutureOS while Lisp runs

FutureOS is off while Lisp runs: its interrupts, its tasks, its desktop.
It has preemptive multitasking, and Lisp does not yet read FutureOS's
XRAM variables (XRAM_C4..XRAM_FF), so it may overwrite the blocks of a
task (bit 6), a loaded file (7), a long-term buffer (2) or another
program (4), and FutureOS's buffered directories are forgotten after
`(reset)`. **Keep nothing in the expansion's first 512 KB while Lisp
runs.** For the same reason M: does not survive a trip to the desktop.

## What was tested where

On 2026-11-17, and where it says so since.

| machine | setup | result |
|---|---|---|
| MAME, 464 and 6128, 2026-11-19 | as below; `LISP.64K` tagged on the desktop and run with X, the images loaded through FutureOS (LADE_N) | `(hwtest)` 7 yes, eight demos, `(ed 'tree)` and ESC, `(load "apfel")`, a file read on A while one is written to M:, `(dir)`, `(reset)` to the desktop; started as a RAM program instead (no directory read), the images came through AMSDOS, as before |
| MAME, 464 | 1.0 firmware, 576K, a DDI-1 (AMSDOS) with `cpclispfos.dsk`, FutureOS's ROMs as 1-4 in the ROM box | `(hwtest)` 7 yes, `(rose)`, `(reset)` to the desktop |
| MAME, 6128 | 576K, its own drive and AMSDOS, the ROM box | `(hwtest)` 7 yes, the text screen, `(reset)` to the desktop |
| Mike's 464 | 1.0 firmware; Revaldinho's card, configuration 8; the official FutureOS from the LambdaSpeak card's slots (its 464 firmware, the fast ROM select); `\|DDI1,4`: Parados as ROM 7, `cpclispfos.dsk` in the card's drive as A | `(hwtest)` 7 yes and `(reset)` to the desktop, the screen still jumbled; then with the screen fix (the build before 4236: the same but for the 664's and 6128's lower ROMs) the text, `(rose)` and `(reset)` right |
| Mike's 6128 | Revaldinho's card, configuration 0; the official FutureOS from the card's slots, the card on its 664/6128 firmware (lambdaspeak4 f008560: FutureOS's drive E at &FBF6, the fast ROM select restored); `cpclispfos.dsk` on the Gotek as A | build 4236: `(hwtest)` 7 yes, `(rose)`, the demos, `(reset)` to the desktop. `LISP.64K` also loads from the card's drive E and runs, the images still from A. One earlier load from E went back to the desktop quietly and is not understood; reloading the card's drive fixed it (that drive also lost its disc once to a power cut, the card's USB out with the 6128 off) |

What did not work, on the way:

* **The 1.1 firmware on the 464**, before the 6128's lower ROM was in the
  table: straight back to the desktop. The 464 with 1.1 is the 6128 case
  now -- passed in MAME's 6128, not tried on the 464 since.
* **VDOS's workspace**: "Too many ROMs", with the resident part at &A6F0.
  Fixed.
* **VDOS given the data-format disc**: hung while loading the images --
  the card had stayed in its Vortex setup when `|DDI1,4` was meant.
* **A Vortex-format disc on the 464's drive E** (`|VORTEX,7`): FutureOS
  hung loading `LISP.64K`, in ROM B's seek loop -- sense interrupt status
  forever, waiting for a seek the card's controller never saw. Two times
  in three. Open, on the card's side; data-format discs on E load.
* **The jumbled screen**: fixed (above).
* After `(hwtest)` and a few demos **string space ran out**: a disc
  file took 2 KB of it, the function editor 768 bytes for its font and
  half of what was left. Since 2026-11-18 both live in the expansion
  (bank 7's block 2), and string space is a quarter of the heap: 7.7 KB
  at start, 3.9 KB after hwtest and eight demos (MAME), where
  `(ed 'tree)` and `(load "apfel")` work. On Mike's 6128 the first half
  of it (build 23879, the buffer) made `(load "apfel")` work after the
  demos; `(ed 'tree)` still said "out of string space" there. Build
  26078 passed there (2026-11-18): hwtest, the demos, then `(ed 'tree)`
  and `(load "apfel")`.

## Testing in MAME

    MACH=futureos tools/build.sh
    tools/futureos/run.sh [-m 464|6128] [-f frames] [-s shot.png] file.lsp

`-m 464` (the default) is a 464 with 576K and a DDI-1 holding
`cpclispfos.dsk`, MAME's ROM box behind it; `-m 6128` a 6128 with 576K,
its own drive, and the ROM box. The box holds FutureOS's ROMs renumbered
1-4 (`tools/futureos/fosroms.py SRC ~/claude/cpc/futureos/mame-1234 1 2 3
4`, from the installer disc). The run types `|OS`, reads drive A's
directory on the desktop (SPACE, A, D), moves the pointer onto
`LISP.64K` with the cursor keys, tags it (COPY) and runs it (X), as a
user does -- so FutureOS loads `LISP.64K` from the disc, and `LISP.64K`
the images through FutureOS. Then it types the file's lines when Lisp
asks for them. `FOS_DIR=0` starts `LISP.64K` the old way instead: put
at &8000 (`!poke`) and started from the RUN menu (X, 3, &9000, &C0),
with no directory read -- which tries the loader's fallback, the images
through AMSDOS. MAME has no Vortex controller: the Vortex disc is checked
only by reading it back.

`hello.asm` is a first FutureOS program built here: it prints with
TERM_2 and goes back with KLICK. `fos.asm` names the FutureOS entries
used.

## Further

* **Respect FutureOS's expansion RAM**: take only the blocks its XRAM
  variables mark free, and mark Lisp's -- then M: and the images could
  survive the desktop, and a second start skip loading.
* Lisp's own files through FutureOS (`load`, `save`, `(dir)`, streams),
  from any FutureOS medium: then nothing needs drive A. And its fast
  text output.
* A native Lisp, without the island, through FutureOS's text, keyboard
  and file functions -- and Lisp as a task beside others, with TFM's
  description of the task interface.
* More string space for the disc versions.
* The 6128 Plus's lower ROM (&0621); VDOS 2.11 for a 6128's Vortex
  drive, through CAS.
* The maths package under FutureOS proper, without the island: the
  arithmetic uses no RAM, but SQR, LOG, EXP, the powers and the
  trigonometry use &B8E4-&B8F7.
