(in-package #:hexmaw)

(defclass main (trial:main)
  ()
  (:default-initargs
   :context '(:title "hexmaw" :width 1280 :height 720)))

(defmethod setup-scene ((main main) scene)
  (build-level scene)
  ;; A scene reload makes a fresh player; carry over where it stood and looked.
  (let ((old *player*)
        (new (make-instance 'player)))
    (when old
      (v<- (feet new) (feet old))
      (v<- (rotation new) (rotation old))
      (setf (mouse-look new) (mouse-look old)
            (weapon new) (wanted-weapon old)
            (wanted-weapon new) (wanted-weapon old)))
    (setf *player* new)
    (enter new scene))
  (add-hud scene)
  (add-weapon-bar scene)
  (add-hands scene)
  (add-sword scene)
  ;; Projectiles and impacts are spawned mid-game; load their shaders and sprites up front.
  (preload-spells scene)
  (enter (make-instance 'menu-controller) scene)
  ;; The game draws into one pass and the menus (Alloy) into another; the blend
  ;; puts the menus on top and is what reaches the screen.
  (let ((ui (persistent-menu-ui))
        (blend (make-instance 'blend-pass)))
    (setf *render-pass* (make-instance 'render-pass)
          *output-pass* blend)
    (connect (port *render-pass* 'color) (port blend 'a-pass) scene)
    (connect (port ui 'color) (port blend 'b-pass) scene)))

(defmethod update :around ((main main) tt dt fc)
  (setf *game-thread* (bt:current-thread))
  (handler-bind ((error (lambda (e) (guard-runtime-error e :update))))
    (call-next-method)))

(defmethod update :after ((main main) tt dt fc)
  ;; Hit-stop runs out only in play, so a menu opened mid-hit doesn't eat it.
  (when (eq *game-state* :playing)
    (setf *hit-stop* (max 0.0 (- *hit-stop* dt))))
  ;; Clear to the fog colour so geometry fades into the background.
  (when *render-pass*
    (let ((clear (clear-color *render-pass*)))
      (setf (vx clear) (vx *fog-color*) (vy clear) (vy *fog-color*) (vz clear) (vz *fog-color*) (vw clear) 1.0))))

(defmethod render :around ((main main) target)
  (handler-bind ((error (lambda (e) (guard-runtime-error e :render))))
    (call-next-method)))

(defun status ()
  "One-line summary of the running game, for agents and the REPL."
  (if (game-running-p)
      (let* ((feet (feet *player*)) (rot (rotation *player*))
             (now (get-internal-real-time))
             (active (count-if (lambda (e) (< (- now (getf e :last-time)) (* 2 internal-time-units-per-second)))
                               *runtime-errors*)))
        (format NIL "running, ~a; player feet (~,2f ~,2f ~,2f) pitch ~,2f yaw ~,2f grounded ~a hp ~d mana ~d weapon ~(~a~); ~
                     creatures ~{~a~^, ~}; ~d runtime error~:p firing now, ~d recorded (tools/hd errors)"
                (case *game-state*
                  (:title "main menu up, world frozen (start with (game (start-game)))")
                  (:paused "paused, world frozen (resume with (game (resume-game)))")
                  (T "playing"))
                (vx feet) (vy feet) (vz feet) (vx rot) (vy rot) (grounded *player*)
                (health *player*) (floor (mana *player*)) (weapon *player*)
                (map 'list (lambda (c)
                             (format NIL "~(~a~) ~:[~d/~d hp~;dead~*~*~] at (~,2f ~,2f)"
                                     (type-of c) (dead c) (health c) (max-health c)
                                     (vx (location c)) (vz (location c))))
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
