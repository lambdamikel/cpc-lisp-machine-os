# The Lisps of the day

The Lisps that CPC Lisp was measured against in
[docs/benchmarks.md](../docs/benchmarks.md), as disc images. That page
also has a short guide to each one: how to start it, define a function
and run it, and how to get out again. For most of them that is not
obvious.

These are other people's programs from 1980-1987, kept here for their
history. If you hold the rights to one and want it removed, open an
issue.

## The CPC: CP/M Plus discs

Each disc boots CP/M Plus on a CPC 6128: put it in drive A and type
`|CPM`. The emulator or the real machine needs nothing else. Mike's 2018
notes say that muLISP-80 and LISP/80 also run on a 464 with a 64 KB
DK'tronics RAM expansion; HiSoft Lisp needs a 6128.

| Disc | Lisp | Start it with |
|---|---|---|
| `cpc/hisoft-lisp.dsk` | **LinguaSoft/HiSoft Lisp 1.57B** (Ofer and Shelly Ben-Ami, 1986-88), HiSoft's real Lisp for the 6128 and the PCW, and HLE, its editor | `LISP6128` |
| `cpc/mulisp-lisp80.dsk` | **muLISP-80** (The Soft Warehouse, 8080 version of 10/06/80) with its MuSTAR editor and demos, and **LISP/80 1.1** (T. W. Yonkman, The Software Toolworks, 1980) | `MULISP`, `LISP_80` |
| `cpc/xlisp11.dsk` | **XLisp 1.1** (David Betz, 1985), with its C sources (squeezed) | starts by itself |
| `cpc/mulisp215-cpcpower.dsk` | **muLISP-80 2.15** (1982), sold as HiSoft's "LISP Interpreter" (1987). It is damaged: no library, and `(TIMES 12 12)` is 180 | `LISP` |

`hisoft-lisp.dsk` and `mulisp-lisp80.dsk` are the two discs Mike put
together in 2018 for the "Lisp on the CPC" thread on the CPCWiki forum,
from several CP/M sources (`HILISP.dsk`, `MULISP.dsk` there). The other
two are CPC-Power's (*XLisp Version 1.1 (UK) (128K) (1985) (CPM)*,
*Hisoft LISP Interpreter (UK) (128K) (1987) (CPM)*).

## The TRS-80: UOLisp

| Disc | |
|---|---|
| `trs80/trsdos23.dmk` | TRSDOS 2.3, the Model I's system disc: drive 0 |
| `trs80/uolisp.dmk` | **UO-LISP V1.5b** (Jed Marti, Northwest Computer Algorithms, 1982), with its compiler: drive 1 |

Mike imaged the UOLisp disc, and the Computer History Museum's Software
Preservation Group keeps it with its manual and installation guide
(softwarepreservation.computerhistory.org/LISP/utah/uolisp). On a 48 KB
Model I, or in trs80gp (`trs80gp -m1 -d0 trsdos23.dmk -d1 uolisp.dmk`),
type `LISP48` at `TRSDOS READY`.

## The manuals

They are too big for this repository; these are where they are:

* LISP/80: the Software Toolworks' manual, at
  heathkit.garlanger.com/software/library/TheSoftwareToolworks/software/manuals/209_Lisp-80.pdf
* muLISP-80: web.archive.org/web/20140530042250/http://maben.homeip.net/static/s100/software/microsoft/LISP/MuLisp.pdf
* UO-LISP: at the Computer History Museum, above.
* HiSoft Lisp's has not turned up. `HLE.HLP` on its disc lists the
  editor's keys.

## Timing them

`tools/bench/cpm.lua` boots CP/M on MAME's 6128 (headless), types the
lines of a file into the program at its prompt and logs everything it
prints, each character with its frame; `tools/bench/cpmtime.py` turns
the log into times. The benchmark files are in `tools/bench/` too
(`linguasoft.txt`, `mulisp.txt`, `mulisp80.txt`, `lisp80.txt`,
`xlisp.txt`); docs/benchmarks.md, *How it was measured*, has the
details.
