(in-package #:hexmaw)

;;; Heads-up display: health, mana and stamina in the lower-left corner, each a label, a
;;; bar and the numbers, breath above them while it is short, and the frame counter in the upper-left when it's on. HUD elements are ordinary scene entities drawn with a
;;; pixel-space orthographic projection at the near plane, so they stay on top
;;; whatever order the scene draws in. Text uses Trial's built-in 9x17 pixel font.

(defparameter *hud-margin* 16 "Pixels from the window's left and bottom edges.")
(defparameter *hud-bar-width* 180)
(defparameter *hud-bar-height* 12)
(defparameter *hud-row-gap* 6)
(defparameter *hud-text-color* (vec4 0.92 0.88 0.78 1))
(defparameter *health-bar-color* (vec4 0.78 0.14 0.10 1))
(defparameter *mana-bar-color* (vec4 0.22 0.38 0.90 1))
(defparameter *stamina-bar-color* (vec4 0.30 0.68 0.24 1))
(defparameter *breath-bar-color* (vec4 0.62 0.84 0.92 1))
(defparameter *hud-bar-back-color* (vec4 0.06 0.05 0.06 0.8))

(defconstant +glyph-height+ 17)

(define-shader-entity hud-element () ())

(defgeneric hud-shown-p (element)
  (:documentation "Whether ELEMENT draws this frame."))

(defmethod hud-shown-p ((element hud-element))
  ;; No HUD on the main menu; the pause menu dims it instead.
  (not (eq *game-state* :title)))

(defmethod render :around ((element hud-element) (program shader-program))
  (when (hud-shown-p element)
    (with-pushed-matrix ((view-matrix :identity)
                         (projection-matrix :identity))
      ;; Pixel coordinates with the origin at the bottom left; z 0 is the near plane.
      (orthographic-projection 0 (width *context*) 0 (height *context*) 0 10)
      (call-next-method))))

(defun place (entity x y &optional (z 0))
  "Put ENTITY at pixel X, Y. Z below 0 (down to -10) puts it behind elements nearer 0."
  (let ((loc (location entity)))
    (setf (vx loc) (float x 0f0) (vy loc) (float y 0f0) (vz loc) (float z 0f0))))

;;; Bars.

(define-asset (hexmaw hud-quad) mesh
    (make-rectangle-mesh 1 1 :align :bottomleft))

(define-shader-entity hud-bar (hud-element vertex-entity transformed-entity)
  ((vertex-array :initform (// 'hexmaw 'hud-quad))
   (fill-fraction :initform 1.0 :accessor fill-fraction)
   (fill-color :initarg :fill-color :initform (vec4 1 1 1 1) :accessor fill-color)))

(defmethod render :before ((bar hud-bar) (program shader-program))
  (setf (uniform program "fill_fraction") (float (fill-fraction bar) 0f0))
  (setf (uniform program "fill_color") (fill-color bar))
  (setf (uniform program "back_color") *hud-bar-back-color*))

(define-class-shader (hud-bar :vertex-shader)
  "layout (location = TRIAL_V_UV) in vec2 in_uv;
out vec2 bar_uv;

void main(){
  maybe_call_next_method();
  bar_uv = in_uv;
}")

(define-class-shader (hud-bar :fragment-shader)
  "in vec2 bar_uv;
uniform float fill_fraction;
uniform vec4 fill_color;
uniform vec4 back_color;
out vec4 color;

void main(){
  // One screen pixel in UV units, so the frame is 1 px at any bar size.
  vec2 px = fwidth(bar_uv);
  bool border = any(lessThan(bar_uv, px)) || any(greaterThan(bar_uv, 1.0 - px));
  bool filled = bar_uv.x <= fill_fraction;
  color = filled ? fill_color : back_color;
  // A lighter top edge on the filled part, so the bar reads as a solid tube.
  if(filled && 1.0 - 4.0 * px.y < bar_uv.y) color.rgb = min(color.rgb * 1.35, 1.0);
  if(border) color = vec4(0.0, 0.0, 0.0, 1.0);
}")

;;; Text.

(define-shader-entity hud-text (hud-element debug-text) ())

(define-class-shader (hud-text :fragment-shader)
  "out vec4 color;

void main(){
  maybe_call_next_method();
  // Drop the transparent box around the glyphs so it can't cover anything.
  if(color.a < 0.01) discard;
}")

;;; Breath: a bar over the others, only while the player has less than a full breath.

(define-shader-entity breath-element () ())

(defun breath-shown-p ()
  (and *player* (< (breath *player*) *breath-time*)))

(defmethod hud-shown-p ((element breath-element))
  (and (call-next-method) (breath-shown-p)))

(define-shader-entity breath-bar (breath-element hud-bar) ())
(define-shader-entity breath-text (breath-element hud-text) ())

(defun make-hud-text (&optional (text "") (class 'hud-text))
  (make-instance class :text text :font-size (float +glyph-height+ 0f0)
                           :foreground *hud-text-color* :background (vec4 0 0 0 0)))

;;; Frame counter: frames drawn per second, in the upper-left corner, when the
;;; settings menu's Show FPS is on.

(defvar *show-fps* NIL "Show the frame counter. The settings menu (menu.lisp) toggles it.")
(defparameter *fps-interval* 0.5 "Seconds of frames the counter averages over between updates.")

(define-shader-entity fps-display (hud-text)
  ((frames :initform 0 :accessor frames)
   (since :initform 0 :accessor since :documentation "Internal real time the count started.")))

;; On every screen, menus included: what the menus cost to draw is worth seeing too.
(defmethod hud-shown-p ((display fps-display))
  *show-fps*)

(defmethod render :before ((display fps-display) (program shader-program))
  ;; Render runs once a frame (the tick runs at a fixed rate), so count here.
  (let* ((now (get-internal-real-time))
         (elapsed (/ (- now (since display)) (float internal-time-units-per-second))))
    (incf (frames display))
    (when (<= *fps-interval* elapsed)
      ;; A longer gap means the counter was hidden: start over rather than show it.
      (when (< elapsed (* 2 *fps-interval*))
        (setf (text display) (format NIL "~d FPS" (round (frames display) elapsed))))
      (setf (frames display) 0
            (since display) now))))

;;; Pain: the whole view flashes red when the player is hurt.

(defparameter *pain-color* (vec4 0.75 0.0 0.0 0.4) "RGB and peak opacity of the pain flash.")

(define-shader-entity pain-flash (hud-element vertex-entity transformed-entity)
  ((vertex-array :initform (// 'hexmaw 'hud-quad))
   (strength :initform 0.0 :accessor strength :documentation "0 to 1.")))

(defmethod render :around ((flash pain-flash) (program shader-program))
  ;; Writing depth would hide whatever the scene draws after it, such as projectiles.
  (when (< 0 (strength flash))
    (with-depth-mask NIL
      (call-next-method))))

(defmethod render :before ((flash pain-flash) (program shader-program))
  (let ((c *pain-color*))
    (setf (uniform program "pain_color") (vec4 (vx c) (vy c) (vz c) (* (vw c) (strength flash))))))

(define-class-shader (pain-flash :fragment-shader)
  "uniform vec4 pain_color;
out vec4 color;

void main(){
  color = pain_color;
}")

;;; Under water: the whole view, the hands with it, turned blue. The colour multiplies what
;;; is drawn, so the darks stay dark. Drawn after the water's see-through surface (LATE-RANK),
;;; behind the bars like the pain flash.

(defparameter *underwater-tint* (vec 0.45 0.68 1.0) "What the view is multiplied by under water.")

(define-shader-entity underwater-tint (hud-element vertex-entity transformed-entity)
  ((vertex-array :initform (// 'hexmaw 'hud-quad))))

(defmethod hud-shown-p ((tint underwater-tint))
  (and (call-next-method) *eye-underwater* (not (eq *game-state* :map))))

(defmethod late-rank ((tint underwater-tint)) 1)

(defmethod render :around ((tint underwater-tint) (program shader-program))
  (with-depth-mask NIL
    (gl:blend-func :dst-color :zero)
    (unwind-protect (call-next-method)
      (gl:blend-func :src-alpha :one-minus-src-alpha))))

(defmethod render :before ((tint underwater-tint) (program shader-program))
  (setf (uniform program "tint_color") *underwater-tint*))

(define-class-shader (underwater-tint :fragment-shader)
  "uniform vec3 tint_color;
out vec4 color;

void main(){
  color = vec4(tint_color, 1.0);
}")

;;; In a vortex: chunky streaks of wind and dust rush across the view, thickest at its edges
;;; so the middle stays clear to aim through, and go on, thinner, while the player is
;;; thrown. From inside, the funnel alone is too close to read as anything (vortex.lisp).

(defparameter *streak-cell* 5.0 "Screen pixels on a side of a streak's chunky cells.")
(defparameter *streak-ease* 0.4 "Seconds in a vortex until the streaks are at full strength.")
(defparameter *streak-thrown* 0.6 "Their strength while thrown.")

(define-shader-entity whirl-streaks (hud-element vertex-entity transformed-entity listener)
  ((vertex-array :initform (// 'hexmaw 'hud-quad))
   (strength :initform 0.0 :accessor strength :documentation "0 to 1.")
   (clock :initform 0.0 :accessor streak-clock)))

(defmethod hud-shown-p ((streaks whirl-streaks))
  (and (call-next-method) (< 0 (strength streaks)) (not (eq *game-state* :map))))

(defmethod late-rank ((streaks whirl-streaks)) 1)

(define-handler (whirl-streaks tick) (dt)
  (when *player*
    (unless (frozen-p)
      (setf (streak-clock whirl-streaks) (mod (+ (streak-clock whirl-streaks) dt) 1000.0)))
    (setf (strength whirl-streaks)
          (cond ((whirl *player*) (min 1.0 (/ (whirl-time *player*) *streak-ease*)))
                ((flung *player*) *streak-thrown*)
                (T 0.0)))))

(defmethod render :around ((streaks whirl-streaks) (program shader-program))
  (with-depth-mask NIL
    (gl:blend-func :one :one-minus-src-alpha)
    (unwind-protect (call-next-method)
      (gl:blend-func :src-alpha :one-minus-src-alpha))))

(defmethod render :before ((streaks whirl-streaks) (program shader-program))
  (setf (uniform program "strength") (float (strength streaks) 0f0)
        (uniform program "time") (float (streak-clock streaks) 0f0)
        (uniform program "cell_size") (float *streak-cell* 0f0)
        (uniform program "screen") (vec2 (width *context*) (height *context*))))

(define-class-shader (whirl-streaks :fragment-shader)
  "uniform float strength;
uniform float time;
uniform float cell_size;
uniform vec2 screen;
out vec4 color;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void main(){
  vec2 cell = floor(gl_FragCoord.xy / cell_size);
  vec2 at = cell * cell_size / screen - 0.5;
  // A row of the wind, slanting a little; each runs at its own speed, broken into lengths.
  float row = cell.y + floor(cell.x * 0.12);
  float speed = 60.0 + 110.0 * hash(vec2(row, 1.0));
  float x = cell.x + time * speed + 500.0 * hash(vec2(row, 2.0));
  float piece = floor(x / (18.0 + 30.0 * hash(vec2(row, 3.0))));
  float on = step(0.82, hash(vec2(row, piece)));
  float edge = smoothstep(0.18, 0.62, length(at * vec2(1.0, 1.3)));
  float alpha = on * edge * strength * (0.35 + 0.5 * hash(vec2(row, 4.0)));
  vec3 c = mix(vec3(0.35, 0.31, 0.42), vec3(0.72, 0.68, 0.82), hash(vec2(row, 5.0)));
  color = vec4(c * alpha, alpha);
}")

;;; The HUD: owns the elements, keeps them in place and in sync with the player.

(defclass hud (entity listener)
  ((name :initform :hud)
   (health-label :initform (make-hud-text "HP") :reader health-label)
   (health-bar :initform (make-instance 'hud-bar :fill-color *health-bar-color*) :reader health-bar)
   (health-text :initform (make-hud-text) :reader health-text)
   (mana-label :initform (make-hud-text "MP") :reader mana-label)
   (mana-bar :initform (make-instance 'hud-bar :fill-color *mana-bar-color*) :reader mana-bar)
   (mana-text :initform (make-hud-text) :reader mana-text)
   (stamina-label :initform (make-hud-text "SP") :reader stamina-label)
   (stamina-bar :initform (make-instance 'hud-bar :fill-color *stamina-bar-color*) :reader stamina-bar)
   (stamina-text :initform (make-hud-text) :reader stamina-text)
   (breath-label :initform (make-hud-text "AIR" 'breath-text) :reader breath-label)
   (breath-bar :initform (make-instance 'breath-bar :fill-color *breath-bar-color*) :reader breath-bar)
   (pain-flash :initform (make-instance 'pain-flash) :reader pain-flash)
   (underwater-tint :initform (make-instance 'underwater-tint) :reader underwater-tint)
   (whirl-streaks :initform (make-instance 'whirl-streaks) :reader whirl-streaks)
   (fps-display :initform (make-hud-text "" 'fps-display) :reader fps-display)
   (shown-health :initform NIL :accessor shown-health)
   (shown-mana :initform NIL :accessor shown-mana)
   (shown-stamina :initform NIL :accessor shown-stamina)))

(defun hud-elements (hud)
  ;; The flash first, so the bars draw over it.
  (list (pain-flash hud) (underwater-tint hud) (whirl-streaks hud)
        (health-label hud) (health-bar hud) (health-text hud)
        (mana-label hud) (mana-bar hud) (mana-text hud)
        (stamina-label hud) (stamina-bar hud) (stamina-text hud)
        (breath-label hud) (breath-bar hud)
        (fps-display hud)))

(defun add-hud (container)
  (let ((hud (make-instance 'hud)))
    (enter hud container)
    (dolist (element (hud-elements hud) hud)
      (enter element container))))

(defun hud-row-y (row)
  "Pixels from the bottom edge to the bottom of ROW, counted from 0 at the bottom."
  (+ *hud-margin* (* row (+ +glyph-height+ *hud-row-gap*))))

(defun hud-top ()
  "Pixels from the bottom edge to the top of the bars, for what stacks above them."
  (+ (hud-row-y (if (breath-shown-p) 3 2)) +glyph-height+))

(defun layout-hud (hud)
  "Rows from the bottom: stamina, mana, health, then breath. Each row is a label, a bar and the
numbers; breath has none."
  (let* ((margin *hud-margin*)
         (bar-x (+ margin (* 3 9)))
         ;; Whole pixels only: a bar on a half pixel loses an edge row.
         (bar-dy (floor (- +glyph-height+ *hud-bar-height*) 2)))
    (flet ((row (y label bar value)
             (place label margin y)
             (place bar bar-x (+ y bar-dy))
             (setf (vx (scaling bar)) (float *hud-bar-width* 0f0)
                   (vy (scaling bar)) (float *hud-bar-height* 0f0))
             (when value
               (place value (+ bar-x *hud-bar-width* 8) y))))
      (row (hud-row-y 0) (stamina-label hud) (stamina-bar hud) (stamina-text hud))
      (row (hud-row-y 1) (mana-label hud) (mana-bar hud) (mana-text hud))
      (row (hud-row-y 2) (health-label hud) (health-bar hud) (health-text hud))
      (row (hud-row-y 3) (breath-label hud) (breath-bar hud) NIL)))
  (place (fps-display hud) *hud-margin* (- (height *context*) *hud-margin* +glyph-height+))
  ;; Behind every HUD element, in front of the world: anything nearer than -0.5 would
  ;; be within the near plane's 5 cm.
  (dolist (cover (list (pain-flash hud) (underwater-tint hud) (whirl-streaks hud)))
    (place cover 0 0 -0.5)
    (setf (vx (scaling cover)) (float (width *context*) 0f0)
          (vy (scaling cover)) (float (height *context*) 0f0))))

(define-handler (hud tick) ()
  (when *player*
    (let ((hp (max 0 (health *player*)))
          (mp (floor (mana *player*)))
          (sp (floor (stamina *player*))))
      (setf (strength (pain-flash hud)) (/ (pain *player*) *pain-time*)
            (fill-fraction (health-bar hud)) (/ (float hp) *player-max-health*)
            (fill-fraction (mana-bar hud)) (/ (mana *player*) *max-mana*)
            (fill-fraction (stamina-bar hud)) (/ (stamina *player*) *max-stamina*)
            (fill-fraction (breath-bar hud)) (/ (breath *player*) *breath-time*))
      ;; Re-uploading text costs a buffer update, so only when the number changes.
      (unless (eql hp (shown-health hud))
        (setf (shown-health hud) hp
              (text (health-text hud)) (format NIL "~d/~d" hp *player-max-health*)))
      (unless (eql mp (shown-mana hud))
        (setf (shown-mana hud) mp
              (text (mana-text hud)) (format NIL "~d/~d" mp (floor *max-mana*))))
      (unless (eql sp (shown-stamina hud))
        (setf (shown-stamina hud) sp
              (text (stamina-text hud)) (format NIL "~d/~d" sp (floor *max-stamina*))))))
  (layout-hud hud))
