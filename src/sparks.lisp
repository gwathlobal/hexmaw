(in-package #:hexmaw)

;;; Sparks, embers and grit: one pool of tiny simulated particles, built like the blood pool
;;; (gore.lisp): plain arrays of *MAX-SPARKS* slots, written each frame into one stream-draw
;;; vertex buffer and drawn in one call, each particle a quad in the view plane. They are
;;; fullbright, unfogged and opaque, as effects are, and they draw no art: the shader lays
;;; whole texels of the 64-a-metre grid (*TEXELS-PER-METRE*) in colours of the house palette.
;;;
;;; - A spark is a streak of 1 to *SPARK-MAX-STREAK* texels, its length how far it moves
;;;   across the view in *SPARK-STREAK-TIME*, two-toned (a hot head, a cooler tail). It
;;;   falls, bounces off what it hits and cools down its ramp's three colours, then goes.
;;; - An ember rises, wanders and blinks out (torches, lava): a short streak, as a spark is.
;;; - Grit is a texel or a 2 x 2 chip that falls, bounces once, settles and dissolves.
;;; - A flake is snow carried round by the winds (WIND-CARRY, a rime hag's blizzard): a streak as
;;;   long as its speed, or a 2 x 2 chip, that goes when it meets rock, falls out of the wind, or
;;;   its short life ends.
;;;
;;; The kinds are reworked for 3D from the idea of pixelfx's simulated particles (Patch and
;;; Hugo Duprez, MIT); nothing is lifted from its code. They are left out of saves, as
;;; status auras are: a load starts with none in flight.

(defparameter *max-sparks* 2048 "Slots in the spark pool. Past that a new spark takes the next slot, whatever it holds.")
(defparameter *spark-streak-time* 0.025 "Seconds of a spark's movement across the view its streak covers.")
(defparameter *spark-max-streak* 9 "Most texels a streak is long.")

(defparameter *spark-gravity* 12.0 "Metres per second² a spark falls by.")
(defparameter *spark-drag* 1.5 "Fraction of its speed a spark loses per second to the air.")
(defparameter *spark-bounce* 0.4 "Fraction of its speed into a surface a spark bounces back with.")
(defparameter *spark-friction* 0.6 "Fraction of its speed along the floor a spark keeps when it bounces.")
(defparameter *spark-rest-speed* 0.6 "A spark striking the floor slower than this, in m/s, lies there until it cools.")
(defparameter *spark-speed* '(3.0 7.5) "Slowest and fastest a spark leaves at, in m/s.")
(defparameter *spark-spread* 0.8 "Radians either side of the way they are thrown that sparks fan out.")
(defparameter *spark-life* '(0.3 0.75) "Least and most seconds a spark lasts, cooling all the while.")

(defparameter *ember-rise* '(0.4 1.0) "Least and most m/s an ember rises at.")
(defparameter *ember-buoyancy* 2.5 "How fast, per second, an ember's climb comes to its rise.")
(defparameter *ember-wander* 1.2 "M/s² of an ember's sideways wandering.")
(defparameter *ember-damping* 1.5 "Fraction of its sideways speed an ember loses per second.")
(defparameter *ember-life* '(0.9 2.0) "Least and most seconds an ember lasts.")
(defparameter *ember-blink* 0.4 "The last fraction of an ember's life, in which it blinks out.")
(defparameter *ember-blink-rate* 14.0 "Blinks a second while an ember goes out.")

(defparameter *grit-gravity* 9.8)
(defparameter *grit-drag* 0.5)
(defparameter *grit-bounce* 0.3 "Fraction of its speed into the floor grit bounces back with, the once.")
(defparameter *grit-friction* 0.4 "Fraction of its speed along the floor grit keeps when it bounces.")
(defparameter *grit-speed* '(1.0 3.2))
(defparameter *grit-spread* 1.1)
(defparameter *grit-rest* '(0.8 1.8) "Least and most seconds settled grit lies before it dissolves.")
(defparameter *grit-dissolve-time* 0.6 "Seconds grit takes to dissolve, a texel at a time.")
(defparameter *grit-big-chance* 0.35 "Chance a piece of grit is a 2 x 2 chip, not one texel.")
(defparameter *grit-flight* 3.0 "Seconds grit flies before it goes, if it lands nowhere.")

(defparameter *flake-flutter* 0.5 "M/s a flake rises and falls by as the wind carries it.")
(defparameter *flake-fall* 1.5 "M/s a flake out of the wind falls at.")

;;; Winds (spells.lisp has the rest: WIND-TURN, WIND-SLOW): what blows round in the level now.
(defvar *winds* (make-array 4 :adjustable T :fill-pointer 0) "The winds blowing now.")

(defgeneric wind-carry (wind x y z speed dt)
  (:documentation "Where WIND carries a flake at X Y Z, whose own SPEED is a factor about 1, in DT
seconds: (values DX DZ T), or NIL where it doesn't reach. Allocates nothing.")
  (:method (wind x y z speed dt) (declare (ignore wind x y z speed dt)) NIL))

;; Three colours of art/style/palette.txt each, hottest (or lightest) first.
(defparameter *spark-ramps*
  '((:steel "fceab6" "fcb918" "c76733")   ; Steel on steel or stone.
    (:ward "efc9fc" "c58bfd" "6f23b4")    ; A boss's or elite's ward.
    (:fire "fcb918" "fb6403" "ac0f07")    ; A torch's embers.
    (:lava "fcb918" "fe901f" "f11402")    ; Lava's.
    (:dust "c3b698" "a08a71" "77613d")    ; Grit, as pale as the ogre's dust.
    (:frost "deebfd" "a9d4fa" "45b1f5")   ; A frost nova's glitter and chips.
    (:snow "f9f9f3" "deebfd" "a9d4fa")    ; A blizzard's flakes.
    (:shock "f9f9f3" "f8ec3b" "d8aa38")   ; A shock nova's sparks.
    (:drain "f98497" "f52a5a" "7e2225")   ; A drain nova's motes.
    ;; Grit takes the second and third colours: fresh splinters are paler than the timber.
    (:wood "e0a16f" "c39e76" "8c6d54")    ; Splinters off a beam or planks.
    (:snow-chips "f9f9f3" "deebfd" "b5c3cc") ; Snow struck loose.
    ;; A broken pane's shards (glass.lisp), by its glass's colours.
    (:glass-red "f98497" "f52a5a" "ce326c")
    (:glass-gold "f8ec3b" "fcb918" "d8aa38")
    (:glass-blue "94bdfe" "45b1f5" "0a3be1")
    (:glass-green "b4ee93" "3caa3b" "317918")
    (:glass-violet "d860f5" "ba23f4" "6f23b4")
    (:glass-teal "73daea" "52979d" "204550"))
  "Per ramp: its name and three hex colours from the house palette.")

(defun spark-ramp-colors ()
  (let ((colors (make-array (* 9 (length *spark-ramps*)) :element-type 'single-float)))
    (loop for (nil . hexes) in *spark-ramps*
          for o from 0 by 9
          do (loop for hex in hexes
                   for k from o by 3
                   do (dotimes (c 3)
                        (setf (aref colors (+ k c))
                              (/ (parse-integer hex :start (* 2 c) :end (+ 2 (* 2 c)) :radix 16) 255f0)))))
    colors))

(defparameter *spark-ramp-colors* (spark-ramp-colors) "*SPARK-RAMPS*' colours, nine floats a ramp.")

(defun spark-ramp-index (name)
  (or (position name *spark-ramps* :key #'first)
      (error "No spark ramp ~s." name)))

(defvar *spark-pool* NIL "The spark pool in the current scene.")

;; Each vertex: position (3), velocity (3), head colour (3), tail colour (3), then the
;; quad's corner (2, 0 or 1), the size in texels (1; above 1 a square chip, else a streak)
;; and dissolve (1, 0 to 1), and a seed (1) for the dissolve's order.
(defparameter *spark-vertex-floats* 17)

(define-shader-entity spark-pool (renderable listener)
  ((size :reader pool-size)
   (cursor :initform 0 :accessor pool-cursor :documentation "Where the search for a free slot starts.")
   (state :reader pool-state
          :documentation "Per particle: 0 free, 1 a flying spark, 2 a spark lying cooling, 3 an ember,
4 flying grit, 5 settled grit, 6 dissolving grit, 7 a flake.")
   (ramp :reader pool-ramp :documentation "Per particle: its ramp, an index into *SPARK-RAMPS*.")
   (chip :reader pool-chip :documentation "Per grit: its size in texels; per particle else 1.")
   (tone :reader pool-tone :documentation "Per grit: the colour of its ramp it is, 1 or 2.")
   (bounces :reader pool-bounces)
   (positions :reader pool-positions)
   (velocities :reader pool-velocities)
   (ages :reader pool-ages)
   (lives :reader pool-lives :documentation "Per particle: seconds it lasts, or settled grit lies.")
   (seeds :reader pool-seeds :documentation "Per particle: a random number, 0 to 2 pi, for its wander and blink.")
   (rises :reader pool-rises :documentation "Per ember: the m/s it climbs toward; per flake, its own speed in the wind.")
   (rests :reader pool-rests :documentation "Per grit: seconds it lies once settled, or 0 for *GRIT-REST*'s.")
   (data :reader pool-data :documentation "Vertex data, 6 vertices per particle.")
   (vbo :reader pool-vbo)
   (vao :reader pool-vao)))

(defmethod initialize-instance :after ((pool spark-pool) &key)
  (let* ((n *max-sparks*)
         (data (make-array (* n 6 *spark-vertex-floats*) :element-type 'single-float :initial-element 0f0))
         (vbo (make-instance 'vertex-buffer :buffer-data data :data-usage :stream-draw))
         (stride (* 4 *spark-vertex-floats*)))
    (flet ((bytes () (make-array n :element-type '(unsigned-byte 8) :initial-element 0))
           (floats (&optional (k 1)) (make-array (* k n) :element-type 'single-float :initial-element 0f0)))
      (setf (slot-value pool 'size) n
            (slot-value pool 'state) (bytes)
            (slot-value pool 'ramp) (bytes)
            (slot-value pool 'chip) (bytes)
            (slot-value pool 'tone) (bytes)
            (slot-value pool 'bounces) (bytes)
            (slot-value pool 'positions) (floats 3)
            (slot-value pool 'velocities) (floats 3)
            (slot-value pool 'ages) (floats)
            (slot-value pool 'lives) (floats)
            (slot-value pool 'seeds) (floats)
            (slot-value pool 'rises) (floats)
            (slot-value pool 'rests) (floats)))
    (setf (slot-value pool 'data) data
          (slot-value pool 'vbo) vbo
          (slot-value pool 'vao) (make-instance 'vertex-array
                                                :vertex-form :triangles
                                                :bindings `((,vbo :size 3 :offset 0 :stride ,stride :index 0)
                                                            (,vbo :size 3 :offset 12 :stride ,stride :index 1)
                                                            (,vbo :size 3 :offset 24 :stride ,stride :index 2)
                                                            (,vbo :size 3 :offset 36 :stride ,stride :index 3)
                                                            (,vbo :size 4 :offset 48 :stride ,stride :index 4)
                                                            (,vbo :size 1 :offset 64 :stride ,stride :index 5))))))

(defmethod stage :after ((pool spark-pool) (area staging-area))
  (stage (pool-vao pool) area))

(defun add-spark-pool (scene)
  (setf *spark-pool* (make-instance 'spark-pool))
  (enter *spark-pool* scene))

(defun clear-sparks ()
  "Take every spark, ember and piece of grit away."
  (when *spark-pool*
    (fill (pool-state *spark-pool*) 0)
    (setf (pool-cursor *spark-pool*) 0)))

(defun spark-slot (pool ambient)
  "The next free slot of POOL after the last one taken. With none free, the slot after it
whatever it holds, unless AMBIENT (an ember from a torch), when NIL: a blow's sparks matter more."
  (let* ((state (pool-state pool))
         (n (pool-size pool))
         (start (pool-cursor pool))
         (i (or (loop for k from 0 below n
                      for j = (mod (+ start k) n)
                      when (= 0 (aref state j)) return j)
                (if ambient (return-from spark-slot NIL) start))))
    (declare (type (simple-array (unsigned-byte 8) (*)) state)
             (type fixnum n start))
    (setf (pool-cursor pool) (mod (1+ i) n))
    i))

(defun spawn-spark (state ramp x y z vx vy vz life &key (chip 1) (tone 1) ambient (rest 0.0))
  "Put a particle in state STATE (see SPARK-POOL) of ramp index RAMP at X Y Z, moving at VX VY
VZ m/s, for LIFE seconds; grit lies REST seconds once settled (0 for *GRIT-REST*'s). Returns its
slot, or NIL if AMBIENT and the pool is full."
  (let* ((pool *spark-pool*)
         (i (and pool (spark-slot pool ambient))))
    (when i
      (let ((p (pool-positions pool))
            (v (pool-velocities pool))
            (b (* 3 i)))
        (setf (aref (pool-state pool) i) state
              (aref (pool-ramp pool) i) ramp
              (aref (pool-chip pool) i) chip
              (aref (pool-tone pool) i) tone
              (aref (pool-bounces pool) i) 0
              (aref (pool-ages pool) i) 0f0
              (aref (pool-lives pool) i) (float life 0f0)
              (aref (pool-seeds pool) i) (random #.(float (* 2 pi) 0f0))
              (aref (pool-rises pool) i) (float vy 0f0)
              (aref (pool-rests pool) i) (float rest 0f0)
              (aref p b) (float x 0f0) (aref p (+ b 1)) (float y 0f0) (aref p (+ b 2)) (float z 0f0)
              (aref v b) (float vx 0f0) (aref v (+ b 1)) (float vy 0f0) (aref v (+ b 2)) (float vz 0f0))
        i))))

(defun spray-sparks (at dir count &key (kind :spark) ramp speed spread)
  "Throw COUNT particles of KIND (:SPARK, :EMBER or :GRIT) from point AT, fanned SPREAD radians
about the direction DIR (any length; NIL for up, and by default any way above level). RAMP
names their colours in *SPARK-RAMPS*, SPEED is the least and most m/s they leave at."
  (when *spark-pool*
    (let* ((ramp (spark-ramp-index (or ramp (ecase kind (:spark :steel) (:ember :fire) (:grit :dust)))))
           (speed (or speed (ecase kind (:spark *spark-speed*) (:ember *ember-rise*) (:grit *grit-speed*))))
           (spread (float (or spread (if dir
                                         (ecase kind (:spark *spark-spread*) (:ember 0.4) (:grit *grit-spread*))
                                         (/ pi 2)))
                          0f0))
           (dx (if dir (float (vx dir) 0f0) 0f0))
           (dy (if dir (float (vy dir) 0f0) 1f0))
           (dz (if dir (float (vz dir) 0f0) 0f0))
           (len (sqrt (+ (* dx dx) (* dy dy) (* dz dz)))))
      (if (< len 1f-5)
          (setf dx 0f0 dy 1f0 dz 0f0)
          (setf dx (/ dx len) dy (/ dy len) dz (/ dz len)))
      ;; Two directions square to DIR and each other, to fan about it.
      (multiple-value-bind (ux uy uz)
          (if (< (abs dy) 0.9)
              (let ((l (sqrt (+ (* dx dx) (* dz dz))))) (values (/ (- dz) l) 0f0 (/ dx l)))
              (let ((l (sqrt (+ (* dy dy) (* dz dz))))) (values 0f0 (/ dz l) (/ (- dy) l))))
        (let ((wx (- (* dy uz) (* dz uy)))
              (wy (- (* dz ux) (* dx uz)))
              (wz (- (* dx uy) (* dy ux))))
          (dotimes (n count)
            (let* ((theta (* spread (sqrt (random 1f0))))
                   (phi (random #.(float (* 2 pi) 0f0)))
                   (s (range-random speed))
                   (c (cos theta)) (r (sin theta))
                   (a (* r (cos phi))) (bb (* r (sin phi)))
                   (vx (* s (+ (* c dx) (* a ux) (* bb wx))))
                   (vy (* s (+ (* c dy) (* a uy) (* bb wy))))
                   (vz (* s (+ (* c dz) (* a uz) (* bb wz)))))
              (ecase kind
                (:spark (spawn-spark 1 ramp (vx at) (vy at) (vz at) vx vy vz (range-random *spark-life*)))
                (:ember (spawn-spark 3 ramp (vx at) (vy at) (vz at) vx vy vz (range-random *ember-life*)))
                (:grit (spawn-spark 4 ramp (vx at) (vy at) (vz at) vx vy vz *grit-flight*
                                    :chip (if (< (random 1f0) *grit-big-chance*) 2 1)
                                    :tone (+ 1 (random 2))))))))))))

;;; Where sparks come from in the game.

(defparameter *shield-sparks* 10 "Sparks a blow or spell glancing off a shield throws.")
(defparameter *shield-spark-height* 0.55 "Height of a shield's face, as a fraction of its bearer's.")

(defun shield-sparks (creature &optional (count *shield-sparks*))
  "Throw sparks off the face of CREATURE's shield, the way it faces: steel off a knight's,
its ward's violet off anyone else's."
  (let* ((yaw (facing creature))
         (fx (sin yaw)) (fz (- (cos yaw)))
         (loc (location creature))
         (r (* 0.9 (body-radius creature))))
    (spray-sparks (vec (+ (vx loc) (* r fx)) (+ (vy loc) (* *shield-spark-height* (sprite-height creature))) (+ (vz loc) (* r fz)))
                  (vec fx 0.35 fz) count
                  :ramp (if (typep creature 'knight) :steel :ward))))

(defun strike-sparks (creature from count &key (speed *spark-speed*))
  "Throw COUNT sparks from where a blow from point FROM strikes CREATURE: its front toward FROM,
at the height a wound bleeds, back toward FROM and up."
  (let* ((loc (location creature))
         (dx (- (vx from) (vx loc)))
         (dz (- (vz from) (vz loc)))
         (len (max 1f-4 (sqrt (+ (* dx dx) (* dz dz)))))
         (r (* 0.8 (body-radius creature))))
    (setf dx (/ dx len) dz (/ dz len))
    (spray-sparks (vec (+ (vx loc) (* r dx)) (+ (vy loc) (* *blood-wound-height* (sprite-height creature))) (+ (vz loc) (* r dz)))
                  (vec dx 0.5 dz) count :speed speed)))

(defparameter *grit-per-puff* 7 "Grit each puff of dust throws (KICK-DUST, ogre.lisp).")

(defun kick-grit (x y z &optional (count *grit-per-puff*))
  (spray-sparks (vec x (+ y 0.05) z) NIL count :kind :grit))

(defparameter *floor-sparks* 12 "Sparks a heavy blow on the floor throws: the ogre's maul, the player's earthshake.")

(defun floor-sparks (x y z &optional (count *floor-sparks*))
  (spray-sparks (vec x (+ y 0.03) z) NIL count :spread 1.2))

(defparameter *wall-strike-kinds*
  '((:stone :sparks 1.0 :grit 1.0 :grit-ramp :dust)
    (:ice-rock :sparks 0.6 :grit 1.3 :grit-ramp :frost)
    (:ice :sparks 0.0 :grit 1.5 :grit-ramp :frost)
    (:snow :sparks 0.0 :grit 2.0 :grit-ramp :snow-chips)
    (:wood :sparks 0.0 :grit 2.0 :grit-ramp :wood))
  "Per strike kind (SOLID-STRIKE, greybox.lisp): how many of a blow's sparks and grit it throws, as
a share of the weapon's, and the grit's ramp.")
(defparameter *wall-spark-glance* 0.6 "Share of the aim mirrored off the face that wall sparks go along, beside its normal.")
(defparameter *wall-spark-lift* 0.25 "Upward lean of wall sparks.")

(defun wall-sparks (x y z nx ny nz dx dy dz strike &key (sparks 8) (grit 4) (speed *spark-speed*) (spread *spark-spread*))
  "Throw a blow's SPARKS and GRIT off the face with normal NX NY NZ at X Y Z that a blow along DX
DY DZ struck, as its STRIKE kind throws them (*WALL-STRIKE-KINDS*): about the normal, glancing
the way the blow came in."
  (let* ((kind (rest (or (assoc strike *wall-strike-kinds*) (assoc :stone *wall-strike-kinds*))))
         (into (+ (* dx nx) (* dy ny) (* dz nz)))
         (g *wall-spark-glance*)
         ;; The aim mirrored off the face.
         (rx (- dx (* 2 into nx))) (ry (- dy (* 2 into ny))) (rz (- dz (* 2 into nz)))
         (at (vec (+ x (* 0.02 nx)) (+ y (* 0.02 ny)) (+ z (* 0.02 nz))))
         (dir (vec (+ nx (* g rx)) (+ ny (* g ry) *wall-spark-lift*) (+ nz (* g rz))))
         (n-sparks (round (* sparks (getf kind :sparks))))
         (n-grit (round (* grit (getf kind :grit)))))
    (when (< 0 n-sparks)
      (spray-sparks at dir n-sparks :speed speed :spread spread))
    (when (< 0 n-grit)
      (spray-sparks at dir n-grit :kind :grit :ramp (getf kind :grit-ramp) :spread (+ spread 0.3)))))

;;; Embers rise from torches and lava, each source on its own timer, only near the player.

(defparameter *ember-reach* 14.0 "Metres from the player within which a source sends up embers.")
(defparameter *torch-embers* '(0.3 0.8) "Least and most seconds between a torch's embers.")
(defparameter *lava-ember-area* 1.0 "Square metres of lava per ember a second.")

(defvar *ember-sources* (make-array 32 :adjustable T :fill-pointer 0)
  "Per source: x y z, the half-sizes it spreads over along x, y and z, its timer, its least and
most seconds between embers, its ramp index and its rise, all single floats. CLEAR-LEVEL
empties it.")

(defun add-ember-source (x y z hx hy hz lo hi ramp &optional (rise 1.0))
  (vector-push-extend (make-array 11 :element-type 'single-float
                                     :initial-contents (mapcar (lambda (v) (float v 0f0))
                                                               (list x y z hx hy hz (random (float hi 0f0)) lo hi
                                                                     (spark-ramp-index ramp) rise)))
                      *ember-sources*))

(defun add-torch-embers (x y z flame)
  "A torch's flame, FLAME metres tall, stands on X Y Z: embers leave from its upper half."
  (destructuring-bind (lo hi) *torch-embers*
    (add-ember-source x (+ y (* 0.75 flame)) z 0.04 (* 0.2 flame) 0.04 lo hi :fire)))

(defun add-lava-embers (x0 z0 x1 z1 top)
  "Embers off a lava surface at TOP from X0 Z0 to X1 Z1, as many as its area."
  (let* ((area (max 0.25 (* (- x1 x0) (- z1 z0))))
         (mean (/ *lava-ember-area* area)))
    (add-ember-source (* 0.5 (+ x0 x1)) (+ top 0.04) (* 0.5 (+ z0 z1)) (* 0.5 (- x1 x0)) 0.0 (* 0.5 (- z1 z0))
                      (* 0.5 mean) (* 1.5 mean) :lava 1.6)))

(defun send-up-embers (pool dt)
  (declare (type single-float dt) (ignore pool))
  (when *player*
    (let* ((eye (location *player*))
           (ex (vx eye)) (ey (vy eye)) (ez (vz eye))
           (reach2 (expt (float *ember-reach* 0f0) 2)))
      (declare (type single-float ex ey ez reach2))
      (loop for s across *ember-sources*
            do (let ((s s))
                 (declare (type (simple-array single-float (11)) s))
                 (when (< (+ (expt (- (aref s 0) ex) 2) (expt (- (aref s 1) ey) 2) (expt (- (aref s 2) ez) 2)) reach2)
                   (when (<= (decf (aref s 6) dt) 0f0)
                     (setf (aref s 6) (+ (aref s 7) (random (max 1f-3 (- (aref s 8) (aref s 7))))))
                     (flet ((jitter (h) (if (< 0f0 h) (- (random (* 2 h)) h) 0f0)))
                       (let ((rise (* (aref s 10) (range-random *ember-rise*))))
                         (spawn-spark 3 (floor (aref s 9))
                                      (+ (aref s 0) (jitter (aref s 3))) (+ (aref s 1) (jitter (aref s 4))) (+ (aref s 2) (jitter (aref s 5)))
                                      (jitter 0.15) rise (jitter 0.15) (range-random *ember-life*)
                                      :ambient T))))))))))

;;; Flight.

(defun bounce-spark (pool i s nx ny nz restitution friction rest-speed)
  "Particle I of POOL moved from where it is to NX NY NZ, into solid S: put it on the face it
crossed and bounce it back off it. Returns :REST if it struck the floor slower than
REST-SPEED (and so stays on it), :GONE if it was inside already, else NIL."
  (declare (type (simple-array single-float (*)) s)
           (type single-float nx ny nz restitution friction rest-speed))
  (let ((p (pool-positions pool))
        (v (pool-velocities pool))
        (b (* 3 i)))
    (declare (type (simple-array single-float (*)) p v))
    (multiple-value-bind (axis high tt) (crossed-face p b s nx ny nz)
      (cond ((diagonal-entry-p p b s axis high tt nx nz)
             (reflect-off-diagonal v b s restitution)
             NIL)
            ((< axis 0) :gone)
            (T
             (move-to-face p b s axis high tt nx ny nz)
             (let ((into (abs (aref v (+ b axis))))
                   (floor-p (and (= axis 1) high)))
               (cond ((and floor-p (< into rest-speed))
                      (setf (aref v b) 0f0 (aref v (+ b 1)) 0f0 (aref v (+ b 2)) 0f0)
                      (incf (aref p (+ b 1)) 0.002)
                      :rest)
                     (T
                      (setf (aref v (+ b axis)) (* (if high into (- into)) restitution))
                      (incf (aref p (+ b axis)) (if high 0.002 -0.002))
                      (when floor-p
                        (setf (aref v b) (* (aref v b) friction)
                              (aref v (+ b 2)) (* (aref v (+ b 2)) friction)))
                      NIL))))))))

(defun step-sparks (pool dt)
  (declare (type single-float dt))
  (let ((state (pool-state pool))
        (bounces (pool-bounces pool))
        (p (pool-positions pool))
        (v (pool-velocities pool))
        (ages (pool-ages pool))
        (lives (pool-lives pool))
        (seeds (pool-seeds pool))
        (rises (pool-rises pool))
        (spark-keep (max 0f0 (- 1f0 (* (float *spark-drag* 0f0) dt))))
        (grit-keep (max 0f0 (- 1f0 (* (float *grit-drag* 0f0) dt))))
        (spark-fall (* (float *spark-gravity* 0f0) dt))
        (grit-fall (* (float *grit-gravity* 0f0) dt))
        (buoyancy (min 1f0 (* (float *ember-buoyancy* 0f0) dt)))
        (wander (* (float *ember-wander* 0f0) dt))
        (damping (max 0f0 (- 1f0 (* (float *ember-damping* 0f0) dt))))
        (spark-bounce (float *spark-bounce* 0f0))
        (spark-friction (float *spark-friction* 0f0))
        (spark-rest (float *spark-rest-speed* 0f0))
        (grit-bounce (float *grit-bounce* 0f0))
        (grit-friction (float *grit-friction* 0f0))
        (dissolve (float *grit-dissolve-time* 0f0))
        (flutter (float *flake-flutter* 0f0))
        (flake-fall (float *flake-fall* 0f0)))
    (declare (type (simple-array (unsigned-byte 8) (*)) state bounces)
             (type (simple-array single-float (*)) p v ages lives seeds rises)
             (type single-float spark-keep grit-keep spark-fall grit-fall buoyancy wander damping
                   spark-bounce spark-friction spark-rest grit-bounce grit-friction dissolve flutter flake-fall))
    (dotimes (i (pool-size pool))
      (let ((st (aref state i))
            (b (* 3 i)))
        (unless (= 0 st)
          (let ((age (incf (aref ages i) dt)))
            (declare (type single-float age))
            (case st
              ((1 3 4 7)
               (case st
                 (1 (decf (aref v (+ b 1)) spark-fall)
                  (dotimes (k 3) (setf (aref v (+ b k)) (* spark-keep (aref v (+ b k))))))
                 (3 (let ((seed (aref seeds i)))
                      ;; Two waves crossed, so no two embers drift alike; its climb comes to its rise.
                      (incf (aref v b) (* wander (sin (+ (* age 2.3) seed))))
                      (incf (aref v (+ b 2)) (* wander (cos (+ (* age 1.7) (* 1.3 seed)))))
                      (setf (aref v b) (* damping (aref v b))
                            (aref v (+ b 2)) (* damping (aref v (+ b 2))))
                      (incf (aref v (+ b 1)) (* buoyancy (- (aref rises i) (aref v (+ b 1)))))))
                 (4 (decf (aref v (+ b 1)) grit-fall)
                  (dotimes (k 3) (setf (aref v (+ b k)) (* grit-keep (aref v (+ b k))))))
                 (7 (let ((cx 0f0) (cz 0f0) (carried NIL))
                      (declare (type single-float cx cz))
                      (loop for wind across *winds*
                            do (multiple-value-bind (dx dz in)
                                   (wind-carry wind (aref p b) (aref p (+ b 1)) (aref p (+ b 2)) (aref rises i) dt)
                                 (when in
                                   (incf cx (float dx 0f0)) (incf cz (float dz 0f0))
                                   (setf carried T))))
                      (if carried
                          (setf (aref v b) (/ cx dt)
                                (aref v (+ b 1)) (* flutter (sin (+ (* age 3.1) (aref seeds i))))
                                (aref v (+ b 2)) (/ cz dt))
                          ;; Out of the wind: it slows and falls, and its life ends it soon.
                          (setf (aref v b) (* damping (aref v b))
                                (aref v (+ b 1)) (- flake-fall)
                                (aref v (+ b 2)) (* damping (aref v (+ b 2))))))))
               (let* ((nx (+ (aref p b) (* dt (aref v b))))
                      (ny (+ (aref p (+ b 1)) (* dt (aref v (+ b 1)))))
                      (nz (+ (aref p (+ b 2)) (* dt (aref v (+ b 2)))))
                      (s (solid-at nx ny nz)))
                 (cond ((< (aref lives i) age) (setf (aref state i) 0))
                       ((liquid-at nx ny nz) (setf (aref state i) 0))
                       ((null s) (setf (aref p b) nx (aref p (+ b 1)) ny (aref p (+ b 2)) nz))
                       ((or (= st 3) (= st 7)) (setf (aref state i) 0)) ; An ember or flake that meets rock goes.
                       ((= st 1)
                        (case (bounce-spark pool i s nx ny nz spark-bounce spark-friction spark-rest)
                          (:gone (setf (aref state i) 0))
                          (:rest (setf (aref state i) 2))))
                       (T
                        ;; Grit bounces once, then settles where it next comes down.
                        (case (bounce-spark pool i s nx ny nz grit-bounce grit-friction
                                            (if (< 0 (aref bounces i)) 1f6 0.8))
                          (:gone (setf (aref state i) 0))
                          (:rest (setf (aref state i) 5 (aref ages i) 0f0
                                       (aref lives i) (let ((rest (aref (pool-rests pool) i)))
                                                        (if (< 0f0 rest) rest (float (range-random *grit-rest*) 0f0)))))
                          (T (setf (aref bounces i) 1)))))))
              (2 (when (< (aref lives i) age) (setf (aref state i) 0)))
              (5 (when (< (aref lives i) age) (setf (aref state i) 6 (aref ages i) 0f0)))
              (6 (when (< dissolve age) (setf (aref state i) 0))))))))))

(define-handler (spark-pool tick) (dt)
  (unless (frozen-p)
    (let ((dt (float (min dt 0.05) 0f0)))
      (send-up-embers spark-pool dt)
      (step-sparks spark-pool dt))))

;;; Drawing.

(defparameter *spark-corners* (coerce '(0 0 1 0 1 1 0 0 1 1 0 1) '(simple-array (unsigned-byte 8) (12))))

(defun spark-heat (pool i)
  "How far particle I of POOL has cooled, 0 to 1 over its life."
  (min 1f0 (/ (aref (pool-ages pool) i) (max 1f-3 (aref (pool-lives pool) i)))))

(defun write-spark-vertices (pool)
  "Write every live particle's quad into POOL's vertex data. Returns the vertex count."
  (let* ((state (pool-state pool))
         (ramps (pool-ramp pool))
         (chips (pool-chip pool))
         (tones (pool-tone pool))
         (p (pool-positions pool))
         (v (pool-velocities pool))
         (ages (pool-ages pool))
         (lives (pool-lives pool))
         (seeds (pool-seeds pool))
         (data (pool-data pool))
         (colors *spark-ramp-colors*)
         (corners *spark-corners*)
         (stride *spark-vertex-floats*)
         (blink (float *ember-blink* 0f0))
         (blink-rate (float *ember-blink-rate* 0f0))
         (dissolve (float *grit-dissolve-time* 0f0))
         (half-texel (/ 0.5 *texels-per-metre*))
         (k 0))
    (declare (type (simple-array (unsigned-byte 8) (*)) state ramps chips tones corners)
             (type (simple-array single-float (*)) p v ages lives seeds data colors)
             (type single-float blink blink-rate dissolve half-texel)
             (type fixnum k stride))
    (dotimes (i (pool-size pool))
      (let ((st (aref state i)))
        (unless (= 0 st)
          (let* ((b (* 3 i))
                 (age (aref ages i))
                 (heat (max 0f0 (min 0.999f0 (/ age (max 1f-3 (aref lives i))))))
                 ;; Embers keep their heat longer, and go out blinking.
                 (stage (truncate (the (single-float 0f0 3f0) (* 3f0 (if (= st 3) (* heat heat) heat)))))
                 (ramp (* 9 (aref ramps i)))
                 (chip (aref chips i))
                 (head (+ ramp (* 3 (case st ((4 5 6) (- (aref tones i) 1)) (T stage)))))
                 (tail (+ ramp (* 3 (case st ((4 5 6) (aref tones i)) (T (min 2 (1+ stage)))))))
                 ;; Sparks and embers streak as they move; the rest are still.
                 (moving (or (= st 1) (= st 3) (= st 7)))
                 ;; Lying on the floor, a particle stands on it rather than half in it.
                 (lift (case st ((2 5 6) (* chip half-texel)) (T 0f0)))
                 (fade (if (= st 6) (min 1f0 (/ age dissolve)) 0f0))
                 (shown (or (/= st 3)
                            (let ((out (/ (- heat (- 1f0 blink)) blink)))
                              (or (<= out 0f0)
                                  (let ((phase (the (single-float 0f0 1f6) (+ (* age blink-rate) (aref seeds i)))))
                                    (< out (- phase (float (truncate phase) 0f0)))))))))
            (declare (type single-float heat lift fade) (type fixnum stage ramp head tail))
            (when shown
              (loop for c from 0 below 12 by 2
                    for o = (* k stride)
                    do (setf (aref data o) (aref p b)
                             (aref data (+ o 1)) (+ lift (aref p (+ b 1)))
                             (aref data (+ o 2)) (aref p (+ b 2))
                             (aref data (+ o 3)) (if moving (aref v b) 0f0)
                             (aref data (+ o 4)) (if moving (aref v (+ b 1)) 0f0)
                             (aref data (+ o 5)) (if moving (aref v (+ b 2)) 0f0)
                             (aref data (+ o 6)) (aref colors head)
                             (aref data (+ o 7)) (aref colors (+ head 1))
                             (aref data (+ o 8)) (aref colors (+ head 2))
                             (aref data (+ o 9)) (aref colors tail)
                             (aref data (+ o 10)) (aref colors (+ tail 1))
                             (aref data (+ o 11)) (aref colors (+ tail 2))
                             (aref data (+ o 12)) (float (aref corners c) 0f0)
                             (aref data (+ o 13)) (float (aref corners (1+ c)) 0f0)
                             (aref data (+ o 14)) (float chip 0f0)
                             (aref data (+ o 15)) fade
                             (aref data (+ o 16)) (aref seeds i))
                       (incf k)))))))
    k))

(defun map-hot-sparks (function)
  "Call FUNCTION with x, y, z, how far it has cooled (0 to 1) and its ramp's name for every spark
and ember in the pool: a hook for a glow layer to put halos round them. Nothing calls it yet."
  (let ((pool *spark-pool*))
    (when pool
      (let ((p (pool-positions pool)))
        (dotimes (i (pool-size pool))
          (when (<= 1 (aref (pool-state pool) i) 3)
            (funcall function (aref p (* 3 i)) (aref p (+ 1 (* 3 i))) (aref p (+ 2 (* 3 i)))
                     (spark-heat pool i) (first (nth (aref (pool-ramp pool) i) *spark-ramps*)))))))))

(defmethod render ((pool spark-pool) (program shader-program))
  (let ((count (write-spark-vertices pool)))
    (when (< 0 count)
      (update-buffer-data (pool-vbo pool) (pool-data pool) :count (* count *spark-vertex-floats* 4))
      (setf (uniform program "view_matrix") (view-matrix))
      (setf (uniform program "projection_matrix") (projection-matrix))
      (setf (uniform program "texels_per_metre") (float *texels-per-metre* 0f0))
      (setf (uniform program "streak_time") (float *spark-streak-time* 0f0))
      (setf (uniform program "max_streak") (float *spark-max-streak* 0f0))
      (setf (uniform program "view_rows") (float (render-size (height *context*)) 0f0))
      (render-array (pool-vao pool) :vertex-count count))))

(define-class-shader (spark-pool :vertex-shader)
  "layout (location = 0) in vec3 position;
layout (location = 1) in vec3 velocity;
layout (location = 2) in vec3 in_head;
layout (location = 3) in vec3 in_tail;
layout (location = 4) in vec4 in_params;
layout (location = 5) in float in_seed;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;
uniform float texels_per_metre;
uniform float streak_time;
uniform float max_streak;
uniform float view_rows;
out vec2 texel_pos;
flat out vec2 seg;
flat out vec3 head;
flat out vec3 tail;
flat out float chip;
flat out float fade;
flat out float seed;

void main(){
  vec4 view_position = view_matrix * vec4(position, 1.0);
  chip = in_params.z;
  vec2 d = vec2(0.0);
  vec2 lo, hi;
  if(chip > 1.5){
    lo = vec2(-0.5 * chip);
    hi = vec2(0.5 * chip);
  }else{
    // The tail trails the head as far as the spark moves across the view in STREAK_TIME,
    // in whole texels, at most MAX_STREAK of them along the longer axis.
    vec2 back = -(mat3(view_matrix) * velocity).xy * (streak_time * texels_per_metre);
    float m = max(abs(back.x), abs(back.y));
    if(m > max_streak - 1.0) back *= (max_streak - 1.0) / m;
    d = floor(back + 0.5);
    lo = min(vec2(0.0), d) - 0.5;
    hi = max(vec2(0.0), d) + 0.5;
  }
  texel_pos = mix(lo, hi, in_params.xy);
  // A texel is never drawn smaller than a pixel, so a far streak stays a whole line.
  float pixels_per_metre = projection_matrix[1][1] * 0.5 * view_rows / max(0.001, -view_position.z);
  view_position.xy += texel_pos * max(1.0 / texels_per_metre, 1.0 / pixels_per_metre);
  gl_Position = projection_matrix * view_position;
  seg = d;
  head = in_head;
  tail = in_tail;
  fade = in_params.w;
  seed = in_seed;
}")

(define-class-shader (spark-pool :fragment-shader)
  "in vec2 texel_pos;
flat in vec2 seg;
flat in vec3 head;
flat in vec3 tail;
flat in float chip;
flat in float fade;
flat in float seed;
out vec4 color;

float hash(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void main(){
  vec3 c;
  if(chip > 1.5){
    // A chip of grit, lit from the upper left: its top-left texel the lighter tone.
    vec2 t = floor(texel_pos + 0.5 * chip);
    c = (t.x < 0.5 && t.y > chip - 1.5) ? head : tail;
    if(fade > 0.0 && hash(t + seed) < fade) discard;
  }else{
    // A streak from the head's texel (0, 0) to SEG, a texel per step along the longer axis.
    vec2 t = floor(texel_pos + 0.5);
    bool along_x = abs(seg.x) >= abs(seg.y);
    float m = along_x ? t.x : t.y;
    float dm = along_x ? seg.x : seg.y;
    float minor = along_x ? t.y : t.x;
    float dminor = along_x ? seg.y : seg.x;
    float k = (dm == 0.0) ? 0.0 : m / dm;
    if(k < 0.0 || k > 1.0 || (dm == 0.0 && m != 0.0)) discard;
    if(minor != floor(k * dminor + 0.5)) discard;
    float count = abs(dm) + 1.0;
    c = (abs(m) < max(1.0, floor(count / 3.0))) ? head : tail;
    if(fade > 0.0 && hash(vec2(seed)) < fade) discard;
  }
  color = vec4(c, 1.0);
}")

;;; Lightning: jagged bolts, each a line of segments that lasts a moment (BOLT-LIFE), so whatever
;;; makes them draws them anew to make them crackle. Every segment is a quad facing the view, its
;;; ends snapped to the art's pixel grid on screen (an art pixel is a 240th of the rows, as the
;;; weapons' are), drawn twice: a yellow edge BOLT-WIDTH art pixels wide, then a white core one
;;; wide, added over what is behind it. Plain arrays and one stream-draw buffer, like the sparks.

(defparameter *max-bolt-segments* 2048 "Segments the lightning holds at once; past that a new one is left out.")
(defparameter *bolt-edge* '(0.97 0.82 0.22) "Lightning's edge colour, the shock ramp's middle.")
(defparameter *bolt-core* '(0.98 0.98 0.95) "Lightning's core colour.")
(defparameter *bolt-vertex-floats* 10)
(defparameter *bolt-segment-floats* 9 "Per segment: start (3), end (3), width in art pixels, whiteness, life.")

(defvar *bolt-lines* NIL "The lightning in the current scene.")

(define-shader-entity bolt-lines (renderable listener)
  ((segments :reader bolt-segments)
   (count :initform 0 :accessor bolt-count)
   (data :reader bolt-data)
   (vbo :reader bolt-vbo)
   (vao :reader bolt-vao)))

(defmethod initialize-instance :after ((bolts bolt-lines) &key)
  (let* ((n *max-bolt-segments*)
         (data (make-array (* n 2 6 *bolt-vertex-floats*) :element-type 'single-float :initial-element 0f0))
         (vbo (make-instance 'vertex-buffer :buffer-data data :data-usage :stream-draw))
         (stride (* 4 *bolt-vertex-floats*)))
    (setf (slot-value bolts 'segments) (make-array (* n *bolt-segment-floats*) :element-type 'single-float :initial-element 0f0)
          (slot-value bolts 'data) data
          (slot-value bolts 'vbo) vbo
          (slot-value bolts 'vao) (make-instance 'vertex-array
                                                 :vertex-form :triangles
                                                 :bindings `((,vbo :size 3 :offset 0 :stride ,stride :index 0)
                                                             (,vbo :size 3 :offset 12 :stride ,stride :index 1)
                                                             (,vbo :size 4 :offset 24 :stride ,stride :index 2))))))

(defmethod stage :after ((bolts bolt-lines) (area staging-area))
  (stage (bolt-vao bolts) area))

(defun add-bolt-lines (scene)
  (setf *bolt-lines* (make-instance 'bolt-lines))
  (enter *bolt-lines* scene))

(defun clear-bolts ()
  (when *bolt-lines* (setf (bolt-count *bolt-lines*) 0)))

(defun add-bolt-segment (x0 y0 z0 x1 y1 z1 width white life)
  (let ((bolts *bolt-lines*))
    (when (and bolts (< (bolt-count bolts) *max-bolt-segments*))
      (let ((s (bolt-segments bolts))
            (o (* *bolt-segment-floats* (bolt-count bolts))))
        (setf (aref s o) (float x0 0f0) (aref s (+ o 1)) (float y0 0f0) (aref s (+ o 2)) (float z0 0f0)
              (aref s (+ o 3)) (float x1 0f0) (aref s (+ o 4)) (float y1 0f0) (aref s (+ o 5)) (float z1 0f0)
              (aref s (+ o 6)) (float width 0f0) (aref s (+ o 7)) (float white 0f0) (aref s (+ o 8)) (float life 0f0))
        (incf (bolt-count bolts))))))

(defun bolt-line (x0 y0 z0 x1 y1 z1 depth &key (roughness 0.2) sphere (width 2.0) (branch 0.0) (white 0.0)
                                                (drop 0.0) (life 0.05))
  "Add a jagged bolt from X0 Y0 Z0 to X1 Y1 Z1: midpoints moved across the line by ROUGHNESS of its
length, DEPTH times (2^DEPTH segments); on SPHERE, (centre radius), each midpoint is put back on it
first, so the bolt runs over its surface. BRANCH is the chance at each midpoint of a fork; DROP the
chance a finished segment is left out, a bolt breaking up. It lasts LIFE seconds."
  (let ((cx 0f0) (cy 0f0) (cz 0f0) (cr 0f0))
    (when sphere
      (destructuring-bind (centre radius) sphere
        (setf cx (vx centre) cy (vy centre) cz (vz centre) cr (float radius 0f0))))
    (labels ((onto (x y z)
               (if (< 0 cr)
                   (let* ((dx (- x cx)) (dy (- y cy)) (dz (- z cz))
                          (k (/ cr (max 1f-4 (sqrt (+ (* dx dx) (* dy dy) (* dz dz)))))))
                     (values (+ cx (* dx k)) (+ cy (* dy k)) (+ cz (* dz k))))
                   (values x y z)))
             (jit (len) (* len roughness (- (random 2f0) 1f0)))
             (walk (ax ay az bx by bz d w)
               (if (<= d 0)
                   (unless (< (random 1f0) drop)
                     (add-bolt-segment ax ay az bx by bz w white life))
                   (let ((len (sqrt (+ (expt (- bx ax) 2) (expt (- by ay) 2) (expt (- bz az) 2)))))
                     (multiple-value-bind (mx my mz)
                         (onto (+ (* 0.5 (+ ax bx)) (jit len)) (+ (* 0.5 (+ ay by)) (jit len)) (+ (* 0.5 (+ az bz)) (jit len)))
                       (when (and (< 0 branch) (< 1 d) (< (random 1f0) branch))
                         (let ((k (+ 0.3 (random 0.4))))
                           (multiple-value-bind (tx ty tz)
                               (onto (+ mx (* k (- bx ax)) (jit (* 1.5 len))) (+ my (* k (- by ay)) (jit (* 1.5 len)))
                                     (+ mz (* k (- bz az)) (jit (* 1.5 len))))
                             (walk mx my mz tx ty tz (- d 2) (max 1.0 (- w 1.0))))))
                       (walk ax ay az mx my mz (1- d) w)
                       (walk mx my mz bx by bz (1- d) w))))))
      (walk (float x0 0f0) (float y0 0f0) (float z0 0f0) (float x1 0f0) (float y1 0f0) (float z1 0f0) depth (float width 0f0)))))

(define-handler (bolt-lines tick) (dt)
  (unless (frozen-p)
    ;; Segments run out and the live ones close up.
    (let ((s (bolt-segments bolt-lines)) (n (bolt-count bolt-lines)) (k 0) (stride *bolt-segment-floats*))
      (dotimes (i n)
        (let ((o (* i stride)))
          (when (< 0 (decf (aref s (+ o 8)) (float dt 0f0)))
            (unless (= i k) (replace s s :start1 (* k stride) :start2 o :end2 (+ o stride)))
            (incf k))))
      (setf (bolt-count bolt-lines) k))))

(defmethod render ((bolts bolt-lines) (program shader-program))
  (let ((n (bolt-count bolts)))
    (when (< 0 n)
      (let ((s (bolt-segments bolts)) (data (bolt-data bolts)) (k 0))
        (destructuring-bind (er eg eb) *bolt-edge*
          (destructuring-bind (cr cg cb) *bolt-core*
            ;; Each segment twice: its edge, wide, then its core, an art pixel.
            (dotimes (pass 2)
              (dotimes (i n)
                (let* ((o (* i *bolt-segment-floats*))
                       (white (* 0.5 (aref s (+ o 7))))
                       (width (if (= pass 0) (aref s (+ o 6)) 1f0))
                       (r (if (= pass 0) (+ er (* white (- cr er))) cr))
                       (g (if (= pass 0) (+ eg (* white (- cg eg))) cg))
                       (b (if (= pass 0) (+ eb (* white (- cb eb))) cb)))
                  (loop for c from 0 below 12 by 2
                        for v = (* k *bolt-vertex-floats*)
                        do (replace data s :start1 v :start2 o :end2 (+ o 6))
                           (setf (aref data (+ v 6)) r (aref data (+ v 7)) g (aref data (+ v 8)) b
                                 (aref data (+ v 9)) (+ (* 4f0 (aref *spark-corners* c)) (* 2f0 (aref *spark-corners* (1+ c))) (* 0.125f0 width)))
                           (incf k)))))))
        (update-buffer-data (bolt-vbo bolts) data :count (* k *bolt-vertex-floats* 4))
        (setf (uniform program "view_matrix") (view-matrix)
              (uniform program "projection_matrix") (projection-matrix)
              (uniform program "view_rows") (float (render-size (height *context*)) 0f0)
              (uniform program "view_cols") (float (render-size (width *context*)) 0f0))
        (gl:depth-mask NIL)
        (gl:blend-func :one :one)
        (render-array (bolt-vao bolts) :vertex-count k)
        (gl:blend-func :src-alpha :one-minus-src-alpha)
        (gl:depth-mask T)))))

(define-class-shader (bolt-lines :vertex-shader)
  "layout (location = 0) in vec3 a;
layout (location = 1) in vec3 b;
layout (location = 2) in vec4 in_color;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;
uniform float view_rows;
uniform float view_cols;
out vec3 v_color;

vec2 to_px(vec4 c, vec2 size){ return (c.xy / c.w * 0.5 + 0.5) * size; }

void main(){
  vec2 size = vec2(view_cols, view_rows);
  float art = max(1.0, floor(view_rows / 240.0));
  // The corner packed in the colour's fourth: 4 for the far end, 2 for the left side, plus
  // an eighth of the width.
  float corner = in_color.w;
  float end = step(3.9, corner);
  float side = step(1.9, corner - 4.0 * end) * 2.0 - 1.0;
  float width = 8.0 * (corner - 4.0 * end - (side + 1.0));
  vec4 ca = projection_matrix * (view_matrix * vec4(a, 1.0));
  vec4 cb = projection_matrix * (view_matrix * vec4(b, 1.0));
  v_color = in_color.rgb;
  if(ca.w < 0.05 || cb.w < 0.05){ gl_Position = vec4(2.0, 2.0, 2.0, 1.0); return; }
  // Both ends on the art's pixel grid, so a bolt steps as pixel art does.
  vec2 pa = (floor(to_px(ca, size) / art) + 0.5) * art;
  vec2 pb = (floor(to_px(cb, size) / art) + 0.5) * art;
  vec2 dir = pb - pa;
  dir = dir / max(length(dir), 0.001);
  vec2 n = vec2(-dir.y, dir.x);
  float half_w = 0.5 * width * art;
  vec4 c = mix(ca, cb, end);
  vec2 e = mix(pa, pb, end);
  vec2 p = e + n * side * half_w + dir * (end * 2.0 - 1.0) * half_w;
  gl_Position = vec4(((p / size) * 2.0 - 1.0) * c.w, c.z, c.w);
}")

(define-class-shader (bolt-lines :fragment-shader)
  "in vec3 v_color;
out vec4 color;
void main(){ color = vec4(v_color, 1.0); }")
