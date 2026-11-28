;;; CLASSICS.LSP -- the classics disc: (load "classics") shows what is on
;;; it (in 40 columns, a CPC's mode 1: 39 characters a line at most --
;;; a 40th puts the cursor on the next line, and the newline adds a blank one)

(format t "~%Classic Lisp programs. Load one, then:~%")
(format t " eliza    (eliza)       DOCTOR, 1966~%")
(format t " deriv    (deriv-demo)  differentiation~%")
(format t " animals  (animals)     it learns~%")
(format t " meval    (meval-demo)  Lisp in Lisp~%")
(format t " life     (life 8)      Conway's Life~%")
(format t " tictac   (tictac)      unbeatable~%")
(format t " huffman  (huffman-demo) SICP's codes~%")
(format t "(load \"eliza\") loads ELIZA, and so on.~%")
(format t "Built in: (hanoi 4), (queens 6)~%")
(format t "-- (demo) lists all the ROM's.~%")
