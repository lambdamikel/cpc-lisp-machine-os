# CPC Lisp 0.9 -- a tour

*A Lisp machine for the Amstrad CPC*

This is a walk through CPC Lisp at the keyboard: first the language, then
what makes it a CPC language -- the screen, graphics, the turtle, keys,
sound, speech, files -- and the compiler. Everything here can be typed
as it stands, and was checked on the machine. The
[reference](reference.md) has every function; the
[README](../README.md#installing-the-roms) says how to install the ROMs.

Two keys first. **ESC** stops whatever is running and comes back to
`LISP>`. The CPC has no tilde key, and `format` needs one: **CTRL + 2**
types `~`. (On a TRS-80: SHIFT down-arrow, then `-`.)

## 1. First steps

When the CPC is switched on it says

    CPC Lisp 0.9
    A Lisp machine for the Amstrad CPC
    library ROMs 4 5 6 3
    6402 cells free
    LISP>

Type an expression and RETURN; the value comes back:

    LISP> (+ 1 2)
    3
    LISP> (defun square (x) (* x x))
    SQUARE
    LISP> (square 12)
    144
    LISP> (mapcar #'square '(1 2 3 4 5))
    (1 4 9 16 25)

It is Common Lisp: `defun`, `let`, `lambda`, closures, `loop`, `format`,
structures, hash tables. Integers go from -16384 to 16383; past that a
result becomes a float:

    LISP> (* 200 200)
    40000.0
    LISP> (sqrt 2)
    1.41421356

`*` is the last value printed (`**`, `***` the ones before). A mistake
prints `Error:` and what it is about, and you are back at `LISP>`:

    LISP> (car 5)
    Error: not a list: 5

`(loop)` runs for ever -- try it, then ESC.

## 2. The editors

The **line editor** helps with the parentheses. When you type a `)` the
cursor jumps to its `(` for a moment (a beep if there is none). RETURN on
an unfinished expression asks for the next line, indented as Lisp
indents. **↑** brings back the last line; SHIFT + the arrows move the copy
cursor, and **COPY** copies from under it, as in BASIC.

The **function editor** shows a definition on the whole screen:

    LISP> (ed 'square)

The arrow keys move (SHIFT + ↑ ↓ a page), typing inserts, DEL deletes.
**COPY** (or CTRL + S) reads it all back in and evaluates it; **ESC**
leaves the function as it was. `(ed)` opens the last text again -- handy
after an error in it.

## 3. Saving your work

    LISP> (save "work")
    (SQUARE)
    LISP> (dir)
    LISP> (load "work")
    T

`save` writes everything you have defined -- functions, macros,
variables -- pretty-printed, to `WORK.LSP` (a name without a `.` gets
`.LSP`); `(save "work" 'square)` writes just those named. `load` reads a
file back. This goes through the disc ROM -- AMSDOS or Parados -- so it
works with any drive the CPC has.

A 6128, or a CPC with a RAM expansion, also has a **RAM disc**, `M:`:
`(save "m:work")`, `(load "m:work")`, `(dir "m:")`. It is fast and survives
a reset, but not switching off.

## 4. The text screen

`(mode n)` sets the screen mode, as in BASIC: 0 has 20 columns and 16
colours, 1 has 40 and 4, 2 has 80 and 2. It clears the screen.
`(ink pen colour)` says which of the 27 colours (0-26) a pen shows,
`(pen n)` and `(paper n)` choose the pens for text, `(border colour)` the
border, `(locate column row)` places the cursor (from 1), `(cls)` clears.

    (mode 1)
    (border 0) (ink 0 0) (ink 1 24) (ink 2 6) (ink 3 18)
    (progn (cls) (locate 14 12) (pen 2) (princ "Hello, CPC!") (pen 1))

Black paper, then yellow, red and green pens: the greeting is red in the
middle of the screen. Why the `progn`? After each form the REPL prints
its value on a new line, so a `locate` typed on its own is undone at once:
whatever arranges the screen goes in one form, or in a function.
`(ink 1 26 0)` makes pen 1 flash between two colours.

`(window left right top bottom)` keeps text to part of the screen. Before
drawing, `(window 1 40 21 25)` is useful: you type in the bottom five
lines, and the picture above is not scrolled away. `(mode 1)` gives the
whole screen back.

## 5. Graphics

The graphics screen is 640 by 400, whatever the mode, with (0, 0) at the
bottom left -- as in BASIC. These are the firmware's units, not pixels:
there are 200 rows of pixels, two units each, and 160, 320 or 640 pixels
across in modes 0, 1 and 2. A picture comes out the same in every mode,
and a circle round. Each drawing function takes a pen last; it
stays set for the next one. In mode 1 the pens start as yellow (1), cyan
(2) and red (3) on blue.

    (mode 1) (window 1 40 21 25) (cls)
    (plot 320 200 1)                   ; a point
    (move 0 0) (draw 639 399 2)        ; a line across
    (circle 320 200 150 3)             ; a circle
    (disc 320 200 60 2)                ; a filled one
    (box 20 20 200 120 1)              ; a frame
    (fill-box 440 20 620 120 3)        ; a block

`drawr`, `plotr` and `mover` go relative to where the last one ended.
`(test x y)` tells the pen of a pixel, `(clg)` clears the graphics.
`(flood-fill x y pen)` paints the area around a point, up to any other
colour -- a paint bucket:

    (clg)
    (circle 320 200 100 1)
    (flood-fill 320 200 2)

**XOR**: after `(ink-mode 1)` everything is drawn by XOR, and drawing a
thing twice takes it away again -- the trick for moving things without
spoiling what is under them. `(ink-mode 0)` is normal drawing again.

    (ink-mode 1)
    (fill-box 100 100 300 300 3)
    (fill-box 100 100 300 300 3)       ; gone again
    (ink-mode 0)

A small program, a star with floats -- `sin` and `cos` take radians:

    (defun star (x y r n)
      (move (+ x r) y)
      (dotimes (i (1+ n))
        (let ((a (/ (* i 4 pi) n)))
          (draw (+ x (* r (cos a))) (+ y (* r (sin a))) 2))))

    (clg) (star 320 200 180 5)

**Characters of your own**: `(symbol code row...)` redefines one of the
characters 240-255 from eight rows of bits, top first, as BASIC's
SYMBOL:

    (symbol 240 #b00111100 #b01000010 #b10100101 #b10000001
                #b10100101 #b10011001 #b01000010 #b00111100)
    (princ (code-char 240))            ; a smiley

`(tag t)` makes text go to the graphics cursor instead, for labels
anywhere on the screen; `(tag nil)` puts it back.

## 6. The turtle

Logo's turtle draws as it moves. It starts in the middle facing up;
`forward`, `back`, `left` and `right` move and turn it (degrees),
`pen-up` and `pen-down` stop and start it drawing.

    (mode 1) (window 1 40 21 25) (home)
    (dotimes (i 4) (forward 100) (right 90))          ; a square

    (defun polygon (sides size)
      (dotimes (i sides) (forward size) (right (/ 360 sides))))

    (dotimes (i 12) (polygon 6 50) (right 30))         ; a flower

    (clg) (home)
    (dotimes (i 90) (forward (* i 3)) (right 91))      ; a spiral

`(set-position x y)` and `(set-heading degrees)` place it without
drawing, `(turtle-position)` and `(heading)` say where it is. Its
position is kept to a 256th of a pixel, so many small steps come back
where they started. `(koch 4)` and `(tree)` in the demos are turtle
programs; `(ed 'koch)` shows how, and `(ed '%koch-side)` the recursive
part that draws a side. (A name starting with `%` is a helper of the
system's: an ordinary function, named so as not to collide with yours.)

## 7. Keys, time and moving things

`(inkey)` gives the next key typed, or NIL if there is none; `(wait-key)`
waits for one. For games, `(key-down-p n)` is T while key n is held, by
BASIC's INKEY numbers: cursor up 0, right 1, down 2, left 8, COPY 9,
SPACE 47. `(joystick)` adds up 1 up, 2 down, 4 left, 8 right, 16 and 32
the fire buttons. `(frame)` waits for the next frame, a fiftieth of a
second: what keeps a moving thing smooth.

A disc to steer with the cursor keys, drawn by XOR: the new one is drawn,
then the old one again, which takes it away. SPACE ends it.

    (defun steer ()
      (mode 1) (cls) (ink-mode 1)
      (let ((x 320) (y 200))
        (disc x y 12 2)
        (loop
          (when (key-down-p 47) (return))
          (let ((nx x) (ny y))
            (when (key-down-p 8) (decf nx 4))
            (when (key-down-p 1) (incf nx 4))
            (when (key-down-p 0) (incf ny 4))
            (when (key-down-p 2) (decf ny 4))
            (unless (and (= nx x) (= ny y))
              (frame)
              (disc nx ny 12 2)
              (disc x y 12 2)
              (setq x nx y ny)))))
      (ink-mode 0)
      (loop (unless (inkey) (return))))

The last line throws away the keys typed meanwhile, so they do not turn
up at `LISP>`. `(time)` is the firmware's clock, in 300ths of a second.

## 8. Sound

`(sound channels period duration volume)` is BASIC's SOUND. Channel 1 is
A, 2 is B, 4 is C (add them for more than one); the period sets the
pitch (a bigger number is lower); the duration is in hundredths of a
second, the volume 0-15. `(note 'a4)` gives a note's period -- C4 is
middle C, `#` a sharp and `B` a flat (`'f#4`, `'bb3`):

    (sound 1 (note 'a4) 100 12)                ; A for a second
    (sound 1 (note 'c4) 100) (sound 2 (note 'e4) 100) (sound 4 (note 'g4) 100)

The last line plays a C major chord: each channel has its own queue, and
they sound together. `(play notes)` plays a tune; a note in a list has its
own duration, `R` is a rest:

    (play '(c4 e4 g4 (c5 40) r (g4 10) (c5 60)))

An **envelope** shapes the volume: `(envelope 1 15 -1 3)` makes envelope
1 fall a step every 3/100 s, fifteen times -- a plucked string. Give its
number after the volume:

    (sound 1 (note 'c4) 50 15 1)

`(tune)` in the demos plays Ode to Joy that way. `tone-envelope` shapes
the pitch (BASIC's ENT); `(release channels)`, `(sound-hold)` and
`(sound-continue)` work the queues.

## 9. Speech, PlayCity and MIDI

With the LambdaSpeak card, `say` speaks, and Lisp goes on meanwhile:

    (say "Hello. I am a Lisp machine.")
    (speech-voice 3) (say "And I am Betty.")
    (sing)

There are nine voices (`speech-voice` 1-9); `speech-rate` and
`speech-volume` take 0-15. DECtalk's own commands work in the text --
`(ed 'sing)` shows a song written in its phonemes.

The card's **PlayCity** adds six channels of its own. `(playcity t)`
switches it on, `(pc-tone channel period volume)` holds a note on one of
them (0-5) until changed, `(pc-off)` silences them all:

    (playcity t)
    (pc-tone 0 (note 'c4) 12) (pc-tone 1 (note 'e4) 12) (pc-tone 2 (note 'g4) 12)
    (pc-off)

`(chords)` in the demos plays six-note chords that way. Without the card
all these simply do nothing.

**MIDI**: with a synthesizer on the card's MIDI OUT (or MIDI/80's, on a
TRS-80), `midi-note` plays a note -- channel, note (60 is middle C),
velocity, and a duration in 1/100 s if it should end by itself:

    (midi-program 1 20)                        ; a church organ
    (dolist (n '(60 64 67 72)) (midi-note 1 n 100 40))
    (midi-note 1 48 90) (midi-note 1 48 0)     ; on, and off
    (midi-tune)                                ; the demo: a minuet

`(ed 'midi-tune)` shows how two voices are kept in time. The card is in
its MIDI mode while it plays; `say` takes it out again by itself.

## 10. Files as streams

Every printer takes a stream, and every reader. `with-open-file` opens a
file for the length of its body, and closes it however the body ends:

    (with-open-file (out "notes" :direction :output)
      (format out "~{~A~%~}" '(one two three)))

    (with-open-file (in "notes")
      (loop for line = (read-line in nil nil)
            while line collect line))

The second gives `("ONE" "TWO" "THREE")`: `read-line` with NIL, NIL
answers NIL at the end of the file instead of an error. One file can be
open for reading and one for writing at a time. Strings work as streams
too: `(with-output-to-string (s) (format s "~D-~D" 1 2))` is `"1-2"`.

## 11. The compiler

`compile` turns a function into bytecode for the VM ROM, three to nine
times faster:

    LISP> (defun fib (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
    FIB
    LISP> (fib 17)                    ; about 13 seconds
    1597
    LISP> (compile 'fib)
    FIB
    LISP> (fib 17)                    ; about 4
    1597
    LISP> (disassemble 'fib)

Compiled and interpreted functions call each other, so compile what is
slow and leave the rest. A whole file at once:

    LISP> (compile-file "work")
    ;; 1 compiled
    "work.FAS"
    LISP> (load "work.fas")
    T

`load` then brings the functions back compiled, without compiling again.
A compiled function cannot be shown by `ed` -- keep the source.

## 12. Where next

`(demo)` lists the demo programs: `(rose)`, `(bounce)`, `(sketch)`,
`(koch 4)`, `(tune)`, `(queens 6)`... They are Lisp, read from ROM the
first time they run, and `(ed 'bounce)` shows how each is written -- the
best examples there are of everything above. The
[reference](reference.md) has the rest; [the design](design.md) how it is
made.
