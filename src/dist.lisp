(in-package #:hexmaw)

;;; The standalone build: tools/build-dist dumps the game into dist/ with Deploy
;;; (asdf:make, which hexmaw.asd sends to deploy-op). Deploy copies the foreign
;;; libraries beside the executable, and Trial's own deploy hook copies every asset pool
;;; to pool/<name>/ and points the pools there, so files read through DATA-PATH (dev.lisp)
;;; are found wherever dist/ ends up.

(deploy:define-hook (:build hexmaw) ()
  ;; The blocks were built before the dump; the blueprints aren't shipped.
  (setf hexmaw.blueprint:*build-blocks* NIL))

(defun dist-main ()
  "Entry point of the standalone executable: the game on the main menu. HEXMAW_EVAL_PORT
starts the eval server, so tools/hd can drive a build; there is no Swank.
Quits the process when the window closes."
  (when (env-integer "HEXMAW_EVAL_PORT")
    (start-eval-server))
  (setf *game-state* :title)
  (unwind-protect (launch)
    (stop-eval-server)
    (deploy:quit)))
