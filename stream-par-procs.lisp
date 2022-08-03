(defpackage #:stream-par-procs
  (:use #:cl)
  (:import-from #:bordeaux-threads :make-thread :join-thread)
  (:import-from #:chanl :bounded-channel :send :recv))

(in-package #:stream-par-procs)

(defparameter *to-processor-buffer-size* 2)
(defparameter *to-collector-buffer-size* 2)

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
  to-processor-channels
  to-collector-channel
  wrapped-processors
  wrapped-collector)

(defun make-proc-states (ctx)
  (let* ((num-of-procs (proc-info-num-of-procs ctx))
	 (init-state-fn (proc-info-init-proc-state-fn ctx))
	 (states (make-array num-of-procs)))
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

(defun wrap-collector (ctx)
  (let ((collect-fn (proc-info-collect-fn ctx))
	(to-collector-chan (proc-info-to-collector-channel ctx))
	(num-of-procs (proc-info-num-of-procs ctx))
	(state (proc-info-collect-state ctx)))
    (make-thread (lambda ()
		   (loop with finish-count = 0
			 for element = (recv to-collector-chan)
			 do 
			    (if (eq element :END-OF-STREAM)
				(incf finish-count)
				(setq state (funcall collect-fn element state)))	  
			 until (eq finish-count num-of-procs)
			 finally (return state))))))

(defun echo (element state)
  (declare (ignore state))
  (print element))

(defun make-collector-channel ()
  (make-instance 'bounded-channel :size *to-collector-buffer-size*))

(defun make-wrapped-processors (ctx)
  (let ((proc-fn (proc-info-proc-fn ctx))
	(states (proc-info-proc-states ctx))
	(to-processor-channels (proc-info-to-processor-channels ctx))
	(to-collector-chan (proc-info-to-collector-channel ctx))
	(num-of-procs (proc-info-num-of-procs ctx)))
      (make-array num-of-procs
		  :initial-contents
		  (loop for i from 0 below num-of-procs
			collect (wrap-processor proc-fn
						(elt states i)
						(elt to-processor-channels i)
						to-collector-chan)))))

(defun init-additional-ctx (ctx)
  (setf (proc-info-proc-states ctx) (make-proc-states ctx))
  (setf (proc-info-collect-state ctx) (funcall (proc-info-init-collect-state-fn ctx)))
  (setf (proc-info-to-processor-channels ctx) (make-to-processor-channels (proc-info-num-of-procs ctx)))
  (setf (proc-info-to-collector-channel ctx) (make-collector-channel))
  (setf (proc-info-wrapped-processors ctx) (make-wrapped-processors ctx))
  (setf (proc-info-wrapped-collector ctx) (wrap-collector ctx)))

(defun dispatch (element i num-of-procs to-processor-channels)
  (let* ((proc-i (mod i num-of-procs))
	 (ch (elt to-processor-channels proc-i)))
    (send ch (values element i))))

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
		  (collect-fn #'echo))
  (let ((ctx (make-proc-info :proc-fn proc-fn
			     :read-fn read-fn
			     :init-proc-state-fn init-proc-state-fn
			     :init-collect-state-fn init-collect-state-fn
			     :num-of-procs num-of-procs
			     :collect-fn collect-fn)))
    (init-additional-ctx ctx)
    (feed stream ctx)
    (loop for ch across (proc-info-to-processor-channels ctx)
	  do (send ch :END-OF-STREAM))
    (loop for p across (proc-info-wrapped-processors ctx) do
      (join-thread p))
    (join-thread (proc-info-wrapped-collector ctx))))

(defun t1 ()
  (with-open-file (f #p"stream-par-procs.lisp")
    (process f
	     (lambda (elem state output-ch)
	       (declare (ignore state))
	       (send output-ch (length elem)))
	     :collect-fn (lambda (n sum)
			   (+ n sum))
	     :init-collect-state-fn (lambda () 0))))
