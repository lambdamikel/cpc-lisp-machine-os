# CPC Lisp 0.95 -- the machine layer

*A Lisp machine for the Amstrad CPC*

Everything in CPC Lisp that depends on the machine is in `mach/<machine>/`;
everything in `src/` and `lib/` is portable Z80 code that reaches the
machine only through the names listed here. `mach/cpc/` is the Amstrad
CPC, `mach/trs80/` the TRS-80 Model I and III with X-MEM/80 (its
[README](trs80/README.md)). A port to another Z80 machine is a new
directory beside it with the same files, and a build with `MACH=<machine> tools/build.sh` (the default
is `cpc`).

On the CPC the interface costs nothing: each name is the address of a
firmware routine, and the ROMs are byte for byte what they were before
the split (`BUILD_ID=n tools/build.sh` fixes the build number, so two
builds can be compared with `cmp`).

## What the machine must offer

* **A Z80**, and its interrupts left alone: IY and the alternate registers
  are never touched by the portable code.
* **Six 16 KB banks of code, seen at &C000-&FFFF, one at a time**: the
  core, library parts 0-3 and the VM ROM. They are assembled for &C000,
  and the object encoding needs that window at the top of memory: an
  address of &C000 or more is a builtin (an entry in the core's symbol
  table) or library code, never a Lisp object in RAM. On the CPC the banks
  are ROMs; on another machine they may be RAM pages loaded at boot.
  Switching (`SYS_BANK`) may be slow: on the CPC it is some 2000 T-states.
  (The library parts may run at &4000 instead -- `LIB_ORG` below -- as on
  a plain 6128, `mach/cpc6128`; the core stays at &C000. The VM ROM may be
  left out: `novm` below.)
* **RAM below &C000 that is always there**, for what `memmap.asm` lays out:
  * the low system area, 1.2 KB: the GC's mark stack, the symbol hash
    table, LIBDEFS and FNBOUND (512 bytes, 256-aligned);
  * the symbols (`SYM_LO`, 512 slots of 8 bytes: 4 KB), and the cells from
    `CELL_LO` = `SYM_HI` up, then the mark bitmap, block space and the 4 KB
    stack, up to the last usable byte. `SYM_LO` must be &0500 or more:
    every word below it is an immediate (characters, markers, headers);
  * the fixed area, 1.25 KB: `LINEBUF`, `TOKBUF`, `VARS`, `LIBSCR`,
    `HISTBUF`, `TRAMP` (the cross-bank trampoline, 58 bytes, copied at
    boot) and `RDISK`.

  On the CPC that is about 40 KB, from &0040 to &B0FF. With the parts at
  &4000, &4000-&7FFF is theirs: `CELL_TOP` ends the cells below it, and
  `BLK_LO` starts block space above.
* **The machine's routines reachable from the bank that calls them.** On
  the CPC the firmware's jumpblock is always there. A port puts its
  routines in RAM that is always visible -- its own firmware -- or in each
  bank that needs them (see *Who needs what*).

## The files

| file | included by | what |
|---|---|---|
| `firmware.asm` | `src/defs.asm` | the machine's own entry points, for its files' use (on the CPC: the firmware's, by name) |
| `machine.asm` | `src/defs.asm` | the interface names below, bound to the machine |
| `memmap.asm` | `src/defs.asm` | the memory map: `LOWMEM`, `MARKSTK`, `MARKSTK_END`, `OBARRAY`, `NBUCKETS`, `OBARRAY_END`, `LIBDEFS`, `LIBDEFS_END`, `FNBOUND`, `SYM_LO`, `NSYMS`, `SYM_HI`, `CELL_LO`, `LINEBUF`, `TOKBUF`, `VARS`, `LIBSCR`, `HISTBUF`, `TRAMP`, `RDISK`, `VARS_END`; if the parts run at &4000, `LIB_ORG` (&4000; &C000 if not defined), `CELL_TOP` (where the cells end; `src/lisp.asm`'s layout), and what `MACH_BLOCKS` needs |
| `mmacros.asm` | `src/macros.asm` | the macros: `MACH_START`, `MACH_INIT`, `MACH_BLOCKS`, `FM`, `SYS_RESET`, `MACH_TITLE` |
| `fp.asm` | `lib/float.asm` (part 1) | calling the maths routines: `fmcall` (for `FM`), `fp_callix` |
| `fr.asm` | `lib/lib.asm` (part 0) | the function editor's screen: `VID_INIT`, `VID_CHAR`, `VID_NORMAL`, `VID_INVERSE`, `VID_PAPER`, `VID_COLS`, `VID_FONTSIZE`, `VID_ROWS`, `VID_VARS` |
| `ramdisc.asm` | `lib/disc.asm` (part 0) | a RAM disc, drive `M:`: `RDISC_IS`, `RDISC_IN`, `RDISC_OUT`, `RDISC_CAT` |
| `natives.asm` | `lib/gfx.asm` (part 0) | Lisp functions of the machine's own |
| `graphics.asm` | the end of `lib/gfx.asm` (part 0) | `SYMBOL` and `FLOOD-FILL`, or nothing |
| `card.asm` | `lib/lib2.asm` (part 1) | more of the machine's own: on the CPC, speech and PlayCity on the LambdaSpeak card |
| `far.asm` | `lib/farray.asm` (part 1) | far arrays' way into the RAM disc: its directory's layout and `fa_xfer` (below) |
| `hwtest.lsp` | the machine's disc (`post-build.sh`) | a test for the real machine: `(load "hwtest")`, `(hwtest)` |

The assembler finds them with `-I mach/$MACH`, and `tools/mklib.py` finds
the Lisp functions in them (their `;@` lines) the same way. A file `novm`
there makes `tools/build.sh` leave the VM ROM out, and its names out of
part 1's table. A machine that is a variant of another can be a
directory of links to the other's files, with its own beside them
(`mach/cpc6128`): rasm reads an include from the directory of the link
first.

## Who needs what

| bank | names |
|---|---|
| core | `CON_PUTC` `CON_GETCUR` `KEY_READ` `KEY_UNREAD` `KEY_TEST` `KEY_ESC` `FILE_GETC` `FILE_PUTC` `FILE_IABANDON` `FILE_OABANDON` `SYS_BANK` `SYS_CURBANK` `NBANKS` `MACH_START` `MACH_INIT` |
| part 0 | the rest of `CON_`, `KEY_`, `VID_`, `GFX_`, `FILE_`; `SND_QUEUE` `SYS_TIME` `SYS_RESET`; `RDISC_` |
| part 1 | `CON_GETCUR`, `FM` and the `FP_` routines, `fp_callix`; `FILE_GETC` `FILE_PUTC` (lazy loading's skipping, far arrays' filling); `far.asm` |
| parts 2, 3, the VM ROM | nothing |

## The interface

**The contract of each name is that of the CPC firmware routine it is
bound to**, as *The Amstrad CPC Firmware Guide* gives it: what goes in,
what comes out, which registers are kept. A port keeps at least what that
routine keeps. The notes say what the Lisp relies on beyond that.

### Console: the text screen

| name | CPC | the Lisp relies on |
|---|---|---|
| `CON_PUTC` | TXT OUTPUT | A = a character. Controls: 7 (bell), 10 (line feed), 13 (return) are the Lisp's; `putc` (`src/print.asm`) sends a lone 10 as 13, 10. Other codes below 32 are the user's, and the machine's to interpret (on the CPC: 12 clears, 31 moves the cursor...) |
| `CON_WRCH` | TXT WR CHAR | A = a character, drawn as it is, the cursor moved on |
| `CON_RDCH` | TXT RD CHAR | -> carry and A = the character under the cursor: the line editor's copy cursor reads the screen with it |
| `CON_GETCUR` | TXT GET CURSOR | -> H = column, L = row (from 1, in the window), A = the *roll count*, which goes down by one each time the window scrolls up. The line editor keeps rows less the roll count, so a line survives a scroll. A machine without hardware scrolling counts its scrolls |
| `CON_SETCUR` | TXT SET CURSOR | H = column, L = row |
| `CON_CURON` `CON_CUROFF` | TXT CUR ON, OFF | the cursor shown, hidden (the system's switch) |
| `CON_CURENA` `CON_CURDIS` | TXT CUR ENABLE, DISABLE | the user's switch for it |
| `CON_INVERSE` | TXT INVERSE | pen and paper swapped |
| `CON_GETWIN` | TXT GET WINDOW | -> H, D = left and right column, L, E = top and bottom row, from 0: the editors and the pretty printer take the width from it |
| `CON_CLS` | TXT CLEAR WINDOW | `cls` |
| `CON_PEN` `CON_PAPER` | TXT SET PEN, PAPER | A = a pen, 0-15 |

### Keys

| name | CPC | the Lisp relies on |
|---|---|---|
| `KEY_READ` | KM READ CHAR | -> carry and A = a character, or no carry if none is waiting |
| `KEY_WAIT` | KM WAIT CHAR | -> A = a character |
| `KEY_UNREAD` | KM CHAR RETURN | A = a character, to be read next |
| `KEY_TEST` | KM TEST KEY | A = a key number -> NZ while the key is down. The numbers are the machine's: `key-down-p` passes the user's on |
| `KEY_ESC` | 66 | the number of the key that breaks |

The editors expect the CPC's codes for these keys, so a port's `KEY_READ`
returns them: 9 TAB, 13 RETURN, &7F DEL, &10 CLR, &13 CTRL-S, &E0 COPY,
&F0-&F3 the cursor keys up, down, left, right, &F4-&F7 with SHIFT, &F8-&FB
with CTRL, and &FC for ESC. ESC is break: `poll_esc` (`src/eval.asm`)
breaks when it reads &FC, or &EF, the CPC's break marker, or when
`KEY_TEST` says `KEY_ESC` is down.

### Video: the screen as a whole

| name | CPC | the Lisp relies on |
|---|---|---|
| `VID_MODE` | SCR SET MODE | A = a mode: 0, 1, 2 are 20, 40, 80 columns on the CPC (`mode`) |
| `VID_INK` | SCR SET INK | A = an ink, B, C = its colours (`ink`) |
| `VID_BORDER` | SCR SET BORDER | B, C = its colours (`border`) |
| `VID_FRAME` | MC WAIT FLYBACK | waits for the next frame (`frame`, the editors) |
| `VID_FILLBOX` | SCR FILL BOX | A = `VID_PAPER`; H, D = left, right column, L, E = top, bottom row: the function editor clears with it |

The function editor draws its own characters, far faster than the
firmware could (`fr.asm`):

| name | the Lisp relies on |
|---|---|
| `VID_INIT` | DE = `VID_FONTSIZE` bytes, lent from block space while the editor runs. Finds the mode, the colours, where the screen is |
| `VID_CHAR` | A = a character, B = column, C = row, from 0: drawn, as `VID_NORMAL` or `VID_INVERSE` said. BC kept |
| `VID_NORMAL` `VID_INVERSE` | how `VID_CHAR` draws from now on |
| `VID_PAPER` | a byte in RAM: the paper, as `VID_FILLBOX` takes it |
| `VID_COLS` | a byte in RAM: the screen's columns |
| `VID_FONTSIZE` | a constant |
| `VID_ROWS` | a constant: the screen's rows (the last is the function editor's status line) |
| `VID_VARS` | where the renderer's variables start in `LIBSCR`: the function editor keeps below it |

### Graphics

Logical coordinates, as on the CPC whatever the mode: x 0-639, y 0-399,
from the origin, y upwards. A machine with fewer pixels scales: the
CPC's own pixel is 2 units high and 1, 2 or 4 wide.

| name | CPC | the Lisp relies on |
|---|---|---|
| `GFX_PLOT` `GFX_MOVE` `GFX_LINE` | GRA PLOT, MOVE, LINE ABSOLUTE | DE = x, HL = y |
| `GFX_PLOTR` `GFX_MOVER` `GFX_LINER` | ... RELATIVE | DE, HL = offsets from where the last one ended |
| `GFX_TEST` `GFX_TESTR` | GRA TEST ABSOLUTE, RELATIVE | DE, HL -> A = the pen of that point |
| `GFX_WHERE` | GRA ASK CURSOR | -> DE = x, HL = y |
| `GFX_ORIGIN` | GRA SET ORIGIN | DE = x, HL = y |
| `GFX_PEN` `GFX_PAPER` | GRA SET PEN, PAPER | A = a pen |
| `GFX_CLEAR` | GRA CLEAR WINDOW | `clg` |

The circles, discs, boxes and the turtle (`lib/gfx.asm`) are drawn with
these alone, and keep IX around them.

### Sound

| name | CPC | the Lisp relies on |
|---|---|---|
| `SND_QUEUE` | SOUND QUEUE | HL = a sound, nine bytes as the firmware has them (channels, envelopes, period, noise, volume, duration) -> carry if it was queued; `sound` tries again while the queue is full |

### Files

One file open for input and one for output at a time, each with a 2 KB
buffer lent from block space.

| name | CPC | the Lisp relies on |
|---|---|---|
| `FILE_IOPEN` `FILE_OOPEN` | CAS IN OPEN, CAS OUT OPEN | B = the name's length, HL = the name, DE = the buffer -> carry if open |
| `FILE_GETC` | CAS IN CHAR | -> carry and A = a character, or no carry at the end |
| `FILE_PUTC` | CAS OUT CHAR | A = a character |
| `FILE_ICLOSE` `FILE_OCLOSE` | CAS IN CLOSE, OUT CLOSE | |
| `FILE_IABANDON` `FILE_OABANDON` | CAS IN ABANDON, OUT ABANDON | the REPL abandons what an error left open |
| `FILE_CAT` | CAS CATALOG | DE = a buffer: the directory, shown on the screen (`dir`) |
| `FILE_BUFSIZE` | 2048 | the size of the buffer lent to each open file |

Names are the CPC's: up to eight letters, a dot and three, a drive in
front (`A:`); `load` and `save` add `.LSP` to a name without a dot.

### Floats

Five-byte reals in the CPC firmware's form: four bytes of mantissa, least
significant first, the top bit of the last one the sign, then the
exponent (0 is zero). `lib/float.asm` reads and writes those bytes itself,
so a port's routines work on the same form. They are called with the
macro `FM name`, or with the name in IX and `call fp_callix`; A, BC, DE,
HL go in, IX is lost.

| name | what |
|---|---|
| `FP_MOVE` | (HL) = (DE) |
| `FP_INT2R` | HL = a magnitude, A bit 7 = the sign -> the real at (DE) |
| `FP_BIN2R` | four bytes at HL, A bit 7 = the sign -> a real there |
| `FP_R2INT` | (HL) -> HL rounded, S = the sign, carry if it fitted |
| `FP_R2BIN` `FP_FIX` `FP_INT` | (HL) -> four bytes there, rounded, truncated, floored; B bit 7 = the sign |
| `FP_EXP10` | (HL) times 10 to the power A |
| `FP_ADD` `FP_MUL` `FP_DIV` | (HL) = (HL) op (DE) |
| `FP_RSUB` | (HL) = (DE) - (HL) |
| `FP_CMP` | A = 1, 0, &FF as (HL) >, =, < (DE) |
| `FP_NEG` | (HL) = -(HL) |
| `FP_SGN` | A = 1, 0, &FF; Z if zero, carry if negative |
| `FP_ANGLE` | A = 0: radians |
| `FP_PI` | (HL) = pi |
| `FP_SQR` `FP_LOG` `FP_EXP` `FP_SIN` `FP_COS` `FP_TAN` `FP_ATN` | (HL) = that of (HL) |
| `FP_POW` | (HL) = (HL) to the power (DE) |

Each returns carry if all went well, as the firmware's do.

### System

| name | CPC | the Lisp relies on |
|---|---|---|
| `SYS_BANK` | KL ROM SELECT | C = a bank -> C = the one that was in. The trampoline (`src/xrom.asm`: `ROMCALL`, `ROMPEEK`) is all that calls it |
| `SYS_CURBANK` | KL CURR SELECTION | -> A = the bank in now: at boot, the core's own |
| `NBANKS` | 16 | banks 1 to `NBANKS`-1 are searched for the library |
| `SYS_TIME` | KL TIME PLEASE | -> DEHL = the time in 1/300 s (`time`) |

### Macros

| name | the Lisp relies on |
|---|---|
| `MACH_START` | the core's first step: the machine made ready, the stack set below &C000, and the last usable byte of RAM pushed. On the CPC: KL ROM WALK, which starts the background ROMs (the disc) |
| `MACH_INIT` | HL = that byte, the low area and the variables clear -> `V_MEMTOP` and `V_EDITV` set: `V_EDITV` is the line editor used when there is no library (on the CPC the firmware's EDIT, whose address differs between the 464 and the 664/6128). It may keep RAM for itself under the top: the CPC keeps 128 bytes for `SYMBOL` (`V_UDG`) |
| `MACH_BLOCKS` | HL = the bytes left for cells and blocks -> HL = block space's share (strings, vectors, floats, compiled code, file buffers); the CPC gives 11/64 |
| `FM` | `FM name` calls the maths routine `name` (above) |
| `SYS_RESET` | starts the machine afresh (`reset`) |
| `MACH_TITLE` | the banner's second line: `db "A Lisp machine for ...",13,10,0` |

### A RAM disc (it may be left out)

| name | the Lisp relies on |
|---|---|
| `RDISC_IS` | `TOKBUF` holds a file name -> Z if it names the RAM disc. A machine without one answers NZ |
| `RDISC_IN` `RDISC_OUT` | `TOKBUF` = "M:name", B = its length -> carry if the file is open for reading, for writing; while it is, `FILE_GETC` and the rest reach it (on the CPC the RAM disc takes over the cassette vectors) |
| `RDISC_CAT` | its files listed (`dir "m:"`) |

A file on `M:` is lent 512 bytes of block space (`fl_lend_f`), not the
2 KB a disc file gets: a RAM disc must keep its state for an open file
in that (the CPC 512K's and the TRS-80's use 64 bytes and a 256-byte
buffer after them). Its errors after the lend (no RAM disc, a bad name)
call `fl_release` before `lib_error`, or the buffer stays lent when the
error is caught.

### Far arrays (with the RAM disc; `far.asm`)

A far array (`lib/farray.asm`) is a file on `M:` read and written in
place. `far.asm` says how the machine's RAM disc keeps its directory --
`FA_DIR0` (where entry 0 is), `FA_ESIZE`, `FA_NENT`, `FA_USED` (the
in-use byte's offset, or -1: in use if the name is not empty),
`FA_NAME`, `FA_PAD` (what pads a name), `FA_START`, `FA_LEN`, `FA_W`
(2 or 3 bytes a start and a length) -- and has `fa_xfer`: A = 0, BC
bytes from the disc at `FA_OFF` (three bytes) to RAM at HL; 1, the other
way. The RAM is `TOKBUF`'s; `FA_X` (16 bytes) is `fa_xfer`'s own. A
machine without a RAM disc can link the 6128's (`mach/cpc6128`): it
refuses, as `M:` does.

### The machine's own Lisp functions

What only makes sense on one machine is a Lisp function of its own, in
`natives.asm`, `graphics.asm` and `card.asm`. The CPC's:

* `natives.asm`: `ink-mode`, `window`, `tag`, `transparent`,
  `flash-speed`, `text-cursor`, `joystick`, `peek`, `poke`, `envelope`,
  `tone-envelope`, `release`, `sound-check`, `sound-hold`,
  `sound-continue`;
* `graphics.asm`: `symbol`, `flood-fill`;
* `card.asm`: `say`, `speech-stop`, `speech-voice`, `speech-rate`,
  `speech-volume`, `playcity`, `pc-tone`, `pc-off`.

Library part 0 has about 240 bytes free (18 on the CPC 512K), part 1
about 130, part 3 about 450 (2026-11-12): a port's own functions go where
there is room, Lisp text in any part.

## A port, step by step

1. `mach/<machine>/`, starting from a copy of `mach/cpc/`.
2. `memmap.asm`: where the low area, the symbols, the heap and the fixed
   area go below &C000.
3. `machine.asm` and the routines behind it: the console, keys and files
   first, then graphics, sound and floats. A name the machine cannot
   honour still needs a routine that does nothing sensible.
4. `mmacros.asm`: start-up (`MACH_START`, `MACH_INIT`), the maths call,
   reset.
5. Loading the six banks at start-up, and switching them (`SYS_BANK`).
6. The machine's own Lisp functions.
7. A `hwtest.lsp` for the real machine (the CPC's are the pattern) on its
   disc.
8. Testing: the MAME harness (`emu/repl.lua`) is the CPC's. It catches
   output at TXT OUTPUT (&BB5A) and types a line whenever the core calls
   `EDHOOK`, so another machine needs a harness that does the same at its
   own `CON_PUTC`.

After any change, the CPC's ROMs should still be what they were: build
twice with the same `BUILD_ID` before and after, and compare.
