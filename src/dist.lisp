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

;;; The player's documents beside the executable, beside Hexmaw.app on macOS: the README, the
;;; EULA, the changelog and the notices, and licenses/ with the texts the notices name and the
;;; source of the LGPL libraries (notices/head.txt says why).

(defparameter *player-documents*
  '(("README-PLAYERS.txt" "README.txt") ("EULA.txt") ("CHANGELOG.md") ("THIRD-PARTY-NOTICES.txt")
    ("LICENSE" "licenses/hexmaw-code-zlib.txt") ("ASSETS-LICENSE.md" "licenses/ASSETS-LICENSE.md")
    ("notices/GPL-3.0.txt" "licenses/GPL-3.0.txt") ("notices/LGPL-3.0.txt" "licenses/LGPL-3.0.txt")
    ("notices/LGPL-2.1.txt" "licenses/LGPL-2.1.txt") ("notices/OFL-1.1.txt" "licenses/OFL-1.1.txt")
    ("notices/GCC-exception-3.1.txt" "licenses/GCC-exception-3.1.txt")
    ("notices/SBCL-COPYING.txt" "licenses/SBCL-COPYING.txt"))
  "Files from the source tree a build ships, as (source [where in the build]).")

(defparameter *lgpl-systems* '("text.editing" "utilities.print-items" "flexichain")
  "The LGPL libraries whose source ships in licenses/lgpl-source/, as tools/notices allows.")

(defun copy-folder (from to)
  (ensure-directories-exist to)
  (dolist (file (uiop:directory-files from))
    (uiop:copy-file file (merge-pathnames (file-namestring file) to)))
  (dolist (sub (uiop:subdirectories from))
    (copy-folder sub (merge-pathnames (make-pathname :directory (list :relative (car (last (pathname-directory sub)))))
                                    to))))

(defun player-folder (directory)
  "Where the player unpacks to: DIRECTORY itself, or for a macOS bundle's Contents/Resources/
(Deploy's macos-app-deploy-op) the folder Hexmaw.app is in."
  (let ((parts (pathname-directory directory)))
    (if (equal (last parts 2) '("Contents" "Resources"))
        (make-pathname :directory (butlast parts 3) :name NIL :type NIL :defaults directory)
        directory)))

(deploy:define-hook (:deploy hexmaw-documents -20) (directory)
  (let ((root (asdf:system-source-directory :hexmaw))
        (out (player-folder directory)))
    (loop for (source target) in *player-documents*
          for to = (merge-pathnames (or target source) out)
          do (ensure-directories-exist to)
             (uiop:copy-file (merge-pathnames source root) to))
    (dolist (system *lgpl-systems*)
      (let ((source (asdf:system-source-directory system)))
        (copy-folder source (merge-pathnames (format NIL "licenses/lgpl-source/~a/" (car (last (pathname-directory source))))
                                           out))))))

(deploy:define-hook (:boot hexmaw) ()
  ;; Found when the image was built, on the build machine; find it again on the player's.
  (setf *save-directory* (uiop:xdg-data-home "hexmaw/saves/"))
  ;; Trial writes its log beside the executable (in ~/Library on macOS), where a player may
  ;; not be allowed to write; put it with the saves, unless TRIAL_LOGFILE says otherwise.
  (unless (deploy:env-set-p "TRIAL_LOGFILE")
    (ensure-directories-exist (user-directory))
    (setf (uiop:getenv "TRIAL_LOGFILE")
          (uiop:native-namestring (merge-pathnames "trial.log" (user-directory))))))

(defun dist-main ()
  "Entry point of the standalone executable: the game on the main menu. With arguments,
Trial's command line instead (`hexmaw help` lists the commands: version, check, selftest,
system, paths and the rest). HEXMAW_EVAL_PORT starts the eval server, so tools/hd can
drive a build; there is no Swank. Quits the process when the window closes."
  ;; macOS passes -psn_... to an app opened from the Finder on older systems.
  (if (remove-if (lambda (arg) (uiop:string-prefix-p "-psn" arg))
                 (rest (deploy:command-line-arguments)))
      (command-line-toplevel)
      (play-dist)))

(defvar *exit-code* 0 "What the process exits with when the window closes.")

(defun play-dist (&optional script)
  "Run the game until its window closes, then quit with *EXIT-CODE*. SCRIPT, if given, is
called in a thread of its own once the game is up (the self-test)."
  (when (env-integer "HEXMAW_EVAL_PORT")
    (start-eval-server))
  (setf *game-state* :title)
  (when script
    (bt:make-thread script :name "hexmaw script"))
  (unwind-protect (launch)
    (stop-eval-server)
    (quit-process *exit-code*)))

(defun quit-process (code)
  "End the process with CODE once the game is done: Deploy's quit hooks, the log and the
streams written out, then an abort exit. Deploy's own quit exits through the C runtime, which
on Windows runs every library's DLL shutdown, and with XAudio2's threads still alive (the
sound server is stopped, not freed, at quit: main.lisp) the game hung there after its window
closed. An abort exit runs none of that; it is what the self-test's watchdog already used to
end a stuck game on Windows."
  (ignore-errors (deploy:run-hooks :quit))
  (ignore-errors (v:remove-global-controller))
  (ignore-errors (finish-output *standard-output*))
  (ignore-errors (finish-output *error-output*))
  (sb-ext:exit :code code :abort T))


;;; Reports: what `hexmaw check` and `hexmaw selftest` found, printed and saved in the user
;;; directory, since a Windows build has no console to print to and a player can send the
;;; file with a problem report.

(defun write-report (name lines)
  "Print LINES and save them as NAME in the user directory."
  (let ((file (merge-pathnames name (user-directory))))
    (ensure-directories-exist file)
    (with-open-file (out file :direction :output :if-exists :supersede)
      (dolist (line lines)
        (write-line line out)
        (write-line line *standard-output*)))
    (finish-output *standard-output*)
    file))

(defun build-description ()
  (format NIL "Hexmaw ~a, ~a ~a" (game-version) (software-type) (machine-type)))

(defparameter *checked-files*
  '("fonts/Jersey15.json" "fonts/Jersey15.png" "sfx/index.lisp" "music/title.ogg"
    "splash/title.png" "sprites/imp/turnaround.png" "textures/wall-stone.png"
    "blocks/chamber.glb")
  "Files under data/ the game can't start without, one of each kind, for `hexmaw check`.")

(defun installation-problems ()
  "What is missing from this installation, as strings; NIL when nothing is."
  (append (loop for file in *checked-files*
                unless (probe-file (data-path file))
                  collect (format NIL "missing: ~a" (uiop:native-namestring (data-path file))))
          (unless (directory (data-path "blocks/*.glb"))
            (list "missing: the level blocks (blocks/*.glb)"))
          ;; The libraries the build ships beside the executable. Deploy opens at boot only
          ;; those that were open when the image was dumped; the rest open when first used.
          (loop for library in (deploy:list-libraries)
                for problem = (unless (or (deploy:library-dont-deploy-p library)
                                          (deploy:library-dont-open-p library)
                                          (deploy:library-open-p library))
                                (handler-case (progn (deploy:open-library library) NIL)
                                  (error (e) (princ-to-string e))))
                when problem
                  collect (format NIL "won't load: ~(~a~): ~a" (deploy:library-name library) problem))))

(command-line:define-command check ()
  :help "Check that the game's files and libraries are all where it needs them, without opening a window."
  (let ((problems (installation-problems)))
    (write-report "check.txt"
                  (append (list (build-description)
                                (format NIL "data: ~a" (uiop:native-namestring (data-path ""))))
                          problems
                          (list (if problems
                                    (format NIL "~d problem~:p found." (length problems))
                                    "All data files and libraries present."))))
    (quit-process (if problems 1 0))))

;;; The self-test: the window, the main menu, a generated level, a screenshot, a clean quit.

(defparameter *selftest-seed* 12345 "The run seed the self-test plays.")
(defparameter *selftest-timeout* 180 "Seconds before the self-test gives up and exits 2.")

(defun wait-until (test timeout what)
  (loop with deadline = (+ (get-internal-real-time) (* timeout internal-time-units-per-second))
        until (funcall test)
        do (when (< deadline (get-internal-real-time))
             (error "Timed out after ~d s waiting for ~a." timeout what))
           (sleep 0.05)))

(defun wait-frames (count)
  (let ((target (+ *render-frame* count)))
    (wait-until (lambda () (<= target *render-frame*)) 60 (format NIL "~d frames" count))))

(defvar *selftest-lines* () "What the self-test has found so far, newest first.")

(defun selftest-verdict-p ()
  "Whether the self-test has said whether it passed."
  (find-if (lambda (line) (uiop:string-prefix-p "self-test " line)) *selftest-lines*))

(defun selftest-script (directory)
  "Drive the running game through the self-test, then close it. Writes selftest.txt."
  (symbol-macrolet ((lines *selftest-lines*))
    (flet ((note (format &rest args) (push (apply #'format NIL format args) lines)))
      (handler-case
          (progn
            (wait-until #'game-running-p 60 "the game window")
            (wait-frames 30)
            (note "menu: ~(~a~), ~d frames drawn" *game-state* *render-frame*)
            (destructuring-bind (renderer gl-version vendor)
                (game (list (gl:get-string :renderer) (gl:get-string :version) (gl:get-string :vendor)))
              (note "GL: ~a, ~a (~a)" renderer gl-version vendor))
            ;; The backend's class, as MIXED.PULSE:DRAIN; Trial falls back to a dummy one.
            (note "sound: ~a" (or (ignore-errors
                                   (let ((*package* (find-package '#:keyword)))
                                     (prin1-to-string
                                      (type-of (harmony:segment :drain (harmony:segment :output harmony:*server*))))))
                                  "none"))
            (game (setf *level-seed* *selftest-seed*) (start-game))
            (wait-until (lambda () (and (eq *game-state* :playing) (eq *level* :generated) *player*))
                        120 "a generated level")
            (wait-frames 120)
            (note "level: seed ~d, ~d monsters, ~d blocks" *last-level-seed* (length *creatures*)
                  (length *map-blocks*))
            (note "screenshot: ~a"
                  (screenshot (merge-pathnames "selftest.png" (uiop:ensure-directory-pathname directory))))
            (wait-frames 2)
            (when (< 0 *runtime-error-count*)
              (error "~d runtime error~:p, the first: ~a" *runtime-error-count*
                     (getf (aref *runtime-errors* 0) :message)))
            (note "self-test passed")
            (setf *exit-code* 0))
        (error (e)
          (note "self-test FAILED: ~a" e)
          (setf *exit-code* 1))))
    (write-report "selftest.txt" (reverse lines))
    (ignore-errors (game (exit-game)))))

(command-line:define-command selftest (&key ((directory :directory :d) NIL pathname "Where to save the screenshot; the user directory if not given."))
  :help "Open the window, show the main menu, play a generated level for a moment, take a screenshot and quit, saying whether all of that worked."
  (let ((directory (or directory (user-directory))))
    (setf *exit-code* 1
          *selftest-lines* (list (build-description)))
    (bt:make-thread (lambda ()
                      (sleep *selftest-timeout*)
                      ;; What it found, then why it gave up: still running the test, or the
                      ;; test done and the game not quitting.
                      (ignore-errors
                       (write-report "selftest.txt"
                                     (reverse (cons (format NIL "self-test FAILED: ~:[no answer~;the game didn't quit~] within ~d s"
                                                            (selftest-verdict-p) *selftest-timeout*)
                                                    (or *selftest-lines* (list (build-description)))))))
                      (sb-ext:exit :code 2 :abort T))
                    :name "hexmaw selftest watchdog")
    ;; An error that would stop the game (no OpenGL context, say) ends the test at once, with
    ;; its reason in the report, instead of waiting behind Trial's error box until the
    ;; watchdog. Only on this thread: the game's other threads keep Trial's handler.
    (handler-bind ((error (lambda (e)
                            (ignore-errors
                             (push (format NIL "self-test FAILED: ~a" e) *selftest-lines*)
                             (write-report "selftest.txt" (reverse *selftest-lines*)))
                            (sb-ext:exit :code 1 :abort T))))
      (let ((org.shirakumo.fraf.trial::*inhibit-standalone-error-handler* T))
        (play-dist (lambda () (selftest-script directory)))))))
