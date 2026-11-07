(demo)
(hanoi 3)
(queens 6)
(primes 100)
(fact 20)
(spiral)
!type 450 x
(do ((i 0 (1+ i)) (j 10 (1- j))) ((= i 3) (list i j)))
(macroexpand-1 '(do ((a 1 (+ a b)) (b 2 a)) ((> a 5) a)))
