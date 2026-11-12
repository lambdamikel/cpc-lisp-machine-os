# CPC Lisp 0.9 -- reference

*A Lisp machine for the Amstrad CPC*

CPC Lisp is a Common Lisp dialect in ROM for the Amstrad CPC 464, 664
and 6128. This manual lists everything built in. Where CPC Lisp follows
Common Lisp the descriptions are short; where it differs, it says so (and
[Differences from Common Lisp](#differences-from-common-lisp) collects
them).

Each function is marked with where it lives: **core** (the core ROM),
**1**, **2**, **3** (the library ROMs LISPLIB, LISPLIB2, LISPLIB3),
**demo** (LISPDEMO) or **vm** (LISPVM, which runs compiled code). Any
ROM but the core can be left out; its functions are then undefined, and
everything else works. The [README](../README.md#installing-the-roms) says
how to install them; [the tutorial](tutorial.md) is a tour, and
[the design](design.md) how it all works.

Contents: [Starting](#starting) · [The REPL](#the-repl) ·
[The editors](#the-editors) · [Syntax](#syntax) ·
[Data types](#data-types) · [Evaluation](#evaluation) ·
[Special forms](#special-forms) · [Macros](#macros) ·
[Functions and evaluation](#functions-and-evaluation) ·
[The compiler](#the-compiler) ·
[Symbols](#symbols) · [Lists](#lists) · [Sequences](#sequences) ·
[Numbers](#numbers) · [Characters](#characters) · [Strings](#strings) ·
[Vectors](#vectors) · [Structures](#structures) ·
[Hash tables](#hash-tables) · [Types](#types) ·
[Input and output](#input-and-output) · [Files](#files) ·
[The text screen](#the-text-screen) · [Graphics](#graphics) ·
[Turtle graphics](#turtle-graphics) · [Sound and music](#sound-and-music) ·
[Speech and PlayCity](#the-lambdaspeak-card-speech-and-playcity) ·
[Keys, time and the machine](#keys-time-and-the-machine) ·
[The demos](#the-demos) · [Memory](#memory) ·
[Differences from Common Lisp](#differences-from-common-lisp)

## Starting

With the core ROM at ROM 0 (replacing BASIC), the CPC starts in Lisp:

    CPC Lisp 0.9
    A Lisp machine for the Amstrad CPC
    library ROMs 4 5 6 3
    6402 cells free
    LISP>

The numbers are the ROMs where the library parts were found (LISPLIB,
LISPLIB2, LISPLIB3, LISPDEMO); the VM ROM is not listed. At any other ROM
number, `|LISP` from BASIC starts it.

## The REPL

Type an expression and RETURN. Its values are printed, one a line; an
expression may run over several lines (the next is asked for until the
parentheses balance).

- `*`, `**`, `***` hold the last three values printed (the first of each).
- An error prints `Error:`, a message and the object it is about, and comes
  back to `LISP>` -- unless `ignore-errors` or `handler-case` catches it. Open files are abandoned, and special variables bound
  with `let` get their global values back.
- **ESC** stops whatever is running: `Error: break`. Even a tight `(loop)`.
- The CPC has no `~` key: it is **CTRL + 2** (the firmware's key table).

## The editors

**The line editor** (library 1; without it, the firmware's own) edits the
line being typed, with the CPC's keys:

| Key | |
|---|---|
| ← → | move in the line |
| ↑ | the last line again |
| DEL / CLR | delete before / under the cursor |
| TAB | indent a blank line to where Lisp would |
| SHIFT + arrows, COPY | the copy cursor, as in BASIC |
| `)` | shows its `(` for a moment (beeps if there is none) |
| **CTRL + 2** | `~` (the CPC has no tilde key; in MAME: Right Alt + 2) |

A continuation line starts indented Lisp-style.

**The function editor**: `(ed 'name)` shows name's definition,
pretty-printed, on the whole screen; `(ed)` reopens the last text (after an
error in it, say).

| Key | |
|---|---|
| arrows | move |
| SHIFT + ↑ / ↓ | a page up / down |
| CTRL + ↑ / ↓ | the top / bottom |
| CTRL + ← / → | the start / end of the line |
| RETURN | a new line, indented |
| TAB | indent the line |
| DEL / CLR | delete before / under the cursor |
| **COPY** or CTRL + S | done: read and evaluate it all |
| **ESC** | leave it as it was |

## Syntax

The reader is Common Lisp's, mostly:

| | |
|---|---|
| `foo`, `Foo` | symbols, upcased: both are `FOO` |
| `:key` | a keyword: a constant, its own value |
| `42`, `-7`, `#x1F`, `#b101` | integers |
| `3.14`, `1e10`, `.5`, `40000` | floats (a whole number too big for an integer is one) |
| `"text\"s"` | a string, `\` quoting the next character |
| `#\a`, `#\Space`, `#\Newline` | characters; also `#\Tab` `#\Return` `#\Linefeed` `#\Page` `#\Backspace` `#\Escape` `#\Rubout` `#\Nul` |
| `(a b . c)` | lists, dotted pairs |
| `'x`, `` `x ``, `,x`, `,@x` | quote, backquote, unquote, splice |
| `#'f` | `(function f)` |
| `#(1 2 3)` | a vector |
| `; ...`, `#| ... |#` | comments |
| `\|hello world\|`, `a\ b` | symbols with characters taken as they are: between bars, or one after `\`. `prin1` writes such a name in bars, `princ` without |

Not read: `#S(...)` (printed, not read back), `#.`, `#+`. A symbol named
like a float (`\|1.5\|`) is printed without bars.

**Typing `~`**: the CPC keyboard has no tilde. **CTRL + 2** types it --
the firmware's own key table, so it works in the line editor, in `ed` and
in the firmware's EDIT alike (in MAME, CTRL is Right Alt: Right Alt + 2).
`format`'s directives need it: `(format t "~A~%" x)`.

## Data types

| Type | Notes |
|---|---|
| integer (fixnum) | -16384 to 16383. A result past that becomes a float: `(* 200 200)` is `40000.0` |
| float | the firmware's five-byte reals, about nine digits, to 10^38 |
| character | codes 0-255 |
| string | any length; functions that build strings make them up to 255 characters |
| symbol | 512 at most (about 160 are built in); keywords are symbols |
| cons, list | `NIL` is the empty list and false |
| vector | one-dimensional, any objects |
| structure | `defstruct`; prints as `#S(POINT 1 2)` |
| hash table | a structure, `#S(HASH-TABLE ...)` |
| function | built in (`#<SUBR CAR>`), interpreted (a closure), compiled, or Lisp text not read yet (autoload); closures and compiled functions print as `#<FUNCTION>` |

## Evaluation

A Lisp-2: a symbol has a value and, apart, a function (`#'f`, `funcall`).
Closures are lexical; `defvar` and `defparameter` make special (dynamic)
variables. Tail calls do not grow the stack: a loop written as tail
recursion runs for ever. The stack is checked: too deep a recursion is an
error, not a crash.

**Lambda lists** take `&optional` (with defaults and supplied-p),
`&rest`, `&body`, `&key` (defaults, supplied-p, `((:keyword var) default)`;
keys nobody asked for are let be, as with `&allow-other-keys`), `&aux`, and
destructuring: a list where a variable would be is matched against its
argument.

**Places** for `setf`, `incf`, `decf`, `push`, `pop`: variables, `car`
`cdr` `first` `rest` `second` `cadr` `nth` `symbol-value`
`symbol-function` `symbol-plist` `get` `char` `aref` `svref`, structure
accessors, `gethash`, and anything given `defsetf`.

**Multiple values**: `values` returns several; `floor`, `truncate`,
`round`, `ceiling` return the remainder too, `gethash` whether it found
the key. Only the forms below see more than the first.

## Special forms

All **core**.

| Form | |
|---|---|
| `(quote x)` `(function f)` | |
| `(lambda (params) body...)` | a closure |
| `(if test then [else])` `(when test body...)` `(unless test body...)` | |
| `(cond (test body...)...)` | |
| `(case key ((k...) body...)... (otherwise body...))` | `t` also means otherwise; keys by `eql` |
| `(and x...)` `(or x...)` | |
| `(progn body...)` `(prog1 first body...)` | |
| `(setq var value...)` `(setf place value...)` | |
| `(incf place [n])` `(decf place [n])` | |
| `(push x place)` `(pop place)` | |
| `(let ((var value)...) body...)` `(let* ...)` | |
| `(flet ((name params body...)...) body...)` `(labels ...)` | local functions; labels' see each other |
| `(defun name params body...)` `(defmacro name params body...)` | |
| `(defvar var [value])` `(defparameter var value)` `(defconstant var value)` | defvar does not change a value already there |
| `(block name body...)` `(return-from name [value])` `(return [value])` | |
| `(catch tag body...)` `(throw tag value)` | |
| `(unwind-protect form cleanup...)` | the cleanups run however form is left: a normal end, `throw`, `return-from`, an error (caught or not), ESC |
| `(dolist (var list [result]) body...)` | |
| `(dotimes (var n [result]) body...)` | |
| `(%loop body...)` | for ever, until `return` (what a simple `loop` is) |
| `(declare ...)` | ignored |
| `(the type form)` | the form |
| `(multiple-value-list form)` | all of form's values, as a list |

## Macros

| Macro | | |
|---|---|---|
| `(loop form...)` | forms that are lists: for ever, until `return`. Otherwise the extended LOOP, below | demo |
| `(do ((var init [step])...) (end-test result...) body...)` | `do*` steps in order | 3 |
| `(psetq var value...)` | in parallel | 3 |
| `(pushnew x place)` | | 3 |
| `(multiple-value-bind (var...) form body...)` | | 3 |
| `(nth-value n form)` | | 3 |
| `(multiple-value-call f form...)` | | 3 |
| `(multiple-value-prog1 form body...)` | | 3 |
| `(multiple-value-setq (var...) form)` | | 3 |
| `(defsetf access update)` | `(setf (access a...) v)` becomes `(update a... v)` | 3 |
| `(defstruct name slot...)` | see [Structures](#structures) | 3 |

`(macroexpand form)`, `(macroexpand-1 form)` (**core**). A macro call is
expanded the first time it is evaluated and the expansion kept in the call
(it prints as written); redefining the macro makes the call expand afresh.


### The extended LOOP

`(loop for i from 1 to 10 when (evenp i) collect i)` is `(2 4 6 8 10)`.
The clauses, in CL's words (keywords may be written `:for` too):

| Clause | |
|---|---|
| `for v in list [by f]` `for v on list` | each element; each tail. v may be a pattern: `for (k . v) in alist` |
| `for v across vector` | each element of a vector or string |
| `for v from a [to b \| below b \| downto b \| above b] [by n]` | counting; `upfrom` `upto` `downfrom` too; from 0 if not given |
| `for v = x [then y]` | x every pass, or x first and y after |
| `for k being the hash-keys of table [using (hash-value v)]` | and `hash-values` |
| `as` | is `for`; `and` joins for clauses |
| `with v [= x] [and ...]` | a variable |
| `repeat n` | n passes |
| `while x` `until x` | stop when x is false / true (where it stands among the clauses) |
| `collect x` `append x` `nconc x` `sum x` `count x` `maximize x` `minimize x` | into the result; `into var` into a variable instead (`-ing` forms too) |
| `do form...` | the forms |
| `when x clause [and clause...] [else clause...] [end]` | `if` the same; `unless` the other way round |
| `return x` | the loop's value: x |
| `always x` `never x` `thereis x` | T unless x is ever false (true); thereis: the first true x |
| `initially form...` `finally form...` | before the first pass; after the last -- `(finally (return x))` gives x |
| `named name` | `(return-from name x)` leaves it; `(loop-finish)` goes to the finally forms |

The expansion is made by native code (in the demo ROM) the first time
the loop runs, and kept. It uses `%0`, `%1`... as its own variables.

## Functions and evaluation

| Function | | |
|---|---|---|
| `(eval form)` | | core |
| `(apply f arg... list)` `(funcall f arg...)` | f a function or a symbol | core |
| `(mapcar f list...)` `(mapc f list...)` | | core |
| `(mapcan f list...)` `(maplist f list)` | | 3 |
| `(identity x)` `(complement f)` | | 3 |
| `(values x...)` | | 2 |
| `(values-list list)` | | 3 |
| `(functionp x)` | | core |
| `(error control arg...)` | signals an error: `(error "bad value: ~A" x)`, the message made by `format`; a symbol is its name. Caught by `ignore-errors` and `handler-case`, else printed and back to `LISP>` | 3 |
| `(ignore-errors form...)` | the forms' value, or NIL and the condition if an error was signalled | 3 |
| `(handler-case form (error (c) body...) (:no-error (v) body...))` | as CL; every error is one kind, so the first clause that is not `:no-error` takes it | 3 |
| `(warn control arg...)` | prints `Warning:` and the message, and goes on | 3 |
| `(assert form)` | an error if form is false | 3 |

## The compiler

| Function | | |
|---|---|---|
| `(compile 'name)` | compiles name's definition in place; the name, or NIL (and why) if it could not | vm |
| `(compile nil '(lambda (x) ...))` | a compiled function | vm |
| `(compile-file "name" [out])` | compiles the defuns of name.LSP into name.FAS (or out); `(load "name.fas")` loads them compiled. Macros, `defvar`s and the like in the file are evaluated as it goes, for what comes after | vm |
| `(disassemble 'name)` | lists the bytecode of a compiled function | vm |

`compile` turns an interpreted function into bytecode for the VM ROM.
Compiled, `(fib 17)` takes 4 s instead of 13; a `dolist` adding up a
list is nine times faster, a `dotimes` over a vector seven, one calling
`oddp` three. The definition's conses are freed: code takes much less
memory than the list it came from. Compiled and interpreted functions
call each other freely. What gains least is code that spends its time
in builtins the machine has no operation for (`append`, `format`...):
each such call goes out to the core ROM and back.

Everything compiles: the special forms, `&optional` `&rest` `&key`
`&aux`, closures (a variable a closure assigns is shared, as when
interpreted), `labels`/`flet`, `block`/`return-from` -- from inside a
`lambda` too --, `catch`/`throw`, `unwind-protect`, special variables
bound by `let`, multiple values, backquote. Macros are expanded once,
when compiling. `car` `cdr` `cons` `list` `eq` `eql` `not` `+` `-` `*`
`1+` `1-` `<` `>` `=` `zerop` `oddp` `aref` (and its `setf`)... are
operations of the machine, on fixnums and vectors; anything else goes to
the function. A call of the function itself in tail
position becomes a jump: a recursive loop runs in no stack.

Not compiled (it says why, and the function stays as it was): a function
that closes over variables (one `defun`ed inside a `let`), a special
variable as a parameter (bind it with `let` inside instead), and `defun`,
`defmacro` or `defvar` inside a function. The compiler itself is
bytecode in the VM ROM; the first `compile` costs about forty symbols
(the compiler's names), nothing else once it is done.

A compiled call takes more stack than an interpreted one (20 bytes, and
2 an argument): a recursion that is not a tail call goes about 175 deep
compiled, 385 interpreted, before `stack overflow`. How the compiler
works: [the internals](internals.md).

## Symbols

| Function | | |
|---|---|---|
| `(symbol-name s)` `(symbol-value s)` `(symbol-function s)` `(symbol-plist s)` | | core |
| `(set s value)` `(boundp s)` `(fboundp s)` `(makunbound s)` `(fmakunbound s)` | | core |
| `(get s indicator [default])` | `setf`-able | core |
| `(remprop s indicator)` | | 2 |
| `(gensym [prefix])` | G1, G2... | 2 |
| `(intern string)` | | 2 |
| `(symbolp x)` `(keywordp x)` | | core |

**Names starting with `%`** -- `%AGAIN`, `%KOCH-SIDE`, `%LOOP`,
`%CODE`... -- are the system's own: helpers of the library and the
demos, and the machinery under the documented functions. They are
ordinary symbols (CPC Lisp has no packages; the `%` keeps them apart
from yours), not listed here, and may change from one version to the
next. `(ed '%koch-side)` shows one written in Lisp.
[The internals](internals.md#names-with-a-percent-sign) list them.

## Lists

| Function | | |
|---|---|---|
| `(car l)` `(cdr l)` `(first l)` `(rest l)` `(second l)` `(third l)` | | core |
| `(caar l)` `(cadr l)` `(cdar l)` `(cddr l)` `(caddr l)` `(cdddr l)` | | core |
| `(cons a b)` `(list x...)` `(list* x... tail)` `(append list...)` | | core |
| `(length seq)` `(nth n l)` `(nthcdr n l)` `(last l)` | | core |
| `(rplaca c x)` `(rplacd c x)` | | core |
| `(null x)` `(not x)` `(atom x)` `(consp x)` `(listp x)` | | core |
| `(eq a b)` `(eql a b)` `(equal a b)` | eql: the same object, or numbers of one value | core |
| `(member x list &key test test-not key)` | | 2 |
| `(assoc x alist &key test test-not key)` `(rassoc ...)` | | 2 |
| `(member-if p list &key key)` `(member-if-not ...)` | | 3 |
| `(assoc-if p alist &key key)` `(rassoc-if ...)` | | 3 |
| `(nconc list...)` `(copy-list l)` `(make-list n &key initial-element)` `(butlast l [n])` | | 3 |
| `(endp l)` | T for NIL (an end of list) | demo |
| `(nreconc l tail)` | l reversed in place onto tail | 1 |
| `(acons k v alist)` `(pairlis keys values [alist])` `(subst new old tree)` | | 3 |
| `(adjoin x l)` `(union a b)` `(intersection a b)` `(set-difference a b)` `(subsetp a b)` | by eql | 3 |

## Sequences

A sequence is a list, a string or a vector. find, position, count,
remove, delete and substitute (and their -if and -if-not) take all of
CL's keywords: `:test`, `:test-not`, `:key`, `:start`, `:end`,
`:from-end`, and `:count` for the removes and substitutes. A result of
the same kind is a fresh one.

| Function | | |
|---|---|---|
| `(length seq)` `(elt seq i)` | | core |
| `(reverse seq)` `(nreverse seq)` | | 2 |
| `(sort seq pred &key key)` `(stable-sort ...)` | a merge sort: stable; lists relinked, vectors in place | 2 |
| `(coerce x type)` | to `list`, `vector`, `string`, `character`, `float`, `t` | 2 |
| `(find x seq ...)` `(find-if p seq ...)` `(find-if-not ...)` | | 2 |
| `(position x seq ...)` `(position-if ...)` `(position-if-not ...)` | | 2 |
| `(count x seq ...)` `(count-if ...)` `(count-if-not ...)` | | 2 |
| `(remove x seq ...)` `(remove-if ...)` `(remove-if-not ...)` | | 2 |
| `(delete ...)` `(delete-if ...)` `(delete-if-not ...)` | as remove (not destructive) | 2 |
| `(substitute new old seq ...)` `(substitute-if ...)` `(substitute-if-not ...)` `(nsubstitute ...)` | | 2 |
| `(remove-duplicates seq ...)` `(delete-duplicates ...)` | keeps the last of each; :test, :test-not, :key | 3 |
| `(search seq1 seq2 ...)` | the index where seq1 is in seq2 | 3 |
| `(subseq seq start [end])` `(copy-seq seq)` | | 3 |
| `(concatenate type seq...)` | type `list`, `vector` or `string` | 3 |
| `(fill seq x &key start end)` | | 3 |
| `(map type f seq...)` | type `list`, `vector`, `string` or `nil` | 3 |
| `(reduce f seq &key key from-end initial-value)` | | 3 |
| `(every p seq...)` `(some p seq...)` `(notany ...)` `(notevery ...)` | | 3 |

## Numbers

Integers are fixnums, -16384..16383; anything else is a float. An integer
result that does not fit becomes a float. Float functions work through
the firmware's maths package.

| Function | | |
|---|---|---|
| `(+ x...)` `(- x...)` `(* x...)` `(/ x...)` | `/` gives an integer only if the quotient is whole | core, `/` 2 |
| `(1+ x)` `(1- x)` `(abs x)` `(max x...)` `(min x...)` | | core |
| `(= x...)` `(/= x...)` `(< x...)` `(> x...)` `(<= x...)` `(>= x...)` | | core |
| `(zerop x)` `(plusp x)` `(minusp x)` `(evenp n)` `(oddp n)` | | core |
| `(numberp x)` `(integerp x)` `(floatp x)` | | core, `floatp` 2 |
| `(floor x [y])` `(truncate x [y])` | quotient and remainder | core |
| `(round x [y])` `(ceiling x [y])` | quotient and remainder; round takes a half to the even integer | 2 |
| `(mod a b)` `(rem a b)` | | core |
| `(float x)` | | 2 |
| `(sqrt x)` `(exp x)` `(log x [base])` `(expt b p)` | expt of integers to whole powers stays exact | 2, `expt` 3 |
| `(sin x)` `(cos x)` `(tan x)` `(atan y [x])` | radians | 2 |
| `pi` | a constant | 3 |
| `(random n)` | 0 <= result < n; an integer or a float, as n is | core |
| `(gcd a b)` `(signum x)` | | 3 |
| `(logand n...)` `(logior n...)` `(logxor n...)` `(lognot n)` `(ash n count)` | | 2 |

## Characters

| Function | | |
|---|---|---|
| `(char-code c)` `(characterp x)` | | core |
| `(code-char n)` | | 1 |
| `(char-upcase c)` `(char-downcase c)` | | 1 |
| `(char= c...)` `(char/= c...)` `(char< c...)` `(char> c...)` `(char<= c...)` `(char>= c...)` | | 1 |
| `(char-equal c...)` `(char-not-equal ...)` `(char-lessp ...)` `(char-greaterp ...)` `(char-not-greaterp ...)` `(char-not-lessp ...)` | case ignored | 1 |
| `(alpha-char-p c)` `(upper-case-p c)` `(lower-case-p c)` `(both-case-p c)` `(alphanumericp c)` `(graphic-char-p c)` | | 1 |
| `(digit-char-p c [radix])` | its weight, or NIL | 1 |
| `(digit-char n [radix])` | | 1 |

## Strings

A string designator -- what the comparisons take -- is a string, a symbol
(its name) or a character. Functions that build a string make it at most
255 characters long.

| Function | | |
|---|---|---|
| `(char s i)` | `setf`-able | core |
| `(string x)` `(stringp x)` | | core |
| `(string= a b)` `(string/= a b)` `(string< a b)` `(string> a b)` `(string<= a b)` `(string>= a b)` | the index where they differ (T for `string=`), or NIL | 1 |
| `(string-equal a b)` `(string-not-equal a b)` `(string-lessp a b)` `(string-greaterp a b)` `(string-not-greaterp a b)` `(string-not-lessp a b)` | case ignored | 1 |
| `(string-upcase s)` `(string-downcase s)` `(string-capitalize s)` | | 1 |
| `(string-trim bag s)` `(string-left-trim bag s)` `(string-right-trim bag s)` | bag: a string or a list of characters | 1 |
| `(make-string n [:initial-element c])` | | 1 |
| `(parse-integer s)` | the number, or NIL | 1 |
| `(prin1-to-string x)` `(princ-to-string x)` `(read-from-string s)` | | 1 |

`subseq`, `concatenate`, `search`, `position`, `remove`... work on
strings (see [Sequences](#sequences)).

## Vectors

| Function | | |
|---|---|---|
| `(make-array n [:initial-element x])` | one dimension | 2 |
| `(vector x...)` | | 2 |
| `(vectorp x)` | | core |
| `(aref v i)` `(svref v i)` | `setf`-able; aref takes strings too | core |

## Structures

    (defstruct point x (y 0))          ; or (defstruct (point option...) slot...)

defines `make-point` (the slots as keys: `(make-point :x 1)`), the
accessors `point-x` and `point-y` (`setf`-able), `point-p` and
`copy-point`. A slot is a name, or `(name default)`. Options:
`(:conc-name prefix)` (`nil` for none), `(:constructor name)`,
`(:predicate name)`, `(:copier name)`. An instance prints as
`#S(POINT 1 0)`. Accessing a slot of the wrong thing is an error. **3**,
on `copy-structure` (**2**).

## Hash tables

| Function | | |
|---|---|---|
| `(make-hash-table &key test size)` | test `eq`, `eql` (the default) or `equal`; size the number of buckets, 16 (they do not grow) | 3 |
| `(gethash key table [default])` | the value and T, or default and NIL; `setf`-able | 2 |
| `(remhash key table)` | | 2 |
| `(clrhash table)` `(maphash f table)` `(hash-table-count table)` `(hash-table-p x)` `(hash-table-test table)` | | 3 |
| `(sxhash x)` | the same for equal objects | 2 |

## Types

All in library ROM 3.

| | |
|---|---|
| `(type-of x)` | `null` `boolean` `fixnum` `single-float` `keyword` `symbol` `cons` `string` `character` `vector` `function`, or a structure's name (`hash-table` for a hash table) |
| `(typep x type)` | a type name: those, and `t` `nil` `integer` `rational` `float` `number` `real` `bit` `list` `atom` `array` `simple-vector` `sequence` `structure-object`, a structure's name, a `deftype`; or a list: `(or ...)` `(and ...)` `(not type)` `(member x...)` `(eql x)` `(satisfies f)` `(mod n)`, `(integer lo hi)` (also `float`, `real`, `number`; `*` for no bound, `(n)` for n itself left out) |
| `(deftype name lambda-list body...)` | a new type name: body returns the type it stands for, `(deftype small () '(integer 0 9))` |
| `(check-type place type)` | an error unless the value is of the type |
| `(typecase key (type form...)... [(otherwise form...)])` | the forms of the first clause whose type key is of; `etypecase`: an error if none fits |

## Input and output

Every printer takes a stream after its object, and every reader a stream
first: a stream from `open` is a file (see *Files*), and string streams
are below. For a printer, nothing or `NIL` means `*standard-output*`,
whose value is `NIL` (the screen) unless you bind it; `T` is the screen.
`(format t ...)` prints to `*standard-output*` too. For a reader, nothing,
`NIL` or `T` is the keyboard. The readers' `eof-error-p` (T) and
`eof-value` (NIL) say what the end of a file gives: an error, or that
value -- `(read-line s nil nil)` is NIL at the end.

| Function | | |
|---|---|---|
| `(print x [stream])` | a new line, x readably, a blank | 1 |
| `(prin1 x [stream])` `(princ x [stream])` | readably / as text | 1 |
| `(terpri [stream])` `(write-char c [stream])` | a new line; a character | 1 |
| `(fresh-line [stream])` | a new line unless at the start of one; T if it was needed | 1 |
| `(write-string s [stream])` `(write-line s [stream])` | s; s and a new line | 1 |
| `(write x)` | as prin1 | 1 |
| `(pprint x [stream])` | broken up to fit the screen (72 columns in a file): code laid out, data (a list that is not a call, anything quoted) filled | 1 |
| `(read [stream eof-error-p eof-value])` | the next object | 1 |
| `(read-line [stream eof-error-p eof-value])` | the next line, a string; from the keyboard with the line editor, ESC breaks | 1 |
| `(read-char [stream eof-error-p eof-value])` | the next character; from the keyboard the next key, waiting for it (`wait-key`) | 1 |
| `(read-char-no-hang [stream ...])` | the same, but NIL if no key is waiting (`inkey`) | 1 |
| `(peek-char [peek-type stream eof-error-p eof-value])` | the next character, left to be read again; peek-type T passes over blanks first (in a file) | 1 |
| `(unread-char c [stream])` | c is the next read | 1 |
| `(listen [stream])` | T if a key is waiting, or the file has more | 1 |
| `(y-or-n-p [message arg...])` `(yes-or-no-p ...)` | asks; T for y, NIL for n | 3 |
| `(format dest control arg...)` | dest `t` (`*standard-output*`: the screen unless bound), `nil` (a string, 255 characters at most) or a stream; the directives below. **Type `~` as CTRL + 2** | 2 |

All output is upper case for symbols. A file being loaded is not
`read`'s input: `(read)` in it reads the keyboard.

**String streams** (**demo** ROM, with the natives in **1**):

| | |
|---|---|
| `(with-output-to-string (var) body...)` | what body prints to var, as a string: `(with-output-to-string (s) (format s "~D-~D" 1 2))` is `"1-2"`. `(with-output-to-string (*standard-output*) ...)` catches what prints without a stream |
| `(make-string-output-stream)` `(get-output-stream-string s)` | the same in two steps; get empties the stream |
| `(with-input-from-string (var string) body...)` | var reads the string: `read`, `read-line`, `read-char`, `peek-char`, `unread-char`, `listen` |
| `(make-string-input-stream string [start])` | |
| `(streamp x)` `(input-stream-p s)` `(output-stream-p s)` `(open-stream-p s)` | for file and string streams |

A string output stream's text is at most 255 characters.

### format directives

A directive is `~`, up to five parameters separated by commas (a number,
`'c` for a character, `V` to take it from the next argument, `#` for how
many arguments are left), the modifiers `:` and `@`, and a letter in
either case.

| Directive | |
|---|---|
| `~A` `~S` | princ / prin1. `~mincol,,,padcharA` pads on the right, `~@A` on the left; `~:A` prints NIL as `()` |
| `~D` `~B` `~O` `~X` | an integer in base 10, 2, 8, 16. `~mincol,padchar,commachar,intervalD`; `~@D` always a sign, `~:D` commas: `(format nil "~:D" 12345)` is `"12,345"`. A whole float (`40000.0`) prints as an integer; anything else as `~A` |
| `~nR` | base n (2-36), then `~D`'s parameters |
| `~R` `~:R` | in words: `"one thousand nine hundred eighty-four"`, `"...eighty-fourth"` |
| `~@R` `~:@R` | Roman numerals (1-3999): `MCMLXXXIV`; old style without IV, IX: `IIII` |
| `~w,d,,,padF` | fixed point, d digits after the point (rounded half up), at least w wide: `(format nil "~8,3F" 2.5)` is `"   2.500"`. Without d as `print` shows it (`7` as `7.0`); `~@F` a sign always |
| `~E` `~G` | as `~F` without d |
| `~d,,w,pad$` | money: `~$` is `~,2F` |
| `~C` | a character; `~@C` as `#\c` |
| `~P` | `s` unless the argument is 1; `~:P` looks at the argument before again (`"~D item~:P"`); `~@P` `y` / `ies` |
| `~%` `~&` `~\|` `~~` | newline, fresh line, page (on the CPC: clears the screen), tilde; `~n%` n of them |
| `~colnum,colincT` | on to column colnum (or past it to the next colinc); `~n@T` n blanks |
| `~n*` `~n:*` `~n@*` | skip n arguments (1), back n (1), go to argument n (0) |
| `~?` `~@?` | the next argument is a control string, its arguments the list after it (`~?`) or the arguments left (`~@?`) |
| `~{...~}` | the body for a list's elements, taking as many as it uses each time: `(format nil "~{~A~^, ~}" '(a b c))` is `"A, B, C"`. `~:{` a list of lists, one each time; `~@{` the arguments left; `~:@{` both; `~n{` at most n times; `~:}` at least once |
| `~[a~;b~;c~]` | clause n, n the argument (or `~n[`); `~:;` before the last makes it the default |
| `~:[false~;true~]` | by whether the argument is NIL |
| `~@[...~]` | if the argument is true, the clause (which then takes it); else nothing |
| `~(...~)` | lower case; `~:(` Each Word Capitalised; `~@(` the first word; `~:@(` UPPER CASE (128 characters at most inside) |
| `~mincol,colinc,minpad,padchar<a~;b~;...~>` | justified: padding between the segments to make mincol, `(format nil "~10<foo~;bar~>")` is `"foo    bar"`; `~:<` pads before the first too, `~@<` after the last; one segment alone goes right (`~10@<x~>` left, `~10:@<x~>` centred). 128 characters at most inside |
| `~^` | stop here if no arguments are left: ends a `~{` iteration (or the whole format) |
| `~` newline | the newline and the blanks after it are left out, to break a long control string; `~:` keeps the blanks, `~@` the newline |

Not there: `~/name/`, `~:C`'s names, `~E`'s exponent form, `~:;` in
`~<` (the line-overflow prefix).

## Files

Through the firmware's cassette vectors, so any disc ROM (AMSDOS,
Parados) -- or the tape. Nothing in it is particular to one disc ROM:
AMSDOS is what the tests use (in MAME, on the 464 and the 6128), and
Parados what the real 464 has. A name without a `.` gets `.LSP`.

| Function | | |
|---|---|---|
| `(load "name")` | reads and evaluates every form in it | 1 |
| `(save "name" [symbol...])` | the symbols' definitions, pretty-printed: functions, macros, variables (as `defparameter`); with none named, everything you defined | 1 |
| `(dir)` | the catalogue | 1 |
| `(delete-file "name")` | through the disc ROM's `|ERA` | 1 |
| `(probe-file "name")` | the name if the file is there, else NIL (the disc ROM says so too) | 3 |

**Streams.** `(open "name" [:direction :input or :output])` opens a file
and gives a stream for the printers and readers above (and `format`);
`(close stream)` closes it (T, or NIL if it was closed). Better,
`with-open-file` closes it however its body is left -- an error or ESC
too:

    (with-open-file (out "notes" :direction :output)
      (format out "~{~A~%~}" '(one two three)))
    (with-open-file (in "notes")
      (loop (let ((line (read-line in nil nil)))
              (if line (print line) (return)))))

One file can be open for input and one for output at a time (the
firmware's): `load` or a second input file while one is open is an
error. A file open for output is only complete once closed. Also
`(streamp x)`, `(open-stream-p s)`, `(input-stream-p s)`,
`(output-stream-p s)`. A stream prints as `#S(FILE-STREAM "notes"
:OUTPUT T)` (the last: open). **3**, the printers and readers **1**.

**The RAM disc** (a 6128, or a CPC with 64 KB more): names starting
`M:` are kept in the second 64 KB -- `(save "m:work")`, `(load "m:work")`,
`(dir "m:")`, `(delete-file "m:work")`. 63 files, 63 KB; they survive a
reset, not a power-off. On a 464 without a RAM expansion, `M:` says there
is none.

## The text screen

| Function | | |
|---|---|---|
| `(mode n)` | 0 (20 columns, 16 colours), 1 (40, 4), 2 (80, 2); clears | 1 |
| `(cls)` | | 1 |
| `(locate column row)` | from 1 | 1 |
| `(pen n)` `(paper n)` | | 1 |
| `(ink pen colour [colour2])` | colours 0-26; two flash | 1 |
| `(border colour [colour2])` | | 1 |
| `(flash-speed on off)` | in 1/50 s (SPEED INK) | 1 |
| `(window left right top bottom)` | the text window, from 1 | 1 |
| `(text-cursor)` | `(column row)` | 1 |
| `(transparent on)` | T: text without its paper | 1 |
| `(tag on)` | T: text at the graphics cursor | 1 |

## Graphics

Coordinates are 0-639 across and 0-399 up, whatever the mode -- the
firmware's own, as in BASIC. The screen has 200 rows of pixels, so a
pixel is two units high (y 100 and 101 are the same row), and one unit
wide in mode 2, two in mode 1, four in mode 0. So a picture comes out
the same in every mode, and a circle round. A `pen` argument sets the
graphics pen first; it stays set.

| Function | | |
|---|---|---|
| `(plot x y [pen])` `(plotr dx dy [pen])` | | 1 |
| `(draw x y [pen])` `(drawr dx dy [pen])` | a line from the graphics cursor | 1 |
| `(move x y)` `(mover dx dy)` | | 1 |
| `(test x y)` `(testr dx dy)` | the pen of a pixel | 1 |
| `(xpos)` `(ypos)` | the graphics cursor | 1 |
| `(origin x y)` | | 1 |
| `(clg [paper])` | clears the graphics window | 1 |
| `(graphics-pen n)` `(graphics-paper n)` | | 1 |
| `(circle x y r [pen])` | | 1 |
| `(disc x y r [pen])` | filled | 1 |
| `(box x1 y1 x2 y2 [pen])` | the edges | 1 |
| `(fill-box x1 y1 x2 y2 [pen])` | filled | 1 |
| `(ink-mode n)` | 0 normal, 1 XOR, 2 AND, 3 OR. A disc or a box drawn twice with XOR is gone again | 1 |
| `(flood-fill x y [pen])` | the area around (x, y) of its colour, up to any other colour, painted with pen -- a paint bucket, the same on every CPC (BASIC 1.1's FILL stops only at the pen's colour). A whole screen in mode 1 takes about half a minute | 1 |
| `(symbol code row...)` | character code 240-255 drawn from up to eight rows, top first, each a byte (`#b00111100`): BASIC's SYMBOL, with SYMBOL AFTER 240 | 1 |

## Turtle graphics

Logo's turtle: it starts in the middle of the screen facing up; headings
are degrees, 0 up, clockwise. It draws with the graphics pen.

| Function | | |
|---|---|---|
| `(forward n)` `(back n)` | moves, drawing if the pen is down | 1 |
| `(left degrees)` `(right degrees)` | turns | 1 |
| `(pen-up)` `(pen-down)` | | 1 |
| `(home)` | the middle, facing up (draws nothing) | 1 |
| `(set-position x y)` `(set-heading degrees)` | (draw nothing) | 1 |
| `(turtle-position)` `(heading)` | `(x y)`, degrees | 1 |

Its position is kept to 1/256, so thousands of short steps do not drift:
`(dotimes (i 360) (forward 2) (right 1))` comes back where it started.
`(koch 4)` and `(tree)` in the demos are turtle programs.

## Sound and music

| Function | | |
|---|---|---|
| `(sound channels period [duration [volume [envelope [tone-envelope [noise]]]]])` | BASIC's SOUND: channels 1 A, 2 B, 4 C (added for more), period 0-4095, duration in 1/100 s (20), volume 0-15 (12); waits if the queue is full | 1 |
| `(envelope n count step pause...)` | volume envelope 1-15, up to five sections (ENV) | 1 |
| `(tone-envelope n count step pause...)` | tone envelope 1-15; a negative n repeats (ENT) | 1 |
| `(release channels)` | | 1 |
| `(sound-check channel)` | the queue's state (SQ) | 1 |
| `(sound-hold)` `(sound-continue)` | | 1 |
| `(note 'c4)` | the period of a note: a letter, `#` (sharp) or `B` (flat), the octave. The AY runs at 1 MHz, period = 62500 / frequency: C4 (middle C) is 239, A4 (440 Hz) 142 | 3 |
| `(play notes [duration [channels [volume]]])` | `notes` like `'(c4 e4 g4 (c5 40) r c5)`: `R` a rest, a list a note with its own duration | 3 |

## The LambdaSpeak card: speech and PlayCity

| Function | | |
|---|---|---|
| `(say text)` | the card speaks it in DECtalk; Lisp goes on meanwhile, and a second line waits its turn. DECtalk's inline commands work: `[:phoneme arpabet speak on]` and `[ax<300,25>]` (300 ms at pitch 25, C4) sing | 2 |
| `(speech-stop)` | | 2 |
| `(speech-voice n)` | 1 Paul, 2 Harry, 3 Betty, 4 Ursula, 5 Dennis, 6 Kit, 7 Frank, 8 Rita, 9 Wendy; 0 the default | 2 |
| `(speech-rate n)` `(speech-volume n)` | 0-15, 0 the default | 2 |
| `(playcity on)` | T: the card's PlayCity on, at the CPC's pitch, silent; NIL off. A real PlayCity needs no switching on, and takes no harm | 2 |
| `(pc-tone channel period [volume])` | channel 0-5 (0-2 the right chip, 3-5 the left) plays period (as `sound`'s: `(note 'a4)`) at volume 0-15 (12) until changed; volume 0 is silence | 2 |
| `(pc-off)` | all six silent | 2 |

Without the card these do nothing (the bytes go to a port nobody answers).

## Keys, time and the machine

| Function | | |
|---|---|---|
| `(inkey)` | the next character typed, or NIL | 1 |
| `(wait-key)` | the next character typed, waiting for it | 1 |
| `(key-down-p key)` | T while a key is held; key numbers as BASIC's INKEY (cursor up 0, right 1, down 2, left 8, COPY 9, SPACE 47...) | 1 |
| `(joystick [n])` | 1 up, 2 down, 4 left, 8 right, 16 fire 2, 32 fire 1, added | 1 |
| `(frame)` | waits for the next frame, 1/50 s | 1 |
| `(time)` | the firmware's clock, 1/300 s, modulo 16384 | 1 |
| `(peek address)` `(poke address byte)` | RAM, all 64 KB (`#xC000` is the screen); an address past 16383 is a float, which is fine | 1 |
| `(gc)` | collects; the cells free | core |
| `*features*` | `(:cpc :cpc-lisp)` on a CPC, `(:trs-80 :cpc-lisp)` on a TRS-80 | 1 |
| `(room)` | cells, symbols and string space free | 2 |
| `(reset)` | the machine, as at power-up | 1 |

## The demos

The demo ROM: `(demo)` lists them. `(shapes)` `(rose [k])` `(spiral)`
`(moire)` `(bounce)` `(sierpinski [n])` `(sketch)` `(koch [level])`
`(tree [level])` `(tune)` `(talk)` `(sing)` `(chords)` `(hanoi n)`
`(queens n)` `(primes n)` `(fact n)`. A key ends a picture.
They are Lisp text, so `(ed 'rose)` shows one.

## Memory

About 6660 cells of four bytes (conses and objects) on a 464, 6400 on a
6128 (its disc ROM takes some RAM), 512 symbols, and string space --
strings, vectors, floats, symbols' names: 5.5-5.8 KB -- between them and
the stack; `(room)` says what is free. A file open takes 2 KB of the
string space while it is open (two files, 4 KB).
The garbage collector runs when cells run out. Functions written in Lisp
in the library ROMs are read from ROM the first time they are called and
then use cells like your own; the names cost nothing until then. A
compiled function takes far less than its interpreted definition (whose
cells go back): its bytecode and constants are in string space. The
compiler costs about forty symbols the first time it runs, its working
memory only while it does.

## Differences from Common Lisp

- Integers are 15-bit fixnums; there are no bignums or ratios (`/` of
  integers gives a float unless it is whole). Floats are about nine
  digits.
- Symbols print upper case only (`*print-case*` is not there).
- No packages; one name space of symbols.
- A condition is its message, a string; there are no condition classes,
  `handler-bind` or restarts. ESC, running out of memory and stack
  overflow are never caught.
- `search`, `remove-duplicates`, `every`/`some` and `map` do not take
  `:start`/`:end`/`:from-end`; `delete` and friends are not destructive.
- Hash tables do not grow their buckets.
- Strings that functions build are at most 255 characters.
- Multi-dimensional arrays, `*standard-input*`,
  `*terminal-io*` and CLOS are not there; `*standard-output*` is NIL for
  the screen, not a stream object. One file is open for input
  and one for output at most.
- A macro call keeps its first expansion (displacing): a macro that
  expands differently each time -- reading a global, say -- is not
  expanded again.
- A compiled function prints as `#<FUNCTION>`; `ed` cannot show it and
  `save` leaves it out (`compile-file` the source instead). A `.FAS`
  file holds bytecode: compile it again after a new VM ROM.
