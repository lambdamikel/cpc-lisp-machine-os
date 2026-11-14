# CPC Lisp from disc, on a CPC with a 512K expansion

The same Lisp as the ROM version -- the same six images, built from the
same sources -- but loaded from disc into a RAM expansion: no ROM board
and no LambdaSpeak card needed.

    CPC Lisp 0.97
    A Lisp machine for the Amstrad CPC, 512K
    library ROMs 1 2 3 4
    6054 cells free

## What it needs

* A CPC 464, 664 or 6128 with a **512K RAM expansion** that banks the
  DK'tronics/Amstrad way -- configurations &C0-&C7 on port &7Fxx, bits
  3-5 the 64K bank: Revaldinho's universal RAM cards, the DK'tronics
  512K, the RAM of an X-MEM. It needs six 64K banks, so a 256K expansion
  is not enough, and neither is a 6128 on its own (its second 64K is one
  bank). **Revaldinho's universal 512K card on a 464 or 664: DIP
  configuration 4** (switches 1234 = 0100: "overdrive", DK'tronics
  mode, all eight banks); on a 6128, configuration 0. Its shadow modes
  (8 and 12, for the 6128's C3 mode) give bank 3 to the base RAM, and
  the loader stops: "Banks of 64K that answer: 3". Checked on Mike's
  464, 2026-11-12: with configuration 4, everything `HWTEST.LSP` checks
  passed (below).
* A disc drive: AMSDOS (a 6128's, a 464's DDI-1) or Parados.

## Starting

Put the disc in drive A and type

    RUN"LISP

`LISP.BIN` finds the expansion, loads `LISP0.IMG`-`LISP5.IMG` into it,
and starts Lisp. Without the expansion it says so and goes back to BASIC.
`(basic)` -- or `(reset)` -- goes back to BASIC; `RUN"LISP` again starts a
fresh Lisp, and the RAM disc keeps its files.

## A test of the real machine

The disc has `HWTEST.LSP`: `(load "hwtest")`, then `(hwtest)` says yes or
NO to the cells, two files open at once, lazy loading from the drive,
the RAM disc, far arrays (into banks 6 and 7: a minute or two) and the
compiler, and lists four things to try by hand; after CTRL-SHIFT-ESC and
`RUN"LISP`, `(load "hwtest")` and `(hwtest2)` check that the RAM disc's
files and a far array survived. The plain 6128's disc has it too, for
what that version has.

## The RAM disc

Drive `M:` is in the expansion's free blocks: 415 KB free with a 512K
expansion's eight banks (287 KB if only six answer) -- `(save
"m:work")`, `(load "m:work")`, `(dir "m:")`, `(delete-file "m:work")`,
streams, an input and an output file at once. 31 files. It keeps its
files through a reset and a new `RUN"LISP` (the loader writes only the
blocks the code goes in), not through switching off.

Far arrays are files here: `(make-far-array "table" 60000)` -- numbers,
characters or bytes, outside the cells, up to 65535 an array, as many as
fit -- and `(far-array "table")` finds one again after a reset. A big
program can stay here too, `(load "m:big" :lazy t)`: each function is
read in when first called and dropped when the cells run short.

## How it works

Each image goes into block 3 of a 64K bank, banks 0-5: configuration C1
(&7F, &C1 + 8 x bank) shows that block at &C000, as the ROM version's
images are at &C000. Switching from one part of the Lisp to another is
one `OUT` to &7F, where the ROM version calls KL ROM SELECT -- the core
calls `SYS_BANK` either way.

The main RAM's &C000-&FFFF is the screen, and the CPU sees it only in
configuration C0. So a small **resident part** in the main RAM, at
&A160-&A6EF (`resident.asm`), does whatever touches the screen with C0
switched in, and puts the Lisp's bank back after:

* each firmware routine the Lisp calls goes through a trampoline there,
  "call fwc : dw address" (`fwtab.inc`, made with `firmware.asm` and
  `fwreal.asm` by `tools/cpc512/mkfw.py` from `mach/cpc/firmware.asm`) --
  but the maths package, which touches no screen, is called directly;
* the function editor's renderer (`frcode.asm`, a copy of
  `mach/cpc/fr.asm`'s);
* the screen bytes `peek`, `poke` and `flood-fill` read and write;
* the RAM disc's copying (`RS_XFER`: a block at &4000 in C4-C7 -- through
  a buffer of its own, for a file's buffer may be at &4000-&7FFF too), and
  the file routines (`FILE_GETC`...), which call the RAM disc's code in its
  bank for a file on `M:` (`ramdisc.asm`, the TRS-80's RAM disc made for
  the CPC's banks).

The Lisp registers no firmware events, so no Lisp code runs at interrupt
time, when its bank might not be in. BASIC's `RUN` of a binary file
restarts the firmware, so the loader walks the ROMs itself, as a
foreground ROM does; the disc ROM's workspace must leave &A160-&A6EF
free (a 6128 or a 464 with a DDI-1: it does).

## Building and testing

    MACH=cpc512 tools/build.sh        # build/cpc512: the images, LISP.BIN,
                                      #   cpclisp512.dsk
    tools/cpc512/run.sh file.lsp      # MAME, a 6128 with 576K (-m 464: a 464
                                      #   with 576K and a DDI-1)
    tools/cpc512/test.sh              # the regression tests

MAME's own romsets, with BASIC; the harness types `RUN"LISP` at BASIC's
EDIT and then the file's lines at Lisp's `EDHOOK` (`LISP_EDIT2` in
`emu/repl.lua`). `test/NAME.cpc512.out` is a test's expected output where
this machine's differs (`*features*`, the disc's own files, the RAM
disc's size).
