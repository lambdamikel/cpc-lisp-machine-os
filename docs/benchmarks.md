# CPC Lisp 0.98 -- benchmarks, and some history

*A Lisp machine for the Amstrad CPC*

How fast is CPC Lisp, against a Lisp of its own time on the same kind of
machine, against the big machines of the 1980s, and against a Lisp of
today? Measured on 2026-11-17, at Mike's question: "if you compare CPC
Lisp with UOLisp for the TRS-80, which also had a compiler, who wins?"

## The benchmarks

The same three small programs everywhere, written once in Common Lisp
and once in UOLisp's Standard LISP (`tools/bench/`):

* **`(fib 20)`**: the doubly recursive Fibonacci, 21,891 calls. Small
  integers and function calls, nothing else.
* **`(tak 18 12 6)`**: Ikuo Takeuchi's function, the first of Richard
  Gabriel's benchmarks (*Performance and Evaluation of Lisp Systems*, MIT
  Press, 1985). It makes 63,609 calls and does little else.
* **`deriv` × 100**: Gabriel's symbolic derivative of `(+ (* 3 x x) (* a
  x x) (* b x) 5)`, a hundred times. It builds lists, so it measures
  `cons`, `mapcar` and the garbage collector. Gabriel ran it 5,000 times,
  so multiply by 50 to compare with his tables.

Each runs interpreted, then compiled.

## Who wins on the TRS-80

The machine is a TRS-80 Model I (1977; a Z80 at 1.77 MHz), emulated by
trs80gp. **UOLisp** is Jed Marti's UO-LISP V1.5b of June 3, 1982,
sold by Northwest Computer Algorithms. It is a Standard LISP, the dialect
of the REDUCE computer algebra system, with an optimizing compiler to
native Z80 code. It runs on a 48 KB Model I under TRSDOS 2.3. Mike
imaged its disc, and the Computer History Museum's Software Preservation
Group keeps the image. **CPC Lisp** is the same Lisp as
on the CPC, under LDOS. It needs Mike's X-MEM/80, since its six 16 KB
images live in the card's pages. Its compiler makes bytecode for a VM
written in Z80 assembly.

| Model I, 1.77 MHz | `(fib 20)` | `(tak 18 12 6)` | `deriv` × 100 |
|---|---|---|---|
| CPC Lisp, interpreted | **121 s** | **578 s** | **17.5 s** |
| UOLisp, interpreted | 1,433 s | 6,007 s | 193 s |
| CPC Lisp, compiled (bytecode) | 32.5 s | **87 s** | **9.2 s** |
| UOLisp, compiled (native, `!*OPT`) | **21.3 s** | 107 s | 13.3 s |
| UOLisp, compiled, `!*OPT` `!*FLINK` | 21.3 s | 107 s | 13.3 s |
| UOLisp, compiled, `!*OPT` `!*FLINK` `!*FAST` | 14.6 s | 48 s | crashes to DOS |

* **Interpreted, CPC Lisp wins by 10-12 times** on all three.
* **Compiled, at UOLisp's safe settings, it is a draw.** UOLisp's
  native code wins `fib` by 1.5 times. CPC Lisp's bytecode wins `tak`
  by 1.2 times and `deriv` by 1.45 times.
* **UOLisp's `!*FAST` level** wins `fib` by 2.2 times and `tak` by 1.8
  times, but it took `deriv` down with it, back to `DOS READY`.
* **UOLisp's `(fib 20)` is -1427, not 6765.** Its integers are 13 bits
  (-4096 to 4095) and wrap silently. CPC Lisp's are 15 bits; past them
  it goes on in floats.
* UOLisp needs nothing but the 48 KB Model I. CPC Lisp needs the
  X-MEM/80, and in return gets its closures, `format`, `loop`,
  structures, editors and graphics.

## The same Lisp on a CPC, and SBCL

| | `(fib 20)` | `(tak 18 12 6)` | `deriv` × 100 |
|---|---|---|---|
| CPC Lisp on a CPC 464 (1984; Z80, 4 MHz), interpreted | 58 s | 265 s | 7.9 s |
| CPC Lisp on a CPC 464, compiled | 16.9 s | 46 s | 4.8 s |
| SBCL 2.2.9, PC (2019, Core i3-9100, 3.6 GHz), interpreted (`sb-eval`) | 19 ms | 54 ms | 1.8 ms |
| SBCL 2.2.9, PC, compiled | 0.11 ms | 0.26 ms | 0.018 ms |

* The CPC runs the same Lisp about twice as fast as the Model I. Its
  Z80 runs at 4 MHz, about 3.3 MHz once the video's wait states are
  counted.
* SBCL is CMU Common Lisp's descendant (Carnegie Mellon, the 1980s),
  forked in 1999. Compiled, it is 150,000-270,000 times faster than
  compiled CPC Lisp on a 464. Even its interpreter beats the 464's
  compiled code by a factor of 1,000-3,000.

## The CPC's own Lisps of the day

The CPC's Lisps of the 1980s ran under CP/M. Mike's thread on the
CPCWiki forum, "Lisp on the CPC" (2018), dug up three that work:
LinguaSoft/HiSoft Lisp (which needs a 6128), muLISP-80 and Lisp-80. The
disc sold as HiSoft's "LISP Interpreter" (1987, £39.95; CPC-Power's copy)
boots CP/M Plus on a 6128. Its LISP.COM calls itself

    muLISP-80 2.15 (03/01/82)
    Standard CP/M Version
    Copyright (C) 1981 The SOFT WAREHOUSE
    Licensed by MICROSOFT, Inc.

That is the Soft Warehouse's muLISP, the Lisp of the muMATH computer
algebra system, which Microsoft sold. As the thread found, this copy is
not HiSoft Lisp proper, and it is cut down: its library does not load,
so there is no `DEFUN`, `MAPCAR`, `PROG` or `ADD1`. Its benchmarks are
written with `PUTD`, `DIFFERENCE` and recursion
(`tools/bench/mulisp.txt`), and `deriv` maps with two small recursive
functions where the others call `mapcar`. It has no compiler.

| CPC 6128 (Z80, 4 MHz), MAME | `(fib 20)` | `(tak 18 12 6)` | `deriv` × 100 |
|---|---|---|---|
| muLISP-80 2.15 (1982), interpreted | **56.8 s** | **186 s** | **7.4 s** |
| CPC Lisp, interpreted | 58.6 s | 266 s | 7.9 s |
| CPC Lisp, compiled | 16.9 s | 46 s | 4.8 s |

* **The two interpreters are level.** muLISP-80 is 3% faster on
  `fib`, 1.4 times on `tak` and 6% on `deriv`. It was the fast
  microcomputer Lisp of its day, built for a computer algebra system.
* **With its compiler CPC Lisp is 3.4, 4 and 1.5 times faster.**
* HiSoft Lisp proper and Lisp-80 are still to time: their discs are
  attached to the thread, behind CPCWiki's browser check.

## In the company of 1985

Gabriel's book timed TAK and DERIV on the Lisps and machines of the
early 1980s: Lisp machines, minicomputers, a Cray. A selection, next to
ours. DERIV here is all 5,000 derivatives: ours times 50, Gabriel's CPU
time plus garbage collection where he gives both (the 3600's, CPU
only).

| machine, Lisp | TAK | DERIV |
|---|---|---|
| Cray-1, PSL | 0.04 s | 2.5 s |
| Symbolics 3600 with IFU, ZetaLisp | 0.43 s | 3.8 s |
| Xerox Dorado, InterLisp | 0.52 s | 22.5 s |
| VAX 11/780, Common Lisp | 1.83 s | 40 s |
| VAX 11/780, Franz Lisp, fastest settings | 1.09 s | 25 s |
| Xerox Dandelion, InterLisp | 1.67 s | 76 s |
| MIT CADR, ZetaLisp | 3.1 s | -- |
| VAX 11/730, Common Lisp | 10.55 s | 180 s |
| VAX 11/750, Franz Lisp, generic arithmetic, slow calls | 47.6 s | -- |
| **CPC 464, CPC Lisp, compiled** | **46 s** | **240 s** |
| **TRS-80 Model I, UOLisp, compiled, `!*FAST`** | **48 s** | -- |
| **TRS-80 Model I, UOLisp, compiled** | **107 s** | **665 s** |
| **TRS-80 Model I, CPC Lisp, compiled** | **87 s** | **460 s** |
| **CPC 464, CPC Lisp, interpreted** | **265 s** | **395 s** |
| **CPC 6128, muLISP-80 (1982), interpreted** | **186 s** | **371 s** |
| PC 2019, SBCL, compiled | 0.00026 s | 0.0009 s |

* **A 4 MHz home computer of 1984 with CPC Lisp's compiler runs TAK as
  fast as a VAX 11/750 did** in the slowest row of Gabriel's table:
  Franz Lisp with generic arithmetic and slow function calls. UOLisp's
  `!*FAST` code on a 1.77 MHz Model I does the same.
* The Lisp machines and the VAX 11/780 were 25-100 times faster. A
  Symbolics 3600 cost about $100,000; a CPC 464, £199 with its monitor.
* SBCL on an ordinary PC does TAK about 150 times faster than the
  Cray-1 did.

## How it was measured

* **The CPC 464:** MAME, the ROM version (`tools/run.sh -t`, which counts
  frames per line, 50 a second): `tools/bench/cpc.lsp`.
* **The TRS-80 Model I:** trs80gp, headless, through
  `tools/bench/bench80.py`. Each run is a fresh boot that types the
  definitions (`trs80-int.lsp`, `trs80-comp.lsp`, `uolisp-*.txt`), then
  the timed form. The screen is dumped every 25-400 frames, and the first
  dump that shows the result gives the time. trs80gp's Model I runs
  about 60 frames a second; CPC Lisp's own clock gave 62.8 for the same
  run, so allow ±5%. Both Lisps are measured in the same frames, so the
  ratios between them are exact.
* **UOLisp's dialect:**
  * Its compiled code cannot pass local variables to an FEXPR, so `fib`
    adds with the binary `PLUS2`, not `PLUS`.
  * `MAPCAR` takes the list first, and `DVRUN` loops with `PROG`.
  * It loads the compiler as `(FLOAD "COMP ")`: the name wants its
    trailing space.
* **CP/M on the CPC:** MAME's 6128 boots CP/M Plus from the disc (`|CPM`),
  and `tools/bench/cpm.lua` types into the program and logs every
  character it prints, with its frame. It finds the BIOS's console output
  (CONOUT) from the jump table that &0001 points into. muLISP calls the
  console input only once a key is waiting, so the next line goes in when
  its prompt, `$ `, comes back. `tools/bench/cpmtime.py` gives the frames
  from a form's RETURN to the first character of its result (50 a
  second).
* **SBCL:** `tools/bench/sbcl.lisp`, each run repeated 3-5,000 times. The
  same source, no declarations, Mike's SBCL 2.2.9.
* **Gabriel's numbers:** his Raw Time tables for TAK (pp. 86-87) and
  DERIV (pp. 173-174), from dreamsongs.com/Files/Timrep.pdf.

Still to come: the CPC's own Lisps of the day, which ran under CP/M --
HiSoft Lisp on the 6128 (said in that thread to come from muLISP-80,
which Microsoft sold as Microsoft LISP) and others. They need their discs from Mike's thread
on the CPCWiki forum.
