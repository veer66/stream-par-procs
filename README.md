# stream-par-procs

A library for parallel processing of a stream in Common Lisp

## Usecase

* When processing data from a stream takes too long because using one thread is the bottleneck
* When data is too big to store in an in-memory list or vector
* When the computer has many idle CPU cores
* When using lparallel or bordeaux-threads with chanl directly takes too much effort

## Example

#### Count characters (excluding newlines)

```Lisp
(defpackage #:example
  (:use #:cl #:stream-par-procs))

(in-package #:example)

(with-open-file (f #p"hello.txt")
  (process f
	     (lambda (elem elem-i state send-fn)
	       (declare (ignore state elem-i state))
	       (funcall send-fn (length elem)))
	     :collect-fn (lambda (n sum)
             		   (+ n sum))
	     :init-collect-state-fn (lambda () 0)
	     :process-end-of-stream-hook-fn (lambda (state send-fn)
					      (declare (ignore state))
					      (funcall send-fn 10000))
	     :num-of-procs 8))
```

#### Make a histogram of characters

```Lisp
(defun histo-proc (line line-no hash-tab send-fn)
  (declare (ignore send-fn line-no))
  (loop for ch across line do
    (if #1=(gethash ch hash-tab)
	(incf #1#)
	(setf #1# 1)))
  hash-tab)

(defun forward (hash-tab send-fn)
  (funcall send-fn hash-tab))

(defun merge-hash-table (hash-tab-from-proc main-hash-tab)
  (loop for k being the hash-keys of hash-tab-from-proc
	  using (hash-value v)
	do
	   (let* ((v-main #2= (gethash k main-hash-tab))
		  (v-sum (+ v (or v-main 0))))
	     (setf #2# v-sum)))
  main-hash-tab)


(defun histo ()
  (with-open-file (fi "hello.txt")
    (stream-par-procs:process fi
			      #'histo-proc
			      :num-of-procs 4
			      :init-proc-state-fn #'make-hash-table
			      :init-collect-state-fn #'make-hash-table
			      :process-end-of-stream-hook-fn #'forward
			      :collect-fn #'merge-hash-table)))

(loop for k being the hash-keys of (histo) 
   using (hash-value v)
   do (format t "~A --- ~A~%" k v))
```

## How to install

1. Install Quicklisp if you didn't.
2. Install Ultradist dist by running (ql-dist:install-dist "http://dist.ultralisp.org/") in REPL if you didn't.
3. In REPL, run (ql:quickload :stream-par-procs).

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
