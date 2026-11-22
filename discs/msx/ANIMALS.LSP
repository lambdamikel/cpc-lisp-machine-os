;;; ANIMALS.LSP -- the guessing game that learns
;;;
;;;   (load "animals")
;;;   (animals)      think of an animal; it asks, and guesses
;;;
;;; What it knows is a tree: an animal, or a question with a tree for yes
;;; and one for no. When it guesses wrong it asks what the animal was and
;;; for a question that tells the two apart, and grows the tree. At the
;;; end it saves the tree to ZOO.LSP, and (animals) loads it from there
;;; next time: it gets cleverer for every game played on the disc.

(defvar *animals* "a cat")

(defun a-line ()
  (string-trim " " (read-line)))

(defun a-play (tree)
  (if (stringp tree)
      (if (y-or-n-p "Is it ~A?" tree)
          (progn (format t "I knew it!~%") tree)
          (let ((new (progn (format t "I give up. What is it? ") (a-line))))
            (format t "Give me a question that tells ~A from ~A: " new tree)
            (let ((q (a-line)))
              (if (y-or-n-p "For ~A, is the answer yes?" new)
                  (list q new tree)
                  (list q tree new)))))
      (if (y-or-n-p "~A" (car tree))
          (list (car tree) (a-play (cadr tree)) (caddr tree))
          (list (car tree) (cadr tree) (a-play (caddr tree))))))

(defun animals ()
  (ignore-errors (load "zoo"))
  (unless *animals* (setq *animals* "a cat"))
  (loop
    (format t "Think of an animal.~%")
    (setq *animals* (a-play *animals*))
    (unless (y-or-n-p "Another?") (return)))
  (save "zoo" '*animals*)
  (format t "What I know is saved, as ZOO.~%"))
