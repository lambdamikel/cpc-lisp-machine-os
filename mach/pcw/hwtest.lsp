;;; CPC Lisp on the PCW: a test of the real machine -- CP/M's files on the
;;; disc in A, through our own disc routines, the RAM disc in the blocks
;;; Lisp leaves, our own maths, the screen.
;;;
;;;   (load "hwtest")  then  (hwtest)     each check says yes or NO
;;;
;;; (hwtest) writes HWTEST.TMP on the disc (and deletes it), and on M:
;;; COPY.LSP, LZM.LSP, WORK.LSP, T.FAR and B.FAR (S.FAR comes and goes).
;;; M: goes at a reboot (the boot program writes into its first block).

(defvar *hw-yes* 0)
(defvar *hw-no* 0)
(defvar *hw-m* nil)

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

(defun hw-byte (file pos)
  (with-open-file (i file) (file-position i pos) (char-code (read-char i))))

(defun hwtest ()
  (setq *hw-yes* 0 *hw-no* 0)
  (setq *hw-m* (car (%catch-errors
                     (with-open-file (o "m:hwm" :direction :output) t))))
  (format t "~%CPC Lisp on the PCW: the test~%")
  (unless *hw-m* (format t "No RAM disc: 1-4, 9, 10 apply~%"))
  (hw-check 1 "cells" #'(lambda () (length (make-list 500))) 500)
  (when (fboundp 'compile)
    (hw-check 2 "the compiler"
              #'(lambda () (compile 'hw-fib) (hw-fib 17))
              1597))
  (hw-check 3 "a file on the disc"
            #'(lambda ()
                (save "hwtest.tmp" 'hw-sq)
                (fmakunbound 'hw-sq)
                (load "hwtest.tmp")
                (delete-file "hwtest.tmp")
                (list (hw-sq 7) (probe-file "hwtest.tmp")))
            '(49 nil))
  (hw-check 4 "lazy loading from the disc"
            #'(lambda ()
                (fmakunbound 'hw-sq)
                (load "hwtest" :lazy t)
                (hw-sq 9))
            81)
  (when *hw-m*
    (hw-check 5 "two files open at once, A: and M:"
              #'(lambda ()
                  (hw-copy "hwtest" "m:copy")
                  (equal (hw-lines "hwtest") (hw-lines "m:copy")))
              t)
    (hw-check 6 "lazy loading from M:"
              #'(lambda ()
                  (defun hw-tri (x) (* 3 x))
                  (save "m:lzm" 'hw-tri)
                  (fmakunbound 'hw-tri)
                  (load "m:lzm" :lazy t)
                  (hw-tri 4))
              12)
    (hw-check 7 "the RAM disc"
              #'(lambda () (save "m:work" 'hw-sq) (probe-file "m:work"))
              "m:work")
    (hw-check 8 "far arrays over its blocks"
              #'(lambda ()
                  (make-far-array "s" 10)
                  (let ((b (make-far-array "b" 30000
                                           :element-type '(unsigned-byte 8)))
                        (a (make-far-array "t" 1000)))
                    (setf (far-ref b 16000) 65)
                    (setf (far-ref b 29999) 66)
                    (setf (far-ref a 7) 42)
                    (delete-file "m:s.far")
                    (list (far-ref b 16000) (far-ref b 29999) (far-ref a 7)
                          (hw-byte "m:b.far" 16002) (hw-byte "m:b.far" 30001))))
              '(65 66 42 65 66)))
  (hw-check 9 "floats: our own maths"
            #'(lambda ()
                (list (floor (* 10000 (sqrt 2.0))) (floor (* 1000 (sin 1.0)))
                      (floor (* 1000 (exp 1.0))) (floor (* 1000 (- 7.9 7)))))
            '(14142 841 2718 900))
  (hw-check 10 "the screen's pixels"
            #'(lambda ()
                (cls) (disc 320 200 40 2) (box 100 100 140 140 3)
                (prog1 (list (test 320 200) (test 120 100) (test 500 300)) (cls)))
            '(1 1 0))
  (format t "~%~D yes, ~D NO~%" *hw-yes* *hw-no*)
  t)
