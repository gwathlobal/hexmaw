(in-package #:hexmaw)

;;; Blood: drops sprayed from a wound, flying under gravity, that stay where they land
;;; as splats on the floor or a wall. Every particle lives in one BLOOD-POOL, entered
;;; into the scene once: plain arrays, reused oldest first, whose quads are written into
;;; one vertex buffer each frame and drawn in one call, so nothing allocates per frame.
;;; Drops face the camera plane; splats lie flat on their surface. Both are lit like the
;;; level (LIGHT_AT) and fogged. A level keeps *MAX-SPLATS* splats; past that the oldest
;;; dissolve, art pixel by art pixel. A drop landing on a round splat adds its blood to
;;; it instead of making its own, so the splat spreads into a puddle where blood falls
;;; thick. The frames are tools/draw_blood.py's strip, each group smallest first: drops 0
;;; to 3; round splats 4 to 27, three variants of eight sizes (drop N leaves size N; 4 to
;;; 7 are puddles, grown into); floor streaks 28 to 31 (running toward image right) and
;;; wall drips 32 to 35 (running down), in the four drop sizes; then each creature's gibs,
;;; four frames a piece (lying as drawn, then turned a quarter at a time, clockwise).
;;;
;;; Gibs are pieces of a creature torn apart by a blow that overkills it (*GIB-OVERKILL*,
;;; or its own GIB-OVERKILL). They live in the same pool: they fly heavier than drops,
;;; tumbling and dripping blood, bounce off what they hit, leaving a splat, and come to
;;; rest standing on the floor, facing the camera like a billboard. A level keeps
;;; *MAX-GIBS* of them. One set serves many creatures: each draws its pieces at its own
;;; GIB-SCALE, and the gibs of a creature that doesn't bleed (bones) leave no blood.

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
(defparameter *bleed-per-damage* 0.25 "Seconds a creature drips from its wound per point of damage.")
(defparameter *bleed-max* 6.0 "Most seconds of dripping a creature has in store.")
(defparameter *bleed-interval* '(0.2 0.4) "Least and most seconds between a wounded creature's drips.")
(defparameter *corpse-bleed-time* 5.0 "Seconds a corpse bleeds into a pool under it.")
(defparameter *corpse-bleed-interval* '(0.15 0.3) "Least and most seconds between a corpse's drips.")
(defparameter *blood-drop-life* 3.0 "Seconds a drop flies before it goes, if it lands nowhere.")
(defparameter *max-blood* 1024
  "Particles in the pool, drops and splats; a full pool reuses the oldest. Read when a
pool is made (tools/hd reset).")
(defparameter *splat-lift* 0.004
  "Metres a splat stands off its surface. Splats alternate between up to 3 times that,
so overlapping ones don't flicker.")
(defparameter *max-splats* 400 "Splats a level keeps; past that the oldest dissolve.")
(defparameter *splat-lifetime* NIL "Seconds before a splat dissolves of its own accord; NIL to keep it.")
(defparameter *splat-dissolve-time* 1.0 "Seconds a splat takes to dissolve.")
(defparameter *splat-radii* '(2.1 2.8 3.6 4.6 6.0 7.5 9.0 10.5)
  "Radius in art pixels of each round splat size, as tools/draw_blood.py draws them
(ROUND_RADII). The first four are the splats the four drop sizes leave.")
(defparameter *splat-merge-reach* 0.8
  "A drop landing on the same face as a round splat, closer to its middle than this
fraction of their two radii together, joins it instead of making its own splat.")
(defparameter *merge-spread* 0.8
  "Fraction of a joining drop's own splat area that the splat it joins spreads by.")
(defparameter *streak-speed* 2.5 "Horizontal m/s above which a drop smears into a streak on the floor.")
(defparameter *drip-chance* 0.5 "Chance a drop bigger than the smallest runs down a wall.")
(defparameter *gib-overkill* 0.3
  "A killing blow tears a creature with GIBS apart when it leaves its health below 0 by
at least this fraction of its most.")
(defparameter *gib-speed* '(1.0 3.5) "Slowest and fastest a gib flies outward, in m/s.")
(defparameter *gib-rise* '(2.0 4.5) "Least and most upward m/s a gib leaves at.")
(defparameter *gib-push* 1.5 "Extra m/s every gib flies along the blow.")
(defparameter *gib-drag* 0.3 "Fraction of its speed a gib loses per second to the air.")
(defparameter *gib-bounce* 0.35 "Fraction of its speed into a surface a gib bounces back with.")
(defparameter *gib-friction* 0.55 "Fraction of its speed along the floor a gib keeps when it bounces.")
(defparameter *gib-rest-speed* 1.0 "A gib falling onto the floor slower than this, in m/s, stays there.")
(defparameter *gib-tumble* 10.0 "Quarter turns a second a flying gib tumbles through.")
(defparameter *gib-drip-interval* 0.12 "Seconds between the drops a flying gib trails, on average.")
(defparameter *gib-drip-scatter* 0.6 "Most m/s a gib's trailing drop strays from the gib's own path.")
(defparameter *gib-blood* 40 "Drops the burst of a creature torn apart sprays.")
(defparameter *max-gibs* 60 "Gibs at rest a level keeps; past that the oldest dissolve.")

(defvar *blood-pool* NIL "The blood pool in the current scene.")

;; Each vertex: position (3), uv (2), corner (2), normal (3), dissolve (1). A drop's
;; position is its centre and its corner the offset in view space; a splat's position is
;; the corner itself, its corner 0 and its normal the surface's, which tells the shader
;; it's a splat. Dissolve runs from 0 (whole) to 1 (gone).
(defparameter *blood-vertex-floats* 11)

(define-shader-entity blood-pool (lit-entity renderable listener)
  ((size :reader pool-size)
   (cursor :initform 0 :accessor pool-cursor :documentation "Where the search for a free slot starts.")
   (splat-count :initform 0 :accessor splat-count :documentation "Splats not yet dissolving.")
   (gib-count :initform 0 :accessor gib-count :documentation "Gibs at rest, not yet dissolving.")
   (state :reader pool-state
          :documentation "Per particle: 0 free, 1 a flying drop, 2 a splat, 3 a dissolving splat,
4 a flying gib, 5 a gib at rest, 6 a dissolving gib.")
   (frame :reader pool-frame :documentation "Per particle: its frame in the strip; a gib's unturned one.")
   (side :reader pool-side
         :documentation "Per splat: the face it lies on, 0 to 5 for +X -X +Y -Y +Z -Z, and in
bits 3 to 5 its turn (quarter turns, then a mirror). Per gib: bit 0 to tumble
anticlockwise, bit 1 to mirror, bits 2 and 3 the quarter turn it starts at, bit 4 if it
leaves no blood.")
   (scales :reader pool-scales :documentation "Per gib: the size it is drawn at, 1 as the art is.")
   (positions :reader pool-positions)
   (velocities :reader pool-velocities)
   (ages :reader pool-ages
         :documentation "Per particle: seconds a drop has flown, a splat has lain or a dissolve has run.")
   (data :reader pool-data :documentation "Vertex data, 6 vertices per particle.")
   (vbo :reader pool-vbo)
   (vao :reader pool-vao)))

(defmethod initialize-instance :after ((pool blood-pool) &key)
  (let* ((n *max-blood*)
         (data (make-array (* n 6 *blood-vertex-floats*) :element-type 'single-float :initial-element 0f0))
         (vbo (make-instance 'vertex-buffer :buffer-data data :data-usage :stream-draw))
         (stride (* 4 *blood-vertex-floats*)))
    (setf (slot-value pool 'size) n
          (slot-value pool 'state) (make-array n :element-type '(unsigned-byte 8) :initial-element 0)
          (slot-value pool 'frame) (make-array n :element-type '(unsigned-byte 8) :initial-element 0)
          (slot-value pool 'side) (make-array n :element-type '(unsigned-byte 8) :initial-element 0)
          (slot-value pool 'scales) (make-array n :element-type 'single-float :initial-element 1f0)
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
                                                            (,vbo :size 3 :offset 28 :stride ,stride :index 1)
                                                            (,vbo :size 1 :offset 40 :stride ,stride :index 4))))))

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
    (setf (pool-cursor *blood-pool*) 0
          (splat-count *blood-pool*) 0
          (gib-count *blood-pool*) 0)))

(defun range-random (range)
  (destructuring-bind (lo hi) range
    (+ lo (random (float (- hi lo) 0f0)))))

(defun free-slot (pool)
  "The next free slot in POOL after the last one taken; if there is none, the slot after
it, whatever it holds."
  (let* ((state (pool-state pool))
         (n (pool-size pool))
         (start (pool-cursor pool))
         (i (or (loop for k from 0 below n
                      for j = (mod (+ start k) n)
                      when (= 0 (aref state j)) return j)
                start)))
    (case (aref state i)
      (2 (decf (splat-count pool)))
      (5 (decf (gib-count pool))))
    (setf (pool-cursor pool) (mod (1+ i) n))
    i))

(defun spawn-drop (x y z vx vy vz &optional size)
  "Throw a drop of SIZE (0 to 3; NIL for mostly small, the odd big one) from X Y Z at
VX VY VZ m/s."
  (let ((pool *blood-pool*))
    (when pool
      (let ((i (free-slot pool))
            (p (pool-positions pool))
            (v (pool-velocities pool)))
        (setf (aref (pool-state pool) i) 1
              (aref (pool-frame pool) i) (or size (min 3 (floor (* 4 (expt (random 1f0) 1.6)))))
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
some of it back toward it. Without FROM the blow comes from the player. The wound drips
for a while after."
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
                   :back *blood-back-spray*))
    (setf (bleeding creature) (min (float *bleed-max* 0f0) (+ (bleeding creature) (* amount *bleed-per-damage*))))))

(defun bleed-out (creature)
  "Burst blood out of CREATURE as it dies, every way, and let the corpse bleed into a pool.
A creature whose DEATH-BLOOD is 0 does neither."
  (let ((loc (location creature))
        (count (or (death-blood creature) *death-blood*)))
    (spray-blood (vec (vx loc) (+ (vy loc) (* *blood-wound-height* (sprite-height creature))) (vz loc))
                 0.0 0.0 count
                 :speed *death-blood-speed* :rise '(0.0 1.0) :lift *death-blood-lift*)
    (setf (bleeding creature) (if (< 0 count) (float *corpse-bleed-time* 0f0) 0f0)
          (drip-timer creature) 0f0)))

;;; Dripping: blood falling straight down, a drop at a time, lands on the blood before it
;;; and so spreads into a puddle: under a wounded creature that stands still (a trail when
;;; it walks), and under a corpse.

(defun drip-blood (creature dt)
  "Run CREATURE's bleeding for DT seconds. Called from its tick while the world moves."
  (when (< 0 (bleeding creature))
    (decf (bleeding creature) dt)
    (decf (drip-timer creature) dt)
    (when (<= (drip-timer creature) 0)
      (let* ((dead (dead creature))
             (loc (location creature))
             (x (+ (vx loc) (- (random 0.08) 0.04)))
             (z (+ (vz loc) (- (random 0.08) 0.04))))
        (setf (drip-timer creature) (range-random (if dead *corpse-bleed-interval* *bleed-interval*)))
        (unless dead
          ;; From the wound, on the side the player sees, so the sprite doesn't hide it.
          (when *player*
            (let* ((feet (feet *player*))
                   (dx (- (vx feet) (vx loc)))
                   (dz (- (vz feet) (vz loc)))
                   (len (sqrt (+ (* dx dx) (* dz dz)))))
              (when (< 1f-4 len)
                (incf x (* *blood-wound-offset* (/ dx len)))
                (incf z (* *blood-wound-offset* (/ dz len)))))))
        (spawn-drop x (+ (vy loc) (if dead 0.1 (* *blood-wound-height* (sprite-height creature)))) z
                    (- (random 0.2) 0.1) 0.0 (- (random 0.2) 0.1)
                    (+ 1 (random (if dead 3 2))))))))

;;; Flight and landing.

(defun solid-at (x y z)
  "The solid box that point X Y Z is inside, or NIL."
  (declare (type single-float x y z))
  (do-solids-near (s x z x z)
    (when (and (< (aref s 0) x (aref s 3))
               (< (aref s 1) y (aref s 4))
               (< (aref s 2) z (aref s 5))
               (< 0f0 (%wedge-depth s x z x z)))
      (return-from solid-at s)))
  NIL)

(defun crossed-face (p b s nx ny nz)
  "The face of solid S that the particle at P, from index B, crossed on its way to NX NY
NZ: its axis (0 to 2, or -1 if the particle was already inside), true if it is the
high side, and how far along the way it was crossed, 0 to 1."
  (declare (type (simple-array single-float (*)) s)
           (type (simple-array single-float (*)) p)
           (type single-float nx ny nz))
  (let ((best -1) (best-t -1f0) (best-high NIL))
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
    (values best best-high best-t)))

(defun move-to-face (p b s axis high tt nx ny nz)
  "Put the particle at P, from index B, where it crossed face AXIS HIGH of S, TT of the way to NX NY NZ."
  (loop for k from 0 below 3
        for o = (aref p (+ b k))
        for q = (ecase k (0 nx) (1 ny) (2 nz))
        do (setf (aref p (+ b k))
                 (if (= k axis)
                     (aref s (if high (+ k 3) k))
                     (+ o (* tt (- q o)))))))

(defun diagonal-entry-p (p b s axis high tt nx nz)
  "True if the particle at P, from index B, went into wedge S through its diagonal: it was
already inside S's box (AXIS -1, from CROSSED-FACE), or the box face it crossed, AXIS
HIGH TT of the way to NX NZ, lies in the cut-away half."
  (and (< 0 (solid-cut s))
       (or (< axis 0)
           (let ((x (if (= axis 0) (aref s (if high 3 0)) (+ (aref p b) (* tt (- nx (aref p b))))))
                 (z (if (= axis 2) (aref s (if high 5 2)) (+ (aref p (+ b 2)) (* tt (- nz (aref p (+ b 2))))))))
             (< (%wedge-depth s x z x z) -1f-5)))))

(defun reflect-off-diagonal (v b s)
  "Turn the velocity at V, from index B, back off wedge S's diagonal, as a bounce."
  (multiple-value-bind (cu cv) (cut-sides (solid-cut s))
    ;; Mirroring about a 45° wall swaps the horizontal parts, signed by its normal.
    (let ((sign (* (if (= cu 1) -1 1) (if (= cv 1) 1 -1)))
          (vx (aref v b)) (vz (aref v (+ b 2))))
      (setf (aref v b) (* sign vz *gib-bounce*)
            (aref v (+ b 2)) (* sign vx *gib-bounce*)))))

(defun land-drop (pool i s nx ny nz)
  "Drop I of POOL has moved from where it is to NX NY NZ, into solid S: stick it where it
crossed S's face as a splat, or let it slide off a ceiling. One that was already inside goes."
  (declare (type (simple-array single-float (*)) s)
           (type single-float nx ny nz))
  (let* ((p (pool-positions pool))
         (v (pool-velocities pool))
         (b (* 3 i)))
    (multiple-value-bind (best best-high best-t) (crossed-face p b s nx ny nz)
     ;; A splat lies flat on a box's face; one on a diagonal would need turning, so a
     ;; drop that goes in through one is gone.
     (cond ((or (< best 0) (diagonal-entry-p p b s best best-high best-t nx nz))
           (setf (aref (pool-state pool) i) 0))
          ((and (= best 1) (not best-high))
           ;; A ceiling: it loses its rise and falls.
           (setf (aref p b) nx
                 (aref p (+ b 1)) (- (aref s 1) 0.001)
                 (aref p (+ b 2)) nz
                 (aref v (+ b 1)) 0f0))
          (T
           (move-to-face p b s best best-high best-t nx ny nz)
           (lay-splat pool i (+ (* 2 best) (if best-high 0 1))))))))

(defun round-splat-p (frame)
  (<= 4 frame 27))

(defun splat-radius (size)
  "Radius in art pixels of round splat SIZE."
  (float (nth size *splat-radii*) 0f0))

(defun splat-size-for (area)
  "The biggest round splat size whose disc is no bigger than AREA (art pixels², over pi)."
  (let ((size 0))
    (loop for r in *splat-radii*
          for n from 0
          when (<= (* r r) area) do (setf size n))
    size))

;; A splat's VELOCITIES slot, unused once it lies still, keeps its blood: the area of
;; its disc in art pixels², over pi, which picks its size.
(defun merge-splat (pool i face)
  "Pour drop I, landed on FACE, into the nearest round splat there that it overlaps by
*SPLAT-MERGE-REACH*, spreading it toward the drop. Returns true if there was one, so
the drop isn't needed."
  (let* ((state (pool-state pool))
         (frames (pool-frame pool))
         (sides (pool-side pool))
         (p (pool-positions pool))
         (v (pool-velocities pool))
         (b (* 3 i))
         (size (aref frames i))
         (ppm (float *blood-pixels-per-metre* 0f0))
         (own (splat-radius size))
         (best NIL) (best-k 0f0))
    (declare (type (simple-array (unsigned-byte 8) (*)) state frames sides)
             (type (simple-array single-float (*)) p v))
    ;; The one it lands furthest inside, as a fraction of how far merging reaches.
    (dotimes (j (pool-size pool))
      (when (and (= 2 (aref state j))
                 (= face (logand 7 (aref sides j)))
                 (round-splat-p (aref frames j)))
        (let ((d (sqrt (+ (expt (- (aref p (* 3 j)) (aref p b)) 2)
                          (expt (- (aref p (+ 1 (* 3 j))) (aref p (+ b 1))) 2)
                          (expt (- (aref p (+ 2 (* 3 j))) (aref p (+ b 2))) 2))))
              (reach (/ (* *splat-merge-reach* (+ own (splat-radius (mod (- (aref frames j) 4) 8)))) ppm)))
          (when (and (< d reach) (or (null best) (< (/ d reach) best-k)))
            (setf best j best-k (/ d reach))))))
    (when best
      (let* ((j best)
             (added (* *merge-spread* own own))
             (area (+ (aref v (* 3 j)) added))
             (k (/ added area)))
        (setf (aref v (* 3 j)) area
              (aref frames j) (+ 4 (* 8 (floor (- (aref frames j) 4) 8)) (splat-size-for area)))
        ;; It spreads toward where the new blood fell.
        (dotimes (axis 3)
          (incf (aref p (+ (* 3 j) axis)) (* k (- (aref p (+ b axis)) (aref p (+ (* 3 j) axis))))))
        T))))

(defun dissolve-oldest-splat (pool)
  (let ((state (pool-state pool))
        (ages (pool-ages pool))
        (oldest NIL))
    (dotimes (j (pool-size pool))
      (when (and (= 2 (aref state j))
                 (or (null oldest) (< (aref ages oldest) (aref ages j))))
        (setf oldest j)))
    (when oldest
      (setf (aref state oldest) 3
            (aref ages oldest) 0f0)
      (decf (splat-count pool)))))

(defun lay-splat (pool i face)
  "Turn drop I of POOL, which has landed on FACE (0 to 5 for +X -X +Y -Y +Z -Z), into a
splat, or into a bigger one already there. A fast drop smears into a streak on the floor,
the way it was going; a bigger one may run down a wall."
  (cond ((merge-splat pool i face)
         (setf (aref (pool-state pool) i) 0))
        (T
         (let* ((size (aref (pool-frame pool) i))
                (v (pool-velocities pool))
                (vx (aref v (* 3 i)))
                (vz (aref v (+ 2 (* 3 i))))
                (frame (+ 4 (* 8 (random 3)) size))
                (turn (random 8)))
           (cond ((and (= face 2) (< (expt *streak-speed* 2) (+ (* vx vx) (* vz vz))))
                  ;; The art runs toward its right, which quarter turn K points along the
                  ;; floor's +X, +Z, -X, -Z.
                  (setf frame (+ 28 size)
                        turn (if (< (abs vz) (abs vx))
                                 (if (< 0 vx) 0 2)
                                 (if (< 0 vz) 1 3))))
                 ((and (/= 1 (floor face 2)) (< 0 size) (< (random 1f0) *drip-chance*))
                  ;; Unturned, so it runs down; mirrored or not.
                  (setf frame (+ 32 size)
                        turn (* 4 (random 2)))))
           (setf (aref (pool-state pool) i) 2
                 (aref (pool-ages pool) i) 0f0
                 (aref v (* 3 i)) (expt (splat-radius size) 2)
                 (aref (pool-frame pool) i) frame
                 (aref (pool-side pool) i) (+ face (* 8 turn)))
           (incf (splat-count pool))
           (loop while (and (< *max-splats* (splat-count pool))
                            (dissolve-oldest-splat pool)))))))

(defun step-blood (pool dt)
  (declare (type single-float dt))
  (let ((state (pool-state pool))
        (p (pool-positions pool))
        (v (pool-velocities pool))
        (ages (pool-ages pool))
        (keep (max 0f0 (- 1f0 (* (float *blood-drag* 0f0) dt))))
        (keep-gib (max 0f0 (- 1f0 (* (float *gib-drag* 0f0) dt))))
        (fall (* (float *blood-gravity* 0f0) dt)))
    (declare (type (simple-array (unsigned-byte 8) (*)) state)
             (type (simple-array single-float (*)) p v ages))
    (dotimes (i (pool-size pool))
      (case (aref state i)
        (2 (incf (aref ages i) dt)
         (when (and *splat-lifetime* (< *splat-lifetime* (aref ages i)))
           (setf (aref state i) 3 (aref ages i) 0f0)
           (decf (splat-count pool))))
        ((3 6) (incf (aref ages i) dt)
         (when (< *splat-dissolve-time* (aref ages i))
           (setf (aref state i) 0)))
        (4 (step-gib pool i dt keep-gib fall))
        (5 (incf (aref ages i) dt)))
      (when (= 1 (aref state i))
        (let ((b (* 3 i)))
          (incf (aref ages i) dt)
          (decf (aref v (+ b 1)) fall)
          (dotimes (k 3) (setf (aref v (+ b k)) (* keep (aref v (+ b k)))))
          (let* ((nx (+ (aref p b) (* dt (aref v b))))
                 (ny (+ (aref p (+ b 1)) (* dt (aref v (+ b 1)))))
                 (nz (+ (aref p (+ b 2)) (* dt (aref v (+ b 2)))))
                 (s (solid-at nx ny nz)))
            (cond ((liquid-at nx ny nz) (setf (aref state i) 0)) ; Sunk, or burnt off.
                  (s (land-drop pool i s nx ny nz))
                  ((< *blood-drop-life* (aref ages i)) (setf (aref state i) 0))
                  (T (setf (aref p b) nx (aref p (+ b 1)) ny (aref p (+ b 2)) nz)))))))))

(define-handler (blood-pool tick) (dt)
  (unless (frozen-p)
    (step-blood blood-pool (float (min dt 0.05) 0f0))))

;;; Gibs.

(defun gib-set (name)
  "The first frame and piece count of gib set NAME in the blood strip."
  (let ((set (getf (getf (animation-atlas (find-fx-animation 'blood)) :gibs) name)))
    (unless set (error "No gib set ~s in the blood strip (tools/draw_blood.py --gibs)." name))
    (values (getf set :first) (getf set :count))))

(defun spawn-gib (frame x y z vx vy vz &key (scale 1.0) dry)
  "Throw the gib whose unturned frame is FRAME from X Y Z at VX VY VZ m/s, drawn at
SCALE; a DRY one leaves no blood."
  (let ((pool *blood-pool*))
    (when pool
      (let ((i (free-slot pool))
            (p (pool-positions pool))
            (v (pool-velocities pool)))
        (setf (aref (pool-state pool) i) 4
              (aref (pool-frame pool) i) frame
              (aref (pool-side pool) i) (logior (random 16) (if dry 16 0))
              (aref (pool-scales pool) i) (float scale 0f0)
              (aref (pool-ages pool) i) 0f0
              (aref p (* 3 i)) (float x 0f0) (aref p (+ 1 (* 3 i))) (float y 0f0) (aref p (+ 2 (* 3 i))) (float z 0f0)
              (aref v (* 3 i)) (float vx 0f0) (aref v (+ 1 (* 3 i))) (float vy 0f0) (aref v (+ 2 (* 3 i))) (float vz 0f0))))))

(defun gib-p (creature amount)
  "True if CREATURE, killed by a blow of AMOUNT, should be torn apart."
  (declare (ignore amount))
  (and (gibs creature)
       (<= (health creature) (- (* (or (gib-overkill creature) *gib-overkill*) (max-health creature))))))

(defun burst-gibs (creature from)
  "Tear CREATURE apart: throw its gibs out every way and along the blow from point FROM
(NIL: from the player), with a burst of blood if it bleeds. Its GIBS are groups, each a
set's name in the blood strip and its piece numbers; a piece written (:HEAD N) flies
from the top of the body, the rest from anywhere in it."
  (let* ((loc (location creature))
         (height (sprite-height creature))
         (scale (gib-scale creature))
         (dry (not (bleeds creature)))
         (from (or from (and *player* (feet *player*))))
         (dx (if from (- (vx loc) (vx from)) 0.0))
         (dz (if from (- (vz loc) (vz from)) 0.0))
         (len (sqrt (+ (* dx dx) (* dz dz)))))
    (when (< 1f-4 len)
      (setf dx (/ dx len) dz (/ dz len)))
    (loop for (set . pieces) in (gibs creature)
          for first = (gib-set set)
          do (loop for entry in pieces
                   for head = (consp entry)
                   for piece = (if head (second entry) entry)
                   for a = (random (float (* 2 pi) 0f0))
                   for s = (range-random *gib-speed*)
                   for y = (+ (vy loc) (* height (if head 0.85 (+ 0.25 (random 0.5)))))
                   do (spawn-gib (+ first (* 4 piece)) (vx loc) y (vz loc)
                                 (+ (* s (cos a)) (* *gib-push* dx))
                                 (range-random *gib-rise*)
                                 (+ (* s (sin a)) (* *gib-push* dz))
                                 :scale scale :dry dry)))
    (unless dry
      (spray-blood (vec (vx loc) (+ (vy loc) (* 0.5 height)) (vz loc)) dx dz *gib-blood*
                   :spread pi :speed *death-blood-speed* :rise '(0.0 1.0) :lift *death-blood-lift*))))

(defun tear-apart (creature &key from)
  "Tear CREATURE apart, struck from point FROM, as a blow that overkills it does: it
vanishes and its gibs fly. Its wound stops dripping, since nothing of it is left."
  (unless (gibbed creature)
    (setf (gibbed creature) T
          (bleeding creature) 0f0)
    (burst-gibs creature from)))

(defun dissolve-oldest-gib (pool)
  (let ((state (pool-state pool))
        (ages (pool-ages pool))
        (oldest NIL))
    (dotimes (j (pool-size pool))
      (when (and (= 5 (aref state j))
                 (or (null oldest) (< (aref ages oldest) (aref ages j))))
        (setf oldest j)))
    (when oldest
      (setf (aref state oldest) 6
            (aref ages oldest) 0f0)
      (decf (gib-count pool)))))

(defun rest-gib (pool i)
  (setf (aref (pool-state pool) i) 5
        (aref (pool-ages pool) i) 0f0)
  (incf (gib-count pool))
  (loop while (and (< *max-gibs* (gib-count pool))
                   (dissolve-oldest-gib pool))))

(defun step-gib (pool i dt keep fall)
  "Fly gib I of POOL for DT seconds, slowed by KEEP and pulled down by FALL: it drips,
bounces off what it hits, leaving a splat, and rests on the floor once slow enough."
  (declare (type single-float dt keep fall))
  (let* ((p (pool-positions pool))
         (v (pool-velocities pool))
         (ages (pool-ages pool))
         (b (* 3 i))
         (scatter (float *gib-drip-scatter* 0f0))
         (dry (logbitp 4 (aref (pool-side pool) i))))
    (declare (type (simple-array single-float (*)) p v ages)
             (type single-float scatter))
    (incf (aref ages i) dt)
    ;; At random, so the trail isn't a dotted line.
    (when (and (not dry) (< (random 1f0) (/ dt *gib-drip-interval*)))
      (flet ((stray () (- (random (* 2 scatter)) scatter)))
        (spawn-drop (aref p b) (aref p (+ b 1)) (aref p (+ b 2))
                    (+ (* 0.3 (aref v b)) (stray)) (+ (* 0.3 (aref v (+ b 1))) (stray)) (+ (* 0.3 (aref v (+ b 2))) (stray))
                    (random 2))))
    (decf (aref v (+ b 1)) fall)
    (dotimes (k 3) (setf (aref v (+ b k)) (* keep (aref v (+ b k)))))
    (let* ((nx (+ (aref p b) (* dt (aref v b))))
           (ny (+ (aref p (+ b 1)) (* dt (aref v (+ b 1)))))
           (nz (+ (aref p (+ b 2)) (* dt (aref v (+ b 2)))))
           (s (solid-at nx ny nz)))
      (cond ((liquid-at nx ny nz)
             (setf (aref (pool-state pool) i) 0))
            ((null s)
             (if (< *blood-drop-life* (aref ages i))
                 (setf (aref (pool-state pool) i) 0)
                 (setf (aref p b) nx (aref p (+ b 1)) ny (aref p (+ b 2)) nz)))
            (T
             (multiple-value-bind (axis high tt) (crossed-face p b s nx ny nz)
               (cond ((diagonal-entry-p p b s axis high tt nx nz)
                      ;; Off a diagonal: it stays where it was and bounces back.
                      (reflect-off-diagonal v b s))
                     ((< axis 0)
                      (setf (aref (pool-state pool) i) 0))
                     (T
                      (move-to-face p b s axis high tt nx ny nz)
                      (let* ((into (abs (aref v (+ b axis))))
                             (floor-p (and (= axis 1) high))
                             (out (if high 0.01 -0.01)))
                        ;; A splat where it struck, from a drop just off the face.
                        (when (and (not dry) (< 1.5 into))
                          (spawn-drop (+ (aref p b) (if (= axis 0) out 0.0))
                                      (+ (aref p (+ b 1)) (if (= axis 1) out 0.0))
                                      (+ (aref p (+ b 2)) (if (= axis 2) out 0.0))
                                      (if (= axis 0) (- out) 0.0) (if (= axis 1) (- out) 0.0) (if (= axis 2) (- out) 0.0)
                                      (+ 1 (random 3))))
                        (cond ((and floor-p (< into *gib-rest-speed*))
                               (rest-gib pool i))
                              (T
                               (setf (aref v (+ b axis)) (* (if high into (- into)) *gib-bounce*))
                               (incf (aref p (+ b axis)) out)
                               (when floor-p
                                 (setf (aref v b) (* (aref v b) *gib-friction*)
                                       (aref v (+ b 2)) (* (aref v (+ b 2)) *gib-friction*))))))))))))))

;;; Drawing.

(defvar *blood-bottoms* (cons NIL NIL) "The atlas and its :BOTTOMS as a vector, so drawing needn't walk the list.")

(defun blood-bottoms (atlas)
  "Per frame of the blood strip, the empty art pixels below what is drawn in its cell."
  (unless (eq atlas (car *blood-bottoms*))
    (setf *blood-bottoms* (cons atlas (coerce (or (getf atlas :bottoms) (make-list (getf atlas :frames) :initial-element 0))
                                             '(simple-array fixnum (*))))))
  (cdr *blood-bottoms*))

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
         (scales (pool-scales pool))
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
         (ages (pool-ages pool))
         (dissolve-time (float *splat-dissolve-time* 0f0))
         (stride *blood-vertex-floats*)
         (bottoms (blood-bottoms atlas))
         (ppm (float *blood-pixels-per-metre* 0f0))
         (tumble (float *gib-tumble* 0f0))
         ;; Resting gibs stand upright, turned about +Y to face the camera plane.
         (camera (camera (scene +main+)))
         (yaw (if (typep camera 'fps-camera) (vy (rotation camera)) 0f0))
         (rx (cos yaw)) (rz (sin yaw))
         (k 0))
    (declare (type (simple-array (unsigned-byte 8) (*)) state frames sides corners)
             (type (simple-array single-float (*)) p scales data axes ages)
             (type (simple-array fixnum (*)) bottoms)
             (type single-float du h lift dissolve-time ppm tumble rx rz)
             (type fixnum k stride))
    (flet ((put (x y z u v cx cy nx ny nz fade)
             (let ((o (* k stride)))
               (setf (aref data o) x (aref data (+ o 1)) y (aref data (+ o 2)) z
                     (aref data (+ o 3)) u (aref data (+ o 4)) v
                     (aref data (+ o 5)) cx (aref data (+ o 6)) cy
                     (aref data (+ o 7)) nx (aref data (+ o 8)) ny (aref data (+ o 9)) nz
                     (aref data (+ o 10)) fade))
             (incf k)))
      (dotimes (i (pool-size pool))
        (let ((s (aref state i)))
          (unless (= 0 s)
            (let* ((b (* 3 i))
                   (x (aref p b)) (y (aref p (+ b 1))) (z (aref p (+ b 2)))
                   (u0 (/ (* (aref frames i) (+ cell gap)) width)))
              (cond
                ((= 1 s)
                  (loop for c from 0 below 12 by 2
                        for a = (aref corners c)
                        for bb = (aref corners (1+ c))
                        do (put x y z (+ u0 (* a du)) (float bb 0f0)
                                (* h (- (* 2 a) 1)) (* h (- (* 2 bb) 1)) 0f0 0f0 0f0 0f0)))
                ((= 4 s)
                 ;; Tumbling: a quarter turn of the art at a time, from its start.
                 (let* ((bits (aref sides i))
                        (turns (+ (ash bits -2) (floor (* (aref ages i) tumble))))
                        (frame (+ (aref frames i) (mod (if (logbitp 0 bits) (- turns) turns) 4)))
                        (u0 (/ (* frame (+ cell gap)) width))
                        (mirror (logbitp 1 bits))
                        (h (* h (aref scales i))))
                   (loop for c from 0 below 12 by 2
                         for a = (aref corners c)
                         for bb = (aref corners (1+ c))
                         do (put x y z (+ u0 (* (if mirror (- 1 a) a) du)) (float bb 0f0)
                                 (* h (- (* 2 a) 1)) (* h (- (* 2 bb) 1)) 0f0 0f0 0f0 0f0))))
                ((<= 5 s 6)
                 ;; At rest, standing on the floor at its lowest drawn pixel.
                 (let* ((scale (aref scales i))
                        (h (* h scale))
                        (cy (+ y (- h (/ (* scale (aref bottoms (aref frames i))) ppm))))
                        (mirror (logbitp 1 (aref sides i)))
                        (fade (if (= 6 s) (min 1f0 (/ (aref ages i) dissolve-time)) 0f0)))
                   (loop for c from 0 below 12 by 2
                         for a = (aref corners c)
                         for bb = (aref corners (1+ c))
                         for sa = (* h (- (* 2 a) 1))
                         do (put (+ x (* sa rx)) (+ cy (* h (- (* 2 bb) 1))) (+ z (* sa rz))
                                 (+ u0 (* (if mirror (- 1 a) a) du)) (float bb 0f0) 0f0 0f0 0f0 0f0 0f0 fade))))
                (T
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
                         (cx (+ x (* nx off))) (cy (+ y (* ny off))) (cz (+ z (* nz off)))
                         (fade (if (= 3 s) (min 1f0 (/ (aref ages i) dissolve-time)) 0f0)))
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
                                    (+ u0 (* ta du)) (float tb 0f0) 0f0 0f0 nx ny nz fade))))))))))
      k)))

(defmethod render ((pool blood-pool) (program shader-program))
  (let ((count (write-blood-vertices pool)))
    (when (< 0 count)
      (update-buffer-data (pool-vbo pool) (pool-data pool) :count (* count *blood-vertex-floats* 4))
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
layout (location = 4) in float in_fade;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;
out vec2 uv;
out vec3 v_world_position;
out vec3 v_view_position;
out vec3 v_normal;
out float v_fade;

void main(){
  vec4 view_position = view_matrix * vec4(position, 1.0);
  view_position.xy += corner;
  gl_Position = projection_matrix * view_position;
  uv = in_uv;
  v_world_position = position;
  v_view_position = view_position.xyz;
  v_normal = in_normal;
  v_fade = in_fade;
}")

(define-class-shader (blood-pool :fragment-shader)
  "in vec2 uv;
in vec3 v_world_position;
in vec3 v_view_position;
in vec3 v_normal;
in float v_fade;
uniform sampler2D texture_image;
out vec4 color;

void main(){
  color = texture(texture_image, uv);
  if(color.a < 0.5) discard;
  // Dissolving: art pixels drop out in a fixed random order as V_FADE rises.
  if(v_fade > 0.0){
    vec2 texel = floor(uv * vec2(textureSize(texture_image, 0)));
    if(fract(sin(dot(texel, vec2(12.9898, 78.233))) * 43758.5453) < v_fade) discard;
  }
  // A splat is lit and shaded like the face it lies on; a drop like a sprite.
  float splat = dot(v_normal, v_normal);
  vec3 n = abs(v_normal);
  float shade = mix(1.0, n.y * 1.0 + n.x * 0.75 + n.z * 0.6, splat);
  vec3 surface = color.rgb * shade;
  vec3 light = band_light(light_at(snap_position(v_world_position), v_normal, splat, v_world_position + v_normal * 0.05));
  vec3 lamp = lamp_part(light);
  color.rgb = fog_lit(surface * (light - lamp), surface * lamp, length(v_view_position));
}")
