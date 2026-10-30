(in-package #:hexmaw)

;;; Live development support: a localhost eval server, file reloading on the
;;; game thread, a runtime-error guard that keeps the game alive after a bad
;;; edit, and screenshots. tools/hd is the command-line client.

(defparameter *eval-port* 7171)
(defvar *eval-server* NIL)
(defvar *game-thread* NIL)
(defvar *render-pass* NIL "The pass the game world draws into.")
(defvar *output-pass* NIL "The last pass, what reaches the screen: the world with the menus over it.")
(defvar *debug-version* T
  "True in development: the main menu offers the debug level and Settings the debug
minimap. The standalone build (dist.lisp) sets it to NIL, a release version.")

(defun root ()
  "The project folder, or the executable's in a standalone build (dist.lisp)."
  (if (deploy:deployed-p)
      (deploy:runtime-directory)
      (asdf:system-source-directory :hexmaw)))

(defun data-path (file)
  "FILE under data/, the HEXMAW pool. Read game files through this, not ROOT:
a standalone build ships data/ as its pool, pool/hexmaw/ beside the executable."
  (pool-path 'hexmaw file))

(defun env-integer (name)
  (let ((value (uiop:getenv name)))
    (when (and value (string/= value ""))
      (parse-integer value :junk-allowed T))))

(defun backtrace-string (&optional (count 25))
  "The current backtrace, starting at the frame that signalled (the handler frames are dropped)."
  (let* ((text (with-output-to-string (stream)
                 (sb-debug:print-backtrace :stream stream :count (+ count 10) :print-thread NIL)))
         (start (or (search "(ERROR " text) (search "(CERROR " text) (search "(SB-KERNEL::%SIGNAL" text)))
         (start (if start (or (position #\Newline text :end start :from-end T) 0) 0))
         (lines (with-input-from-string (in (subseq text start))
                  (loop for line = (read-line in NIL) while line
                        unless (string= "" line) collect line))))
    (format NIL "~{~a~^~%~}" (subseq lines 0 (min count (length lines))))))

;;; Runtime errors. Instead of crashing the game (or dropping into a debugger
;;; nobody is watching), errors in event handlers and rendering are recorded
;;; here and the offending event or frame is skipped.

(defvar *runtime-errors* (make-array 0 :adjustable T :fill-pointer T)
  "Recent distinct runtime errors, oldest first. Each is a plist.")
(defvar *runtime-error-count* 0
  "Total runtime error occurrences since start, repeats included.")
(defparameter *max-runtime-errors* 20)

(defun note-runtime-error (condition where)
  (let ((message (or (ignore-errors (princ-to-string condition))
                     (format NIL "<unprintable ~s>" (type-of condition))))
        (id (incf *runtime-error-count*))
        (now (get-internal-real-time))
        (last (when (< 0 (length *runtime-errors*))
                (aref *runtime-errors* (1- (length *runtime-errors*))))))
    ;; A repeat only if it is still firing; one that stopped and came back is new.
    (cond ((and last (equal message (getf last :message))
                (< (- now (or (getf last :last-time) 0)) internal-time-units-per-second))
           (incf (getf last :repeats))
           (setf (getf last :last-id) id (getf last :last-time) now))
          (T
           (v:error :hexmaw "Runtime error in ~a: ~a" where message)
           (when (<= *max-runtime-errors* (length *runtime-errors*))
             (replace *runtime-errors* *runtime-errors* :start2 1)
             (decf (fill-pointer *runtime-errors*)))
           (vector-push-extend (list :where where :message message :repeats 1
                                     :first-id id :last-id id :last-time now
                                     :backtrace (backtrace-string))
                               *runtime-errors*)))))

(defun guard-runtime-error (condition where)
  "HANDLER-BIND handler: record CONDITION and skip the failing event or frame."
  (let ((restart (or (find-restart 'skip-event)
                     (and (eq where :render) (find-restart 'abort)))))
    (when restart
      ;; Recording must never fail: an error escaping from here would park the
      ;; render thread in the debugger and freeze the game.
      (handler-case (note-runtime-error condition where)
        (error (e) (ignore-errors (v:error :hexmaw "Failed to record runtime error: ~a" e))))
      (invoke-restart restart))))

(defun format-runtime-errors (errors &key backtrace)
  (with-output-to-string (out)
    (dolist (e errors)
      (format out "[~a, ~d time~:p] ~a~%" (getf e :where) (getf e :repeats) (getf e :message))
      (when backtrace
        (format out "~a~%" (getf e :backtrace))))))

(defun runtime-errors-since (id &key (new T))
  "Errors that happened after occurrence ID. With NEW, only those that first appeared
after it; otherwise only those that were already happening before it and still are."
  (remove-if-not (lambda (e)
                   (and (< id (getf e :last-id))
                        (if new (< id (getf e :first-id)) (<= (getf e :first-id) id))))
                 (coerce *runtime-errors* 'list)))

(defun runtime-errors (&key (backtrace T))
  "Describe recent runtime errors, newest last."
  (if (= 0 (length *runtime-errors*))
      "No runtime errors."
      (format-runtime-errors (coerce *runtime-errors* 'list) :backtrace backtrace)))

(defun clear-runtime-errors ()
  (setf (fill-pointer *runtime-errors*) 0)
  "Cleared.")

;;; Running code on the game thread. Redefinitions and anything touching GL
;;; or the scene must happen between frames, not from the server thread.

(define-condition game-error (error)
  ((original :initarg :original :reader original)
   (backtrace :initarg :backtrace :reader backtrace))
  (:report (lambda (c s)
             (format s "~a~%~%Backtrace:~%~a" (original c) (backtrace c)))))

(define-condition reload-failed (simple-error) ()
  (:documentation "A reload that failed for a reason the message fully explains; no backtrace needed."))

(defun reload-failed (format-control &rest format-arguments)
  (error 'reload-failed :format-control format-control :format-arguments format-arguments))

(defun game-running-p ()
  (and +main+ (eq (state +main+) 'org.shirakumo.fraf.trial::render-loop)))

(defun changing-scene-p ()
  (and +main+ (eq (state +main+) 'org.shirakumo.fraf.trial::change-scene)))

(defun wait-for-scene-change (&key (timeout 10))
  "Return once the game isn't in the middle of swapping scenes. A swap takes the game
thread a moment (setup, loading, a full GC), and the game isn't running meanwhile."
  (loop with deadline = (+ (get-internal-real-time) (* timeout internal-time-units-per-second))
        while (changing-scene-p)
        do (when (< deadline (get-internal-real-time))
             (reload-failed "The game has been changing scenes for ~d s; check its terminal output." timeout))
           (sleep 0.02)))

(defun call-capturing (function)
  "Call FUNCTION. Return (:values . values) or (:error condition backtrace)."
  (let ((backtrace NIL))
    (handler-case
        (handler-bind ((serious-condition
                         (lambda (e) (declare (ignore e))
                           (setf backtrace (backtrace-string)))))
          (cons :values (multiple-value-list (funcall function))))
      (serious-condition (e)
        (list :error e backtrace)))))

(defun call-in-game (function &key (timeout 30))
  "Call FUNCTION on the game thread between frames and return its values.
If the game is not running, call it directly; if it is swapping scenes, wait for
that first, since GL calls only work on the game thread. Errors are re-signalled in
the caller as GAME-ERROR, with the backtrace from where they happened."
  (unless (eq (bt:current-thread) *game-thread*)
    (wait-for-scene-change))
  (let ((result (if (or (not (game-running-p)) (eq (bt:current-thread) *game-thread*))
                    (call-capturing function)
                    (let ((semaphore (sb-thread:make-semaphore))
                          (result NIL))
                      (call-in-render-loop (lambda ()
                                             (unwind-protect (setf result (call-capturing function))
                                               (sb-thread:signal-semaphore semaphore)))
                                           (scene +main+))
                      (unless (sb-thread:wait-on-semaphore semaphore :timeout timeout)
                        (reload-failed "The game thread did not run the request within ~d s, so the ~
                                        game is probably frozen (an error escaped into the render thread, ~
                                        or an endless loop). Check the game's terminal output, then ~
                                        restart it with ./run.sh." timeout))
                      result))))
    (ecase (car result)
      (:values (values-list (cdr result)))
      (:error (error 'game-error :original (second result) :backtrace (third result))))))

(defmacro game (&body body)
  "Evaluate BODY on the game thread between frames. Use it for anything that
changes the scene, its entities or GL state."
  `(call-in-game (lambda () ,@body)))

;;; Reloading.

(defun fasl-path (source)
  (let ((relative (enough-namestring source (root))))
    (merge-pathnames (make-pathname :directory '(:relative ".cache" "fasl")
                                    :name (substitute #\- #\/ (subseq relative 0 (position #\. relative :from-end T)))
                                    :type "fasl")
                     (root))))

(defun compile-quietly (source fasl)
  "Compile SOURCE to FASL. Returns the fasl, or NIL, and the compiler output."
  (let ((log (make-string-output-stream)))
    (multiple-value-bind (output warnings-p failure-p)
        (handler-case
            (let ((*standard-output* log) (*error-output* log)
                  (*compile-verbose* NIL) (*compile-print* NIL)
                  (*package* (find-package '#:cl-user)))
              (compile-file source :output-file fasl))
          (error (e)
            (format log "~&~a~%" e)
            (values NIL T T)))
      (declare (ignore warnings-p))
      (values (unless failure-p output) (get-output-stream-string log)))))

(defparameter *reload-settle-time* 0.3
  "Seconds of play after a reload during which new runtime errors count as caused by it.")

(defun load-and-check (thunk description compiler-output)
  "Run THUNK on the game thread, let the game run briefly, and fail if new runtime errors appear."
  (let ((mark (call-in-game (lambda () (funcall thunk) *runtime-error-count*))))
    (when (game-running-p)
      (sleep *reload-settle-time*))
    (let ((new (runtime-errors-since mark))
          (ongoing (runtime-errors-since mark :new NIL)))
      (when new
        (reload-failed "~a loaded, but the game now signals errors. The new code stays ~
                        loaded and the failing events are skipped each frame; fix it or revert.~%~a"
                       description (format-runtime-errors new :backtrace T)))
      (string-right-trim '(#\Newline #\Space)
                         (format NIL "Reloaded ~a.~@[~%~a~]~@[~%Errors from before this reload are still happening:~%~a~]"
                                 description
                                 (when (string/= "" (string-trim '(#\Newline #\Space) compiler-output))
                                   compiler-output)
                                 (when ongoing (format-runtime-errors ongoing)))))))

(defun reload-file (file)
  "Compile FILE (relative to the project root) and load it into the running game.
Signals an error with the compiler output if it does not compile cleanly, or
with the runtime errors if the game starts failing once it is loaded."
  (let* ((source (merge-pathnames file (root)))
         (name (enough-namestring source (root)))
         (fasl (fasl-path source)))
    (ensure-directories-exist fasl)
    (multiple-value-bind (output log) (compile-quietly source fasl)
      (unless output
        (reload-failed "~a did not compile; nothing was loaded and the game runs the previous code.~%~a" name log))
      ;; Trial shadows LOAD with a generic function for assets.
      (let ((result (load-and-check (lambda () (cl:load output)) name log)))
        ;; Redefining a loaded asset reloads it, and entities already using it stop
        ;; drawing until the scene is rebuilt.
        (cond ((and (game-running-p) (defines-assets-p source))
               (reload-scene)
               (format NIL "~a~%Scene reloaded because this file defines assets." result))
              (T result))))))

(defun defines-assets-p (source)
  "True if SOURCE has a top-level asset definition: one that starts a line, so a mention
in a string or comment (as in this file) doesn't count."
  (let ((text (uiop:read-file-string source))
        (nl (string #\Newline)))
    (or (search (concatenate 'string nl "(define-asset ") text :test #'char-equal)
        ;; Defines an image asset (creature.lisp, spells.lisp).
        (search (concatenate 'string nl "(define-fx-animation ") text :test #'char-equal))))

(defun reload-system ()
  "Reload the whole system through ASDF, for changes that affect other files (macros, the .asd).
ASDF reloads every file after the first changed one, which redefines the assets in them,
so the scene is rebuilt afterwards, as RELOAD-FILE does for one such file."
  (let* ((log (make-string-output-stream))
         (result (load-and-check (lambda ()
                                   (let ((*standard-output* log) (*error-output* log))
                                     (asdf:load-system :hexmaw)))
                                 "hexmaw (whole system)"
                                 (get-output-stream-string log))))
    (cond ((game-running-p)
           (reload-scene)
           (format NIL "~a~%Scene reloaded, since the reload redefines assets." result))
          (T result))))

(defun reload-scene (&key (timeout 10))
  "Rebuild the scene from SETUP-SCENE and wait until the new one is up. The player keeps
position and view."
  (let ((old (and +main+ (scene +main+))))
    (maybe-reload-scene)
    (when (game-running-p)
      ;; The game thread handles the request on its next frame and makes a new scene.
      (loop with deadline = (+ (get-internal-real-time) (* timeout internal-time-units-per-second))
            until (and (not (eq old (scene +main+))) (game-running-p))
            do (when (< deadline (get-internal-real-time))
                 (reload-failed "The scene didn't reload within ~d s; check the game's terminal output." timeout))
               (sleep 0.02))
      ;; Let the new scene draw a frame, so a screenshot taken next shows it.
      (call-in-game (constantly NIL))
      (call-in-game (constantly NIL)))
    "Scene reloaded."))

;;; Screenshots.

(defun timestamp ()
  (multiple-value-bind (s m h d mo y) (decode-universal-time (get-universal-time))
    (format NIL "~4,'0d~2,'0d~2,'0d-~2,'0d~2,'0d~2,'0d-~3,'0d" y mo d h m s
            (mod (floor (get-internal-real-time) (/ internal-time-units-per-second 1000)) 1000))))

(defun show-window ()
  "Restore the game window if it is minimised."
  (show (context +main+))
  "Window restore requested.")

(defun screenshot (&optional file)
  "Save the last rendered frame as a PNG and return its absolute path."
  (unless (visible-p (context +main+))
    (error "The game window is minimised, so nothing is being drawn. ~
            Restore it (tools/hd '(show-window)') and try again."))
  (let ((file (merge-pathnames (or file (format NIL "screenshots/~a.png" (timestamp))) (root))))
    (ensure-directories-exist file)
    (call-in-game (lambda () (capture (or *output-pass* *render-pass*) :file file)))
    (namestring file)))

;;; The eval server. One request per connection: the client sends a single
;;; form, the server answers "OK" or "ERROR" on the first line, then text.

(defun evaluate-request (form)
  "Evaluate FORM on the server thread (wrap game-state changes in GAME).
Returns printed output plus values as one string; strings print without quotes."
  (let* ((out (make-string-output-stream))
         (result (let ((*standard-output* out) (*error-output* out) (*trace-output* out)
                       (*package* (find-package '#:hexmaw)))
                   (call-capturing
                    (lambda ()
                      (mapcar (lambda (v) (if (stringp v) v (prin1-to-string v)))
                              (multiple-value-list (eval form)))))))
         (output (get-output-stream-string out)))
    (ecase (car result)
      (:error
       (let ((e (second result)))
         (error (if (typep e '(or game-error reload-failed)) e
                    (make-condition 'game-error :original e :backtrace (third result))))))
      (:values
       (let ((values (cadr result)))
         (format NIL "~a~:[~;~%~]~{~a~^~%~}" output
                 (and values (string/= "" output) (char/= #\Newline (char output (1- (length output)))))
                 values))))))

(defun serve-client (client)
  (let ((stream (sb-bsd-sockets:socket-make-stream client :input T :output T
                                                          :element-type 'character
                                                          :external-format :utf-8
                                                          :buffering :full)))
    (multiple-value-bind (ok text)
        (handler-case
            (let ((form (let ((*package* (find-package '#:hexmaw))
                              (*read-eval* NIL))
                          (read stream))))
              (values T (evaluate-request form)))
          (error (e)
            (values NIL (or (ignore-errors (princ-to-string e)) "Unprintable error."))))
      (format stream "~:[ERROR~;OK~]~%~a~%" ok text)
      (finish-output stream))))

(defun serve (socket)
  (loop for client = (handler-case (sb-bsd-sockets:socket-accept socket)
                       (error () (return)))
        do (unwind-protect
                (handler-case (serve-client client)
                  (error (e) (v:warn :hexmaw "Eval client failed: ~a" e)))
             (ignore-errors (sb-bsd-sockets:socket-close client)))))

(defun stop-eval-server ()
  (when *eval-server*
    (ignore-errors (sb-bsd-sockets:socket-close (car *eval-server*)))
    (setf *eval-server* NIL)))

(defun start-eval-server (&key (port (or (env-integer "HEXMAW_EVAL_PORT") *eval-port*)))
  "Listen for forms on 127.0.0.1:PORT. Never bind this to anything but localhost."
  (stop-eval-server)
  (let ((socket (make-instance 'sb-bsd-sockets:inet-socket :type :stream :protocol :tcp)))
    (setf (sb-bsd-sockets:sockopt-reuse-address socket) T)
    (sb-bsd-sockets:socket-bind socket #(127 0 0 1) port)
    (sb-bsd-sockets:socket-listen socket 8)
    (setf *eval-server* (cons socket (bt:make-thread (lambda () (serve socket))
                                                     :name "hexmaw eval server")))
    (v:info :hexmaw "Eval server listening on 127.0.0.1:~d" port)
    port))
