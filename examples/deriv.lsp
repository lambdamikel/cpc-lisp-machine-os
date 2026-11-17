;;; DERIV.LSP -- symbolic differentiation, the classic of every Lisp book
;;;
;;;   (load "deriv")
;;;   (deriv '(* x (sin x)) 'x)   =>  (+ (* X (COS X)) (SIN X))
;;;   (deriv-demo)                a few, worked out
;;;
;;; Expressions are in prefix: (+ a b ...), (- a b), (- a), (* a b ...),
;;; (/ a b), (^ a n) with n not depending on x, (sin a), (cos a),
;;; (exp a), (log a). The result is simplified as it is built: no adding
;;; of 0 or multiplying by 1, numbers worked out, 2x for x + x.

;; (+ a b c) -> (+ a (+ b c)), all the way down
(defun d-bin (e)
  (cond ((atom e) e)
        ((and (member (car e) '(+ *)) (cdddr e))
         (list (car e) (d-bin (cadr e)) (d-bin (cons (car e) (cddr e)))))
        (t (cons (car e) (mapcar #'d-bin (cdr e))))))

;; an expression made, simplified
(defun d-mk (op a &optional b)
  (case op
    (+ (cond ((eql a 0) b)
             ((eql b 0) a)
             ((and (numberp a) (numberp b)) (+ a b))
             ((equal a b) (d-mk '* 2 a))
             ((numberp a) (list '+ b a))
             (t (list '+ a b))))
    (- (cond ((eql b 0) a)
             ((and (numberp a) (numberp b)) (- a b))
             ((equal a b) 0)
             ((eql a 0) (d-mk '* -1 b))
             (t (list '- a b))))
    (* (cond ((or (eql a 0) (eql b 0)) 0)
             ((eql a 1) b)
             ((eql b 1) a)
             ((and (numberp a) (numberp b)) (* a b))
             ((numberp b) (d-mk '* b a))
             ((and (numberp a) (consp b) (eq (car b) '*) (numberp (cadr b)))
              (d-mk '* (* a (cadr b)) (caddr b)))
             (t (list '* a b))))
    (/ (cond ((eql a 0) 0)
             ((eql b 1) a)
             ((equal a b) 1)
             (t (list '/ a b))))
    (^ (cond ((eql b 0) 1)
             ((eql b 1) a)
             ((and (numberp a) (numberp b) (>= b 0)) (expt a b))
             (t (list '^ a b))))
    (t (list op a))))

;; d e / d x
(defun d-d (e x)
  (if (atom e)
      (if (eq e x) 1 0)
      (let ((u (cadr e)) (v (caddr e)))
        (case (car e)
          (+ (d-mk '+ (d-d u x) (d-d v x)))
          (- (if (cddr e)
                 (d-mk '- (d-d u x) (d-d v x))
                 (d-mk '* -1 (d-d u x))))
          (* (d-mk '+ (d-mk '* u (d-d v x)) (d-mk '* (d-d u x) v)))
          (/ (d-mk '/ (d-mk '- (d-mk '* (d-d u x) v) (d-mk '* u (d-d v x)))
                   (d-mk '^ v 2)))
          (^ (d-mk '* (d-mk '* v (d-mk '^ u (d-mk '- v 1))) (d-d u x)))
          (sin (d-mk '* (d-mk 'cos u) (d-d u x)))
          (cos (d-mk '* (d-mk '* -1 (d-mk 'sin u)) (d-d u x)))
          (exp (d-mk '* e (d-d u x)))
          (log (d-mk '/ (d-d u x) u))
          (t (error "deriv: what is ~A?" (car e)))))))

(defun deriv (e x)
  (d-d (d-bin e) x))

(defun deriv-demo ()
  (dolist (e '((+ (* 3 (^ x 2)) (* 2 x) 1)
               (* x (sin x))
               (/ 1 x)
               (exp (* 2 x))
               (log (^ x 2))
               (sin (cos x))
               (* (+ x 1) (- x 1))))
    (format t "d/dx ~A~%   = ~A~%" e (deriv e 'x))))
