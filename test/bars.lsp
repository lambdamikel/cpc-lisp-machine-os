'|hello world|
(symbol-name '|hello world|)
'foo|bar|baz
'a\ b
'\a
(list '|123| (symbolp '|123|) '|.| '||)
(eq '|FOO| 'foo)
(intern "lower")
(prin1-to-string (intern "lower"))
(princ '|mixed Case|)
(read-from-string "|x y|")
(format nil "~S ~A" '|a(b| '|a(b|)
(list 'normal :key 'a-b '*x* '1+)
(list '|-5| '|+| '- '|1+| '1+ '|+12| '|1.5|)
(make-array 3 :initial-element 'x)
(make-array 2)
(make-array -1)
