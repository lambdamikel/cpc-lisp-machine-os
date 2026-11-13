# CPC Lisp 0.96 -- the internals in detail

*A Lisp machine for the Amstrad CPC*

[The design](design.md) is the overview: the ROMs, the memory, the
objects, the evaluator, the bytecode machine and the compiler. This
document goes deeper into six things:

* [names with a percent sign](#names-with-a-percent-sign), like `%AGAIN`
  and `%KOCH-SIDE` in the demos;
* [lexical closures](#lexical-closures), in the interpreter and in the
  compiler;
* [tail calls](#tail-calls);
* [making it fast](#making-it-fast): what was done to the interpreter,
  the compiler and the machine;
* [the bootstrap](#the-bootstrap): how the compiler was compiled by
  itself before there was a compiler;
* [what was hard, and what cannot be done](#what-was-hard-and-what-cannot-be-done):
  Common Lisp on a Z80 with 64 KB, looked back on.

The listings are real: typed at the 0.9 ROMs in MAME, on a 464.

## Names with a percent sign

`(ed 'koch)` shows the Koch snowflake demo:

    (DEFUN KOCH (&OPTIONAL (LEVEL 3))
      (%DARK 1)
      (PEN-UP) (SET-POSITION 158 293) (SET-HEADING 90) (PEN-DOWN)
      (GRAPHICS-PEN 1)
      (DOTIMES (I 3)
        (%KOCH-SIDE 324 LEVEL)
        (RIGHT 120)
        (GRAPHICS-PEN (+ I 2)))
      (%AGAIN))

`%DARK`, `%KOCH-SIDE` and `%AGAIN` are ordinary functions, written in
Lisp next to `koch` in the demo ROM's text (`lib/demo.lsp`):

    ;; wait for a key, then the screen back
    (defun %again () (wait-key) (%restore))

    ;; a side is four sides a third as long, the middle two a bump
    (defun %koch-side (len level)
      (if (= level 0)
          (forward len)
          (let ((l (floor len 3)) (n (1- level)))
            (%koch-side l n) (left 60)
            (%koch-side l n) (right 120)
            (%koch-side l n) (left 60)
            (%koch-side l n))))

Like every function of the library written in Lisp, each is read from ROM
the first time it is called, and `(ed '%koch-side)` shows it.

**The `%` is a convention, nothing more.** To the reader it is a letter
like any other. But CPC Lisp has no packages: there is one set of names
for the system and for you. A name starting with `%` says *this is the
system's own, a helper, not part of the language*. Your own `again` or
`restore` cannot collide with the library's, and the functions in the
reference stay the ones to rely on: a `%` function may change or go away
in the next version. Common Lisp implementations name their internals
the same way. `save` never writes them out, because library text defined
them (see *Files* in the design).

The `%` names in 0.9:

| where | names | what they are |
|---|---|---|
| the core: special forms | `%LOOP` `%EXPANDED` `%CATCH-ERRORS` | a `loop` without keywords becomes `%LOOP`; a macro call is rewritten to `(%EXPANDED ...)` the first time it runs (below); `ignore-errors` and `handler-case` are built on `%CATCH-ERRORS` |
| the core: a function | `%SIGNAL` | signals an error with a message; `error` is built on it |
| library natives | `%MAKE-STRUCT` `%STRUCT-REF` `%STRUCT-SET` `%STRUCT-TYPE` `%STRUCT-IS` `%PUTHASH` `%EQHASH` `%OPEN` `%CLOSE` `%SUBSEQ` `%CONCATENATE` `%POW` `%PI` `%LOOP-EXPAND` `%LOAD` `%FILE-POS` `%FILE-SKIP` `%LIBDEF` `%FAR-OPEN` `%FAR-FILL` `%FAR-SET` | the machinery under `defstruct`, the hash tables, `open`, the sequence functions, `expt`, `pi`, the extended `loop`, `load` and `file-position`, lazy loading, the far arrays |
| the VM ROM's natives | `%MAKE-CODE` `%CODE` `%CODE-BYTES` `%CODE-CONSTS` `%FN-INFO` `%FN-DATA` `%SYMBOL-FLAGS` `%OP-NAME` `%OP-KIND` `%VM-RELEASE` | what the compiler and `disassemble` use; every `.FAS` file calls `%CODE` |
| library Lisp | `%SEQ` `%LIKE` `%CONDITION` `%SYM` `%TYPEP-LIST` `%IN-RANGE` (`lisp.lsp`); `%CATCH` `%THROW` `%UNWIND-PROTECT` `%CATCH-ERRORS-FN` `%SET-AREF` `%SET-CHAR` `%SET-NTH` `%SET-GET` `%SET-FN` `%SET-PLIST` (`lisp2.lsp`); `%HASH-PAIRS` (`loop.lsp`); `%LOAD-LAZY` `%LAZY-STUB` `%LAZY-FN` `%LAZY-CALL` (`lazy.lsp`); `%FAR-NAME` (`farray.lsp`) | helpers; the `lisp2.lsp` ones are what compiled code calls for `catch`, `throw`, `unwind-protect` and some `setf` places |
| a property | `%LAZY` | a function loaded with `:lazy t`: (stub file . position) |
| the demos | `%RESTORE` `%AGAIN` `%DARK` `%KOCH-SIDE` `%BRANCH` | the demos' helpers |
| `loop` | `%0` `%1`... | the extended `loop`'s own variables |

To see how a `%` function written in Lisp works, `ed` it. A native's
source is the `;@` line naming it, in `lib/*.asm`.

## Lexical closures

A closure is a function together with the variables it can see where it
was made. CPC Lisp has them twice over: the interpreter keeps the whole
environment, and the compiler keeps just what is used.

### In the interpreter

**The environment** is an alist in `V_ENV`: a variable is an entry
`(symbol . value)`, a local function (`flet`, `labels`) an entry
`((symbol) . function)`. A local function's name is wrapped in a list, so
a variable and a function of the same name never mix: Lisp-2. Looking up
a variable walks the list, newest first, and ends at the symbol's global
value. Special variables are not in it: they are bound in the symbol
itself (shallow binding, see the design).

**Making a closure** (`make_closure`, `src/eval.asm`) is one cons and
one typed cell:

    #'(lambda (x) (+ x k))
      ->  [HDR_CLOSURE][ data ]
                         |
                         ((lambda-list . body) . environment)
                         (((X) (+ X K))        . ((K . 3)))

Nothing is copied. The closure holds the alist as it was, and the alist's
entries are shared with whoever else holds them. `defun` is the same:
its function is a closure over the environment `defun` ran in, usually
none.

**Calling one** (`apply_closure_stack`) makes the closure's environment
current, conses an entry `(parameter . argument)` onto it for each
parameter, and evaluates the body there. The caller's environment comes
back when the call's eval frame ends. If the lambda list is plain
variables, the arguments are bound straight from the stack where the
call put them, and no argument list is ever made. Anything else goes
through the general `bind`: `&optional`, `&key`, destructuring, a special
variable as a parameter, or the wrong number of arguments.

**Assignment is shared** because entries are. `setq` on a lexical
variable finds its entry and overwrites the cdr (`set_var`). Two closures
made in one scope hold the same entry:

    (let ((n 0))
      (setq inc #'(lambda () (setq n (1+ n)))
            get #'(lambda () n)))

    (funcall inc) (funcall inc) (funcall get)  ->  2

**`labels`** has functions that see each other, and themselves. It works
in two passes (`sf_labels`):

1. Push an entry `((name) . NIL)` for each function.
2. Make each closure over the environment that now holds those entries,
   then put it in its entry.

Each closure's environment then holds the entry that holds the closure:
a cycle, which the garbage collector does not mind (it marks what it has
seen). `flet` makes its closures over the outer environment, so its
functions do not see each other, as in CL.

**The price** is in two places. Every variable reference is a walk down
a list, and every binding is two conses. And a closure keeps its whole
environment alive, including the variables it never uses.

### In the compiler

Compiled code keeps variables on the Z80 stack, in the frame, so a
closure cannot simply point at them: the frame is gone when the function
returns. The compiler makes **flat closures**. When a closure is made, it
is handed the values of exactly the outer variables it uses, in a list,
and it reads them from there.

    (defun adder (k) #'(lambda (x) (+ x k)))
    (disassemble 'adder)            (disassemble (adder 3))
      0 ENTER 1                       0 ENTER 1
      2 A0                            2 A0
      3 MKCLO #<FUNCTION> 1           3 CLO 0
      6 RET                           5 ADD
                                      6 RET

`adder` pushes `k` (`A0`, its argument) and `MKCLO` makes a closure from
the inner function's code, a constant, and one value off the stack. The
closure is a `HDR_CODE` cell with data `(code . (3))`. Inside, `CLO 0`
is the first of those values. The inner function's own `x` is `A0`
there.

That is right as long as the variable never changes after the closure
is made. If it does, the copy goes stale. So **a variable that is used
from an inner function and also assigned somewhere is boxed**: its place
holds a cons around the value, and the closure gets the cons.

    (defun make-counter () (let ((n 0)) #'(lambda () (setq n (1+ n)))))
    (disassemble 'make-counter)     (disassemble (make-counter))
      0 ENTER 0                       0 ENTER 0
      2 FIX 0                         2 CLOB 0
      4 BOX                           4 ADD1
      5 L0                            5 SETCLOB 0
      6 MKCLO #<FUNCTION> 1           7 RET
      9 RET

`FIX 0` pushes 0, and that word on the stack is `n`'s place. `BOX` puts
a cons around it. `L0` pushes the place, the box, and `MKCLO` closes
over it. Inside, `CLOB 0` reads the box's car and `SETCLOB 0` writes it.
Two closures made in the same `let` get the same box, so they share `n`
as the interpreter's do.

**Knowing what to box.** Whether a variable must be boxed is known only
once all of its uses have been seen, and by then its `let` has been
compiled. The compiler could make a separate pass to find out first; it
does not, because the code would cost ROM. Instead:

* every binding has a key, the cons in the source that names the
  variable, which is the same object every time the function is compiled;
* `*cc-flags*` holds, per key, what has been learnt: 1 *used from an
  inner function*, 2 *assigned*;
* when both bits are set for a variable this pass did not box,
  `*cc-again*` is set, and `cc-top` compiles the whole function again,
  now boxing it.

Most functions take one pass, closures that assign take two.

**Nested closures** pass variables on. If `h` inside `g` inside `f` uses
`f`'s variable, `g` must close over it too, so that it has it to hand to
`h`. `cc-closed` adds the variable to the list of the function being
compiled, and making `h` inside `g` asks for it again in `g`'s context,
which adds it to `g`'s.

**`labels`** in compiled code is boxes as well: one box for each
function, made empty first. Each closure is made over the boxes, then
stored into its box. The knot is the same as the interpreter's, tied
with boxes instead of alist entries.

**`return-from` out of a `lambda`** cannot be a jump: by the time the
lambda runs, the block's frame may be anywhere. Such a block is compiled
as a `catch` of a fresh cons, made when the block is entered and held in
a hidden variable. The lambda closes over that variable, and its
`return-from` becomes a `throw` to it. Flag 4 on the block's key, and a
second pass again.

**What is not compiled**: a function whose interpreted definition closes
over variables, such as a `defun` inside a `let`. Its environment is an
alist, which compiled code has no way to address, so `compile` says so
and leaves the function interpreted.

## Tail calls

A call is in *tail position* when its value is the function's value:
nothing is left to do after it. Such a call does not need a new stack
frame. It can take the place of the caller's. With that, a loop written
as recursion runs in constant stack:

    (defun deep (n) (if (= n 0) 'done (deep (1- n))))
    (deep 3000)    ->  DONE        ; interpreted
    (compile 'deep)
    (deep 10000)   ->  DONE

### In the interpreter

`eval` (`src/eval.asm`) is a loop, not a recursive function. It pushes
one *eval frame*, the caller's environment and the return address, and
then works on a form at `ev_loop`. Where a form's value is the value of
another form, it does not call `eval` for that other form: it puts it in
HL and jumps back to `ev_loop`, in the same frame. These are the tail
positions:

* the last form of a body: a closure's, `progn`, `let`, `when`, `unless`,
  a `cond` clause, a `case` clause;
* both branches of `if`, and the last form of `and` and `or`;
* a macro call's expansion.

A call of a closure in tail position then costs no stack. The call is
laid out as `[arg n-1] ... [arg 0] [function]` above the eval frame.
`apply_closure_stack` binds the arguments into the new environment, drops
them and the function from the stack, and jumps into the body, so the
stack is back to the eval frame alone. Each step of `(deep 3000)` leaves
the stack as it found it, and only the environment grows, on the heap,
where the garbage collector takes back what is no longer in use.

What ends a tail position is anything that has work left to do after the
form:

* special variables bound by the lambda list or a `let` must be unbound
  afterwards (`let_body`);
* `block`, `catch` and `unwind-protect` frames must be taken off.

That is why `defun` wraps its body in `(block name ...)` only when the
body mentions `return-from`: every function would otherwise lose its
tail calls to a block frame that is almost never used.

The stack is the Lisp's own 4 KB, checked by every `eval`: a recursion
that is too deep is the error `stack overflow`, never a crash. A
recursion that is *not* a tail call gets about 385 deep:

    (defun d (n) (if (= n 0) 0 (1+ (d (1- n)))))
    (d 380)   ->  380
    (d 390)   ->  Error: stack overflow

### In the VM

The compiler knows when a form is in tail position (`cc`'s `tail`
argument), and ends it with `RET` there, so no jump to a common exit is
needed. A call in tail position is `TCALL`, `TCALLG` or `TCALLR`. If the
function called is compiled, it takes over the frame: its arguments are
copied over the caller's own arguments, the caller's four words and IX
stay, and it is entered as if the caller's caller had called it. When it
returns, it returns there.

A function's call of **itself** in tail position does better: it
becomes a jump. The new arguments are stored over the old ones and the
code starts again:

    (defun count-down (n acc)
      (if (= n 0) acc (count-down (1- n) (cons n acc))))
    (disassemble 'count-down)
      0 ENTER 2
      2 A1                 ; n (A0 is the last argument, acc)
      3 FIX 0
      5 NUMEQ
      6 JNILS 10
      8 A0
      9 RET
     10 A1
     11 SUB1               ; (1- n)
     12 A1
     13 A0
     14 CONS               ; (cons n acc)
     15 POPLOC 20          ; into acc's place
     17 POPLOC 22          ; into n's
     19 SPIX               ; the stack back to the frame
     20 JMPS 2             ; and round again

A tail call of something that is **not compiled** is an ordinary call
out through the core followed by `RET`. Compiled and interpreted
functions calling each other in a ring therefore do grow the stack.

**Compiled frames are bigger.** A compiled call keeps four words of the
caller's, the caller's IX and five words of its own on the stack: 20
bytes, and two more for each argument. The interpreter keeps its environment in conses,
on the heap. So a recursion that is not a tail call goes about 175 deep
compiled, against 385 interpreted:

    (compile 'd)
    (d 170)   ->  170
    (d 180)   ->  Error: stack overflow

A loop should be a tail call or `dolist`/`dotimes`/`loop` in either case;
compiled, it is much faster.

## Making it fast

Speed was not the brief, but after the first working version `(fib 17)`
took 1103 frames, 22 seconds. It is 660 interpreted now, and 197
compiled. All of the work was guided by measuring: `tools/run.sh -p
prof.txt file.lsp` has MAME count every instruction fetched while the
file runs, and `tools/profile.py prof.txt` adds them up by routine. One
lesson came up again and again: the firmware's interrupt work is about 8%
of any run, and **a call from one ROM into another is expensive**. `KL
ROM SELECT` twice, through the trampoline, is some 2000 T-states.

### The interpreter

* **Arguments that are constants or variables skip `eval`.** `ev_cons`
  looks at each argument form: a number, NIL, a string or a symbol is
  evaluated in line, with no eval frame.
* **`FNBOUND`, a byte per symbol** (at &0300): has this symbol ever been
  the name of an `flet` or `labels` function? If not, a call skips the
  search of the environment for a local function, which almost every
  call would otherwise do.
* **Plain lambda lists bind from the stack** (above): no argument list,
  no `bind`.
* **Two fixnums take the fast path.** `+`, `-`, `<` and the like check
  for two fixnums first, and only otherwise hand the call to the number
  code that knows floats and overflow.
* **Macros expand once.** The first evaluation rewrites the call in
  place to `(%EXPANDED (macro . expansion) op . args)`. Later ones use
  the expansion, as long as `op` is still that macro. The printers and
  `ed` show the call as written.
* **ESC is polled once per body**, not once per `eval`: a counter, and
  every 256th time a look at the key buffer.
* **`funcall`, `apply` and `mapcar` build no argument lists**:
  `(funcall f a b)` shifts the arguments up over `funcall` and calls `f`
  as if it had been called directly.
* **Blocks only where needed**: `defun`'s `block` (above).
* **Natives where Lisp was too slow**: `sort`, and `loop`'s expander. In
  Lisp, the expander took 2000 cells and 3 seconds an expansion.
* **Names cost nothing until used.** A library function's name is
  interned only when the reader meets it, and a function written in Lisp
  is read from ROM only when it is first called.

### The compiler and the machine

* **Dispatch in five instructions.** Operation k is the byte 3k, which
  is the low byte of its `JP` in a 256-byte page:
  `ld a,(de) : inc de : ld l,a : ld h,page : jp (hl)`.
* **Operands on the Z80 stack**, locals and arguments addressed from IX.
  The commonest, four arguments and four locals, have one-byte
  operations (`A0`-`A3`, `L0`-`L3`), as do NIL and T. A small integer
  is `FIX n`, two bytes.
* **The usual builtins are operations**, so they never leave the VM ROM:
  `car`, `cdr`, `cons`, `list`, `eq`, `eql`, `not`/`null`, `consp`,
  `atom`, `symbolp`, `+`, `-`, `*`, `1+`, `1-`, the comparisons, `zerop`,
  `oddp`, `evenp`, `aref`/`svref` and its `setf`. Each works on fixnums
  and vectors in line, and hands anything else (a float, an overflow, a
  string) to the builtin.
* **A comparison and its jump are one step.** A test that finds its
  answer looks at the next operation. If that is a conditional jump, it
  jumps or not straight away, and T or NIL is never pushed. That is
  `LT` and `JNILS` in `fib` above.
* **Short jumps.** Every jump starts with a one-byte offset. The
  assembler (`cc-assemble`) makes long the ones that do not reach,
  measures again, and repeats until nothing changes.
* **Arguments stay where the caller put them** when the lambda list is
  plain (`ENTER n`). `&optional`, `&rest` and `&key` need `ARGS`, which
  makes locals of them.
* **No clean-up in tail position**: a `let` whose body ends the function
  does not drop its locals (`SLIDE`), because `RET` resets the stack from
  IX anyway.
* **Self tail calls are jumps**; other tail calls replace the frame
  (above).
* **Constants are shared** within a function: the same constant twice is
  one slot.
* **Calling out is avoided.** A call of something not compiled goes out
  through the core (`apply_n`): two ROM switches, more than the
  interpreter's own call costs. That is why the operations above exist,
  and why a global function is taken from the symbol as it is (`vm_fn`):
  only an autoload, not yet read from ROM, goes through the core's
  `coerce_fn`.

What it comes to (MAME, frames of 1/50 s, on a 464):

| | interpreted | compiled |
|---|---|---|
| `(fib 17)` | 660 | 197 |
| a `dolist` adding up 300 numbers | 18 | 2 |
| a `dotimes` calling `oddp` | 67 | 21 |
| filling a vector and adding it up | 22 | 3 |

What gains least is code that spends its time in functions the machine
has no operation for, such as `append` and `format`: each call goes out
and back.

## The bootstrap

### The problem

The compiler is about 780 lines of Lisp (`lib/compiler.lsp`). Run
interpreted on a CPC it would be read into the heap first, and its
definitions alone would take 5500 of a 464's 6600 cells and 170 symbols
before compiling anything. It would be slow as well. Compiled, it is
bytecode, and bytecode can sit in a ROM and cost no heap at all. But
compiling it needs a compiler that runs, which is the oldest problem of
compilers written in their own language.

The way out is to run it **once, at build time, somewhere else**, on
itself, and put what comes out into the VM ROM. "Somewhere else" needs a
Lisp that can run the compiler. That Lisp does not have to be CPC Lisp,
nor fast, nor complete. It has to agree with CPC Lisp on the part of the
language the compiler is written in.

### A Lisp to run the compiler

`tools/bootstrap.py` is that Lisp, in about 870 lines of Python:

* **data**: symbols (with value, function, plist and a *special* flag),
  conses, characters, Python's integers and strings; a `Lambda` for an
  interpreted closure, and a `Code` for what `%make-code` makes;
* **a reader** for the syntax the compiler is written in: lists,
  quote, `#'`, characters, strings, integers (backquote and comma it
  reads as data: the compiler handles them, but does not use them
  itself);
* **an evaluator** with lexical environments (a chain of dictionaries),
  closures, special variables, and the special forms the compiler uses:
  `let`, `let*`, `setq`, `setf`, `incf`, `push`, `pop`, `if`, `cond`,
  `case`, `when`, `unless`, `and`, `or`, `prog1`, `dolist`, `dotimes`,
  `%loop`, `block` and `return-from`, `catch` and `throw` (as Python
  exceptions), `defun`, `defvar`;
* **about seventy-five builtins**: the list functions, `assoc`,
  `member`, `position`, arithmetic, `funcall`, `apply`, `mapcar`. Also
  the natives the compiler calls: `%make-code`, `%fn-info`,
  `%symbol-flags`.

It has no garbage collector (Python has one), no tail calls (Python
recurses; the limit is raised to 20000), and integers of any size. That
is fine, because the compiler computes only small numbers: offsets,
depths, bytes, each taken `mod 256` where it becomes one.

**What it refuses** keeps the compiler honest. The bootstrap knows the
library's macros by name (it reads the `defmacro`s in `lisp.lsp`,
`lisp2.lsp` and `loop.lsp`) and will not expand them. The compiler must
therefore be written in what the core has: `%loop`, not `loop`, and no
`&key` in its own lambda lists. Its builtins need only do what the
compiler asks of them *while compiling itself*. `format`, for instance,
does nothing but `~A`, which is all `cc-keyword` needs to make `:NAME`
from `NAME`. The compiled compiler on the CPC calls the real `format`.

### Compiling the compiler

`main()` does this, in under a second:

1. **The natives' numbers.** The VM ROM's natives (`%make-code`, `%code`
   and the rest: the `;@vm` lines of `lib/vm.asm`) are its functions 0 to
   9.
2. **Load the compiler**: read `compiler.lsp` and evaluate every form, so
   its `defvar`s and `defun`s now exist, interpreted, in Python.
3. **Run it on itself**: call `cc-top` on each of its own `defun`s. Out
   comes a `Code` per function: its bytes, its constants and its name.
   An inner `lambda` is a `Code` among its parent's constants, for
   `MKCLO`.
4. **Number them all**, depth first from each `defun`, inner functions
   too, after the natives: `compile` is 10, and the 82 functions are
   10 to 91.
5. **Rewrite the calls.** The compiler's calls of its own functions came
   out as `CALLG k n`: call the function of constant k, a symbol, at run
   time. Where that symbol names one of the 82, or a native,
   `CALLG`/`TCALLG` becomes `CALLR`/`TCALLR` with the function's
   number. No symbol is needed at run time, and no cell.
6. **Pool the constants.** Each function's constant indices are
   rewritten into one pool shared by all of them, the same constant
   being one slot. A `&key` list's keywords stay together, because
   `ARGS` takes the first and a count.
7. **Turn functions into references.** A constant that is a `Code` (an
   inner `lambda`), or a symbol naming one of the 82 or a native (a
   `#'cc-...` passed to `mapcar`, say), cannot be text. It becomes a
   NIL in the text and a *reference*: this constant is that function.
8. **Write `build/vmcode.asm`**, which `lib/vm.asm` includes.

The output looks like this:

    ; made by tools/bootstrap.py from lib/compiler.lsp -- do not edit

    vm_pooldata:
        dw vm_pooltext
        db 14                               ; 14 references:
        db 4,11,102,58,108,61,109,62,...    ; constant 4 is function 11...
    vm_pooltext:                            ; the constants, as Lisp text:
        db 40,83,89,77,66,79,76,45,70,...   ; "(SYMBOL-FUNCTION LAMBDA ..."
    ;@vmcode COMPILE vb_10+2
    ; 10: COMPILE
    vb_10:
        db 178,0,105,1,1,0,195,252,...      ; 178 bytes: ARGS 1 1 0, ...
    ;@vmcode - vb_11+2
    ; 11: NIL                               ; an inner lambda, no name
    vb_11:
        db 17,0,102,0,27,0,...              ; 17 bytes: ENTER 0, ...
    ...

`tools/mklib.py` turns the `;@vmcode` lines into the VM ROM's function
table. For the three meant to be called by name, `COMPILE`,
`COMPILE-FILE` and `DISASSEMBLE`, it adds a name to library 2's symbol
table, a kind 3 entry; the other 79 have none (`-`). The bootstrap
reports: 82 functions, 7813 bytes of code, 178 constants, 2325 bytes of
text.

**Why the constants are text.** A Lisp object cannot be built at build
time: symbols are interned at run time, and cells are in RAM, at
addresses only the running system knows. Text, read by the CPC's own
reader, is the form that survives. The library's Lisp functions are kept
as text for the same reason.

### At run time

1. **The name.** The reader meets `compile` and interns it. `lib_find`
   finds it in library 2's table as a kind 3 entry and gives the symbol
   a `HDR_CODE` cell whose data is the fixnum 10.
2. **The call.** `apply_core` sees `HDR_CODE` and goes to the VM ROM
   (`VMCALL`). A fixnum means *this ROM's function 10*. Its bytecode is
   in the ROM, so `vm_romcode` makes a frame whose code pointer is the
   ROM address and whose constants are the pool's.
3. **The pool**, the first time (`vm_pool`). The core's reader reads the
   text from the ROM into a vector, and each reference becomes a
   `HDR_CODE` cell with its function's number. The vector is kept in
   `V_VMROOT`, a root for the garbage collector. The pool lives in block
   space and moves with a collection, like any compiled code's constants;
   `vm_fix` finds it again after one, and leaves the program counter
   alone, since ROM does not move.
4. **The compiler's calls of itself** are `CALLR k n`: straight into
   function k of the same ROM, with no symbol looked up.
5. **When it is done**, `compile` (and `disassemble`) call `%vm-release`,
   which sets `V_VMROOT` to NIL. The pool becomes garbage, and the next
   collection takes it back.

Measured with `(room)`, compiling a small function takes about 400 cells
and 1.3 KB of string space while it runs, all given back afterwards. The
one lasting cost is about forty symbols, interned when the pool is
first read: the compiler's special variables and quoted names, which the
garbage collector does not take back.

### Can it be trusted?

The compiled compiler is the product of the Python interpreter running
the compiler's source. If the Python Lisp disagreed with CPC Lisp on
something the compiler relies on, the ROM's compiler would be subtly
wrong, though the source is right. Three things stand against that.
The subset is small and plain: no macros of the library's, no floats, no
large numbers. The compiled compiler then compiles the regression tests
on the CPC itself (`test/compile.lsp`, `test/disccomp.lsp`, on the 464
and the 6128 in MAME), and every answer is checked. And the compiler is used on real code, on a real 464.

The classic further check has not been done. That check is a second
stage: the compiled compiler compiles its own source on the CPC, and
the bytes must come out the same. The source is 33 KB, and it does not
fit in a CPC's memory at once.

### Changing the compiler

A change to `compiler.lsp` is a change to the VM ROM: `tools/build.sh`
runs the bootstrap every time. Mind these:

* **Write in the subset**: the core's special forms and what
  `bootstrap.py` has as builtins (add one there if needed); no library
  macros; no `&key` in the compiler's own functions; no reliance on
  numbers beyond 15 bits.
* **A quoted symbol that names one of the compiler's own functions**
  becomes that function in the pool (step 7), not the symbol.
* **Limits**: the pool's indices are a byte (178 of 256 used); the VM
  ROM has about 570 bytes free; the dispatch page is full (85
  operations), so a new operation must replace one. The bootstrap's
  `KINDS` table, each operation's operand layout, must match the
  disassembler's.
* **Test on the CPC**: `tools/test.sh` and `tools/test.sh -m 6128`.

## What was hard, and what cannot be done

Common Lisp was made for machines with megabytes. Its standard package
has 978 symbols. It has a numeric tower with integers of any size,
ratios and complex numbers, and it has packages, CLOS, and a condition
system with restarts. The CPC has a 4 MHz Z80, and about 40 KB of RAM
left for everything. CPC Lisp has some 460 functions, macros and special
forms, and a good part of them are the CPC's own: graphics, sound,
files. This section looks back on what made the port hard, roughly in
the order of how much each shaped the result, and on what does not fit
or cannot be done.

### Memory, all the time

About 40 KB is left for the cells, the symbols, the strings, the stack
and the program itself. Nearly every decision comes back to that:

* **Small objects.** A value is a 16-bit word and a cons is 4 bytes.
  The type is mostly *where* a value points: symbols in one region,
  cells in another, builtins in ROM. So a cons needs no header, and most
  type tests are one comparison of the high byte. The price is 15-bit
  fixnums and a fixed 512 symbols.
* **Little room for programs.** A 464 has about 6600 cells.
  Interpreted, the compiler's 780 lines would take 5500 of them, so the
  heap holds fewer than a thousand lines of interpreted Lisp, with
  nothing left for data. Compiling helps: bytecode is far smaller than
  the lists it came from. But a large program does not fit, whatever
  the language.
* **Nothing loaded that is not used.** That is why the library is in
  ROMs whose names cost nothing until the reader meets them, and why the
  eighty functions of library 3 are text, read in on first use. Loaded
  at boot, they would take roughly half the heap.
* **Out of the heap.** `loop`'s expander, written in Lisp, took 2000
  cells and 3 seconds an expansion, so it became native code in a ROM.
  The compiler could not run on the CPC at all, so it was
  [bootstrapped](#the-bootstrap) into one.
* **Small limits everywhere**: a string that a function builds is at
  most 255 characters (it is built in the reader's token buffer), the
  stack is 4 KB, hash tables do not grow, a file needs 2 KB of string
  space while it is open.

The 6128's second 64 KB does not help the heap. It can be seen only 16
KB at a time, banked in at &4000, and a heap there would need a bank
switch on every pointer followed. So it is a RAM disc, `M:`, and the
Lisp lives in the first 64 KB on every model.

Three things make the heap go further all the same (2026-11-12):

* **Dropping what can come back.** When a collection frees no cell,
  `cons` asks the library (`ln_short`, `lib/short.asm`) before it gives
  up. A function the library's text defined can be read from ROM again,
  so each such closure is hidden from a second collection -- its pointer
  made odd, which the collector takes for a fixnum -- and the ones that
  collection frees get their autoload stub back. Anything still holding
  one (a call running, a variable) keeps it alive, and the pointer is
  put back.
* **Programs read on demand.** `(load "big" :lazy t)` gives a program's
  functions the library's life: a stub each, knowing the file and the
  position (the reader counts what it takes from a file), the
  definition read on the first call and marked as the library's, so the
  same dropping takes it back to its stub.
* **Data outside the heap.** A far array is a file on `M:`, read and
  written in place an element at a time. Only what the collector need
  not look at goes there -- fixnums, characters, T and NIL, or bytes.

### 16 KB at a time

The Z80 addresses 64 KB. A ROM is seen in a 16 KB window at &C000, over
the screen memory, and only one at a time.

* **16 KB is small.** The core has a dozen bytes free. Much of the late
  work was moving things out of it to make room: `vector` and
  `code-char` went to the library, the second so that 0.9's banner
  would fit.
* **The ROMs cannot see each other.** A call from one ROM to another
  goes through a trampoline in RAM and `KL ROM SELECT` twice: some 2000
  T-states, which is more than an interpreted call. That one cost shaped
  the VM, whose usual builtins are its own operations so that it rarely
  has to call out.
* **A ROM cannot read another's bytes.** The name of a builtin symbol is
  in the core ROM, so library code cannot read it. It compares builtins
  by address, and asks the core for a name. Anything handed from one ROM
  to another must be in RAM.
* **A ROM cannot read the screen.** At &C000 it sees itself. The
  function editor writes to the screen but never reads it back, so its
  cursor is a character drawn again in inverse; an XOR showed the ROM's
  own code on the screen.
* **Bits are scarce.** A library function's data word has two spare bits
  for its part, so there are at most four parts. The VM ROM had to be a
  special case, with no names of its own. A part cannot call another
  part, so code they share is in each of them.

### The Z80

* **Few registers.** HL, DE and BC; IX is slow (19 T-states for each
  `(ix+d)`); IY and the alternate set belong to the firmware. The VM
  spends DE on its program counter and IX on the frame, and keeps
  everything else on the stack.
* **Tags made for it.** A fixnum is any word with bit 0 set, one
  `bit 0,l`; NIL is 0, `ld a,h : or l`; a symbol or a cell is a range of
  high bytes. Decoding a fixnum is a 16-bit shift.
* **No multiply or divide**: `*`, `floor` and `mod` are loops. Floats
  come from the firmware's maths package, which is slow, but its maths
  costs no ROM of ours.
* **Speed.** At 4 MHz, with the firmware's interrupts taking about 8%,
  `(fib 17)` takes 13 seconds interpreted and 4 compiled.
* **Bytecode, not machine code.** Native Z80 code would be faster, but
  several times larger for each operation. It would have to live in the
  heap, in block space, which moves, and a compiler good enough to be
  worth it would not fit in a ROM. The bytecode compiler, at 7.8 KB of
  bytecode, nearly fills its ROM already.

### The firmware

* **Three machines, three firmwares.** Past &BD37 the 464's jumpblock
  and the 664/6128's differ. EDIT moved, the maths package has other
  entries in another place, only the 464 has REAL SUBTRACTION and only
  the 6128 has RND. Everything goes through the vectors, and the ones
  that differ are found at boot.
* **No BASIC.** Replacing it means none of its code: no number
  printing, no editor, no floats of BASIC's. The firmware's maths
  package gives about nine digits, and clobbers IX and IY.
* **The firmware's stack is tiny**, so the Lisp brings its own 4 KB.
* **Behaviour learnt the hard way**, all recorded in `CLAUDE.md`:
  * a far call in a jumpblock returns past its own address, into the
    next vector (the RAM disc wrote broken files until that was found);
  * the 6128's internal AMSDOS ignores ROMDIS (a ROM at 7 there drives
    the bus against it);
  * the 464's ROM walk looks only at ROMs 0 to 7;
  * ESC raises the break event from the interrupt, whatever the program
    does, so the Lisp must handle it;
  * background ROMs take memory at boot that HIMEM does not show;
  * text output manages about five characters a frame: fine for a line,
    far too slow for a full-screen editor, which draws into the screen
    memory itself.
* **One file in, one file out.** The cassette vectors, which the disc
  ROM takes over, have one input and one output file. So that is all
  Lisp has, and `compile-file` reads its whole source before it writes.

### Memory that moves

Strings, vectors, floats and compiled code live in block space, which
the garbage collector compacts. Any raw pointer into block space is
therefore wrong after anything that may allocate. The collector scans
the machine stack conservatively: any word there that looks like a cell
keeps it alive. That makes native code easy to write, since a Lisp
value may sit in a register pair or on the stack across a `cons`, but
it does nothing for raw pointers. The VM's program counter is exactly
such a pointer, into bytecode that moves. Hence the GC counter and
`vm_fix`, after every operation that can allocate. More than one bug in
this project was a raw pointer kept across an allocation.

The collector also has to work in what is left over. Its mark stack is
256 words. When it overflows, the collector scans the heap again for
what it could not reach, rather than giving up or recursing.

### Testing without a debugger

There is no debugger on a CPC. Development was in MAME, driven by a Lua
harness that types each line when the REPL asks for one, catches the
output at the firmware's text vector, and counts instructions for the
profiler. The real 464 got each build that passed the tests on both
machines, through the LambdaSpeak card. Some things only the hardware
shows: timing, the 1.1 firmware, a RAM expansion, the card's own ROMs.

### What does not fit, and what cannot be done

Some of Common Lisp is left out for want of space and could come with
more; some is beyond the machine.

**Beyond this machine:**

* **A heap past about 40 KB**: the Z80's 64 KB address space, less the
  firmware, the screen and the ROM window, is all there is. Banked RAM
  makes a RAM disc, not a bigger heap.
* **Compiling the compiler on the CPC**: its source does not fit in
  memory, so the bootstrap has to happen elsewhere.
* **The whole standard**: 978 symbols in 512 slots and six 16 KB ROMs.
  CLOS alone, in the implementations that have it, is larger than all
  six.
* **A compiler to machine code that is worth having**: no room for the
  compiler, and the code would be several times the size of the
  bytecode.
* **A modern garbage collector**: a generational or incremental one
  needs a write barrier on every store and more memory, and a precise
  one needs to know what every stack word is. Mark and sweep, with a
  conservative stack scan, stops the program while it runs.
* **Numbers as a modern machine has them**: one float type, the
  firmware's 40-bit reals, with no double precision and no IEEE
  infinities or NaNs. Characters are 8-bit.

**Possible, but not in 0.9** (`docs/reference.md`, *Differences from
Common Lisp*, has the full list):

* bignums and ratios: an integer overflow becomes a float instead, and
  `/` of integers that does not divide gives a float;
* packages, so the `%` names above are a convention instead;
* condition classes, `handler-bind` and restarts: a condition is its
  message;
* multi-dimensional and adjustable arrays: vectors are one-dimensional;
* CLOS, `*print-case*`, `*terminal-io*`;
* a backtrace or stepper: an error goes back to the REPL;
* tail calls between compiled and interpreted code: within each they
  are proper, across the two they are ordinary calls.

What came out is more than one might expect of the machine:
closures, macros, `format`, `loop`, `unwind-protect`, catchable errors,
floats, file streams, two editors and a compiler, on a 1984 home
computer. That fits because each piece is lazy (nothing in RAM until
used), shared (one pool, one reader for everything), or pushed into
ROM, which is the one resource the CPC has plenty of: 16 KB at a time,
as many times as there are slots.
