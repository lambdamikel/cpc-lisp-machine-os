# CPC Lisp -- example programs

Programs in CPC Lisp that are not in the ROMs. They are on the discs
(`discs/`): load them by name.

| file | what | on |
|---|---|---|
| `apfel.lsp` | **The Apfelmaennchen**, the Mandelbrot set: `(load "apfel")`, `(apfel)` -- or `(apfel 40)` for more rounds a point. Drawn coarse to fine (blocks of 16 units, 8, 4: the whole picture after the first pass), in fixnums times 64, the upper half mirrored. On a CPC in mode 2, its rounds compiled where there is a compiler (the ROMs: 11 minutes on a 464); on a TRS-80 Model 4 on the high-resolution board, interpreted | the CPC demo disc `cpclisp-demo.dsk` (on Mike's card: flash disc 3), the other CPC discs (`cpclisp-hwtest.dsk`, `cpclisp512.dsk`, `cpclisp6128.dsk`), the Model 4's (`APFEL/LSP`); on a Model I or III (in its blocks, compiled) type it in or copy it: their discs have no room |
