# CPC Lisp 0.98 -- benchmarks, and some history

*A Lisp machine for the Amstrad CPC*

How fast is CPC Lisp, against the Lisps of its own time on the same kind
of machine, against the big machines of the 1980s, and against a Lisp of
today? Measured on 2026-11-17, at Mike's question: "if you compare CPC
Lisp with UOLisp for the TRS-80, which also had a compiler, who wins?"

## The benchmarks

The same three small programs everywhere, written in Common Lisp and in
each other Lisp's own dialect (`tools/bench/`):

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

## In a nutshell

Each Lisp's time divided by CPC Lisp's on the same machine: above 1,
CPC Lisp is faster; below 1, the other Lisp is. Interpreters are
compared with CPC Lisp's interpreter, compilers with its compiler.

| Lisp (year), machine | `fib` | `tak` | `deriv` |
|---|---|---|---|
| *interpreted* | | | |
| muLISP-80 (1980), CPC 6128 | 0.94 | **0.69** | 0.96 |
| muLISP-80 2.15 (1982), CPC 6128 | 0.97 | 0.70 | 0.94 |
| LinguaSoft/HiSoft Lisp (1986), CPC 6128 | 2.5 | 2.1 | 2.8 |
| UOLisp (1982), TRS-80 Model I | 11.8 | 10.4 | 11.0 |
| LISP/80 (1980), CPC 6128 | 18 | fails | 17 |
| XLisp 1.1 (1985), CPC 6128 | 65 | wrong answer | crashes |
| *compiled* | | | |
| UOLisp, `!*OPT`, TRS-80 Model I | **0.66** | 1.23 | 1.45 |
| UOLisp, `!*FAST`, TRS-80 Model I | **0.45** | **0.55** | crashes |

* **Only muLISP's interpreter is faster than CPC Lisp's**, by 3-6% on
  `fib` and `deriv` and 1.45 times on `tak`. The others are 2-65 times
  slower; two of them cannot finish `tak`.
* **None of the CPC's CP/M Lisps has a compiler.** CPC Lisp's compiled
  code is 1.5-4 times faster than muLISP's interpreter, and 4.6-12 times
  faster than HiSoft's.
* **Against UOLisp's native code on the TRS-80 it is a draw** at
  UOLisp's safe setting. UOLisp's `!*FAST` is about twice as fast, but
  it crashes on `deriv`, and UOLisp's 13-bit integers give the wrong
  `(fib 20)`.
* **SBCL on a 2019 PC** is 3,000-4,900 times faster than CPC Lisp
  interpreted, and 154,000-267,000 times faster compiled.

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

The CPC's Lisps of the 1980s ran under CP/M. Mike's 2018 thread on the
CPCWiki forum, "Lisp on the CPC", dug up the ones that work, and he put
two discs together from several CP/M sources. With two of CPC-Power's,
that makes five Lisps on four discs, all in [`vintage/`](../vintage/):

* **muLISP-80** (The Soft Warehouse, Honolulu, 1980; licensed by
  Microsoft), the Lisp of the muMATH computer algebra system. There are
  two versions: the 8080 version of 10/06/80 on Mike's disc, and 2.15
  (03/01/82), which HiSoft sold in 1987 as its "LISP Interpreter"
  (£39.95). CPC-Power's copy of that is damaged. Its library does not
  load, even started as `lisp baselisp`, so there is no `DEFUN`,
  `MAPCAR` or `PROG`. Its multiplication is broken: `(TIMES 12 12)` is
  180. The benchmarks do not multiply, and its `fib` and `tak` answers
  are right.
* **LinguaSoft Lisp 1.57B** (Ofer and Shelly Ben-Ami, 1986-88). This is
  HiSoft's real Lisp, for the 6128 and the PCW, and comes with HLE, a
  full-screen editor.
* **LISP/80 1.1** (T. W. Yonkman, The Software Toolworks, 1980).
* **XLisp 1.1** (David Betz, 1985), written in C. AutoCAD's AutoLISP
  grew out of an early XLisp.

None of them has a compiler. All five ran on MAME's 6128:

| CPC 6128 (Z80, 4 MHz), MAME | `(fib 20)` | `(tak 18 12 6)` | `deriv` × 100 |
|---|---|---|---|
| muLISP-80 (1980) | **55.2 s** | **183 s** | 7.6 s |
| muLISP-80 2.15 (1982) | 56.8 s | 186 s | **7.4 s** |
| CPC Lisp, interpreted | 58.6 s | 266 s | 7.9 s |
| LinguaSoft/HiSoft Lisp 1.57B (1986) | 146 s | 554 s | 22.1 s |
| LISP/80 1.1 (1980) | 1,041 s | fails | 132 s |
| XLisp 1.1 (1985) | 3,780 s | wrong: 12 | crashes |
| CPC Lisp, compiled | 16.9 s | 46 s | 4.8 s |

* **muLISP-80 and CPC Lisp's interpreter are level.** muLISP is 3-7%
  faster on `fib` and `deriv`, and 1.45 times on `tak`. The 1980 8080
  version is as fast as 2.15. It was the fast microcomputer Lisp of its
  day, built for computer algebra.
* **HiSoft's Lisp, the one sold for the 6128, is 2-3 times slower**
  than either.
* **LISP/80 and XLisp are another world**: 19 and 68 times slower than
  muLISP on `fib`. XLisp, written in C, takes a cell for every integer
  it computes.
* **Neither finishes `tak`.** LISP/80 seems to lose stack as it goes:
  `tak` stops with ERROR 18 after 54 s with the default stack, and
  after 15 minutes with a 20 KB one (`LISP_80 S=20000`). A `PROG` loop
  of `deriv` stops with ERROR 13 after some 36 rounds, so the table's
  `deriv` loops by recursion. XLisp corrupts its heap on a long run:
  `(tak 18 12 6)` answered 12 after 50 minutes, though `(tak 12 8 4)`
  and smaller come out right. Its `deriv` stopped after 222 s with
  "bad node type (172) found during left scan", from its garbage
  collector, and fell back to CP/M's `A>`.
* **Only muLISP counts past 16 bits**: its `(TIMES 300 300)` is 90000.
  LinguaSoft, LISP/80 and XLisp wrap: 200 times 200 is -25536.
  LinguaSoft's `*` at least reports an overflow.
* **With its compiler CPC Lisp is 3.3, 4 and 1.5 times faster than
  muLISP.**

## Defining a function, in each dialect

Each of these Lisps starts at a bare prompt, and for most of them it is
not obvious how to make a function of your own. The manuals, where they
survive, are scans (vintage/README.md says where they are). Here is each one's way, as it answered in the emulator: a
function defined, called, and the way back out. The discs boot CP/M Plus
with `|CPM`.

**CPC Lisp** (and SBCL: this is Common Lisp)

    LISP> (defun square (n) (* n n))
    SQUARE
    LISP> (square 12)
    144
    LISP> (compile 'square)
    SQUARE

**muLISP-80**: `MULISP` on vintage/cpc/mulisp-lisp80.dsk (`LISP` on
the 2.15 disc). A function is a `LAMBDA` put on its name with `PUTD`:

    $ (PUTD (QUOTE SQUARE) (QUOTE (LAMBDA (N) (TIMES N N))))
    (LAMBDA (N) (TIMES N N))
    $ (SQUARE 12)
    144
    $ (PUTD (QUOTE FACT) (QUOTE (LAMBDA (N) ((ZEROP N) 1)
      (TIMES N (FACT (DIFFERENCE N 1))))))
    (LAMBDA (N) ((ZEROP N) 1) (TIMES N (FACT (DIFFERENCE N 1))))
    $ (FACT 7)
    5040
    $ (SYSTEM)
    A>

* A function's body is an implicit `COND`. An element whose head is a
  list is a test: if it holds, its other elements are evaluated and the
  function returns the last one, as `((ZEROP N) 1)` above.
* There is no `'`: `(CAR '(A B))` is `'`. Write `QUOTE`.
* A call of an undefined function comes back as it was typed:
  `(ADD1 5)` answers `(ADD1 5)`.
* `(RDS (QUOTE UTILITY) (QUOTE LIB))` loads the 1980 version's library.
  Then there are `DEFUN`, `(DEFUN SQUARE (LAMBDA (N) (TIMES N N)))`, and
  `MAPCAR`, `ADD1`, `APPEND`...

**LinguaSoft/HiSoft Lisp**: `LISP6128` on vintage/cpc/hisoft-lisp.dsk.
The prompt is `§`:

    § (DEFUN SQUARE (N) (TIMES N N))
    Value is...
    SQUARE
    § (SQUARE 12)
    Value is...
    144
    § (EXIT)
    A>

* `EQ` is false for numbers: `(EQ 300 300)` is NIL. Write `EQUAL`, or
  `(LESSP N 1)` for `ZEROP`, which is not there either.
* `MAPCAR` takes the list first: `(MAPCAR '((1) (2)) 'CAR)` is `(1 2)`.
* `'-` right before a `)` hangs the reader: write `'- )`.

**LISP/80**: `LISP_80` on vintage/cpc/mulisp-lisp80.dsk (`LISP_80
S=20000` for a bigger stack). The number in the prompt counts the open
parentheses, and an answer follows a `>`:

    0>(DEFPROP SQUARE (LAMBDA (N) (TIMES N N)) EXPR)
    >(LAMBDA(N)(TIMES N N))
    0>(SQUARE 12)
    >144

CTRL-C goes back to `A>`.

* `DEFPROP` puts the `LAMBDA` on the name's property list as its EXPR.
  The manual's `DEFINE ((SQUARE (N) ...))` makes a broken definition in
  version 1.1, and ERROR 1 when it is called.
* There is no `'`: write `QUOTE`. There is no `SUB1` or `ZEROP`.
* `MAPCAR` takes the function first.

**XLisp 1.1**: vintage/cpc/xlisp11.dsk starts it by itself:

    > (defun square (n) (* n n))
    square
    > (square 12)
    144
    > (exit)
    A>

* Its core has no `if`, `not`, `mapcar` or `caddr`. Write `cond`,
  `null`, recursion and `car`/`cdr`.

**UOLisp** (TRS-80 Model I): `LISP48` at `TRSDOS READY`, with the
prompt `*`. Standard LISP defines with `DE`, `(DE FIB (N) ...)`. After
`(FLOAD "COMP ")` (the space is needed) and `(SETQ !*COMP T)`, `DE`
compiles to Z80 code. There, add with `PLUS2`: `PLUS` is an FEXPR, which
cannot see a compiled function's variables.

The benchmark's `fib`, in each:

    ; CPC Lisp, SBCL
    (defun fib (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
    ; UOLisp
    (DE FIB (N) (COND ((LESSP N 2) N) (T (PLUS2 (FIB (SUB1 N)) (FIB (DIFFERENCE N 2))))))
    ; muLISP-80
    (PUTD (QUOTE FIB) (QUOTE (LAMBDA (N) (COND ((LESSP N 2) N)
      (T (PLUS (FIB (DIFFERENCE N 1)) (FIB (DIFFERENCE N 2))))))))
    ; LinguaSoft/HiSoft Lisp
    (DEFUN FIB (N) (COND ((LESSP N 2) N) (T (PLUS (FIB (DIFFERENCE N 1)) (FIB (DIFFERENCE N 2))))))
    ; LISP/80
    (DEFPROP FIB (LAMBDA (N) (COND ((LESSP N 2) N)
      (T (PLUS (FIB (DIFFERENCE N 1)) (FIB (DIFFERENCE N 2)))))) EXPR)
    ; XLisp 1.1
    (defun fib (n) (cond ((< n 2) n) (t (+ (fib (- n 1)) (fib (- n 2))))))

`tak` and `deriv` in each are in `tools/bench/`: `cpc.lsp`,
`uolisp-*.txt`, `mulisp.txt`, `linguasoft.txt`, `lisp80.txt`,
`xlisp.txt`. `deriv` maps with `MAPCAR` where the Lisp has it, and with
two small recursive functions where it has not (muLISP, XLisp).

## The utter horrors of the 1980s: alien toy Lisp dialects on microcomputers

Getting each of them to define and run three small functions took from
a few minutes to an afternoon. A blunt verdict, from that:

**muLISP-80 is the only one you could have worked in.** It is fast, as
fast as CPC Lisp's interpreter, from a 9.5 KB program, and its
integers do not wrap. But it fights you on every line. There is no `'`,
so every constant is `(QUOTE ...)`, and a function is `(PUTD (QUOTE F)
(QUOTE (LAMBDA ...)))` until you load the library that brings `DEFUN`.
Worst of all, a misspelt function is no error: `(ADD1 5)` without the
library answers `(ADD1 5)`, and a typo deep in a program quietly hands
its own call back up as data. The copy HiSoft sold in 1987 cannot
multiply.

**LinguaSoft/HiSoft Lisp has the friendliest face on a slow engine.**
It reads like a real Lisp, with `DEFUN`, `'`, and errors in English that
name the culprit ("Expression in function position not a function --
Faulty argument:- ((1) (2))"). It comes with a full-screen editor. Then
it trips you:

* `EQ` is false for two equal numbers, so the textbook `(EQ N 0)`
  recurses until "Variable binding space exhausted".
* `'-` before a `)` hangs the reader without a word.
* `TIMES` wraps at 16 bits in silence, while `*` reports the overflow.
* It drops keys typed while it reads a line.

It is 2-3 times slower than muLISP, which was six years older, and no
manual for it has turned up.

**LISP/80 is a teaching toy that cannot finish its homework.** Its
manual is a friendly tutorial, but the tutorial's way to define a
function, `DEFINE`, makes a broken definition in version 1.1. The way
that works, `DEFPROP`, takes guessing. Errors are bare numbers, "ERROR
14", with no table to look them up in. It is 19 times slower than
muLISP, and it cannot run `(tak 18 12 6)` or a `PROG` loop of 100
rounds: it loses stack as it goes, and stops with ERROR 18 or ERROR 13.

**XLisp 1.1 is the future, at an hour per `fib`.** It is the only one
that looks modern: lower case, `defun`, `'`, `(exit)`. Its descendants,
XLISP-PLUS and AutoCAD's AutoLISP, lived on. On a 4 MHz Z80 it is
unusable: `(fib 20)` takes an hour, 68 times muLISP. It also cannot be
trusted with a long run. After 50 minutes of `(tak 18 12 6)` it answers
12 instead of 7, and `deriv` ends in its garbage collector's "bad node
type (172) found during left scan" and a drop back to CP/M. Its core
has no `if`, `not`, `mapcar` or `caddr` ("error: null function"), and
its integers wrap at 16 bits.

**UOLisp has a real compiler and arithmetic you cannot trust.** Native
Z80 code from a 48 KB TRS-80 in 1982 was ahead of its time. But its
13-bit integers wrap in silence, and `(fib 20)` answers -1427 with a
straight face. Its interpreter is 10-12 times slower than CPC Lisp's.
`(FLOAD "COMP")` fails without a trailing space, compiled code cannot
use `PLUS` ("NOT GLOBAL N"), and its fastest setting took the machine
back to DOS.

**What they share.** They give text only: no graphics or sound. They
offer little help when something goes wrong, and two have no `'`.
Four of them wrap their integers, mostly without a word. For a CPC
owner in 1987 it was muLISP, if you could find a copy that worked, or
HiSoft's, if you had patience.

**And CPC Lisp.** The same pitfalls, typed into the ROM version on a
464:

    LISP> (defun square (n) (* n n))
    SQUARE
    LISP> (add1 5)
    Error: undefined function ADD1
    LISP> (eq 300 300)
    T
    LISP> (* 300 300)
    90000.0
    LISP> (list '- '* '/)
    (- * /)
    LISP> (mapcar #'square '(1 2 3))
    (1 4 9)
    LISP> (car 5)
    Error: not a list: 5
    LISP> (ignore-errors (car 5))
    NIL
    "not a list: 5"

It is Common Lisp as a modern programmer expects it, so the tutorial
above is one line long. It comes on when the machine is switched on,
with no CP/M disc to boot. Its line editor shows the `(` that a typed
`)` closes, indents continuation lines and remembers earlier ones. `(ed
'fact)` puts a definition on a full screen to edit. Errors are messages
that name the culprit, and they can be caught. An integer past 15 bits
goes on as a float instead of wrapping. It has closures, `loop`,
`format`, structures, files, graphics and sound, and a compiler one
call away.

Its own weak spots:

* **It needs more hardware.** The ROM version takes six ROM slots: a
  ROM board, or Mike's LambdaSpeak card. The disc versions need a 6128
  or a 512 KB expansion.
* **It has no exact big integers.** Past 16383 come floats with about
  nine digits: `(fact 10)` is 3628800.0, and `(fact 20)` can only be
  approximate.
* **Memory is tight.** 6527 cells are free on a 464. String space is
  the tight resource on the disc versions.
* **It is a subset of Common Lisp**, with no packages, no CLOS and one
  dimension of array.
* **Its interpreter is no faster than muLISP's.**

**In fairness**, the others lived in 10-40 KB of a CP/M machine's
memory, with nothing to learn from but the minicomputer Lisps of the
1970s. CPC Lisp takes 96 KB of ROM, and was written with forty years of
hindsight and Common Lisp to copy. The comfort is what those 96 KB buy.

**Where Lisp really lived** was not on 8-bit micros. In the 1970s it
lived on timeshared PDP-10s: MacLisp at MIT, which ran Macsyma, and InterLisp at
BBN and Xerox PARC. In the 1980s it lived on VAXes, with Berkeley's
Franz Lisp, and for those who could pay about $100,000 a seat, on Lisp
machines from Symbolics, LMI, TI and Xerox. Gabriel's table below shows
the VAX keeping up in speed: Franz Lisp's TAK, 1.09 s, beats the
Dandelion and the CADR. What the Lisp machines sold was the environment:
editor, debugger, inspector and windows, all in one Lisp. On an 8-bit
micro, only muLISP was serious: it ran muMATH in 64 KB, and from 1988
Derive on PCs. Comfortable Lisp reached ordinary desks with the 68000
and 386 machines of 1985-88: Suns with Lucid and Allegro Common Lisp,
Macs with Coral, PCs with Golden Common Lisp. They ended the Lisp
machines.

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
| **CPC 6128, HiSoft Lisp (1986), interpreted** | **554 s** | **1,105 s** |
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
  (CONOUT) from the jump table that &0001 points into; LinguaSoft writes
  through the firmware, so for it the log taps TXT OUTPUT (&BB5A,
  `CPM_TXT`). muLISP, LinguaSoft and XLisp read the keys only once one is
  waiting, so the next line goes in when the prompt comes back
  (`CPM_PROMPT`). LinguaSoft and LISP/80 lose keys typed while they read
  a line, so their definitions go in a line at a time, at their
  continuation prompts. `tools/bench/cpmtime.py` gives the frames from a
  form's RETURN (its echo, or with `--typed` the moment its last key went
  up) to the first character of its result (`--skip` passes LISP/80's
  `>` and LinguaSoft's "Value is...", printed before the evaluation), 50
  a second.
* **SBCL:** `tools/bench/sbcl.lisp`, each run repeated 3-5,000 times. The
  same source, no declarations, Mike's SBCL 2.2.9.
* **Gabriel's numbers:** his Raw Time tables for TAK (pp. 86-87) and
  DERIV (pp. 173-174), from dreamsongs.com/Files/Timrep.pdf.

