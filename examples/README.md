# CPC Lisp -- example programs

Programs in CPC Lisp that are not in the ROMs. They are on the discs
(`discs/`): load them by name.

| file | what | on |
|---|---|---|
| `apfel.lsp` | **The Apfelmaennchen**, the Mandelbrot set: `(load "apfel")`, `(apfel)` -- or `(apfel 40)` for more rounds a point. Drawn coarse to fine (blocks of 16 units, 8, 4: the whole picture after the first pass), in fixnums times 64, the upper half mirrored. On a CPC in mode 2, its rounds compiled where there is a compiler (the ROMs: 11 minutes on a 464); on a TRS-80 Model 4 on the high-resolution board, interpreted | the CPC demo disc `cpclisp-demo.dsk` (on Mike's card: flash disc 3), the other CPC discs (`cpclisp-hwtest.dsk`, `cpclisp512.dsk`, `cpclisp6128.dsk`), and the TRS-80's (`APFEL/LSP`; the Model I's without its comments, to fit) |

## The classics disc

Classic Lisp programs, text only, so they run on every machine: the CPC
ROMs and disc versions, under FutureOS, and the TRS-80 Model I, III and
4. They are on the classics discs: `cpclisp-classics.dsk` for a CPC and
`cpclisp-trs80-classics-model1/3/4.dsk` for the TRS-80s, the latter in
any drive but the system's (LDOS looks in every drive). `(load
"classics")` lists them. Load one at a time: on a TRS-80 a program and a
conversation with ELIZA take most of the cells; a fresh Lisp for each
is best there.

| file | what | start |
|---|---|---|
| `eliza.lsp` | **ELIZA**, Joseph Weizenbaum's DOCTOR (1966): a pattern matcher with `?X` for any words, answers given in turn, I said back as YOU. After Peter Norvig's version in *Paradigms of AI Programming* | `(eliza)`; BYE ends it |
| `deriv.lsp` | **Symbolic differentiation**: `(deriv '(* x (sin x)) 'x)` gives `(+ (* X (COS X)) (SIN X))`, simplified as it is built | `(deriv-demo)` |
| `animals.lsp` | **The guessing game that learns**: a tree of questions, grown when it guesses wrong, saved as `ZOO` and loaded again next time | `(animals)` |
| `meval.lsp` | **Lisp in Lisp**: McCarthy's eval and apply for a small Scheme, closures and all, as in SICP chapter 4 | `(meval-demo)`, `(meval-repl)` |
| `life.lsp` | **Conway's Game of Life**, a glider and a blinker on a board that wraps round | `(life 8)` |
| `classics.lsp` | the list above, in 40 columns | `(load "classics")` |

The Towers of Hanoi and n queens need no disc: `(hanoi 4)` and
`(queens 6)` are among the ROMs' own demos, which `(demo)` lists.

Checked in MAME on a 464 and a 6128 (`test/classic*.lsp`) and in
trs80gp on a Model I with X-MEM/80 and a Model 4 (2026-11-17). ELIZA on
a Model 4 leaves about 300 cells.
