(in-package #:hexmaw)

;;; The standalone build: tools/build-dist dumps the game into dist/ with Deploy
;;; (asdf:make, which hexmaw.asd sends to deploy-op). Deploy copies the foreign
;;; libraries beside the executable, and Trial's own deploy hook copies every asset pool
;;; to pool/<name>/ and points the pools there, so files read through DATA-PATH (dev.lisp)
;;; are found wherever dist/ ends up.

(deploy:define-hook (:build hexmaw) ()
  ;; The blocks were built before the dump; the blueprints aren't shipped.
  (setf hexmaw.blueprint:*build-blocks* NIL)
  ;; A build is a release version: no debug level or debug minimap.
  (setf *debug-version* NIL))

(deploy:define-hook (:deploy hexmaw-fonts -10) (directory)
  ;; After Trial's and Alloy's hooks (priority 0) have copied their font caches. The menus
  ;; draw in Jersey 15 (*menu-font*, menu.lisp); nothing draws in the Arial atlas Alloy
  ;; ships, and its source isn't ours to vouch for, so it stays out of the build.
  (dolist (file (directory (merge-pathnames "pool/**/Arial.*" directory)))
    (delete-file file)))

(deploy:define-hook (:boot hexmaw) ()
  ;; Found when the image was built, on the build machine; find it again on the player's.
  (setf *save-directory* (uiop:xdg-data-home "hexmaw/saves/")))

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
