# CPC Lisp 0.97 -- the discs

*A Lisp machine for the Amstrad CPC*

Ready to use, built from this repository: CPC Lisp loaded from disc, and
the test discs for the real machine. Each disc's test is `HWTEST.LSP`:

    (load "hwtest")
    (hwtest)        each check says yes or NO
    CTRL-SHIFT-ESC, then (load "hwtest") and (hwtest2) where it says so:
                    what a reset should leave

| disc | what | build |
|---|---|---|
| `cpclisp512.dsk` | **CPC Lisp from disc, for a 512K RAM expansion** (`mach/cpc512`): `RUN"LISP` -- all of it, the compiler too, and a RAM disc `M:` of 415 KB; and its test: the cells, two files open at once, lazy loading, the RAM disc, far arrays (into the expansion's banks 6 and 7), the compiler | 475 |
| `cpclisp6128.dsk` | **CPC Lisp from disc, for a plain 6128** (or a CPC with 64 KB more; `mach/cpc6128`): `RUN"LISP` -- everything but the compiler, no RAM disc; and its test, of what it has | 475 |
| `cpclisp-demo.dsk` | **the demo disc**, for the ROMs (or a disc version): the programs of `examples/` -- `APFEL.LSP`, the Apfelmaennchen: `(load "apfel")`, `(apfel)` (mode 2) | -- |
| `cpclisp-hwtest.dsk` | **the test of the ROMs' use of a RAM expansion** (or a 6128's second 64 KB): two files at once, lazy loading from the drive and from `M:`, the RAM disc, far arrays over its banks, the compiler. Needs the 0.96 ROMs or later (`roms/`) | -- |

| `cpclisp-trs80-model1.dsk` | **CPC Lisp on a TRS-80 Model I** with X-MEM/80 (LDOS 5.3.1, single density): `LISP` at LDOS Ready, and its test, `HWTEST/LSP` -- also `(hwtest-big)`, the RAM disc past 256 KB | 475 |
| `cpclisp-trs80-model3.dsk` | **the same for a Model III** (LDOS 5.1.4, double density, JV3) | 475 |
| `cpclisp-trs80-model4.dsk` | **CPC Lisp on a TRS-80 Model 4** with 128 KB, natively (`mach/trs80m4`): LS-DOS 6.3.1's system disc (double density, 40 tracks, JV3) with `LISP` and `HWTEST/LSP` -- boot it, give the date and time, `LISP` | 475 |
| `cpclisp-trs80-model4.hfe` | the same disc for a **Gotek** (FlashFloppy) or an **HxC** | 475 |
| `frehd/cpclisp4` | the same on the **FreHD**'s hard disc: an LS-DOS 6.3.1 system (1.6 MB, Radio Shack hard disc driver; the hard disc is drive :0 only, the floppies :4 and :5) with `LISP` and `HWTEST/LSP`. Copy it to the root of the FreHD's SD card *as it is named* (no extension, as the FreHD's images); its boot menu lists it, ENTER boots it, `LISP` -- no date asked | 475 |
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

The CPC discs and the Model 4's also carry **APFEL.LSP**, the
Apfelmaennchen (`examples/apfel.lsp`): `(load "apfel")`, `(apfel)`.

(HWTEST writes small files to drive A -- LZ.LSP, NOTES.LSP -- and to
`M:`; the 512K version's test 5 takes a minute or two. The Model 4's
writes HWCOPY/LSP and HWSAVE/LSP on its own disc and deletes them.)

The Model 4's test passed on Mike's Model 4 (2026-11-13: from the FreHD,
build 25495, with the Improved Grafyx: `(hwtest)` 8 yes; F1 confirms the
function editor), and in trs80gp from the floppy and from the FreHD
image (trs80gp's FreHD, its boot menu); build 31726, the same code but
for the version, passed there too (Mike: "all checks out"), and the
release's build 475 passed every machine's tests in the emulators. From an HxC it worked on his Model 4
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
