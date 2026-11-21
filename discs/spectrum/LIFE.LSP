;;; LIFE.LSP -- John Conway's Game of Life, in text
;;;
;;;   (load "life")
;;;   (life 4)      four generations of a glider and a blinker
;;;   (life 10 '((1 . 1) (2 . 1) (3 . 1) (3 . 2) (2 . 3)))
;;;                 your own cells, (x . y) from the top left
;;;
;;; A board of 20 by 10 cells that wraps round at the edges. A live cell
;;; with two or three live neighbours lives on; an empty one with
;;; exactly three comes alive; every other cell is empty next time.

(defvar *life-w* 20)
(defvar *life-h* 10)

(defun life-board ()
  (make-array (* *life-w* *life-h*) :initial-element 0))

(defun life-at (b x y)
  (aref b (+ (mod x *life-w*) (* (mod y *life-h*) *life-w*))))

(defun life-n (b x y)
  (+ (life-at b (1- x) (1- y)) (life-at b x (1- y)) (life-at b (1+ x) (1- y))
     (life-at b (1- x) y) (life-at b (1+ x) y)
     (life-at b (1- x) (1+ y)) (life-at b x (1+ y)) (life-at b (1+ x) (1+ y))))

(defun life-step (b)
  (let ((nb (life-board)))
    (dotimes (y *life-h* nb)
      (dotimes (x *life-w*)
        (let ((n (life-n b x y)))
          (when (or (= n 3) (and (= n 2) (= 1 (life-at b x y))))
            (setf (aref nb (+ x (* y *life-w*))) 1)))))))

(defun life-show (b g)
  (format t "generation ~D~%" g)
  (dotimes (y *life-h*)
    (dotimes (x *life-w*)
      (princ (if (= 1 (life-at b x y)) "O" ".")))
    (terpri)))

(defun life (gens &optional cells)
  (let ((b (life-board)))
    (dolist (c (or cells '((1 . 0) (2 . 1) (0 . 2) (1 . 2) (2 . 2)
                           (14 . 5) (15 . 5) (16 . 5))))
      (setf (aref b (+ (car c) (* (cdr c) *life-w*))) 1))
    (dotimes (g gens)
      (life-show b g)
      (setq b (life-step b)))
    (life-show b gens)
    nil))
