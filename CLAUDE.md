# CPC Lisp — working notes for Claude

A Lisp machine for the Amstrad CPC: an **auto-boot ROM** (maybe two) that
starts a Lisp instead of BASIC. Mike's brief, 2026-11-06: a modern dialect
with Common Lisp syntax; speed is not the point and no byte-code compiler is
needed, though one would be nice later; closures; graphics, disc and sound.

These notes carry over what was learned on LambdaSpeak 4
(`~/git/lambdaspeak4`, private), so a session in this repo does not have to
rediscover it. That project's memory notes do not load here -- this file is
the bridge. Keep it current; put new lasting lessons here or in this repo's
own memory.

## The starting design (proposed, not settled -- confirm with Mike)

* **ROM 0 is the core.** At power-up the firmware enters whatever answers
  as ROM 0 -- normally BASIC. An expansion ROM answering 0 (with ROMDIS
  silencing the internal one) replaces it. Evaluator, reader, printer, GC,
  REPL and line editor live here.
* **A second ROM is the library**: graphics, sound and disc wrappers over
  the firmware jumpblock, and as much of the language as possible written in
  Lisp itself (macros), stored in ROM.
* **Z80 assembly with rasm**, not C: a Lisp with GC and a reader in C would
  not fit 2 x 16 KB.
* **Lexical closures**: environments in the heap, `lambda` captures them.
  `defun`, `let`/`let*`, `labels`, `setq`/`setf`, `if`/`cond`/`when`/
  `unless`, `and`/`or`, `progn`, `dolist`/`dotimes`, `defmacro` + backquote.
  Tail calls in `eval` (if/progn/let bodies) -- the Z80 stack is small.
* **Data**: fixnums, symbols, conses, strings, characters; maybe vectors.
  Floats only if the firmware's maths routines are usable -- verify first.
* **Heap**: RAM &0040-&A6FF on a 464 is about 42 KB before ROM workspace;
  4-byte conses give roughly 8-9 K cells. Mark-and-sweep with a
  non-recursive mark (pointer reversal). The 6128's extra 64 KB is a later
  option.
* **I/O through the firmware**: text VDU, KM for keys, GRA for graphics,
  the sound manager, CAS/AMSDOS for files -- so `(load "x.lsp")` works with
  any disc ROM.
* **First milestone**: one ROM at 0 that boots to `LISP>` with integers,
  symbols, conses, `lambda` + closures, `defun`, `if`, `let` and GC; tested
  in MAME, then on Mike's 464 through the card.

**Upper ROM caveat:** code running in an upper ROM sits at &C000-&FFFF, the
same addresses as screen RAM. Screen access from ROM code goes through the
firmware (or careful ROM/RAM banking) -- design around it from the start.

## Hardware on Mike's bench

* **CPC 464, BASIC 1.0**, with **LambdaSpeak 4** (board 1). The card serves
  up to eight expansion ROMs from flash, uploaded over USB with no EPROM
  burning -- the reason this project is cheap to iterate. It also emulates
  the disc drive (54 flash discs) with **Parados as ROM 7**, and does speech,
  PlayCity (six more AY channels), MIDI, PCM drums and an RTC.
* **CPC 6128** with a Gotek on its own drive -- put away for now. The card
  runs a separate 664/6128 firmware build there.
* The 664 is untried.

Mike tests on the real machines. Tell him exactly what to type, and what he
should see.

## Toolchain (already on this machine)

| | |
|---|---|
| rasm 3.2.7 | `~/claude/midi80/toolchain/rasm/rasm` |
| iDSK | `~/claude/midi80/toolchain/idsk/iDSK` |
| hxcfe (HFE images) | `~/claude/midi80/toolchain/hxc/build/hxcfe` |
| MAME | `/usr/games/mame`; CPC ROMs in `~/claude/cpc/mame-roms` (`-rompath`) |
| 464 OS/BASIC 1.0 ROM image | `~/claude/cpc/mame-roms/cpc464/cpc464.rom`; firmware jumpblock table at &08AC, two bytes an entry |

**rasm reports a failed assembly on stdout and still exits 0.** Check for
`Write binary file` in its output.

## Testing in MAME

The pattern from LambdaSpeak 4 (`~/git/lambdaspeak4/tools/run_rom.sh` and
`emu/romtest.lua`, `emu/midipiano.lua` -- read them before writing a
harness):

    env -u WAYLAND_DISPLAY GDK_BACKEND=x11 xvfb-run -a \
      mame -rompath ~/claude/cpc/mame-roms -video none -sound none \
      cpc464 -exp rom -rom1 build/LISP.ROM -autoboot_script test.lua

* A 464 with a drive **and** a ROM box: `-exp ddi1 -exp:ddi1:exp rom -rom1 ...`.
* The ROM box has sockets `rom1`..`rom8`. **Open question:** which ROM
  number each socket answers, and whether MAME can put a ROM at **0** to
  replace BASIC. Settle that first; if it cannot, test the core as a
  background ROM entered by a command, or patch the boot.
* `screen:snapshot(path)` works with `-video none`; `-nothrottle` makes long
  runs fast.
* **Drive the key matrix directly** for held keys: `:kbrow.0`..`:kbrow.9`,
  where a field's `mask` is the CPC key number (row*8+bit);
  `field:set_value(1)` presses, `(0)` releases. `natkeyboard` presses and
  releases within a frame, and **drops the first character** of a posted
  string often enough to matter -- post a leading space.
* Use MAME's **cpc464** as the baseline (BASIC 1.0, the oldest firmware);
  check the 6128 too.

## CPC facts that cost time before

* **ROMDIS**: BASIC's ROM obeys it on all three machines, so a card ROM at 0
  replaces BASIC on the 464, 664 and 6128. **The 664/6128's internal AMSDOS
  ignores ROMDIS** -- never put anything at ROM 7 there (on a 6128, both
  drove the bus).
* **ROM 7** on the 464 with the card is the card's disc ROM (Parados now).
  Don't use 7 for Lisp.
* **Background ROMs reserve workspace at init**, near the top of RAM, and
  `MEMORY`/HIMEM does not move it. Every ROM the card serves lowers the free
  RAM -- measure HIMEM rather than trusting the arithmetic.
* **ESC / break**: the firmware's own key scan raises the break event from
  the interrupt, whatever the program reads (KM_BREAK_EVENT &1C90 queues an
  &EF marker after the ESC key). BASIC handles it; **our OS must handle the
  break event itself**. Don't "cancel" it with KM DISARM BREAK (&BB48). Drain
  the key buffer before returning to the REPL.
* **&F8FF** (the generic peripheral reset) is written by the firmware at boot
  **and** when `RUN"` starts machine code (&05E9, &061C on the 464). It
  resets the card's PlayCity chips, not its speech or MIDI mode.
* **BASIC 1.0 vs 1.1** differ in more than syntax; a `|` in a BASIC comment
  breaks 1.0. Any BASIC loader shipped with this must run on a 464.
* **An ASCII BASIC file loads through BASIC's editor** and is slow (172 lines
  is about 20 s); keys typed meanwhile are swallowed into the load.

## The LambdaSpeak 4 card, as a development tool

Everything is in `~/git/lambdaspeak4` (README: *The USB console*,
*Building and flashing*; `docs/rom-emulation.md`; `rom/README.md`).

* **Upload a ROM with `tools/romloader.py`** (GUI). **Never hand-roll an
  uploader**: on 2026-11-03 one that skipped the idle wait desynced, and the
  console executed 16 KB of ROM as keystrokes -- renumbering slots, one to
  ROM 0. If a command-line upload is wanted, reuse romloader's `wait_idle()`
  and `send_rom()` exactly (`ROM<slot><num>`, 16384 bytes in 256-byte chunks
  12 ms apart, wait for `stored`).
* **`N<slot><number>`** on the console renumbers a slot without re-uploading
  (255 = silent). `n` lists the slots. **Giving a slot ROM 0 means the CPC
  boots into it every time** -- to get BASIC back, set it to 255. Check `n`
  before Mike powers on after any change.
* Current slots (2026-11-06): 0 AMSDOS 0.5 (silent), 1 vector head (ROM 1),
  2 Parados (ROM 7), 3 ROM 3, 4/5/7 silent (old images), 6 LSAI (ROM 2).
  **Ask Mike which slots the Lisp ROMs may overwrite.**
* **Before flash writes or a firmware flash, the CPC should be off.** Check
  with `kitloader.cpc_is_off()` (`~/git/lambdaspeak4/tools/kitloader.py`):
  two `d` readings with `/IORQ /RD /WR` all zero. Counters standing still do
  NOT mean it is off.
* **Discs**: `tools/mkcpcdisk.py` builds a DSK and an HFE; `tools/dskloader.py`
  puts a `.dsk` in a flash slot or the drive (`--list`, `--slot N`,
  `--load N`, `--get N`). Free flash disc slots: 8, 14, 50-54.
* **The Gotek serves a cached image**: after copying a disc to its stick,
  Mike must re-select it. **AMSDOS caches the catalogue** too.

## Working rules with Mike

* Concise reports; say what was verified and how.
* **Never crawl the NAS**: no `find`/`grep -r` from `/` or over all of
  `~`. Look in known places; `find <dir> -xdev` with a timeout if needed.
* This repo is **local only** (no GitHub remote yet). Ask before creating
  one; private by default.
* Commit with the attribution lines the session gives you.
