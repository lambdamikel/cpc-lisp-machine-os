;;; MEVAL.LSP -- Lisp in Lisp: an evaluator for a small Scheme
;;;
;;;   (load "meval")
;;;   (meval-demo)     a few forms, evaluated
;;;   (meval-repl)     type its forms yourself; (exit) leaves
;;;
;;; McCarthy's eval and apply, as in "Structure and Interpretation of
;;; Computer Programs", chapter 4: QUOTE, IF, LAMBDA (closures, so
;;; functions remember their variables), DEFINE, BEGIN, and calls; the
;;; arithmetic and list functions are this Lisp's own. An environment is
;;; a list of frames, each an association list; the global one is
;;; *M-GLOBAL*.

(defvar *m-global*
  (list (cons '+ #'+) (cons '- #'-) (cons '* #'*) (cons '< #'<)
        (cons '= #'=) (cons 'car #'car) (cons 'cdr #'cdr)
        (cons 'cons #'cons) (cons 'list #'list) (cons 'null? #'null)
        (cons 'eq? #'eq) (cons 'display #'print)))

(defun m-lookup (s env)
  (dolist (frame env
           (let ((g (assoc s *m-global*)))
             (if g (cdr g) (error "meval: ~A has no value" s))))
    (let ((b (assoc s frame)))
      (when b (return (cdr b))))))

(defun m-eval (x env)
  (cond ((member x '(t nil)) x)
        ((symbolp x) (m-lookup x env))
        ((atom x) x)
        (t (case (car x)
             (quote (cadr x))
             (if (if (m-eval (cadr x) env)
                     (m-eval (caddr x) env)
                     (m-eval (car (cdddr x)) env)))
             (lambda (list 'closure (cadr x) (cddr x) env))
             (define (push (cons (cadr x) (m-eval (caddr x) env)) *m-global*)
                     (cadr x))
             (begin (m-progn (cdr x) env))
             (t (m-apply (m-eval (car x) env)
                         (mapcar #'(lambda (a) (m-eval a env)) (cdr x))))))))

(defun m-progn (body env)
  (let ((v nil))
    (dolist (f body v)
      (setq v (m-eval f env)))))

(defun m-apply (f args)
  (if (and (consp f) (eq (car f) 'closure))
      (m-progn (caddr f) (cons (pairlis (cadr f) args) (car (cdddr f))))
      (apply f args)))

(defun meval-demo ()
  (dolist (f '((define fact (lambda (n) (if (< n 2) 1 (* n (fact (- n 1))))))
               (fact 7)
               (define make-adder (lambda (n) (lambda (x) (+ x n))))
               ((make-adder 3) 4)
               (define map (lambda (f l)
                             (if (null? l) nil
                                 (cons (f (car l)) (map f (cdr l))))))
               (map (make-adder 10) (list 1 2 3))))
    (format t "~S~%  => ~S~%" f (m-eval f nil))))

(defun meval-repl ()
  (loop
    (princ "meval> ")
    (let ((f (read)))
      (when (equal f '(exit)) (return))
      (print (m-eval f nil))
      (terpri))))
