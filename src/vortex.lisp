(in-package #:hexmaw)

;;; The tornado: a spell delivered as a SPELL-VORTEX, which forms on the floor, wanders
;;; after its target on the nav grid and fades after its lifetime. It has no favourites:
;;; it takes the player, any creature and its own caster alike.
;;;
;;; PULL: within *VORTEX-PULL-RADIUS*, on its storey and with a clear line, an actor is
;;; dragged in, faster the nearer it is, so a run gets away and a walk near the middle
;;; doesn't. CATCH: within the spell's area it is held (WHIRL). It orbits the centre line,
;;; spinning faster and carried up to *WHIRL-LIFT* or just under the ceiling, for
;;; *WHIRL-HOLD* seconds, losing health to the wind. THROW: then, or when the vortex fades,
;;; it leaves along its orbit at *FLING-SPEED* and flies (FLUNG) until it lands, hurt if it
;;; hits a wall fast enough. It can't be pulled again for *SPAT-TIME*. The player can
;;; still look and attack, and pushing away from the centre widens the orbit; past
;;; *WHIRL-ESCAPE* they drop out with a weak throw.
;;;
;;; Each actor runs all this in its own tick, so its camera can't lag the vortex, and
;;; heavier ones (KNOCKBACK-SCALE) are dragged and thrown less.

(defparameter *vortex-pull-radius* 6.0 "Metres from the centre line that a vortex drags things from.")
(defparameter *vortex-pull-speed* 5.5
  "Speed in m/s it drags something at the edge of its catch, falling to nothing at the pull radius.")
(defparameter *vortex-form-time* 0.6 "Seconds it takes to form, pulling nothing.")
(defparameter *vortex-fade-time* 0.8 "Seconds it takes to die away after its lifetime, holding nothing.")
(defparameter *vortex-speed* 1.8 "Metres per second a creature's vortex moves.")
(defparameter *vortex-player-speed* 2.5 "Metres per second the player's vortex moves.")
(defparameter *vortex-replan* 1.0 "Seconds between its fresh paths to its target.")
(defparameter *vortex-max-walk* 25.0 "Longest path, in metres, it takes to its target.")
(defparameter *vortex-seek-range* 12.0 "Metres within which the player's vortex makes for a creature it can see.")
(defparameter *vortex-look* 1.0 "Metres around it that it keeps under the lowest ceiling of.")
(defparameter *vortex-step* 1.3 "Tallest ledge it passes over.")
(defparameter *vortex-light-color* (vec 0.45 0.3 0.8))
(defparameter *vortex-light-radius* 5.0)
(defparameter *vortex-puff-time* 0.18 "Seconds between the puffs of dust round its foot.")
(defparameter *player-vortex-reach* '(3.0 8.0) "Least and most metres away the player's aim places a vortex.")

(defparameter *whirl-hold* '(2.5 3.5) "Least and most seconds it holds something before it throws it.")
(defparameter *whirl-spin* '(3.0 9.0) "Radians per second something orbits at when caught, and at full spin.")
(defparameter *whirl-spin-up* 2.0 "Seconds until full spin.")
(defparameter *whirl-lift* 3.0 "Metres over the floor it carries things, where the ceiling allows.")
(defparameter *whirl-climb* 2.5 "Metres per second it carries them up.")
(defparameter *whirl-bob* 0.15 "Metres they rise and fall about that height.")
(defparameter *whirl-headroom* 0.15 "Metres it keeps between their heads and the ceiling.")
(defparameter *whirl-orbit* '(0.6 1.2) "Metres out from the centre line of an orbit at the floor and at full height.")
(defparameter *whirl-draw* 0.5 "Metres per second an orbit eases to its proper width.")
(defparameter *whirl-squeeze* 3.0 "Metres per second an orbit narrows while walls keep something off it.")
(defparameter *whirl-miss* 0.4 "Metres off its orbit that count as kept off it.")
(defparameter *whirl-stuck-limit* 0.5 "Seconds kept off its orbit before something is thrown out.")
(defparameter *whirl-step* 0.25
  "Most metres an orbit moves something in a tick: more than the widest orbit at full spin
needs, and too little to land beyond a wall, since a move is only tested where it ends.")
(defparameter *whirl-tumble* 11.0 "Radians per second a held creature's facing spins, so its views cycle.")
(defparameter *whirl-drift* 0.25 "Share of the spin that turns a held player's view.")

(defparameter *struggle-speed* 5.0 "Metres per second pushing straight out widens the player's orbit.")
(defparameter *whirl-escape* 2.2 "Metres from the centre line at which a struggling player drops out.")
(defparameter *struggle-fling* 0.3 "Share of a full throw that a player who struggled out leaves with.")

(defparameter *fling-speed* 16.0 "Speed in m/s something is thrown out at, across.")
(defparameter *fling-lift* 5.0 "Speed in m/s it is thrown up at.")
(defparameter *spat-time* 1.5 "Seconds after a throw that no vortex can pull it.")
(defparameter *land-carry* 0.5 "Share of a thrown creature's speed it keeps sliding with when it lands.")
(defparameter *slam-speed* 8.0 "Speed in m/s below which something thrown hits a wall unhurt.")
(defparameter *slam-per-speed* 2.5 "Damage per m/s over that.")
(defparameter *slam-max* 20 "The most damage hitting a wall does.")

;;; What every actor is asked.

(defgeneric actor-heft (actor)
  (:documentation "How easily a vortex moves ACTOR, 1 for the usual.")
  (:method ((creature creature)) (knockback-scale creature))
  (:method ((player player)) 1.0))

(defun pull-scale (actor) (+ 0.4 (* 0.6 (actor-heft actor))))
(defun fling-scale (actor) (+ 0.5 (* 0.5 (actor-heft actor))))

(defun ramp (range k)
  "The point K of the way between the two values of RANGE."
  (destructuring-bind (lo hi) range
    (+ lo (* k (- hi lo)))))

(defun whirl-effect (spell)
  (find :whirl (spell-effects spell) :key #'effect-kind))

(defun whirl-damage (actor)
  "Health per second the vortex holding ACTOR takes from it, or 0."
  (let ((vortex (whirl actor)))
    (if vortex
        (float (first (effect-magnitude (whirl-effect (spell vortex)))) 0f0)
        0f0)))

;;; The funnel: a cone of chunky dust round the centre line, swaying toward the top and
;;; fitted to the ceiling. Its bands spiral up it, snapped to whole cells round it and up
;;; it. It writes no depth and is drawn after everything else (LATE-RANK), so what it covers
;;; shows through from both sides, whoever stands inside it.

(defparameter *funnel-segments* 48 "Quads round a funnel's ring. Read when the mesh is made (a restart).")
(defparameter *funnel-rows* 16 "Rings of quads up a funnel. Read when the mesh is made (a restart).")
(defparameter *funnel-foot* 0.5 "Radius in metres of a funnel's foot.")
(defparameter *funnel-flare* 0.25 "Metres its mouth widens per metre of its height.")
(defparameter *funnel-inside-fade* 0.35 "Share of its dust that a camera inside it doesn't see, so it can see out.")
(defparameter *funnel-inside-detail* 4.0
  "How many times finer its cells are from inside: this close, the usual ones are metres across on screen.")

(define-shader-entity funnel (renderable listener)
  ((centre :initarg :centre :reader centre)
   (height :initform 4.0 :accessor funnel-height)
   (strength :initform 0.0 :accessor funnel-strength :documentation "0 (none) to 1 (full).")
   (clock :initform (random 100.0) :accessor funnel-clock)))

(defmethod late-rank ((funnel funnel)) 0.5)

(defvar *funnel-vao* NIL
  "The mesh every funnel draws, shared: one made mid-game would never be loaded onto the
GPU. PRELOAD-VORTEX stages it with the scene.")

(defun funnel-vao ()
  (or *funnel-vao*
      (let* ((n *funnel-segments*)
             (m *funnel-rows*)
             (data (make-array (* n m 12) :element-type 'single-float))
             (k 0))
        ;; Two triangles a quad, each vertex (fraction of the way round, fraction up).
        (dotimes (j m)
          (let ((y0 (float (/ j m) 0f0)) (y1 (float (/ (1+ j) m) 0f0)))
            (dotimes (i n)
              (let ((a0 (float (/ i n) 0f0)) (a1 (float (/ (1+ i) n) 0f0)))
                (loop for v in (list a0 y0 a1 y0 a1 y1 a0 y0 a1 y1 a0 y1)
                      do (setf (aref data k) v) (incf k))))))
        (setf *funnel-vao*
              (make-instance 'vertex-array
                             :vertex-form :triangles
                             :bindings `((,(make-instance 'vertex-buffer :buffer-data data) :size 2 :offset 0 :stride 8 :index 0))
                             :size (* n m 6))))))

(defmethod stage :after ((funnel funnel) (area staging-area))
  (stage (funnel-vao) area))

(define-handler (funnel tick) (dt)
  (unless (frozen-p)
    (incf (funnel-clock funnel) dt)))

(defun camera-inside-funnel-p (funnel)
  (and *player*
       (let ((c (centre funnel))
             (eye (location *player*))
             (r (+ *funnel-foot* (* *funnel-flare* (funnel-height funnel)))))
         (< (+ (expt (- (vx eye) (vx c)) 2) (expt (- (vz eye) (vz c)) 2)) (* r r)))))

(defmethod render ((funnel funnel) (program shader-program))
  (when (< 0 (funnel-strength funnel))
    (let ((inside (camera-inside-funnel-p funnel)))
      (setf (uniform program "view_matrix") (view-matrix)
            (uniform program "projection_matrix") (projection-matrix)
            (uniform program "centre") (centre funnel)
            (uniform program "height") (float (funnel-height funnel) 0f0)
            (uniform program "foot") (float *funnel-foot* 0f0)
            (uniform program "mouth") (float (+ *funnel-foot* (* *funnel-flare* (funnel-height funnel))) 0f0)
            (uniform program "strength") (float (* (funnel-strength funnel)
                                                   (if inside (- 1.0 *funnel-inside-fade*) 1.0))
                                                0f0)
            (uniform program "detail") (float (if inside *funnel-inside-detail* 1.0) 0f0)
            (uniform program "time") (float (funnel-clock funnel) 0f0)))
    ;; Premultiplied, so its dust can darken what is behind it as well as light it.
    (gl:disable :cull-face)
    (gl:depth-mask NIL)
    (gl:blend-func :one :one-minus-src-alpha)
    (render-array (funnel-vao))
    (gl:blend-func :src-alpha :one-minus-src-alpha)
    (gl:depth-mask T)
    (gl:enable :cull-face)))

(define-class-shader (funnel :vertex-shader)
  "layout (location = 0) in vec2 in_ah;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;
uniform vec3 centre;
uniform float height;
uniform float foot;
uniform float mouth;
uniform float time;
out vec2 v_ah;

void main(){
  float a = in_ah.x * 6.2831853;
  float y = in_ah.y;
  float r = mix(foot, mouth, pow(y, 1.5));
  // Bulges that climb it, and a sway that grows toward the top: the foot stays put.
  r *= 1.0 + 0.1 * sin(3.0 * a + 7.0 * y - time * 4.0);
  vec3 sway = vec3(sin(time * 1.3 + y * 2.5), 0.0, cos(time * 1.1 + y * 2.0)) * 0.3 * y * y;
  vec3 p = centre + sway + vec3(cos(a) * r, y * height, sin(a) * r);
  gl_Position = projection_matrix * (view_matrix * vec4(p, 1.0));
  v_ah = in_ah;
}")

(define-class-shader (funnel :fragment-shader)
  "in vec2 v_ah;
uniform float strength;
uniform float height;
uniform float detail;
uniform float time;
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
  // Whole cells round it and up it, for the art's chunky pixels.
  float cols = 96.0 * detail;
  float rows = max(8.0, floor(height * 14.0)) * detail;
  float u = (floor(v_ah.x * cols) + 0.5) / cols;
  float y = (floor(v_ah.y * rows) + 0.5) / rows;
  // Bands spiralling up it, a broad set and a fine one.
  float broad = ring_noise(u * 14.0 - y * 10.0 + time * 2.6, 14.0);
  float fine = ring_noise(u * 32.0 - y * 24.0 + time * 4.3, 32.0);
  float dust = smoothstep(0.35, 0.8, 0.65 * broad + 0.45 * fine);
  float edge = smoothstep(0.0, 0.06, y) * (1.0 - smoothstep(0.85, 1.0, y));
  vec3 c = mix(vec3(0.3, 0.27, 0.36), vec3(0.62, 0.58, 0.72), broad)
         + vec3(0.25, 0.12, 0.4) * pow(fine, 4.0);
  float alpha = dust * mix(0.55, 0.85, y) * edge * strength;
  color = vec4(c * alpha, alpha);
}")

;;; The vortex.

(define-shader-entity spell-vortex (fx-sprite)
  ((spell :initarg :spell :reader spell)
   (caster :initarg :caster :initform NIL :reader caster)
   (centre :initarg :centre :reader centre :documentation "Where its centre line meets the floor.")
   (heading :initform (vec 0 0 -1) :reader vortex-heading :documentation "The way it goes with no target: only X and Z count.")
   (route :initform () :accessor vortex-route :documentation "Points still to go to, nearest first.")
   (replan :initform 0.0 :accessor vortex-replan :documentation "Seconds until it looks for a fresh path.")
   (ceiling :initform 1000.0 :accessor vortex-ceiling :documentation "The lowest ceiling around it.")
   (puff-timer :initform 0.0 :accessor puff-timer)
   (funnel :initform NIL :accessor vortex-funnel)))

;; All that shows of it is its funnel and its dust.
(defmethod render :around ((vortex spell-vortex) (program shader-program)))

(defun vortex-lifetime (vortex)
  (effect-duration (whirl-effect (spell vortex))))

(defun vortex-live-p (vortex)
  "True while VORTEX pulls and holds: formed, and not yet dying away."
  (<= *vortex-form-time* (age vortex) (vortex-lifetime vortex)))

(defun vortex-strength (vortex)
  (let ((age (age vortex)) (lifetime (vortex-lifetime vortex)))
    (if (< age lifetime)
        (min 1.0 (/ age *vortex-form-time*))
        (max 0.0 (- 1.0 (/ (- age lifetime) *vortex-fade-time*))))))

(defun vortex-speed (vortex)
  (if (eq (caster vortex) *player*) *vortex-player-speed* *vortex-speed*))

(defun vortex-target (vortex)
  "Where VORTEX makes for: a creature's goes after the player, the player's after the
nearest creature it can see. NIL, for keeping its heading, once its quarry is inside it."
  (let ((c (centre vortex)))
    (if (eq (caster vortex) *player*)
        (let ((best NIL) (best-distance *vortex-seek-range*))
          (loop for creature across *creatures*
                for at = (location creature)
                for d = (sqrt (+ (expt (- (vx at) (vx c)) 2) (expt (- (vz at) (vz c)) 2)))
                when (and (< d best-distance) (not (dead creature)) (not (whirl creature))
                          (clear-path-p c at 1.0))
                  do (setf best at best-distance d))
          best)
        (when (and *player* (not (whirl *player*)))
          (feet *player*)))))

(defun plan-vortex (vortex)
  (let ((c (centre vortex))
        (target (vortex-target vortex)))
    (setf (vortex-route vortex)
          (when (and target *nav-grid*)
            (if (nav-line-clear-p c target 0.4 1.5 *vortex-step*)
                (list (vcopy target))
                (nav-path-to c target 0.4 1.5 *vortex-step* :max-walk *vortex-max-walk*))))))

(defun move-vortex (vortex dt)
  "Move VORTEX DT seconds along its route, or on its heading, over any floor. Blocked, it
turns aside. It settles to the floor and notes the ceiling."
  (let* ((c (centre vortex))
         (heading (vortex-heading vortex))
         (step (* (vortex-speed vortex) dt))
         (*nav-hazards* :ignore)
         (to (first (vortex-route vortex))))
    (when to
      (let* ((dx (- (vx to) (vx c)))
             (dz (- (vz to) (vz c)))
             (d (sqrt (+ (* dx dx) (* dz dz)))))
        (if (< d (max step 0.1))
            (pop (vortex-route vortex))
            (setf (vx heading) (float (/ dx d) 0f0)
                  (vz heading) (float (/ dz d) 0f0)))))
    (let* ((x (+ (vx c) (* step (vx heading))))
           (z (+ (vz c) (* step (vz heading))))
           (floor (nav-floor-at x (+ (vy c) 0.5) z)))
      (cond ((and floor
                  (< (abs (- floor (vy c))) *vortex-step*)
                  (fits-at-p x (+ floor 0.5) z 0.3 1.0))
             (setf (vx c) (float x 0f0)
                   (vz c) (float z 0f0)))
            (T
             (let ((turn (+ (/ pi 2) (random (float pi 0f0))))
                   (hx (vx heading)) (hz (vz heading)))
               (setf (vortex-route vortex) ()
                     (vx heading) (float (- (* hx (cos turn)) (* hz (sin turn))) 0f0)
                     (vz heading) (float (+ (* hx (sin turn)) (* hz (cos turn))) 0f0))))))
    (multiple-value-bind (floor ceiling)
        (nav-room-around (vx c) (+ (vy c) 0.5) (vz c) *vortex-look* *vortex-step*)
      (when floor
        (let ((most (* *settle-speed* dt)))
          (setf (vy c) (float (+ (vy c) (max (- most) (min most (- floor (vy c))))) 0f0)
                (vortex-ceiling vortex) (float ceiling 0f0)))))))

(defun puff-dust (vortex)
  "A puff of dust somewhere round VORTEX's foot."
  (when *ogre-dust*
    (let* ((c (centre vortex))
           (a (random (float (* 2 pi) 0f0)))
           (r (+ *funnel-foot* (random 1.0))))
      (spawn-standing-fx *ogre-dust* (+ (vx c) (* r (cos a))) (vy c) (+ (vz c) (* r (sin a)))
                         (container vortex)))))

(defun start-vortex (vortex)
  "Bring VORTEX's funnel and lamp up and list it, the first time it ticks in the scene."
  (vector-push-extend vortex *vortices*)
  (setf (vortex-funnel vortex) (make-instance 'funnel :centre (centre vortex)))
  (enter (vortex-funnel vortex) (container vortex))
  ;; A loaded one has its lamp back already (RESTORE-EFFECT).
  (unless (find vortex *lamps* :key #'source)
    (attach-glow vortex *vortex-light-color* *vortex-light-radius*)))

;; Its own tick, not FX-SPRITE's: it doesn't play out an animation.
(define-handler (spell-vortex tick) (dt)
  (when (and (container spell-vortex) (null (vortex-funnel spell-vortex)))
    (start-vortex spell-vortex))
  (unless (frozen-p)
    (incf (age spell-vortex) dt)
    (when *nav-grid*
      (when (<= (decf (vortex-replan spell-vortex) dt) 0)
        (setf (vortex-replan spell-vortex) *vortex-replan*)
        (let ((*nav-hazards* :ignore))
          (plan-vortex spell-vortex)))
      (move-vortex spell-vortex dt))
    (when (and (vortex-live-p spell-vortex) (<= (decf (puff-timer spell-vortex) dt) 0))
      (setf (puff-timer spell-vortex) *vortex-puff-time*)
      (puff-dust spell-vortex))
    (when (< (+ (vortex-lifetime spell-vortex) *vortex-fade-time*) (age spell-vortex))
      (despawn spell-vortex)))
  (let ((c (centre spell-vortex))
        (loc (location spell-vortex))
        (funnel (vortex-funnel spell-vortex)))
    (setf (vx loc) (vx c) (vy loc) (+ (vy c) 1.0) (vz loc) (vz c))
    (when funnel
      (setf (funnel-strength funnel) (vortex-strength spell-vortex)
            (funnel-height funnel) (min 9.0 (max 2.0 (- (vortex-ceiling spell-vortex) (vy c))))))))

(defun caught (vortex)
  "Everything VORTEX holds, which is how a save remembers it."
  (let ((held (loop for creature across *creatures*
                    when (eq (whirl creature) vortex) collect creature)))
    (if (and *player* (eq (whirl *player*) vortex))
        (cons *player* held)
        held)))

(defun (setf caught) (actors vortex)
  (dolist (actor actors actors)
    (setf (whirl actor) vortex)))

;; A reset or rebuild takes it away before it is done; REVIVE and RESPAWN have cleared
;; whatever it held by then, and a despawn at its end holds nothing.
(defmethod leave :after ((vortex spell-vortex) container)
  (when (vortex-funnel vortex)
    (despawn (vortex-funnel vortex))
    (setf (vortex-funnel vortex) NIL))
  (let ((at (position vortex *vortices*)))
    (when at
      (replace *vortices* *vortices* :start1 at :start2 (1+ at))
      (decf (fill-pointer *vortices*))))
  (dolist (actor (caught vortex))
    (throw-actor actor 1.0)))

(defun preload-vortex (spell scene)
  "Load what SPELL's vortex draws, which only appears mid-game."
  (preload (make-instance 'spell-vortex :spell spell :centre (vec 0 0 0)
                                        :animation (find-fx-animation 'ogre-dust))
           scene)
  (preload (make-instance 'funnel :centre (vec 0 0 0)) scene)
  (preload (make-instance 'gale-sign :centre (vec 0 0 0) :animation (find-fx-animation 'gale-sign)) scene))

(defun floor-under (point)
  "POINT on the floor under it."
  (let ((floor (and *nav-grid* (nav-floor-at (vx point) (vy point) (vz point)))))
    (vec (vx point) (or floor (vy point)) (vz point))))

(defun vortex-aim-point (origin direction)
  "The floor a vortex cast from ORIGIN along unit vector DIRECTION goes on: where the aim
meets the floor, within *PLAYER-VORTEX-REACH* across, short of any wall."
  (let* ((len (sqrt (+ (expt (vx direction) 2) (expt (vz direction) 2))))
         (fx (if (< 1f-3 len) (/ (vx direction) len) 0.0))
         (fz (if (< 1f-3 len) (/ (vz direction) len) -1.0))
         (slope (if (< 1f-3 len) (/ (vy direction) len) -10.0))
         (feet (vy (floor-under origin)))
         (eye-over (- (vy origin) feet)))
    (destructuring-bind (least most) *player-vortex-reach*
      (let ((wanted (if (< slope -1f-3)
                        (max least (min most (/ eye-over (- slope))))
                        most)))
        ;; Along the floor, stopping short of anything in the way.
        (loop with x = (vx origin) and z = (vz origin) and y = (+ feet 0.5)
              for d from 0.25 to wanted by 0.25
              for nx = (+ (vx origin) (* d fx))
              for nz = (+ (vz origin) (* d fz))
              while (fits-at-p nx y nz 0.3 1.0)
              do (setf x nx z nz)
              finally (return (floor-under (vec x y z))))))))

(defun place-vortex (spell origin direction container caster)
  "Raise SPELL's vortex for CASTER: the player's where their aim from ORIGIN along DIRECTION
meets the floor, anyone else's on the floor under ORIGIN."
  (let* ((point (if (and caster (eq caster *player*))
                    (vortex-aim-point origin direction)
                    (floor-under origin)))
         (vortex (make-instance 'spell-vortex :spell spell :caster caster :centre point
                                              :location (vcopy point)
                                              :animation (find-fx-animation 'ogre-dust)))
         (heading (vortex-heading vortex))
         (len (sqrt (+ (expt (vx direction) 2) (expt (vz direction) 2)))))
    (when (< 1f-3 len)
      (setf (vx heading) (float (/ (vx direction) len) 0f0)
            (vz heading) (float (/ (vz direction) len) 0f0)))
    (enter vortex container)
    vortex))

;;; Pull and catch.

(defun vortex-reaches-p (vortex feet)
  "True if feet at FEET are on VORTEX's storey: a line of sight only looks across, at one
height, so without this it would reach through a floor."
  (let ((y (vy (centre vortex))))
    (< (- y 1.0) (vy feet) (vortex-ceiling vortex))))

(defun line-to-vortex-p (actor vortex dt)
  "True if ACTOR has a clear line to VORTEX, looked for ten times a second."
  (when (<= (decf (pull-look actor) dt) 0)
    (setf (pull-look actor) 0.1
          (pull-clear actor) (clear-path-p (centre vortex) (body-feet actor) 1.0)))
  (pull-clear actor))

(defun vortex-pull (actor dt)
  "Set ACTOR's PULL from the vortices reaching it. Returns the vortex that catches it, if one does."
  (let ((pull (pull actor))
        (feet (body-feet actor))
        (radius (float (body-radius actor) 0f0)))
    (setf (vx pull) 0f0 (vz pull) 0f0)
    (when (<= (spat-timer actor) 0)
      (loop for vortex across *vortices*
            for c = (centre vortex)
            for dx = (- (vx c) (vx feet))
            for dz = (- (vz c) (vz feet))
            for d = (sqrt (+ (* dx dx) (* dz dz)))
            when (and (< d *vortex-pull-radius*)
                      (vortex-live-p vortex)
                      (vortex-reaches-p vortex feet)
                      (line-to-vortex-p actor vortex dt))
              do (let ((catch (+ (circle-radius (spell vortex)) (* 0.5 radius))))
                   (when (< d catch)
                     (return vortex))
                   (let ((speed (* *vortex-pull-speed* (pull-scale actor)
                                   (expt (/ (- *vortex-pull-radius* d) (- *vortex-pull-radius* catch)) 1.5))))
                     (incf (vx pull) (float (* speed (/ dx d)) 0f0))
                     (incf (vz pull) (float (* speed (/ dz d)) 0f0))))))))

(defgeneric note-caught (actor)
  (:documentation "A vortex has just caught ACTOR: stop whatever it was doing."))

(defun catch-actor (actor vortex)
  (let ((feet (body-feet actor))
        (c (centre vortex))
        (pull (pull actor)))
    (destructuring-bind (lo hi) *whirl-hold*
      (setf (whirl actor) vortex
            (flung actor) NIL
            (whirl-angle actor) (float (atan (- (vz feet) (vz c)) (- (vx feet) (vx c))) 0f0)
            (whirl-radius actor) (float (sqrt (+ (expt (- (vx feet) (vx c)) 2) (expt (- (vz feet) (vz c)) 2))) 0f0)
            ;; Not all at one height, so a crowd spreads out up the funnel.
            (whirl-lift actor) (float (* *whirl-lift* (+ 0.7 (random 0.3 *roll-random*))) 0f0)
            (whirl-time actor) 0.0
            (whirl-stuck actor) 0.0
            (whirl-hold actor) (+ lo (random (float (- hi lo) 0f0) *roll-random*))
            (vx pull) 0f0
            (vz pull) 0f0))
    (note-caught actor)))

;;; The orbit.

(defun orbit-point (actor vortex dt)
  "Advance ACTOR's orbit of VORTEX by DT seconds. Returns where it should be now, and how
fast it is spinning."
  (let* ((time (incf (whirl-time actor) dt))
         (spin (ramp *whirl-spin* (min 1.0 (/ time *whirl-spin-up*))))
         (angle (mod (+ (whirl-angle actor) (* spin dt)) #.(float (* 2 pi) 0f0)))
         (c (centre vortex))
         (feet (body-feet actor))
         (floor (vy c))
         (top (max floor (min (+ floor (whirl-lift actor) (* *whirl-bob* (sin (* 3.0 time))))
                              (- (vortex-ceiling vortex) (float (body-height actor) 0f0) *whirl-headroom*))))
         (most (* *whirl-climb* dt))
         (y (+ (vy feet) (max (- most) (min most (- top (vy feet))))))
         (wanted (ramp *whirl-orbit* (max 0.0 (min 1.0 (/ (- y floor) *whirl-lift*)))))
         (radius (whirl-radius actor))
         (draw (* *whirl-draw* dt))
         (radius (+ radius (max (- draw) (min draw (- wanted radius))))))
    (setf (whirl-angle actor) angle
          (whirl-radius actor) radius)
    (values (+ (vx c) (* radius (cos angle))) y (+ (vz c) (* radius (sin angle))) spin)))

(defun orbit-step (x z from-x from-z)
  "The move this tick from FROM-X FROM-Z toward the orbit's point X Z, at most *WHIRL-STEP*.
Walls can keep something a whole orbit's width off that point, or the point beyond them."
  (let* ((dx (- x from-x))
         (dz (- z from-z))
         (d (sqrt (+ (* dx dx) (* dz dz))))
         (k (if (< *whirl-step* d) (/ *whirl-step* d) 1.0)))
    (values (float (* k dx) 0f0) (float (* k dz) 0f0))))

(defun note-orbit-miss (actor x z dt)
  "See how far walls kept ACTOR from its orbit's point X Z: its orbit narrows to fit, and
it counts toward being thrown out."
  (let ((feet (body-feet actor)))
    (if (< (* *whirl-miss* *whirl-miss*)
           (+ (expt (- x (vx feet)) 2) (expt (- z (vz feet)) 2)))
        (setf (whirl-stuck actor) (+ (whirl-stuck actor) dt)
              (whirl-radius actor) (max 0.0 (- (whirl-radius actor) (* *whirl-squeeze* dt))))
        (setf (whirl-stuck actor) 0.0))))

(defun whirl-over-p (actor vortex dt)
  "Run down ACTOR's hold on VORTEX by DT seconds. True if it is time to throw it."
  (or (<= (decf (whirl-hold actor) dt) 0)
      (not (vortex-live-p vortex))
      (<= *whirl-stuck-limit* (whirl-stuck actor))))

;;; The throw.

(defgeneric launch-actor (actor vx vy vz)
  (:documentation "Send ACTOR flying at that velocity."))

(defun throw-actor (actor scale)
  "Throw ACTOR out of the vortex holding it, along its orbit and a little outward, at
SCALE of the full speed."
  (let* ((angle (whirl-angle actor))
         (ox (cos angle)) (oz (sin angle))
         (dx (+ (* 0.8 (- oz)) (* 0.6 ox)))
         (dz (+ (* 0.8 ox) (* 0.6 oz)))
         (k (* scale (fling-scale actor)))
         (speed (* k *fling-speed*)))
    (setf (whirl actor) NIL
          (flung actor) T
          (whirl-stuck actor) 0.0
          (spat-timer actor) *spat-time*)
    (launch-actor actor (float (* speed dx) 0f0) (float (* k *fling-lift*) 0f0) (float (* speed dz) 0f0))))

(defun slam-damage (speed)
  (max 1 (min *slam-max* (round (* *slam-per-speed* (- speed *slam-speed*))))))

;;; Creatures.

(defmethod note-caught ((creature creature))
  (let ((m (momentum creature)))
    (setf (vx m) 0f0 (vz m) 0f0))
  (stop-walking creature 0.5)
  (setf (slot-yaw creature) NIL
        (rising creature) 0.0
        (footing creature) NIL)
  (break-flight creature))

(defmethod launch-actor ((creature creature) vx vy vz)
  (let ((v (flight creature)))
    (setf (vx v) vx (vy v) vy (vz v) vz))
  (stop-walking creature 0.5))

(defun orbit-creature (creature vortex dt)
  (multiple-value-bind (x y z) (orbit-point creature vortex dt)
    (let ((loc (location creature))
          (*ignore-bodies* T))
      (multiple-value-bind (dx dz) (orbit-step x z (vx loc) (vz loc))
        (move-creature creature dx dz 0.05))
      (when (fits-at-p (vx loc) y (vz loc) (body-radius creature) (sprite-height creature))
        (setf (vy loc) (float y 0f0)))
      (note-orbit-miss creature x z dt)))
  ;; Its flinch frame, its views cycling: it tumbles.
  (setf (stagger creature) (* 0.6 *stagger-time*)
        (facing creature) (mod (+ (facing creature) (* *whirl-tumble* dt)) #.(float (* 2 pi) 0f0)))
  (multiple-value-bind (timer due) (burn-due (burn-timer creature) dt (whirl-damage creature))
    (setf (burn-timer creature) timer)
    (when (< 0 due)
      (burn creature due))))

(defun land-creature (creature)
  (let ((m (momentum creature))
        (v (flight creature)))
    (setf (vx m) (* *land-carry* (vx v))
          (vz m) (* *land-carry* (vz v))
          (flung creature) NIL)
    (unless (dead creature)
      (land-thrown creature))))

(defun slam-creature (creature speed lost-x lost-z)
  "CREATURE flew into a wall at SPEED, which took LOST-X and LOST-Z off its flight."
  (let ((loc (location creature)))
    (hurt creature (slam-damage speed)
          :from (vec (+ (vx loc) lost-x) (+ (vy loc) (* 0.5 (sprite-height creature))) (+ (vz loc) lost-z)))))

(defun fly-thrown (creature dt)
  "Fly CREATURE DT seconds through the air under gravity, through other bodies, stopping
at walls, until it comes to a floor."
  (let* ((loc (location creature))
         (v (flight creature))
         (x0 (vx loc)) (z0 (vz loc))
         (dx (* (vx v) dt)) (dz (* (vz v) dt)))
    (decf (vy v) (* *gravity* dt))
    (let ((*ignore-bodies* T))
      (move-creature creature dx dz 0.05))
    ;; Compared with where it meant to go: a slide along a 45 degree wall counts for what it lost.
    (let* ((moved-x (- (vx loc) x0))
           (moved-z (- (vz loc) z0))
           (lost-x (/ (- dx moved-x) dt))
           (lost-z (/ (- dz moved-z) dt))
           (lost (sqrt (+ (* lost-x lost-x) (* lost-z lost-z)))))
      (setf (vx v) (/ moved-x dt)
            (vz v) (/ moved-z dt))
      (when (< *slam-speed* lost)
        (slam-creature creature lost lost-x lost-z)))
    (let ((y (+ (vy loc) (* (vy v) dt)))
          (floor (and *nav-grid* (nav-floor-at (vx loc) (vy loc) (vz loc)))))
      (cond ((< y *kill-height*)
             ;; Nowhere to land.
             (v<- loc (home creature))
             (setf (vx v) 0f0 (vz v) 0f0)
             (land-creature creature))
            ((and floor (<= (vy v) 0) (<= y floor))
             (setf (vy loc) (float floor 0f0))
             (land-creature creature))
            ((fits-at-p (vx loc) y (vz loc) (body-radius creature) (sprite-height creature))
             (setf (vy loc) (float y 0f0)))
            ((< 0 (vy v))
             (setf (vy v) 0f0))
            (T
             (land-creature creature))))))

(defun whirl-step (creature dt)
  "Run CREATURE's part in the vortices for DT seconds. True if one holds or has thrown it:
it moves no other way, and doesn't think."
  (setf (spat-timer creature) (max 0.0 (- (spat-timer creature) dt)))
  (let ((vortex (whirl creature)))
    (cond (vortex
           (cond ((or (dead creature) (whirl-over-p creature vortex dt))
                  (throw-actor creature 1.0)
                  (fly-thrown creature dt))
                 (T
                  (orbit-creature creature vortex dt)))
           T)
          ((flung creature)
           (fly-thrown creature dt)
           T)
          ((dead creature)
           NIL)
          (T
           (let ((caught (vortex-pull creature dt)))
             (cond (caught
                    (catch-actor creature caught)
                    T)
                   (T
                    (let ((pull (pull creature)))
                      (unless (and (= 0 (vx pull)) (= 0 (vz pull)))
                        (move-creature creature (* (vx pull) dt) (* (vz pull) dt) (move-lift creature))))
                    NIL)))))))

;;; The player.

(defmethod note-caught ((player player))
  (let ((vel (velocity player)))
    (setf (vx vel) 0f0 (vy vel) 0f0 (vz vel) 0f0))
  (setf (climbing player) NIL
        (footing player) NIL
        (grounded player) NIL))

(defmethod launch-actor ((player player) vx vy vz)
  (let ((vel (velocity player)))
    (setf (vx vel) vx (vy vel) vy (vz vel) vz))
  (setf (grounded player) NIL))

(defun whirl-transitions (player dt)
  "Before PLAYER moves this tick: throw them if it's time, or see what pulls or catches them."
  (setf (spat-timer player) (max 0.0 (- (spat-timer player) dt)))
  (let ((vortex (whirl player)))
    (if vortex
        (when (whirl-over-p player vortex dt)
          (throw-actor player 1.0))
        (let ((caught (vortex-pull player dt)))
          (when caught
            (catch-actor player caught))))))

(defun struggle (player wx wz dt)
  "PLAYER wishing along WX WZ against the vortex: pushing away from the centre widens the
orbit, and past *WHIRL-ESCAPE* they drop out. Returns true if they did."
  (let* ((angle (whirl-angle player))
         (out (+ (* wx (cos angle)) (* wz (sin angle)))))
    (when (< 0 out)
      (incf (whirl-radius player) (* *struggle-speed* out dt))
      (when (<= *whirl-escape* (whirl-radius player))
        (throw-actor player *struggle-fling*)
        T))))

(defun orbit-player (player dt wx wz)
  "Move PLAYER DT seconds round the vortex holding them, wishing along WX WZ. Walls stop
them; bodies don't, and a share of the spin turns their view."
  (let ((vortex (whirl player))
        (*walk-through-bodies* T))
    (unless (struggle player wx wz dt)
      (multiple-value-bind (x y z spin) (orbit-point player vortex dt)
        (let ((feet (feet player))
              (vel (velocity player))
              (rot (rotation player)))
          (multiple-value-bind (dx dz) (orbit-step x z (vx feet) (vz feet))
            (move-flat player dx dz))
          (move-axis player 1 (float (- y (vy feet)) 0f0))
          (note-orbit-miss player x z dt)
          (setf (vx vel) 0f0 (vy vel) 0f0 (vz vel) 0f0
                (grounded player) NIL
                (footing player) NIL
                (vy rot) (float (mod (+ (vy rot) (* *whirl-drift* spin dt)) #.(float (* 2 pi) 0f0)) 0f0)))))))

(defun end-player-flight (player vx0 vz0)
  "After PLAYER, thrown and moving at VX0 VZ0, has moved this tick: a wall that stopped
them hurts, as a shield can't help, and landing ends the flight."
  (when (flung player)
    (let* ((vel (velocity player))
           (hit-x (if (= 0 (vx vel)) vx0 0f0))
           (hit-z (if (= 0 (vz vel)) vz0 0f0))
           (hit (sqrt (+ (* hit-x hit-x) (* hit-z hit-z)))))
      (when (< *slam-speed* hit)
        (hurt-player player (slam-damage hit) (feet player) :shove NIL :by :tornado)
        (hit-stop))
      (when (or (grounded player) (swimming player))
        (setf (flung player) NIL)))))

;;; The spell.

(define-spell tempest (:delivery :vortex)
  ;; Health per second, the catch's radius in metres, its lifetime in seconds.
  (:whirl :magnitude '(4 4) :area 1.0 :duration 9))
