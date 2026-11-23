;;; CPC Lisp -- the machine's own Lisp, in library part 0: the Amstrad PCW.

(defvar *features* '(:pcw :cpc-lisp))

;; no speech on a PCW: (say ...) is quiet, as the demos' (talk) asks it
(defun say (text) (declare (ignore text)) t)
