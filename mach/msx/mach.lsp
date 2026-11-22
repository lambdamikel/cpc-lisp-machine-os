;;; CPC Lisp -- the machine's own Lisp, in library part 0: the MSX.

(defvar *features* '(:msx :cpc-lisp))

;; no speech on an MSX: (say ...) is quiet, as the demos' (talk) asks it
(defun say (text) (declare (ignore text)) t)
