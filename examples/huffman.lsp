;;; HUFFMAN.LSP -- Huffman codes, after "Structure and Interpretation of
;;; Computer Programs", section 2.3.4
;;;
;;;   (load "huffman")
;;;   (huffman-demo)    SICP's tree for A-H, and a message coded with it
;;;   (huffman-song)    the 1950s rock song of exercise 2.70
;;;
;;; A Huffman code gives the commonest symbols the shortest bit strings.
;;; Its tree is built from the symbols' weights: the two lightest trees,
;;; again and again, joined into one, until one is left. A symbol's code
;;; is the way down to its leaf, 0 for left and 1 for right; decoding
;;; walks down the tree bit by bit and starts at the top again at a leaf.
;;;
;;; A leaf is (LEAF symbol weight), a tree (left right symbols weight).

(defun h-leaf (s w) (list 'leaf s w))
(defun h-leaf-p (x) (eq (car x) 'leaf))

(defun h-symbols (tr)
  (if (h-leaf-p tr) (list (cadr tr)) (caddr tr)))

(defun h-weight (tr)
  (if (h-leaf-p tr) (caddr tr) (nth 3 tr)))

(defun h-tree (l r)
  (list l r (append (h-symbols l) (h-symbols r))
        (+ (h-weight l) (h-weight r))))

;; a set of trees, the lightest first
(defun h-adjoin (x set)
  (cond ((null set) (list x))
        ((< (h-weight x) (h-weight (car set))) (cons x set))
        (t (cons (car set) (h-adjoin x (cdr set))))))

(defun h-merge (set)
  (if (null (cdr set))
      (car set)
      (h-merge (h-adjoin (h-tree (car set) (cadr set)) (cddr set)))))

;; pairs: ((symbol weight) ...)
(defun huffman-tree (pairs)
  (let ((set nil))
    (dolist (p pairs)
      (setq set (h-adjoin (h-leaf (car p) (cadr p)) set)))
    (h-merge set)))

(defun h-encode-1 (s tr)
  (cond ((h-leaf-p tr) nil)
        ((member s (h-symbols (car tr))) (cons 0 (h-encode-1 s (car tr))))
        ((member s (h-symbols (cadr tr))) (cons 1 (h-encode-1 s (cadr tr))))
        (t (error "huffman: ~A is not in the tree" s))))

(defun h-encode (message tr)
  (mapcan #'(lambda (s) (h-encode-1 s tr)) message))

(defun h-decode (bits tr)
  (let ((out nil) (b tr))
    (dolist (bit bits (nreverse out))
      (setq b (if (= bit 0) (car b) (cadr b)))
      (when (h-leaf-p b)
        (push (cadr b) out)
        (setq b tr)))))

(defun huffman-demo ()
  (let* ((pairs '((a 8) (b 3) (c 1) (d 1) (e 1) (f 1) (g 1) (h 1)))
         (tr (huffman-tree pairs))
         (message '(b a c a d a e a f a b b a a g a h))
         (bits (h-encode message tr)))
    (format t "The code, from the weights ~A:~%" pairs)
    (dolist (p pairs)
      (format t " ~A ~{~D~}~%" (car p) (h-encode-1 (car p) tr)))
    (format t "~A~%is ~D bits, not ~D: ~{~D~}~%"
            message (length bits) (* 3 (length message)) bits)
    (format t "decoded: ~A~%" (h-decode bits tr))))

(defun huffman-song ()
  (let* ((tr (huffman-tree '((a 2) (na 16) (boom 1) (sha 3) (get 2)
                             (yip 9) (job 2) (wah 1))))
         (song '(get a job sha na na na na na na na na
                 get a job sha na na na na na na na na
                 wah yip yip yip yip yip yip yip yip yip
                 sha boom))
         (bits (h-encode song tr)))
    (format t "~D symbols, ~D bits -- at 3 bits a symbol ~D~%"
            (length song) (length bits) (* 3 (length song)))
    (equal (h-decode bits tr) song)))
