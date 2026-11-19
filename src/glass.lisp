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

;; Each design's pieces (tools/make_texture.py --glass): which shard every texel goes with.
(define-asset (hexmaw glass-lancet-flame-pieces) image #p"textures/glass/glass-lancet-flame-pieces.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :clamp-to-edge)
(define-asset (hexmaw glass-lancet-frost-pieces) image #p"textures/glass/glass-lancet-frost-pieces.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :clamp-to-edge)
(define-asset (hexmaw glass-rose-maw-pieces) image #p"textures/glass/glass-rose-maw-pieces.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :clamp-to-edge)
(define-asset (hexmaw glass-quarry-pieces) image #p"textures/glass/glass-quarry-pieces.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :clamp-to-edge)

(defparameter *glass-tint* 0.85 "How strongly a pane colours what is seen through it, 0 to 1.")
(defparameter *glass-filter* 0.75 "How much of the light behind a pane comes through its glass.")
(defparameter *glass-reflect* 0.35 "How much of the light on its near face a pane's glass gives back.")
(defparameter *glass-transmit* 1.6 "How much of the lamps' light on its far face shines through a pane.")

(defparameter *pane-light-strength* 0.35
  "How bright the lamp a pane hangs on its darker side is, by its design's colour; NIL for none.")
(defparameter *pane-light-radius* 3.5)
(defparameter *pane-light-reach* 8.0 "Metres from a pane a torch makes it hang its lamp, on the far side.")
(defparameter *pane-light-out* 1.0 "Metres out from the pane its lamp hangs.")
(defparameter *pane-light-merge* 2.5
  "Metres within which windows share one lamp, its colour their colours added: every lamp sent
costs every lit pixel, and the chapel's four came to 0.9 ms of GPU a frame.")

(defparameter *glitter-per-m2* 10 "Specks of glass dust (spark-pool grit) a pane throws besides its shards, a square metre.")
(defparameter *glitter-rest* '(1.5 3.0) "Seconds a speck lies before it dissolves.")

(defparameter *max-glass-shards* 640 "Shards a design's pool holds; past that a new one takes the oldest's slot.")
(defparameter *shard-speed* '(0.6 2.6) "M/s shards fly from a pane at, the way the blow went.")
(defparameter *shard-burst* 2.0 "How much faster the shards nearest where a blow struck fly, at most.")
(defparameter *shard-back-share* 0.2 "Share of the shards that fall back toward the blow, slowly.")
(defparameter *shard-spin* '(3.0 14.0) "Radians a second a shard tumbles at.")
(defparameter *shard-gravity* 9.8)
(defparameter *shard-drag* 0.4 "Fraction of its speed a shard loses a second to the air.")
(defparameter *shard-bounce* 0.25 "Fraction of its speed into a surface a shard bounces back with.")
(defparameter *shard-friction* 0.45 "Fraction of its speed along the floor a shard keeps when it bounces.")
(defparameter *shard-rest-speed* 1.5 "A shard striking the floor slower than this, in m/s, lies there.")
(defparameter *shard-lie* '(5.0 9.0) "Seconds a shard lies on the floor before it dissolves.")
(defparameter *shard-dissolve* 1.0 "Seconds a shard takes to dissolve, a texel at a time.")
(defparameter *shard-flight* 5.0 "Seconds a shard flies before it goes, if it lands nowhere.")
(defparameter *shard-glint* 0.3 "Of its own colour a shard's glass shows lit by nothing, so it glints in the dark.")

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
   (piece-map :initarg :piece-map :reader piece-map
              :documentation "Which shard each texel flies off as; piece 0 stays in the frame.")
   (axis :initarg :axis :reader pane-axis :documentation "Its direction across, in XZ.")
   (origin :initarg :origin :reader pane-origin
           :documentation "Where its texture starts: along its axis, and its bottom's height.")
   (size :initarg :size :reader pane-size :documentation "Its width and height in metres.")
   (shown-broken :initform NIL :accessor shown-broken)
   (rank :initform 0.35 :accessor pane-rank))
  (:documentation "A pane of stained glass: a quad standing in its window."))

(defmethod stage :after ((sheet glass-pane) (area staging-area))
  (stage (glass-texture sheet) area)
  (stage (piece-map sheet) area))

(defmethod bind-textures :after ((sheet glass-pane))
  (bind (glass-texture sheet) :texture0)
  (bind (piece-map sheet) :texture1))

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
          (uniform program "piece_map") 1))
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
uniform sampler2D piece_map;
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
out vec4 color;

void main(){
  // Laid on the pane a texel of the 64-a-metre grid at a time, its bottom row at the sill.
  vec2 texels = floor(pane_size * texels_per_metre + 0.5);
  vec2 uv = vec2(dot(v_world_position.xz, pane_axis) - pane_origin.x, v_world_position.y - pane_origin.y);
  vec2 t = clamp(floor(uv * texels_per_metre), vec2(0.0), texels - 1.0);
  vec4 c = texture(glass_texture, (t + 0.5) / texels);
  if(pane_broken != 0){
    // An empty frame: only what its shards left, its lead and teeth of glass (piece 0).
    vec4 m = texelFetch(piece_map, ivec2(t), 0);
    if(0.5 < m.r * 255.0 + m.g * 255.0 * 256.0) discard;
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
                               :piece-map (// 'hexmaw (intern (format NIL "~a-PIECES" (glass-look design :texture)) '#:hexmaw))
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
  "Throw PANE's glass as its shards and a little glitter, away from point FROM (both ways if NIL)."
  (let* ((low (pane-low pane)) (high (pane-high pane))
         (along-x (pane-along-x pane))
         (n (pane-normal pane))
         (centre (pane-centre pane))
         (side (if (and from (< 0 (v. n (v- centre from)))) 1.0 -1.0))
         (width (if along-x (- (vx high) (vx low)) (- (vz high) (vz low))))
         (height (- (vy high) (vy low)))
         (ramps (mapcar #'spark-ramp-index (glass-look (pane-design pane) :ramps))))
    (spawn-shards pane from side)
    (dotimes (k (round (* *glitter-per-m2* width height)))
      (let* ((u (+ 0.04 (random (max 0.01 (- width 0.08)))))
             (y (+ (vy low) 0.04 (random (max 0.01 (- height 0.08)))))
             (out (* side (range-random *shard-speed*)))
             (across (- (random 1.2) 0.6)))
        (spawn-spark 4 (nth (random (length ramps)) ramps)
                     (if along-x (+ (vx low) u) (vx centre)) y (if along-x (vz centre) (+ (vz low) u))
                     (+ (* out (vx n)) (if along-x across 0.0)) (- (random 1.4) 0.3) (+ (* out (vz n)) (if along-x 0.0 across))
                     *grit-flight* :tone (+ 1 (random 2)) :rest (range-random *glitter-rest*))))))

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

;;; Shards: the pieces a pane breaks into, each a piece of its own glass between the lead (and the
;;; big ones cracked), as tools/make_texture.py --glass cut it, tumbling as it flies, bouncing, lying
;;; flat on the floor a while, then dissolving a texel at a time. One pool a design, drawn in one
;;; call: each shard a quad of its piece's box in its pane's texture, the texels of other pieces cut
;;; away by the piece map, lit as it faces. Plain arrays, nothing allocated a frame, not saved.

(defvar *shard-pools* () "Each design's SHARD-POOL in the scene, as (design . pool).")

(defparameter *shard-vertex-floats* 10 "Position (3), texel (2), piece (1), normal (3), dissolve (1).")

(defun glass-pieces (design)
  "DESIGN's pieces' boxes, (X0 Y0 X1 Y1) in texels from the bottom left, as a simple-vector."
  (with-open-file (in (data-path (format NIL "textures/glass/glass-~a.lisp" design)))
    (coerce (getf (let ((*read-eval* NIL)) (read in)) :pieces) 'simple-vector)))

(define-shader-entity shard-pool (lit-entity renderable listener)
  ((design :initarg :design :reader pool-design)
   (texture :initarg :texture :reader glass-texture)
   (piece-map :initarg :piece-map :reader piece-map)
   (pieces :initarg :pieces :reader pool-pieces)
   (size :reader pool-size)
   (cursor :initform 0 :accessor pool-cursor)
   (state :reader pool-state :documentation "Per shard: 0 free, 1 flying, 2 lying, 3 dissolving.")
   (piece :reader pool-piece :documentation "Per shard: its piece, from 1.")
   (bounces :reader pool-bounces)
   (positions :reader pool-positions :documentation "Per shard: its middle.")
   (velocities :reader pool-velocities)
   (axes :reader pool-axes :documentation "Per shard: its texture's across and up in the world, 6 floats.")
   (spins :reader pool-spins :documentation "Per shard: the axis it tumbles about, times radians a second.")
   (ages :reader pool-ages)
   (lives :reader pool-lives)
   (data :reader pool-data)
   (vbo :reader pool-vbo)
   (vao :reader pool-vao)))

(defmethod initialize-instance :after ((pool shard-pool) &key)
  (let* ((n *max-glass-shards*)
         (data (make-array (* n 6 *shard-vertex-floats*) :element-type 'single-float :initial-element 0f0))
         (vbo (make-instance 'vertex-buffer :buffer-data data :data-usage :stream-draw))
         (stride (* 4 *shard-vertex-floats*)))
    (flet ((floats (k) (make-array (* k n) :element-type 'single-float :initial-element 0f0)))
      (setf (slot-value pool 'size) n
            (slot-value pool 'state) (make-array n :element-type '(unsigned-byte 8) :initial-element 0)
            (slot-value pool 'piece) (make-array n :element-type '(unsigned-byte 16) :initial-element 0)
            (slot-value pool 'bounces) (make-array n :element-type '(unsigned-byte 8) :initial-element 0)
            (slot-value pool 'positions) (floats 3)
            (slot-value pool 'velocities) (floats 3)
            (slot-value pool 'axes) (floats 6)
            (slot-value pool 'spins) (floats 3)
            (slot-value pool 'ages) (floats 1)
            (slot-value pool 'lives) (floats 1)))
    (setf (slot-value pool 'data) data
          (slot-value pool 'vbo) vbo
          (slot-value pool 'vao) (make-instance 'vertex-array
                                                :vertex-form :triangles
                                                :bindings `((,vbo :size 3 :offset 0 :stride ,stride :index 0)
                                                            (,vbo :size 2 :offset 12 :stride ,stride :index 1)
                                                            (,vbo :size 1 :offset 20 :stride ,stride :index 2)
                                                            (,vbo :size 3 :offset 24 :stride ,stride :index 3)
                                                            (,vbo :size 1 :offset 36 :stride ,stride :index 4))))))

(defmethod stage :after ((pool shard-pool) (area staging-area))
  (stage (pool-vao pool) area)
  (stage (glass-texture pool) area)
  (stage (piece-map pool) area))

(defmethod bind-textures :after ((pool shard-pool))
  (bind (glass-texture pool) :texture0)
  (bind (piece-map pool) :texture1))

(defun add-shard-pools (scene)
  "A shard pool for each design, entered into SCENE (SETUP-SCENE)."
  (setf *shard-pools*
        (loop for (design . look) in *glass-looks*
              collect (let ((pool (make-instance 'shard-pool
                                                 :design design
                                                 :texture (// 'hexmaw (getf look :texture))
                                                 :piece-map (// 'hexmaw (intern (format NIL "~a-PIECES" (getf look :texture)) '#:hexmaw))
                                                 :pieces (glass-pieces design))))
                        (enter pool scene)
                        (cons design pool)))))

(defun clear-shards ()
  (loop for (nil . pool) in *shard-pools*
        do (fill (pool-state pool) 0)))

(defun shard-slot (pool)
  "The next free slot of POOL, or the next one whatever it holds."
  (let* ((state (pool-state pool))
         (n (pool-size pool))
         (start (pool-cursor pool))
         (i (or (loop for k from 0 below n
                      for j = (mod (+ start k) n)
                      when (= 0 (aref state j)) return j)
                start)))
    (setf (pool-cursor pool) (mod (1+ i) n))
    i))

(defun spawn-shards (pane from side)
  "Throw every piece of PANE from where it is in the pane, SIDE (1 or -1) along its normal, the
nearest to where the blow from FROM struck the fastest."
  (let ((pool (cdr (assoc (pane-design pane) *shard-pools* :test #'string=))))
    (when pool
      (let* ((along-x (pane-along-x pane))
             (low (pane-low pane))
             (centre (pane-centre pane))
             (n (pane-normal pane))
             (tpm (float *texels-per-metre* 0f0))
             ;; The pane's texture runs along +X or +Z from its low corner, and up from its sill.
             (ox (if along-x (vx low) (vx centre)))
             (oz (if along-x (vz centre) (vz low)))
             (oy (vy low))
             (ux (if along-x 1f0 0f0)) (uz (if along-x 0f0 1f0))
             ;; Where the blow struck, in the pane's metres, if it came from a point.
             (hit-u (and from (- (if along-x (vx from) (vz from)) (if along-x ox oz))))
             (hit-v (and from (- (vy from) oy))))
        (loop for box across (pool-pieces pool)
              for piece from 1
              do (destructuring-bind (x0 y0 x1 y1) box
                   (let* ((u (/ (+ x0 x1 1) 2 tpm))
                          (v (/ (+ y0 y1 1) 2 tpm))
                          (i (shard-slot pool))
                          (b (* 3 i))
                          (near (if hit-u
                                    (exp (- (/ (+ (expt (- u hit-u) 2) (expt (- v (max 0.3 (min hit-v 2.0))) 2)) 0.4)))
                                    0.5))
                          (back (< (random 1f0) *shard-back-share*))
                          (out (* (if back (* -0.35 side) side)
                                  (range-random *shard-speed*) (+ 1.0 (* *shard-burst* near))))
                          (across (- (random 1.0) 0.5))
                          (p (pool-positions pool)) (vel (pool-velocities pool))
                          (axes (pool-axes pool)) (spins (pool-spins pool)))
                     (setf (aref (pool-state pool) i) 1
                           (aref (pool-piece pool) i) piece
                           (aref (pool-bounces pool) i) 0
                           (aref (pool-ages pool) i) 0f0
                           (aref (pool-lives pool) i) (float *shard-flight* 0f0)
                           (aref p b) (float (+ ox (* ux u)) 0f0)
                           (aref p (+ b 1)) (float (+ oy v) 0f0)
                           (aref p (+ b 2)) (float (+ oz (* uz u)) 0f0)
                           (aref vel b) (float (+ (* out (vx n)) (* across ux)) 0f0)
                           (aref vel (+ b 1)) (float (- (random 1.2) 0.2) 0f0)
                           (aref vel (+ b 2)) (float (+ (* out (vz n)) (* across uz)) 0f0))
                     ;; Its texture across and up, as the pane's.
                     (let ((a (* 6 i)))
                       (setf (aref axes a) ux (aref axes (+ a 1)) 0f0 (aref axes (+ a 2)) uz
                             (aref axes (+ a 3)) 0f0 (aref axes (+ a 4)) 1f0 (aref axes (+ a 5)) 0f0))
                     ;; Tumbling about a random axis.
                     (let* ((ax (- (random 2f0) 1f0)) (ay (- (random 2f0) 1f0)) (az (- (random 2f0) 1f0))
                            (len (max 1f-3 (sqrt (+ (* ax ax) (* ay ay) (* az az)))))
                            (rate (/ (float (range-random *shard-spin*) 0f0) len)))
                       (setf (aref spins b) (* ax rate) (aref spins (+ b 1)) (* ay rate) (aref spins (+ b 2)) (* az rate))))))))))

(declaim (inline turn-axis))
(defun turn-axis (axes a wx wy wz)
  "Turn the vector at AXES[A..A+2] by the small rotation W (axis times angle), keeping its length."
  (declare (type (simple-array single-float (*)) axes) (type fixnum a) (type single-float wx wy wz))
  (let* ((x (aref axes a)) (y (aref axes (+ a 1))) (z (aref axes (+ a 2)))
         (cx (- (* wy z) (* wz y))) (cy (- (* wz x) (* wx z))) (cz (- (* wx y) (* wy x)))
         (nx (+ x cx)) (ny (+ y cy)) (nz (+ z cz))
         (k (/ (sqrt (+ (* x x) (* y y) (* z z))) (max 1f-6 (sqrt (+ (* nx nx) (* ny ny) (* nz nz)))))))
    (setf (aref axes a) (* k nx) (aref axes (+ a 1)) (* k ny) (aref axes (+ a 2)) (* k nz))))

(defun lay-shard (pool i)
  "Shard I of POOL lies flat on the floor, turned at random."
  (let* ((axes (pool-axes pool)) (a (* 6 i))
         (yaw (random #.(float (* 2 pi) 0f0)))
         (c (cos yaw)) (s (sin yaw)))
    (setf (aref axes a) c (aref axes (+ a 1)) 0f0 (aref axes (+ a 2)) s
          (aref axes (+ a 3)) (- s) (aref axes (+ a 4)) 0f0 (aref axes (+ a 5)) c)))

(defun step-shards (pool dt)
  (declare (type single-float dt))
  (let ((state (pool-state pool))
        (bounces (pool-bounces pool))
        (p (pool-positions pool))
        (v (pool-velocities pool))
        (axes (pool-axes pool))
        (spins (pool-spins pool))
        (ages (pool-ages pool))
        (lives (pool-lives pool))
        (keep (max 0f0 (- 1f0 (* (float *shard-drag* 0f0) dt))))
        (fall (* (float *shard-gravity* 0f0) dt))
        (bounce (float *shard-bounce* 0f0))
        (friction (float *shard-friction* 0f0))
        (rest (float *shard-rest-speed* 0f0))
        (dissolve (float *shard-dissolve* 0f0)))
    (declare (type (simple-array (unsigned-byte 8) (*)) state bounces)
             (type (simple-array single-float (*)) p v axes spins ages lives)
             (type single-float keep fall bounce friction rest dissolve))
    (dotimes (i (pool-size pool))
      (let ((st (aref state i)) (b (* 3 i)))
        (unless (= 0 st)
          (let ((age (incf (aref ages i) dt)))
            (declare (type single-float age))
            (case st
              (1
               (decf (aref v (+ b 1)) fall)
               (dotimes (k 3) (setf (aref v (+ b k)) (* keep (aref v (+ b k)))))
               (let ((wx (* dt (aref spins b))) (wy (* dt (aref spins (+ b 1)))) (wz (* dt (aref spins (+ b 2)))))
                 (turn-axis axes (* 6 i) wx wy wz)
                 (turn-axis axes (+ 3 (* 6 i)) wx wy wz))
               (let* ((nx (+ (aref p b) (* dt (aref v b))))
                      (ny (+ (aref p (+ b 1)) (* dt (aref v (+ b 1)))))
                      (nz (+ (aref p (+ b 2)) (* dt (aref v (+ b 2)))))
                      (s (solid-at nx ny nz)))
                 (cond ((< (aref lives i) age) (setf (aref state i) 0))
                       ((liquid-at nx ny nz) (setf (aref state i) 0))
                       ((null s) (setf (aref p b) nx (aref p (+ b 1)) ny (aref p (+ b 2)) nz))
                       (T
                        (case (bounce-spark pool i s nx ny nz bounce friction
                                            (if (< 1 (aref bounces i)) 1f6 rest))
                          (:gone (setf (aref state i) 0))
                          (:rest (setf (aref state i) 2 (aref ages i) 0f0
                                       (aref lives i) (float (range-random *shard-lie*) 0f0))
                           (incf (aref p (+ b 1)) 0.003)
                           (lay-shard pool i))
                          (T (setf (aref bounces i) (min 255 (1+ (aref bounces i))))
                           ;; A bounce takes most of its spin.
                           (dotimes (k 3) (setf (aref spins (+ b k)) (* 0.5 (aref spins (+ b k)))))))))))
              (2 (when (< (aref lives i) age) (setf (aref state i) 3 (aref ages i) 0f0)))
              (3 (when (< dissolve age) (setf (aref state i) 0))))))))))

(define-handler (shard-pool tick) (dt)
  (unless (frozen-p)
    (step-shards shard-pool (float (min dt 0.05) 0f0))))

(defun write-shard-vertices (pool)
  "Write every shard's quad into POOL's vertex data. Returns the vertex count."
  (let* ((state (pool-state pool))
         (pieces (pool-pieces pool))
         (piece (pool-piece pool))
         (p (pool-positions pool))
         (axes (pool-axes pool))
         (ages (pool-ages pool))
         (data (pool-data pool))
         (stride *shard-vertex-floats*)
         (tpm (float *texels-per-metre* 0f0))
         (dissolve (float *shard-dissolve* 0f0))
         (corners *spark-corners*)
         (k 0))
    (declare (type (simple-array (unsigned-byte 8) (*)) state corners)
             (type (simple-array (unsigned-byte 16) (*)) piece)
             (type (simple-array single-float (*)) p axes ages data)
             (type simple-vector pieces)
             (type single-float tpm dissolve)
             (type fixnum k stride))
    (dotimes (i (pool-size pool))
      (let ((st (aref state i)))
        (unless (= 0 st)
          (let* ((id (aref piece i))
                 (box (svref pieces (1- id)))
                 (x0 (float (the fixnum (first box)) 0f0)) (y0 (float (the fixnum (second box)) 0f0))
                 (x1 (+ 1f0 (the fixnum (third box)))) (y1 (+ 1f0 (the fixnum (fourth box))))
                 (cx (* 0.5 (+ x0 x1))) (cy (* 0.5 (+ y0 y1)))
                 (b (* 3 i)) (a (* 6 i))
                 (ux (aref axes a)) (uy (aref axes (+ a 1))) (uz (aref axes (+ a 2)))
                 (vx (aref axes (+ a 3))) (vy (aref axes (+ a 4))) (vz (aref axes (+ a 5)))
                 (nx (- (* uy vz) (* uz vy))) (ny (- (* uz vx) (* ux vz))) (nz (- (* ux vy) (* uy vx)))
                 (fade (if (= st 3) (min 1f0 (/ (aref ages i) dissolve)) 0f0)))
            (declare (type single-float x0 y0 x1 y1 cx cy fade))
            (loop for c from 0 below 12 by 2
                  for tx = (if (= 0 (aref corners c)) x0 x1)
                  for ty = (if (= 0 (aref corners (1+ c))) y0 y1)
                  for du = (/ (- tx cx) tpm)
                  for dv = (/ (- ty cy) tpm)
                  for o = (* k stride)
                  do (setf (aref data o) (+ (aref p b) (* du ux) (* dv vx))
                           (aref data (+ o 1)) (+ (aref p (+ b 1)) (* du uy) (* dv vy))
                           (aref data (+ o 2)) (+ (aref p (+ b 2)) (* du uz) (* dv vz))
                           (aref data (+ o 3)) tx
                           (aref data (+ o 4)) ty
                           (aref data (+ o 5)) (float id 0f0)
                           (aref data (+ o 6)) nx
                           (aref data (+ o 7)) ny
                           (aref data (+ o 8)) nz
                           (aref data (+ o 9)) fade)
                     (incf k))))))
    k))

(defmethod render ((pool shard-pool) (program shader-program))
  (let ((count (write-shard-vertices pool)))
    (when (< 0 count)
      (update-buffer-data (pool-vbo pool) (pool-data pool) :count (* count *shard-vertex-floats* 4))
      (setf (uniform program "view_matrix") (view-matrix))
      (setf (uniform program "projection_matrix") (projection-matrix))
      (set-fog-uniforms program)
      (setf (uniform program "light_snap") (float *sprite-light-snap* 0f0))
      (setf (uniform program "light_bands") (float *sprite-light-bands* 0f0))
      (setf (uniform program "glass_texture") 0
            (uniform program "piece_map") 1
            (uniform program "glint") (float *shard-glint* 0f0)
            (uniform program "eye") (location (camera (scene +main+))))
      (gl:disable :cull-face)
      (render-array (pool-vao pool) :vertex-count count)
      (gl:enable :cull-face))))

(define-class-shader (shard-pool :vertex-shader)
  "layout (location = 0) in vec3 position;
layout (location = 1) in vec2 in_texel;
layout (location = 2) in float in_piece;
layout (location = 3) in vec3 in_normal;
layout (location = 4) in float in_fade;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;
out vec2 v_texel;
flat out float v_piece;
out vec3 v_world_position;
out vec3 v_view_position;
flat out vec3 v_normal;
flat out float v_fade;

void main(){
  vec4 view_position = view_matrix * vec4(position, 1.0);
  gl_Position = projection_matrix * view_position;
  v_texel = in_texel;
  v_piece = in_piece;
  v_world_position = position;
  v_view_position = view_position.xyz;
  v_normal = in_normal;
  v_fade = in_fade;
}")

(define-class-shader (shard-pool :fragment-shader)
  "in vec2 v_texel;
flat in float v_piece;
in vec3 v_world_position;
in vec3 v_view_position;
flat in vec3 v_normal;
flat in float v_fade;
uniform sampler2D glass_texture;
uniform sampler2D piece_map;
uniform float glint;
uniform vec3 eye;
out vec4 color;

void main(){
  ivec2 size = textureSize(piece_map, 0);
  ivec2 t = clamp(ivec2(floor(v_texel)), ivec2(0), size - 1);
  vec4 m = texelFetch(piece_map, t, 0);
  float id = floor(m.r * 255.0 + 0.5) + 256.0 * floor(m.g * 255.0 + 0.5);
  if(abs(id - v_piece) > 0.5) discard;
  // Dissolving: its texels drop out in a fixed random order.
  if(v_fade > 0.0 && fract(sin(dot(vec2(t) + v_piece, vec2(12.9898, 78.233))) * 43758.5453) < v_fade) discard;
  vec4 c = texelFetch(glass_texture, t, 0);
  bool came = 0.75 < c.a;
  vec3 n = normalize(v_normal);
  if(dot(n, eye - v_world_position) < 0.0) n = -n;
  vec3 light = band_light(light_at(snap_position(v_world_position), n, 0.6, v_world_position + n * 0.05));
  vec3 lamp = lamp_part(light);
  // Not a ternary inside a sum: Trial's shader printer drops its brackets.
  float shine = came ? 0.0 : glint;
  vec3 glow = c.rgb * (lamp + shine);
  color = vec4(fog_lit(c.rgb * (light - lamp), glow, length(v_view_position)), 1.0);
}")

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
