(in-package #:hexmaw)

;;; Liquids: lava and water. A liquid is a box of volume, never a solid, and everything
;;; asks LIQUID-AT whether a point is in one. Lava lies in a sunken pit whose floor is an
;;; ordinary solid, so walking in and out is a step down and up. Water is deep: it fills
;;; the lower storey of a two-storey block (a pool, a canal) or a whole flooded passage,
;;; and the player swims in it. Its kind (*LIQUID-KINDS*) says what being in it does. The
;;; surface is a quad at the top: lava's (LIQUID-SURFACE) fullbright and warped like
;;; Quake's, water's (WATER-SURFACE) lit and see-through, drawn after everything else. A
;;; liquid that glows lights the pit with lamps over it.

(define-asset (hexmaw lava-flow) image #p"textures/lava-flow.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)

(define-asset (hexmaw water-ripple) image #p"textures/water.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)

(defparameter *liquid-kinds*
  '((:lava :damage 12.0 :speed 0.8 :jump 0.7 :texture lava-flow :surface liquid-surface
     :glow (2.4 1.0 0.3) :glow-radius 7.0 :glow-spacing 4.0 :glow-flicker 0.08)
    (:water :damage 0.0 :speed 1.0 :jump 1.0 :texture water-ripple :surface water-surface :swim T))
  "Per kind: :DAMAGE health per second to what stands in it, :SPEED the factor on walking
speed (kept through a jump from it until landing outside), :JUMP the factor on a jump's
speed from it (height goes with its square), :TEXTURE its surface and :SURFACE the class
that draws it, :SWIM true for a liquid deep enough to swim in, and :GLOW the colour of the
lamps over it (NIL for none), :GLOW-RADIUS their reach, one per :GLOW-SPACING metres of the
pool's length.")
(defparameter *water-alpha* 0.6 "How much of what lies beyond water's surface it hides.")
(defparameter *lava-tick* 0.4 "Seconds between the burns of something standing in lava.")
(defparameter *glow-height* 0.8 "Metres above a liquid's surface that its lamps hang.")

(defun liquid-property (kind key)
  (getf (rest (or (assoc kind *liquid-kinds*) (error "No liquid kind ~s." kind))) key))

(defclass liquid ()
  ((kind :initarg :kind :reader liquid-kind)
   (bounds :initarg :bounds :reader liquid-bounds
           :documentation "#(min-x min-y min-z max-x max-y max-z) as a solid's; max-y is the surface.")
   (glows :initform () :accessor liquid-glows :documentation "The lamps it hung over itself.")))

(defvar *liquids* (make-array 0 :adjustable T :fill-pointer T)
  "Every liquid in the level. BUILD-LEVEL empties it.")

(defun liquid-at (x y z)
  "The liquid the point X Y Z is in, or NIL."
  (loop for liquid across *liquids*
        for s = (liquid-bounds liquid)
        when (and (<= (aref s 0) x (aref s 3)) (<= (aref s 1) y (aref s 4)) (<= (aref s 2) z (aref s 5)))
          return liquid))

(defun swim-liquid-at (x y z)
  "The liquid one swims in (water) that the point X Y Z is in, or NIL."
  (let ((liquid (liquid-at x y z)))
    (and liquid (liquid-property (liquid-kind liquid) :swim) liquid)))

(defun water-surfaces (x z)
  "The surfaces of the deep water over the point X Z with room above them to float:
the nav grid's floors there (nav.lisp)."
  (let ((tops ()))
    (loop for liquid across *liquids*
          for s = (liquid-bounds liquid)
          do (when (and (liquid-property (liquid-kind liquid) :swim)
                        (<= (aref s 0) x (aref s 3)) (<= (aref s 2) z (aref s 5))
                        (fits-at-p x (aref s 4) z 0.0 *nav-min-height*))
               (pushnew (aref s 4) tops :test (lambda (a b) (< (abs (- a b)) 1f-3)))))
    tops))

(defun hazard-at (x y z)
  "Health per second that standing at X Y Z costs: the damage of the liquid there, or 0."
  (let ((liquid (liquid-at x y z)))
    (if liquid (liquid-property (liquid-kind liquid) :damage) 0.0)))

(defun burn-due (timer dt damage)
  "Run a burn TIMER, the seconds until the next burn may land, down by DT while standing in
something that does DAMAGE per second (0 out of it). Returns the timer's new value and the
damage due now, a whole number, or 0. A burn lands the moment one is allowed, so stepping
in burns at once and staying in burns every *LAVA-TICK*; out of it the timer only runs
down, so hopping out and back in doesn't burn sooner."
  (let ((timer (- timer dt)))
    (cond ((<= damage 0) (values (max 0.0 timer) 0))
          ((<= timer 0) (values (+ (max timer (- *lava-tick*)) *lava-tick*)
                                (max 1 (round (* damage *lava-tick*)))))
          (T (values timer 0)))))

(define-shader-entity liquid-sheet (lit-entity vertex-entity transformed-entity listener)
  ((vertex-array :initform (// 'hexmaw 'centered-quad))
   (surface-texture :initarg :surface-texture :reader surface-texture)
   (clock :initform 0.0 :accessor liquid-clock))
  (:documentation "A liquid's surface, a quad lying flat at its top."))

(defmethod stage :after ((surface liquid-sheet) (area staging-area))
  (stage (surface-texture surface) area))

(defmethod bind-textures :after ((surface liquid-sheet))
  (bind (surface-texture surface) :texture0))

(define-handler (liquid-sheet tick) (dt)
  (unless (frozen-p)
    ;; Wrapped, so it stays a small single-float; the shader's waves repeat by then.
    (setf (liquid-clock liquid-sheet) (mod (+ (liquid-clock liquid-sheet) dt) 1000.0))))

(defmethod render :before ((surface liquid-sheet) (program shader-program))
  (when (first-this-frame-p program)
    (set-fog-uniforms program)
    (setf (uniform program "surface_texture") 0)
    (setf (uniform program "texels_per_metre") (float *texels-per-metre* 0f0))
    (when (typep surface 'water-surface)
      (setf (uniform program "water_alpha") (float *water-alpha* 0f0))))
  (setf (uniform program "time") (float (liquid-clock surface) 0f0)))

(defgeneric late-rank (object)
  (:documentation "NIL for what the render pass draws in its usual order; for what it draws
after everything else (GAME-PASS, main.lisp), a rank, lower first: see-through surfaces (0),
which must cover what lies beyond them, then whole-screen tints (1, hud.lisp), which colour
all of it.")
  (:method (object) NIL))

(define-shader-entity liquid-surface (liquid-sheet) ()
  (:documentation "Lava's surface: opaque and glowing."))

(define-class-shader (liquid-surface :fragment-shader)
  "in vec3 v_world_position;
in vec3 v_view_position;
uniform sampler2D surface_texture;
uniform float texels_per_metre;
uniform float time;
out vec4 color;

void main(){
  // Laid flat in world XZ like a floor, swirled by crossed waves and drifting slowly.
  vec2 p = v_world_position.xz;
  vec2 st = p + 0.18 * sin(p.yx * 1.7 + time * vec2(0.9, 1.1)) + time * vec2(0.05, 0.03);
  vec3 c = texture(surface_texture, st * texels_per_metre / vec2(textureSize(surface_texture, 0))).rgb;
  // A slow throb that rolls across the pool.
  c *= 1.0 + 0.12 * sin(time * 1.7 + p.x * 0.8 + p.y * 0.6);
  // Its own light: it fogs as lamp light does, so it glows from far off.
  color = vec4(fog_lit(vec3(0.0), c, length(v_view_position)), 1.0);
}")

(define-shader-entity water-surface (liquid-sheet) ()
  (:documentation "Water's surface: lit like a floor and see-through, from above and below.
It writes no depth, so it is drawn last (LATE-RANK), over what lies beyond it."))

(defmethod late-rank ((surface water-surface)) 0)

(defmethod render :around ((surface water-surface) (program shader-program))
  (gl:disable :cull-face)
  (gl:depth-mask NIL)
  (call-next-method)
  (gl:depth-mask T)
  (gl:enable :cull-face))

(define-class-shader (water-surface :fragment-shader)
  "in vec3 v_world_position;
in vec3 v_view_position;
uniform sampler2D surface_texture;
uniform float texels_per_metre;
uniform float time;
uniform float water_alpha;
out vec4 color;

void main(){
  // Laid flat in world XZ like a floor, rippled by small crossed waves and drifting.
  vec2 p = v_world_position.xz;
  vec2 st = p + 0.06 * sin(p.yx * 2.3 + time * vec2(0.7, 0.9)) + time * vec2(0.02, 0.015);
  vec3 c = texture(surface_texture, st * texels_per_metre / vec2(textureSize(surface_texture, 0))).rgb;
  // Lit on the side it is seen from, as a floor or, from under the water, a ceiling.
  vec3 n = vec3(0.0, (camera_position.y >= v_world_position.y) ? 1.0 : -1.0, 0.0);
  vec3 light = band_light(light_at(snap_position(v_world_position), n, 1.0, v_world_position + n * 0.05));
  vec3 lamp = lamp_part(light);
  color = vec4(fog_lit(c * (light - lamp), c * lamp, length(v_view_position)), water_alpha);
}")

(defun add-liquid (container kind x0 y0 z0 x1 y1 z1)
  "Add a liquid of KIND filling the box between the two corners, its surface the top, to
CONTAINER: the volume, its surface and, if it glows, the lamps over it."
  (let* ((s (make-solid x0 y0 z0 x1 y1 z1))
         (w (- (aref s 3) (aref s 0))) (d (- (aref s 5) (aref s 2)))
         (top (aref s 4))
         (liquid (make-instance 'liquid :kind kind :bounds s)))
    (vector-push-extend liquid *liquids*)
    ;; On the automap, a thin slab at the surface.
    (add-map-piece container (// 'trial 'unit-cube)
                   (vec (/ (+ (aref s 0) (aref s 3)) 2) (- top 0.02) (/ (+ (aref s 2) (aref s 5)) 2))
                   (quat) (vec w 0.04 d)
                   (vec (aref s 0) (- top 0.04) (aref s 2)) (vec (aref s 3) top (aref s 5)) :surface kind)
    ;; A liquid that fills its space to a ceiling (a flooded passage) shows no surface.
    (unless (solid-overlapping (/ (+ (aref s 0) (aref s 3)) 2) (+ top 0.01) (/ (+ (aref s 2) (aref s 5)) 2) 0.05 0.05)
      (enter (make-instance (liquid-property kind :surface)
                            :surface-texture (// 'hexmaw (liquid-property kind :texture))
                            :location (vec (/ (+ (aref s 0) (aref s 3)) 2) top (/ (+ (aref s 2) (aref s 5)) 2))
                            :scaling (vec w d 1)
                            :orientation (qfrom-angle +vx+ (float (- (/ pi 2)) 0f0)))
             container))
    (let ((glow (liquid-property kind :glow)))
      (when glow
        ;; Lamps spaced along the pool's longer side, down its middle. An irregular pool
        ;; is many boxes side by side, so a lamp nearer than the spacing to one already
        ;; hung over this kind is left out, its colour added to that one's: every lamp
        ;; sent costs every lit pixel, and lamps that close lit as one brighter lamp.
        (let* ((spacing (liquid-property kind :glow-spacing))
               (along-x (<= d w))
               (len (if along-x w d))
               (n (max 1 (ceiling len spacing))))
          (dotimes (i n)
            (let* ((f (/ (+ i 0.5) n))
                   (at (if along-x
                           (vec (+ (aref s 0) (* f w)) (+ top *glow-height*) (/ (+ (aref s 2) (aref s 5)) 2))
                           (vec (/ (+ (aref s 0) (aref s 3)) 2) (+ top *glow-height*) (+ (aref s 2) (* f d))))))
              (let ((near NIL) (nearest spacing))
                (loop for other across *liquids*
                      when (eq (liquid-kind other) kind)
                        do (dolist (lamp (liquid-glows other))
                             (let ((distance (vdistance (location lamp) at)))
                               (when (< distance nearest)
                                 (setf near lamp nearest distance)))))
                (if near
                    (nv+ (color near) (apply #'vec glow))
                    (push (add-lamp at (apply #'vec glow) (liquid-property kind :glow-radius)
                                    :flicker (liquid-property kind :glow-flicker))
                          (liquid-glows liquid)))))))))))

(defun add-lava (container x0 z0 x1 z1 &key (floor 0.0)
                                            (depth hexmaw.blueprint:*lava-depth*)
                                            (surface hexmaw.blueprint:*lava-surface*))
  "Dig a lava pit from X0 Z0 to X1 Z1 into a floor at height FLOOR, whose slab is 0.5 m
thick: the pit's floor DEPTH below, the lava's surface SURFACE below, as a blueprint's
lava. Leave the hole in the floor around it."
  (add-box container x0 (- floor 0.5) z0 x1 (- floor depth) z1 :surface :floor)
  (add-liquid container :lava x0 (- floor depth) z0 x1 (- floor surface) z1))

;;; Ambience (sound.lisp): every torch crackles, every lava pool bubbles and every pool of
;;; water laps, but only the nearest few of each sound, their loops moved onto them a few
;;; times a second; under it all, the room tone.

(defparameter *ambient-sources*
  '((:torch-crackle :source :torches :voices 3 :reach 12.0 :volume 0.6)
    (:lava-bubble :source :lava :voices 3 :reach 18.0 :volume 0.8)
    (:water-lap :source :water :voices 2 :reach 14.0 :volume 0.6))
  "Per ambient loop: what sounds it (:TORCHES, or a liquid's kind, heard from the nearest point
of its surface), how many of the nearest sources at most (8), from how far, how loud.")
(defparameter *room-tone* :dungeon-drips "The loop under everything in play, or NIL.")
(defparameter *room-tone-volume* 0.3)
(defparameter *ambience-interval* 0.25 "Seconds between choosing the nearest sources again.")

(defvar *ambience-timer* 0.0)
(defvar *ambient-near* (let ((v (make-array 8))) (dotimes (i 8 v) (setf (aref v i) (vec3))))
  "Scratch: the nearest sources found, nearest first.")
(defvar *ambient-distances* (make-array 8 :element-type 'single-float :initial-element 0f0)
  "Scratch: their squared distances.")

(defun note-ambient-source (n count x y z d2)
  "Keep the point X Y Z, D2 square metres off, among the N nearest of the COUNT kept so far.
Returns how many are kept now."
  (let ((j (if (< count n) count (1- n)))
        (near *ambient-near*) (dist *ambient-distances*))
    (cond ((or (< count n) (< d2 (aref dist j)))
           (loop while (and (< 0 j) (< d2 (aref dist (1- j))))
                 do (setf (aref dist j) (aref dist (1- j)))
                    (v<- (aref near j) (aref near (1- j)))
                    (decf j))
           (setf (aref dist j) (float d2 0f0))
           (let ((p (aref near j)))
             (setf (vx p) (float x 0f0) (vy p) (float y 0f0) (vz p) (float z 0f0)))
           (min n (1+ count)))
          (T count))))

(defun update-ambience (dt)
  "Every *AMBIENCE-INTERVAL*, put each ambient loop of *AMBIENT-SOURCES* on its nearest sources
in reach of the player's ear, and keep the room tone going (quiet under water)."
  (when (and *player* (<= (decf *ambience-timer* dt) 0.0))
    (setf *ambience-timer* *ambience-interval*)
    (let* ((ear (location *player*))
           (ex (vx ear)) (ey (vy ear)) (ez (vz ear)))
      (when *room-tone*
        (ambient-voice *room-tone* 0 ear (if *eye-underwater* 0.0 *room-tone-volume*)))
      (loop for (name . properties) in *ambient-sources*
            do (destructuring-bind (&key source voices reach volume) properties
                 (let ((n (min voices 8)) (count 0) (r2 (* reach reach)))
                   (flet ((consider (x y z)
                            (let ((d2 (+ (expt (- x ex) 2) (expt (- y ey) 2) (expt (- z ez) 2))))
                              (when (< d2 r2)
                                (setf count (note-ambient-source n count x y z d2))))))
                     (declare (dynamic-extent #'consider))
                     (if (eq source :torches)
                         (loop for p across *torch-points*
                               do (consider (vx p) (vy p) (vz p)))
                         (loop for liquid across *liquids*
                               for b = (liquid-bounds liquid)
                               do (when (eq (liquid-kind liquid) source)
                                    (consider (max (aref b 0) (min ex (aref b 3)))
                                              (aref b 4)
                                              (max (aref b 2) (min ez (aref b 5))))))))
                   (dotimes (i count)
                     (ambient-voice name i (aref *ambient-near* i) volume))
                   (drop-ambient-voices name count)))))))
