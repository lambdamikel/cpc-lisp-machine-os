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
;;; find, position, count, remove, delete, substitute (and their -if,
;;; -if-not) are native, with all CL's keywords (lib/seqfn.asm).

(defun %seq (s) (if (listp s) s (coerce s 'list)))

(defun %like (s l)
  (cond ((listp s) l) ((stringp s) (coerce l 'string)) (t (coerce l 'vector))))

(defun remove-duplicates (seq &key test test-not key)
  (let ((r nil) (l (%seq seq)))
    (loop (when (null l) (return (%like seq (nreverse r))))
          (let ((x (pop l)))
            (unless (position (if key (funcall key x) x) l :test test :test-not test-not :key key)
              (push x r))))))
(defun delete-duplicates (seq &rest keys) (apply #'remove-duplicates seq keys))

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

;;; Errors. (error "format string" args...) signals one; ignore-errors and
;;; handler-case catch them (through the core's %catch-errors, which gives
;;; (T . value) or (NIL . (message . objects))). A condition is its message,
;;; a string: (format t "~A" c) shows it. ESC is never caught.

(defun error (datum &rest args)
  (%signal (if (stringp datum) (apply #'format nil datum args) (princ-to-string datum))))

(defun warn (datum &rest args)
  (fresh-line)
  (princ "Warning: ")
  (if (stringp datum) (apply #'format t datum args) (princ datum))
  (terpri)
  nil)

(defmacro assert (form &rest ignore)
  `(unless ,form (error "assertion failed: ~S" ',form)))

(defun %condition (c)
  (if (cdr c) (format nil "~A ~S" (car c) (cadr c)) (car c)))

(defmacro ignore-errors (&body body)
  (let ((r (gensym)))
    `(let ((,r (%catch-errors (progn ,@body))))
       (if (car ,r) (cdr ,r) (values nil (%condition (cdr ,r)))))))

;; (handler-case form (error (c) body...) (:no-error (v) body...)): every
;; error is one kind, so the first clause that is not :no-error takes it
(defmacro handler-case (form &rest clauses)
  (let ((r (gensym))
        (err (find :no-error clauses :key #'car :test-not #'eq))
        (ok (find :no-error clauses :key #'car)))
    `(let ((,r (%catch-errors ,form)))
       (if (car ,r)
           ,(if ok
                `(let ((,(or (car (cadr ok)) (gensym)) (cdr ,r))) ,@(cddr ok))
                `(cdr ,r))
           ,(if err
                `(let ((,(or (car (cadr err)) (gensym)) (%condition (cdr ,r))))
                   ,@(cddr err))
                `(%signal (%condition (cdr ,r))))))))

;;; Questions

(defun y-or-n-p (&optional message &rest args)
  (loop (when message (fresh-line) (apply #'format t message args))
        (princ " (y or n) ")
        (let ((c (char-downcase (read-char))))
          (princ c)
          (terpri)
          (cond ((char= c #\y) (return t))
                ((char= c #\n) (return nil))))))

(defun yes-or-no-p (&optional message &rest args)
  (apply #'y-or-n-p message args))

;;; Music

;; (note 'c4) -> the period SOUND wants: a letter, then # (sharp) or B
;; (flat), then the octave (4 if none). The CPC's AY runs at 1 MHz: period
;; = 62500 / frequency, so C4 (middle C) is 239 and A4 (440 Hz) 142 --
;; measured in MAME. The table below is octave 0.
(defun note (n)
  (let* ((s (string n)) (k (position (char s 0) "C D EF G A B")) (i 1) (o 4))
    (unless k (error "not a note: ~A" n))
    (when (> (length s) 1)
      (case (char s 1) (#\# (incf k) (incf i)) (#\B (decf k) (incf i))))
    (when (> (length s) i) (setq o (digit-char-p (char s i))))
    (cond ((< k 0) (setq k 11) (decf o))
          ((> k 11) (setq k 0) (incf o)))
    (ash (+ (nth k '(3822 3608 3405 3214 3034 2863 2703 2551 2408 2273 2145 2025))
            (ash 1 (1- o)))
         (- o))))

;; (play '(c4 e4 g4 (c5 40) r c5)): each note for duration 1/100 s, or as
;; long as its list says; R is a rest
(defun play (notes &optional (duration 20) (channels 1) (volume 12))
  (dolist (n notes)
    (let ((d duration))
      (when (consp n) (setq d (cadr n) n (car n)))
      (if (eq n 'r)
          (sound channels 0 d 0)
          (sound channels (note n) d volume)))))

;;; Multiple values (values and multiple-value-list are built in)

(defmacro multiple-value-bind (vars form &body body)
  (let ((g (gensym)))
    `(apply #'(lambda (&optional ,@vars &rest ,g) ,@body)
            (multiple-value-list ,form))))

(defmacro nth-value (n form) `(nth ,n (multiple-value-list ,form)))

(defmacro multiple-value-call (f &rest forms)
  `(apply ,f (append ,@(mapcar #'(lambda (x) `(multiple-value-list ,x)) forms))))

(defmacro multiple-value-prog1 (form &body body)
  (let ((g (gensym)))
    `(let ((,g (multiple-value-list ,form))) ,@body (values-list ,g))))

(defmacro multiple-value-setq (vars form)
  (let ((g (gensym)) (i -1))
    `(let ((,g (multiple-value-list ,form)))
       (setq ,@(mapcan #'(lambda (v) (list v `(nth ,(incf i) ,g))) vars))
       (car ,g))))

(defun values-list (l) (apply #'values l))

;;; setf on more places: (defsetf access update) -- (setf (access a...) v)
;;; calls (update a... v). The core looks for the SETF property.

(defmacro defsetf (access update)
  `(progn (setf (get ',access 'setf) ',update) ',access))

;;; Structures: (defstruct point x (y 0)), or (defstruct (point options) ...)
;;; with :conc-name, :constructor, :predicate, :copier. make-point takes
;;; the slots as keys; point-x reads one and setf writes it; point-p and
;;; copy-point. An instance prints as #S(POINT 1 0).

(defun %sym (&rest parts) (intern (apply #'concatenate 'string (mapcar #'string parts))))

(defmacro defstruct (name &rest slots)
  (let* ((opts (if (consp name) (cdr name)))
         (name (if (consp name) (car name) name))
         (conc (%sym name "-"))
         (make (%sym "MAKE-" name))
         (pred (%sym name "-P"))
         (copy (%sym "COPY-" name))
         (i 0) (forms nil))
    (dolist (o opts)
      (when (consp o)
        (case (car o)
          (:conc-name (setq conc (or (cadr o) "")))
          (:constructor (setq make (cadr o)))
          (:predicate (setq pred (cadr o)))
          (:copier (setq copy (cadr o))))))
    (when (stringp (car slots)) (pop slots))
    (dolist (s slots)
      (let ((acc (%sym conc (if (consp s) (car s) s))) (k (incf i)))
        (push `(defun ,acc (s) (%struct-ref s ,k ',name)) forms)
        (push `(setf (get ',acc 'setf) #'(lambda (s v) (%struct-set s ,k v ',name))) forms)))
    `(progn
       ,@(when make
           `((defun ,make (&key ,@(mapcar #'(lambda (s) (if (consp s) (list (car s) (cadr s)) s)) slots))
               (%make-struct ',name ,@(mapcar #'(lambda (s) (if (consp s) (car s) s)) slots)))))
       ,@(when pred `((defun ,pred (x) (%struct-is x ',name))))
       ,@(when copy `((defun ,copy (x) (copy-structure x))))
       ,@(nreverse forms)
       ',name)))

;;; Hash tables: a structure (HASH-TABLE test count buckets), the buckets a
;;; vector of alists; a key's bucket is its hash -- sxhash for EQUAL tables,
;;; %eqhash for EQ and EQL ones -- modulo their number. A table does not
;;; grow its buckets: :size says how many (16). gethash, %puthash (setf
;;; gethash) and remhash are native (lib/structs.asm).

(defun make-hash-table (&key (test 'eql) (size 16))
  (%make-struct 'hash-table
                (cond ((member test (list 'eq #'eq)) 'eq)
                      ((member test (list 'equal #'equal 'equalp)) 'equal)
                      (t 'eql))
                0
                (make-array (max 1 (min size 250)))))

(defun hash-table-p (x) (%struct-is x 'hash-table))
(defun hash-table-count (h) (%struct-ref h 2 'hash-table))
(defun hash-table-test (h) (%struct-ref h 1 'hash-table))

(defsetf gethash %puthash)

(defun clrhash (h)
  (fill (%struct-ref h 3 'hash-table) nil)
  (%struct-set h 2 0 'hash-table)
  h)

(defun maphash (f h)
  (let ((b (%struct-ref h 3 'hash-table)))
    (dotimes (i (length b)) (dolist (e (aref b i)) (funcall f (car e) (cdr e))))))

;;; Types

(defun type-of (x)
  (cond ((null x) 'null) ((eq x t) 'boolean) ((integerp x) 'fixnum)
        ((floatp x) 'single-float) ((keywordp x) 'keyword)
        ((symbolp x) 'symbol) ((consp x) 'cons) ((stringp x) 'string)
        ((characterp x) 'character) ((%struct-type x)) ((vectorp x) 'vector)
        ((functionp x) 'function) (t t)))

(defun typep (x type)
  (if (consp type)
      (%typep-list x (car type) (cdr type))
      (case type
        ((t) t)
        ((nil) nil)
        ((integer fixnum rational) (integerp x))
        ((float single-float double-float short-float long-float) (floatp x))
        ((number real) (numberp x))
        (bit (or (eql x 0) (eql x 1)))
        (symbol (symbolp x))
        (keyword (keywordp x))
        (boolean (or (eq x t) (null x)))
        (cons (consp x))
        (list (listp x))
        (null (null x))
        (atom (atom x))
        ((string simple-string) (stringp x))
        ((character base-char standard-char) (characterp x))
        ((vector array) (or (vectorp x) (stringp x)))
        (simple-vector (vectorp x))
        (sequence (or (listp x) (vectorp x) (stringp x)))
        ((function compiled-function) (functionp x))
        (structure-object (if (%struct-type x) t nil))
        (otherwise
         (let ((d (get type '%deftype)))
           (if d (typep x (funcall d)) (%struct-is x type)))))))

(defun %typep-list (x head args)
  (case head
    (or (some (lambda (ty) (typep x ty)) args))
    (and (every (lambda (ty) (typep x ty)) args))
    (not (not (typep x (car args))))
    (member (if (member x args) t nil))
    (eql (eql x (car args)))
    (satisfies (if (funcall (car args) x) t nil))
    (mod (and (integerp x) (<= 0 x) (< x (car args))))
    ((integer fixnum float single-float real number)
     (and (typep x head) (%in-range x (car args) (cadr args))))
    (otherwise
     (let ((d (get head '%deftype)))
       (if d (typep x (apply d args)) (typep x head))))))

(defun %in-range (x lo hi)
  (and (cond ((or (null lo) (eq lo '*)) t) ((consp lo) (> x (car lo)))
             (t (>= x lo)))
       (cond ((or (null hi) (eq hi '*)) t) ((consp hi) (< x (car hi)))
             (t (<= x hi)))))

(defmacro deftype (name args &body body)
  `(progn (setf (get ',name '%deftype) (lambda ,args ,@body)) ',name))

(defmacro check-type (place type)
  `(unless (typep ,place ',type)
     (error "~S is not of type ~S" ,place ',type)))

(defmacro typecase (key &body clauses)
  (let ((k (gensym)))
    `(let ((,k ,key))
       (cond ,@(mapcar (lambda (c)
                         (cons (if (member (car c) '(t otherwise)) t
                                   `(typep ,k ',(car c)))
                               (or (cdr c) '(nil))))
                       clauses)))))

(defmacro etypecase (key &body clauses)
  (let ((k (gensym)))
    `(let ((,k ,key))
       (typecase ,k ,@clauses
         (otherwise (error "~S fits no clause of etypecase" ,k))))))

;;; Files as streams. The firmware has one file open for input and one for
;;; output at a time; a stream is #S(FILE-STREAM name direction open-p), and
;;; the printers and readers (lib/streams.asm) take it as their stream.

(defun open (name &key (direction :input))
  (%open name (eq direction :output))
  (%make-struct 'file-stream name direction t))

(defun close (stream &key abort)
  (when (%struct-ref stream 3 'file-stream)
    (%struct-set stream 3 nil 'file-stream)
    (%close (eq (%struct-ref stream 2 'file-stream) :output))))

(defmacro with-open-file (spec &body body)
  `(let ((,(car spec) (open ,@(cdr spec))))
     (unwind-protect (progn ,@body) (close ,(car spec)))))

(defun streamp (x) (%struct-is x 'file-stream))
(defun open-stream-p (s) (%struct-ref s 3 'file-stream))
(defun input-stream-p (s) (eq (%struct-ref s 2 'file-stream) :input))
(defun output-stream-p (s) (eq (%struct-ref s 2 'file-stream) :output))
(defun probe-file (name)
  (when (car (%catch-errors (%open name nil))) (%close nil) name))

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
  ;; the steps go through temporaries in a LET: no macro is left in the
  ;; expansion, so nothing is expanded again on each pass of the loop
  (let ((temps nil) (sets nil))
    (dolist (v vars)
      (when (and (consp v) (cddr v))
        (let ((g (gensym)))
          (push (list g (caddr v)) temps)
          (push (car v) sets)
          (push g sets))))
    `(let ,(mapcar #'(lambda (v) (if (consp v) (list (car v) (cadr v)) v)) vars)
       (loop (when ,(car end) (return (progn ,@(cdr end))))
             ,@body
             ,@(when temps `((let ,(nreverse temps) (setq ,@(nreverse sets)))))))))

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
