# CPC Lisp on the TRS-80 Model I with X-MEM/80

*A port in progress.* The same Lisp as on the CPC -- the six images are
built from the same sources -- on a TRS-80 Model I with Michael Wessel's
and Mark Pruden's [X-MEM/80](https://github.com/lambdamikel/x-mem-80)
512 KB paged memory, in its X-MEM mode (16 KB pages), under LDOS 5.3.

## Building and running

    MACH=trs80 tools/build.sh     # build/trs80: the images, LISP/CMD,
                                  #   lisp-a.dsk and lisp-b.dsk
    tools/trs80/play.sh           # trs80gp in a window: LDOS boots, LISP runs
    tools/trs80/run.sh file.lsp   # type a file at it in trs80gp, print the
                                  #   transcript

The discs are LDOS 5.3.1 for the Model I, single density: `lisp-a.dsk`
boots and holds `LISP/CMD` and the first images, `lisp-b.dsk` the rest
(LDOS looks for a file in every drive). At `LDOS Ready`, `LISP` loads the
seven pages and starts. `(quit)` goes back to LDOS.

`tools/trs80/ldos-m1.dsk` is the starting disc: a minimal LDOS 5.3.1
system disc with nothing else on it (from the MIDI/80 project's discs).

## How it is arranged

| | |
|---|---|
| &0000-&3FFF | ROM, keyboard, screen (64 x 16 at &3C00) |
| &4000-&51FF | LDOS |
| &5200-&53FF | the resident part: SYS_BANK and the jumpblock (`resident.asm`) |
| &5400-&BAFF | the Lisp's RAM: tables, symbols, cells, strings, the stack (`memmap.asm`); &8000-&BFFF is X-MEM page 1, never moved |
| &BB00-&BFFF | the fixed variables and buffers |
| &C000-&FFFF | one code page at a time: the core (page 2), library parts 0-3 (3-6), the VM (7), the machine page (8) |

The six images run unchanged in the &C000 window -- they are assembled
for it on the CPC too. A switch is one `OUT (66)`. The machine's routines
-- the console, keys, graphics, files, floats -- live in their own page
(`page.asm`); a call to an interface name lands in the resident
jumpblock, which maps that page in, calls the routine, and maps the
caller's page back (`resident.asm`, `jumps.asm`; `tools/trs80/mkjumps.py`
makes the jumpblock from one list). The loader (`loader.asm`, LISP/CMD)
reads the seven pages through LDOS.

About 3150 cells are free at start, half a CPC's.

## The keys

| TRS-80 | CPC Lisp |
|---|---|
| BREAK | ESC: interrupts |
| <- | DEL: the character to the left |
| SHIFT <- | cursor left |
| -> | cursor right |
| SHIFT -> | TAB |
| up, down | the history |
| SHIFT up, SHIFT down | the copy cursor |
| CLEAR | CLR: the character under the cursor |

`key-down-p` takes the matrix's numbers, row * 8 + bit: ENTER 48, CLEAR
49, BREAK 50, up 51, down 52, left 53, right 54, SPACE 55.

## What works, and what not yet

* The language, the compiler, the editors, `format`, the extended
  `loop`, structures, hash tables, string streams.
* **Floats**, the CPC's five-byte reals: + - * / through the Level II
  ROM's double precision, as good as the CPC's; `sqrt` and whole powers
  the same; the other functions (`exp`, `log`, `sin`, `cos`, `tan`,
  `atan`) through its single precision, about seven digits.
* **Graphics** in the screen's 2 x 3 blocks, 128 by 48, from the CPC's
  logical 640 by 400; `ink-mode` (XOR, AND, OR); the turtle; circles,
  discs, boxes. One colour: a pen is lit or not.
* **Files** through LDOS: `load`, `save`, `open`, `with-open-file`,
  `probe-file`, `compile-file`. A name `B:FOO.LSP` is LDOS's
  `FOO/LSP:1`.
* `*features*` is `(:trs-80 :cpc-lisp)`; the demos look at it.
* Not yet: `dir`, sound (`sound` is silent), `symbol`, `flood-fill`,
  speech and music (Talker/80 and MIDI/80 belong here), the Model III, a
  RAM disc in X-MEM/80's spare pages, the images compressed onto one
  disc.

## In trs80gp

`-m1 -mem xmem80` is a Model I with X-MEM/80. With `-ee` the machine
page copies everything the Lisp prints, and each line typed, to the
printer -- `-batch` writes that to `trs80-printer.txt`, the transcript --
and `(quit)` ends the emulator. Typed input (`-i`) arrives when a program
waits in the ROM's key routine (&0049), which is where `KEY_WAIT` waits.
