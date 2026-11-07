(defun fact (n) (if (= n 0) 1 (* n (fact (- n 1)))))
(pprint '(defun fact (n) (if (= n 0) 1 (* n (fact (- n 1))))))
(pprint '(let ((alpha 1) (beta 2) (gamma 3)) (when (> alpha 0) (print alpha) (print beta)) (list alpha beta gamma 'some-long-symbol-name)))
(prin1-to-string '(a "b" #\c))
(princ-to-string '(a "b" #\c))
(read-from-string "(1 2 (3 . 4))")
(ed 'fact)
!shot 150
!press 9 10
(fact 6)
(ed 'twice)
!press 1 150
!press 1 12
!press 1 12
!press 1 12
!press 1 12
!press 1 12
!press 1 12
!press 1 12
!press 1 12
!press 1 12
!press 1 12
!press 1 12
!press 1 12
!press 1 12
!type 12 x
!press 2 20
!press 8 12
!type 12 (* 2 x)
!shot 150
!press 9 10
(twice 21)
(ed 'g)
!press 23+2 150
!press 8 15
!type 15 {ENTER}(list 1{ENTER}2){ENTER}(car '(a b
!type 300 c))
!shot 200
!press 9 10
(g)
(ed 'nothing-here)
!press 66 150
(ed)
!shot 150
!press 9 10
