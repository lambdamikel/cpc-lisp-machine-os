# CPC Lisp 1.0 -- the ROM images

*A Lisp machine for the Amstrad CPC*

Ready to use: six 16 KB ROM images, built from this repository (build
1000, version 1.0). You do not need to build anything to use them.
(No ROM board? CPC Lisp loads from disc too, with a 512K expansion or on
a 6128, and under FutureOS: [`discs/`](../discs/). The TRS-80's discs are there and with the
release: see the end.)

**New in 1.0**: **CPC Lisp on FutureOS itself** -- `cpclispfos-n.dsk`:
no firmware, FutureOS stays resident, and Lisp loads, saves and prints
through FutureOS's own routines, from any of its drives (`(dir "e:")`,
`(cd "e:")`), with its own keyboard, graphics and sound, the RAM disc
`M:` in the expansion's free blocks, and a check of every image it
loads; quicker than through the firmware (checked on a real 464 and
6128; [`mach/fos/`](../mach/fos/README.md)). **`cd`** on every disc
version and machine: `(cd "b:")` makes B the drive for names without
one, `(cd)` says which, and `(dir "b:")` lists another drive. **`save`
and `load` round-trip structures**: the reader reads `#S(...)` (a far
array saved after `(hwtest)` said "syntax error" when loaded). The
ROMs have the last two.

**New in 0.99**: **CPC Lisp under FutureOS**, TFM's operating system --
`cpclispfos.dsk`, started from FutureOS's desktop on a 464, 664 or 6128
with a 512K expansion, `(reset)` back to the desktop (checked on a real
464 and 6128; [`mach/futureos/`](../mach/futureos/README.md)). **More
string space** on the disc versions with a 512K expansion and under
FutureOS: a disc file's buffer and the function editor's font live in
the expansion, and strings have a quarter of the heap -- 7.7 KB at start
instead of 5.3 (some 5500 cells; the RAM disc 16 KB smaller). **The
classics discs**, for the CPC and the TRS-80s: ELIZA, symbolic
differentiation, the animal game, Lisp in Lisp, Life, tic-tac-toe by
minimax, Huffman codes -- `(load "classics")`. And **benchmarks** against
the Lisps of the day, with their discs (`docs/benchmarks.md`,
`vintage/`). The ROMs are 0.98's but for the version.

**New in 0.98**: fixes found on the real machines. `compile-file` wrote
a quoted name of a compiled function (`'compile`) as an empty function,
and the `.fas` file said "not a symbol" when loaded (the Apfelmaennchen's
did). A new `(ed 'name)` lets the last edited text go when string space
is short -- after a long session it said "out of string space", `(gc)`
or not. On the TRS-80 the function editor drew its key line past the
screen, into the Model III's LDOS variables (it turned LDOS's clock
on); it is on the last row now, with the TRS-80's keys -- SHIFT -> is
indent. The Model I and III have half as much string space again (3/8
of the heap, about 6 KB, for some 500 cells), and the Apfelmaennchen is
on every disc, the Model I's too.

**New in 0.97**: CPC Lisp on the **TRS-80 Model 4**, natively, with 128
KB under LS-DOS 6.3.1 -- 80 by 24, graphics on the high-resolution board
(Radio Shack's, the Grafyx Solution, Ian Mavric's Improved Grafyx), on a
floppy, an HxC or Gotek, or a FreHD (below); and **the Apfelmaennchen**,
`(load "apfel")` `(apfel)`, on the discs -- `cpclisp-demo.dsk` and the
others; on a CPC in mode 2, compiled.
The CPC's ROMs are 0.96's but for the version, and `(basic)` and
`|BOOTLISP` default to card slot 2. Checked on a real 464 with the
LambdaSpeak card (the demo disc's `(apfel)` too).

**New in 0.96**: programs bigger than memory -- `(load "big" :lazy t)`
reads each function from the file when it is first called -- and library
functions dropped again when the cells run out, read back when needed;
**far arrays** on the RAM disc (`make-far-array`, `far-ref`), outside
the cells; CL's `file-position`. Checked on a real 464 with Revaldinho's
512K card.


| image | what | needed? |
|---|---|---|
| `LISP.ROM` | **the core**: the Lisp itself -- the evaluator, the garbage collector, the reader and printer, the special forms, the basic functions | yes |
| `LISPLIB.ROM` | **library 1**: the screen, graphics, turtle graphics, sound, keys and joystick; strings and characters; printing and reading with streams; files and the RAM disc; the line editor and the function editor | recommended |
| `LISPLIB2.ROM` | **library 2**: floats and the maths functions, `format`, `sort`, the sequence functions, hash tables, structures, `load` (lazy too) and `file-position`, dropping library functions when the cells run out, speech, PlayCity and MIDI on the LambdaSpeak card, `(basic)` and `\|BOOTLISP` | recommended |
| `LISPLIB3.ROM` | **library 3**: about eighty Common Lisp functions and macros written in Lisp (`reduce`, `map`, `defstruct`, `typep`, `handler-case`, `with-open-file`...) | recommended |
| `LISPDEMO.ROM` | **the demo ROM**: `loop`, string streams, far arrays (`make-far-array`, `far-array`), `midi-note` and the MIDI functions, `sleep`, and the demo programs (`(demo)` lists them) | optional |
| `LISPVM.ROM` | **the VM ROM**: the compiler (`compile`, `compile-file`, `disassemble`) and the bytecode machine that runs compiled code | optional |

**All six must be from the same build** -- these are: the core recognises
the others by a build number and ignores any from another build.

## Installing them

They go into any ROM expansion -- a ROM box or ROM board, or the
LambdaSpeak card, below. The rules:

* **The core at ROM 0** replaces BASIC (the board must assert ROMDIS, as a
  ROM at 0 always does): the CPC switches on into Lisp. At another free
  number the CPC starts in BASIC, and `|LISP` is to start Lisp (built in,
  not tried yet).
* **The other five at any free numbers from 1 to 6**, in any order. Not 7:
  that is the disc ROM (AMSDOS, or Parados). On a 6128 or 664 the
  internal AMSDOS is ROM 7 and cannot be switched off: never put anything
  at 7 there.
* **Leave out any you do not want** but the core: their functions are then
  not there, and the rest works. The banner lists the library ROMs it
  found (not the VM ROM).

When it starts, it says

    CPC Lisp 1.0
    A Lisp machine for the Amstrad CPC
    library ROMs 4 5 6 3
    6402 cells free
    LISP>

## On the LambdaSpeak card

[LambdaSpeak 4, aka LambdaSpeak AI](https://github.com/lambdamikel/lambdaspeak4)
([Hackaday](https://hackaday.io/project/206813-lambdaspeak-4-aka-lambdaspeak-ai))
serves eight expansion ROMs from its flash, uploaded over USB -- no
EPROMs -- and does the speech, PlayCity and MIDI that `say`, `pc-tone`
and `midi-note` use.
CPC Lisp was developed on it, with these slots (the card's own Parados
and LS AI ROMs keep theirs):

| slot | ROM number | image |
|---|---|---|
| 2 | 0 | `LISP.ROM` -- the CPC boots into it |
| 5 | 4 | `LISPLIB.ROM` |
| 0 | 5 | `LISPLIB2.ROM` |
| 7 | 6 | `LISPLIB3.ROM` |
| 3 | 3 | `LISPDEMO.ROM` |
| 1 | 1 | `LISPVM.ROM` |
| 4 | 7 | Parados (the card's) |
| 6 | 2 | LS AI (the card's) |

(0.96 and before: the core in slot 4, Parados in 2.)

Upload them with the card's ROM loader, with the CPC **switched off**.
From this repository, `python3 tools/card.py lisp` uploads the images in
`build/` to these slots (it uses the card's own loader, from the
LambdaSpeak repository). **BASIC and back**: `(basic)` at `LISP>` resets
the CPC into BASIC (the card silences slot 2), and `|BOOTLISP` in BASIC
back into Lisp -- or, from the PC with the CPC off, `tools/card.py basic`
and `tools/card.py number 2 0`.

## On a TRS-80

The release has the same Lisp for a **TRS-80 Model I or III with
X-MEM/80** -- **in its X-MEM/80 mode, 16 KB pages** (in its 32 KB
SuperMem mode the RAM disc keeps to 112 KB) -- on LDOS discs ready to
boot, each as a `.dsk` for emulators and an `.hfe` for a Gotek or HxC
(the `.dsk` files are in [`discs/`](../discs/) too):

| file | for |
|---|---|
| `cpc-lisp-1.0-trs80-model1.dsk` / `.hfe` | a Model I: LDOS 5.3.1, single density (JV1) -- tested in trs80gp (0.95 also on a real Model I with X-MEM/80 and MIDI/80) |
| `cpc-lisp-1.0-trs80-model3.dsk` / `.hfe` | a Model III: LDOS 5.1.4, double density (JV3) -- tested on a real Model III with X-MEM/80, Talker/80 and MIDI/80 (0.96) |

Each has `HWTEST/LSP`, a test of the machine: `(load "hwtest")`,
`(hwtest)`.

Boot it, give LDOS the date (and on a Model I the time), type `LISP`.
[`mach/trs80/README.md`](../mach/trs80/README.md) has the rest.

**The TRS-80 Model 4** (128 KB, natively, LS-DOS 6.3.1) has its own:

| file | for |
|---|---|
| `cpc-lisp-1.0-trs80-model4.dsk` / `.hfe` | a floppy, or an HxC or Gotek: LS-DOS 6.3.1's system disc with `LISP`, `HWTEST/LSP` and `APFEL/LSP` -- boot, the date and time, `LISP` |
| `cpc-lisp-1.0-trs80-model4-frehd` | a FreHD: a bootable LS-DOS 6.3.1 hard disc with the same. Copy it to the FreHD's SD card **as `cpclisp4`** (no extension); its boot menu lists it, ENTER, `LISP` |

**The classics** -- ELIZA, symbolic differentiation, the animal game,
Lisp in Lisp, Life, tic-tac-toe, Huffman codes -- are on a data disc for
each: `cpc-lisp-1.0-trs80-classics-model1`, `-model3`, `-model4` (`.dsk`
and `.hfe`). Put it in drive 1 and `(load "classics")`. The CPC's is
`cpclisp-classics.dsk`.

Tested on a real Model 4 with a FreHD, an HxC and Ian Mavric's Improved
Grafyx; [`mach/trs80m4/README.md`](../mach/trs80m4/README.md) has the
keys (SHIFT down-arrow for `[ ] { } ~`...) and the rest.

## What next

The [README](../README.md) is the overview, the
[tutorial](../docs/tutorial.md) a tour at the keyboard, and the
[reference](../docs/reference.md) has every function. Type `~` as
**CTRL + 2**: the CPC has no tilde key.

## Licence

GPL-3.0 -- [`LICENSE`](../LICENSE) is the text, and the source is this
repository. Programs you write in CPC Lisp are not covered: they are
yours (the [README](../README.md#licence) says so in full).
