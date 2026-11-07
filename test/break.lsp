(loop)
!esc 100
(+ 1 2)
(defun forever (n) (forever (+ n 1)))
(forever 0)
!esc 150
(let ((l '(1 2))) (setf (cdr (cdr l)) l) (length l))
!esc 100
(* 6 7)
(let ((x 0)) (dotimes (i 16000) (dotimes (j 16000) (setq x j))))
!esc 100
(do ((i 0 (+ i 0))) (nil) i)
!esc 100
(dolist (x (let ((l (list 1 2))) (setf (cdr (cdr l)) l) l)) x)
!esc 100
(+ 3 4)
