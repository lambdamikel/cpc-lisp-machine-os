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

(defun subst (new old tree)
  (cond ((eql tree old) new)
        ((atom tree) tree)
        (t (cons (subst new old (car tree)) (subst new old (cdr tree))))))

;;; Sequences: lists, strings and vectors. A string or a vector is worked
;;; through as a list (%seq) and the result made the same kind (%like).
;;; :test, :test-not and :key as in CL; :start, :end and :from-end are
;;; not taken (they are let be, as unknown keys are).

(defun %seq (s) (if (listp s) s (coerce s 'list)))

(defun %like (s l)
  (cond ((listp s) l) ((stringp s) (coerce l 'string)) (t (coerce l 'vector))))

(defun %eqf (item test test-not)
  (cond (test-not #'(lambda (x) (not (funcall test-not item x))))
        (test #'(lambda (x) (funcall test item x)))
        (t #'(lambda (x) (eql item x)))))

(defun %pos (p seq key)
  (let ((i 0))
    (dolist (x (%seq seq))
      (when (funcall p (if key (funcall key x) x)) (return (cons i x)))
      (incf i))))

(defun find (item seq &key test test-not key)
  (cdr (%pos (%eqf item test test-not) seq key)))
(defun find-if (p seq &key key) (cdr (%pos p seq key)))
(defun find-if-not (p seq &key key) (cdr (%pos (complement p) seq key)))

(defun position (item seq &key test test-not key)
  (car (%pos (%eqf item test test-not) seq key)))
(defun position-if (p seq &key key) (car (%pos p seq key)))
(defun position-if-not (p seq &key key) (car (%pos (complement p) seq key)))

(defun %count (p seq key)
  (let ((n 0))
    (dolist (x (%seq seq) n) (when (funcall p (if key (funcall key x) x)) (incf n)))))
(defun count (item seq &key test test-not key)
  (%count (%eqf item test test-not) seq key))
(defun count-if (p seq &key key) (%count p seq key))
(defun count-if-not (p seq &key key) (%count (complement p) seq key))

(defun %remove (p seq key count)
  (let ((r nil) (n 0))
    (dolist (x (%seq seq) (%like seq (nreverse r)))
      (if (and (or (null count) (< n count)) (funcall p (if key (funcall key x) x)))
          (incf n)
          (push x r)))))
(defun remove (item seq &key test test-not key count)
  (%remove (%eqf item test test-not) seq key count))
(defun remove-if (p seq &key key count) (%remove p seq key count))
(defun remove-if-not (p seq &key key count) (%remove (complement p) seq key count))
(defun delete (item seq &rest keys) (apply #'remove item seq keys))
(defun delete-if (p seq &rest keys) (apply #'remove-if p seq keys))
(defun delete-if-not (p seq &rest keys) (apply #'remove-if-not p seq keys))

(defun remove-duplicates (seq &key test test-not key)
  (let ((r nil) (l (%seq seq)))
    (loop (when (null l) (return (%like seq (nreverse r))))
          (let ((x (pop l)))
            (unless (%pos (%eqf (if key (funcall key x) x) test test-not) l key)
              (push x r))))))
(defun delete-duplicates (seq &rest keys) (apply #'remove-duplicates seq keys))

(defun %subst (new p seq key)
  (let ((r nil))
    (dolist (x (%seq seq) (%like seq (nreverse r)))
      (push (if (funcall p (if key (funcall key x) x)) new x) r))))
(defun substitute (new old seq &key test test-not key)
  (%subst new (%eqf old test test-not) seq key))
(defun substitute-if (new p seq &key key) (%subst new p seq key))
(defun nsubstitute (new old seq &rest keys) (apply #'substitute new old seq keys))

(defun search (a b &key test test-not key)
  (let ((a (%seq a)) (b (%seq b)) (i 0)
        (f (cond (test-not #'(lambda (x y) (not (funcall test-not x y))))
                 (test test) (t #'eql))))
    (loop (do ((p a (cdr p)) (q b (cdr q)))
              ((null p) (return-from search i))
            (when (or (null q)
                      (not (funcall f (if key (funcall key (car p)) (car p))
                                    (if key (funcall key (car q)) (car q)))))
              (return)))
          (when (null b) (return nil))
          (pop b) (incf i))))

(defun member-if (p l &key key)
  (loop (when (null l) (return nil))
        (when (funcall p (if key (funcall key (car l)) (car l))) (return l))
        (setq l (cdr l))))
(defun member-if-not (p l &key key) (member-if (complement p) l :key key))

(defun assoc-if (p alist &key key)
  (dolist (x alist) (when (and x (funcall p (if key (funcall key (car x)) (car x)))) (return x))))
(defun rassoc-if (p alist &key key)
  (dolist (x alist) (when (and x (funcall p (if key (funcall key (cdr x)) (cdr x)))) (return x))))

(defun every (p seq &rest more)
  (if more
      (let ((ls (mapcar #'%seq (cons seq more))))
        (loop (when (member nil ls) (return t))
              (unless (apply p (mapcar #'car ls)) (return nil))
              (setq ls (mapcar #'cdr ls))))
      (dolist (x (%seq seq) t) (unless (funcall p x) (return nil)))))

(defun some (p seq &rest more)
  (if more
      (let ((ls (mapcar #'%seq (cons seq more))))
        (loop (when (member nil ls) (return nil))
              (let ((v (apply p (mapcar #'car ls)))) (when v (return v)))
              (setq ls (mapcar #'cdr ls))))
      (dolist (x (%seq seq) nil) (let ((v (funcall p x))) (when v (return v))))))

(defun notany (p seq &rest more) (not (apply #'some p seq more)))

(defun notevery (p seq &rest more) (not (apply #'every p seq more)))

(defun reduce (f seq &key key from-end (initial-value nil init-p))
  (let ((l (%seq seq)))
    (when key (setq l (mapcar key l)))
    (when from-end (setq l (reverse l)))
    (let ((acc (cond (init-p initial-value)
                     (l (pop l))
                     (t (return-from reduce (funcall f))))))
      (dolist (x l acc) (setq acc (if from-end (funcall f x acc) (funcall f acc x)))))))

(defun map (type f seq &rest more)
  (let ((r (apply #'mapcar f (%seq seq) (mapcar #'%seq more))))
    (cond ((null type) nil) ((eq type 'list) r) (t (coerce r type)))))

(defun mapcan (f l &rest more) (apply #'nconc (apply #'mapcar f l more)))

(defun maplist (f l)
  (let ((r nil))
    (loop (when (null l) (return (nreverse r)))
          (push (funcall f l) r)
          (setq l (cdr l)))))

(defun subseq (seq start &optional end)
  (if (stringp seq)
      (if end (%subseq seq start end) (%subseq seq start))
      (let ((l (nthcdr start (%seq seq))) (r nil))
        (if end
            (dotimes (i (- end start)) (when (null l) (error "index out of range")) (push (pop l) r))
            (setq r (reverse l)))
        (%like seq (nreverse r)))))

(defun copy-seq (s) (subseq s 0))

(defun concatenate (type &rest seqs)
  (if (member type '(string simple-string))
      (apply #'%concatenate type
             (mapcar #'(lambda (s) (if (stringp s) s (coerce s 'string))) seqs))
      (let ((l (apply #'append (mapcar #'(lambda (s) (copy-list (%seq s))) seqs))))
        (if (eq type 'list) l (coerce l type)))))

(defun fill (seq item &key (start 0) end)
  (if (listp seq)
      (do ((l (nthcdr start seq) (cdr l)) (i start (1+ i)))
          ((or (null l) (and end (>= i end))) seq)
        (setf (car l) item))
      (do ((i start (1+ i))) ((>= i (or end (length seq))) seq)
        (setf (aref seq i) item))))

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

;;; Music

;; (note 'c4) -> the period SOUND wants: a letter, then # (sharp) or B
;; (flat), then the octave (4 if none). C4 is middle C, 478, and A4 284, as
;; in the CPC manual's table (period = 125000 / frequency); the table below
;; is octave 1.
(defun note (n)
  (let* ((s (string n)) (k (position (char s 0) "C D EF G A B")) (i 1) (o 4))
    (unless k (error "not a note:" n))
    (when (> (length s) 1)
      (case (char s 1) (#\# (incf k) (incf i)) (#\B (decf k) (incf i))))
    (when (> (length s) i) (setq o (digit-char-p (char s i))))
    (cond ((< k 0) (setq k 11) (decf o))
          ((> k 11) (setq k 0) (incf o)))
    (let ((p (nth k '(3822 3608 3405 3214 3034 2863 2703 2551 2408 2273 2145 2025))))
      (if (< o 1) (ash p 1) (ash (+ p (ash 1 (- o 2))) (- 1 o))))))

;; (play '(c4 e4 g4 (c5 40) r c5)): each note for duration 1/100 s, or as
;; long as its list says; R is a rest
(defun play (notes &optional (duration 20) (channels 1) (volume 12))
  (dolist (n notes)
    (let ((d duration))
      (when (consp n) (setq d (cadr n) n (car n)))
      (if (eq n 'r)
          (sound channels 0 d 0)
          (sound channels (note n) d volume)))))

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
