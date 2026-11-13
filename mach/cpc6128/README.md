# CPC Lisp from disc, on a plain CPC 6128

The Lisp of the ROMs, loaded from disc into a 6128's own 128 KB -- no ROM
board, no expansion: the core and the four library parts, built from the
same sources. The compiler (the VM ROM) is left out: there is no room
for a sixth image.

    CPC Lisp 0.96
    A Lisp machine for the Amstrad CPC, 128K
    library ROMs 1 2 3 4
    2430 cells free

## What it needs

* A **CPC 6128**, or a 464 or 664 with a 64 KB RAM expansion that banks
  the DK'tronics/Amstrad way (configurations &C4-&C7). With a 512K
  expansion, use the 512K version (`mach/cpc512`): the compiler, a RAM
  disc and more than twice the cells.
* A disc drive: the 6128's own, a DDI-1, or Parados.

## Starting

Put the disc in drive A and type

    RUN"LISP

`LISP.BIN` loads `LISP0.IMG`-`LISP4.IMG` and starts Lisp. Without the
second 64 KB it says so and goes back to BASIC. `(basic)` goes back to
BASIC; `RUN"LISP` starts a fresh Lisp.

## What is different

Everything of the ROM version is there but:

* **No compiler**: `compile`, `compile-file`, `disassemble` are undefined.
* **No RAM disc**: the second 64 KB holds the code; `M:` says so.
* **Less room**: about 2400 cells and 5 KB of strings, against 6400
  cells with the ROMs; the stack is 3.25 KB, some 250 calls deep (350
  with the ROMs). A file open takes 2 KB of the strings' space: two at
  once fit, but not with many strings about.

## How it works

The 6128's second 64 KB is four 16 KB blocks, 4-7; the CPU sees one of
them at &4000 (configurations C4-C7), or block 7 at &C000 (C1). So:

| image | what | where it runs |
|---|---|---|
| LISP0.IMG | the core | block 7 at &C000 (C1), as in ROM |
| LISP1.IMG | library part 0 | block 4 at &4000 (C4) |
| LISP2.IMG | library part 1 | block 5 at &4000 (C5) |
| LISP3.IMG | library part 2 | block 6 at &4000 (C6) |
| LISP4.IMG | library part 3 | the main RAM's &4000 (C0) |

The library parts are assembled at &4000 (`LIB_ORG` in `memmap.asm`):
their addresses keep the part in the top two bits, and `lib_addr`
(`src/xrom.asm`) and `lib_dispatch` (`lib/common.asm`) put back &4000's
bits instead of &C000's. The core stays at &C000, so nothing else in it
changes.

The main RAM's &4000-&7FFF is code, and hidden whenever a part in blocks
4-6 runs: so the cells end at &4000 (`CELL_TOP`), and block space and
the stack are above &8000 (`BLK_LO`, `MACH_BLOCKS` in `mmacros.asm`).
The stack is 3.25 KB (`STACK_SIZE`, 4 KB elsewhere), so that block space
can lend two file buffers.

The rest is the 512K version's: switching parts is one `OUT` to &7F
(`SYS_BANK`, the bank's configuration from `BANK_CFGS`), and the
resident part holds the firmware's trampolines and whatever must see
the screen -- at &A2F0 here, without the RAM disc's routines
(`variant.asm`: `RESIDENT`, `RAMDISC`). This directory has only what
differs; the other files are links to `mach/cpc512`'s (rasm reads an
include beside the link, so they get this machine's `memmap.asm`,
`mmacros.asm` and `variant.asm`).
`novm` tells `tools/build.sh` to leave the VM ROM out, and its names
out of part 1's table.

On the real machine (2026-11-12): Mike's 464 with Revaldinho's 512K card
(this version uses its bank 0) -- `HWTEST.LSP` on the disc, `(load
"hwtest")`, `(hwtest)`: all it checks here passed, and the screen, the
function editor, ESC and the card's speech.

## Building and testing

    MACH=cpc6128 tools/build.sh       # build/cpc6128: the images, LISP.BIN,
                                      #   cpclisp6128.dsk
    tools/cpc6128/run.sh file.lsp     # MAME, a 6128 (-m 464: a 464 with
                                      #   128K and a DDI-1)
    tools/cpc6128/test.sh             # the regression tests

`test/NAME.cpc6128.out` is a test's expected output where this
machine's differs; `test/skip.cpc6128` names the tests it skips (the
compiler's).
