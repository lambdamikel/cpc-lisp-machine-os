;;; CPC Lisp -- the compiler: Lisp to the bytecode of the VM ROM
;;; (lib/vm.asm, which keeps this text and reads a function of it the
;;; first time it is called).
;;;
;;; (compile 'name) compiles name's interpreted definition in place;
;;; (compile nil '(lambda ...)) gives a compiled function.
;;; (disassemble 'name) shows the code.
;;;
;;; A function's code is a list of items, last first, in *cc-code*: a
;;; byte; a label, (NIL . its position); a jump, (op label . bytes before
;;; the offset). The VM's operation k is the byte 3k (CC-EMIT takes k).
;;; *cc-depth* counts the words pushed under the frame: a local's place
;;; is known from it (ix - 2(d+1) for the d-th; the arguments of a plain
;;; lambda list are at ix + 20 + 2(n-1-i)).
;;;
;;; The environment is a list of entries:
;;;   (0 name fn disp boxed key)  a variable: fn its function's context,
;;;       disp its place, boxed T if the place holds a cons around the
;;;       value; key the cons in the source whose car names it
;;;   (1 name)                    a special variable bound here
;;;   (2 name var)                a local function, held in variable var
;;;   (3 name label depth fn key tail tag)  a block
;;;   (4 disp)                    special bindings made: V_SPECS was at disp
;;; A function's context is (closed...): the variables of functions around
;;; it that it uses, in order -- CLO k is the kth. A variable used from an
;;; inner function and also assigned somewhere is boxed. That is known only
;;; once all its uses are seen: *cc-flags* has, per key, 1 used from inside,
;;; 2 assigned (4 for a block: returned to from inside); when what a pass
;;; assumed turns out wrong, *cc-again* says so, and the function is
;;; compiled again with what is known now.

(defvar *cc-code* nil)
(defvar *cc-consts* nil)
(defvar *cc-depth* 0)
(defvar *cc-fn* nil)
(defvar *cc-flags* nil)
(defvar *cc-again* nil)
(defvar *cc-self* nil)
(defvar *cc-mexp* nil)
(defvar *cc-tmp* nil)

(defun compile (name &optional def)
  (let ((f (or def (symbol-function name))) (r nil))
    (when (and (consp f) (eq (car f) 'lambda))
      (setq f (cons (cons (cadr f) (cddr f)) nil)))
    (when (eql (%fn-info f) 2)
      (setq f (%fn-data f)))
    (if (and (consp f) (consp (car f)))
        (if (cdr f)
            (progn (format t "~&;; ~A closes over variables: not compiled~%" name)
                   (setq f nil))
            (progn
              (setq r (%catch-errors (cc-top name (caar f) (cdar f))))
              (if (car r)
                  (setq f (cdr r))
                  (progn (format t "~&;; ~A not compiled: ~A~{ ~S~}~%" name (cadr r) (cddr r))
                         (setq f nil)))))
        (unless (member (%fn-info f) '(3 4)) (setq f nil)))
    (%vm-release)
    (if (and f name)
        (progn (setf (symbol-function name) f) name)
        f)))

(defun cc-top (name ll body)
  (let ((*cc-flags* nil) (*cc-mexp* nil) (*cc-tmp* (list nil)) (r nil))
    (%loop
      (let ((*cc-again* nil) (*cc-self* nil))
        (setq r (car (cc-lambda name ll body nil t)))
        (unless *cc-again* (return r))))))

;; cc-lambda: a function -> (its code . the variables it closes over)
(defun cc-lambda (name ll body env top)
  (let ((*cc-code* nil) (*cc-consts* nil) (*cc-depth* 0) (*cc-fn* (list nil)))
    (setq env (cc-params name ll env top))
    (cc-body body env t)
    (cons (%make-code (cc-assemble (reverse *cc-code*)) *cc-consts* name)
          (car *cc-fn*))))

(defun cc-fail (x) (error "cannot compile ~S" x))
(defun cc-limit (what) (error what))

;; f on each cons of l
(defun cc-cells (f l)
  (%loop (when (null l) (return)) (funcall f l) (setq l (cdr l))))

;;; ------------------------------------------------------------ emitting

(defun cc-emit (op &rest bytes)
  (push (* 3 op) *cc-code*)
  (dolist (b bytes) (push b *cc-code*))
  (setq *cc-depth* (+ *cc-depth* (nth op '(0 1 1 1 1 1 0 1 0 1  1 0 1 0 0 1 1 1 1 1
      1 1 1 -1 1 0 0 -1 -1 -1  -1 0 0 0 0 0 1 1 0 0  -1 -1 0 0 0 -1 -1 0 0 -1
      -1 -1 -1 -1 -1 -1 0 0 -1 0  1 -1 0 0 0 0 1 0 0 0  -1 0 -1 -1 -1 -1 1 0 1 0
      0 0 -1 -1 -2)))))

(defun cc-label () (list nil))
(defun cc-place (l) (push l *cc-code*))
(defun cc-jump (op l &rest bytes)
  (push (cons (if (< 25 op 31) (+ op 45) op) (cons l bytes)) *cc-code*)
  (when (member op '(27 28 29 30)) (decf *cc-depth*)))
(defun cc-jlen (i) (+ (if (> (car i) 70) 2 3) (length (cddr i))))

(defun cc-assemble (items)
  (let ((pos 0) (out nil) (again t))
    (%loop
      (unless again (return))
      (setq again nil pos 0)
      (dolist (i items)
        (cond ((numberp i) (incf pos))
              ((car i) (incf pos (cc-jlen i)))
              (t (rplacd i pos))))
      (setq pos 0)
      (dolist (i items)
        (cond ((numberp i) (incf pos))
              ((car i) (incf pos (cc-jlen i))
               (when (and (> (car i) 70) (not (< -129 (- (cdr (cadr i)) pos) 128)))
                 (rplaca i (- (car i) 45))
                 (setq again t))))))
    (setq pos 0)
    (dolist (i items (nreverse out))
      (cond ((numberp i) (push i out) (incf pos))
            ((car i)
             (push (* 3 (car i)) out)
             (dolist (b (cddr i)) (push b out))
             (incf pos (cc-jlen i))
             (let ((off (- (cdr (cadr i)) pos)))
               (push (mod off 256) out)
               (unless (> (car i) 70) (push (mod (floor off 256) 256) out))))))))

(defun cc-const (x)
  (let ((p (position x *cc-consts*)))
    (or p (cc-new-const x))))
(defun cc-new-const (x)
  (setq *cc-consts* (append *cc-consts* (list x)))
  (let ((n (1- (length *cc-consts*))))
    (if (> n 255) (cc-limit "too many constants") n)))

(defun cc-literal (x)
  (cond ((null x) (cc-emit 2))
        ((eq x t) (cc-emit 3))
        ((and (integerp x) (< -129 x 128)) (cc-emit 4 (mod x 256)))
        (t (cc-emit 1 (cc-const x)))))

(defun cc-tail (tail) (when tail (cc-emit 33)))

;; cc-loc: LOC (5), LOCB (7), SETLOC (6), SETLOCB (8), POPLOC (70) at disp
(defun cc-loc (op d)
  (cond ((and (= op 5) (member d '(20 22 24 26))) (cc-emit (+ 15 (floor (- d 20) 2))))
        ((and (= op 5) (member d '(-2 -4 -6 -8))) (cc-emit (- 18 (floor d 2))))
        (t (cc-emit op (mod d 256)))))

;;; ------------------------------------------------------------ variables

(defun cc-lookup (x env)
  (dolist (e env nil)
    (when (and (< (car e) 2) (eq (cadr e) x)) (return e))))

(defun cc-fnlookup (x env)
  (dolist (e env nil)
    (when (and (= (car e) 2) (eq (cadr e) x)) (return e))))

(defun cc-flag (key) (or (cdr (assoc key *cc-flags*)) 0))

(defun cc-mark (v bit)
  (let ((e (assoc (nth 5 v) *cc-flags*)))
    (unless e (setq e (cons (nth 5 v) 0)) (push e *cc-flags*))
    (unless (cc-bit (cdr e) bit) (rplacd e (+ (cdr e) bit)))
    (when (and (not (nth 4 v)) (= (mod (cdr e) 4) 3)) (setq *cc-again* t))))

;; the index of v among the variables this function closes over
(defun cc-closed (v)
  (cc-mark v 1)
  (or (position v (car *cc-fn*))
      (progn (rplaca *cc-fn* (append (car *cc-fn*) (list v)))
             (1- (length (car *cc-fn*))))))

;; push v's value; cc-raw: what its place holds (the box, if boxed)
(defun cc-ref (v)
  (if (eq (nth 2 v) *cc-fn*)
      (cc-loc (if (nth 4 v) 7 5) (nth 3 v))
      (cc-emit (if (nth 4 v) 10 9) (cc-closed v))))
(defun cc-raw (v)
  (if (eq (nth 2 v) *cc-fn*)
      (cc-loc 5 (nth 3 v))
      (cc-emit 9 (cc-closed v))))

;; the top of the stack into v (it stays there)
(defun cc-set (v)
  (cc-mark v 2)
  (if (eq (nth 2 v) *cc-fn*)
      (cc-loc (if (nth 4 v) 8 6) (nth 3 v))
      (let ((k (cc-closed v)))
        (when (nth 4 v) (cc-emit 11 k)))))

(defun cc-var (x env)
  (if (or (null x) (eq x t) (keywordp x))
      (cc-literal x)
      (let ((v (cc-lookup x env)))
        (if (and v (= (car v) 0)) (cc-ref v) (cc-emit 12 (cc-const x))))))

(defun cc-setvar (x env)
  (let ((v (if (consp x) (cdr x) (cc-lookup x env))))
    (cond ((and v (= (car v) 0)) (cc-set v))
          ((cc-bit (%symbol-flags x) 2) (cc-fail x))
          (t (cc-emit 13 (cc-const x))))))

;; a new variable: the value just pushed is its place. -> the entry
(defun cc-newvar (name key)
  (let ((box (= (mod (cc-flag key) 4) 3)))
    (when box (cc-emit 14))
    (list 0 name *cc-fn* (* -2 *cc-depth*) box key)))

;; a hidden variable (a form refers to it as (*cc-tmp* . entry))
(defun cc-tmp () (cc-newvar nil (list nil)))
(defun cc-tmpref (v) (cons *cc-tmp* v))

(defun cc-special-p (x) (cc-bit (%symbol-flags x) 1))
(defun cc-bit (x b) (oddp (floor x b)))

;;; ------------------------------------------------------------ forms

(defun cc (x env tail)
  (cond ((symbolp x) (cc-var x env) (cc-tail tail))
        ((atom x) (cc-literal x) (cc-tail tail))
        (t (cc-form x env tail))))

(defun cc-body (forms env tail)
  (if (null forms)
      (progn (cc-literal nil) (cc-tail tail))
      (%loop
        (when (null (cdr forms)) (return (cc (car forms) env tail)))
        (unless (or (atom (car forms)) (eq (caar forms) 'declare))
          (cc (car forms) env nil)
          (cc-emit 23))
        (setq forms (cdr forms)))))

(defun cc-args (args env) (dolist (a args) (cc a env nil)))

(defun cc-form (x env tail)
  (let ((op (car x)) (a (cdr x)))
    (cond ((eq op *cc-tmp*) (cc-ref a) (cc-tail tail))
          ((consp op)
           (if (eq (car op) 'lambda) (cc-call (cons 'funcall x) env tail) (cc-fail x)))
          ((cc-fnlookup op env)
           (cc-ref (nth 2 (cc-fnlookup op env)))
           (cc-args a env)
           (cc-callop (length a) tail))
          (t (case op
               (quote (cc-literal (car a)) (cc-tail tail))
               (function (cc-function (car a) env) (cc-tail tail))
               (lambda (cc-function x env) (cc-tail tail))
               (if (cc-if (car a) (cadr a) (caddr a) env tail))
               (when (cc-if (car a) (cons 'progn (cdr a)) nil env tail))
               (unless (cc-if (car a) nil (cons 'progn (cdr a)) env tail))
               (cond (cc-cond a env tail))
               (case (cc-case a env tail))
               ((and or) (cc-andor op a env tail))
               (progn (cc-body a env tail))
               (prog1 (cc (car a) env nil) (cc-effects (cdr a) env) (cc-tail tail))
               (setq (cc-setq a env) (cc-tail tail))
               ((setf incf decf push pop) (cc-setf op a env) (cc-tail tail))
               ((let let*) (cc-let op (car a) (cdr a) env tail))
               ((flet labels) (cc-flet op (car a) (cdr a) env tail))
               (block (cc-block x env tail))
               (return-from (cc-return (car a) (cadr a) env))
               (return (cc-return nil (car a) env))
               ((dolist dotimes) (cc-do op (car a) (cdr a) env) (cc-tail tail))
               (%loop (cc-loop a env) (cc-tail tail))
               (declare (cc-literal nil) (cc-tail tail))
               (the (cc (cadr a) env tail))
               (multiple-value-list
                (cc-emit 67) (cc (car a) env nil) (cc-emit 63) (cc-tail tail))
               (%expanded
                (cc (if (eq (caar a) (symbol-function (cadr a))) (cdar a) (cdr a)) env tail))
               (quasiquote (cc (cc-qq (car a)) env tail))
               (catch (cc (list '%catch (car a) (cons 'lambda (cons nil (cdr a)))) env tail))
               (throw (cc (cons '%throw a) env tail))
               (unwind-protect
                (cc (list '%unwind-protect (list 'lambda nil (car a))
                          (cons 'lambda (cons nil (cdr a)))) env tail))
               (%catch-errors (cc (list '%catch-errors-fn (cons 'lambda (cons nil a))) env tail))
               ((defun defmacro defvar defparameter defconstant) (cc-fail op))
               (t (if (eql (%fn-info op) 1)
                      (cc (cc-expand x) env tail)
                      (cc-call x env tail))))))))

(defun cc-effects (forms env)
  (dolist (f forms) (cc f env nil) (cc-emit 23)))

(defun cc-expand (x)
  (let ((e (assoc x *cc-mexp*)))
    (if e (cdr e)
        (let ((y (macroexpand-1 x)))
          (push (cons x y) *cc-mexp*)
          y))))

;; a call: an operation of the VM's for the usual builtins
(defun cc-call (x env tail)
  (let* ((op (car x)) (a (cdr x)) (n (length a))
         (p (cdr (assoc op '((car 38 . 1) (cdr 39 . 1) (first 38 . 1) (rest 39 . 1)
                             (cons 40 . 2) (eq 41 . 2) (not 42 . 1) (null 42 . 1)
                             (consp 43 . 1) (atom 44 . 1) (1+ 47 . 1) (1- 48 . 1)
                             (< 49 . 2) (> 50 . 2) (<= 51 . 2) (>= 52 . 2) (= 53 . 2)
                             (cadr 56 . 1) (second 56 . 1) (cddr 57 . 1) (eql 58 . 2)
                             (zerop 59 . 1) (symbolp 64 . 1) (oddp 80 . 1) (evenp 81 . 1)
                             (aref 83 . 2) (svref 83 . 2))))))
    (cond ((and p (= n (cdr p))) (cc-args a env) (cc-emit (car p)) (cc-tail tail))
          ((and (eq op 'funcall) a) (cc-args a env) (cc-callop (1- n) tail))
          ((and (eq op 'list) (< n 256))
           (cc-args a env) (cc-emit 62 n) (decf *cc-depth* (1- n)) (cc-tail tail))
          ((and (member op '(+ - *)) (> n 1))
           (cc (car a) env nil)
           (dolist (b (cdr a)) (cc b env nil) (cc-emit (cdr (assoc op '((+ . 45) (- . 46) (* . 82))))))
           (cc-tail tail))
          ((and (eq op '-) (= n 1)) (cc-literal 0) (cc (car a) env nil) (cc-emit 46) (cc-tail tail))
          ((and (eq op '+) (= n 0)) (cc-literal 0) (cc-tail tail))
          ((and tail *cc-self* (eq op (car *cc-self*)) (= n (cadr *cc-self*))
                (eq *cc-fn* (nth 3 *cc-self*)))
           (cc-args a env)
           (dotimes (i n) (cc-loc 70 (+ 20 (* 2 i))))
           (cc-emit 69)
           (cc-jump 26 (nth 2 *cc-self*)))
          (t (cc-args a env) (cc-callg op n tail)))))

;; CALLG/TCALLG k n: constant k's function, the arguments pushed
(defun cc-callg (f n tail)
  (if (> n 255) (cc-limit "too many arguments"))
  (if tail (cc-emit 77 (cc-const f) n) (progn (cc-emit 76 (cc-const f) n) (decf *cc-depth* n))))

(defun cc-callop (n tail)
  (if (> n 255) (cc-limit "too many arguments"))
  (if tail (cc-emit 32 n) (progn (cc-emit 31 n) (decf *cc-depth* n))))

(defun cc-function (f env)
  (cond ((and (symbolp f) (cc-fnlookup f env)) (cc-ref (nth 2 (cc-fnlookup f env))))
        ((symbolp f) (cc-emit 37 (cc-const f)))
        ((eq (car f) 'lambda) (cc-closure nil (cadr f) (cddr f) env))
        (t (cc-fail f))))

;; a closure: its code, and the places of what it closes over pushed
(defun cc-closure (name ll body env)
  (let ((g (cc-lambda name ll body env nil)))
    (dolist (v (cdr g)) (cc-raw v))
    (cc-emit 36 (cc-const (car g)) (length (cdr g)))
    (decf *cc-depth* (length (cdr g)))))

(defun cc-if (test then else env tail)
  (let ((l1 (cc-label)) (l2 (cc-label)) (d *cc-depth*))
    (cc test env nil)
    (cc-jump 27 l1)
    (cc then env tail)
    (unless tail (cc-jump 26 l2))
    (cc-place l1)
    (setq *cc-depth* d)
    (cc else env tail)
    (cc-place l2)))

(defun cc-cond (cl env tail)
  (let ((c (car cl)))
    (cond ((null cl) (cc-literal nil) (cc-tail tail))
          ((eq (car c) t) (cc-body (cdr c) env tail))
          ((null (cdr c)) (cc-andor 'or (list (car c) (cons 'cond (cdr cl))) env tail))
          (t (cc-if (car c) (cons 'progn (cdr c)) (cons 'cond (cdr cl)) env tail)))))

(defun cc-andor (op args env tail)
  (if (null args)
      (progn (cc-literal (eq op 'and)) (cc-tail tail))
      (let ((l (cc-label)))
        (%loop
          (when (null (cdr args)) (return (cc (car args) env tail)))
          (cc (car args) env nil)
          (cc-jump (if (eq op 'and) 29 30) l)
          (setq args (cdr args)))
        (cc-place l)
        (cc-tail tail))))

;; case: the key in a hidden variable, then ifs
(defun cc-case (a env tail)
  (cc (car a) env nil)
  (let* ((k (cc-tmp)) (r (cc-tmpref k)) (tests nil))
    (dolist (c (reverse (cdr a)))
      (setq tests
            (list 'if
                  (if (member (car c) '(t otherwise))
                      t
                      (cons 'or (mapcar #'(lambda (key) (list (if (or (symbolp key) (integerp key)
                                                                     (characterp key)) 'eq 'eql)
                                                                 r (list 'quote key)))
                                        (if (listp (car c)) (car c) (list (car c))))))
                  (cons 'progn (cdr c))
                  tests)))
    (cc tests env tail)
    (unless tail (cc-emit 25 1) (decf *cc-depth*))))

(defun cc-setq (a env)
  (if (null a) (cc-literal nil)
      (%loop
        (cc (cadr a) env nil)
        (cc-setvar (car a) env)
        (unless (cddr a) (return))
        (cc-emit 23)
        (setq a (cddr a)))))

;; setf and its friends. A place (acc args...) has its arguments put in
;; hidden variables first, so each is evaluated once.
(defun cc-setf (op a env)
  (case op
    (setf (if (null a) (cc-literal nil)
              (%loop
                (cc-store (car a) (cadr a) env)
                (unless (cddr a) (return))
                (cc-emit 23)
                (setq a (cddr a)))))
    ((incf decf)
     (cc-place-do (car a) env
                  #'(lambda (pl e)
                      (cc-store pl (list (if (eq op 'incf) '+ '-) pl (if (cdr a) (cadr a) 1)) e))))
    (push (cc (car a) env nil)
          (let ((v (cc-tmp)))
            (cc-place-do (cadr a) (cons v env)
                         #'(lambda (pl e) (cc-store pl (list 'cons (cc-tmpref v) pl) e)))
            (cc-emit 25 1) (decf *cc-depth*)))
    (pop (cc-place-do (car a) env
                      #'(lambda (pl e) (cc (list 'prog1 (list 'car pl) (list 'setf pl (list 'cdr pl))) e nil))))))

(defun cc-place-do (pl env f)
  (cond ((or (symbolp pl) (eq (car pl) *cc-tmp*)) (funcall f pl env))
        ((eql (%fn-info (car pl)) 1) (cc-place-do (cc-expand pl) env f))
        (t (let ((vs nil))
             (dolist (x (cdr pl))
               (cc x env nil)
               (push (cc-tmp) vs))
             (funcall f (cons (car pl) (mapcar #'cc-tmpref (reverse vs))) env)
             (when vs (cc-emit 25 (length vs)) (decf *cc-depth* (length vs)))))))

;; the value of form into place; it stays on the stack
(defun cc-store (pl form env)
  (cond ((symbolp pl) (cc form env nil) (cc-setvar pl env))
        ((eq (car pl) *cc-tmp*) (cc form env nil) (cc-set (cdr pl)))
        (t (let ((acc (car pl)) (a (cdr pl)))
             (cond ((member acc '(car first)) (cc (car a) env nil) (cc form env nil) (cc-emit 54))
                   ((member acc '(cdr rest)) (cc (car a) env nil) (cc form env nil) (cc-emit 55))
                   ((member acc '(cadr second))
                    (cc (car a) env nil) (cc-emit 39) (cc form env nil) (cc-emit 54))
                   ((and (member acc '(aref svref)) (= (length a) 2))
                    (cc (car a) env nil) (cc (cadr a) env nil) (cc form env nil)
                    (cc-emit 84 (cc-const '%set-aref)))
                   ((eql (%fn-info acc) 1) (cc-store (cc-expand pl) form env))
                   (t (let ((s (or (cdr (assoc acc '((aref . %set-aref) (svref . %set-aref)
                                                     (char . %set-char) (nth . %set-nth)
                                                     (get . %set-get) (symbol-value . set)
                                                     (symbol-function . %set-fn)
                                                     (symbol-plist . %set-plist))))
                                   (get acc 'setf)
                                   (cc-fail pl))))
                        (cc-args a env)
                        (cc form env nil)
                        (cc-callg s (1+ (length a)) nil))))))))

;; let and let*: each value pushed is its variable's place; special ones
;; are bound after (let) or as they come (let*), V_SPECS kept for UNBINDL
(defun cc-let (op bs body env tail)
  (let ((d *cc-depth*) (vs nil) (sp nil) (e2 env))
    (cc-cells #'(lambda (l)
      (let ((name (if (consp (car l)) (caar l) (car l)))
            (key (if (consp (car l)) (car l) l)))
        (cc (if (consp (car l)) (cadr (car l)) nil) (if (eq op 'let) env e2) nil)
        (if (cc-special-p name)
            (let ((v (cc-tmp)))
              (if (eq op 'let)
                  (push (cons name v) sp)
                  (progn (unless sp (cc-emit 60) (setq e2 (cons (list 4 (* -2 *cc-depth*)) e2))
                                 (setq sp t))
                         (cc-ref v) (cc-emit 61 (cc-const name))
                         (push (list 1 name) e2))))
            (let ((v (cc-newvar name key)))
              (if (eq op 'let) (push v vs) (push v e2))))))
      bs)
    (when (and sp (eq op 'let))
      (cc-emit 60)
      (setq e2 (cons (list 4 (* -2 *cc-depth*)) e2))
      (dolist (s sp)
        (cc-ref (cdr s)) (cc-emit 61 (cc-const (car s)))
        (push (list 1 (car s)) e2)))
    (dolist (v vs) (push v e2))
    (cc-body body e2 (and tail (not sp)))
    (unless (and tail (not sp))
      (when sp (cc-emit 68 (mod (nth 1 (find 4 e2 :key #'car)) 256)))
      (when (> *cc-depth* (1+ d)) (cc-emit 25 (- *cc-depth* d 1)) (setq *cc-depth* (1+ d)))
      (cc-tail tail))))

;; flet and labels: each function, a closure, in a variable; labels' are
;; boxed, so the functions can see each other
(defun cc-flet (op fs body env tail)
  (let ((d *cc-depth*) (e2 env) (vs nil))
    (when (eq op 'labels)
      (dolist (f fs)
        (cc-literal nil)
        (cc-emit 14)
        (let ((v (list 0 nil *cc-fn* (* -2 *cc-depth*) t (list nil))))
          (push v vs)
          (push (list 2 (car f) v) e2)))
      (setq vs (reverse vs)))
    (dolist (f fs)
      (cc-closure (car f) (cadr f) (cddr f) (if (eq op 'labels) e2 env))
      (if (eq op 'labels)
          (progn (cc-set (car vs)) (cc-emit 23) (setq vs (cdr vs)))
          (push (list 2 (car f) (list 0 nil *cc-fn* (* -2 *cc-depth*) nil (list nil))) e2)))
    (cc-body body e2 tail)
    (unless tail
      (when (> *cc-depth* (1+ d)) (cc-emit 25 (- *cc-depth* d 1)) (setq *cc-depth* (1+ d))))))

;; block: a label to jump to; returned to from an inner function, a catch
(defun cc-block (x env tail)
  (if (cc-bit (cc-flag x) 4)
      (progn
        (cc-literal nil) (cc-literal nil) (cc-emit 40)
        (let ((v (cc-tmp)))
          (cc (list '%catch (cc-tmpref v) (cons 'lambda (cons nil (cddr x))))
              (cons (list 3 (cadr x) nil 0 nil x nil v) (cons v env)) nil)
          (cc-emit 25 1) (decf *cc-depth*)
          (cc-tail tail)))
      (let ((l (cc-label)))
        (cc-body (cddr x) (cons (list 3 (cadr x) l *cc-depth* *cc-fn* x tail nil) env) tail)
        (cc-place l))))

(defun cc-return (name form env)
  (let ((b nil) (s nil))
    (dolist (e env)
      (when (= (car e) 4) (setq s (nth 1 e)))
      (when (and (= (car e) 3) (eq (nth 1 e) name)) (setq b e) (return)))
    (unless b (cc-fail (list 'return-from name)))
    (cond ((nth 7 b) (cc (list '%throw (cc-tmpref (nth 7 b)) form) env nil))
          ((not (eq (nth 4 b) *cc-fn*))
           (let ((e (assoc (nth 5 b) *cc-flags*)))
             (unless e (setq e (cons (nth 5 b) 0)) (push e *cc-flags*))
             (rplacd e (logior (cdr e) 4))
             (setq *cc-again* t)
             (cc form env nil)))
          (t (cc form env nil)
             (when s (cc-emit 68 (mod s 256)))
             (if (nth 6 b)
                 (cc-emit 33)
                 (progn
                   (when (> *cc-depth* (1+ (nth 3 b)))
                     (cc-emit 25 (- *cc-depth* (nth 3 b) 1)))
                   (cc-jump 26 (nth 2 b))))
             (setq *cc-depth* (1+ (nth 3 b)))))))

;; dolist and dotimes: a hidden list (or count) and the variable, in a
;; block NIL
(defun cc-do (op spec body env)
  (let ((d *cc-depth*) (top (cc-label)) (done (cc-label)) (end (cc-label)))
    (cc (cadr spec) env nil)
    (let ((h (cc-tmp)))
      (cc-literal (if (eq op 'dolist) nil 0))
      (let* ((v (cc-newvar (car spec) spec))
             (e2 (list* (list 3 nil end *cc-depth* *cc-fn* nil nil nil) v env)))
        (cc-place top)
        (if (eq op 'dolist)
            (progn (cc-ref h) (cc-jump 27 done)
                   (cc-ref h) (cc-emit 38) (cc-set v) (cc-emit 23)
                   (cc-ref h) (cc-emit 39) (cc-loc 70 (nth 3 h)))
            (progn (cc-ref v) (cc-ref h) (cc-emit 52) (cc-jump 28 done)))
        (cc-effects body e2)
        (unless (eq op 'dolist) (cc-ref v) (cc-emit 47) (cc-set v) (cc-emit 23))
        (cc-jump 26 top)
        (cc-place done)
        (when (eq op 'dolist) (cc-literal nil) (cc-set v) (cc-emit 23))
        (cc (caddr spec) e2 nil)
        (cc-place end)
        (cc-emit 25 2)
        (setq *cc-depth* (1+ d))))))

(defun cc-loop (body env)
  (let ((top (cc-label)) (end (cc-label)))
    (cc-place top)
    (cc-effects body (cons (list 3 nil end *cc-depth* *cc-fn* nil nil nil) env))
    (cc-jump 26 top)
    (cc-place end)
    (incf *cc-depth*)))

;; backquote, into list building
(defun cc-qq (x)
  (cond ((atom x) (list 'quote x))
        ((eq (car x) 'unquote) (cadr x))
        ((eq (car x) 'quasiquote) (cc-fail x))
        ((and (consp (car x)) (eq (caar x) 'unquote-splicing))
         (if (cdr x) (list 'append (cadr (car x)) (cc-qq (cdr x))) (cadr (car x))))
        (t (list 'cons (cc-qq (car x)) (cc-qq (cdr x))))))

;;; ------------------------------------------------------------ lambda lists

;; the start of a function: its parameters in places; -> the environment.
;; A plain list (no &...): the arguments where they are (ENTER); else
;; ARGS pushes them as locals, then the defaults are worked out
(defun cc-params (name ll env top)
  (let ((n 0) (i 0) (sp nil))
    (if (cc-plain ll)
        (progn
          (setq n (length ll))
          (when (> n 54) (cc-limit "too many parameters"))
          (cc-emit 34 n)
          (let ((start (cc-label)))
            (cc-place start)
            (when top (setq *cc-self* (list name n start *cc-fn*))))
          (cc-cells #'(lambda (l)
            (let ((d (+ 20 (* 2 (- n 1 i)))))
              (if (cc-special-p (car l))
                  (push (cons (car l) d) sp)
                  (let ((box (= (mod (cc-flag l) 4) 3)))
                    (when box (cc-loc 5 d) (cc-emit 14) (cc-loc 70 d))
                    (push (list 0 (car l) *cc-fn* d box l) env))))
            (incf i))
            ll))
        (setq env (cc-complex ll env)))
    (when sp (cc-limit "a special parameter"))
    env))

(defun cc-plain (ll)
  (dolist (p ll t)
    (unless (and (symbolp p) (not (member p '(&optional &rest &body &key &aux)))) (return nil))))

(defun cc-complex (ll env)
  (let ((req nil) (opt nil) (rest nil) (keys nil) (aux nil) (mode 0) (nk 0))
    (cc-cells #'(lambda (l)
      (let ((p (car l)))
        (cond ((eq p '&optional) (setq mode 1))
              ((member p '(&rest &body)) (setq mode 2))
              ((eq p '&key) (setq mode 3))
              ((eq p '&aux) (setq mode 4))
              ((= mode 0) (if (symbolp p) (push l req) (cc-fail p)))
              ((= mode 1) (push l opt))
              ((= mode 2) (setq rest l))
              ((= mode 3) (push l keys))
              (t (push l aux)))))
      ll)
    (setq req (reverse req) opt (reverse opt) keys (reverse keys) aux (reverse aux))
    (setq nk (length keys))
    (if keys
        (let ((k (length *cc-consts*)))
          (dolist (c keys)
            (let ((p (car c)))
              (cc-new-const (cond ((symbolp p) (cc-keyword p))
                                  ((consp (car p)) (caar p))
                                  (t (cc-keyword (car p)))))))
          (cc-emit 35 (length req) (length opt) (if rest 3 2) k nk))
        (cc-emit 35 (length req) (length opt) (if rest 1 0)))
    (setq *cc-depth* (+ (length req) (length opt) (if rest 1 0) nk))
    (let ((j 0))
      (dolist (c req)
        (setq env (cc-param (car c) c (* -2 (incf j)) env)))
      (dolist (c opt)
        (setq env (cc-optional (if (consp (car c)) (caar c) (car c)) c (* -2 (incf j)) env)))
      (when rest (setq env (cc-param (car rest) rest (* -2 (incf j)) env)))
      (dolist (c keys)
        (let ((p (car c)))
          (setq env (cc-optional (cond ((symbolp p) p) ((consp (car p)) (cadr (car p))) (t (car p)))
                                 c (* -2 (incf j)) env)))))
    (dolist (c aux)
      (cc (if (consp (car c)) (cadr (car c)) nil) env nil)
      (push (cc-newvar (if (consp (car c)) (caar c) (car c)) (if (consp (car c)) (car c) c)) env))
    env))

;; a parameter in place d (key: the cons whose car is the spec)
(defun cc-keyword (s) (intern (format nil ":~A" (symbol-name s))))

(defun cc-param (name key d env)
  (when (cc-special-p name) (cc-limit "a special parameter"))
  (let ((box (= (mod (cc-flag key) 4) 3)))
    (when box (cc-loc 5 d) (cc-emit 14) (cc-loc 70 d))
    (cons (list 0 name *cc-fn* d box key) env)))

;; an optional or key parameter: (var init svar) or var; its default
;; worked out unless the argument was given
(defun cc-optional (name key d env)
  (let* ((spec (car key)) (init (and (consp spec) (cadr spec))) (sv (and (consp spec) (cddr spec)))
         (l (cc-label)))
    (when sv
      (cc-emit 66 (mod d 256))
      (push (cc-newvar (car sv) sv) env))
    (cc-jump 65 l (mod d 256))
    (cc init env nil)
    (cc-loc 70 d)
    (cc-place l)
    (cc-param name key d env)))

;;; ------------------------------------------------------------ files

;; (compile-file "name" [out]): name.LSP's defuns compiled, into out
;; (name.FAS): (setf (symbol-function 'f) (%code ...)) for each, which
;; load reads back; defmacro, defvar and the like are evaluated too (later
;; forms may need them), and copied, as is everything else. The source is
;; read first: one file at a time (each takes 2 KB of string space)
(defun compile-file (in &optional out)
  (let ((src (open in)) (eof (list nil)) (forms nil) (k 0) (dst nil))
    (unwind-protect
        (%loop
          (let ((f (read src nil eof)))
            (when (eq f eof) (return))
            (push f forms)))
      (close src))
    (setq out (or out (format nil "~A.FAS" (cc-base in)))
          dst (open out :direction :output))
    (unwind-protect
        (dolist (f (nreverse forms))
          (if (and (consp f) (eq (car f) 'defun))
              (let ((r (%catch-errors (cc-top (cadr f) (caddr f)
                                              (list (list* 'block (cadr f) (cdddr f)))))))
                (if (car r)
                    (progn (format dst "(SETF (SYMBOL-FUNCTION '~S) " (cadr f))
                           (cc-write (cdr r) dst)
                           (format dst ")~%")
                           (incf k))
                    (progn (format t "~&;; ~A not compiled: ~A~{ ~S~}~%" (cadr f) (cadr r) (cddr r))
                           (prin1 f dst) (terpri dst))))
              (progn
                (when (and (consp f) (member (car f) '(defmacro defvar defparameter defconstant defstruct)))
                  (eval f))
                (prin1 f dst) (terpri dst))))
      (close dst))
    (%vm-release)
    (format t "~&;; ~D compiled~%" k)
    out))

(defun cc-base (name)
  (let ((d (position #\. name)))
    (if d (subseq name 0 d) name)))

;; a compiled function as a form that makes it again: its bytes in hex,
;; 127 to a string
(defun cc-write (f s)
  (let ((b (%code-bytes f)) (c (%code-consts f)) (i 0))
    (format s "(%CODE '(\"")
    (dolist (x b)
      (when (= i 127) (format s "\" \"") (setq i 0))
      (format s "~2,'0X" x)
      (incf i))
    (format s "\") (LIST")
    (dolist (x (cdr c))
      (if (eql (%fn-info x) 3)
          (progn (format s " ") (cc-write x s))
          (format s " '~S" x)))
    (format s ") '~S)" (car c))))

;;; ------------------------------------------------------------ disassemble

(defun disassemble (f)
  (when (symbolp f) (setq f (symbol-function f)))
  (let ((b (%code-bytes f)) (c (cdr (%code-consts f))) (pc 0))
    (unless b (error "not compiled:" f))
    (%loop
      (when (null b) (return))
      (let* ((op (floor (car b) 3)) (k (%op-kind op)) (s (%op-name op)))
        (format t "~&~3D ~A" pc s)
        (setq b (cdr b) pc (1+ pc))
        (case k
          (1 (format t " ~S" (nth (car b) c)) (setq b (cdr b) pc (1+ pc)))
          ((2 4) (format t " ~D" (if (and (= k 2) (> (car b) 127)) (- (car b) 256) (car b)))
           (setq b (cdr b) pc (1+ pc)))
          (3 (format t " ~D" (cc-dis-jump b pc)) (setq b (cddr b) pc (+ pc 2)))
          (5 (format t " ~D ~D ~D" (car b) (cadr b) (caddr b))
           (if (cc-bit (caddr b) 2)
               (progn (format t " ~{~S~^ ~}" (subseq c (nth 3 b) (+ (nth 3 b) (nth 4 b))))
                      (setq b (nthcdr 5 b) pc (+ pc 5)))
               (setq b (nthcdr 3 b) pc (+ pc 3))))
          (6 (format t " ~S ~D" (nth (car b) c) (cadr b)) (setq b (cddr b) pc (+ pc 2)))
          (7 (format t " ~D ~D" (- (car b) 256) (cc-dis-jump (cdr b) (1+ pc)))
           (setq b (cdddr b) pc (+ pc 3)))
          (8 (format t " ~D" (+ pc 1 (if (> (car b) 127) (- (car b) 256) (car b))))
           (setq b (cdr b) pc (1+ pc)))
          (9 (format t " ~S ~D" (if (> op 77) (car b) (nth (car b) c)) (cadr b))
           (setq b (cddr b) pc (+ pc 2))))))
    (terpri)
    (%vm-release)
    nil))

(defun cc-dis-jump (b pc)
  (+ pc 2 (car b) (* 256 (if (> (cadr b) 127) (- (cadr b) 256) (cadr b)))))
