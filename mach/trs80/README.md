# CPC Lisp on the TRS-80 Model I with X-MEM/80

*Runs on a real Model I and Model III with X-MEM/80 (2026-11-12).* The same Lisp as on the CPC -- the six images are
built from the same sources -- on a TRS-80 Model I with Michael Wessel's
and Mark Pruden's [X-MEM/80](https://github.com/lambdamikel/x-mem-80)
512 KB paged memory, in its X-MEM mode (16 KB pages), under LDOS 5.3.

## Building and running

    MACH=trs80 tools/build.sh     # build/trs80: the images, LISP/CMD, the
                                  #   discs lisp-a.dsk and lisp-m3.dsk
    tools/trs80/play.sh           # trs80gp in a window: LDOS boots, LISP runs
    tools/trs80/run.sh file.lsp   # type a file at it in trs80gp, print the
                                  #   transcript

For the **Model I**, `lisp-a.dsk`: LDOS 5.3.1, single density, with
`LISP/CMD` and the seven images on it. For the **Model III**,
`lisp-m3.dsk`: LDOS 5.1.4, double density, the same files. At `LDOS
Ready`, `LISP` loads the seven pages and starts; without X-MEM/80 in its
X-MEM mode it says so and goes back to LDOS. `(quit)` goes back to LDOS.

The images are compressed to fit one single-density disc, 93 KB to 55
(`tools/trs80/lz.py`: an LZ77, optimally parsed; the loader decodes
them). Should they outgrow the disc, `mkdisk.py` puts the rest on a
`lisp-b.dsk` for drive 1 -- LDOS looks for a file in every drive.

`tools/trs80/ldos-m1.dsk` and `ldos-m3.dsk` are the starting discs:
LDOS system discs with nothing of the user's on them (from the MIDI/80
project's discs). The machine page tells a Model III by its ROM (an "I"
at &0125).

## How it is arranged

| | |
|---|---|
| &0000-&3FFF | ROM, keyboard, screen (64 x 16 at &3C00) |
| &4000-&51FF | LDOS |
| &5200-&53FF | the resident part: SYS_BANK and the jumpblock (`resident.asm`) |
| &5400-&BAFF | the Lisp's RAM: tables, symbols, cells, strings, the stack (`memmap.asm`); &8000-&BFFF is X-MEM page 1, never moved |
| &BB00-&BFFF | the fixed variables and buffers |
| &C000-&FFFF | one code page at a time: the core (page 2), library parts 0-3 (3-6), the VM (7), the machine page (8); pages 9-31 the RAM disc |

The six images run unchanged in the &C000 window -- they are assembled
for it on the CPC too. A switch is one `OUT (66)`. The machine's routines
-- the console, keys, graphics, files, floats -- live in their own page
(`page.asm`); a call to an interface name lands in the resident
jumpblock, which maps that page in, calls the routine, and maps the
caller's page back (`resident.asm`, `jumps.asm`; `tools/trs80/mkjumps.py`
makes the jumpblock from one list). The loader (`loader.asm`, LISP/CMD)
reads the seven pages through LDOS, each into page 1 at &8000 first, and
decodes it into its own.

About 3150 cells are free at start, half a CPC's.

## The keys

| TRS-80 | CPC Lisp |
|---|---|
| BREAK | ESC: interrupts |
| <- | cursor left |
| SHIFT <- | DEL: the character to the left |
| -> | cursor right |
| SHIFT -> | TAB |
| up, down | the history |
| SHIFT up | the copy cursor up |
| CLEAR | CLR: the character under the cursor |
| SHIFT down, then a key | a character the keyboard has not got (below) |
| SHIFT down twice | the copy cursor down |
| SHIFT down, then C | COPY: copies from the copy cursor; in the function editor, done |
| SHIFT down, then S | CTRL-S: in the function editor, done (BREAK leaves it unchanged) |
| SHIFT @ | output waits (LDOS's way) until another key |

A Model I or III has no `[ ] { } \ | ~ ^ _` or backquote keys -- its up
arrow *is* `[`, code &5B, and fetches the line before from the history
here. **SHIFT down-arrow, pressed and let go, then a key** makes them;
the key may be shifted or not:

| SHIFT down, then | gives | for |
|---|---|---|
| `-` or `=` | `~` | `format`'s directives: `"~A"` |
| `/` or `?` | `\` | characters: `#\a`; escapes in strings |
| `1` or `!` | `\|` | `\|odd names\|`, `#\| comments \|#` |
| `7` or `'` | `` ` `` | backquote |
| `8` or `(`, `9` or `)` | `[` `]` | `format`'s `~[ ~]` |
| `,` or `<`, `.` or `>` | `{` `}` | `format`'s `~{ ~}` |
| `@` | `^` | `format`'s `~^` |
| `0` | `_` | |
| `S` | CTRL-S | the function editor: done |
| `C` | COPY | the copy cursor's character; the function editor: done |

(Keys are read through the ROM's keyboard routine, as LDOS has it
without KI/DVR; with KI/DVR loaded this is untried.)

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
  discs, boxes; `flood-fill` (a whole screen in about 8 s). One colour:
  a pen is lit or not.
* **Files** through LDOS: `load`, `save`, `open`, `with-open-file`,
  `probe-file`, `delete-file`, `compile-file`; `dir` lists each drive's
  files (LDOS's DIR/SYS, read as a file). A name `B:FOO.LSP` is LDOS's
  `FOO/LSP:1`.
* **The RAM disc**, drive `M:`, as on a 6128: X-MEM/80's pages 9-31, 368
  KB -- `(save "m:work")`, `(load "m:work")`, `(dir "m:")`,
  `(delete-file "m:work")`, streams. 31 files, 367 KB for them. Its
  first KB is the directory; the files lie one after the other, and one
  deleted (or saved again) closes up the gap. The pages keep it through
  `(quit)` and a reset; at power-on (no directory there) it starts
  empty (`rdisc80.asm`). **Far arrays** are files there too
  (`make-far-array`, `far-ref`: `mach/trs80/far.asm` reaches the pages
  through RS_XFER), and `(load "name" :lazy t)` works from any drive or
  `M:`.
* **A test of the real machine** is on the disc: `(load "hwtest")`,
  `(hwtest)` -- eight checks, yes or NO: the cells, two files open at
  once, lazy loading from the drive and from `M:`, the RAM disc, far
  arrays over its pages, the compiler; `(hwtest-big)`, far arrays past
  the RAM disc's first 256 KB; and after `(quit)` and `LISP`,
  `(load "hwtest")`, `(hwtest2)`, that the RAM disc kept its files. It
  writes only to `M:` (the Model I's disc is nearly full).
* **X-MEM/80 must be in its 16 KB mode** (pages of 16 KB, the X-MEM/80
  setting of its jumper or switch) for all of the RAM disc: with 16 page
  numbers -- 32 KB (SuperMem) mode, as trs80gp has it -- pages 16-31
  are pages 0-15 again, so the RAM disc keeps to pages 9-15, 112 KB
  (`rd_pages` looks at the first use of `M:`; before it did, writing
  past them reset the machine into LDOS).
* `*features*` is `(:trs-80 :cpc-lisp)`; the demos look at it.
* The Model III: the same images and machine page (its ROM has the
  maths routines at the same places); it runs on Mike's, with X-MEM/80,
  Talker/80 and MIDI/80 (2026-11-12) -- trs80gp has X-MEM/80 only for
  the Model I.
* **Sound**: one voice, a square wave on the cassette port (trs80gp
  plays it): `sound`'s period, volume and duration, the note played
  there and then, within a few percent of its pitch. `envelope` and
  `tone-envelope` are taken and not heard. `(tune)` plays.
* **Speech** through Talker/80 (port 11): `say` speaks DECtalk's way, as
  LambdaSpeak does on the CPC (so `(sing)` sings); `speech-stop`,
  `speech-voice`, `speech-rate`, `speech-volume`. On a real Talker/80
  (a Model III's): each line ends with LF and CR -- the firmware keeps
  the CR, and DECtalk speaks a clause only once it ends; a control byte
  makes it wait until Talker/80 is done with it (it empties its text
  buffer then); DECtalk mode is set once each time Lisp starts.
  **On a Model I, reprogram Talker/80's U1 (its address decoder, a
  GAL22V10) with `Talker80-decoder-xmem.jed`** from the
  [Talker/80 repository](https://github.com/lambdamikel/Talker-80#the-model-1-address-decoder-and-x-mem80): the original answers ports 0-3, 8-11,
  64-67 and 72-75, the VS-100's, so every X-MEM/80 page switch (`out
  (65)`, `out (66)`) lands in its text buffer -- it spoke once, then only
  its LEDs flickered, on Mike's. The new one answers 8-11 in the native
  modes and leaves the VS-100 and TRS modes as they were; with it, `say`
  and `(sing)` work on a Model I with X-MEM/80 (2026-11-12, programmed on
  a T48). Port 8 is MIDI/80's, though, and without A0 and A1 the two
  cannot be told apart: MIDI bytes reach Talker/80 too. The Model III
  version decodes port 11 alone and needs nothing.
* **MIDI** through MIDI/80 (port 8, its MIDI OUT and its Waveblaster as
  its DIP switches say): `midi-note`, `midi-program`, `midi-control`,
  `midi-panic`, `midi-out`, and `(midi-tune)`, a minuet in two voices.
  Tried on Mike's Model I and Model III; in trs80gp, which has no
  MIDI/80, `-ee` copies the bytes to the transcript, as `<90><3C><64>`.
* `time` counts LDOS's ticks, in the CPC's 1/300 s. A Model I's are 25
  ms, a byte at &4040 running on through the seconds (theirs at &4041):
  the ticks between two calls are the byte's difference that is nearest
  40 times the seconds gone by, exact however long between them. A Model
  III's, 33 ms, count 30 down to 1 at &4216 within each second (&4217).
  A call takes 3.5 ms.
* **The text screen**, 64 by 16 in one colour: `cls`, `locate` and the
  printers as on the CPC; `mode` only clears; `ink`, `border`, `pen`,
  `paper` do nothing.
* `(quit)` -- here only -- goes back to LDOS, and so does `(reset)`.
* **Not here, CPC only**: `symbol` (the characters are the character
  generator's, a ROM), `window`, `tag`, `transparent`, `flash-speed`,
  `text-cursor`, `joystick`, `peek`, `poke`, `release`, `sound-check`,
  `sound-hold`, `sound-continue`, PlayCity (`playcity`, `pc-tone`,
  `pc-off`, the `(chords)` demo), and `(basic)` -- the LambdaSpeak
  card's. `midi-off` is there and does nothing.

## In trs80gp

`-m1 -mem xmem80` is a Model I with X-MEM/80. With `-ee` the machine
page copies everything the Lisp prints, each MIDI byte, and each line
typed, to the printer -- `-batch` writes that to `trs80-printer.txt`,
the transcript -- and `(quit)` ends the emulator. Typed input (`-i`)
arrives when a program waits in the ROM's key routine (&0049), which is
where `KEY_WAIT` waits.
