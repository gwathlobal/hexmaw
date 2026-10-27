;;;; Entry point for every Lisp session on this project (run.sh, your editor, CI).
;;;;
;;;;   sbcl --dynamic-space-size 4096 --no-userinit --load boot.lisp
;;;;
;;;; Trial refuses to load with less than 2 GB of heap. --no-userinit keeps
;;;; ~/.sbclrc from loading ~/quicklisp; this project uses its own Quicklisp in
;;;; .ql/ with the Shirakumo dist, and ASDF is limited to this folder so it
;;;; cannot pick up stray systems from elsewhere under ~/common-lisp/ (lem's
;;;; .qlot trees ship an old dissect that breaks Trial).

(require :asdf)

(defparameter cl-user::*hexmaw-root*
  (make-pathname :name NIL :type NIL :defaults *load-truename*))

(asdf:initialize-source-registry
 `(:source-registry :ignore-inherited-configuration
                    (:directory ,cl-user::*hexmaw-root*)))

(load (merge-pathnames ".ql/setup.lisp" cl-user::*hexmaw-root*))

(ql:quickload :hexmaw :silent T)
