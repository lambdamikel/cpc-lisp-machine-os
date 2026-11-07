;;; CPC Lisp -- more library functions written in Lisp (library text in
;;; the demo ROM, part 3, where there is room). Read from the ROM the first
;;; time each is used, as lisp.lsp's are.

;;; Streams. A file stream is #S(FILE-STREAM name direction open-p) (open,
;;; close and with-open-file are in lisp.lsp). A string output stream is
;;; #S(STRING-OUTPUT-STREAM chunks): what each printer call writes is a
;;; string pushed onto it (lib/streams.asm); a string input stream is
;;; #S(STRING-INPUT-STREAM string index). The natives tell them apart by
;;; their number of slots.

(defun make-string-output-stream () (%make-struct 'string-output-stream nil))

(defun get-output-stream-string (s)
  (let ((r "") (l (reverse (%struct-ref s 1 'string-output-stream))))
    (%struct-set s 1 nil 'string-output-stream)
    (dolist (c l r) (setq r (concatenate 'string r c)))))

(defmacro with-output-to-string (spec &body body)
  `(let ((,(car spec) (make-string-output-stream)))
     ,@body
     (get-output-stream-string ,(car spec))))

(defun make-string-input-stream (string &optional (start 0))
  (%make-struct 'string-input-stream string start))

(defmacro with-input-from-string (spec &body body)
  `(let ((,(car spec) (make-string-input-stream ,(cadr spec)))) ,@body))

(defun streamp (x)
  (or (%struct-is x 'file-stream) (%struct-is x 'string-output-stream)
      (%struct-is x 'string-input-stream)))

(defun open-stream-p (s)
  (if (%struct-is s 'file-stream) (%struct-ref s 3 'file-stream) t))

(defun input-stream-p (s)
  (if (%struct-is s 'file-stream)
      (eq (%struct-ref s 2 'file-stream) :input)
      (%struct-is s 'string-input-stream)))

(defun output-stream-p (s)
  (if (%struct-is s 'file-stream)
      (eq (%struct-ref s 2 'file-stream) :output)
      (%struct-is s 'string-output-stream)))
