;;; CPC Lisp on the ZX Spectrum: a test of the real machine -- esxDOS's
;;; files on the SD card, the RAM disc in the DivMMC's RAM, the ROM's
;;; calculator.
;;;
;;;   (load "hwtest")  then  (hwtest)     each check says yes or NO
;;;   (quit), load LISP.TAP again, (load "hwtest"), (hwtest2)
;;;                                       what starting again should leave
;;;
;;; (hwtest) writes HWTEST.TMP on the SD card (and deletes it), and on M:
;;; COPY.LSP, LZM.LSP, WORK.LSP, T.FAR and B.FAR (S.FAR comes and goes).

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
  (format t "~%CPC Lisp on the ZX Spectrum: the test~%")
  (unless *hw-m* (format t "No RAM disc: 1-4, 9, 10 apply~%"))
  (hw-check 1 "cells" #'(lambda () (length (make-list 500))) 500)
  (when (fboundp 'compile)
    (hw-check 2 "the compiler"
              #'(lambda () (compile 'hw-fib) (hw-fib 17))
              1597))
  (hw-check 3 "a file on the SD card"
            #'(lambda ()
                (save "hwtest.tmp" 'hw-sq)
                (fmakunbound 'hw-sq)
                (load "hwtest.tmp")
                (delete-file "hwtest.tmp")
                (list (hw-sq 7) (probe-file "hwtest.tmp")))
            '(49 nil))
  (hw-check 4 "lazy loading from the SD card"
            #'(lambda ()
                (fmakunbound 'hw-sq)
                (load "hwtest" :lazy t)
                (hw-sq 9))
            81)
  (when *hw-m*
    (hw-check 5 "two files open at once, SD and M:"
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
    (hw-check 8 "far arrays over five of its pages"
              #'(lambda ()
                  (make-far-array "s" 10)
                  (let ((b (make-far-array "b" 40000
                                           :element-type '(unsigned-byte 8)))
                        (a (make-far-array "t" 1000)))
                    (setf (far-ref b 16000) 65)
                    (setf (far-ref b 39999) 66)
                    (setf (far-ref a 7) 42)
                    (delete-file "m:s.far")
                    (list (far-ref b 16000) (far-ref b 39999) (far-ref a 7)
                          (hw-byte "m:b.far" 16002) (hw-byte "m:b.far" 40001))))
              '(65 66 42 65 66)))
  (hw-check 9 "floats: the ROM's calculator"
            #'(lambda ()
                (list (floor (* 10000 (sqrt 2.0))) (floor (* 1000 (sin 1.0)))
                      (floor (* 1000 (exp 1.0))) (floor (* 1000 (- 7.9 7)))))
            '(14142 841 2718 900))
  (hw-check 10 "colour pens"
            #'(lambda ()
                (cls) (disc 320 200 40 2) (box 100 100 140 140 3)
                (prog1 (list (test 320 200) (test 120 100) (test 500 300)) (cls)))
            '(2 3 0))
  (format t "~%~D yes, ~D NO~%" *hw-yes* *hw-no*)
  (when *hw-m*
    (format t "Then (quit), load LISP.TAP again,~%(load \"hwtest\"), (hwtest2)~%"))
  t)

(defun hwtest2 ()
  (setq *hw-yes* 0 *hw-no* 0)
  (format t "~%After a reset~%")
  (hw-check 1 "the far arrays kept"
            #'(lambda () (list (far-ref (far-array "t") 7)
                               (far-ref (far-array "b") 39999)))
            '(42 66))
  (hw-check 2 "the RAM disc's file kept"
            #'(lambda () (fmakunbound 'hw-sq) (load "m:work") (hw-sq 9))
            81)
  (format t "~%~D yes, ~D NO~%" *hw-yes* *hw-no*)
  t)
