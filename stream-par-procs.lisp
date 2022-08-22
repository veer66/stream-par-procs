(defpackage #:stream-par-procs
  (:use #:cl)
  (:import-from #:bordeaux-threads :make-thread :join-thread)
  (:import-from #:chanl :bounded-channel :send :recv)
  (:export #:process #:*to-processor-buffer-size* #:*to-collector-buffer-size*))

(in-package #:stream-par-procs)

(defparameter *to-processor-buffer-size* 1024)
(defparameter *to-collector-buffer-size* 128)

(defun default-read-line (stream)
  (read-line stream nil :END-OF-STREAM))

(defstruct proc-info
  proc-fn
  read-fn
  init-proc-state-fn
  init-collect-state-fn
  num-of-procs
  collect-fn
  proc-states
  collect-state
  process-end-of-stream-hook-fn
  to-processor-channels
  to-collector-channel
  wrapped-processors
  wrapped-collector)

(defun make-proc-states (ctx)
  (with-slots (num-of-procs init-proc-state-fn) ctx
    (make-array num-of-procs
		:initial-contents
		(loop for i from 0 below num-of-procs
		      collect (funcall init-proc-state-fn)))))

(defun make-to-processor-channels (num-of-procs)
  (make-array num-of-procs
	      :initial-contents 
	      (loop for i from 0 below num-of-procs
		    collect
		    (make-instance 'bounded-channel :size *to-processor-buffer-size*))))

(defun wrap-processor (ctx state to-proc-chan)
  (with-slots (proc-fn to-collector-channel process-end-of-stream-hook-fn) ctx
    (make-thread (lambda ()
		   (flet ((send-fn (msg) (send to-collector-channel msg)))
		     (loop for (stream-element . element-i) = (recv to-proc-chan)
			   until (eq stream-element :END-OF-STREAM)
			   do
			      (setq state (funcall proc-fn
						   stream-element
						   element-i
						   state
						   #'send-fn)))
		     (unless (null process-end-of-stream-hook-fn)
		       (funcall process-end-of-stream-hook-fn state #'send-fn))
		     (send to-collector-channel :END-OF-STREAM))))))

(defun wrap-collector (ctx)
  (with-slots (collect-fn to-collector-channel num-of-procs collect-state) ctx
    (make-thread (lambda ()
		   (loop with finish-count = 0
			 for element = (recv to-collector-channel)
			 do 
			    (if (eq element :END-OF-STREAM)
				(incf finish-count)
				(setq collect-state (funcall collect-fn element collect-state)))
			 until (eq finish-count num-of-procs)
			 finally (return collect-state))))))

(defun echo (element state)
  (declare (ignore state))
  (print element))

(defun make-collector-channel ()
  (make-instance 'bounded-channel :size *to-collector-buffer-size*))

(defun make-wrapped-processors (ctx)
  (with-slots (proc-fn proc-states to-processor-channels to-collector-channel num-of-procs) ctx
    (make-array num-of-procs
		:initial-contents
		(loop for i from 0 below num-of-procs
		      collect (wrap-processor ctx
					      (elt proc-states i)
					      (elt to-processor-channels i))))))

(defun init-additional-ctx (ctx)
  (with-slots (num-of-procs) ctx
    (setf (proc-info-proc-states ctx) (make-proc-states ctx))
    (setf (proc-info-collect-state ctx) (funcall (proc-info-init-collect-state-fn ctx)))
    (setf (proc-info-to-processor-channels ctx) (make-to-processor-channels num-of-procs))
    (setf (proc-info-to-collector-channel ctx) (make-collector-channel))
    (setf (proc-info-wrapped-processors ctx) (make-wrapped-processors ctx))
    (setf (proc-info-wrapped-collector ctx) (wrap-collector ctx))))

(defun dispatch (element i num-of-procs to-processor-channels)
  (let* ((proc-i (mod i num-of-procs))
	 (ch (elt to-processor-channels proc-i)))
    (send ch (cons element i))))

(defun feed (stream ctx)
  (let ((read-fn (proc-info-read-fn ctx))
	(num-of-procs (proc-info-num-of-procs ctx))
	(to-processor-channels (proc-info-to-processor-channels ctx)))
    (loop for i from 0
	  for stream-element = (funcall read-fn stream)
	  until (eq stream-element :END-OF-STREAM)
	  do (dispatch stream-element i num-of-procs to-processor-channels))))

(defun process (stream proc-fn
		&key (read-fn #'default-read-line)
		  (init-proc-state-fn #'(lambda () nil))
		  (init-collect-state-fn #'(lambda () nil))
		  (num-of-procs 4)
		  (collect-fn #'echo)
		  (process-end-of-stream-hook-fn nil))
  (let ((ctx (make-proc-info :proc-fn proc-fn
			     :read-fn read-fn
			     :init-proc-state-fn init-proc-state-fn
			     :init-collect-state-fn init-collect-state-fn
			     :num-of-procs num-of-procs
			     :collect-fn collect-fn
			     :process-end-of-stream-hook-fn process-end-of-stream-hook-fn)))
    (init-additional-ctx ctx)
    (feed stream ctx)
    (loop for ch across (proc-info-to-processor-channels ctx)
	  do (send ch (cons :END-OF-STREAM nil)))
    (loop for p across (proc-info-wrapped-processors ctx) do
      (join-thread p))
    (join-thread (proc-info-wrapped-collector ctx))))

(defun basic-test-1 ()
  (with-open-file (f #p"stream-par-procs.lisp")
    (process f
	     (lambda (elem elem-i state send-fn)
	       (declare (ignore state elem-i state))
	       (funcall send-fn (length elem)))
	     :collect-fn (lambda (n sum)
			   ;; (sleep 1)
			   ;; (format t "~A,~A~%" n sum)
			   (+ n sum))
	     :init-collect-state-fn (lambda () 0)
	     :process-end-of-stream-hook-fn (lambda (state send-fn)
					      (declare (ignore state))
					      (funcall send-fn 10000))
	     :num-of-procs 8)))
