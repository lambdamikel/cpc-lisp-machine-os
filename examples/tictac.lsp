;;; TICTAC.LSP -- tic-tac-toe against a player that cannot lose
;;;
;;;   (load "tictac")
;;;   (tictac)       you are X and begin: type a square, 1-9
;;;
;;; The computer looks at every game that can follow (minimax): it scores
;;; a win for it 10, a loss -10, a draw 0, a quicker win better than a
;;; slower one, and takes the move whose worst outcome is best. Alpha-beta
;;; pruning stops looking at a move once one already found is better, and
;;; trying the centre and the corners first makes that happen early; a
;;; move is checked for a win only along the lines through it. Its first
;;; reply is the centre, or a corner when you took it: the one search
;;; that would take long, and the answer is known. On a CPC with a
;;; compiler the search is compiled the first time: its hardest move
;;; takes some 5 seconds on a 464; interpreted (a plain 6128, a TRS-80)
;;; up to 20.

(defvar *tt-lines* '((0 1 2) (3 4 5) (6 7 8) (0 3 6) (1 4 7) (2 5 8)
                     (0 4 8) (2 4 6)))
(defvar *tt-order* '(4 0 2 6 8 1 3 5 7))

(defun tt-winner (b)
  (dolist (l *tt-lines* nil)
    (let ((p (aref b (car l))))
      (when (and p (eq p (aref b (cadr l))) (eq p (aref b (caddr l))))
        (return p)))))

(defun tt-full (b)
  (dotimes (i 9 t)
    (unless (aref b i) (return nil))))

(defvar *tt-at* nil)

;; the lines through each square
(defun tt-init ()
  (setq *tt-at* (make-array 9 :initial-element nil))
  (dolist (l *tt-lines*)
    (dolist (i l)
      (push l (aref *tt-at* i)))))

;; did the move at i win? (only the lines through it can have changed)
(defun tt-won (b i)
  (let ((p (aref b i)))
    (dolist (l (aref *tt-at* i) nil)
      (when (and (eq p (aref b (car l))) (eq p (aref b (cadr l)))
                 (eq p (aref b (caddr l))))
        (return t)))))

;; the position's worth to O after a move at i, empty squares left,
;; depth moves into the search
(defun tt-value (b i empty depth alpha beta)
  (cond ((tt-won b i) (if (eq (aref b i) 'o) (- 10 depth) (- depth 10)))
        ((= empty 0) 0)
        (t (let* ((who (if (eq (aref b i) 'o) 'x 'o))
                  (best (if (eq who 'o) -100 100)))
             (dolist (j *tt-order* best)
               (unless (aref b j)
                 (setf (aref b j) who)
                 (let ((v (tt-value b j (1- empty) (1+ depth) alpha beta)))
                   (setf (aref b j) nil)
                   (if (eq who 'o)
                       (when (> v best)
                         (setq best v)
                         (when (> v alpha) (setq alpha v)))
                       (when (< v best)
                         (setq best v)
                         (when (< v beta) (setq beta v))))
                   (when (>= alpha beta) (return best)))))))))

(defun tt-best (b)
  (let ((empty (count nil b)))
    (if (>= empty 8)
        (if (aref b 4) 0 4)
        (let ((best -100) (move nil))
          (dolist (i *tt-order* move)
            (unless (aref b i)
              (setf (aref b i) 'o)
              (let ((v (tt-value b i (1- empty) 1 best 100)))
                (setf (aref b i) nil)
                (when (> v best)
                  (setq best v move i)))))))))

(defun tt-show (b)
  (dotimes (r 3)
    (dotimes (c 3)
      (let ((i (+ c (* 3 r))))
        (format t " ~A " (or (aref b i) (1+ i))))
      (when (< c 2) (princ "|")))
    (terpri)
    (when (< r 2) (format t "---+---+---~%"))))

(defun tt-ask (b)
  (loop
    (princ "Your square? ")
    (let ((n (ignore-errors (read-from-string (read-line)))))
      (when (and (integerp n) (<= 1 n 9) (null (aref b (1- n))))
        (return (1- n)))
      (format t "A free square, 1-9, please.~%"))))

(defun tt-over (b)
  (let ((w (tt-winner b)))
    (cond (w (tt-show b)
             (format t (if (eq w 'x) "You win!~%" "I win.~%"))
             t)
          ((tt-full b) (tt-show b) (format t "A draw.~%") t))))

(defun tictac ()
  (unless *tt-at*
    (tt-init)
    (when (and (fboundp 'compile)      ; on a CPC with a compiler the
               (member :cpc *features*)) ;   search is compiled: some five
      (compile 'tt-won)                ;   times as fast (a TRS-80 has
      (compile 'tt-value)))            ;   too few cells to compile it)
  (let ((b (make-array 9 :initial-element nil)))
    (format t "You are X, I am O.~%")
    (loop
      (tt-show b)
      (setf (aref b (tt-ask b)) 'x)
      (when (tt-over b) (return))
      (let ((m (tt-best b)))
        (format t "I take ~D.~%" (1+ m))
        (setf (aref b m) 'o))
      (when (tt-over b) (return)))))
