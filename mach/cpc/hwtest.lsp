;;; CPC Lisp, the ROMs: a test of the RAM expansion's use, on the real
;;; machine (a 464 with a RAM expansion, or a 6128).
;;;
;;;   (load "hwtest")  then  (hwtest)     each check says yes or NO
;;;   CTRL-SHIFT-ESC, (load "hwtest"), (hwtest2)
;;;                                       what a reset should leave
;;;
;;; M: is the expansion's first 64K (or a 6128's second). (hwtest) writes
;;; LZ.LSP and NOTES.LSP to drive A, and on M: WORK.LSP, COPY.LSP,
;;; LZM.LSP, T.FAR and B.FAR (S.FAR comes and goes).

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

(defun hw-byte (file pos)
  (with-open-file (i file) (file-position i pos) (char-code (read-char i))))

(defun hwtest ()
  (setq *hw-yes* 0 *hw-no* 0)
  (setq *hw-m* (car (%catch-errors
                     (with-open-file (o "m:hwm" :direction :output) t))))
  (format t "~%CPC Lisp, the ROMs: the RAM expansion~%")
  (unless *hw-m* (format t "No RAM disc: only 1 and 3 apply~%"))
  (hw-check 1 "cells" #'(lambda () (length (make-list 1000))) 1000)
  (when *hw-m*
    (hw-check 2 "two files open at once"
              #'(lambda ()
                  (with-open-file (o "notes" :direction :output)
                    (format o "~{~A~%~}" '(one two three)))
                  (hw-copy "notes" "m:copy")
                  (with-open-file (i "m:copy")
                    (list (read-line i) (read-line i) (read-line i))))
              '("ONE" "TWO" "THREE")))
  (hw-check 3 "lazy loading from the drive"
            #'(lambda ()
                (defun hw-dbl (x) (* 2 x))
                (save "lz" 'hw-dbl)
                (fmakunbound 'hw-dbl)
                (load "lz" :lazy t)
                (hw-dbl 21))
            42)
  (when *hw-m*
    (hw-check 4 "lazy loading from M:"
              #'(lambda ()
                  (defun hw-tri (x) (* 3 x))
                  (save "m:lzm" 'hw-tri)
                  (fmakunbound 'hw-tri)
                  (load "m:lzm" :lazy t)
                  (hw-tri 4))
              12)
    (hw-check 5 "the RAM disc"
              #'(lambda () (save "m:work" 'hw-sq) (probe-file "m:work"))
              "m:work")
    (hw-check 6 "a far array over three banks"
              #'(lambda ()
                  (make-far-array "s" 10)
                  (let ((b (make-far-array "b" 40000
                                           :element-type '(unsigned-byte 8))))
                    (setf (far-ref b 16000) 65)
                    (setf (far-ref b 39999) 66)
                    (delete-file "m:s.far")
                    (list (far-ref b 16000) (far-ref b 39999)
                          (hw-byte "m:b.far" 16002) (hw-byte "m:b.far" 40001))))
              '(65 66 65 66))
    (hw-check 7 "a far array"
              #'(lambda ()
                  (let ((a (make-far-array "t" 1000)))
                    (setf (far-ref a 7) 42)
                    (far-ref a 7)))
              42))
  (when (fboundp 'compile)
    (hw-check 8 "the compiler"
              #'(lambda () (compile 'hw-fib) (hw-fib 17))
              1597))
  (format t "~%~D yes, ~D NO~%" *hw-yes* *hw-no*)
  (when *hw-m*
    (format t "Then CTRL-SHIFT-ESC, (load \"hwtest\"), (hwtest2)~%"))
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
