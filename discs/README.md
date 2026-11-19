# CPC Lisp 0.98 -- the discs

*A Lisp machine for the Amstrad CPC*

Ready to use, built from this repository: CPC Lisp loaded from disc, and
the test discs for the real machine. Each disc's test is `HWTEST.LSP`:

    (load "hwtest")
    (hwtest)        each check says yes or NO
    CTRL-SHIFT-ESC, then (load "hwtest") and (hwtest2) where it says so:
                    what a reset should leave

| disc | what | build |
|---|---|---|
| `cpclisp512.dsk` | **CPC Lisp from disc, for a 512K RAM expansion** (`mach/cpc512`): `RUN"LISP` -- all of it, the compiler too, and a RAM disc `M:` of 399 KB; and its test: the cells, two files open at once, lazy loading, the RAM disc, far arrays (into the expansion's banks 6 and 7), the compiler | 26738 |
| `cpclisp6128.dsk` | **CPC Lisp from disc, for a plain 6128** (or a CPC with 64 KB more; `mach/cpc6128`): `RUN"LISP` -- everything but the compiler, no RAM disc; and its test, of what it has | 14943 |
| `cpclispfos.dsk` | **CPC Lisp under FutureOS** (`mach/futureos`), on a 464, 664 or 6128 with a 512K RAM expansion: on FutureOS's desktop, drive A, tag `LISP.64K`, RUN (X); `(reset)` goes back to the desktop. The 512K version and its test (check 5 sized for the smaller RAM disc); `mach/futureos/README.md` has the details | 26078 |
| `cpclisp-demo.dsk` | **the demo disc**, for the ROMs (or a disc version): the programs of `examples/` -- `APFEL.LSP`, the Apfelmaennchen: `(load "apfel")`, `(apfel)` (mode 2) | -- |
| `cpclisp-classics.dsk` | **the classics disc**: ELIZA, symbolic differentiation, the animal game that learns, Lisp in Lisp, Conway's Life, tic-tac-toe by minimax, SICP's Huffman codes (`examples/`) -- `(load "classics")` lists them | -- |
| `cpclisp-hwtest.dsk` | **the test of the ROMs' use of a RAM expansion** (or a 6128's second 64 KB): two files at once, lazy loading from the drive and from `M:`, the RAM disc, far arrays over its banks, the compiler. Needs the 0.96 ROMs or later (`roms/`) | -- |

| `cpclisp-trs80-model1.dsk` | **CPC Lisp on a TRS-80 Model I** with X-MEM/80 (LDOS 5.3.1, single density): `LISP` at LDOS Ready, and its test, `HWTEST/LSP` -- also `(hwtest-big)`, the RAM disc past 256 KB -- and `APFEL/LSP` (since 2026-11-14, without its comments: in the room of LDOS's KI/DVR, which nothing loads) | 14193 |
| `cpclisp-trs80-model3.dsk` | **the same for a Model III** (LDOS 5.1.4, double density, JV3), and `APFEL/LSP` (since 2026-11-14: the same images, the disc made again) | 14193 |
| `cpclisp-trs80-model4.dsk` | **CPC Lisp on a TRS-80 Model 4** with 128 KB, natively (`mach/trs80m4`): LS-DOS 6.3.1's system disc (double density, 40 tracks, JV3) with `LISP` and `HWTEST/LSP` -- boot it, give the date and time, `LISP` | 14431 |
| `cpclisp-trs80-model4.hfe` | the same disc for a **Gotek** (FlashFloppy) or an **HxC** | 14431 |
| `cpclisp-trs80-classics-model1.dsk`, `-model3.dsk`, `-model4.dsk`, `-model4.hfe` | **the classics disc for the TRS-80s**: the same programs on an LDOS 5.3.1, LDOS 5.1.4 and LS-DOS 6.3.1 data disc (`tools/trs80/mkclassics.py`); put it in a drive other than the system's: `(load "classics")` | -- |
| `frehd/cpclisp4` | the same on the **FreHD**'s hard disc: an LS-DOS 6.3.1 system (1.6 MB, Radio Shack hard disc driver; the hard disc is drive :0 only, the floppies :4 and :5) with `LISP` and `HWTEST/LSP`. Copy it to the root of the FreHD's SD card *as it is named* (no extension, as the FreHD's images); its boot menu lists it, ENTER boots it, `LISP` -- no date asked | 14431 |
| `ld4-631.dsk` | **LS-DOS 6.3.1** for the Model 4, its system disc as distributed (Tim Mann's `ld4-631.zip`), which the Model 4 discs are made from -- see below | -- |

Checked on a real CPC 464 with Revaldinho's universal 512K RAM card, on
2026-11-12: all three, every check yes (with the builds before 0.96's,
the same but for the version). **That card wants DIP
configuration 4 on a 464** (switches 1234 = 0100: DK'tronics mode, all
eight banks; 0 on a 6128): its shadow modes give bank 3 to the base RAM,
and the 512K version's loader then stops with "Banks of 64K that answer:
3".

The TRS-80's test passed on Mike's Model III with X-MEM/80, Talker/80
and MIDI/80 (2026-11-12) -- **with X-MEM/80 switched to 16 KB pages**:
in its 32 KB (SuperMem) mode it answers 16 page numbers, and the RAM
disc keeps to 112 KB (`(dir "m:")` says so). The build before this one
(977, the same but for the version) passed there too: `(hwtest)` 8 yes,
and after `(quit)` and `LISP` `(hwtest2)` 2 yes, with all 367 KB of the
RAM disc. For an HxC or a Gotek:
`hxcfe -finput:cpclisp-trs80-model3.dsk -conv:HXC_HFE -foutput:x.hfe`.

**Since 2026-11-18** `cpclisp512.dsk` (26738) and `cpclispfos.dsk`
(26078) have more string space: a disc file's 2 KB buffer and the
function editor's font copy live in the expansion (the RAM disc is 16 KB
smaller for it), and string space is a quarter of the heap -- 7.7 KB at
start, some 5500 cells. After `(hwtest)` and the demos, a `load` and
`(ed 'tree)` had failed for want of it. In MAME: the 512K suite, and
under FutureOS on a 6128 `(hwtest)` 7 yes, eight demos (3.9 KB left),
`(ed 'tree)`, `(load "apfel")`. On Mike's 6128, build 23879 (the buffer
alone) made `(load "apfel")` work after the demos; 26078 is not yet
tried there. The builds below are the ones that passed on the machines.

`cpclispfos.dsk` build 4236 passed on Mike's 6128 under FutureOS (2026-11-17):
`(hwtest)` 7 yes, `(rose)`, the demos and `(reset)` back to the
desktop -- FutureOS from the LambdaSpeak card's slots (the card on its
664/6128 firmware), Revaldinho's card in configuration 0, the disc on the
6128's Gotek as drive A (`LISP.64K` also loads from the card's drive E;
the images come from A). On his 464 the build before it (the same but
for the 664's and 6128's lower ROMs) passed too: 7 yes, `(rose)`,
`(reset)` -- the card on its 464 firmware, `|DDI1,4`, the disc in the
card's drive as A. `mach/futureos/README.md` has the details.

Every disc here also carries **APFEL.LSP**, the
Apfelmaennchen (`examples/apfel.lsp`): `(load "apfel")`, `(apfel)`.

(HWTEST writes small files to drive A -- LZ.LSP, NOTES.LSP -- and to
`M:`; the 512K version's test 5 takes a minute or two. The Model 4's
writes HWCOPY/LSP and HWSAVE/LSP on its own disc and deletes them.)

The Model 4's test passed on Mike's Model 4 (2026-11-13: from the FreHD,
build 25495, with the Improved Grafyx: `(hwtest)` 8 yes; F1 confirms the
function editor), and in trs80gp from the floppy and from the FreHD
image (trs80gp's FreHD, its boot menu); build 31726, the same code but
for the version, passed there too (Mike: "all checks out"), and the
release's build 475 passed every machine's tests in the emulators. The
Model 4's discs are build 2554 since (2026-11-13): `disc` filled only
the CPC's even rows and left every sixth pixel row out -- `(shapes)`'
discs were striped; Mike: "check out round now". Since 2026-11-14 the
TRS-80 discs are build 19680 (the Model 4's 19042) and the 512K's 19682,
since 2026-11-15 10997 (the Model 4's 11294: the function editor's key
line says SHIFT ->, indent, too; Model I hwtest 8 yes, Model 4 suite 30 ok).
**0.98** (2026-11-15): the 512K's 14340, the plain 6128's 14943, the
TRS-80's 14193, the Model 4's 14431 -- a new `(ed 'name)` lets the last
edited text go when string space is short, and the Model I/III have 3/8
of the heap for strings (6184 bytes free at start, 2315 cells): 512K 37,
6128 35, Model 4 30 ok, the Model I's hwtest 8 yes. Before 0.98:
the function editor's status line was drawn at row 24 -- past a TRS-80's
16 rows, into the Model III's ROM and LDOS variables (it turned LDOS's
clock display on; Mike); it is on the last row now, with the machine's
keys. And `compile-file` wrote a quoted name of a compiled function
(`'compile`) as an empty function: APFEL's .FAS said "not a symbol"
(the compiler: the Model I/III's and the 512K's). Model I hwtest 8 yes,
Model 4 30 ok, 512K 37 ok. From an HxC it worked on his Model 4
too: LS-DOS booted from a built-in floppy drive, `SYSTEM
(DRIVE=2,ENABLE)` for the HxC as drives :2 and :3, the `.hfe` chosen
there, `LISP` (LS-DOS finds it and its images on any drive). The HxC's
settings must be its defaults, all "Auto": they take the bitrate and the
interface mode from the image. **LS-DOS 6.3.1** is MISOSYS's; Roy Soltoff made it free to use
and pass on, which is why it is here. The FreHD image's LS-DOS is the one
from Mike's FreHD card with only LS-DOS's own files kept (at its Level 1K
patches, its Radio Shack hard disc driver RSHARD6 and the CONFIG/SYS that
loads it), every other sector zeroed: `tools/trs80m4/mkhdv.py`, which can
also put the Lisp on any LS-DOS 6 `.hdv`.

The disc versions' own documentation: `mach/cpc512/README.md`,
`mach/cpc6128/README.md`. Licence: GPL-3.0, as the rest of the
repository; what you write in CPC Lisp is yours (see the main README).
