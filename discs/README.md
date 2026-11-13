# CPC Lisp 0.95 -- the discs

*A Lisp machine for the Amstrad CPC*

Ready to use, built from this repository: CPC Lisp loaded from disc, and
the test discs for the real machine. Each disc's test is `HWTEST.LSP`:

    (load "hwtest")
    (hwtest)        each check says yes or NO
    CTRL-SHIFT-ESC, then (load "hwtest") and (hwtest2) where it says so:
                    what a reset should leave

| disc | what | build |
|---|---|---|
| `cpclisp512.dsk` | **CPC Lisp from disc, for a 512K RAM expansion** (`mach/cpc512`): `RUN"LISP` -- all of it, the compiler too, and a RAM disc `M:` of 415 KB; and its test: the cells, two files open at once, lazy loading, the RAM disc, far arrays (into the expansion's banks 6 and 7), the compiler | 375 |
| `cpclisp6128.dsk` | **CPC Lisp from disc, for a plain 6128** (or a CPC with 64 KB more; `mach/cpc6128`): `RUN"LISP` -- everything but the compiler, no RAM disc; and its test, of what it has | 478 |
| `cpclisp-hwtest.dsk` | **the test of the ROMs' use of a RAM expansion** (or a 6128's second 64 KB): two files at once, lazy loading from the drive and from `M:`, the RAM disc, far arrays over its banks, the compiler. Needs the ROMs of build 31443 or later -- built from this repository (`tools/build.sh`); `roms/` is still an older build | -- |

Checked on a real CPC 464 with Revaldinho's universal 512K RAM card, on
2026-11-12: all three, every check yes. **That card wants DIP
configuration 4 on a 464** (switches 1234 = 0100: DK'tronics mode, all
eight banks; 0 on a 6128): its shadow modes give bank 3 to the base RAM,
and the 512K version's loader then stops with "Banks of 64K that answer:
3".

(HWTEST writes small files to drive A -- LZ.LSP, NOTES.LSP -- and to
`M:`; the 512K version's test 5 takes a minute or two.)

The disc versions' own documentation: `mach/cpc512/README.md`,
`mach/cpc6128/README.md`. Licence: GPL-3.0, as the rest of the
repository; what you write in CPC Lisp is yours (see the main README).
