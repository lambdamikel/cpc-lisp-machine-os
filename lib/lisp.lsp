;;; CPC Lisp -- library functions written in Lisp.
;;;
;;; Each top-level DEFUN or DEFMACRO here is stored in the library ROM as
;;; text and read and evaluated the first time its name is used (autoload),
;;; so the heap pays only for what a program uses. Any other top-level form
;;; is evaluated at boot. tools/mklib.py strips the comments.

(defvar *features* '(:cpc :cpc-lisp))
(defconstant pi (%pi))

;;; Lists

(defun identity (x) x)

(defun complement (f)
  #'(lambda (&rest args) (not (apply f args))))

(defun nconc (&rest lists)
  (let ((result nil) (tail nil))
    (dolist (l lists result)
      (when l
        (if tail (rplacd (last tail) l) (setq result l))
        (setq tail l)))))

(defun copy-list (l)
  (let ((r nil))
    (loop (unless (consp l) (return (nreconc r l)))
          (push (pop l) r))))

(defun make-list (n &optional initial-element)
  (let ((l nil))
    (dotimes (i n l) (push initial-element l))))

(defun butlast (l &optional (n 1))
  (let ((r nil))
    (dotimes (i (- (length l) n) (nreverse r))
      (push (pop l) r))))

(defun acons (key datum alist) (cons (cons key datum) alist))

(defun pairlis (keys data &optional alist)
  (dolist (k keys alist) (push (cons k (pop data)) alist)))

(defun rassoc (item alist)
  (dolist (p alist) (when (eql (cdr p) item) (return p))))

(defun subst (new old tree)
  (cond ((eql tree old) new)
        ((atom tree) tree)
        (t (cons (subst new old (car tree)) (subst new old (cdr tree))))))

;;; Sequences (lists)

(defun remove (item l)
  (let ((r nil))
    (dolist (x l (nreverse r)) (unless (eql x item) (push x r)))))

(defun remove-if (pred l)
  (let ((r nil))
    (dolist (x l (nreverse r)) (unless (funcall pred x) (push x r)))))

(defun remove-if-not (pred l)
  (let ((r nil))
    (dolist (x l (nreverse r)) (when (funcall pred x) (push x r)))))

(defun find (item l)
  (dolist (x l) (when (eql x item) (return x))))

(defun find-if (pred l)
  (dolist (x l) (when (funcall pred x) (return x))))

(defun position (item l)
  (let ((i 0))
    (dolist (x l) (when (eql x item) (return i)) (incf i))))

(defun position-if (pred l)
  (let ((i 0))
    (dolist (x l) (when (funcall pred x) (return i)) (incf i))))

(defun count (item l)
  (let ((n 0))
    (dolist (x l n) (when (eql x item) (incf n)))))

(defun count-if (pred l)
  (let ((n 0))
    (dolist (x l n) (when (funcall pred x) (incf n)))))

(defun member-if (pred l)
  (loop (when (null l) (return nil))
        (when (funcall pred (car l)) (return l))
        (setq l (cdr l))))

(defun every (pred l)
  (dolist (x l t) (unless (funcall pred x) (return nil))))

(defun some (pred l)
  (dolist (x l nil) (let ((v (funcall pred x))) (when v (return v)))))

(defun notany (pred l) (not (some pred l)))

(defun notevery (pred l) (not (every pred l)))

(defun reduce (f l &optional (initial-value nil init-p))
  (let ((acc (cond (init-p initial-value)
                   (l (pop l))
                   (t (return-from reduce (funcall f))))))
    (dolist (x l acc) (setq acc (funcall f acc x)))))

(defun mapcan (f l) (apply #'nconc (mapcar f l)))

(defun maplist (f l)
  (let ((r nil))
    (loop (when (null l) (return (nreverse r)))
          (push (funcall f l) r)
          (setq l (cdr l)))))

;;; Sets

(defun adjoin (item l) (if (member item l) l (cons item l)))

(defun union (a b)
  (let ((r b))
    (dolist (x a r) (unless (member x b) (push x r)))))

(defun intersection (a b)
  (remove-if-not #'(lambda (x) (member x b)) a))

(defun set-difference (a b)
  (remove-if #'(lambda (x) (member x b)) a))

(defun subsetp (a b)
  (every #'(lambda (x) (member x b)) a))

;;; Numbers

(defun expt (base power)
  (if (and (integerp power) (>= power 0))
      (let ((r 1))
        (dotimes (i power r) (setq r (* r base))))
      (%pow base power)))

(defun gcd (a b)
  (if (zerop b) (abs a) (gcd b (mod a b))))

(defun signum (x)
  (cond ((plusp x) (if (floatp x) 1.0 1))
        ((minusp x) (if (floatp x) -1.0 -1))
        (t x)))

;;; Macros

(defmacro pushnew (item place)
  `(setf ,place (adjoin ,item ,place)))

(defmacro psetq (&rest pairs)
  (let ((binds nil) (sets nil))
    (loop (when (null pairs) (return))
          (let ((g (gensym)))
            (push (list g (cadr pairs)) binds)
            (push (car pairs) sets)
            (push g sets))
          (setq pairs (cddr pairs)))
    `(let ,(nreverse binds) (setq ,@(nreverse sets)) nil)))

(defmacro do (vars end &body body)
  (let ((steps nil))
    (dolist (v vars)
      (when (and (consp v) (cddr v))
        (push (car v) steps)
        (push (caddr v) steps)))
    `(let ,(mapcar #'(lambda (v) (if (consp v) (list (car v) (cadr v)) v)) vars)
       (loop (when ,(car end) (return (progn ,@(cdr end))))
             ,@body
             (psetq ,@(nreverse steps))))))

(defmacro do* (vars end &body body)
  (let ((steps nil))
    (dolist (v vars)
      (when (and (consp v) (cddr v))
        (push (car v) steps)
        (push (caddr v) steps)))
    `(let* ,(mapcar #'(lambda (v) (if (consp v) (list (car v) (cadr v)) v)) vars)
       (loop (when ,(car end) (return (progn ,@(cdr end))))
             ,@body
             (setq ,@(nreverse steps))))))
