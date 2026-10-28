(in-package #:hexmaw)

;;; Blood: drops sprayed from a wound, flying under gravity, that stay where they land
;;; as splats on the floor or a wall. Every particle lives in one BLOOD-POOL, entered
;;; into the scene once: plain arrays, reused oldest first, whose quads are written into
;;; one vertex buffer each frame and drawn in one call, so nothing allocates per frame.
;;; Drops face the camera plane; splats lie flat on their surface. Both are lit like the
;;; level (LIGHT_AT) and fogged. The frames are tools/draw_blood.py's strip: drops 0 to 3,
;;; smallest first, then the splat each drop leaves (drop N, splat 4+N).

(define-fx-animation blood "sprites/blood/blood")

(defparameter *blood-pixels-per-metre* 64.0 "Art pixels per metre, as the monsters' (imp: 96 px, 1.5 m).")
(defparameter *blood-gravity* 9.8 "Metres per second² a drop falls by.")
(defparameter *blood-drag* 1.2 "Fraction of its speed a drop loses per second to the air.")
(defparameter *blood-per-damage* 1.0 "Drops a hit sprays per point of damage.")
(defparameter *blood-drops* '(4 20) "Fewest and most drops one hit sprays.")
(defparameter *blood-speed* '(1.5 4.5) "Slowest and fastest drop of a hit, in m/s.")
(defparameter *blood-spread* 0.8 "Radians either side of the blow's direction that a hit's spray fans out.")
(defparameter *blood-rise* '(-0.2 0.7) "Lowest and highest angle above level, in radians, a drop leaves at.")
(defparameter *blood-lift* 1.2 "Upward m/s added to every drop, so the spray arcs.")
(defparameter *blood-back-spray* 0.3 "Fraction of a hit's drops thrown back toward the attacker.")
(defparameter *blood-wound-height* 0.55 "Height of the wound, as a fraction of the creature's.")
(defparameter *blood-wound-offset* 0.15
  "Metres in front of the sprite, toward the attacker, that drops start, so the sprite
doesn't hide them.")
(defparameter *death-blood* 28 "Drops a death bursts out, in every direction.")
(defparameter *death-blood-speed* '(1.0 3.5))
(defparameter *death-blood-lift* 2.0)
(defparameter *blood-drop-life* 3.0 "Seconds a drop flies before it goes, if it lands nowhere.")
(defparameter *max-blood* 1024
  "Particles in the pool, drops and splats; a full pool reuses the oldest. Read when a
pool is made (tools/hd reset).")
(defparameter *splat-lift* 0.004
  "Metres a splat stands off its surface. Splats alternate between up to 3 times that,
so overlapping ones don't flicker.")

(defvar *blood-pool* NIL "The blood pool in the current scene.")

;; Each vertex: position (3), uv (2), corner (2), normal (3). A drop's position is its
;; centre and its corner the offset in view space; a splat's position is the corner
;; itself, its corner 0 and its normal the surface's, which tells the shader it's a splat.
(defconstant +blood-vertex-floats+ 10)

(define-shader-entity blood-pool (lit-entity renderable listener)
  ((size :reader pool-size)
   (cursor :initform 0 :accessor pool-cursor :documentation "The slot the next particle takes.")
   (state :reader pool-state :documentation "Per particle: 0 free, 1 a flying drop, 2 a splat.")
   (frame :reader pool-frame :documentation "Per particle: its frame in the strip.")
   (side :reader pool-side
         :documentation "Per splat: the face it lies on, 0 to 5 for +X -X +Y -Y +Z -Z, and in
bits 3 to 5 its turn (quarter turns, then a mirror).")
   (positions :reader pool-positions)
   (velocities :reader pool-velocities)
   (ages :reader pool-ages)
   (data :reader pool-data :documentation "Vertex data, 6 vertices per particle.")
   (vbo :reader pool-vbo)
   (vao :reader pool-vao)))

(defmethod initialize-instance :after ((pool blood-pool) &key)
  (let* ((n *max-blood*)
         (data (make-array (* n 6 +blood-vertex-floats+) :element-type 'single-float :initial-element 0f0))
         (vbo (make-instance 'vertex-buffer :buffer-data data :data-usage :stream-draw))
         (stride (* 4 +blood-vertex-floats+)))
    (setf (slot-value pool 'size) n
          (slot-value pool 'state) (make-array n :element-type '(unsigned-byte 8) :initial-element 0)
          (slot-value pool 'frame) (make-array n :element-type '(unsigned-byte 8) :initial-element 0)
          (slot-value pool 'side) (make-array n :element-type '(unsigned-byte 8) :initial-element 0)
          (slot-value pool 'positions) (make-array (* 3 n) :element-type 'single-float :initial-element 0f0)
          (slot-value pool 'velocities) (make-array (* 3 n) :element-type 'single-float :initial-element 0f0)
          (slot-value pool 'ages) (make-array n :element-type 'single-float :initial-element 0f0)
          (slot-value pool 'data) data
          (slot-value pool 'vbo) vbo
          (slot-value pool 'vao) (make-instance 'vertex-array
                                                :vertex-form :triangles
                                                :bindings `((,vbo :size 3 :offset 0 :stride ,stride :index 0)
                                                            (,vbo :size 2 :offset 12 :stride ,stride :index 2)
                                                            (,vbo :size 2 :offset 20 :stride ,stride :index 3)
                                                            (,vbo :size 3 :offset 28 :stride ,stride :index 1))))))

(defmethod stage :after ((pool blood-pool) (area staging-area))
  (stage (pool-vao pool) area)
  (stage (animation-texture (find-fx-animation 'blood)) area))

(defmethod bind-textures :after ((pool blood-pool))
  (bind (animation-texture (find-fx-animation 'blood)) :texture0))

(defun add-blood-pool (scene)
  (setf *blood-pool* (make-instance 'blood-pool))
  (enter *blood-pool* scene))

(defun clear-blood ()
  "Take every drop and splat away."
  (when *blood-pool*
    (fill (pool-state *blood-pool*) 0)
    (setf (pool-cursor *blood-pool*) 0)))

(defun range-random (range)
  (destructuring-bind (lo hi) range
    (+ lo (random (float (- hi lo) 0f0)))))

(defun spawn-drop (x y z vx vy vz)
  "Throw a drop from X Y Z at VX VY VZ m/s, in the oldest slot of the pool."
  (let ((pool *blood-pool*))
    (when pool
      (let ((i (pool-cursor pool))
            (p (pool-positions pool))
            (v (pool-velocities pool)))
        (setf (pool-cursor pool) (mod (1+ i) (pool-size pool)))
        (setf (aref (pool-state pool) i) 1
              ;; Mostly small drops, the odd big one.
              (aref (pool-frame pool) i) (min 3 (floor (* 4 (expt (random 1f0) 1.6))))
              (aref (pool-ages pool) i) 0f0
              (aref p (* 3 i)) (float x 0f0) (aref p (+ 1 (* 3 i))) (float y 0f0) (aref p (+ 2 (* 3 i))) (float z 0f0)
              (aref v (* 3 i)) (float vx 0f0) (aref v (+ 1 (* 3 i))) (float vy 0f0) (aref v (+ 2 (* 3 i))) (float vz 0f0))))))

(defun spray-blood (at dx dz count &key (spread *blood-spread*) (speed *blood-speed*) (rise *blood-rise*)
                                        (lift *blood-lift*) (back 0.0))
  "Throw COUNT drops from point AT, fanned SPREAD radians either side of the horizontal
direction DX DZ (any way when it is 0 0), a BACK fraction of them the other way."
  (let ((heading (if (and (= 0 dx) (= 0 dz)) NIL (atan dz dx))))
    (dotimes (n count)
      (let* ((a (if heading
                    (+ heading (- (random (* 2.0 spread)) spread) (if (< (random 1f0) back) pi 0.0))
                    (random (float (* 2 pi) 0f0))))
             (e (range-random rise))
             (s (range-random speed)))
        (spawn-drop (vx at) (vy at) (vz at)
                    (* s (cos e) (cos a))
                    (+ (* s (sin e)) (* lift (+ 0.5 (random 0.5))))
                    (* s (cos e) (sin a)))))))

(defun bleed (creature amount from)
  "Spray blood from CREATURE's wound, struck for AMOUNT from point FROM: away from FROM,
some of it back toward it. Without FROM the blow comes from the player."
  (let* ((loc (location creature))
         (from (or from (and *player* (feet *player*))))
         (dx (if from (- (vx loc) (vx from)) 0.0))
         (dz (if from (- (vz loc) (vz from)) 0.0))
         (len (sqrt (+ (* dx dx) (* dz dz))))
         (at (vec (vx loc) (+ (vy loc) (* *blood-wound-height* (sprite-height creature))) (vz loc))))
    (when (< 1f-4 len)
      (setf dx (/ dx len) dz (/ dz len))
      (decf (vx at) (* dx *blood-wound-offset*))
      (decf (vz at) (* dz *blood-wound-offset*)))
    (destructuring-bind (fewest most) *blood-drops*
      (spray-blood at dx dz (max fewest (min most (round (* amount *blood-per-damage*))))
                   :back *blood-back-spray*))))

(defun bleed-out (creature)
  "Burst blood out of CREATURE as it dies, every way."
  (let ((loc (location creature)))
    (spray-blood (vec (vx loc) (+ (vy loc) (* *blood-wound-height* (sprite-height creature))) (vz loc))
                 0.0 0.0 (or (death-blood creature) *death-blood*)
                 :speed *death-blood-speed* :rise '(0.0 1.0) :lift *death-blood-lift*)))

;;; Flight and landing.

(defun solid-at (x y z)
  "The solid box that point X Y Z is inside, or NIL."
  (declare (type single-float x y z))
  (loop for s across *solids*
        do (let ((s s))
             (declare (type (simple-array single-float (6)) s))
             (when (and (< (aref s 0) x (aref s 3))
                        (< (aref s 1) y (aref s 4))
                        (< (aref s 2) z (aref s 5)))
               (return s)))))

(defun land-drop (pool i s nx ny nz)
  "Drop I of POOL has moved from where it is to NX NY NZ, into solid S: stick it where it
crossed S's face as a splat, or let it slide off a ceiling. One that was already inside goes."
  (declare (type (simple-array single-float (6)) s)
           (type single-float nx ny nz))
  (let* ((p (pool-positions pool))
         (v (pool-velocities pool))
         (b (* 3 i))
         (best -1) (best-t -1f0) (best-high NIL))
    ;; The face crossed last is the one it went in through.
    (loop for axis from 0 below 3
          for o = (aref p (+ b axis))
          for q = (ecase axis (0 nx) (1 ny) (2 nz))
          for lo = (aref s axis)
          for hi = (aref s (+ axis 3))
          do (flet ((consider (tt high)
                      (when (< best-t tt)
                        (setf best axis best-t tt best-high high))))
               (cond ((and (<= o lo) (< lo q)) (consider (/ (- lo o) (- q o)) NIL))
                     ((and (<= hi o) (< q hi)) (consider (/ (- o hi) (- o q)) T)))))
    (cond ((< best 0)
           (setf (aref (pool-state pool) i) 0))
          ((and (= best 1) (not best-high))
           ;; A ceiling: it loses its rise and falls.
           (setf (aref p b) nx
                 (aref p (+ b 1)) (- (aref s 1) 0.001)
                 (aref p (+ b 2)) nz
                 (aref v (+ b 1)) 0f0))
          (T
           (loop for axis from 0 below 3
                 for o = (aref p (+ b axis))
                 for q = (ecase axis (0 nx) (1 ny) (2 nz))
                 do (setf (aref p (+ b axis))
                          (if (= axis best)
                              (aref s (if best-high (+ axis 3) axis))
                              (+ o (* best-t (- q o))))))
           (setf (aref (pool-state pool) i) 2
                 (aref (pool-frame pool) i) (+ 4 (aref (pool-frame pool) i))
                 (aref (pool-side pool) i) (+ (* 2 best) (if best-high 0 1) (* 8 (random 8))))))))

(defun step-blood (pool dt)
  (declare (type single-float dt))
  (let ((state (pool-state pool))
        (p (pool-positions pool))
        (v (pool-velocities pool))
        (ages (pool-ages pool))
        (keep (max 0f0 (- 1f0 (* (float *blood-drag* 0f0) dt))))
        (fall (* (float *blood-gravity* 0f0) dt)))
    (declare (type (simple-array (unsigned-byte 8) (*)) state)
             (type (simple-array single-float (*)) p v ages))
    (dotimes (i (pool-size pool))
      (when (= 1 (aref state i))
        (let ((b (* 3 i)))
          (incf (aref ages i) dt)
          (decf (aref v (+ b 1)) fall)
          (dotimes (k 3) (setf (aref v (+ b k)) (* keep (aref v (+ b k)))))
          (let* ((nx (+ (aref p b) (* dt (aref v b))))
                 (ny (+ (aref p (+ b 1)) (* dt (aref v (+ b 1)))))
                 (nz (+ (aref p (+ b 2)) (* dt (aref v (+ b 2)))))
                 (s (solid-at nx ny nz)))
            (cond (s (land-drop pool i s nx ny nz))
                  ((< *blood-drop-life* (aref ages i)) (setf (aref state i) 0))
                  (T (setf (aref p b) nx (aref p (+ b 1)) ny (aref p (+ b 2)) nz)))))))))

(define-handler (blood-pool tick) (dt)
  (unless (frozen-p)
    (step-blood blood-pool (float (min dt 0.05) 0f0))))

;;; Drawing.

;; Per face (+X -X +Y -Y +Z -Z): the splat's right and up directions, whose cross
;; product is the face's normal, so the quad winds counter-clockwise seen from outside.
(defparameter *splat-axes*
  (let ((axes '(((0 0 -1) (0 1 0)) ((0 0 1) (0 1 0))
                ((1 0 0) (0 0 -1)) ((1 0 0) (0 0 1))
                ((1 0 0) (0 1 0)) ((-1 0 0) (0 1 0)))))
    (make-array 36 :element-type 'single-float
                   :initial-contents (mapcar (lambda (x) (float x 0f0)) (alexandria:flatten axes)))))

;; The quad's corners, counter-clockwise in two triangles, as (a b) from 0 to 1.
(defparameter *quad-corners* (coerce '(0 0 1 0 1 1 0 0 1 1 0 1) '(simple-array (unsigned-byte 8) (12))))

(defun write-blood-vertices (pool)
  "Write every live particle's quad into POOL's vertex data. Returns the vertex count."
  (let* ((state (pool-state pool))
         (frames (pool-frame pool))
         (sides (pool-side pool))
         (p (pool-positions pool))
         (data (pool-data pool))
         (axes *splat-axes*)
         (corners *quad-corners*)
         (atlas (animation-atlas (find-fx-animation 'blood)))
         (cell (getf atlas :cell-width))
         (gap (getf atlas :gap))
         (count (getf atlas :frames))
         (width (float (+ (* count cell) (* (1- count) gap)) 0f0))
         (du (/ cell width))
         (h (/ (* 0.5 cell) (float *blood-pixels-per-metre* 0f0)))
         (lift (float *splat-lift* 0f0))
         (k 0))
    (declare (type (simple-array (unsigned-byte 8) (*)) state frames sides corners)
             (type (simple-array single-float (*)) p data axes)
             (type single-float du h lift)
             (type fixnum k))
    (flet ((put (x y z u v cx cy nx ny nz)
             (let ((o (* k +blood-vertex-floats+)))
               (setf (aref data o) x (aref data (+ o 1)) y (aref data (+ o 2)) z
                     (aref data (+ o 3)) u (aref data (+ o 4)) v
                     (aref data (+ o 5)) cx (aref data (+ o 6)) cy
                     (aref data (+ o 7)) nx (aref data (+ o 8)) ny (aref data (+ o 9)) nz))
             (incf k)))
      (dotimes (i (pool-size pool))
        (let ((s (aref state i)))
          (unless (= 0 s)
            (let* ((b (* 3 i))
                   (x (aref p b)) (y (aref p (+ b 1))) (z (aref p (+ b 2)))
                   (u0 (/ (* (aref frames i) (+ cell gap)) width)))
              (if (= 1 s)
                  (loop for c from 0 below 12 by 2
                        for a = (aref corners c)
                        for bb = (aref corners (1+ c))
                        do (put x y z (+ u0 (* a du)) (float bb 0f0)
                                (* h (- (* 2 a) 1)) (* h (- (* 2 bb) 1)) 0f0 0f0 0f0))
                  (let* ((side (logand 7 (aref sides i)))
                         (turn (ash (aref sides i) -3))
                         (axis (floor side 2))
                         (sign (if (evenp side) 1f0 -1f0))
                         (o (* 6 side))
                         (nx (if (= axis 0) sign 0f0))
                         (ny (if (= axis 1) sign 0f0))
                         (nz (if (= axis 2) sign 0f0))
                         ;; Off the surface, a different height for neighbours in the pool.
                         (off (* lift (+ 1 (mod i 3))))
                         (cx (+ x (* nx off))) (cy (+ y (* ny off))) (cz (+ z (* nz off))))
                    (loop for c from 0 below 12 by 2
                          for a = (aref corners c)
                          for bb = (aref corners (1+ c))
                          for sa = (* h (- (* 2 a) 1))
                          for sb = (* h (- (* 2 bb) 1))
                          ;; Turn and mirror the art, not the quad, so it still winds outward.
                          do (let ((ta a) (tb bb))
                               (dotimes (q (logand 3 turn))
                                 (psetf ta (- 1 tb) tb ta))
                               (when (logbitp 2 turn) (setf ta (- 1 ta)))
                               (put (+ cx (* sa (aref axes o)) (* sb (aref axes (+ o 3))))
                                    (+ cy (* sa (aref axes (+ o 1))) (* sb (aref axes (+ o 4))))
                                    (+ cz (* sa (aref axes (+ o 2))) (* sb (aref axes (+ o 5))))
                                    (+ u0 (* ta du)) (float tb 0f0) 0f0 0f0 nx ny nz)))))))))
      k)))

(defmethod render ((pool blood-pool) (program shader-program))
  (let ((count (write-blood-vertices pool)))
    (when (< 0 count)
      (update-buffer-data (pool-vbo pool) (pool-data pool) :count (* count +blood-vertex-floats+ 4))
      (setf (uniform program "view_matrix") (view-matrix))
      (setf (uniform program "projection_matrix") (projection-matrix))
      (set-fog-uniforms program)
      (setf (uniform program "light_snap") (float *sprite-light-snap* 0f0))
      (setf (uniform program "light_bands") (float *sprite-light-bands* 0f0))
      (render-array (pool-vao pool) :vertex-count count))))

(define-class-shader (blood-pool :vertex-shader)
  "layout (location = 0) in vec3 position;
layout (location = 1) in vec3 in_normal;
layout (location = 2) in vec2 in_uv;
layout (location = 3) in vec2 corner;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;
out vec2 uv;
out vec3 v_world_position;
out vec3 v_view_position;
out vec3 v_normal;

void main(){
  vec4 view_position = view_matrix * vec4(position, 1.0);
  view_position.xy += corner;
  gl_Position = projection_matrix * view_position;
  uv = in_uv;
  v_world_position = position;
  v_view_position = view_position.xyz;
  v_normal = in_normal;
}")

(define-class-shader (blood-pool :fragment-shader)
  "in vec2 uv;
in vec3 v_world_position;
in vec3 v_view_position;
in vec3 v_normal;
uniform sampler2D texture_image;
uniform vec3 fog_color;
uniform float fog_start;
uniform float fog_end;
out vec4 color;

void main(){
  color = texture(texture_image, uv);
  if(color.a < 0.5) discard;
  // A splat is lit and shaded like the face it lies on; a drop like a sprite.
  float splat = dot(v_normal, v_normal);
  vec3 n = abs(v_normal);
  float shade = mix(1.0, n.y * 1.0 + n.x * 0.75 + n.z * 0.6, splat);
  color.rgb *= shade * band_light(light_at(snap_position(v_world_position), v_normal, splat, v_world_position + v_normal * 0.05));
  float fog = clamp((length(v_view_position) - fog_start) / (fog_end - fog_start), 0.0, 1.0);
  color.rgb = mix(color.rgb, fog_color, fog);
}")
