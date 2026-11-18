# CPC Lisp under FutureOS

CPC Lisp started from FutureOS's desktop, on a CPC 464 with Revaldinho's
512K card in configuration 8 (the C3 mode FutureOS needs) and FutureOS's
ROMs on a ROM board: the LambdaSpeak 4's slots, with its fast ROM
select. `(reset)` goes back to the desktop. This was Mike's goal for
2026-11-17; TFM, FutureOS's author, had asked for it.

    CPC Lisp 0.98
    A Lisp machine for the Amstrad CPC, 512K
    library ROMs 1 2 3 4
    6121 cells free

Nothing of FutureOS is in this repository. TFM's ROMs, discs and
documents are free for non-commercial use from futureos.de.

## How it works: a firmware island

FutureOS keeps its variables, tables and stack at &A000-&BFFF, where the
CPC's firmware keeps its own. The firmware is always in the lower ROM,
so Lisp takes it back for a while:

1. FutureOS loads `LISP.64K` at &8000 and starts it at &9000. The stub
   (`loader.asm`) puts FutureOS's RAM aside in bank 7's block 3:
   &A000-&BFFF, &0000-&00FF, the way back (`fosback.asm`) and the
   numbers of ROMs B and D. The block's last 4 KB is the catalogue's
   (below).
2. It starts the firmware as the 464 starts a program. That is MC START
   PROGRAM's body in the lower ROM, at &060E: the firmware's RAM is
   cleared, every pack initialised, IM 1, EI, and then the stub's routine
   is called. There is no ROM walk and no BASIC.
3. The 512K version's loader (`loader512.asm`, a link to
   `mach/cpc512/loader.asm`) starts only ROM 7, the disc's (AMSDOS,
   Parados or VDOS), through KL INIT BACK. A ROM walk would also start
   FutureOS's four ROMs, whose workspace takes the resident part's room.
   The loader then reads `LISP0.IMG` to `LISP5.IMG` through the disc
   ROM and starts Lisp. From here on Lisp is the 512K version: the
   firmware for text, graphics and sound, and the disc ROM for files.
4. `(reset)` maps bank 7's block 3, copies the way back to &8000 and runs
   it. It restores FutureOS's RAM, its colours (ROM B's table at &FE0B)
   and the screen's start. Then come ROM D, IM 2 with I = &BD, and
   TUR_D, which draws the desktop afresh.

Everything else comes from `mach/cpc512` through links, with
`variant.asm` setting `FUTUREOS`. The 512K version's builds are byte for
byte unchanged by the `ifdef FUTUREOS` parts.

**Bank 3 is never used.** In configurations 8 and 12, Revaldinho's card
makes bank 3 a shadow of the base RAM. So under FutureOS:
* the images go to block 3 of banks 0, 1, 2, 4, 5 and 6 (`BANK_CFGS`
  in `memmap.asm`, and the loader's `map_bank`);
* the RAM disc's banks 3-6 are banks 4-7 (`RS_XFER` in
  `resident.asm`);
* the RAM disc's top 16 KB, bank 7's block 3, keeps FutureOS's RAM, so
  M: is 336 KB.

In MAME no gate array configuration of bank 3 is ever written.

**VDOS 2.0 assumes BASIC's RAM** (the card session's finding). Its
catalogue fills 4 KB, where Lisp lends 2 KB; that crashed `(dir)` when
the ROM Lisp was ROM 0, on 2026-11-13. Under FutureOS, CAS CATALOG's
trampoline is the resident part's `r_catalog` (`tools/cpc512/mkfw.py`
makes it so). It hands VDOS 4 KB in bank 7's block 3, so `(dir)` lends
no string space. VDOS also zeroes &AC01, and its 50 Hz ticker waits
for &C9 there, BASIC's mark, before patching &AC01-&AC06 and copying
code to &BF00. &AC00 is Lisp's line buffer, which holds only typed text,
so it should never see &C9 there; nothing yet shows that it does.

**FutureOS has preemptive multitasking.** While Lisp runs, FutureOS is
off: a background task waits until `(reset)`. Lisp does not yet read
FutureOS's XRAM variables, so it could overwrite a task's blocks (bit 6),
a loaded file's (7) or a long-term buffer (2). Taking only the blocks
marked free, and marking Lisp's, is the next step.

FutureOS may use the expansion's blocks while its desktop runs: for
directories, short-term buffers, a background program. Lisp overwrites
them, and TUR_D forgets the buffered directories. So M: does not survive
a trip to the desktop. For that, Lisp would have to mark its blocks in
FutureOS's XRAM_C4..XRAM_FF variables.

## On Mike's 464

**Passed on Mike's 464, 2026-11-17**: `(hwtest)` 7 yes, `(reset)` back
to the desktop. The setup:

* The 464's 1.0 firmware. LISP.64K starts the firmware through MC
  START PROGRAM's body in the lower ROM -- &060E on a 464, &061F on a
  6128 (or a 464 with the 1.1 firmware), &0609 on a 664 -- and checks
  the bytes before it jumps; with none of them it goes back to the
  desktop. The 6128's passed in MAME the same evening (hwtest 7 yes,
  `(reset)`: `tools/futureos/run.sh -m 6128`); the 664's is untried
  (MAME here has no 664 romset).
* FutureOS's official ROMs in the card's slots: the card session's
  firmware with the fast ROM select (`QS`).
* Revaldinho's card in configuration 8 (DIP 1234 = 1000).
* The card's drive in its normal place with Parados as ROM 7:
  `|DDI1,4` at BASIC, and `build/futureos/cpclispfos.dsk` in the drive.

Then:

    |OS             the desktop
    SPACE, A, D     drive A's directory
    LISP.64K        tag it: the pointer on it, COPY
    X               RUN: Lisp starts

`(load "hwtest")` and `(hwtest)` check what the 512K version checks, with
check 5's far arrays sized for the smaller RAM disc (it takes a few
minutes). `(reset)` goes back to the desktop.

Lisp uses whatever disc ROM is ROM 7: AMSDOS, Parados, or VDOS 2.0 (its
1326 bytes of workspace are why the resident part is at &A120). The
Vortex disc, `cpclispfos-vortex.dsk` with `|VORTEX,7` and drive E, is
not there yet: FutureOS itself hung loading LISP.64K from it, in ROM B's
seek loop on the card's Vortex controller, two times in three. The card
session is looking into it (FutureOS has no drive E configured).

FutureOS's screen is 64 bytes by 256 lines (CRTC R1 &20, R2 &2A, R6 &20,
R7 &22); the firmware's is 80 by 200, and MC START PROGRAM sets only R12
and R13. LISP.64K sets the firmware's four before starting it, and the
way back sets FutureOS's again (on the 464 the text and graphics came out
jumbled before; with this, the text, `(rose)` and the desktop after
`(reset)` were right there, the same evening).

## On a 6128

**Passed on Mike's 6128, 2026-11-17** (build 4236, `discs/cpclispfos.dsk`):
`(hwtest)` 7 yes, `(rose)`, the demos. FutureOS from the card's slots
(its 6128 firmware), Revaldinho's card in configuration 0, the disc on
the Gotek as drive A. (A first try from the card's drive E went back to
the desktop: the drive was empty -- USB unplugged with the 6128 off
loses it, and the card's 6128 firmware has no flash discs to reload.)
After a few demos string space runs out, as on the other disc
versions.

The same disc and steps, with the 6128's own drive A (Mike's has a
Gotek) and its AMSDOS as ROM 7. A RAM expansion of 512 KB is needed as
on a 464: Revaldinho's card in configuration 0 (DIP 1234 = 0000; the
6128 does C3 itself). Lisp does not yet ask FutureOS which expansion
RAM is free: banks 0-2 and 4-6 take its images and RAM disc, and bank
7's block 3 FutureOS's own RAM while Lisp runs -- keep nothing there.
The LambdaSpeak card needs its 664/6128 firmware in a 6128 (the card
session's; it never answers ROM 7 there).

## Testing in MAME

    MACH=futureos tools/build.sh
    tools/futureos/run.sh [-f frames] [-s shot.png] file.lsp

The 464 has 576K and a DDI-1 with `cpclispfos.dsk`. Behind it, MAME's
ROM box holds FutureOS's ROMs renumbered 1-4, made with
`tools/futureos/fosroms.py SRC ~/claude/cpc/futureos/mame-1234 1 2 3 4`
from the installer disc. The run types `|OS`, puts `LISP.64K` at &8000
(`!poke`) and starts it from the RUN menu: X, 3, &9000, &C0. Then it
types the file's lines when Lisp asks for them. MAME has no Vortex
controller, so the Vortex disc is checked only by reading it back.

`hello.asm` is a first FutureOS program built here. It prints with
TERM_2 and goes back with KLICK, and `fos.asm` names the FutureOS entries
it uses.

## Further

* A 664's or 6128's firmware: MC START PROGRAM's body sits elsewhere
  in their lower ROMs, and the stub only accepts the 464's for now.
* The maths package under FutureOS proper: the arithmetic uses no RAM,
  but SQR, LOG, EXP, the powers and the trigonometry use &B8E4-&B8F7.
* A native Lisp, without the island, through FutureOS's text, keyboard
  and file functions. That is a firmware's worth of routines to write;
  the island needed none of them.
