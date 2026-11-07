(unwind-protect (+ 1 2) (print 'cleanup))
(defvar *log* nil)
(defun f (x) (unwind-protect (if (> x 0) (throw 'out x) x) (push x *log*)))
(catch 'out (f 5))
(catch 'out (f -1))
*log*
(block b (unwind-protect (return-from b 'early) (push 'block *log*)))
*log*
(catch 'out (unwind-protect (unwind-protect (throw 'out 1) (push 'inner *log*)) (push 'outer *log*)))
*log*
(defvar *s* 'global)
(defun g () (let ((*s* 'bound)) (unwind-protect (throw 'out *s*) (push *s* *log*))))
(catch 'out (g))
*log*
*s*
(dolist (i '(1 2 3)) (unwind-protect (when (= i 2) (return 'two)) (push i *log*)))
*log*
(unwind-protect (car 5) (push 'error *log*))
*log*
(pprint '(unwind-protect (progn (open-it) (use-it)) (close-it) (say-so)))
