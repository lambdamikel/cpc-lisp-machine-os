;;; CPC Lisp from disc: a test on the real machine.
;;;
;;;   (load "hwtest")  then  (hwtest)     each check says yes or NO
;;;   CTRL-SHIFT-ESC, RUN"LISP, (load "hwtest"), (hwtest2)
;;;                                       what a reset should leave (512K)
;;;
;;; The 512K version is tested in full; the plain 6128's (no compiler, no
;;; RAM disc) only in what it has. (hwtest) writes LZ.LSP, NOTES.LSP and
;;; COPY.LSP to drive A, and on M: WORK.LSP, COPY.LSP and T.FAR.

(defvar *hw-yes* 0)
(defvar *hw-no* 0)
(defvar *hw-a* nil)

(defun hw-check (n what fn want)
  (format t "~D ~A: " n what)
  (let* ((r (%catch-errors (funcall fn)))
         (got (if (car r) (cdr r) (list 'error (cadr r)))))
    (if (equal got want)
        (progn (setq *hw-yes* (+ *hw-yes* 1)) (format t "yes~%"))
        (progn (setq *hw-no* (+ *hw-no* 1)) (format t "NO -- ~S~%" got)))))

(defun hw-sq (x) (* x x))

(defun hw-fib (n) (if (< n 2) n (+ (hw-fib (- n 1)) (hw-fib (- n 2)))))

(defun hw-512 () (member :cpc512 *features*))

(defun hw-copy (from to)
  (with-open-file (i from)
    (with-open-file (o to :direction :output)
      (loop (let ((l (read-line i nil nil)))
              (if l (write-line l o) (return t)))))))

(defun hw-zap (name) (ignore-errors (delete-file name)))

(defun hwtest ()
  (setq *hw-yes* 0 *hw-no* 0)
  (format t "~%CPC Lisp from disc: the test~%")
  (hw-check 1 "cells" #'(lambda () (length (make-list 1000))) 1000)
  (if (hw-512)
      (hw-check 2 "two files open at once"
                #'(lambda ()
                    (with-open-file (o "notes" :direction :output)
                      (format o "~{~A~%~}" '(one two three)))
                    (hw-copy "notes" "m:copy")
                    (with-open-file (i "m:copy")
                      (list (read-line i) (read-line i) (read-line i))))
                '("ONE" "TWO" "THREE"))
      (format t "2 two files: skipped -- the 6128 version needs 4.3 KB of~%  string space for them, and this test takes 1.5~%"))
  (hw-check 3 "lazy loading from the drive"
            #'(lambda ()
                (defun hw-dbl (x) (* 2 x))
                (save "lz" 'hw-dbl)
                (fmakunbound 'hw-dbl)
                (load "lz" :lazy t)
                (hw-dbl 21))
            42)
  (when (hw-512)
    (hw-check 4 "the RAM disc"
              #'(lambda () (save "m:work" 'hw-sq) (probe-file "m:work"))
              "m:work")
    (format t "  (5 takes a minute or two)~%")
    (hw-check 5 "far arrays in banks 6 and 7"
              #'(lambda ()
                  (unwind-protect
                      (let ((a (make-far-array "a" 65000))
                            (b (make-far-array "b" 65000))
                            (c (make-far-array "c" 65000)))
                        (setf (far-ref a 0) 1)
                        (setf (far-ref c 64999) 7)
                        (let ((before (far-ref c 64999)))
                          (delete-file "m:a.far")
                          (delete-file "m:b.far")
                          (list before (far-ref c 64999) (far-length c))))
                    (hw-zap "m:a.far") (hw-zap "m:b.far") (hw-zap "m:c.far")))
              '(7 7 65000.0))
    (hw-check 6 "a far array"
              #'(lambda ()
                  (setq *hw-a* (make-far-array "t" 1000))
                  (setf (far-ref *hw-a* 7) 42)
                  (far-ref *hw-a* 7))
              42)
    (hw-check 7 "the compiler"
              #'(lambda () (compile 'hw-fib) (hw-fib 17))
              1597))
  (format t "~%~D yes, ~D NO~%" *hw-yes* *hw-no*)
  (format t "~%By hand:~%")
  (format t " (rose)        a rose; a key ends it~%")
  (format t " (ed 'hw-sq)   on a full screen; ESC leaves~%")
  (format t " (loop)        then ESC: back at LISP>~%")
  (format t " (say \"hello\") the card speaks~%")
  (when (hw-512)
    (format t "~%Then CTRL-SHIFT-ESC, RUN\"LISP, (load \"hwtest\"), (hwtest2)~%"))
  t)

(defun hwtest2 ()
  (setq *hw-yes* 0 *hw-no* 0)
  (format t "~%After a reset~%")
  (cond ((hw-512)
         (hw-check 1 "the far array kept"
                   #'(lambda () (far-ref (far-array "t") 7)) 42)
         (hw-check 2 "the RAM disc's file kept"
                   #'(lambda () (fmakunbound 'hw-sq) (load "m:work") (hw-sq 9))
                   81)
         (format t "~%~D yes, ~D NO~%" *hw-yes* *hw-no*))
        (t (format t "nothing to check here: no RAM disc~%")))
  t)
