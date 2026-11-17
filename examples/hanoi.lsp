;;; HANOI.LSP -- the Towers of Hanoi
;;;
;;;   (load "hanoi")
;;;   (hanoi 3)      the seven moves of three discs from peg A to peg C
;;;   (hanoi-count 10)   how many moves ten discs take: 1023, 2^10 - 1
;;;                      (past 14 discs a float: integers are 15 bits)
;;;
;;; To move n discs: move n-1 out of the way, the biggest across, and the
;;; n-1 back on top of it -- each half the same problem, one disc smaller.

(defun hanoi (n &optional (from 'a) (to 'c) (via 'b))
  (when (> n 0)
    (hanoi (1- n) from via to)
    (format t "disc ~D from ~A to ~A~%" n from to)
    (hanoi (1- n) via to from))
  nil)

(defun hanoi-count (n)
  (if (= n 0) 0 (+ 1 (* 2 (hanoi-count (1- n))))))
