(defpackage #:stream-par-procs
  (:use #:cl)
  (:import-from #:bordeaux-threads :make-thread :join-thread)
  (:import-from #:chanl :bounded-channel :send :recv))

(in-package #:stream-par-procs)

(defparameter *to-processor-buffer-size* 2)
(defparameter *to-collector-buffer-size* 2)

(defun default-read-line (stream)
  (read-line stream nil :END-OF-STREAM))

(defun split (stream-element proc-fn state-vec i num-of-procs)
  )

(defun make-states (num-of-procs init-state-fn)
  (let ((states (make-array num-of-procs)))
    (loop for i from 0 below num-of-procs
	  do (setf (elt states i)
		   (funcall init-state-fn)))
    states))

(defun make-to-processor-channels (num-of-procs)
  (make-array num-of-procs
	      :initial-contents 
	      (loop for i from 0 below num-of-procs
		    collect
		    (make-instance 'bounded-channel :size *to-processor-buffer-size*))))

(defun wrap-processor (proc-fn state to-proc-chan to-collector-chan)
  (make-thread (lambda ()
		 (loop for stream-element = (recv to-proc-chan)
		       until (eq stream-element :END-OF-STREAM)
		       do
			  (setq state (funcall proc-fn stream-element state to-collector-chan)))
		 (send to-collector-chan :END-OF-STREAM))))

(defun wrap-collector (collect-fn to-collector-chan num-of-procs state)
  (make-thread (lambda ()
		 (loop with finish-count = 0
		       for element = (recv to-collector-chan)
		       do 
			  (if (eq element :END-OF-STREAM)
			      (incf finish-count)
			      (setq state (funcall collect-fn element state)))	  
		       until (eq finish-count num-of-procs)
		       finally (return state)))))

(defun echo (element state)
  (print element))

(defun make-collector-channel ()
  (make-instance 'bounded-channel :size *to-collector-buffer-size*))

(defun make-wrapped-processors (proc-fn states to-processor-channels to-collector-chan num-of-procs)
  (make-array num-of-procs
	      :initial-contents
	      (loop for i from 0 below num-of-procs
		    collect (wrap-processor proc-fn
					    (elt states i)
					    (elt to-processor-channels i)
					    to-collector-chan))))

(defun dispatch (element i num-of-procs to-processor-channels)
  (let* ((proc-i (mod i num-of-procs))
	 (ch (elt to-processor-channels proc-i)))
    (send ch (values element i))))

(defun feed (stream read-fn num-of-procs to-processor-channels)
  (loop for i from 0
	for stream-element = (funcall read-fn stream)
	until (eq stream-element :END-OF-STREAM)
	do (dispatch stream-element i num-of-procs to-processor-channels)))

(defun process (stream proc-fn
		&key (read-fn #'default-read-line)
		  (init-proc-state-fn #'(lambda () nil))
		  (init-collect-state-fn #'(lambda () nil))
		  (num-of-procs 4)
		  (collect-fn #'echo))
  (let* ((proc-states (make-states num-of-procs init-proc-state-fn))
	 (collect-state (funcall init-collect-state-fn))
	 (to-processor-channels (make-to-processor-channels num-of-procs))
	 (to-collector-channel (make-collector-channel))
	 (wrapped-processors (make-wrapped-processors proc-fn proc-states to-processor-channels
						      to-collector-channel num-of-procs))
	 (wrapped-collector (wrap-collector collect-fn to-collector-channel
					    num-of-procs collect-state)))
    (feed stream read-fn num-of-procs to-processor-channels)
    (loop for ch across to-processor-channels
	  do
	     (send ch :END-OF-STREAM))
    (loop for p across wrapped-processors do
      (join-thread p))
    (join-thread wrapped-collector)))


(defun t1 ()
  (with-open-file (f #p"stream-par-procs.lisp")
    (process f
	     (lambda (elem state output-ch)
	       (send output-ch (length elem)))
	     :collect-fn (lambda (n sum)
			   (+ n sum))
	     :init-collect-state-fn (lambda () 0))))
