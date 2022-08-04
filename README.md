# stream-par-procs

A library for parallelly processing a stream in Common Lisp

## Usecase

* When processing data from a stream takes too long because using one thread is the bottleneck
* When data is too big to store in an in-memory list or vector
* When the computer has many idle CPU cores
* When using lparallel or bordeaux-threads with chanl directly takes too much effort

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

## API

This library has only one function

### process function

#### Arguments

* stream
* proc-fn

#### Keyword arguments

* read-fn
* init-proc-state-fn
* init-collect-state-fn
* num-of-procs
* collect-fn
* process-end-of-stream-hook-fn
