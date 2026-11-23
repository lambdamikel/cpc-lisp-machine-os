;;; TORUS.LSP -- John Dot Donut: a torus of 31 by 16 dots
;;;
;;; A circle of radius 20, 100 from the axis, turned about the axis,
;;; tilted by -0.5 about x and drawn in perspective. A port of Madram's
;;; Locomotive BASIC in "Rosetta Sugar" (64nops.wordpress.com,
;;; 2021-01-21), to compare the two. (torus) draws it and says how long
;;; it took; (compile 'torus) first, and it is compiled.
;;;
;;; BASIC keeps the 496 dots in an array of reals, five bytes each, and
;;; goes over it three times: make, tilt, draw. CPC Lisp's floats are
;;; objects -- a cell and a block of nine bytes -- and 1488 of them do
;;; not fit in a 464's 5.8 KB of block space. So each dot is made, tilted
;;; and drawn in turn, with the same arithmetic.

(defun torus ()
  (let* ((r1 100) (r2 20) (dist 210) (zoom 250) (tiltx -0.5)
         (nb1 31) (nb2 16) (tau (* 2 pi))
         (cx (make-array nb2)) (cy (make-array nb2))
         (ct (cos tiltx)) (st (sin tiltx))
         (tic (time)) (ticks 0))
    (cls)
    (dotimes (i nb2)                    ; one circle
      (let ((a (/ (* i tau) nb2)))
        (setf (aref cx i) (+ r1 (* (cos a) r2))
              (aref cy i) (* (sin a) r2))))
    (origin 320 200)
    (locate 1 1)
    (princ "Torus:")
    (dotimes (j nb1)                    ; the circle turned about y
      (let* ((a (* (/ j nb1) tau)) (c (cos a)) (s (sin a)))
        (locate 8 1)
        (format t "~d%" (round (* (/ (1+ j) nb1) 100)))
        (dotimes (i nb2)
          (let* ((x (* (aref cx i) c))
                 (y0 (aref cy i))
                 (z0 (* (aref cx i) s))
                 (y (- (* y0 ct) (* z0 st)))  ; tilted about x
                 (z (+ (* y0 st) (* z0 ct)))
                 (d (+ dist z)))
            (plot (* (/ x d) zoom) (* (/ y d) zoom)))))
      (let ((toc (time)))         ; (time) wraps every 54.6 s: count
        (incf ticks (mod (- toc tic) 16384))     ; ring by ring
        (setq tic toc)))
    (locate 1 3)
    (format t "Done in: ~,2f seconds~%" (/ ticks 300.0))))
