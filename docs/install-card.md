# Installing CPC Lisp on a LambdaSpeak 4

*CPC Lisp 1.2.1 -- the card installer*

The [LambdaSpeak 4](https://github.com/lambdamikel/lambdaspeak4) (also
called LambdaSpeak AI) serves eight ROMs to the CPC from its flash, and
emulates a disc drive with a library of flash discs. `tools/install-card.py`
puts CPC Lisp on it in one go:

- **the six ROMs**, with the core as ROM 0, so the CPC starts in Lisp
  instead of BASIC;
- **the Lisp discs** as flash discs: the ROM test (`HWTEST`, `APFEL`), the
  demos, and the classics (ELIZA, Life, tic-tac-toe...);
- **the classics in the card's drive**, so drive A has them.

It shows its plan and asks before it writes anything. It keeps the card's
own ROMs (Parados, the LS AI ROM) and anything else that isn't CPC Lisp,
and it never stores a disc over one of yours. Every checksum is read back
at the end. It works on rev 2 and rev 3 cards alike: they run the same
firmware.

## What you need

- A LambdaSpeak 4 with **the firmware for your CPC**: the 464 build in a
  464, the 664/6128 build in a 664 or 6128 (see *On a CPC 664 or 6128*).
  And its USB lead.
- A PC (Linux, macOS or Windows) with **Python 3**, **git**, **pyserial**
  and **tkinter**. tkinter comes with Python on Windows and macOS; on
  Debian or Ubuntu it is the `python3-tk` package.
- **This repository and the card's, side by side**, because the installer
  writes through the card's own tools:

      git clone https://github.com/lambdamikel/cpc-lisp-machine-os
      git clone https://github.com/lambdamikel/lambdaspeak4
      pip install pyserial

  The installer finds `lambdaspeak4` beside this repository, or in
  `~/git/lambdaspeak4`. Anywhere else, name its tools folder with
  `--ls4 DIR` (or `LS4_TOOLS=DIR`).

**The CPC must be switched off** whenever the card writes its flash. The
card stalls while it writes, and a CPC running from the card's ROMs goes
down with it. The installer checks before every write and stops if the
CPC is on. The card can stay in the CPC: its USB lead powers it.

## On a CPC 464

1. Switch the CPC off. Plug the card's USB lead into the PC.
2. In this repository, run:

       python3 tools/install-card.py

   (On Windows: `py tools\install-card.py`.)

3. Read the plan and answer `y`. A card with only LS AI and Parados on it
   looks like this:

       CPC Lisp 1.2.1 -> the LambdaSpeak card on /dev/ttyACM0 (serial ...)

       ROM slots:
         slot 0: silent  empty -> LISPLIB2.ROM as ROM 5
         slot 1: silent  empty -> LISPVM.ROM as ROM 1
         slot 2: silent  empty -> LISP.ROM as ROM 0
         slot 3: silent  empty -> LISPDEMO.ROM as ROM 3
         slot 4: ROM 7   ROM 7, the disc ROM's number -- kept
         slot 5: silent  empty -> LISPLIB.ROM as ROM 4
         slot 6: ROM 2   the LS AI ROM -- kept
         slot 7: silent  empty -> LISPLIB3.ROM as ROM 6

       Flash discs:
          2: CPC Lisp 1.2.1 ROM test (HWTEST, APFEL) -- in a free slot
          3: CPC Lisp 1.2.1 demos: (load "apfel") -- in a free slot
          4: CPC Lisp 1.2.1 classics (load "classics") -- in a free slot
         the drive: flash disc 4

   It takes a few minutes: about ten seconds per ROM, and up to a minute
   per disc.

4. Switch the CPC on. You see the CPC Lisp banner and `LISP>`. Try:

       (load "classics")

   The menu of the classic programs appears. `(load "eliza")`, then
   `(eliza)`, and so on. `(demo)` lists the demos in the ROMs.

**Parados must answer ROM 7** for the card's drive to work, as it does on
a card as it comes. Without a disc ROM a 464 has only tape:
`(load "classics")` then says *Press PLAY then any key* (ESC gets you
out). The installer warns when nothing answers ROM 7. Give Parados's slot
ROM 7 again with the card's ROM loader (lambdaspeak4's
`tools/romloader.py`), with the CPC off. A 464 with a DDI-1 or DDI-3 has
its own AMSDOS at 7 and its own drive. Then the card must not answer 7
or the drive's ports (lambdaspeak4's documentation has how).

## On a CPC 664 or 6128

The 664 and 6128 have their own disc controller and their own AMSDOS at
ROM 7, which pay no attention to the card. So the card needs its
**664/6128 firmware**, which never answers ROM 7 or the machine's disc
ports. Plugged in with the 464 firmware, the card and the machine both
drive the data bus. **Flash first, then move the card**:
lambdaspeak4's [`docs/two-firmwares.md`](https://github.com/lambdamikel/lambdaspeak4/blob/main/docs/two-firmwares.md)
has the steps (with the card on USB: `./tools/flash.sh
firmware/build-6128/lambdaspeak4.uf2`).

Then, with the CPC off, run the installer exactly as on a 464:

    python3 tools/install-card.py

It sees that this firmware has no flash discs, says so, and puts on the
six ROMs only. Switch on: the CPC starts in CPC Lisp.

**The discs come from the machine's own drive** (a 3" disc, a Gotek, an
M4). The ROM version's discs are in this repository's
[`discs/`](../discs/) and with every release: `cpclisp-classics.dsk`,
`cpclisp-demo.dsk`, `cpclisp-hwtest.dsk`. On a Gotek, copy them to its USB
stick. The card's own drive on that firmware is a Vortex controller,
which AMSDOS does not use. If the card goes back into a 464 later, its
flash discs are there again, as they were.

Other ROM boards: a 6128 looks at ROMs 0-15, a 664 too. CPC Lisp answers
ROM numbers 0, 1, 3, 4, 5 and 6 (the installer lists them at the end):
keep other boards' ROMs off those.

The ROM version from the card's slots has run on the 464. On a real 664
or 6128 it has not been tried yet. CPC Lisp's disc versions have run on
a real 6128 (the plain 6128's, and FutureOS's).

## After installing

**BASIC and back.** `(basic)` at `LISP>` makes the core's slot silent and
resets: the CPC comes up in BASIC. In BASIC, `|BOOTLISP` makes the core
ROM 0 again and resets into Lisp. Everything in RAM is lost both ways, so
save first. From the PC, with the CPC off, `--basic` does the same as
`(basic)`, and running the installer again brings Lisp back:

    python3 tools/install-card.py --basic

**A new release.** `git pull` in both repositories, then run the installer
again. It replaces what changed, renumbers what only moved, and leaves the
rest alone. A card that is already up to date gets *Nothing to do*.

**Options:**

| | |
|---|---|
| `--dry-run` | look and show the plan; write nothing |
| `-p PORT` | the card's port (`/dev/ttyACM0`, `COM3`...). Needed when two cards are on USB: the installer lists them with their serial numbers |
| `--yes` | no questions. Then only empty slots and CPC Lisp's own are written; other ROMs only when named with `--replace` |
| `--replace 3,5` | ROM slots whose ROMs may go to make room for Lisp. Without it, the installer asks about each one it would need |
| `--drive KIND` | the disc for the card's drive: `classics` (the default), `demos`, `test` or `none` |
| `--no-discs` | the ROMs only |
| `--build` | your own build from `build/` (`tools/build.sh`) instead of `roms/` and `discs/` |
| `--basic` | BASIC back: the core's slot made silent |
| `--ls4 DIR` | where the LambdaSpeak 4 tools are |

**Where things go.** On a card that has room, the ROMs take the same slots
as on the developers' card (the main README's table). A slot holding
the same image already is kept. Flash discs go over an older CPC Lisp disc
of the same kind (by its label), or into the first free slot. Older 512K
and 6128 disc versions found in the library are brought up to date too.

## If something goes wrong

| it says | what to do |
|---|---|
| *the CPC is on* | switch it off; run it again (it carries on where it stopped) |
| *no LambdaSpeak card on USB* | plug in the USB lead; on Linux, your user may need to be in the `dialout` group |
| *More than one card is on USB* | pick one with `-p`, by its serial number |
| *CPC Lisp needs six ROM slots* | the card is full of other ROMs: let some go (answer `y`, or `--replace`) |
| *slot N answers ROM 0* | another ROM would start instead of Lisp: let it go, or renumber it with the card's ROM loader |
| *the LambdaSpeak 4 tools ... are older or newer* | `git pull` both repositories |
| *the card's drive holds a disc ... the CPC wrote to* | the CPC saved to the drive's disc. Save it into a flash disc first (the ROM loader's *Flash discs* tab), or give `--drive none` |
| the CPC starts in neither Lisp nor BASIC | switch it off, run `--basic`, and tell us what happened |
| *Press PLAY then any key* on `load` | no disc ROM at 7 (a 464): see *On a CPC 464* |
