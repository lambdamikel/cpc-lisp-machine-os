;;; CPC Lisp -- far arrays, in library part 3 (the natives are part 1's):
;;; arrays kept in a file on the RAM disc (M:), outside the cells.
;;; (make-far-array "table" 20000) makes M:TABLE.FAR; (far-array "table")
;;; finds it again (after a reset too); far-ref and its setf, far-length
;;; (lib/farray.asm). Element types: T -- fixnums, characters, T and NIL,
;;; two bytes each -- (unsigned-byte 8) and character, one byte each.
;;; delete-file gives the space back.

(defun make-far-array (name size &key (element-type t))
  (let ((n (%far-name name))
        (k (cond ((eq element-type t) 0)
                 ((equal element-type '(unsigned-byte 8)) 1)
                 ((member element-type '(character base-char)) 2)
                 (t (error "no far array of ~S" element-type)))))
    (with-open-file (s n :direction :output) (%far-fill size k))
    (let ((a (and (%far-open n) (far-array n))))
      (unless (and a (= (far-length a) size))
        (when a (delete-file n))
        (error "no room on M: for ~A" n))
      a)))

(defun far-array (name)
  (let* ((n (%far-name name)) (k (%far-open n)))
    (unless k (error "no far array ~A" n))
    (%make-struct 'far-array n 0 k)))

(defun %far-name (name)
  (let ((n (string-upcase (string name))))
    (when (and (> (length n) 1) (eql (char n 1) #\:))
      (unless (eql (char n 0) #\M) (error "far arrays are on M:"))
      (setq n (subseq n 2)))
    (concatenate 'string "M:" n (if (find #\. n) "" ".FAR"))))

(setf (get 'far-ref 'setf) '%far-set)
