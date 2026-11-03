(in-package #:hexmaw)

;;; Daggerfall-style spells. A spell is a delivery (how it reaches its target)
;;; plus a list of effects. Each effect has a kind, a magnitude range, a duration,
;;; an area and a target type, and the spell's cost is derived from that
;;; composition, so a spellmaker can later build new spells from the same parts.
;;; What an effect kind does is a method on APPLY-EFFECT.

(defclass effect ()
  ((kind :initarg :kind :reader effect-kind
         :documentation "Keyword naming what the effect does: :DAMAGE, :KNOCKBACK, ...")
   (magnitude :initarg :magnitude :initform '(1 1) :reader effect-magnitude
              :documentation "(MIN MAX); each application rolls an integer in that range.")
   (duration :initarg :duration :initform 0 :reader effect-duration
             :documentation "Seconds; 0 is instant. Not used yet.")
   (area :initarg :area :initform 0 :reader effect-area
         :documentation "Radius in metres; 0 is a single target. A :CIRCLE delivery's reach.")
   (target-type :initarg :target-type :initform :target :reader effect-target-type
                :documentation ":SELF, :TOUCH or :TARGET (whatever the delivery hits).")))

(defclass spell ()
  ((name :initarg :name :reader spell-name)
   (delivery :initarg :delivery :initform :projectile :reader spell-delivery)
   (projectile-speed :initarg :projectile-speed :initform 20.0 :reader projectile-speed)
   (projectile-animation :initarg :projectile-animation :initform NIL :reader projectile-animation
                         :documentation "Effect animation the projectile flies as.")
   (impact-animation :initarg :impact-animation :initform NIL :reader impact-animation
                     :documentation "Effect animation played where the projectile hits, or NIL.")
   (light-color :initarg :light-color :initform *bolt-light-color* :reader light-color
                :documentation "Colour of the glow the projectile and its impact cast.")
   (light-radius :initarg :light-radius :initform *bolt-light-radius* :reader light-radius)
   (homing :initarg :homing :initform NIL :reader spell-homing
           :documentation "Radians a second a creature's projectile turns after the player; NIL flies straight.")
   (pain-bonus :initarg :pain-bonus :initform 0 :reader spell-pain-bonus
               :documentation "Percent its damage adds to a creature's PAIN-CHANCE.")
   (lifetime :initarg :lifetime :initform NIL :reader spell-lifetime
             :documentation "Seconds a projectile that hit nothing flies; NIL for *PROJECTILE-LIFETIME*.")
   (windup :initarg :windup :initform 2.5 :reader spell-windup
           :documentation "Seconds a :CIRCLE delivery glows on the floor before it strikes.")
   (circle-animation :initarg :circle-animation :initform NIL :reader circle-animation
                     :documentation "A :CIRCLE's sign on the floor: frames drawing it in, then a pulsing loop of 4.")

   (strike-animation :initarg :strike-animation :initform NIL :reader strike-animation
                     :documentation "What bursts up out of a :CIRCLE's floor when it strikes, played many times over it.")
   (effects :initarg :effects :reader spell-effects)))

(defvar *spells* (make-hash-table :test 'eq))

(defun find-spell (name)
  (or (gethash name *spells*) (error "No spell named ~s." name)))

(defmacro define-spell (name (&rest options) &body effects)
  "Define spell NAME. OPTIONS are SPELL initargs; each effect is (KIND &rest EFFECT-INITARGS):

  (define-spell bolt (:delivery :projectile :projectile-speed 20.0)
    (:damage :magnitude '(6 10))
    (:knockback :magnitude '(4 4)))"
  `(setf (gethash ',name *spells*)
         (make-instance 'spell :name ',name ,@options
                               :effects (list ,@(loop for (kind . args) in effects
                                                      collect `(make-instance 'effect :kind ,kind ,@args))))))

;;; Cost: each effect's base cost times its average magnitude, scaled up by
;;; duration and area; a spell costs the sum, rounded up.

(defparameter *effect-base-costs* '(:damage 1.5 :knockback 0.5)
  "Mana per point of average magnitude, per effect kind. Unlisted kinds cost 1.")

(defun effect-cost (effect)
  (destructuring-bind (lo hi) (effect-magnitude effect)
    (* (getf *effect-base-costs* (effect-kind effect) 1.0)
       (/ (+ lo hi) 2)
       (+ 1 (/ (effect-duration effect) 5))
       (+ 1 (effect-area effect)))))

(defun spell-cost (spell)
  (ceiling (reduce #'+ (spell-effects spell) :key #'effect-cost)))

(defun roll (magnitude)
  (destructuring-bind (lo hi) magnitude
    (+ lo (random (1+ (- hi lo)) *roll-random*))))

;;; Effects.

(defgeneric apply-effect (kind effect target source)
  (:documentation "Apply EFFECT, whose kind is KIND, to TARGET. SOURCE is what delivered
it (a SPELL-PROJECTILE for projectile spells, a SPELL-CIRCLE for circles)."))

(defmethod apply-effect (kind effect target source)
  (v:warn :hexmaw "No ~s effect for ~a; ignored." kind target))

(defgeneric effect-origin (source)
  (:documentation "The point an effect delivered by SOURCE strikes from, or NIL.")
  (:method (source) NIL))

(defgeneric effect-direction (source target)
  (:documentation "The way an effect delivered by SOURCE pushes TARGET, a vector whose
horizontal part counts."))

(defgeneric effect-unblockable-p (source)
  (:documentation "True if the player's raised shield does nothing against an effect
delivered by SOURCE.")
  (:method (source) NIL))

(defmethod apply-effect ((kind (eql :damage)) effect (target creature) source)
  ;; Blood sprays away from where it struck from.
  (hurt target (roll (effect-magnitude effect)) :from (effect-origin source)
                :pain-bonus (spell-pain-bonus (spell source))))

(defmethod apply-effect ((kind (eql :knockback)) effect (target creature) source)
  (push-creature target (effect-direction source target) (float (roll (effect-magnitude effect)) 0f0)))

(defun apply-spell (spell target source)
  (dolist (effect (spell-effects spell))
    (when (eq :target (effect-target-type effect))
      (apply-effect (effect-kind effect) effect target source))))

;;; Projectile delivery.

(defparameter *projectile-lifetime* 3.0 "Seconds before a projectile that hit nothing vanishes.")
(defparameter *projectile-size* 0.18 "Collision diameter in metres; the sprite can be bigger.")
(defparameter *impact-pullback* 0.25
  "Metres back along the flight path where the impact plays, so it isn't buried in the wall.")

(define-shader-entity spell-projectile (fx-sprite)
  ((spell :initarg :spell :initform NIL :reader spell)
   (caster :initarg :caster :initform NIL :accessor caster
           :documentation "Who fired it (the player or a creature), whom it never hits.")
   (homing :initarg :homing :initform NIL :accessor homing
           :documentation "Radians a second it turns after the player, or NIL; a shield that
turns it aside ends it.")
   (projectile-velocity :initform (vec 0 0 0) :reader projectile-velocity)
   (submerged :initform NIL :accessor submerged
              :documentation "True while it is in a liquid: one cast under water flies on in it,
and bursts only on entering one from outside.")
   (evade-asked :initform NIL :accessor evade-asked
                :documentation "The creature last asked whether it evades this (the player's)
projectile about to reach it, so each is asked once.")))

;; It strikes from behind itself, along its flight, and pushes along it.
(defmethod effect-origin ((source spell-projectile))
  (v- (location source) (projectile-velocity source)))

(defmethod effect-direction ((source spell-projectile) target)
  (projectile-velocity source))

(defun launch-projectile (spell origin direction container caster)
  "Fire SPELL from ORIGIN along unit vector DIRECTION, on behalf of CASTER."
  (let ((projectile (make-instance 'spell-projectile
                                  :spell spell :caster caster :location (vcopy origin)
                                  :homing (spell-homing spell)
                                  :animation (find-fx-animation (projectile-animation spell)))))
    (v<- (projectile-velocity projectile) direction)
    (setf (submerged projectile) (and (liquid-at (vx origin) (vy origin) (vz origin)) T))
    (nv* (projectile-velocity projectile) (float (projectile-speed spell) 0f0))
    (enter projectile container)
    (attach-glow projectile (light-color spell) (light-radius spell))
    projectile))

(defun impact (projectile)
  "Play the spell's impact where PROJECTILE hit, and remove it."
  (let* ((spell (spell projectile))
         (name (impact-animation spell)))
    (when (and name (container projectile))
      (let* ((velocity (projectile-velocity projectile))
             (at (v- (location projectile) (v* velocity (/ *impact-pullback* (max 0.001 (vlength velocity)))))))
        (attach-glow (spawn-fx name at (container projectile)) (light-color spell) (light-radius spell)))))
  (despawn projectile))

;; The player's own projectiles never hit them, nor a creature's that creature.
(defun projectile-victim (projectile point margin)
  "The body PROJECTILE hits at POINT, MARGIN metres around it: a live creature or the player."
  (let ((caster (caster projectile)))
    (or (creature-at point margin caster)
        (and *player* (not (eq caster *player*)) (player-at-p *player* point margin)
             *player*))))

;;; Shields. A spell striking a shield from the front (SHIELDED-P, creature.lisp: the
;;; views of the sprite its shield covers) does nothing to the bearer. A shield that
;;; reflects sends it back the way it came, mirrored off the shield's face, as the
;;; bearer's own; one that doesn't, stops it.

(defgeneric deflects-p (target projectile)
  (:documentation "True if TARGET turns PROJECTILE aside instead of taking its effects.")
  (:method (target projectile) NIL))

(defmethod deflects-p ((target creature) (projectile spell-projectile))
  (shielded-p target (v- (location target) (projectile-velocity projectile))))

(defun deflect (target projectile)
  "TARGET's shield takes PROJECTILE: reflect it, or stop it if the shield doesn't reflect."
  (block-hit target)
  (cond ((shield-reflects target)
         ;; Mirror the flight off the shield's face, whose normal is the way TARGET faces,
         ;; and send it back up or down too: straight on, it returns to its caster.
         (let* ((v (projectile-velocity projectile))
                (nx (sin (facing target)))
                (nz (- (cos (facing target))))
                (d (+ (* (vx v) nx) (* (vz v) nz))))
           (setf (vx v) (- (vx v) (* 2 d nx))
                 (vz v) (- (vz v) (* 2 d nz))
                 (vy v) (- (vy v))))
         (setf (caster projectile) target
               (homing projectile) NIL
               (age projectile) 0.0))
        (T
         (impact projectile))))

(defun steer (projectile dt)
  "Turn PROJECTILE's flight toward the player's chest by at most its HOMING rate for DT
seconds, keeping its speed."
  (let* ((v (projectile-velocity projectile))
         (loc (location projectile))
         (feet (feet *player*))
         (tx (- (vx feet) (vx loc)))
         (ty (- (+ (vy feet) *cast-aim-height*) (vy loc)))
         (tz (- (vz feet) (vz loc)))
         (tl (sqrt (+ (* tx tx) (* ty ty) (* tz tz))))
         (speed (vlength v)))
    (when (and (< 1f-3 tl) (< 1f-3 speed))
      (let* ((ux (/ (vx v) speed)) (uy (/ (vy v) speed)) (uz (/ (vz v) speed))
             (dx (/ tx tl)) (dy (/ ty tl)) (dz (/ tz tl))
             (cos-a (max -1f0 (min 1f0 (+ (* ux dx) (* uy dy) (* uz dz)))))
             (step (* (homing projectile) dt)))
        (if (<= (acos cos-a) step)
            (setf (vx v) (* speed dx) (vy v) (* speed dy) (vz v) (* speed dz))
            ;; Rotate toward the target in the plane of the flight and the target: W is the
            ;; part of the way to the target square to the flight.
            (let* ((wx (- dx (* cos-a ux))) (wy (- dy (* cos-a uy))) (wz (- dz (* cos-a uz)))
                   (wl (sqrt (+ (* wx wx) (* wy wy) (* wz wz)))))
              (when (< 1f-5 wl)
                (let ((c (cos step)) (s (/ (sin step) wl)))
                  (setf (vx v) (* speed (+ (* c ux) (* s wx)))
                        (vy v) (* speed (+ (* c uy) (* s wy)))
                        (vz v) (* speed (+ (* c uz) (* s wz))))))))))))

(defparameter *evade-look-ahead* 0.2
  "Seconds of flight ahead of the player's projectile that a creature sees it coming (EVADE-PROJECTILE).")

(defgeneric evade-projectile (creature projectile)
  (:documentation "Give CREATURE, which the player's PROJECTILE is about to reach, its chance
to get out of the way (the riftwalker's blink, riftwalker.lisp). Asked once per projectile.")
  (:method (creature projectile) NIL))

(defvar *evade-probe* (vec 0 0 0))

(defun look-ahead (projectile r)
  "Ask the creature the player's PROJECTILE will reach within *EVADE-LOOK-AHEAD* whether it evades it."
  (let ((probe *evade-probe*)
        (loc (location projectile))
        (v (projectile-velocity projectile))
        (k (float *evade-look-ahead* 0f0)))
    (setf (vx probe) (+ (vx loc) (* k (vx v)))
          (vy probe) (+ (vy loc) (* k (vy v)))
          (vz probe) (+ (vz loc) (* k (vz v))))
    (let ((c (creature-at probe r *player*)))
      (when (and c (not (eq c (evade-asked projectile))))
        (setf (evade-asked projectile) c)
        (evade-projectile c projectile)))))

;; After FX-SPRITE's tick, which animates and ages it.
(define-handler (spell-projectile tick :after) (dt)
  (unless (frozen-p)
    (let* ((loc (location spell-projectile))
           (r (* 0.5 (float *projectile-size* 0f0))))
      (when (and (homing spell-projectile) *player* (not (eq (caster spell-projectile) *player*)))
        (steer spell-projectile (float dt 0f0)))
      (when (and *player* (eq (caster spell-projectile) *player*))
        (look-ahead spell-projectile r))
      (nv+* loc (projectile-velocity spell-projectile) dt)
      (let ((victim (projectile-victim spell-projectile loc r))
            (entered (and (liquid-at (vx loc) (vy loc) (vz loc)) (not (submerged spell-projectile)))))
        (setf (submerged spell-projectile) (and (liquid-at (vx loc) (vy loc) (vz loc)) T))
        (cond ((and victim (deflects-p victim spell-projectile))
               (deflect victim spell-projectile))
              (victim
               (apply-spell (spell spell-projectile) victim spell-projectile)
               (impact spell-projectile))
              ((or (solid-overlapping (vx loc) (- (vy loc) r) (vz loc) r (* 2 r)) entered)
               (impact spell-projectile))
              ((< (or (spell-lifetime (spell spell-projectile)) *projectile-lifetime*) (age spell-projectile))
               (despawn spell-projectile)))))))

;;; Circle delivery: a sign glows on the floor around a point for the spell's WINDUP,
;;; an aurora rising round it and a lamp brightening over it, so it shows from
;;; anywhere in the room; then it strikes everything living that stands in it, once
;;; (the effects' AREA is its radius), and its STRIKE-ANIMATION bursts up all over it.
;;; Once cast it goes on by itself: hitting or killing its caster doesn't stop it. Nor
;;; does it spare the caster's allies, only the caster and the undead.

(defparameter *aurora-height* '(0.3 3.2) "Metres a circle's aurora rises from and to as it winds up.")
(defparameter *aurora-segments* 128 "Quads round an aurora's ring. Read when the ring is made (a restart).")
(defparameter *circle-draw-in* 0.45 "Fraction of the wind-up a circle's sign takes to draw itself.")
(defparameter *circle-pulse-fps* 8.0)
(defparameter *circle-light-color* (vec 0.5 2.2 0.6) "Its lamp's colour at full strength, just before it strikes.")
(defparameter *circle-light-radius* 7.0)
(defparameter *circle-flash* 2.0 "How much brighter the lamp flashes as the circle strikes.")
(defparameter *circle-linger* 0.8 "Seconds the sign and its light fade after the strike.")
(defparameter *circle-reach-height* 1.0 "Metres above or below the sign that feet can be to be struck.")
(defparameter *strike-rings* '((0.0 1) (0.5 4) (0.9 6))
  "Where the strike bursts up: (FRACTION-OF-RADIUS COUNT) rings, from the middle out.")
(defparameter *strike-ring-delay* 0.06 "Seconds between one ring of the strike and the next.")
(defparameter *harvest-blood* 30 "Drops the strike wrenches up out of each living thing it hits.")

(define-shader-entity upright-fx (fx-sprite) ()
  (:documentation "An effect sprite turned only about +Y, standing upright as a billboard does."))

(define-handler (upright-fx tick :after) ()
  (let ((camera (camera (scene +main+))))
    (when (typep camera 'fps-camera)
      (!qfrom-angle (orientation upright-fx) +vy+ (- (vy (rotation camera)))))))

(defun spawn-standing-fx (name x y z container &key (class 'upright-fx))
  "Play effect animation NAME once, upright, standing on the floor at X Y Z."
  (let* ((animation (find-fx-animation name))
         (sprite (make-instance class :animation animation
                                      :location (vec x (+ y (* 0.5 (animation-size animation))) z))))
    (enter sprite container)
    sprite))

;;; The aurora: a curtain of light standing on a circle's rim like the northern lights:
;;; soft vertical streaks of many heights, drifting and shimmering along it, a bright band
;;; along its foot, its colour wandering through the necromancer's greens round the ring
;;; and deepening toward the top. It is a ring of quads whose vertices are
;;; an angle round the ring and a height up it; the shader sways the upper part (the foot
;;; stays on the rim) and adds its light over what is behind it, writing no depth, so it
;;; needs no sorting against other glows. COLORS gives it another caster's look, and
;;; SPIN and TWIST make its streaks a wind's, running round it and leaning.

(defparameter *grave-aurora-colors*
  (list (vec 0.1 1.0 0.35) (vec 0.5 1.0 0.15) (vec 0.15 0.95 0.65) (vec 0.05 0.55 0.25) (vec 0.8 1.0 0.7))
  "An aurora's colours: the three its foot wanders through round the ring, its top, its band.")

(define-shader-entity aurora (renderable listener)
  ((centre :initarg :centre :reader centre)
   (radius :initarg :radius :reader aurora-radius)
   (colors :initarg :colors :initform *grave-aurora-colors* :reader aurora-colors)
   (spin :initarg :spin :initform 0.0 :reader aurora-spin :documentation "Turns a second its streaks run round the ring.")
   (twist :initarg :twist :initform 0.0 :reader aurora-twist :documentation "Whole turns its streaks lean, foot to top.")
   (arc :initarg :arc :initform pi :accessor aurora-arc
        :documentation "Radians either side of ARC-MIDDLE it stands on: pi for the whole ring, less for an arc.")
   (arc-middle :initarg :arc-middle :initform pi :accessor aurora-arc-middle
               :documentation "Angle round the ring, from +X toward +Z, of its arc's middle.")
   (height :initform (first *aurora-height*) :accessor aurora-height)
   (strength :initform 0.0 :accessor aurora-strength :documentation "0 (none) to 1 (full).")
   (clock :initform (random 100.0) :accessor aurora-clock)))

(defvar *aurora-vao* NIL
  "The ring every aurora draws, shared: one made mid-game would never be loaded onto the
GPU. PRELOAD-SPELLS stages it with the scene.")

(defun aurora-vao ()
  (or *aurora-vao*
      (let* ((n *aurora-segments*)
             (data (make-array (* n 12) :element-type 'single-float))
             (k 0))
        ;; Two triangles a segment, each vertex (fraction of the way round, fraction up).
        (dotimes (i n)
          (let ((a0 (float (/ i n) 0f0)) (a1 (float (/ (1+ i) n) 0f0)))
            (loop for v in (list a0 0f0 a1 0f0 a1 1f0 a0 0f0 a1 1f0 a0 1f0)
                  do (setf (aref data k) v) (incf k))))
        (setf *aurora-vao*
              (make-instance 'vertex-array
                             :vertex-form :triangles
                             :bindings `((,(make-instance 'vertex-buffer :buffer-data data) :size 2 :offset 0 :stride 8 :index 0))
                             :size (* n 6))))))

(defmethod stage :after ((aurora aurora) (area staging-area))
  (stage (aurora-vao) area))

(define-handler (aurora tick) (dt)
  (unless (frozen-p)
    (incf (aurora-clock aurora) dt)))

(defmethod render ((aurora aurora) (program shader-program))
  (when (< 0 (aurora-strength aurora))
    (setf (uniform program "view_matrix") (view-matrix)
          (uniform program "projection_matrix") (projection-matrix)
          (uniform program "centre") (centre aurora)
          (uniform program "radius") (float (aurora-radius aurora) 0f0)
          (uniform program "height") (float (aurora-height aurora) 0f0)
          (uniform program "strength") (float (aurora-strength aurora) 0f0)
          (uniform program "spin") (float (aurora-spin aurora) 0f0)
          (uniform program "twist") (float (aurora-twist aurora) 0f0)
          (uniform program "arc") (float (aurora-arc aurora) 0f0)
          (uniform program "arc_middle") (float (aurora-arc-middle aurora) 0f0)
          (uniform program "time") (float (aurora-clock aurora) 0f0))
    (destructuring-bind (foot-1 foot-2 foot-3 top band) (aurora-colors aurora)
      (setf (uniform program "foot_1") foot-1
            (uniform program "foot_2") foot-2
            (uniform program "foot_3") foot-3
            (uniform program "top_color") top
            (uniform program "band_color") band))
    ;; Light added over what is behind it, seen from outside the ring and from inside.
    (gl:disable :cull-face)
    (gl:depth-mask NIL)
    (gl:blend-func :one :one)
    (render-array (aurora-vao))
    (gl:blend-func :src-alpha :one-minus-src-alpha)
    (gl:depth-mask T)
    (gl:enable :cull-face)))

(define-class-shader (aurora :vertex-shader)
  "layout (location = 0) in vec2 in_ah;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;
uniform vec3 centre;
uniform float radius;
uniform float height;
uniform float time;
uniform float arc;
uniform float arc_middle;
out vec2 v_ah;

void main(){
  // The ring's segments spread over its arc: the whole ring when ARC is pi.
  float a = arc_middle + (in_ah.x - 0.5) * 2.0 * arc;
  // Folds that drift round the ring and sway, growing toward the top: the foot stays
  // on the circle's rim.
  float lean = in_ah.y * in_ah.y;
  float fold = 0.08 * sin(5.0 * a + time * 0.9) + 0.04 * sin(12.0 * a - time * 1.6)
             + 0.08 * sin(3.0 * a + time * 0.7);
  float r = radius * (1.0 + lean * fold);
  vec3 p = centre + vec3(cos(a) * r, in_ah.y * height, sin(a) * r);
  gl_Position = projection_matrix * (view_matrix * vec4(p, 1.0));
  v_ah = in_ah;
}")

(define-class-shader (aurora :fragment-shader)
  "in vec2 v_ah;
uniform float strength;
uniform float spin;
uniform float twist;
uniform float time;
uniform float arc;
uniform vec3 foot_1;
uniform vec3 foot_2;
uniform vec3 foot_3;
uniform vec3 top_color;
uniform vec3 band_color;
out vec4 color;

float hash(float n){ return fract(sin(n * 127.1) * 43758.5453); }

// Smooth noise along the ring, repeating every PERIOD cells, so it meets itself.
float ring_noise(float x, float period){
  float i = floor(x);
  float f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(hash(mod(i, period)), hash(mod(i + 1.0, period)), f);
}

void main(){
  float y = v_ah.y;
  float u = v_ah.x + fract(spin * time) + twist * y;
  // Streaks: a broad set and a fine one, sharpened into separate rays, drifting.
  float broad = ring_noise(u * 70.0 + time * 0.8, 70.0);
  float fine = ring_noise(u * 190.0 - time * 1.9, 190.0);
  float streak = 0.75 * pow(broad, 2.5) + 0.6 * pow(fine, 4.0);
  // Each ray has its own height, the tallest the whole curtain, and they rise and fall.
  float top = 0.25 + 0.75 * ring_noise(u * 40.0 + 7.0 + time * 0.35, 40.0);
  float rise = smoothstep(0.0, 0.03, y) * (1.0 - smoothstep(top * 0.3, top, y));
  // The glowing band along its foot.
  float band = exp(-y * 14.0) * (0.45 + 0.55 * broad);
  float light = (streak * rise + 0.7 * band) * strength;
  // An arc fades out toward its ends; a whole ring meets itself.
  if(arc < 3.14) light *= smoothstep(0.0, 0.12, min(v_ah.x, 1.0 - v_ah.x));
  // Its colour wanders round the ring through its three foot colours (the necromancer's
  // greens: emerald, acid and sea-green) and deepens toward the top.
  float hue = ring_noise(u * 5.0 + time * 0.12, 5.0) * 2.0;
  vec3 low = hue < 1.0 ? mix(foot_1, foot_2, hue) : mix(foot_2, foot_3, hue - 1.0);
  vec3 c = mix(low, top_color, smoothstep(0.25, 0.95, y / max(top, 0.3)));
  c = mix(c, band_color, band * 0.6);
  color = vec4(c * light * 1.3, 1.0);
}")

(define-shader-entity spell-circle (fx-sprite)
  ((spell :initarg :spell :reader spell)
   (caster :initarg :caster :initform NIL :reader caster)
   (centre :initarg :centre :reader centre :documentation "The point on the floor it is drawn round.")
   (aurora :initform NIL :accessor circle-aurora)
   (lamp :initform NIL :accessor circle-lamp)
   (struck :initform NIL :accessor struck :documentation "Seconds since it struck, or NIL.")
   (rings-left :initform () :accessor rings-left :documentation "Rings of the strike yet to burst.")))

(defun circle-radius (spell)
  (reduce #'max (spell-effects spell) :key #'effect-area :initial-value 0))

(defmethod initialize-instance :after ((circle spell-circle) &key)
  ;; Flat on the floor, facing up, just off it. Drawn for a radius of the strip's
  ;; :RADIUS metres (tools/draw_grave_circle.py), scaled to the spell's.
  (let* ((atlas (animation-atlas (sprite-animation circle)))
         (k (/ (circle-radius (spell circle)) (getf atlas :radius 2.5))))
    (nv* (scaling circle) (float k 0f0)))
  (!qfrom-angle (orientation circle) +vx+ #.(float (- (/ pi 2)) 0f0))
  (incf (vy (location circle)) 0.01))

(defmethod effect-origin ((source spell-circle)) (centre source))

(defmethod effect-direction ((source spell-circle) target)
  (v- (if (typep target 'creature) (location target) (feet target)) (centre source)))

;; It comes up from the floor, under any shield.
(defmethod effect-unblockable-p ((source spell-circle)) T)

(defun circle-strength (circle)
  "How bright CIRCLE's light is: rising through the wind-up, a flash as it strikes,
then fading."
  (let ((struck (struck circle)))
    (if struck
        (* (+ 1 *circle-flash*) (max 0.0 (- 1 (/ struck *circle-linger*))))
        (expt (min 1.0 (/ (age circle) (spell-windup (spell circle)))) 1.5))))

(defun light-circle (circle)
  "Raise CIRCLE's aurora and lamp, the first time it ticks in the scene."
  (let ((c (centre circle)))
    (setf (circle-aurora circle) (make-instance 'aurora :centre c :radius (circle-radius (spell circle))))
    (enter (circle-aurora circle) (container circle))
    (setf (circle-lamp circle)
          (add-lamp (vec (vx c) (+ (vy c) 0.8) (vz c)) *circle-light-color* *circle-light-radius*
                    :flicker 0.15))))

(defun drop-aurora (circle)
  (when (circle-aurora circle)
    (despawn (circle-aurora circle))
    (setf (circle-aurora circle) NIL)))

(defun drop-circle-light (circle)
  (drop-aurora circle)
  (when (circle-lamp circle)
    (remove-lamp (circle-lamp circle))
    (setf (circle-lamp circle) NIL)))

;; A reset or rebuild takes the circle away before it is done.
(defmethod leave :after ((circle spell-circle) container)
  (drop-circle-light circle))

(defun in-circle-p (circle point radius)
  "True if feet at POINT, of a body RADIUS wide, stand in CIRCLE."
  (let* ((c (centre circle))
         (r (+ (circle-radius (spell circle)) (* 0.5 radius)))
         (dx (- (vx point) (vx c)))
         (dz (- (vz point) (vz c))))
    (and (< (+ (* dx dx) (* dz dz)) (* r r))
         (< (abs (- (vy point) (vy c))) *circle-reach-height*))))

(defun harvest (at height)
  "Wrench blood straight up out of something struck, standing at AT, HEIGHT tall."
  (spray-blood (vec (vx at) (+ (vy at) (* 0.5 height)) (vz at)) 0.0 0.0 *harvest-blood*
               :speed '(0.3 1.5) :rise '(1.2 1.5) :lift 5.0))

(defun strike-circle (circle)
  "CIRCLE strikes: everything living in it takes the spell, and the strike's first ring bursts up."
  (let ((spell (spell circle))
        (caster (caster circle)))
    (setf (struck circle) 0.0
          (rings-left circle) *strike-rings*)
    (drop-aurora circle)
    (loop for c across *creatures*
          when (and (not (dead c)) (not (undead c)) (not (eq c caster))
                    (in-circle-p circle (location c) (body-radius c)))
            do (when (bleeds c) (harvest (location c) (sprite-height c)))
               (apply-spell spell c circle))
    (when (and *player* (< 0 (health *player*)) (in-circle-p circle (feet *player*) *player-radius*))
      (harvest (feet *player*) *player-height*)
      (apply-spell spell *player* circle))))

(defun burst-ring (circle ring)
  (destructuring-bind (fraction count) ring
    (let* ((c (centre circle))
           (r (* fraction (circle-radius (spell circle))))
           (turn (random (float (* 2 pi) 0f0))))
      (dotimes (k count)
        (let* ((a (+ turn (* k (/ (* 2 pi) count))))
               ;; A little scatter, so the rings don't look drawn with a compass.
               (rr (+ r (if (< 0 r) (- (random 0.3) 0.15) 0.0))))
          (spawn-standing-fx (strike-animation (spell circle)) (+ (vx c) (* rr (cos a))) (vy c)
                             (+ (vz c) (* rr (sin a))) (container circle)))))))

(defun sign-frame (age windup count)
  "The frame of a strip of COUNT, frames drawing a sign in and then a pulsing loop of 4, to
show AGE seconds into a wind-up of WINDUP."
  (let ((draw-in (- count 4))
        (progress (/ age (* *circle-draw-in* windup))))
    (if (< progress 1)
        (min (1- draw-in) (floor (* progress draw-in)))
        (+ draw-in (mod (floor (* age *circle-pulse-fps*)) 4)))))

;; Its own tick, not FX-SPRITE's: the frame follows the wind-up, and it lies flat.
(define-handler (spell-circle tick) (dt)
  (let* ((spell (spell spell-circle))
         (windup (spell-windup spell))
         (atlas (animation-atlas (sprite-animation spell-circle)))
         (count (getf atlas :frames)))
    (when (and (null (circle-lamp spell-circle)) (null (struck spell-circle)) (container spell-circle))
      (light-circle spell-circle))
    (unless (frozen-p)
      (incf (age spell-circle) dt)
      (let ((struck (struck spell-circle)))
        (cond (struck
               (setf struck (+ struck dt)
                     (struck spell-circle) struck)
               (let ((ring (first (rings-left spell-circle))))
                 (when (and ring (<= (* *strike-ring-delay* (- (length *strike-rings*) (length (rings-left spell-circle))))
                                     struck))
                   (burst-ring spell-circle ring)
                   (pop (rings-left spell-circle))))
               (when (< *circle-linger* struck)
                 (despawn spell-circle)))
              ((<= windup (age spell-circle))
               (strike-circle spell-circle)
               (burst-ring spell-circle (pop (rings-left spell-circle)))))))
    ;; The sign draws itself in, then pulses.
    (strip-uv (frame-uv spell-circle) atlas (sign-frame (age spell-circle) windup count) count)
    ;; The aurora rises and brightens, and so does the lamp.
    (let ((k (circle-strength spell-circle))
          (lamp (circle-lamp spell-circle))
          (aurora (circle-aurora spell-circle)))
      (when aurora
        (raise-aurora aurora (age spell-circle) windup k))
      (when lamp
        (let ((color (color lamp)))
          (setf (vx color) (* k (vx *circle-light-color*))
                (vy color) (* k (vy *circle-light-color*))
                (vz color) (* k (vz *circle-light-color*))))))))

(defun raise-aurora (aurora age windup k)
  "Bring AURORA up, AGE seconds into a wind-up of WINDUP, as bright as a lamp at K of its full."
  (destructuring-bind (low high) *aurora-height*
    (setf (aurora-height aurora) (+ low (* (- high low) (min 1.0 (/ age (* 0.8 windup)))))
          (aurora-strength aurora) (min 1.0 (* 1.6 k)))))

(defun place-circle (spell centre container caster)
  "Draw SPELL's circle on the floor round point CENTRE for CASTER."
  (let ((circle (make-instance 'spell-circle :spell spell :caster caster :centre (vcopy centre)
                                             :location (vcopy centre)
                                             :animation (find-fx-animation (circle-animation spell)))))
    (enter circle container)
    circle))

(defun cast-spell (spell origin direction container &key caster)
  "Deliver SPELL from ORIGIN along unit vector DIRECTION for CASTER, the player or a
creature; a :CIRCLE is drawn round ORIGIN, on the floor, and DIRECTION doesn't count.
Mana is the caster's business."
  (ecase (spell-delivery spell)
    (:projectile (launch-projectile spell origin direction container caster))
    (:circle (place-circle spell origin container caster))
    (:vortex (place-vortex spell origin direction container caster))))

;;; The spells.

(defun preload-spells (scene)
  "Load the sprites of every spell, which only appear mid-game."
  (loop for spell being the hash-values of *spells*
        do (when (eq (spell-delivery spell) :vortex)
             (preload-vortex spell scene))
           (dolist (name (list (projectile-animation spell) (impact-animation spell)))
             (when name
               (preload (make-instance 'fx-sprite :animation (find-fx-animation name)) scene)))
           (when (strike-animation spell)
             (preload (make-instance 'upright-fx :animation (find-fx-animation (strike-animation spell))) scene))
           (when (projectile-animation spell)
             (preload (make-instance 'spell-projectile :spell spell
                                                       :animation (find-fx-animation (projectile-animation spell)))
                      scene))
           (when (circle-animation spell)
             (preload (make-instance 'spell-circle :spell spell :centre (vec 0 0 0)
                                                   :animation (find-fx-animation (circle-animation spell)))
                      scene)
             (preload (make-instance 'aurora :centre (vec 0 0 0) :radius 1.0) scene))))

(define-fx-animation bolt-flight "sprites/bolt/flight" :fps 12 :loop T :size 0.4)
(define-fx-animation bolt-burst "sprites/bolt/burst" :fps 14 :size 0.9)

(define-spell bolt (:delivery :projectile :projectile-speed 20.0 :pain-bonus 10
                    :projectile-animation 'bolt-flight :impact-animation 'bolt-burst)
  (:damage :magnitude '(6 10))
  (:knockback :magnitude '(4 4)))

;; The acolyte's spell (creature.lisp): slower than the bolt, so a sidestep dodges it.
;; It flies on the bolt's frames, bigger and redder, until it has its own.
(define-fx-animation cinder-flight "sprites/bolt/flight" :fps 9 :loop T :size 0.55)

(define-spell cinder (:delivery :projectile :projectile-speed 9.0
                      :projectile-animation 'cinder-flight :impact-animation 'bolt-burst
                      :light-color (vec 1.8 0.35 0.12) :light-radius 4.5)
  (:damage :magnitude '(5 8)))

;; The necromancer's spells (creature.lisp). The grave skull flies slowly and curves
;; after the player, but turns slower than a late sidestep.
(define-fx-animation grave-skull-flight "sprites/grave/flight" :fps 10 :loop T :size 0.5)
(define-fx-animation grave-skull-burst "sprites/grave/burst" :fps 14 :size 1.0)

(define-spell grave-skull (:delivery :projectile :projectile-speed 6.0 :homing 1.0 :lifetime 5.0
                           :projectile-animation 'grave-skull-flight :impact-animation 'grave-skull-burst
                           :light-color (vec 0.4 1.8 0.5) :light-radius 4.0)
  (:damage :magnitude '(6 9)))

;; The grave circle: a pentagram drawn for a 2.5 m radius (tools/draw_grave_circle.py),
;; its cell 328 px at 64 px a metre; an aurora round it; then bone spikes burst up all
;; over it, the tallest 1.8 m.
(define-fx-animation grave-circle "sprites/grave/circle" :loop T :size (/ 328 64.0))
(define-fx-animation grave-spikes "sprites/grave/spikes" :fps 12 :size (/ 115 64.0))

(define-spell grave-spikes (:delivery :circle :windup 2.5
                            :circle-animation 'grave-circle
                            :strike-animation 'grave-spikes)
  (:damage :magnitude '(14 22) :area 2.5)
  (:knockback :magnitude '(3 3) :area 2.5))
