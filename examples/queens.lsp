;;; QUEENS.LSP -- n queens on an n by n board, none attacking another
;;;
;;;   (load "queens")
;;;   (queens 8)        the first solution, drawn; it is the list of
;;;                     columns, one a row, the last row first
;;;   (queens-count 6)  how many solutions there are (6: 4; 8: 92 --
;;;                     minutes interpreted; (compile 'q-ok) and
;;;                     (compile 'q-count) where there is a compiler)
;;;
;;; Backtracking: a queen in each row in turn, in the first column no
;;; earlier queen attacks; when a row has none, back to the row before.

;; can a queen go in column col, below the queens of placed (their
;; columns, the nearest row first)?
(defun q-ok (col placed)
  (let ((d 1))
    (dolist (c placed t)
      (when (or (= c col) (= (abs (- c col)) d))
        (return nil))
      (setq d (1+ d)))))

(defun q-place (n placed)
  (if (= (length placed) n)
      placed
      (dotimes (col n nil)
        (when (q-ok col placed)
          (let ((s (q-place n (cons col placed))))
            (when s (return s)))))))

(defun q-count (n placed)
  (if (= (length placed) n)
      1
      (let ((k 0))
        (dotimes (col n k)
          (when (q-ok col placed)
            (setq k (+ k (q-count n (cons col placed)))))))))

(defun q-show (n sol)
  (dolist (c (reverse sol))
    (dotimes (i n)
      (princ (if (= i c) "Q " ". ")))
    (terpri)))

(defun queens (n)
  (let ((sol (q-place n nil)))
    (when sol (q-show n sol))
    sol))

(defun queens-count (n)
  (q-count n nil))
