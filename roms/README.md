# CPC Lisp 0.97 -- the ROM images

*A Lisp machine for the Amstrad CPC*

Ready to use: six 16 KB ROM images, built from this repository (build
1471, version 0.97). You do not need to build anything to use them.
(No ROM board? CPC Lisp loads from disc too, with a 512K expansion or on
a 6128: [`discs/`](../discs/). The TRS-80's discs are there and with the
release: see the end.)

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

    CPC Lisp 0.97
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
| `cpc-lisp-0.97-trs80-model1.dsk` / `.hfe` | a Model I: LDOS 5.3.1, single density (JV1) -- tested in trs80gp (0.95 also on a real Model I with X-MEM/80 and MIDI/80) |
| `cpc-lisp-0.97-trs80-model3.dsk` / `.hfe` | a Model III: LDOS 5.1.4, double density (JV3) -- tested on a real Model III with X-MEM/80, Talker/80 and MIDI/80 (0.96) |

Each has `HWTEST/LSP`, a test of the machine: `(load "hwtest")`,
`(hwtest)`.

Boot it, give LDOS the date (and on a Model I the time), type `LISP`.
[`mach/trs80/README.md`](../mach/trs80/README.md) has the rest.

**The TRS-80 Model 4** (128 KB, natively, LS-DOS 6.3.1) has its own:

| file | for |
|---|---|
| `cpc-lisp-0.97-trs80-model4.dsk` / `.hfe` | a floppy, or an HxC or Gotek: LS-DOS 6.3.1's system disc with `LISP`, `HWTEST/LSP` and `APFEL/LSP` -- boot, the date and time, `LISP` |
| `cpc-lisp-0.97-trs80-model4-frehd` | a FreHD: a bootable LS-DOS 6.3.1 hard disc with the same. Copy it to the FreHD's SD card **as `cpclisp4`** (no extension); its boot menu lists it, ENTER, `LISP` |

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
