;;; CPC Lisp on the TRS-80 Model 4: a test of the real machine -- the
;;; 128 KB's banks, LS-DOS's files, the ROM's floats, the clock, the
;;; high-resolution board.
;;;
;;;   (load "hwtest")  then  (hwtest)     each check says yes or NO
;;;
;;; It writes HWCOPY/LSP and HWSAVE/LSP on the Lisp's disc and deletes
;;; them again.

(defvar *hw-yes* 0)
(defvar *hw-no* 0)

(defun hw-check (n what fn want)
  (format t "~D ~A: " n what)
  (let* ((r (%catch-errors (funcall fn)))
         (got (if (car r) (cdr r) (list 'error (cadr r)))))
    (if (equal got want)
        (progn (setq *hw-yes* (+ *hw-yes* 1)) (format t "yes~%"))
        (progn (setq *hw-no* (+ *hw-no* 1)) (format t "NO -- ~S~%" got)))))

(defun hw-sq (x) (* x x))
(defun hw-fib (n) (if (< n 2) n (+ (hw-fib (- n 1)) (hw-fib (- n 2)))))

(defun hw-copy (from to)
  (with-open-file (i from)
    (with-open-file (o to :direction :output)
      (loop (let ((l (read-line i nil nil)))
              (if l (write-line l o) (return t)))))))

(defun hw-lines (f)
  (with-open-file (i f) (list (read-line i) (read-line i) (read-line i))))

(defun hwtest ()
  (setq *hw-yes* 0 *hw-no* 0)
  (format t "~%CPC Lisp on the TRS-80 Model 4: the test~%")
  (hw-check 1 "cells, and the banks" #'(lambda () (length (make-list 1000)))
            1000)
  (hw-check 2 "two files open at once"
            #'(lambda ()
                (hw-copy "hwtest" "hwcopy")
                (prog1 (equal (hw-lines "hwtest") (hw-lines "hwcopy"))
                  (delete-file "hwcopy")))
            t)
  (hw-check 3 "save and load"
            #'(lambda ()
                (defun hw-tri (x) (* 3 x))
                (save "hwsave" 'hw-tri)
                (fmakunbound 'hw-tri)
                (load "hwsave")
                (delete-file "hwsave")
                (hw-tri 4))
            12)
  (hw-check 4 "lazy loading"
            #'(lambda ()
                (fmakunbound 'hw-sq)
                (load "hwtest" :lazy t)
                (hw-sq 9))
            81)
  (hw-check 5 "floats, the ROM's"
            #'(lambda ()
                (list (format nil "~,4F" (sqrt 2)) (format nil "~,4F" (sin 1.0))
                      (* 200 200)))
            '("1.4142" "0.8415" 40000.0))
  (hw-check 6 "the clock"
            #'(lambda ()
                (let ((t0 (time))) (hw-fib 12) (> (time) t0)))
            t)
  (hw-check 7 "the high-resolution board"
            #'(lambda ()
                (cls)
                (plot 100 100 1)
                (draw 300 100 1)
                (prog1 (list (test 100 100) (test 200 100) (test 200 110))
                  (cls)))
            '(1 1 0))
  (hw-check 8 "a flood fill"
            #'(lambda ()
                (cls)
                (box 200 100 440 300 1)
                (flood-fill 320 200 1)
                (prog1 (list (test 320 200) (test 210 290) (test 100 200))
                  (cls)))
            '(1 1 0))
  (format t "~D yes, ~D no~%" *hw-yes* *hw-no*)
  (format t "~%By hand: (rose) -- a picture, the text over it;~%")
  (format t "(tune) -- a tune from the speaker; (loop) then BREAK.~%")
  *hw-no*)
