(in-package #:hexmaw)

(defclass main (trial:main)
  ()
  (:default-initargs
   :context '(:title "hexmaw" :width 1280 :height 720)))

(defmethod setup-scene ((main main) scene)
  (build-level scene)
  ;; A scene reload makes a fresh player; carry over where it stood and looked, unless
  ;; the reload starts a new run (START-LEVEL).
  (let ((old *player*)
        (new (make-instance 'player)))
    (when old
      (unless *new-run*
        (v<- (feet new) (feet old))
        (v<- (rotation new) (rotation old))
        (setf (mouse-look new) (mouse-look old)))
      (setf (weapon new) (wanted-weapon old)
            (wanted-weapon new) (wanted-weapon old)))
    (setf *player* new)
    (enter new scene)
    (when *new-run*
      (setf *new-run* NIL
            *game-state* :playing)
      (reset-player new)
      ;; Come down from the level above (DESCEND): what the player carries comes along.
      (when *carried-state*
        (restore-state new *carried-state*)
        (setf *carried-state* NIL))
      (when (eq *level* :generated)
        (setf *level-banner-left* *level-banner-time*))
      (when *boss-fight-start*
        (setf *boss-fight-start* NIL)
        (stand-outside-arena new))
      (capture-mouse new)))
  ;; The arena's gate, outside the block batches so it can move (boss.lisp).
  (add-arena-gate scene)
  ;; A boss's summons are spawned mid-game, and its kind may be nowhere else in the level.
  (let ((boss (and *arena* (arena-boss *arena*))))
    (when boss
      (preload (make-instance (third (boss-kind-entry (boss-kind boss)))) scene)
      ;; And the sigils they rise from.
      (preload (make-instance 'summon-sigil :centre (vec 0 0 0) :animation (find-fx-animation 'summon-sigil)) scene)))
  (add-blood-pool scene)
  (add-hud scene)
  (add-weapon-bar scene)
  (add-inventory-view scene)
  (add-hands scene)
  (add-sword scene)
  (add-spear scene)
  (add-shield scene)
  ;; Projectiles and impacts are spawned mid-game; load their shaders and sprites up front.
  (preload-spells scene)
  ;; And a riftwalker's rifts.
  (preload-riftwalker scene)
  ;; So are raised skeletons.
  (preload (make-instance 'skeleton-warrior) scene)
  ;; And the dust an ogre kicks up.
  (preload (make-instance 'upright-fx :animation (find-fx-animation 'ogre-dust)) scene)
  (enter (make-instance 'menu-controller) scene)
  ;; The automap screen (map-view.lisp), after the player: its camera mustn't become the scene's.
  (add-map-view scene)
  ;; The game draws into one pass and the menus (Alloy) into another; the blend
  ;; puts the menus on top and is what reaches the screen.
  (let ((ui (persistent-menu-ui))
        (blend (make-instance 'blend-pass)))
    (setf *render-pass* (make-instance 'game-pass)
          *output-pass* blend)
    (connect (port *render-pass* 'color) (port blend 'a-pass) scene)
    (connect (port ui 'color) (port blend 'b-pass) scene))
  ;; A loaded game: the save over the level just built from its seed (save.lisp).
  (when *pending-load*
    (restore-run scene)))

(define-shader-pass game-pass (render-pass) ()
  (:documentation "The pass the world draws into: Trial's, but with what has a LATE-RANK (see-through
water, then whole-screen tints) moved to the end of the frame, by rank, else in the order it came."))

(defvar *late-entries* (make-array 32 :adjustable T :fill-pointer 0)
  "Scratch for GAME-PASS's SORT-FRAME, kept so a frame allocates nothing.")

(defmethod sort-frame ((pass game-pass) frame)
  (let ((late *late-entries*) (j 0))
    (setf (fill-pointer late) 0)
    ;; A stable partition in place: each entry is a cons (object . program) the frame reuses.
    (loop for i from 0 below (length frame)
          for entry = (aref frame i)
          do (if (late-rank (car entry))
                 (vector-push-extend entry late)
                 (progn (setf (aref frame j) entry) (incf j))))
    ;; The late ones by rank: an insertion sort, stable, and they are few.
    (loop for i from 1 below (length late)
          for entry = (aref late i)
          for rank = (late-rank (car entry))
          do (loop for k downfrom (1- i) to 0
                   while (< rank (late-rank (car (aref late k))))
                   do (setf (aref late (1+ k)) (aref late k))
                   finally (setf (aref late (1+ k)) entry)))
    (loop for entry across late
          do (setf (aref frame j) entry) (incf j))
    frame))

(defmethod update :around ((main main) tt dt fc)
  (setf *game-thread* (bt:current-thread))
  (handler-bind ((error (lambda (e) (guard-runtime-error e :update))))
    (call-next-method)))

(defmethod update :after ((main main) tt dt fc)
  ;; Hit-stop runs out only in play, so a menu opened mid-hit doesn't eat it.
  (when (eq *game-state* :playing)
    (setf *hit-stop* (max 0.0 (- *hit-stop* dt))))
  (advance-light-clock dt)
  ;; Clear to the fog colour so geometry fades into the background; the map has its own.
  (when *render-pass*
    (let ((clear (clear-color *render-pass*))
          (color (if (eq *game-state* :map) *map-background* (fog-color))))
      (setf (vx clear) (vx color) (vy clear) (vy color) (vz clear) (vz color) (vw clear) 1.0))))

(defmethod render :before ((main main) target)
  (incf *render-frame*)
  ;; The nearest lights, for every lit shader this frame (lights.lisp). The map draws nothing lit.
  (unless (eq *game-state* :map)
    (gather-lights)))

(defmethod render :around ((main main) target)
  (handler-bind ((error (lambda (e) (guard-runtime-error e :render))))
    (call-next-method)))

(defun level-status ()
  "Which level the player is on and where it is left by, for STATUS."
  (format NIL "~a~@[; ~a~]"
          (if (eq *level* :generated)
              (format NIL "level ~d of ~d, ~:[no exit~;~:*exit at ~{(~,2f ~,2f ~,2f)~^, ~}~]" *run-depth* (run-length)
                      (loop for (at) across *level-exits*
                            append (list (vx at) (vy at) (vz at))))
              (format NIL "level ~(~a~)" *level*))
          (arena-status)))

(defun arena-status ()
  "The arena and its boss, for STATUS, or NIL without one."
  (let* ((arena *arena*)
         (boss (and arena (arena-boss arena))))
    (when arena
      (let ((door (connector-location (arena-door arena))))
        (format NIL "arena door at (~,2f ~,2f ~,2f) ~:[open~;sealed~]~@[, boss ~a~]"
                (vx door) (vy door) (vz door) (sealed arena)
                (and boss (format NIL "~(~a~) ~a ~d/~d hp~:[~; dormant~]~:[~; enraged~] powers ~(~{~a~^ ~}~)~@[ using ~(~a~)~]"
                                  (boss-kind boss) (boss-title boss) (max 0 (health boss)) (max-health boss)
                                  (dormant boss) (enraged boss) (boss-powers boss) (boss-power boss))))))))

(defun status ()
  "One-line summary of the running game, for agents and the REPL."
  (if (game-running-p)
      (let* ((feet (feet *player*)) (rot (rotation *player*))
             (now (get-internal-real-time))
             (active (count-if (lambda (e) (< (- now (getf e :last-time)) (* 2 internal-time-units-per-second)))
                               *runtime-errors*)))
        (format NIL "running, ~a; ~a; player feet (~,2f ~,2f ~,2f) pitch ~,2f yaw ~,2f grounded ~a~@[ on ~(~a~)~]~:[~; swimming~]~@[ climbing~*~] speed ~,2f hp ~d mana ~d stamina ~,1f~:[~; winded~]~@[ breath ~,1f~] weapon ~(~a~) quickslot ~(~a~) bag ~(~a~); ~
                     creatures ~{~a~^, ~}; ~d runtime error~:p firing now, ~d recorded (tools/hd errors)"
                (case *game-state*
                  (:title "main menu up, world frozen (start with (game (start-game)))")
                  (:paused "paused, world frozen (resume with (game (resume-game)))")
                  (:loading "building a level, world frozen")
                  (:map "map open, world frozen (close with (game (close-map)))")
                  (:inventory "inventory open, world frozen (close with (game (close-inventory)))")
                  (:dead "player dead, world frozen (leave with (game (exit-to-title)))")
                  (:victory "boss slain, run won, world frozen (leave with (game (exit-to-title)))")
                  (T "playing"))
                (level-status)
                (vx feet) (vy feet) (vz feet) (vx rot) (vy rot) (grounded *player*) (footing *player*)
                (swimming *player*) (climbing *player*)
                (let ((v (velocity *player*))) (sqrt (+ (expt (vx v) 2) (expt (vz v) 2))))
                (health *player*) (floor (mana *player*)) (stamina *player*) (winded *player*)
                (and (< (breath *player*) *breath-time*) (breath *player*)) (weapon *player*)
                (let ((*print-pretty* NIL)) (princ-to-string (quickslot *player*)))
                (let ((*print-pretty* NIL)) (princ-to-string (remove NIL (inventory *player*))))
                (map 'list (lambda (c)
                             (format NIL "~(~a~) ~:[~d/~d hp ~(~a~)~;dead~*~*~*~] at (~,2f ~,2f)~@[ on ~(~a~)~]"
                                     (type-of c) (dead c) (health c) (max-health c) (brain c)
                                     (vx (location c)) (vz (location c)) (footing c)))
                     *creatures*)
                active (length *runtime-errors*)))
      "not running"))

(defparameter *fullscreen* NIL
  "Start fullscreen. HEXMAW_FULLSCREEN=1 turns it on for one run.")

(defun launch (&rest args)
  ;; Trial's default settings are fullscreen at monitor resolution. Override in
  ;; memory only: saving would write ~/.config/shirakumo/trial/settings.lisp,
  ;; which every Trial game shares.
  (let ((org.shirakumo.fraf.trial::*save-settings* NIL))
    (setf (setting :display :fullscreen)
          (or *fullscreen* (eql 1 (env-integer "HEXMAW_FULLSCREEN")))))
  (apply #'trial:launch 'main args))

(defun dev-launch ()
  "Entry point for run.sh: eval server (and Swank if asked), then the game.
Quits the process when the window closes."
  (start-eval-server)
  (setf *game-state* (if (eql 1 (env-integer "HEXMAW_SKIP_MENU")) :playing :title))
  (let ((swank-port (env-integer "HEXMAW_SWANK_PORT")))
    (when swank-port
      (ql:quickload :swank :silent T)
      (uiop:symbol-call :swank :create-server :port swank-port :dont-close T)))
  (unwind-protect (launch)
    (stop-eval-server)
    (uiop:quit 0)))
