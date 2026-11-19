(in-package #:hexmaw)

;;; Stained glass: a coloured pane in a window (a blueprint's GLASS action, over a sill at
;;; least *GLASS-MIN-SILL* high), a solid like a wall until anything strikes it: a blow, a
;;; projectile, a burst or nova, an earthshake or an ogre's quake, a body thrown into it.
;;; Then it shatters into shards of its colours and leaves an empty frame with a few teeth of
;;; glass in it. Intact, it blocks sight and paths like any wall; the sill keeps every walk
;;; as it was, so the nav grid never changes. A pane belongs to one block, so to one room.
;;;
;;; It is drawn twice, late (LATE-RANK, after water, before the tornado's funnel), writing no
;;; depth: first as a filter, multiplying what lies behind by its colours (black behind the
;;; lead), then adding its own light, the light on its near face and the lamps' light on its
;;; far face shining through it, so a torch behind a window lights it up in its colours.

(defparameter *glass-looks*
  '(("lancet-flame" :texture glass-lancet-flame :ramps (:glass-red :glass-gold :glass-violet :glass-violet :glass-blue)
     :light (1.0 0.42 0.15))
    ("lancet-frost" :texture glass-lancet-frost :ramps (:glass-blue :glass-blue :glass-blue :glass-violet :glass-teal)
     :light (0.3 0.5 1.0))
    ("rose-maw" :texture glass-rose-maw :ramps (:glass-violet :glass-violet :glass-red :glass-red :glass-gold)
     :light (0.8 0.3 0.6))
    ("quarry" :texture glass-quarry :ramps (:glass-gold :glass-gold :glass-gold :glass-green)
     :light (0.9 0.75 0.35)))
  "Per stained-glass design (its size is HEXMAW.BLUEPRINT:*GLASS-DESIGNS*'): its texture, the
spark ramps its shards are, drawn from at random, and its lamp's colour.")

(define-asset (hexmaw glass-lancet-flame) image #p"textures/glass-lancet-flame.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :clamp-to-edge)
(define-asset (hexmaw glass-lancet-frost) image #p"textures/glass-lancet-frost.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :clamp-to-edge)
(define-asset (hexmaw glass-rose-maw) image #p"textures/glass-rose-maw.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :clamp-to-edge)
(define-asset (hexmaw glass-quarry) image #p"textures/glass-quarry.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :clamp-to-edge)

(defparameter *glass-tint* 0.85 "How strongly a pane colours what is seen through it, 0 to 1.")
(defparameter *glass-filter* 0.75 "How much of the light behind a pane comes through its glass.")
(defparameter *glass-reflect* 0.35 "How much of the light on its near face a pane's glass gives back.")
(defparameter *glass-transmit* 1.6 "How much of the lamps' light on its far face shines through a pane.")
(defparameter *glass-teeth* 6.0 "Most texels of glass a broken pane keeps in its frame.")

(defparameter *pane-light-strength* 0.35
  "How bright the lamp a pane hangs on its darker side is, by its design's colour; NIL for none.")
(defparameter *pane-light-radius* 3.5)
(defparameter *pane-light-reach* 8.0 "Metres from a pane a torch makes it hang its lamp, on the far side.")
(defparameter *pane-light-out* 1.0 "Metres out from the pane its lamp hangs.")
(defparameter *pane-light-merge* 2.5
  "Metres within which windows share one lamp, its colour their colours added: every lamp sent
costs every lit pixel, and the chapel's four came to 0.9 ms of GPU a frame.")

(defparameter *shards-per-m2* 42 "Shards a pane breaks into, a square metre.")
(defparameter *shard-speed* '(1.0 3.6) "M/s shards fly from a pane at, the way the blow went.")
(defparameter *shard-back-share* 0.25 "Share of the shards that fall back toward the blow, slowly.")
(defparameter *shard-rest* '(4.0 8.0) "Seconds a shard lies on the floor before it dissolves.")
(defparameter *shard-big-chance* 0.6 "Chance a shard is a 2 x 2 chip, not one texel.")

(defvar *panes* (make-array 0 :adjustable T :fill-pointer T)
  "Every pane of the level, in the order placed: a save names the broken ones by index. CLEAR-LEVEL
empties it.")

(defclass pane ()
  ((design :initarg :design :reader pane-design)
   (low :initarg :low :reader pane-low :documentation "The low corner of its solid.")
   (high :initarg :high :reader pane-high)
   (along-x :initarg :along-x :reader pane-along-x :documentation "True if it runs along x, else along z.")
   (solid :initarg :solid :reader pane-solid)
   (sheet :initform NIL :accessor pane-sheet :documentation "Its GLASS-PANE, which draws it.")
   (light :initform NIL :accessor pane-light :documentation "Where its lamp hangs, or NIL for none.")
   (lamp :initform NIL :accessor pane-lamp)
   (broken :initform NIL :accessor broken)))

(defun glass-look (design key)
  (getf (rest (or (assoc design *glass-looks* :test #'string=) (error "No glass design ~s." design))) key))

(defun pane-centre (pane)
  (v* (v+ (pane-low pane) (pane-high pane)) 0.5))

(defun pane-normal (pane)
  "Its face's normal, one way: +Z for a pane along x, +X for one along z."
  (if (pane-along-x pane) (vec 0 0 1) (vec 1 0 0)))

(defun pane-of-solid (s)
  "The pane whose solid S is, or NIL."
  (and s (< 8 (length s)) (eq :glass (solid-strike s))
       (find s *panes* :key #'pane-solid :test #'eq)))

;;; Drawing.

(define-shader-entity glass-pane (lit-entity vertex-entity transformed-entity listener)
  ((vertex-array :initform (// 'hexmaw 'centered-quad))
   (texture :initarg :texture :reader glass-texture)
   (axis :initarg :axis :reader pane-axis :documentation "Its direction across, in XZ.")
   (origin :initarg :origin :reader pane-origin
           :documentation "Where its texture starts: along its axis, and its bottom's height.")
   (size :initarg :size :reader pane-size :documentation "Its width and height in metres.")
   (shown-broken :initform NIL :accessor shown-broken)
   (rank :initform 0.35 :accessor pane-rank))
  (:documentation "A pane of stained glass: a quad standing in its window."))

(defmethod stage :after ((sheet glass-pane) (area staging-area))
  (stage (glass-texture sheet) area))

(defmethod bind-textures :after ((sheet glass-pane))
  (bind (glass-texture sheet) :texture0))

(defmethod late-rank ((sheet glass-pane)) (pane-rank sheet))

;; Nearer last: a filter then a glow doesn't commute, so the panes go far to near.
(define-handler (glass-pane tick) ()
  (let ((camera (camera (scene +main+))))
    (when camera
      (let* ((a (location camera)) (b (location glass-pane))
             (d (sqrt (+ (expt (- (vx a) (vx b)) 2) (expt (- (vy a) (vy b)) 2) (expt (- (vz a) (vz b)) 2)))))
        (setf (pane-rank glass-pane) (+ 0.3 (/ 0.1 (+ 1.0 d))))))))

(defmethod render :before ((sheet glass-pane) (program shader-program))
  (when (first-this-frame-p program)
    (set-fog-uniforms program)
    (setf (uniform program "glass_texture") 0
          (uniform program "texels_per_metre") (float *texels-per-metre* 0f0)
          (uniform program "glass_tint") (float *glass-tint* 0f0)
          (uniform program "glass_filter") (float *glass-filter* 0f0)
          (uniform program "glass_reflect") (float *glass-reflect* 0f0)
          (uniform program "glass_transmit") (float *glass-transmit* 0f0)
          (uniform program "glass_teeth") (float *glass-teeth* 0f0)))
  (setf (uniform program "pane_axis") (pane-axis sheet)
        (uniform program "pane_origin") (pane-origin sheet)
        (uniform program "pane_size") (pane-size sheet)
        (uniform program "pane_broken") (if (shown-broken sheet) 1 0)))

(defmethod render :around ((sheet glass-pane) (program shader-program))
  (gl:disable :cull-face)
  (gl:depth-mask NIL)
  ;; The filter: what lies behind, times its colours.
  (gl:blend-func :zero :src-color)
  (setf (uniform program "pane_pass") 0)
  (call-next-method)
  ;; Its own light, added.
  (gl:blend-func :one :one)
  (setf (uniform program "pane_pass") 1)
  (call-next-method)
  (gl:blend-func :src-alpha :one-minus-src-alpha)
  (gl:depth-mask T)
  (gl:enable :cull-face))

(define-class-shader (glass-pane :fragment-shader)
  "in vec3 v_world_position;
in vec3 v_view_position;
uniform sampler2D glass_texture;
uniform float texels_per_metre;
uniform vec2 pane_axis;
uniform vec2 pane_origin;
uniform vec2 pane_size;
uniform int pane_broken;
uniform int pane_pass;
uniform float glass_tint;
uniform float glass_filter;
uniform float glass_reflect;
uniform float glass_transmit;
uniform float glass_teeth;
out vec4 color;

float glass_hash(vec2 p){
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main(){
  // Laid on the pane a texel of the 64-a-metre grid at a time, its bottom row at the sill.
  vec2 texels = floor(pane_size * texels_per_metre + 0.5);
  vec2 uv = vec2(dot(v_world_position.xz, pane_axis) - pane_origin.x, v_world_position.y - pane_origin.y);
  vec2 t = clamp(floor(uv * texels_per_metre), vec2(0.0), texels - 1.0);
  vec4 c = texture(glass_texture, (t + 0.5) / texels);
  if(pane_broken != 0){
    // An empty frame: teeth of glass a few texels deep, jagged along each side.
    vec2 from_low = t;
    vec2 from_high = texels - 1.0 - t;
    float keep = 0.0;
    if(from_low.x < glass_teeth) keep = max(keep, step(from_low.x, floor(glass_hash(vec2(t.y, 1.0)) * glass_teeth)));
    if(from_high.x < glass_teeth) keep = max(keep, step(from_high.x, floor(glass_hash(vec2(t.y, 2.0)) * glass_teeth)));
    if(from_low.y < glass_teeth) keep = max(keep, step(from_low.y, floor(glass_hash(vec2(t.x, 3.0)) * glass_teeth)));
    if(from_high.y < glass_teeth) keep = max(keep, step(from_high.y, floor(glass_hash(vec2(t.x, 4.0)) * glass_teeth)));
    if(keep < 0.5) discard;
  }
  bool came = 0.75 < c.a;
  float dist = length(v_view_position);
  float fog = clamp((dist - fog_start) / (fog_end - fog_start), 0.0, 1.0);
  float lamp_fog = clamp((dist - lamp_fog_start) / (lamp_fog_end - lamp_fog_start), 0.0, 1.0);
  if(pane_pass == 0){
    // The glass's hue at full strength, so the filter colours what is behind without
    // darkening it more than GLASS_FILTER; the lead stops it. Far off it fades away.
    vec3 hue = c.rgb / max(max(c.r, c.g), max(c.b, 0.001));
    vec3 tint = came ? vec3(0.0) : mix(vec3(1.0), hue, glass_tint) * glass_filter;
    color = vec4(mix(tint, vec3(1.0), came ? fog : lamp_fog), 1.0);
  }else{
    vec3 n = vec3(-pane_axis.y, 0.0, pane_axis.x);
    if(dot(n, camera_position - v_world_position) < 0.0) n = -n;
    vec3 front = band_light(light_at(snap_position(v_world_position), n, 1.0, v_world_position + n * 0.05));
    vec3 front_lamp = lamp_part(front);
    vec3 glow = vec3(0.0);
    if(came){
      glow = c.rgb * ((front - front_lamp) * (1.0 - fog) + front_lamp * (1.0 - lamp_fog));
    }else{
      vec3 back = band_light(light_at(snap_position(v_world_position), -n, 1.0, v_world_position - n * 0.05));
      vec3 back_lamp = lamp_part(back);
      glow = c.rgb * (glass_reflect * ((front - front_lamp) * (1.0 - fog) + front_lamp * (1.0 - lamp_fog))
                      + glass_transmit * back_lamp * (1.0 - lamp_fog));
    }
    color = vec4(glow, 1.0);
  }
}")

;;; Placing.

(defun add-pane (container design low high)
  "Add a pane of stained glass DESIGN (HEXMAW.BLUEPRINT:*GLASS-DESIGNS*) whose solid is the box
from LOW to HIGH, its thinner side across it, to CONTAINER: the solid, the quad that draws it and,
with a torch near, its lamp. While a level is built: INDEX-SOLIDS runs after."
  (let* ((size (or (assoc design hexmaw.blueprint:*glass-designs* :test #'string=)
                   (error "No glass design ~s." design)))
         (w (- (vx high) (vx low))) (d (- (vz high) (vz low)))
         (along-x (< d w))
         (solid (make-solid (vx low) (vy low) (vz low) (vx high) (vy high) (vz high) 0 0 (surface-strike :glass)))
         (pane (make-instance 'pane :design design :low (vcopy low) :high (vcopy high)
                                    :along-x along-x :solid solid))
         (centre (pane-centre pane))
         (width (second size)) (height (third size))
         (sheet (make-instance 'glass-pane
                               :texture (// 'hexmaw (glass-look design :texture))
                               :axis (if along-x (vec2 1 0) (vec2 0 1))
                               :origin (vec2 (if along-x (vx low) (vz low)) (vy low))
                               :size (vec2 width height)
                               :location centre
                               :scaling (vec width height 1)
                               :orientation (if along-x (quat) (qfrom-angle +vy+ (float (/ pi 2) 0f0))))))
    (setf (pane-sheet pane) sheet)
    (vector-push-extend solid *solids*)
    (vector-push-extend pane *panes*)
    (enter sheet container)
    ;; Its lamp, on its darker side, as if the torches' light came through it.
    (when *pane-light-strength*
      (let ((n (pane-normal pane)))
        (flet ((torchlight (side)
                 ;; The torches that light this side of it, each by its nearness.
                 (let ((from (nv+ (v* n (* side 0.3)) centre)))
                   (loop for p across *torch-points*
                         for d = (vdistance p centre)
                         when (and (< d *pane-light-reach*) (clear-line-p from p))
                           sum (/ 1.0 (max 1.0 (* d d)))))))
          (let ((front (torchlight 1.0)) (back (torchlight -1.0)))
            (when (< 0.0 (max front back))
              (setf (pane-light pane) (nv+ (v* n (* (if (< front back) 1.0 -1.0) *pane-light-out*)) centre))
              (light-pane pane))))))
    pane))

(defun pane-lamp-color (pane)
  (v* (apply #'vec (glass-look (pane-design pane) :light)) *pane-light-strength*))

(defun light-pane (pane)
  "Light PANE's lamp: a lamp of another window's near where it hangs, its colour added to that one's."
  (when (and (pane-light pane) (not (pane-lamp pane)) *pane-light-strength*)
    (let ((near (loop for other across *panes*
                      for lamp = (pane-lamp other)
                      thereis (and lamp (< (vdistance (location lamp) (pane-light pane)) *pane-light-merge*) lamp))))
      (if near
          (progn (nv+ (color near) (pane-lamp-color pane))
                 (setf (pane-lamp pane) near))
          (setf (pane-lamp pane) (add-lamp (pane-light pane) (pane-lamp-color pane) *pane-light-radius*))))))

(defun douse-pane (pane)
  "Take PANE's colour out of its lamp, and the lamp away if no other window keeps it."
  (let ((lamp (pane-lamp pane)))
    (when lamp
      (setf (pane-lamp pane) NIL)
      (if (find lamp *panes* :key #'pane-lamp)
          (nv- (color lamp) (pane-lamp-color pane))
          (remove-lamp lamp)))))

;;; Breaking.

(defun remove-solid (s)
  "Take solid S out of *SOLIDS*, if it is there, and file the rest again."
  (let ((i (position s *solids*)))
    (when i
      (replace *solids* *solids* :start1 i :start2 (1+ i))
      (decf (fill-pointer *solids*))
      (index-solids))))

(defun shatter-pane (pane from)
  "Throw PANE's glass as shards, away from point FROM (both ways if NIL)."
  (let* ((low (pane-low pane)) (high (pane-high pane))
         (along-x (pane-along-x pane))
         (n (pane-normal pane))
         (centre (pane-centre pane))
         (side (if (and from (< 0 (v. n (v- centre from)))) 1.0 -1.0))
         (width (if along-x (- (vx high) (vx low)) (- (vz high) (vz low))))
         (height (- (vy high) (vy low)))
         (ramps (mapcar #'spark-ramp-index (glass-look (pane-design pane) :ramps)))
         (count (round (* *shards-per-m2* width height))))
    (dotimes (k count)
      (let* ((u (+ 0.04 (random (max 0.01 (- width 0.08)))))
             (y (+ (vy low) 0.04 (random (max 0.01 (- height 0.08)))))
             (x (if along-x (+ (vx low) u) (vx centre)))
             (z (if along-x (vz centre) (+ (vz low) u)))
             (back (< (random 1f0) *shard-back-share*))
             (out (* (if (or back (null from)) (if (< (random 1f0) 0.5) side (- side)) side)
                     (if back 0.4 1.0) (range-random *shard-speed*)))
             (across (- (random 1.2) 0.6))
             (vx (+ (* out (vx n)) (if along-x across 0.0)))
             (vz (+ (* out (vz n)) (if along-x 0.0 across)))
             (vy (- (random 1.4) 0.3)))
        (spawn-spark 4 (nth (random (length ramps)) ramps) x y z vx vy vz *grit-flight*
                     :chip (if (< (random 1f0) *shard-big-chance*) 2 1)
                     :tone (+ 1 (random 2))
                     :rest (range-random *shard-rest*))))))

(defun break-pane (pane &key from quiet)
  "Shatter PANE, from point FROM (where the blow came from, or NIL): its solid gone, its lamp out,
the blood on it dissolving, its shards thrown and its crash heard, unless QUIET. True if it broke."
  (unless (broken pane)
    (setf (broken pane) T
          (shown-broken (pane-sheet pane)) T)
    (remove-solid (pane-solid pane))
    (douse-pane pane)
    (dissolve-splats-in (pane-low pane) (pane-high pane) 0.05)
    (unless quiet
      (shatter-pane pane from)
      (play-sound :glass-shatter (pane-centre pane)))
    T))

(defun pane-distance (pane point)
  "Metres from POINT to the nearest point of PANE's box, and that point."
  (let* ((low (pane-low pane)) (high (pane-high pane))
         (q (flet ((within (lo x hi) (max lo (min x hi))))
              (vec (within (vx low) (vx point) (vx high))
                   (within (vy low) (vy point) (vy high))
                   (within (vz low) (vz point) (vz high))))))
    (values (vdistance q point) q)))

(defparameter *quake-glass-height* 2.5
  "Metres above the floor a quake shakes out a window at most: a storey up is out of its reach.")

(defun pane-reached-p (pane point)
  "True if a clear line runs from POINT to PANE's face: to its middle or a point halfway to a
corner, just off its face on POINT's side, out through the window's opening."
  (let* ((low (pane-low pane)) (high (pane-high pane))
         (centre (pane-centre pane))
         (n (pane-normal pane))
         (side (if (< 0 (v. n (v- point centre))) 1.0 -1.0))
         (half (/ (if (pane-along-x pane) (- (vx high) (vx low)) (- (vz high) (vz low))) 4))
         (rise (/ (- (vy high) (vy low)) 4)))
    (loop for (du dv) in '((0 0) (-1 -1) (1 -1) (-1 1) (1 1) (0 -1.6))
          thereis (let ((q (vec (+ (vx centre) (* side 0.15 (vx n)) (if (pane-along-x pane) (* du half) 0.0))
                                (+ (vy centre) (* dv rise))
                                (+ (vz centre) (* side 0.15 (vz n)) (if (pane-along-x pane) 0.0 (* du half))))))
                    (clear-line-p point q)))))

(defun strike-panes (point radius &key (from point) quake)
  "Break every intact pane within RADIUS metres of POINT that it reaches in a clear line (a burst,
a nova), or, for a QUAKE, every one standing over that floor whatever is between. Their shards
fly away from FROM."
  (let ((struck ()))
    (loop for pane across *panes*
          do (unless (broken pane)
               (when (and (<= (pane-distance pane point) radius)
                          (if quake
                              (< (- (float (vy point) 0f0) 1.0) (vy (pane-low pane)) (+ (vy point) *quake-glass-height*))
                              (pane-reached-p pane point)))
                 (push pane struck))))
    ;; Broken after, so one pane going doesn't open the line to one behind it.
    (dolist (pane struck) (break-pane pane :from from))
    struck))

(defparameter *body-glass-reach* 0.6
  "Metres out from a body, the way it was going, a pane may be for its impact to break it: the
window's sill stops the body short of the glass set into its wall.")

(defun strike-panes-by-body (feet radius height x z)
  "A body with FEET, RADIUS and HEIGHT was stopped going along X Z fast enough to be hurt: break
the panes it was flung into."
  (let ((len (sqrt (+ (* x x) (* z z)))))
    (when (< 1e-4 len)
      (loop for pane across *panes*
            do (unless (broken pane)
                 (dolist (share '(0.5 0.85))
                   (let ((point (vec (+ (vx feet) (* radius (/ x len)))
                                     (+ (vy feet) (* share height))
                                     (+ (vz feet) (* radius (/ z len))))))
                     (when (and (<= (pane-distance pane point) *body-glass-reach*)
                                (pane-reached-p pane point))
                       (break-pane pane :from feet)
                       (return)))))))))

;;; Saving and resetting.

(defun broken-pane-indices ()
  (loop for pane across *panes* for i from 0 when (broken pane) collect i))

(defun break-panes-at (indices)
  (dolist (i indices)
    (when (< -1 i (length *panes*))
      (break-pane (aref *panes* i) :quiet T))))

(defun restore-panes ()
  "Every broken pane whole again, for a new run."
  (let ((any NIL))
    (loop for pane across *panes*
          do (when (broken pane)
               (setf (broken pane) NIL
                     (shown-broken (pane-sheet pane)) NIL
                     any T)
               (vector-push-extend (pane-solid pane) *solids*)
               (light-pane pane)))
    (when any (index-solids))))
