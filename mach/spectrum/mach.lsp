;;; CPC Lisp -- the machine's own Lisp, in library part 0: the ZX Spectrum.

(defvar *features* '(:zx-spectrum :cpc-lisp))

;; no speech on a Spectrum: (say ...) is quiet, as the demos' (talk) asks it
(defun say (text) (declare (ignore text)) t)
