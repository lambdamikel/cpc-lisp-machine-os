;;; CLASSICS.LSP -- the classics disc: (load "classics") shows what is on
;;; it (in 40 columns: a CPC's mode 1)

(format t "~%Classic Lisp programs. Load one, then:~%")
(format t " eliza    (eliza)       DOCTOR, 1966~%")
(format t " deriv    (deriv-demo)  differentiation~%")
(format t " animals  (animals)     it learns~%")
(format t " meval    (meval-demo)  Lisp in Lisp~%")
(format t " queens   (queens 8)    eight queens~%")
(format t " hanoi    (hanoi 4)     Towers of Hanoi~%")
(format t " life     (life 8)      Conway's Life~%")
(format t "(load \"eliza\") loads ELIZA, and so on.~%")
