(in-package #:hexmaw)

;;; Sound effects, through Harmony like the music (music.lisp). Each clip is a file or a few
;;; variants in data/sfx/, made by tools/make_sfx.py from the takes chosen in
;;; audio/sfx-picks.txt and listed in data/sfx/index.lisp; audio/sfx.md says which moment
;;; plays which. A positional clip is mono and plays on Harmony's :effect mixer, a space
;;; mixer whose listener the SOUND-DIRECTOR moves with the player's eye; a first-person one
;;; plays on :speech, unplaced. Both mixers take the Settings' Sound volume.
;;;
;;; Trial's sound assets are one Harmony voice each, which plays one copy at a time, so the
;;; clips keep voices of their own: *SFX-VOICES* per file for a one-shot, taken in turn (the
;;; oldest is cut short when all are busy), and *LOOP-VOICES* for a loop, each held by one
;;; caller between START-LOOP and STOP-LOOP. They are made once, by ADD-SOUNDS, and outlive
;;; scene rebuilds (*SOUNDS*). The game thread never touches a voice's connection: PLAY-SOUND
;;; queues a request, and once a tick the director hands Harmony's mixing thread one function,
;;; SOUND-FRAME, which starts the requested voices, moves the loops and the listener, and
;;; pauses the loops while the world is frozen. (Harmony's queue holds 64 jobs: one a play
;;; would fill it in a busy frame. And an error in the mixing thread stops all sound for good,
;;; so SOUND-FRAME keeps its errors in *SOUND-ERROR* instead.) A loop is connected the first
;;; time it plays and from then on only paused and unpaused, as the music is.

(defparameter *sfx-voices* 3 "Voices for each file of a one-shot: how many copies may overlap.")
(defparameter *loop-voices* 6 "Voices for each loop clip: how many may sound at once.")
(defparameter *sound-min-distance* 2.0 "Metres within which a positional sound is at full volume.")
(defparameter *sound-max-distance* 40.0 "Metres beyond which a positional sound is silent.")
(defparameter *sound-rolloff* 1.0 "How fast a positional sound falls off between the two.")

(defclass sfx ()
  ((name :initarg :name :reader sfx-name)
   (files :initarg :files :reader sfx-files)
   (seconds :initarg :seconds :reader sfx-seconds)
   (space :initarg :space :reader sfx-space-p
          :documentation "T to play on the space mixer, at a point.")
   (loop-p :initarg :loop :reader sfx-loop-p)
   (voices :initform (make-array 0 :adjustable T :fill-pointer 0) :reader sfx-voices
           :documentation "SFX-VOICEs: for a one-shot *SFX-VOICES* per file, file by file.")
   (turn :initform 0 :accessor sfx-turn
         :documentation "The variant to play next, as an index into FILES.")
   (freed :initform NIL :accessor sfx-freed
          :documentation "T once RELOAD-SOUND has replaced it: requests still queued are dropped.")))

(defclass sfx-voice ()
  ((voice :initarg :voice :reader sfx-voice-voice :documentation "The Harmony voice.")
   (sfx :initarg :sfx :reader voice-sfx)
   (seconds :initarg :seconds :reader voice-seconds :documentation "How long its file plays.")
   (busy-until :initform 0.0 :accessor busy-until
               :documentation "Game seconds (SOUND-CLOCK) until a one-shot has played out.")
   (location :initform (make-array 3 :element-type 'single-float :initial-element 0f0)
             :reader voice-location)
   (volume :initform 1.0 :accessor voice-volume)
   (held :initform NIL :accessor voice-held
         :documentation "A loop's: T while a caller holds it (START-LOOP to STOP-LOOP).")
   (connected :initform NIL :accessor voice-connected
              :documentation "A loop's: set in the mixing thread once it is connected.")))

(defvar *sounds* (make-hash-table :test 'eq)
  "The clips by keyword (the index's name), with their voices. Kept across reloads and
rebuilds, so voices are made once; RELOAD-SOUNDS makes them afresh.")
(defvar *loop-voice-list* ()
  "Every loop's SFX-VOICEs, for SOUND-FRAME.")
(defvar *sound-requests* ()
  "SFX-VOICEs of one-shots asked for and not started yet. The game thread pushes and the
mixing thread pops, both atomically.")
(defvar *sound-error* NIL "The last error in SOUND-FRAME, with its clip if it had one.")
(defvar *sound-clock* 0.0 "Seconds of real time the sound director has ticked.")
(macrolet ((def (name doc)
             `(defvar ,name (make-array 3 :element-type 'single-float :initial-element 0f0) ,doc)))
  (def *listener-location* "Where the listener is: the player's eye, from the game thread.")
  (def *listener-direction* "Which way the listener faces.")
  (def *listener-up* "Which way is up for the listener."))
(defvar *loops-paused* NIL "T while the world is frozen by the game state: loops pause.")

(defun sound-key (name)
  (if (keywordp name) name (intern (string-upcase name) :keyword)))

(defun find-sound (name)
  (gethash name *sounds*))

(defun read-sound-index ()
  (with-open-file (in (data-path "sfx/index.lisp"))
    (with-standard-io-syntax
      (let ((*package* (find-package :hexmaw)))
        (loop for entry = (read in NIL) while entry collect entry)))))

(defun make-sound-voice (sfx file seconds)
  (make-instance 'sfx-voice
                 :sfx sfx :seconds seconds
                 :voice (harmony:create (data-path (format NIL "sfx/~a" file))
                                        :mixer (if (sfx-space-p sfx) :effect :speech)
                                        :repeat (sfx-loop-p sfx)
                                        :on-end :disconnect)))

(defun add-sounds (scene)
  "Make the voices of every clip in the index not made yet, set up the space mixer, and
enter the director."
  (when harmony:*server*
    ;; Whatever held a loop went with the old scene.
    (dolist (voice *loop-voice-list*)
      (setf (voice-held voice) NIL))
    (unless (find-sound :%mixer-set)
      (harmony:with-server (harmony:*server* :synchronize T)
        (let ((mixer (harmony:segment :effect harmony:*server*)))
          (setf (mixed:min-distance mixer) (float *sound-min-distance* 0f0)
                (mixed:max-distance mixer) (float *sound-max-distance* 0f0)
                (mixed:rolloff mixer) (float *sound-rolloff* 0f0)
                (mixed:soundspeed mixer) 343f0
                (mixed:doppler-factor mixer) 0f0)))
      (setf (gethash :%mixer-set *sounds*) T))
    (dolist (entry (read-sound-index))
      (destructuring-bind (&key name files seconds space loop) entry
        (let ((key (sound-key name)))
          (unless (find-sound key)
            (let ((sfx (make-instance 'sfx :name key :files files :seconds seconds
                                           :space space :loop loop)))
              (loop for file in files
                    for s in seconds
                    do (dotimes (i (if loop *loop-voices* *sfx-voices*))
                  (let ((voice (make-sound-voice sfx file s)))
                    (vector-push-extend voice (sfx-voices sfx))
                    (when loop (push voice *loop-voice-list*)))))
              (setf (gethash key *sounds*) sfx))))))
    (enter (make-instance 'sound-director) scene)))

(defun free-voices (voices)
  "Free VOICES in the mixing thread, which may still be playing them."
  (when voices
    (harmony:with-server (harmony:*server* :synchronize T)
      (dolist (voice voices)
        (mixed:free (sfx-voice-voice voice))))))

(defun reload-sound (name)
  "Make clip NAME afresh from data/sfx/index.lisp, as tools/make_sfx.py just wrote it, while
the game runs (tools/sfx_picker.py's swap). Its old voices are freed, cut off if playing; a
loop held then falls silent until its holder starts it again. Run it in the game thread.
Returns the new clip, or NIL if the index no longer has it."
  (let* ((key (sound-key name))
         (old (find-sound key))
         (entry (find key (read-sound-index) :key (lambda (e) (sound-key (getf e :name))))))
    (when old
      (setf (sfx-freed old) T)
      (remhash key *sounds*)
      (setf *loop-voice-list* (set-difference *loop-voice-list* (coerce (sfx-voices old) 'list)))
      (free-voices (coerce (sfx-voices old) 'list)))
    (when entry
      (destructuring-bind (&key name files seconds space loop) entry
        (declare (ignore name))
        (let ((sfx (make-instance 'sfx :name key :files files :seconds seconds :space space :loop loop)))
          (loop for file in files
                for s in seconds
                do (dotimes (i (if loop *loop-voices* *sfx-voices*))
                     (let ((voice (make-sound-voice sfx file s)))
                       (vector-push-extend voice (sfx-voices sfx))
                       (when loop (push voice *loop-voice-list*)))))
          (setf (gethash key *sounds*) sfx))))))

(defvar *auditions* () "Loops AUDITION-SOUND started, with when to stop them.")

(defun audition-sound (name &optional (seconds 2.0))
  "Play clip NAME for the picker: a positional one 3 m in front of the player, a loop there
for SECONDS. Run it in the game thread."
  (let* ((sfx (find-sound (sound-key name)))
         (player *player*)
         (at (if player
                 (let ((yaw (vy (rotation player))) (eye (location player)))
                   (vec (+ (vx eye) (* 3 (sin yaw))) (vy eye) (- (vz eye) (* 3 (cos yaw)))))
                 (vec 0 0 0))))
    (cond ((null sfx) NIL)
          ((sfx-loop-p sfx)
           (let ((voice (start-loop (sfx-name sfx) at)))
             (when voice
               (push (cons voice (+ *sound-clock* seconds)) *auditions*))
             (and voice T)))
          (T (and (play-sound (sfx-name sfx) at) T)))))

(defun end-auditions ()
  (when *auditions*
    (setf *auditions* (delete-if (lambda (a)
                                   (when (<= (cdr a) *sound-clock*)
                                     (stop-loop (car a))
                                     T))
                                 *auditions*))))

(defun reload-sounds ()
  "Free every voice and forget the clips, so the next scene build reads data/sfx/ afresh
(after tools/make_sfx.py). Run it, then tools/hd reset."
  (let ((voices (loop for sfx being the hash-values of *sounds*
                      when (typep sfx 'sfx) append (coerce (sfx-voices sfx) 'list))))
    (clrhash *sounds*)
    (setf *loop-voice-list* () *sound-requests* ())
    (free-voices voices)
    (length voices)))

;;; Playing

(defun copy-into (array vec)
  "VEC into ARRAY as the space mixer counts: its axes are the other hand to the game's (a
sound on the player's left came out on the right), so Z is mirrored."
  (setf (aref array 0) (float (vx vec) 0f0)
        (aref array 1) (float (vy vec) 0f0)
        (aref array 2) (float (- (vz vec)) 0f0))
  array)

(defun take-voice (sfx)
  "A free voice of SFX's next variant, or that variant's that will be done soonest."
  (let* ((files (length (sfx-files sfx)))
         (variant (mod (sfx-turn sfx) files))
         (start (* variant *sfx-voices*))
         (best NIL))
    (setf (sfx-turn sfx) (1+ variant))
    (loop for i from start below (+ start *sfx-voices*)
          for voice = (aref (sfx-voices sfx) i)
          do (when (or (null best) (< (busy-until voice) (busy-until best)))
               (setf best voice)))
    best))

(defun listener-or (at)
  (or at (and *player* (location *player*)) (vec 0 0 0)))

(defun play-sound (name &optional at (volume 1.0))
  "Play the one-shot NAME (a keyword from the index). A positional clip plays at AT, a vec,
or at the listener without one; a first-person clip ignores AT. Does nothing for a clip not
made yet, or without a sound server."
  (let ((sfx (find-sound name)))
    (when (and sfx (not (sfx-loop-p sfx)))
      (let ((voice (take-voice sfx)))
        (copy-into (voice-location voice) (listener-or at))
        (setf (voice-volume voice) (float volume 0f0))
        ;; A voice asked for twice before it starts starts once.
        (unless (< *sound-clock* (- (busy-until voice) (voice-seconds voice)))
          (sb-ext:atomic-push voice (symbol-value '*sound-requests*)))
        (setf (busy-until voice) (+ *sound-clock* (voice-seconds voice) 0.05))
        voice))))

(defun start-loop (name &optional at (volume 1.0))
  "Hold a free voice of the loop NAME, sounding at AT; NIL when none is free. Keep it to move
it (MOVE-LOOP) and to give it back (STOP-LOOP)."
  (let ((sfx (find-sound name)))
    (when (and sfx (sfx-loop-p sfx))
      (let ((voice (find NIL (sfx-voices sfx) :key #'voice-held)))
        (when voice
          (setf (voice-held voice) T
                (voice-volume voice) (float volume 0f0))
          (copy-into (voice-location voice) (listener-or at))
          voice)))))

(defun move-loop (voice at &optional volume)
  "Put a held loop at AT (a vec), and at VOLUME if given. Allocates nothing."
  (when voice
    (copy-into (voice-location voice) at)
    (when volume (setf (voice-volume voice) (float volume 0f0))))
  voice)

(defun stop-loop (voice)
  "Give a held loop back; it falls silent in the next tick. Returns NIL, for the holder's slot."
  (when voice (setf (voice-held voice) NIL))
  NIL)

;;; The mixing thread's side

(defun place-voice (voice)
  (when (sfx-space-p (voice-sfx voice))
    (setf (mixed:location (sfx-voice-voice voice)) (voice-location voice))))

(defun connect-voice (voice)
  (let ((hvoice (sfx-voice-voice voice)))
    (unless (harmony:chain hvoice)
      (mixed:add hvoice (harmony:segment :sources harmony:*server*))
      (harmony:connect hvoice T (harmony:segment (if (sfx-space-p (voice-sfx voice)) :effect :speech)
                                                 harmony:*server*)
                       T))))

(defvar *sound-frame-queued* NIL
  "True while a SOUND-FRAME waits in Harmony's mixing queue.")

(defun sound-frame ()
  "Run in Harmony's mixing thread once a tick (SOUND-DIRECTOR): the listener, the one-shots
asked for, and every loop's state."
  (setf *sound-frame-queued* NIL)
  (handler-case
      (let ((space (harmony:segment :effect harmony:*server*)))
        (setf (mixed:location space) *listener-location*
              (mixed:direction space) *listener-direction*
              (mixed:up space) *listener-up*)
        (loop for voice = (sb-ext:atomic-pop (symbol-value '*sound-requests*))
              while voice
              unless (sfx-freed (voice-sfx voice))
              do (let ((hvoice (sfx-voice-voice voice)))
                   ;; Still playing (all its voices were busy): from the top.
                   (when (harmony:chain hvoice)
                     (mixed:seek hvoice 0))
                   (connect-voice voice)
                   (setf (mixed:volume hvoice) (voice-volume voice))
                   (place-voice voice)))
        (dolist (voice *loop-voice-list*)
          (let ((hvoice (sfx-voice-voice voice))
                (on (and (voice-held voice) (not *loops-paused*))))
            (cond (on
                   (unless (voice-connected voice)
                     (connect-voice voice)
                     (setf (voice-connected voice) T))
                   (setf (mixed:volume hvoice) (voice-volume voice))
                   (place-voice voice)
                   (when (harmony:paused-p hvoice) (setf (harmony:paused-p hvoice) NIL)))
                  ((and (voice-connected voice) (not (harmony:paused-p hvoice)))
                   (setf (harmony:paused-p hvoice) T))))))
    (error (e) (setf *sound-error* e))))

;;; The director

(defclass sound-director (entity listener)
  ((name :initform :sound-director)))

(defun update-listener ()
  "The listener at the player's eye, facing where they look."
  (let ((player *player*))
    (when player
      (let* ((pitch (vx (rotation player)))
             (yaw (vy (rotation player)))
             (flat (cos pitch))
             (direction *listener-direction*))
        (copy-into *listener-location* (location player))
        (setf (aref direction 0) (float (* flat (sin yaw)) 0f0)
              (aref direction 1) (float (- (sin pitch)) 0f0)
              ;; Mirrored, as COPY-INTO mirrors places.
              (aref direction 2) (float (* flat (cos yaw)) 0f0)
              (aref *listener-up* 1) 1f0)))))

(define-handler (sound-director tick) (dt)
  (when harmony:*server*
    (incf *sound-clock* dt)
    (end-auditions)
    (update-listener)
    ;; Loops stop with the world, but not for a hit-stop's blink.
    (setf *loops-paused* (not (eq *game-state* :playing)))
    ;; One waiting frame does all the next would: after a level build Trial runs a burst of
    ;; catch-up ticks, more than the mixing queue's 64 jobs.
    (unless *sound-frame-queued*
      (setf *sound-frame-queued* T)
      (harmony:call-in-mixing-context #'sound-frame harmony:*server* :synchronize NIL))))
