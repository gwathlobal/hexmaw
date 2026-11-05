(in-package #:hexmaw)

(defclass main (org.shirakumo.fraf.trial.harmony:main)
  ()
  (:default-initargs
   :context '(:title "Hexmaw" :width 1280 :height 720)
   ;; Sound is set up below instead.
   :initialize-audio NIL))

(defun start-sound (main)
  "Set up sound, as Trial's Harmony MAIN would (its :INITIALIZE-AUDIO is off). Trial falls back
to a silent output on any failure only when compiled as a release (:trial-release), which
this build isn't: otherwise just on DEVICE-NOT-FOUND. A Windows machine with no sound device
fails otherwise (XAudio2: \"Element not found\"), and the game stopped at start behind an error
box. With no sound, play on silently."
  (handler-case (apply #'org.shirakumo.fraf.trial.harmony:initialize-audio-backend main NIL
                       (org.shirakumo.fraf.trial.harmony:server-initargs main))
    (error (e)
      (v:warn :hexmaw "No sound, playing on without: ~a" e)
      (org.shirakumo.fraf.trial.harmony:initialize-audio-backend main :dummy))))

(defmethod finalize :around ((server harmony:server))
  ;; At quit, when Trial finalizes the sound server last of all: stop its thread, but leave its
  ;; memory to the process's end. Freeing it corrupted libmixed's heap on Windows, after XAudio2
  ;; had failed and the dummy output had taken over, and the game hung instead of quitting.
  (ignore-errors (mixed:end server))
  server)

;; The one :AFTER method MAIN may have: another would replace it.
(defmethod initialize-instance :after ((main main) &key)
  (start-sound main)
  ;; On the main thread, where GLFW wants it: makes Trial's monitor objects of GLFW's. Going
  ;; fullscreen at a monitor's own resolution (APPLY-FULLSCREEN) asks the primary one's video
  ;; mode, which only Trial's class answers; asked of GLFW's, it kills the game.
  (list-monitors (context main))
  (when *fullscreen*
    (apply-fullscreen (context main))))

(defvar *window-icon-set* NIL "Whether this process has given the window its icon.")

(defun set-window-icon ()
  "Give the window data/icon/hexmaw-64.png (tools/make_icon.py) as its icon. Around two bugs
in this Trial and its GLFW binding: (SETF ICON) on a pathname still expects LOAD-IMAGE's old
multiple values, and the binding stores the pixels as C chars, so it fails, in the window
thread, on any byte over 127, while Trial's RGBA-ICON takes only unsigned bytes. So the
pixels go as signed bytes straight onto the window thread's queue, as (SETF ICON) of an
RGBA-ICON would put them. An icon that won't load only logs."
  (handler-case
      (let* ((image (load-image (data-path "icon/hexmaw-64.png") T))
             (bytes (org.shirakumo.fraf.imagine:image-data image))
             (signed (make-array (length bytes) :element-type '(signed-byte 8))))
        (dotimes (i (length bytes))
          (let ((b (aref bytes i))) (setf (aref signed i) (if (< 127 b) (- b 256) b))))
        (org.shirakumo.fraf.trial.glfw::push-event-queue
         (org.shirakumo.fraf.trial.glfw::event-queue *context*) :set-icon
         (list (list signed (org.shirakumo.fraf.imagine:image-w image)
                     (org.shirakumo.fraf.imagine:image-h image)))))
    (error (e) (v:warn :hexmaw "No window icon: ~a" e))))

(defmethod setup-scene ((main main) scene)
  ;; Once a process: the context lives as long as it. Between frames, since the first setup
  ;; runs before the window exists. macOS ignores it (Hexmaw.app has its own).
  (unless *window-icon-set*
    (setf *window-icon-set* T)
    (call-in-render-loop #'set-window-icon scene))
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
      ;; In hand at once, whatever its old slot holds on the new hotbar.
      (setf (wanted-slot new) (wanted-slot old))
      (settle-held new))
    (setf *player* new)
    (enter new scene)
    (when *new-run*
      (setf *new-run* NIL
            *game-state* :playing)
      (reset-player new)
      ;; Come down from the level above (DESCEND): what the player carries comes along.
      (when *carried-state*
        (restore-state new *carried-state*)
        (migrate-bindings new)
        (migrate-enchantments new)
        (settle-held new)
        (setf *carried-state* NIL))
      (when (eq *level* :generated)
        (play-sound :level-gong)
        (setf *level-banner-left* *level-banner-time*)
        (announce-settlement))
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
  (add-settlement-director scene)
  (add-hud scene)
  (add-inventory-view scene)
  (add-status-icons scene)
  (add-hands scene)
  (add-sword scene)
  (add-spear scene)
  (add-shield scene)
  ;; Projectiles and impacts are spawned mid-game; load their shaders and sprites up front.
  (preload-spells scene)
  (preload-status-auras scene)
  ;; And a riftwalker's rifts.
  (preload-riftwalker scene)
  ;; So are raised skeletons.
  (preload (make-instance 'skeleton-warrior) scene)
  ;; And the dust an ogre kicks up.
  (preload (make-instance 'upright-fx :animation (find-fx-animation 'ogre-dust)) scene)
  ;; And the loot imps carry off and drop.
  (preload-pickups scene)
  (enter (make-instance 'menu-controller) scene)
  (add-music scene)
  (add-sounds scene)
  ;; The automap screen (map-view.lisp), after the player: its camera mustn't become the scene's.
  (add-map-view scene)
  ;; The world draws into one pass, at the render scale (settings.lisp), and the menus (Alloy)
  ;; into another. The HUD pass draws at the window's size, so its text stays sharp: the world
  ;; scaled up behind it, the HUD, then the menus over everything. It is what reaches the screen.
  (let ((ui (persistent-menu-ui)))
    (setf *render-pass* (make-instance 'game-pass)
          *hud-pass* (make-instance 'hud-pass)
          *output-pass* *hud-pass*)
    (connect (port *render-pass* 'color) (port *hud-pass* 'world-layer) scene)
    (connect (port ui 'color) (port *hud-pass* 'ui-layer) scene))
  (enter (make-instance 'world-backdrop) scene)
  (enter (make-instance 'menu-overlay) scene)
  ;; A loaded game: the save over the level just built from its seed (save.lisp).
  (when *pending-load*
    (restore-run scene)))

(define-shader-pass layer-pass (render-pass) ()
  (:documentation "A pass of the scene's objects: Trial's, but with what has a LATE-RANK moved, by
rank, to the start of the frame (below 0: the world behind the HUD) or its end (see-through
water, then whole-screen tints, then the menus), else in the order it came."))

(define-shader-pass game-pass (layer-pass)
  ((color :port-type output :attachment :color-attachment0 :reader color
          :texspec (:width (render-size width) :height (render-size height)
                    :min-filter :nearest :mag-filter :nearest))
   (depth :port-type output :attachment :depth-stencil-attachment :reader depth
          :texspec (:width (render-size width) :height (render-size height))))
  (:documentation "The world, at the render scale's share of the window, scaled up without smoothing
behind the HUD (WORLD-BACKDROP). Drawing every pixel is most of a frame's cost on a slow or
software renderer, so a smaller world is the one setting that makes a large difference there."))

(define-shader-pass hud-pass (layer-pass)
  ((world-layer :port-type input)
   (ui-layer :port-type input))
  (:documentation "The window: the world pass's picture (WORLD-BACKDROP), the HUD (HUD-ELEMENT) and
the hands and weapons over it, and the menu pass's over all (MENU-OVERLAY). Drawing the HUD
straight onto the world spares a pass that reads three pictures the window's size back, which
under software OpenGL cost 40 ms a frame at 1280x720."))

(defmethod object-renderable-p ((element hud-element) (pass game-pass)) NIL)
(defmethod object-renderable-p ((object renderable) (pass hud-pass)) NIL)
(defmethod object-renderable-p ((element hud-element) (pass hud-pass)) T)

;; A preloaded class is entered into every pass (Trial builds its program there): only into the
;; one that draws it, or every world shader is built twice.
(defmethod enter :around ((class shader-entity-class) (pass game-pass))
  (unless (subtypep class 'hud-element)
    (call-next-method)))

(defmethod enter :around ((class shader-entity-class) (pass hud-pass))
  (when (subtypep class 'hud-element)
    (call-next-method)))

(defmethod render :before ((pass hud-pass) target)
  ;; It runs after the menu pass, whose renderer sets its own blending.
  (gl:enable :blend)
  (gl:blend-func :src-alpha :one-minus-src-alpha))

;;; A pass's picture drawn over the whole window by the HUD pass, which binds it as LAYER.

;; RENDERABLE: without it the pass draws it without preparing its program for the pass, and
;; the sampler never gets the layer's texture unit.
(define-shader-entity layer-quad (hud-element renderable)
  ((vertex-array :initform (// 'trial 'fullscreen-square) :accessor vertex-array)))

(defmethod stage :after ((quad layer-quad) (area staging-area))
  (stage (vertex-array quad) area))

;; On the map screen too, whose camera draws only what MAP-DRAWN-P allows.
(defmethod map-drawn-p ((quad layer-quad)) T)

(defmethod render ((quad layer-quad) (program shader-program))
  ;; Over everything, and leaving the depth the HUD's elements sort themselves by.
  (with-pushed-features
    (disable-feature :depth-test)
    (with-depth-mask NIL
      (render (vertex-array quad) program))))

(define-class-shader (layer-quad :vertex-shader)
  "layout (location = TRIAL_V_LOCATION) in vec3 position;
layout (location = TRIAL_V_UV) in vec2 in_uv;
out vec2 layer_uv;

void main(){
  gl_Position = vec4(position.xy, 0.0, 1.0);
  layer_uv = in_uv;
}")

(define-shader-entity world-backdrop (layer-quad) ()
  (:documentation "The world pass's picture, the window's background, each of its pixels a square
of the window's (nearest filtering) at a render scale below 1."))

(defmethod hud-shown-p ((backdrop world-backdrop)) T)
(defmethod late-rank ((backdrop world-backdrop)) -1)

(define-class-shader (world-backdrop :fragment-shader)
  "uniform sampler2D world_layer;
in vec2 layer_uv;
out vec4 color;

void main(){
  color = vec4(texture(world_layer, layer_uv).rgb, 1.0);
}")

(define-shader-entity menu-overlay (layer-quad) ()
  (:documentation "The menu pass's picture over everything, while a panel is up. Otherwise the menu
pass doesn't draw at all (MAIN's UPDATE): an empty one still cost a pass the window's size."))

(defmethod hud-shown-p ((overlay menu-overlay))
  (and *menu-ui* (active-p *menu-ui*)))

(defmethod late-rank ((overlay menu-overlay)) 100)

(define-class-shader (menu-overlay :fragment-shader)
  "uniform sampler2D ui_layer;
in vec2 layer_uv;
out vec4 color;

void main(){
  color = texture(ui_layer, layer_uv);
}")

(defvar *late-entries* (make-array 32 :adjustable T :fill-pointer 0)
  "Scratch for LAYER-PASS's SORT-FRAME, kept so a frame allocates nothing.")

(defmethod sort-frame ((pass layer-pass) frame)
  (let ((late *late-entries*) (j 0) (early 0))
    (setf (fill-pointer late) 0)
    ;; A stable partition in place: each entry is a cons (object . program) the frame reuses.
    (loop for i from 0 below (length frame)
          for entry = (aref frame i)
          do (if (late-rank (car entry))
                 (vector-push-extend entry late)
                 (progn (setf (aref frame j) entry) (incf j))))
    ;; The ranked ones by rank: an insertion sort, stable, and they are few.
    (loop for i from 1 below (length late)
          for entry = (aref late i)
          for rank = (late-rank (car entry))
          do (loop for k downfrom (1- i) to 0
                   while (< rank (late-rank (car (aref late k))))
                   do (setf (aref late (1+ k)) (aref late k))
                   finally (setf (aref late (1+ k)) entry)))
    ;; Those below 0 go first: the rest move up to make room for them.
    (loop while (and (< early (length late)) (< (late-rank (car (aref late early))) 0))
          do (incf early))
    (when (< 0 early)
      (loop for k downfrom (1- j) to 0
            do (setf (aref frame (+ k early)) (aref frame k)))
      (loop for k from 0 below early
            do (setf (aref frame k) (aref late k))))
    (loop for k from early below (length late)
          for at from (+ j early)
          do (setf (aref frame at) (aref late k)))
    frame))

;; Trial pools 64 of each input event. Its pool is a counter, not a free list (ACQUIRE-EVENT,
;; event-loop.lisp): the input thread takes the next one while those before it wait in the
;; scene's queue, which only drains in a tick. On a slow frame (software OpenGL) a quick mouse
;; ran past 64, and then the input thread slept up to 10 ms an event and finally overwrote the
;; last one, still queued. A pool the size of a few slow frames' worth of moves avoids that.
;; Handlers still mustn't trust an event's OLD-POS (the player's MOUSE-MOVE says why).
(define-event-pool mouse-move 512)
(define-event-pool mouse-press 128)
(define-event-pool mouse-release 128)

(defparameter *max-ticks-per-frame* 5
  "The most ticks run between two frames. Trial's loop runs as many as the frame took (100 a
second) before it draws, up to 10 s of them, so on a machine too slow to draw a frame in 50 ms
each frame came with more ticks to catch up, which made it slower still: under software OpenGL
(Mesa's llvmpipe on 4 cores) 27 ticks a frame took 80 of every 270 ms. Past this many the rest
are dropped, and the game runs slower than real time instead, as old games did below their
frame rate.")

(defvar *frame-ticks* 0 "Ticks run since the last frame was drawn.")

(defmethod update :around ((main main) tt dt fc)
  (setf *game-thread* (bt:current-thread))
  (when (< *frame-ticks* *max-ticks-per-frame*)
    (incf *frame-ticks*)
    (let ((start (get-internal-real-time)))
      (handler-bind ((error (lambda (e) (guard-runtime-error e :update))))
        (call-next-method))
      (incf (aref *frame-timing* 0) (- (get-internal-real-time) start))
      (incf (aref *frame-timing* 2)))))

(defmethod update :after ((main main) tt dt fc)
  ;; Hit-stop runs out only in play, so a menu opened mid-hit doesn't eat it.
  (when (eq *game-state* :playing)
    (setf *hit-stop* (max 0.0 (- *hit-stop* dt))))
  (advance-light-clock dt)
  ;; Clear to the fog colour so geometry fades into the background; the map has its own.
  (when *render-pass*
    (let ((clear (clear-color *render-pass*))
          (color (if (eq *game-state* :map) *map-background* (fog-color))))
      (setf (vx clear) (vx color) (vy clear) (vy color) (vz clear) (vz color) (vw clear) 1.0)))
  ;; The menu pass draws only while a panel is up: an empty one still cost a whole-window pass
  ;; a frame (25 of 190 ms under software OpenGL). MENU-OVERLAY shows it.
  (when *menu-ui*
    (setf (active-p *menu-ui*) (and (trial-alloy:find-panel 'menu-panel) T))))

(defmethod render :before ((main main) target)
  (incf *render-frame*)
  ;; The nearest lights, for every lit shader this frame (lights.lisp). The map draws nothing lit.
  (unless (eq *game-state* :map)
    (gather-lights)))

(defmethod render :around ((main main) target)
  (setf *frame-ticks* 0)
  (let ((start (get-internal-real-time)))
    (handler-bind ((error (lambda (e) (guard-runtime-error e :render))))
      (call-next-method))
    (incf (aref *frame-timing* 1) (- (get-internal-real-time) start))))

(defun level-status ()
  "Which level the player is on and where it is left by, for STATUS."
  (format NIL "~a~@[; ~a~]"
          (if (eq *level* :generated)
              (format NIL "level ~d of ~d, ~:[no exit~;~:*exit at ~{(~,2f ~,2f ~,2f)~^, ~}~]" *run-depth* (run-length)
                      (loop for (at) across *level-exits*
                            append (list (vx at) (vy at) (vz at))))
              (format NIL "level ~(~a~)" *level*))
          (or (arena-status) (settlement-status))))

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
        (format NIL "running, ~a; ~a; player feet (~,2f ~,2f ~,2f) pitch ~,2f yaw ~,2f grounded ~a~@[ on ~(~a~)~]~:[~; swimming~]~@[ climbing~*~] speed ~,2f hp ~d mana ~d stamina ~,1f~:[~; winded~]~@[ breath ~,1f~] weapon ~(~a~)~@[ casting ~a~] hotbar ~a quickslot ~(~a~) bag ~a; ~
                     creatures ~{~a~^, ~}; ~d runtime error~:p firing now, ~d recorded (tools/hd errors)"
                (case *game-state*
                  (:title "main menu up, world frozen (start with (game (start-game)))")
                  (:paused "paused, world frozen (resume with (game (resume-game)))")
                  (:loading "building a level, world frozen")
                  (:map "map open, world frozen (close with (game (close-map)))")
                  (:inventory "inventory open, world frozen (close with (game (close-inventory)))")
                  (:talk (format NIL "talking to ~a, world frozen (close with (game (end-talk)))" (townsfolk-title *talk-target*)))
                  (:forge "spellforge open, world frozen (close with (game (close-forge)))")
                  (:dead "player dead, world frozen (leave with (game (exit-to-title)))")
                  (:victory "boss slain, run won, world frozen (leave with (game (exit-to-title)))")
                  (T "playing"))
                (level-status)
                (vx feet) (vy feet) (vz feet) (vx rot) (vy rot) (grounded *player*) (footing *player*)
                (swimming *player*) (climbing *player*)
                (let ((v (velocity *player*))) (sqrt (+ (expt (vx v) 2) (expt (vz v) 2))))
                (health *player*) (floor (mana *player*)) (stamina *player*) (winded *player*)
                (and (< (breath *player*) *breath-time*) (breath *player*)) (weapon *player*)
                (and (held-spell *player*) (spell-title (held-spell *player*)))
                (format NIL "[~{~a~^ ~}]" (loop for stack in (hotbar *player*) for i from 1
                                                collect (format NIL "~d:~a~:[~;*~]" i (stack-label stack)
                                                                (eql (1- i) (wanted-slot *player*)))))
                (let ((*print-pretty* NIL)) (princ-to-string (quickslot *player*)))
                (format NIL "(~{~a~^ ~})" (mapcar #'stack-label (remove NIL (inventory *player*))))
                (map 'list (lambda (c)
                             (format NIL "~(~a~)~@[ elite:~(~a~)~] ~:[~d/~d hp ~(~a~)~;dead~*~*~*~] at (~,2f ~,2f)~@[ on ~(~a~)~]"
                                     (type-of c) (and (typep c 'elite) (elite-trait c))
                                     (dead c) (health c) (max-health c) (brain c)
                                     (vx (location c)) (vz (location c)) (footing c)))
                     *creatures*)
                active (length *runtime-errors*)))
      "not running"))

(defun launch (&rest args)
  ;; The player's settings (settings.lisp), before the window and the player exist.
  (load-settings-file)
  (when (eql 1 (env-integer "HEXMAW_FULLSCREEN"))
    (setf *fullscreen* T))
  ;; Trial's default settings are fullscreen at monitor resolution. Override in
  ;; memory only: saving would write ~/.config/shirakumo/trial/settings.lisp,
  ;; which every Trial game shares. The window opens as a window, and goes
  ;; fullscreen at the monitor's own resolution once it is up (MAIN's
  ;; INITIALIZE-INSTANCE), as Settings' checkbox puts it.
  (let ((org.shirakumo.fraf.trial::*save-settings* NIL))
    (setf (setting :display :fullscreen) NIL))
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
