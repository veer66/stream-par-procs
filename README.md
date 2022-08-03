# stream-par-procs

A library for parallelly processing a stream in Common Lisp

## Example

```Lisp
(defpackage #:example
  (:use #:cl #:stream-par-procs))

(in-package #:example)

(with-open-file (f #p"hello.txt")
  (process f
	   (lambda (elem state send-fn)
	     (declare (ignore state))
	     (funcall send-fn (length elem)))
	   :collect-fn (lambda (n sum)
			 (+ n sum))
	   :init-collect-state-fn (lambda () 0)
	   :num-of-procs 8))
```
