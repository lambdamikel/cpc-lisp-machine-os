(read-line)
hello world
(list (read-line) (read-line))
first line
second line
(progn (princ "Name? ") (read-line))
Mike
(length (read-line))

(read-char)
!type 40 x
(progn (unread-char #\q) (read-char))
(listen)
(read-char-no-hang)
(list (peek-char) (read-char))
!type 40 k
(unread-char 5)
(y-or-n-p "Go on?")
!type 40 y
(y-or-n-p)
!type 40 n
(write-string "abc")
(write-line "def")
(write '(1 "a" #\b))
(fresh-line)
(read)
(a b . c)
(+ 1 2)
