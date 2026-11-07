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

## The design

Settled with Mike on 2026-11-06:

* **It must run on every CPC** (464, 664, 6128). Firmware is called **only
  through its vectors**, never at ROM-internal addresses. Past &BD37 the
  jumpblocks differ between the 464 and the 664/6128 -- see *CPC facts*.
* **Floats are wanted, through the firmware's maths package** (it is in the
  firmware ROM, not BASIC's, so it survives replacing BASIC).
* **Don't worry about ROM slots or numbers**: any number that does not
  collide with a built-in ROM (0 is BASIC, 7 the disc ROM). Development is
  in MAME; the real CPC comes much later.

What is built (`src/`, read `src/lisp.asm`'s header first):

* **ROM 0 is the core**, a foreground ROM: at 0 (ROMDIS) it replaces BASIC;
  at any other number `|LISP` starts it. It calls **KL ROM WALK** itself, as
  BASIC does, or no background ROM (disc!) is initialised.
* **Z80 assembly with rasm.** Common Lisp syntax and semantics where they
  fit: Lisp-2 (`#'`, `funcall`), symbols upcased, lexical closures, special
  variables (`defvar`), `defmacro` + backquote, `block`/`return-from`,
  `catch`/`throw`, `labels`/`flet`, `setf` on the usual places, `&optional`
  `&rest` `&body` `&aux` and destructuring. No `&key` yet.
* **Objects**: 16-bit words, tag in the low bits. Fixnums are 15-bit
  (-16384..16383). Symbols live in a fixed region (&0500-&14FF, 512 slots);
  cells (4 bytes) above; strings in a compacted block space; characters and
  markers are immediates below &0500. `src/defs.asm` has the layout.
* **GC**: mark and sweep; marking is iterative with a 256-word mark stack
  and a heap rescan on overflow (not pointer reversal -- simpler, any depth).
  The machine stack is scanned **conservatively**, so native code may keep
  Lisp values on it; it must never hold a raw block-space pointer across an
  allocation (blocks move).
* **Eval** is a loop with proper tail calls; the Lisp has its own 4 KB
  machine stack (the firmware's is tiny), checked against overflow.
* **Input** is the firmware's EDIT (BASIC's line editor, copy cursor and
  all); ESC is polled with KM TEST KEY during evaluation.
* **Still to come**: a second ROM (graphics, sound, disc, Lisp-defined
  library), floats, vectors, `&key`, `unwind-protect`, `load`, the 6128's
  extra RAM.

**Upper ROM caveat:** code running in an upper ROM sits at &C000-&FFFF, the
same addresses as screen RAM. Screen access from ROM code goes through the
firmware (or careful ROM/RAM banking). Likewise a ROM at another number
cannot be read while ROM 0's code runs: crossing ROMs needs RAM trampolines
or the firmware's FAR CALL.

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

    tools/build.sh                      assemble, splice into build/mame
    tools/run.sh [-m 464|6128] [-s shot.png] file.lsp    type it, print the transcript
    tools/test.sh [-m 6128] [-u]        regression: test/*.lsp against test/*.out

* **MAME's ROM box cannot answer ROM 0**: it numbers its *filled* sockets
  1, 2, 3... in order (rom1, rom2, rom8 became ROMs 1, 2, 3). So
  `tools/build.sh` builds private romsets in `build/mame` with BASIC's 16 KB
  replaced by LISP.ROM -- what ROMDIS does on the real machine. MAME warns
  about the checksum and runs it.
* `emu/repl.lua` catches output by tapping opcode fetches at &BB5A (TXT
  OUTPUT; A is the character) and types a line each time the ROM enters the
  EDIT vector. EDIT's own echo does not go through &BB5A, so the harness
  writes the typed line into the transcript itself.
* The first keys typed after power-up are lost: the harness waits 50
  frames before the first line, and posts every line with a leading space.
* `screen:snapshot(path)` works with `-video none`; `-nothrottle` runs at
  about 14x. Long tests outlast a 2-minute tool timeout -- run in background.
* The LambdaSpeak 4 patterns (`~/git/lambdaspeak4/tools/run_rom.sh`,
  `emu/romtest.lua`, `emu/midipiano.lua`) are the reference for anything
  new: tap tokens in globals, the key matrix through `:kbrow.N` fields.

## CPC facts that cost time before

* **A foreground ROM is entered** (464 and 6128 alike) with DE = &0040,
  HL = &ABFF, BC = &B0FF, SP = &BFF8. After KL ROM WALK, HL is &ABFF on a
  bare 464 and &A6F7 on a 6128 (AMSDOS takes ~1.3 KB, and every background
  ROM 4 bytes more). &AC00-&B0FF is the foreground's own area on both.
* **The jumpblocks differ past &BD37.** The 664/6128 insert twelve entries
  at &BD3A, so EDIT (the line editor -- firmware ROM, not BASIC) is &BD3A on
  a 464 and &BD5E on a 664/6128, and the maths package starts at &BD3D
  (464, 49 entries) or &BD61 (6128, 32 entries) -- different sets, not an
  offset. A 464 is recognised by &EF (FIRM JUMP) at &BD3D; the 6128 has &CF.
* **The 464's ROM walk** went 3, 2, 1 in MAME. The docs say it only looks
  at ROMs 0-7 (the 664/6128 at 0-15): give library ROMs numbers 1-6.
* **rasm labels are case-insensitive**: `s_quote` and `S_QUOTE` collide.
  A label in front of a macro that starts with `align` is not aligned.
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
