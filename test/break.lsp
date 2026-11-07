(loop)
!esc 100
(+ 1 2)
(defun forever (n) (forever (+ n 1)))
(forever 0)
!esc 150
(let ((l '(1 2))) (setf (cdr (cdr l)) l) (length l))
!esc 100
(* 6 7)
