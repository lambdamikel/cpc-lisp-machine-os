# CPC Lisp under FutureOS (work in progress)

The goal (Mike, 2026-11-17): run CPC Lisp under FutureOS, TFM's operating
system for the CPC. FutureOS's ROMs sit in the LambdaSpeak 4's slots, or
any ROM board fast enough for its ROM switching. Lisp starts from the
desktop, from any FutureOS drive: the card's Vortex drive E, a DDI, the
M4. It uses Revaldinho's RAM card and needs neither the firmware nor BASIC.
TFM asked for this himself. FutureOS offers fast text output, fast file
access, a memory manager, and the interrupts and alternate registers free
for the program.

Nothing of FutureOS is in this repository. TFM's ROMs, discs and documents
are free for non-commercial use from futureos.de; `fos.asm` names the
entries this machine uses, with addresses from his public documentation.

## What FutureOS asks of a program

From TFM's documentation: API-ENG, API-A to D, the manual, and "How to
create an Application for FutureOS".

* **Programs.** A program is a binary with an AMSDOS header: `.64K` runs
  in main RAM, `.X16` in expansion RAM. The desktop's RUN icon (hot key
  X) loads the first tagged file and jumps to its exec address. With
  nothing tagged, RUN 3 jumps into RAM: you give an address and a
  configuration (&C0 is main RAM). The MAME tests start programs that way.
* **Main RAM.**

  | range | use |
  |---|---|
  | &0000-&9FFF | the program's |
  | &0000-&3FFF | also the desktop's buffer when it sorts a directory |
  | &8000-&8FFF | also a sector buffer when more than 16 KB loads at once |
  | &9000-&9FFF | never touched by the OS |
  | &A000-&AFFF | the file-tagging bytes |
  | &B000-&B7FF | a text buffer |
  | &B800-&BFFF | FutureOS's: its variables, the IM 2 table at &BD00 (I = &BD), the stack |

  Disc work overwrites &A000-&B7FF.
* **Interrupts** are off when a program starts, in IM 2; &0038 holds a
  RET and &0066 a RETN.
* **Expansion RAM** comes in 16 KB blocks shown at &4000 (&7FC4...). A
  program reserves blocks through the XRAM_C4..XRAM_FF variables; KZS2E
  finds a free one.
* **Calling FutureOS.** The OS is four ROMs, A to D. Programs reach them
  through the API page at &FF00, identical in all four: ROM_A..ROM_D jump
  to HL in that ROM; ROM_x2y calls IX in ROM y and comes back to ROM x.
  KLICK or TUR_D in ROM D return to the desktop.
* **Text** through FutureOS's routines (TERM_2 and friends, mode 2) needs
  a character set at &3800: the lower ROM's, switched in, or a copy.

## The plan

An overlay on `mach/cpc512`, as `mach/cpc6128` is. The same six images go
into block 3 of six expansion banks and run at &C000 in configuration
C1 + 8n. A resident part in main RAM does the work. Every firmware
routine is replaced:

| interface | under FutureOS |
|---|---|
| `CON_`, `VID_` (text) | our renderer (`fr.asm` draws into the screen already), with the font read from the lower ROM at &3800 |
| `KEY_` | our own keyboard scan through the PPI and PSG; the ESC test polls it |
| `FILE_` | FutureOS's own functions. To load: read the drive's directory (LESEDIR), find the name, tag the file, load it into expansion RAM (LADEN), and stream it from there. To save: write into expansion RAM, then FutureOS puts it on disc (BBTT, EGEN, SICHRE, SIDIR). The details are still to work out; TFM offered help. |
| `FP_` | the lower ROM's maths package, called at its own addresses with the lower ROM on. The 464 ROM's jumpblock table at &08AC gives them, so the ROM tells us where they are. Move, add, subtract, multiply, divide, compare and the conversions use no RAM. SQR, LOG, EXP, the powers and the trigonometry use &B8E4-&B8F7, which belongs to FutureOS, so those 20 bytes are saved and restored around them. A 6128's ROM is still to check. |
| `GFX_` | our own plot, line and fill into the screen |
| `SND_` | our own PSG writes; there are no firmware sound queues |
| `SYS_` | `(reset)` and `(quit)` go back to the desktop (TUR_D); time comes from a frame counter, or the clock |

The 512K version's resident part and fixed buffers sit at &A160-&B0FF,
which is FutureOS's. They move below &A000, to &9000-&9FFF.

The loader, `LISP.64K`, reserves six blocks: block 3 of six banks, the
blocks that configuration C1 can show at &C000. It loads `LISP0.IMG` to
`LISP5.IMG` into them, sets up the resident part and starts Lisp.

## Milestones

1. **Done (2026-11-17).** A FutureOS program assembled here runs in MAME.
   `hello.asm` prints a line and goes back to the desktop.
2. The core and part 0 run under FutureOS: text out, keys, the REPL. No
   files yet, no floats.
3. Files: `load`, `save` and `dir` through FutureOS. Then the loader
   reads the images itself.
4. Floats, graphics, sound and time. Then the test suite runs under
   FutureOS in MAME.
5. On Mike's 464: FutureOS from the card's slots, Lisp from the card's
   Vortex drive E.

## Testing in MAME

FutureOS's ROMs are renumbered to 1-4 for MAME's ROM box with
`tools/futureos/fosroms.py SRC OUT 1 2 3 4`. Its installer disc has
the ROMs; they stay in ~/claude/cpc/futureos. A test then types `|OS` at
BASIC's EDIT, puts the program in RAM, and starts it from the RUN menu:

    |OS
    !shot 700
    !poke 10 9000 hello.bin
    !press 63 30            X: RUN
    !press 57 60            3: RAM application
    !press 33 60            9 0 0 0, RETURN: the address
    !press 32 20
    !press 32 20
    !press 32 20
    !press 18 20
    !press 62 60            C 0, RETURN: the configuration
    !press 32 20
    !press 18 20
    !shot 100

Run it with:

    LISP_IN=test.txt LISP_OUT=out.txt LISP_SHOT=s.png LISP_FRAMES=2200 \
    LISP_EDIT=0xBD3A xvfb-run -a mame -video none -nothrottle cpc464 \
      -ramsize 576K -exp rom -rom1 FOS-A.ROM -rom2 FOS-B.ROM \
      -rom3 FOS-C.ROM -rom4 FOS-D.ROM -autoboot_script emu/repl.lua

For a disc, put MAME's DDI-1 in front of the ROM box: `-exp ddi1 -flop
D.dsk -exp:ddi1:exp rom ...`. On the desktop, SPACE A selects drive A
and D reads its directory.

## Open questions

* Will FutureOS leave block 3 of six banks free? It needs about 32 KB of
  expansion RAM for its directory buffers, and Revaldinho's configuration
  8 lends bank 3 to the base RAM.
* How should FutureOS's tag-based file functions be driven by name, for
  loading and for saving?
* The screen mode and inks under FutureOS, and what the desktop expects
  back.
