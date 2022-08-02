(asdf:defsystem #:stream-par-procs
  :description "Stream parallel processors for Common Lisp"
  :author "Vee Satayamas <vsatayamas@gmail.com>"
  :license "MIT"
  :version "0.0.1"
  :serial t
  :depends-on (#:chanl #:bordeaux-threads)
  :components ((:file "stream-par-procs")))
