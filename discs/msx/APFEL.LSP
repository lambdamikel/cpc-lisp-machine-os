;;; The Apfelmaennchen -- the Mandelbrot set -- for CPC Lisp: on a CPC in
;;; mode 2 (640 by 200, two colours), on a TRS-80 Model 4 with a
;;; high-resolution board (640 by 240).
;;;
;;;   (load "apfel")  then  (apfel)       24 rounds a point
;;;                         (apfel 40)    more: the edge finer, slower
;;;
;;; It is drawn coarse to fine: blocks of 16 units, then 8, then 4 -- a
;;; block's first corner is its parent's, so only the other three are
;;; computed, and a block is drawn only where it differs from what the
;;; screen shows in its middle (test: on a Model 4 a pixel row may straddle
;;; two blocks, and a block's edge row tells of its neighbour). The whole
;;; picture is there after the first pass.
;;;
;;; In fixnums, no floats: a number is kept times 64, so -2.3 is -147 (a
;;; float is slow, and takes string space). A point escapes when x or y
;;; passes 127 (2 * 64 -- tested before squaring, so no product passes
;;; 16383) or x*x + y*y passes 4. x runs from -2.3 to 0.8 over the 640
;;; units, y from -1.17 to the axis over the upper 200 (the 4:3 of the
;;; screen: the set is not stretched), the lower half mirrored. Lit: the
;;; set. Where there is a compiler (a CPC with the VM ROM) the rounds are
;;; compiled. ESC (BREAK) stops it.

(defun apfel-depth (cx cy depth)
  (let ((x 0) (y 0) (n 0))
    (loop
      (when (or (= n depth) (> (abs x) 127) (> (abs y) 127))
        (return n))
      (let ((x2 (floor (* x x) 64))
            (y2 (floor (* y y) 64)))
        (when (> (+ x2 y2) 256)
          (return n))
        (setq y (+ (floor (* x y) 32) cy)
              x (+ (- x2 y2) cx)
              n (+ n 1))))))

;; one pass: blocks of S units; the upper half's rows from the top edge
;; down to the axis, each mirrored below it
(defun apfel-pass (s depth first)
  (dotimes (j (floor (+ 199 s) s))
    (let* ((y (* j s))
           (cy (- (floor (* y 3) 8) 75)))
      (dotimes (i (floor 640 s))
        (unless (and (not first) (evenp i) (evenp j))
          (let* ((x (* i s))
                 (pen (if (= (apfel-depth (- (floor (* x 5) 16) 147) cy depth)
                             depth)
                          1 0)))
            (unless (= pen (if first 0 (test (+ x (floor s 2)) (- 400 y (floor s 2)))))
              (fill-box x (- 400 y s) (+ x s -1) (- 399 y) pen)
              (fill-box x y (+ x s -1) (+ y s -1) pen))))))))

(defun apfel (&optional (depth 24))
  (when (fboundp 'compile)
    (compile 'apfel-depth)
    (compile 'apfel-pass))
  (if (member :trs-80 *features*) (cls) (mode 2))
  (apfel-pass 16 depth t)
  (apfel-pass 8 depth nil)
  (apfel-pass 4 depth nil)
  t)
