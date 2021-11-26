;;;; april-demo.dfns.power.asd

(asdf:defsystem #:april-demo.dfns.power
  :description "Demo of April used to implement Dyalog power operators"
  :author "Andrew Sengul"
  :license  "Apache-2.0"
  :version "0.0.1"
  :serial t
  :depends-on ("april")
  :components ((:file "package")
               (:file "setup")
               (:file "demo")))
