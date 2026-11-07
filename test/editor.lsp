(defun fact (n)
(if (= n 0)
1
(* n (fact (- n 1)))))
(fact 5)
(let ((x 1)
(y 2))
(list x
y))
(mapcar #'(lambda (x)
(* x x))
'(1 2 3))
"a string (with a paren"
(list #\( 1)
