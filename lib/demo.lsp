;;; CPC Lisp -- the demo ROM: programs to try, and to read. (demo) lists
;;; them. Each is read from this ROM the first time it is called, as the
;;; library's Lisp functions are; (ed 'rose) shows how one is written.

(defun demo ()
  (format t "~%CPC Lisp demos:~%~%")
  (dolist (d '(("(shapes)" "discs and boxes in colours")
               ("(rose)" "a rose curve, in floats")
               ("(spiral)" "a square spiral")
               ("(moire)" "lines drawn with XOR")
               ("(bounce)" "a ball: a key stops it")
               ("(sierpinski)" "the chaos game")
               ("(sketch)" "cursors draw, COPY, SPACE" :cpc)
               ("(sketch)" "arrows draw, CLEAR, SPACE" :trs-80)
               ("(koch 4)" "a Koch snowflake, turtle")
               ("(tree)" "a tree, by turtle")
               ("(tune)" "Ode to Joy")
               ("(midi-tune)" "a minuet, out of MIDI OUT")
               ("(talk)" "speech: LambdaSpeak, Talker/80")
               ("(sing)" "singing: LambdaSpeak, Talker/80")
               ("(chords)" "PlayCity's six voices" :cpc)
               ("(hanoi 4)" "the towers of Hanoi")
               ("(queens 6)" "n queens on a board")
               ("(primes 100)" "a sieve")
               ("(fact 20)" "20!, as a float")))
    (when (or (null (cddr d)) (member (caddr d) *features*))
      (format t "~13A~A~%" (car d) (cadr d))))
  (format t "~%A key ends a picture.~%(ed 'rose) shows how one is written.~%")
  t)

;; the screen as it was at the start, and no keys left over: what the
;; cursor keys typed while key-down-p watched them would go to the editor
(defun %restore ()
  (ink-mode 0) (mode 1) (border 1)
  (ink 0 1) (ink 1 24) (ink 2 20) (ink 3 6)
  (loop (unless (inkey) (return)))
  t)

;; wait for a key, then the screen back
(defun %again () (wait-key) (%restore))

;; black paper, yellow, red and green pens
(defun %dark (m)
  (mode m) (border 0) (ink 0 0) (ink 1 24) (ink 2 6) (ink 3 18) (cls))

(defun shapes ()
  (mode 0) (border 0) (ink 0 0)
  (let ((i 1))
    (dolist (c '(1 2 3 6 9 11 15 18 20 24 25 26 17 13 4))
      (ink i c)
      (incf i)))
  (dotimes (i 15) (disc 320 200 (* (- 15 i) 12) (%pen (1+ i))))
  (dotimes (i 8)
    (fill-box (* i 80) 0 (+ (* i 80) 72) 40 (%pen (1+ i)))
    (fill-box (* i 80) 360 (+ (* i 80) 72) 399 (%pen (- 15 i))))
  (%again))

;; a pen: on a screen with one colour, every other one is the paper's
(defun %pen (n) (if (member :trs-80 *features*) (logand n 1) n))

;; r = sin(k a), drawn with floats, a colour for each stretch
(defun rose (&optional (k 5))
  (%dark 1)
  (dotimes (i 181)
    (let* ((a (/ (* i pi) 90))
           (r (* 190 (sin (* k a))))
           (x (+ 320 (* r (cos a))))
           (y (+ 200 (* r (sin a)))))
      (if (= i 0) (move x y) (draw x y (1+ (mod (floor i 20) 3))))))
  (%again))

(defun spiral ()
  (%dark 1)
  (move 320 200)
  (do ((i 0 (1+ i)) (d 4 (+ d 4))) ((> d 400))
    (let ((p (1+ (mod (floor i 4) 3))))
      (case (mod i 4)
        (0 (drawr d 0 p))
        (1 (drawr 0 d p))
        (2 (drawr (- d) 0 p))
        (t (drawr 0 (- d) p)))))
  (%again))

;; two fans of lines; where they cross, XOR makes the pattern
(defun moire ()
  (mode 2) (border 0) (ink 0 0) (ink 1 26) (cls)
  (ink-mode 1)
  (do ((x 0 (+ x 6))) ((> x 639)) (move 320 0) (draw x 399 1))
  (do ((y 0 (+ y 4))) ((> y 399)) (move 0 200) (draw 639 y 1))
  (%again))

;; drawn with XOR: drawing the ball again takes it off. The new one is
;; drawn before the old one goes, so it never vanishes.
(defun bounce ()
  (%dark 1)
  (box 0 0 639 399 1)
  (ink-mode 1)
  (let ((x 100) (y 300) (dx 10) (dy -8))
    (disc x y 16 2)
    (loop (when (inkey) (return))
          (let ((nx (+ x dx)) (ny (+ y dy)))
            (when (or (< nx 20) (> nx 619)) (setq dx (- dx)) (sound 1 200 2))
            (when (or (< ny 20) (> ny 379)) (setq dy (- dy)) (sound 1 300 2))
            (frame)
            (disc nx ny 16 2)
            (disc x y 16 2)
            (setq x nx y ny))))
  (%restore))

;; half way towards a corner picked at random, again and again
(defun sierpinski (&optional (n 3000))
  (%dark 1)
  (let ((x 320) (y 200) (corners '((320 390 1) (20 10 2) (620 10 3))))
    (dotimes (i n)
      (let ((c (nth (random 3) corners)))
        (setq x (ash (+ x (car c)) -1) y (ash (+ y (cadr c)) -1))
        (plot x y (caddr c)))))
  (%again))

;; key numbers: cursor up 0, right 1, down 2, left 8, COPY 9, SPACE 47
(defun sketch ()
  (%dark 1)
  ;; the keys' numbers: stop, next pen, up, down, right, left
  (let ((x 320) (y 200) (p 1)
        (k (if (member :trs-80 *features*)
               '(55 49 51 52 54 53)     ; SPACE, CLEAR, the arrows
               '(47 9 0 2 1 8))))       ; SPACE, COPY, the cursor keys
    (loop (when (key-down-p (first k)) (return))
          (when (key-down-p (second k))
            (setq p (1+ (mod p 3)))
            (loop (unless (key-down-p (second k)) (return))))
          (when (key-down-p (third k)) (setq y (min 399 (+ y 2))))
          (when (key-down-p (fourth k)) (setq y (max 0 (- y 2))))
          (when (key-down-p (nth 4 k)) (setq x (min 639 (+ x 2))))
          (when (key-down-p (nth 5 k)) (setq x (max 0 (- x 2))))
          (plot x y p)))
  (%restore))

;; Turtle graphics (forward, left, right... are in library 1). A Koch
;; curve: a side is four sides a third as long, the middle two a bump.
;; 324 divides by 3 to level 4 exactly.
(defun %koch-side (len level)
  (if (= level 0)
      (forward len)
      (let ((l (floor len 3)) (n (1- level)))
        (%koch-side l n) (left 60)
        (%koch-side l n) (right 120)
        (%koch-side l n) (left 60)
        (%koch-side l n))))

(defun koch (&optional (level 3))
  (%dark 1)
  (pen-up) (set-position 158 293) (set-heading 90) (pen-down)
  (graphics-pen 1)
  (dotimes (i 3)
    (%koch-side 324 level)
    (right 120)
    (graphics-pen (+ i 2)))
  (%again))

;; a branch, and two smaller ones from its end, each turned 25 degrees
(defun %branch (len level)
  (when (> level 0)
    (graphics-pen (1+ (mod level 3)))
    (forward len)
    (left 25)
    (%branch (floor (* len 3) 4) (1- level))
    (right 50)
    (%branch (floor (* len 3) 4) (1- level))
    (left 25)
    (pen-up) (back len) (pen-down)))

(defun tree (&optional (level 8))
  (%dark 1)
  (pen-up) (set-position 320 10) (set-heading 0) (pen-down)
  (%branch 90 level)
  (%again))

;; Beethoven, with a volume envelope that dies away
(defun tune ()
  (envelope 1 15 -1 3)
  (dolist (n '(e4 e4 f4 g4 g4 f4 e4 d4 c4 c4 d4 e4 (e4 30) (d4 10) (d4 40)
               e4 e4 f4 g4 g4 f4 e4 d4 c4 c4 d4 e4 (d4 30) (c4 10) (c4 40)))
    (let ((d 20))
      (when (consp n) (setq d (cadr n) n (car n)))
      (sound 1 (note n) d 15 1)))
  t)

;; Bach's -- or Petzold's -- Minuet in G, out of MIDI OUT (LambdaSpeak's,
;; MIDI/80's): a harpsichord on channel 1 and a cello's bass under it on 2.
;; A bar is its bass note, then the tune's notes and their eighths. Each
;; note ends at its time from the start (e, in 1/300 s), so the time spent
;; between notes is not added up. A collection in the middle would be
;; heard: there is one first, and the notes go out by midi-out, a native,
;; whose arguments cost no cells (midi-note's &optional and let cost a few
;; each time) -- the tune then fits in 2500 cells.
(defun midi-tune ()
  (gc)
  (midi-program 1 7) (midi-program 2 43)
  (let* ((t0 (time)) (e 0)
         (a '((43 74 2 67 1 69 1 71 1 72 1) (47 74 2 67 2 67 2)
              (48 76 2 72 1 74 1 76 1 78 1) (47 79 2 67 2 67 2)
              (45 72 2 74 1 72 1 71 1 69 1) (43 71 2 72 1 71 1 69 1 67 1)))
         (bars (append a '((50 66 2 67 1 69 1 71 1 67 1) (50 69 6))
                       a '((50 69 2 71 1 69 1 67 1 66 1) (43 67 6)))))
    (dolist (bar bars)
      (midi-out #x91 (car bar) 64)              ; channel 2, on
      (do ((l (cdr bar) (cddr l)) (v 96 80)) ((null l))
        (midi-out #x90 (car l) v)               ; channel 1
        (incf e (* 75 (cadr l)))
        (loop (when (>= (logand (- (time) t0) 16383) e) (return)))
        (midi-out #x90 (car l) 0))
      (midi-out #x91 (car bar) 0)))
  t)

;; The LambdaSpeak card (speech and PlayCity are in library 2). Without
;; the card these are silent.
(defun talk ()
  (say (if (member :trs-80 *features*)
           "Hello. I am a Lisp machine, for the T R S 80."
           "Hello. I am a Lisp machine, for the Amstrad C P C."))
  (say "My library has turtle graphics, sound, and hash tables.")
  t)

;; DECtalk sings in its phoneme notation: [ax<300,25>] is 300 ms at pitch
;; 25, one semitone a step; 20 is G3, 25 C4, 29 E4, 32 G4
(defun sing ()
  (say "[:phoneme arpabet speak on][ay<350,20>ae<220,25>m<100,25>ax<260,29>l<90,32>ih<260,32>s<130,32>p<70,32>m<90,29>ax<220,29>sh<110,25>iy<420,25>n<300,25>]")
  t)

;; six voices: a chord on each PlayCity chip, I IV V I
(defun chords ()
  (playcity t)
  (dolist (c '((c3 e3 g3 c4 e4 g4) (f3 a3 c4 f4 a4 c5)
               (g3 b3 d4 g4 b4 d5) (c3 e3 g3 c4 e4 g4)))
    (let ((i 0))
      (dolist (n c) (pc-tone i (note n) 10) (incf i)))
    (dotimes (k 50) (frame)))
  (pc-off)
  t)

(defun hanoi (n &optional (from 'a) (to 'c) (via 'b))
  (when (> n 0)
    (hanoi (1- n) from via to)
    (format t "disc ~D: ~A to ~A~%" n from to)
    (hanoi (1- n) via to from))
  t)

;; every way to put n queens on an n by n board, none attacking another;
;; the first is drawn
(defun queens (n)
  (let ((count 0) (first nil))
    (labels ((safe (col placed)
               (let ((d 1))
                 (dolist (c placed t)
                   (when (or (= c col) (= (abs (- c col)) d)) (return nil))
                   (incf d))))
             (place (row placed)
               (if (= row n)
                   (progn (incf count) (unless first (setq first placed)))
                   (dotimes (col n)
                     (when (safe col placed) (place (1+ row) (cons col placed)))))))
      (place 0 nil))
    (dolist (c first)
      (dotimes (i n) (princ (if (= i c) "Q " ". ")))
      (terpri))
    (format t "~D solutions~%" count)
    count))

(defun primes (n)
  (let ((sieve (make-array (1+ n) :initial-element t)) (r nil))
    (do ((i 2 (1+ i))) ((> i n) (nreverse r))
      (when (aref sieve i)
        (push i r)
        (when (<= i (floor n i))
          (do ((j (* i i) (+ j i))) ((> j n)) (setf (aref sieve j) nil)))))))

(defun fact (n) (if (< n 2) 1 (* n (fact (1- n)))))
