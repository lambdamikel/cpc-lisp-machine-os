;;; CPC Lisp -- loading, in library part 1: (load name :lazy t) reads a
;;; program's defuns only when they are first called, so a program may be
;;; bigger than the cells. The file is read through once: each defun gets a
;;; stub that remembers where in the file it is, every other form is
;;; evaluated (after the reading, in order). A stub's first call reads its
;;; defun from there and evaluates it; the definition counts as the
;;; library's (%libdef), so when the cells run out it can be dropped again
;;; (lib/short.asm puts the stub back) and save leaves it out. The
;;; position is the characters before the form (%file-pos, lib/lazy.asm).

(defun load (name &key lazy)
  (if lazy (%load-lazy name) (%load name)))

(defun file-position (stream &optional position)
  (when (and (%struct-ref stream 3 'file-stream)
             (not (eq (%struct-ref stream 2 'file-stream) :output)))
    (if position (%file-skip position) (%file-pos))))

(defun %load-lazy (name)
  (let ((forms nil))
    (with-open-file (s name)
      (loop
        (let* ((p (%file-pos)) (f (read s nil s)))
          (cond ((eq f s) (return))
                ((and (consp f) (eq (car f) 'defun) (consp (cdr f))
                      (cadr f) (symbolp (cadr f)))
                 (%lazy-stub (cadr f) name p))
                (t (push f forms))))))
    (dolist (f (nreverse forms) t) (eval f))))

;; the stub is kept in the plist, (stub file . position), for %lazy-call
;; and for the dropper (ls_lazy finds %LAZY by name)
(defun %lazy-stub (name file p)
  (let ((stub (%lazy-fn name)))
    (setf (get name '%lazy) (list* stub file p))
    (setf (symbol-function name) stub)
    (%libdef name)))

(defun %lazy-fn (name) #'(lambda (&rest args) (%lazy-call name args)))

(defun %lazy-call (name args)
  (let ((e (get name '%lazy)))
    (when (eq (symbol-function name) (car e))
      (when (%file-pos)
        (error "~S must be read from ~S, but a file is open" name (cadr e)))
      (let ((f (with-open-file (s (cadr e))
                 (and (file-position s (cddr e)) (read s nil nil)))))
        (unless (and (consp f) (eq (car f) 'defun) (consp (cdr f))
                     (eq (cadr f) name))
          (error "~S is not where it was in ~S" name (cadr e)))
        (eval f)
        (%libdef name)))
    (apply name args)))
