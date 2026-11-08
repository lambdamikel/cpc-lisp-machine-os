# CPC Lisp 0.9 -- the ROM images

*A Lisp machine for the Amstrad CPC*

Ready to use: six 16 KB ROM images, built from this repository (build
25063). You do not need to build anything to use them.

| image | what | needed? |
|---|---|---|
| `LISP.ROM` | **the core**: the Lisp itself -- the evaluator, the garbage collector, the reader and printer, the special forms, the basic functions | yes |
| `LISPLIB.ROM` | **library 1**: the screen, graphics, turtle graphics, sound, keys and joystick; strings and characters; printing and reading with streams; files and the RAM disc; the line editor and the function editor | recommended |
| `LISPLIB2.ROM` | **library 2**: floats and the maths functions, `format`, `sort`, the sequence functions, hash tables, structures, speech and PlayCity on the LambdaSpeak card | recommended |
| `LISPLIB3.ROM` | **library 3**: about eighty Common Lisp functions and macros written in Lisp (`reduce`, `map`, `defstruct`, `typep`, `handler-case`, `with-open-file`...) | recommended |
| `LISPDEMO.ROM` | **the demo ROM**: `loop`, string streams, and the demo programs (`(demo)` lists them) | optional |
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

    CPC Lisp 0.9
    A Lisp machine for the Amstrad CPC
    library ROMs 4 5 6 3
    6402 cells free
    LISP>

## On the LambdaSpeak card

[LambdaSpeak 4, aka LambdaSpeak AI](https://github.com/lambdamikel/lambdaspeak4)
([Hackaday](https://hackaday.io/project/206813-lambdaspeak-4-aka-lambdaspeak-ai))
serves eight expansion ROMs from its flash, uploaded over USB -- no
EPROMs -- and does the speech and PlayCity that `say` and `pc-tone` use.
CPC Lisp was developed on it, with these slots (the card's own Parados
and LS AI ROMs keep theirs):

| slot | ROM number | image |
|---|---|---|
| 4 | 0 | `LISP.ROM` -- the CPC boots into it |
| 5 | 4 | `LISPLIB.ROM` |
| 0 | 5 | `LISPLIB2.ROM` |
| 7 | 6 | `LISPLIB3.ROM` |
| 3 | 3 | `LISPDEMO.ROM` |
| 1 | 1 | `LISPVM.ROM` |
| 2 | 7 | Parados (the card's) |
| 6 | 2 | LS AI (the card's) |

Upload them with the card's ROM loader, with the CPC **switched off**.
From this repository, `python3 tools/card.py lisp` uploads the images in
`build/` to these slots (it uses the card's own loader, from the
LambdaSpeak repository). To get BASIC back, give slot 4 the number 255
(`tools/card.py basic`).

## What next

The [README](../README.md) is the overview, the
[tutorial](../docs/tutorial.md) a tour at the keyboard, and the
[reference](../docs/reference.md) has every function. Type `~` as
**CTRL + 2**: the CPC has no tilde key.

## Licence

GPL-3.0 -- [`LICENSE`](../LICENSE) is the text, and the source is this
repository. Programs you write in CPC Lisp are not covered: they are
yours (the [README](../README.md#licence) says so in full).
