# CPC Lisp on FutureOS itself (in progress)

*A Lisp machine for the Amstrad CPC* -- natively on TFM's FutureOS: no
firmware island (that is [`mach/futureos`](../futureos/README.md), the
released version). FutureOS stays resident, its RAM untouched, and Lisp
runs beside it, using FutureOS's own functions where it has them:
**loading** (LADE_N, from any FutureOS drive) and **character output**
(PR_2, mode 2). TFM asked for exactly that; Mike chose this way on
2026-11-19.

    CPC Lisp 0.99
    A Lisp machine for the Amstrad CPC on FutureOS
    library ROMs 1 2 3 4
    4713 cells free

## State (2026-11-19)

Phase 1 runs in MAME on a 464 and a 6128 (`tools/fos/run.sh`): the REPL,
the line editor, the function editor, floats, ESC, scrolling, `(room)`,
`(time)`, `(reset)` back to the desktop. Not yet: **files** (phase 2,
through FutureOS), **graphics and sound** (phase 3), the RAM disc and far
arrays, a hardware test. **Passed on Mike's 6128** the same day (build
30098, `cpclispfos-n.dsk` in the LambdaSpeak card's drive, FutureOS's drive
E; FutureOS from the card's slots, Revaldinho's card in configuration
0): the banner, sums and floats, scrolling, a wrapped line, the history,
the function editor, ESC, `(room)`, `(reset)` to the desktop -- "all
works, and much snappier".

## How it is arranged

* **LISP.64K** (`loader.asm`), started from the desktop, loads seven
  images through FutureOS's LADE_N from its own drive -- the core, the
  library's four parts, the VM ROM and the **machine page**
  (`page.asm`, LISP6.IMG) -- into block 3 of banks 0-2 and 4-7, puts the
  resident part at &9000, keeps FutureOS's &0000-&00FF in the page,
  takes the interrupts (IM 1, &0038), builds the maths jumpblock, sets
  FutureOS's 80 x 25 screen (S80X25) and starts the core.
* **The machine page** has a routine for each CPC firmware routine Lisp
  calls (82 names, `tools/fos/mkfw.py`), with the firmware's contract:
  the text screen (control codes, windows, hardware scrolling, the
  cursor, a copy of the characters for the copy cursor), the keys (the
  firmware's translation tables), the screen's mode and inks; graphics,
  sound and files are stubs so far.
* **The resident part** (`resident.asm`, &9000-&9AFF) is what must be in
  the main RAM: a trampoline per firmware name into the page, the bank
  switch, the interrupt -- a 300 Hz tick and the keyboard's matrix every
  sixth --, drawing a character with **FutureOS's PR_2** (ROM A, the
  lower ROM's font), filling and copying the screen's rows, the maths
  call, and the way back to FutureOS (its restarts, its 64 x 32 screen
  and colours, IM 2, TUR_D).
* **Floats**: FutureOS has none; the lower ROM's maths package is called
  at its real addresses (read from the lower ROM's own jumpblock table:
  &08AC on a 464, &08DE on a 6128), with the lower ROM in and the
  interrupts off, its RAM (&B8D0-&B8F7 on a 464, &B100-&B117 on a 6128,
  FutureOS's variables now) swapped with a copy of its own for the call.
* **Memory**: FutureOS keeps &A000-&BFFF; the fixed area is
  &9B00-&9FFF, the heap &1500-&8FFF (4713 cells at start, against 5497
  in the island).

## Building and testing

    MACH=fos tools/build.sh         # build/fos: the images, LISP.64K,
                                    #   cpclispfos-n.dsk
    tools/fos/run.sh [-m 6128] [-f frames] [-s shot.png] file.lsp

`run.sh` is `tools/futureos/run.sh`'s: FutureOS in MAME, drive A's
directory read, `LISP.64K` tagged and run; Lisp's output is caught at
its TXT OUTPUT trampoline (`LISP_TXTOUT`). After a change to
`mach/cpc/firmware.asm`'s names: `python3 tools/fos/mkfw.py`.
