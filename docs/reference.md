# CPC Lisp reference

CPC Lisp 0.3 -- a Common Lisp dialect in ROM for the Amstrad CPC 464, 664
and 6128. This manual lists everything built in. Where CPC Lisp follows
Common Lisp the descriptions are short; where it differs, it says so (and
[Differences from Common Lisp](#differences-from-common-lisp) collects
them).

Each function is marked with where it lives: **core** (the core ROM),
**1**, **2**, **3** (the library ROMs) or **demo**. A library ROM can be
left out; its functions are then undefined, and everything else works.

Contents: [Starting](#starting) · [The REPL](#the-repl) ·
[The editors](#the-editors) · [Syntax](#syntax) ·
[Data types](#data-types) · [Evaluation](#evaluation) ·
[Special forms](#special-forms) · [Macros](#macros) ·
[Functions and evaluation](#functions-and-evaluation) ·
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

    CPC Lisp 0.3, library ROMs 4 5 6 3
    6853 cells free
    LISP>

The numbers are the ROMs where the library parts were found. At any other
ROM number, `|LISP` from BASIC starts it.

## The REPL

Type an expression and RETURN. Its values are printed, one a line; an
expression may run over several lines (the next is asked for until the
parentheses balance).

- `*`, `**`, `***` hold the last three values printed (the first of each).
- An error prints `Error:`, a message and the object it is about, and comes
  back to `LISP>`. Open files are abandoned, and special variables bound
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

Not read: `#S(...)` (printed, not read back), `|odd symbols|`, `#.`, `#+`.

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
| symbol | 512 at most (about 150 are built in); keywords are symbols |
| cons, list | `NIL` is the empty list and false |
| vector | one-dimensional, any objects |
| structure | `defstruct`; prints as `#S(POINT 1 2)` |
| hash table | a structure, `#S(HASH-TABLE ...)` |
| function | built in (`#<SUBR CAR>`), closure, or Lisp text not read yet (autoload) |

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
| `(unwind-protect form cleanup...)` | the cleanups run when throw or return-from passes; not on an error or ESC |
| `(dolist (var list [result]) body...)` | |
| `(dotimes (var n [result]) body...)` | |
| `(loop body...)` | for ever, until `return` |
| `(declare ...)` | ignored |
| `(the type form)` | the form |
| `(multiple-value-list form)` | all of form's values, as a list |

## Macros

| Macro | | |
|---|---|---|
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
| `(error x...)` | prints `Error:` and its arguments (`princ`, blanks between), back to `LISP>` | core |

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
| `(nconc list...)` `(copy-list l)` `(make-list n [x])` `(butlast l [n])` | | 3 |
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
| `(char-code c)` `(code-char n)` `(characterp x)` | | core |
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
| `(make-array n [:initial-element x])` | one dimension | core |
| `(vector x...)` `(vectorp x)` | | core |
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

`(type-of x)` (`fixnum`, `single-float`, `symbol`, `null`, `cons`,
`string`, `character`, `vector`, `function`, a structure's name);
`(typep x type)` for those and `integer`, `float`, `number`, `keyword`,
`list`, `atom`, `t`, `nil` (**3**).

## Input and output

| Function | | |
|---|---|---|
| `(print x)` | a new line, x readably, a blank | core |
| `(prin1 x)` `(princ x)` | readably / as text | core |
| `(terpri)` `(write-char c)` | | core |
| `(pprint x)` | broken up to fit the screen | 1 |
| `(read)` | the next object typed | core |
| `(format dest control arg...)` | dest `t` (the screen) or `nil` (a string); `~A` `~S` `~D` `~C` `~%` `~&` `~~`, a width: `~5D` pads on the left, `~8A` on the right. **Type `~` as CTRL + 2** | 2 |

All output is upper case for symbols.

## Files

Through the firmware's cassette vectors, so any disc ROM (AMSDOS,
Parados) -- or the tape. A name without a `.` gets `.LSP`.

| Function | | |
|---|---|---|
| `(load "name")` | reads and evaluates every form in it | 1 |
| `(save "name" [symbol...])` | the symbols' definitions, pretty-printed: functions, macros, variables (as `defparameter`); with none named, everything you defined | 1 |
| `(dir)` | the catalogue | 1 |
| `(delete-file "name")` | through the disc ROM's `|ERA` | 1 |

**The RAM disc** (a 6128, or a CPC with 64 KB more): names starting
`M:` are kept in the second 64 KB -- `(save "m:work")`, `(load "m:work")`,
`(dir "m:")`, `(delete-file "m:work")`. 63 files, 63 KB; they survive a
reset, not a power-off. On a 464, `M:` says there is none.

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

Coordinates are 0-639 across and 0-399 up, whatever the mode, as in
BASIC. A `pen` argument sets the graphics pen first; it stays set.

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
| `(room)` | cells, symbols and string space free | 2 |
| `(reset)` | the machine, as at power-up | 1 |

## The demos

The demo ROM: `(demo)` lists them. `(shapes)` `(rose [k])` `(spiral)`
`(moire)` `(bounce)` `(sierpinski [n])` `(sketch)` `(koch [level])`
`(tree [level])` `(tune)` `(talk)` `(sing)` `(chords)` `(hanoi n)`
`(queens n)` `(primes n)` `(fact n)`. A key ends a picture.
They are Lisp text, so `(ed 'rose)` shows one.

## Memory

About 6800-7100 cells of four bytes (conses and objects), 512 symbols,
and string space between them and the stack; `(room)` says what is free.
The garbage collector runs when cells run out. Functions written in Lisp
in the library ROMs are read from ROM the first time they are called and
then use cells like your own; the names cost nothing until then.

## Differences from Common Lisp

- Integers are 15-bit fixnums; there are no bignums or ratios (`/` of
  integers gives a float unless it is whole). Floats are about nine
  digits.
- Symbols print upper case only (`*print-case*` is not there).
- No packages; one name space of symbols.
- `error` prints its arguments; it does not take a format string, and
  there are no conditions (`handler-case`, `restart`...).
- `search`, `remove-duplicates`, `every`/`some` and `map` do not take
  `:start`/`:end`/`:from-end`; `delete` and friends are not destructive.
- Hash tables do not grow their buckets.
- Strings that functions build are at most 255 characters.
- Multi-dimensional arrays, `loop` with keywords (the extended LOOP),
  `format` directives beyond `~A ~S ~D ~C ~% ~& ~~`, streams, and CLOS are
  not there.
- A macro call keeps its first expansion (displacing): a macro that
  expands differently each time -- reading a global, say -- is not
  expanded again.
- `unwind-protect`'s cleanups do not run on an error or ESC.
