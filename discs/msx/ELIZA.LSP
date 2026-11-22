;;; ELIZA.LSP -- Joseph Weizenbaum's ELIZA (1966), the DOCTOR script
;;;
;;;   (load "eliza")
;;;   (eliza)        talk to her; a line with BYE ends it
;;;
;;; Each rule is a pattern and the answers to give, in turn. In a pattern
;;; ?X stands for any words, none too; the first rule whose pattern fits
;;; the line answers, its ?X filled with the words that matched -- I made
;;; YOU, MY made YOUR and so on, as one would say them back. The last
;;; rule fits anything. The rules are after Peter Norvig's version in
;;; "Paradigms of AI Programming" (1992), which is after Weizenbaum's.

(defvar *eliza-rules*
  '(((?x hello ?y) (how do you do -- please state your problem))
    ((?x computer ?y) (do computers worry you ?)
     (what do you think about machines ?) (why do you mention computers ?))
    ((?x sorry ?y) (please do not apologize) (apologies are not necessary))
    ((?x i remember ?y) (do you often think of ?y ?)
     (does thinking of ?y bring anything else to mind ?))
    ((?x if ?y) (do you really think it is likely that ?y ?)
     (what do you think about ?y ?))
    ((?x dream ?y) (what does that dream suggest to you ?)
     (do you dream often ?))
    ((?x my mother ?y) (tell me more about your family)
     (who else in your family ?y ?))
    ((?x my father ?y) (your father ?) (does he influence you strongly ?))
    ((?x i want ?y) (what would it mean if you got ?y ?)
     (why do you want ?y ?) (suppose you got ?y soon))
    ((?x i am sad ?y) (i am sorry to hear you are depressed))
    ((?x i am ?y) (in what way are you ?y ?) (do you want to be ?y ?))
    ((?x i feel ?y) (do you often feel ?y ?))
    ((?x are like ?y) (what resemblance do you see between ?x and ?y ?))
    ((?x alike ?y) (in what way ?) (what similarities are there ?))
    ((?x you are ?y) (what makes you think i am ?y ?))
    ((?x because ?y) (is that the real reason ?)
     (what other reasons might there be ?))
    ((?x yes ?y) (you seem quite positive) (you are sure ?))
    ((?x no ?y) (why not ?) (you are being a bit negative))
    ((?x everyone ?y) (surely not everyone) (anyone in particular ?))
    ((?x always ?y) (can you think of a specific example ?) (really -- always ?))
    ((?x what ?y) (why do you ask ?) (what do you think ?))
    ((?x) (very interesting) (i am not sure i understand you fully)
     (what does that suggest to you ?) (please continue)
     (do you feel strongly about discussing such things ?))))

(defvar *eliza-switch*
  '((i . you) (you . i) (me . you) (my . your) (your . my)
    (am . are) (are . am) (myself . yourself) (yourself . myself)))

(defun e-var-p (x)
  (and (symbolp x)
       (> (length (symbol-name x)) 1)
       (char= (char (symbol-name x) 0) #\?)))

;; bindings ((?x word...) ...), or :fail
(defun e-match (pat in b)
  (cond ((null pat) (if (null in) b :fail))
        ((e-var-p (car pat))
         (do ((k 0 (1+ k)))
             ((> k (length in)) :fail)
           (let ((r (e-match (cdr pat) (nthcdr k in)
                             (cons (cons (car pat) (subseq in 0 k)) b))))
             (unless (eq r :fail) (return r)))))
        ((and in (eq (car pat) (car in))) (e-match (cdr pat) (cdr in) b))
        (t :fail)))

;; a line's words as symbols: punctuation out
(defun e-words (line)
  (read-from-string
   (concatenate 'string "("
                (substitute-if #\Space
                               #'(lambda (c) (not (alphanumericp c)))
                               (remove #\' line))
                ")")))

(defun e-switch (words)
  (mapcar #'(lambda (w)
              (let ((p (assoc w *eliza-switch*)))
                (if p (cdr p) w)))
          words))

(defun e-fill (answer b)
  (mapcan #'(lambda (w)
              (if (e-var-p w)
                  (e-switch (cdr (assoc w b)))
                  (list w)))
          answer))

;; the words said: the first capitalized, I as I, a full stop unless ?
(defun e-say (words)
  (let ((first t))
    (dolist (w words)
      (unless (or first (eq w '?)) (princ " "))
      (princ (cond ((eq w 'i) "I")
                   (first (string-capitalize (symbol-name w)))
                   (t (string-downcase (symbol-name w)))))
      (setq first nil))
    (unless (eq (car (last words)) '?) (princ "."))
    (terpri)))

(defun e-answer (in)
  (dolist (r *eliza-rules*)
    (let ((b (e-match (car r) in nil)))
      (unless (eq b :fail)
        (e-say (e-fill (cadr r) b))
        ;; the next time, the rule's next answer
        (setf (cdr r) (append (cddr r) (list (cadr r))))
        (return)))))

(defun eliza ()
  (format t "I am ELIZA. Tell me your problem -- BYE ends it.~%")
  (loop
    (princ "> ")
    (let ((in (e-words (read-line))))
      (when (member 'bye in)
        (format t "Goodbye. That will be 50 pence.~%")
        (return))
      (e-answer in))))
