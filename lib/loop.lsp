;;; CPC Lisp -- the extended LOOP (library text in the demo ROM, part 3).
;;; (loop form...) whose first form is not a symbol is the simple loop,
;;; the core's %LOOP; otherwise %LOOP-EXPAND (lib/loop.asm, native) makes
;;; the expansion -- once: macro calls keep it.

(defmacro loop (&rest forms)
  (if (and (car forms) (symbolp (car forms)))
      (%loop-expand forms)
      `(%loop ,@forms)))

(defmacro loop-finish () '(return-from %loop nil))

(defun endp (x) (null x))

(defun %hash-pairs (h)
  (let ((r nil)) (maphash #'(lambda (k v) (push (cons k v) r)) h) r))
