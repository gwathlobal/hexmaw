(in-package #:hexmaw)

;;; The bloodroot: the last level's new monster, a heart-bulb rooted in the floor that never
;;; moves. Its roots do: a carpet of them (a ROOT-CARPET) grows out over the nav grid's cells,
;;; leaning toward what it hunts and toward spilt blood, and climbs the walls (a look only).
;;; Standing on them drains the player and slows them, and the bulb heals what they lose; stood
;;; on long enough they snare (the player's SNARE, player.lisp). They drink blood splats. It
;;; spits seeds that plant more roots, and its Bloom is a drain nova that feeds on everything it
;;; reaches, its own side too. After a Bloom or a big drink it gluts: its roots grow twice as
;;; fast, it spits twice as often, and it is washed red (OWN-TINT).
;;;
;;; Fire burns roots back, frost holds them (TOUCH-ROOTS, from bursts, novas, impacts and the
;;; firestorm), the maul's earthshake tears them up (TEAR-ROOTS), and they wither when it dies.

(defparameter *bloodroot-height* 1.4 "The bulb's height in metres.")
(defparameter *bloodroot-radius* 0.6 "The bulb's body radius in metres.")

(defparameter *root-reach* 10.0 "Metres from the bulb its main carpet grows to.")
(defparameter *root-ring-time* 0.4 "Seconds between rings of growth.")
(defparameter *root-start-rings* 3 "Rings a bulb's carpet has before it notices anything.")
(defparameter *root-lean* 0.35
  "How nearly a step of growth must point at its target or at blood to grow every ring; the rest
grow every other ring.")
(defparameter *root-lean-reach* 6.0 "Metres within which blood draws the roots toward it.")
(defparameter *root-climb* 2.5 "Metres up a wall roots climb.")
(defparameter *root-climb-time* 3.0 "Seconds roots take to climb a wall that high.")
(defparameter *root-grow-in* 0.4 "Seconds a new cell of roots takes to spread over it.")
(defparameter *root-body* '(0.1 0.3 0.45)
  "The radius, height and step roots grow as, over the nav grid: under low things and up steps.")

(defparameter *root-drain* 3.0 "Health a second roots drain from the player standing on them.")
(defparameter *root-slow* 30 "Percent roots slow the player standing on them.")
(defparameter *root-drain-tick* 0.5 "Seconds between the blows of the roots' drain.")

(defparameter *snare-stand* 1.0 "Seconds on roots before they close on the player.")
(defparameter *snare-tell* 0.6 "Seconds the roots bulge before they grab: a jump or a step off escapes.")
(defparameter *snare-hold* 1.5 "Seconds the roots hold the player.")
(defparameter *snare-drain* 8.0 "Health a second held roots drain.")
(defparameter *snare-reach* 0.6 "Metres the player may be from where the roots bulged and still be grabbed.")
(defparameter *snare-sprite-ring* 0.45 "Metres out from the snared feet its roots burst up.")

(defparameter *spit-range* 16.0 "Metres its seed reaches.")
(defparameter *spit-cooldown* 3.0)
(defparameter *glut-spit-cooldown* 1.5)
(defparameter *seed-apex* 2.5 "Metres above the higher end a seed's arc tops out.")
(defparameter *seed-gravity* 14.0)
(defparameter *seed-lead* 0.6 "Seconds of the target's walk a seed is aimed ahead.")
(defparameter *seed-lead-max* 2.0)
(defparameter *seed-scatter* 1.0 "Metres a seed lands off its aim at most.")
(defparameter *seed-patch-radius* 1.25 "Metres a seed's patch of roots spreads.")
(defparameter *seed-patch-time* 12.0 "Seconds a seed's patch lasts.")
(defparameter *seed-ring-time* 0.12)
(defparameter *max-seed-patches* 4 "Seed patches a bulb keeps; the oldest goes.")
(defparameter *seed-floor-drop* 2.0 "Metres below a seed's burst its floor may be.")

(defparameter *bloom-radius* 8.0 "Metres its Bloom reaches.")
(defparameter *bloom-cooldown* 20.0)
(defparameter *bloom-first* 6.0 "Seconds after it first notices anything before it may bloom.")
(defparameter *bloom-crowd* 4 "Bodies in its Bloom's reach that set it off at once.")
(defparameter *bloom-crowd-gap* 6.0 "Seconds after a Bloom before a crowd sets off another.")
(defparameter *bloom-surge* 3 "Rings its roots grow at once after a Bloom.")

(defparameter *glut-time* 6.0 "Seconds of Glut after a Bloom or a big drink.")
(defparameter *glut-drink* 15 "Health drunk within a second that sets off Glut.")
(defparameter *glut-tint* '(0.35 0.5) "The red wash's strength in Glut, low and high, pulsing.")
(defparameter *glut-pulse* 2.0 "The wash's pulses a second.")
(defparameter *glut-color* (vec 0.85 0.05 0.08))

(defparameter *drink-time* 1.0 "Seconds roots take to drink a splat they reach.")
(defparameter *drink-per-area* 0.03 "Health a splat's art pixel squared of blood gives.")
(defparameter *drink-max* 25 "Health one splat gives at most.")
(defparameter *drink-scan* 0.25 "Seconds between looks for splats to drink.")

(defparameter *root-burn-hold* 5.0 "Seconds burnt or torn roots take to start growing back.")
(defparameter *root-frost-time* 6.0 "Seconds frost holds roots: no growth, no drain, no snare.")
(defparameter *root-wither-time* 1.5 "Seconds its roots take to wither when it dies.")
(defparameter *bolt-scorch-radius* 0.75 "Metres a single fire or frost hit with no area touches roots round it.")
(defparameter *root-touch-height* 1.5 "Metres above or below a hit roots it touches may lie.")

(defparameter *bloodroot-light* (vec 0.5 0.06 0.05) "Its veins' glow at rest.")
(defparameter *bloodroot-light-radius* 3.5)
(defparameter *bloom-light* (vec 2.6 0.35 0.25) "Its glow just before a Bloom bursts.")
(defparameter *bloom-light-radius* 9.0)

;;; Its strips: one view, so each is a single sequence. Sliced so the bulb at rest is 90 px
;;; (1.4 m at 64 px a metre); a strip's :SIZE is its cell height over 64.

(defun bloodroot-atlas ()
  (append (read-atlas "sprites/bloodroot/turnaround.lisp") (list :views '(:front))))

(define-asset (hexmaw bloodroot-turnaround) image
    #p"sprites/bloodroot/turnaround.png"
  :min-filter :nearest :mag-filter :nearest)

(define-fx-animation bloodroot-idle "sprites/bloodroot/idle" :fps 6 :loop T :size (/ 92 64.0))
(define-fx-animation bloodroot-spit "sprites/bloodroot/spit" :size (/ 91 64.0))
(define-fx-animation bloodroot-bloom "sprites/bloodroot/bloom" :size (/ 91 64.0))
(define-fx-animation bloodroot-hurt "sprites/bloodroot/hurt" :size (/ 90 64.0))
(define-fx-animation bloodroot-death "sprites/bloodroot/death" :fps 8 :size (/ 90 64.0))
(define-fx-animation snare-roots "sprites/bloodroot/snare" :fps 10 :loop T :size (/ 51 64.0))
(define-fx-animation seed-flight "sprites/bloodroot/seed-flight" :fps 10 :loop T :size (/ 46 64.0))
(define-fx-animation seed-burst "sprites/bloodroot/seed-burst" :fps 14 :size (/ 78 64.0))

;; The roots, laid over floors and walls in world space (ROOT-FLOOR); magenta between them keyed
;; to see-through, so the stone shows.
(define-asset (hexmaw bloodroot-roots) image #p"textures/bloodroot.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)

(define-spell blood-seed (:delivery :projectile :projectile-speed 9.0 :title "Blood Seed" :lifetime 4.0
                          :projectile-animation 'seed-flight :impact-animation 'seed-burst
                          :light-color (vec 1.4 0.15 0.2) :light-radius 2.5)
  ;; Damage, so a seed coming at the player can be swallowed by Absorb.
  (:damage :magnitude '(3 5)))

(define-spell bloom (:delivery :nova :nova-radius *bloom-radius* :title "Bloom")
  ;; Its drain heals the bulb for all of it (DRAIN-SHARE), and it spares no one but the bulb.
  (:drain :magnitude '(10 14)))

(defun bloodroot-abilities ()
  (list (make-instance 'ability :name :spit :spell 'blood-seed :animation 'bloodroot-spit
                                :frame-times '(0.25 0.2 0.2 0.3) :hit-frame 2 :pause 0.6
                                :cooldown *spit-cooldown*)
        ;; The clench is held as the tell: 1.2 s from the start to the burst.
        (make-instance 'ability :name :bloom :spell 'bloom :animation 'bloodroot-bloom
                                :frame-times '(0.3 0.9 0.25 0.5) :hit-frame 2 :pause 1.2
                                :cooldown *bloom-cooldown*)))

(define-shader-entity bloodroot (ability-user creature)
  ((texture :initform (// 'hexmaw 'bloodroot-turnaround))
   (atlas :initform (bloodroot-atlas))
   (sprite-height :initform *bloodroot-height*)
   (body-radius :initform *bloodroot-radius*)
   (attack-animation :initform 'bloodroot-spit)
   (hurt-animation :initform 'bloodroot-hurt)
   (death-animation :initform 'bloodroot-death)
   (abilities :initform (bloodroot-abilities))
   (cooldowns :initform (list :spit 0.0 :bloom *bloom-first*))
   (max-health :initform 110)
   (pain-chance :initform 10)
   (walk-speed :initform 0.0)
   (wander-radius :initform 0.0)
   (attack-range :initform *spit-range*)
   (keep-away :initform 0.0)
   (cast-offset :initform 0.0)
   ;; Sap, not blood: its own blood would feed its roots.
   (bleeds :initform NIL)
   (death-blood :initform 0)
   (carpet :initform NIL :accessor carpet :documentation "Its main ROOT-CARPET, once the nav grid is there.")
   (patches :initform () :accessor patches :documentation "Its seeds' carpets, newest first.")
   (glut :initform 0.0 :accessor glut :documentation "Seconds of Glut left.")
   (drain-carry :initform 0.0 :accessor drain-carry :documentation "Health drained but not yet taken.")
   (drain-timer :initform 0.0 :accessor drain-timer)
   (stand :initform 0.0 :accessor stand :documentation "Seconds its target has stood on its roots.")
   (drinking :initform (make-array *max-blood* :element-type 'single-float :initial-element -1f0)
             :reader drinking :documentation "Seconds each blood pool slot has been drunk, or -1.")
   (drink-timer :initform 0.0 :accessor drink-timer)
   (heal-carry :initform 0.0 :accessor heal-carry :documentation "Health drunk but not yet whole.")
   (drunk :initform 0.0 :accessor drunk :documentation "Health drunk in the last second.")
   (drunk-left :initform 0.0 :accessor drunk-left)
   (last-bloom :initform 100.0 :accessor last-bloom :documentation "Seconds since its last Bloom.")
   (swelled :initform NIL :accessor swelled :documentation "True once this Bloom's tell has sounded.")
   (lamp :initform NIL :accessor bloodroot-lamp)
   (snare-sprites :initform () :accessor snare-sprites)))

(define-creature-sounds bloodroot
  :alert :bloodroot-alert :pain :bloodroot-pain :death :bloodroot-death)

;; Its idle pulse is no ability's strip, so the scene doesn't stage it on its own.
(defmethod stage :after ((bloodroot bloodroot) (area staging-area))
  (stage (animation-texture (find-fx-animation 'bloodroot-idle)) area))

(defmethod rooted-p ((bloodroot bloodroot)) T)
(defmethod vortex-proof-p ((bloodroot bloodroot)) T)
(defmethod drain-share ((bloodroot bloodroot)) 1.0)
(defmethod taught-effect ((bloodroot bloodroot)) :drain)

(defgeneric root-reach (bloodroot)
  (:method ((bloodroot bloodroot)) *root-reach*))

(defgeneric root-speed (bloodroot)
  (:documentation "How many times as fast BLOODROOT's roots grow.")
  (:method ((bloodroot bloodroot)) (if (< 0 (glut bloodroot)) 2.0 1.0)))

;; It never walks: no wander, and its hunt never closes in or backs off.
(defmethod wander ((bloodroot bloodroot))
  (setf (idle-timer bloodroot) (wander-pause)))

(defmethod heal-caster ((bloodroot bloodroot) amount)
  (call-next-method)
  (when (< 0 amount)
    (spray-sparks (v+ (location bloodroot) (vec 0 (* 0.5 *bloodroot-height*) 0)) NIL (min 12 (ceiling amount 2))
                  :kind :ember :ramp :drain)))

;;; The carpet: cells of the nav grid in a window round its centre, every layer, each empty (0),
;;; rooted (1) or burnt (2, growing back after HOLD); a rooted cell may be frosted (FROST). Growth
;;; spreads from the FRONTIER, the rooted cells with room to grow, a ring at a time, through
;;; NAV-STEP: so never through a plugged doorway, over lava or into water, and up and down steps.

(defvar *root-clock* 0f0
  "Seconds the root floor has run while the world does: each cell notes when it rooted, and the
shader spreads it and climbs its wall from then.")
(defvar *roots-dirty* T "True when a carpet changed since the root floor last wrote its cells.")

(defclass root-carpet ()
  ((owner :initarg :owner :reader carpet-owner)
   (kind :initarg :kind :initform :main :reader carpet-kind :documentation ":MAIN or :SEED.")
   (centre :initarg :centre :reader carpet-centre :documentation "Where it grew from, on its floor.")
   (reach :initarg :reach :reader carpet-reach)
   (life :initarg :life :initform NIL :accessor carpet-life :documentation "Seconds left, or NIL for good.")
   (wither :initform NIL :accessor carpet-wither :documentation "NIL, or 0 to 1 as it withers away.")
   (ring-time :initarg :ring-time :initform *root-ring-time* :reader ring-time)
   (ring-timer :initform 0.0 :accessor ring-timer)
   (ring :initform 0 :accessor carpet-ring)
   (i0 :reader carpet-i0) (j0 :reader carpet-j0) (n :reader carpet-n) (layers :reader carpet-layers)
   (state :reader carpet-state) (born :reader carpet-born) (hold :reader carpet-hold) (frost :reader carpet-frost)
   (walls :reader carpet-walls :documentation "Per cell and side (+X -X +Z -Z): the wall's distance from
the cell's centre and its top over the floor, both -1 for none; found when it roots.")
   (frontier :reader frontier) (next :reader next-frontier)
   (queued :reader carpet-queued :documentation "A bit per cell: in the frontier.")
   (rooted :initform 0 :accessor rooted-count)))

(defmethod initialize-instance :after ((carpet root-carpet) &key)
  (let* ((grid *nav-grid*)
         (c (nav-cell-size grid))
         (at (carpet-centre carpet))
         (half (+ 2 (ceiling (carpet-reach carpet) c)))
         (n (1+ (* 2 half)))
         (layers (nav-layers grid))
         (size (* n n layers)))
    (multiple-value-bind (ci cj) (nav-cell (vx at) (vz at) grid)
      (setf (slot-value carpet 'i0) (- (or ci 0) half)
            (slot-value carpet 'j0) (- (or cj 0) half)))
    (setf (slot-value carpet 'n) n
          (slot-value carpet 'layers) layers
          (slot-value carpet 'state) (make-array size :element-type '(unsigned-byte 8) :initial-element 0)
          (slot-value carpet 'born) (make-array size :element-type 'single-float :initial-element 0f0)
          (slot-value carpet 'hold) (make-array size :element-type 'single-float :initial-element 0f0)
          (slot-value carpet 'frost) (make-array size :element-type 'single-float :initial-element 0f0)
          (slot-value carpet 'walls) (make-array (* 8 size) :element-type 'single-float :initial-element -1f0)
          (slot-value carpet 'frontier) (make-array 256 :element-type 'fixnum :adjustable T :fill-pointer 0)
          (slot-value carpet 'next) (make-array 256 :element-type 'fixnum :adjustable T :fill-pointer 0)
          (slot-value carpet 'queued) (make-array size :element-type 'bit :initial-element 0))))

(declaim (inline cell-index))
(defun cell-index (carpet a b k)
  (let ((n (carpet-n carpet)))
    (+ a (* n (+ b (* n k))))))

(defun cell-coords (carpet w)
  "Values A B K of window cell W."
  (let ((n (carpet-n carpet)))
    (multiple-value-bind (rest a) (floor w n)
      (multiple-value-bind (k b) (floor rest n)
        (values a b k)))))

(defun cell-floor (carpet a b k)
  (nav-floor (+ (carpet-i0 carpet) a) (+ (carpet-j0 carpet) b) k))

(defun cell-point (carpet a b)
  "Values X Z of the middle of window column A B."
  (let ((grid *nav-grid*))
    (values (+ (nav-x0 grid) (* (+ (carpet-i0 carpet) a 0.5) (nav-cell-size grid)))
            (+ (nav-z0 grid) (* (+ (carpet-j0 carpet) b 0.5) (nav-cell-size grid))))))

(defun carpet-cell-at (carpet x y z)
  "The window cell of CARPET whose floor X Y Z stands on, or NIL."
  (when *nav-grid*
    (multiple-value-bind (i j) (nav-cell x z)
      (when i
        (let ((a (- i (carpet-i0 carpet))) (b (- j (carpet-j0 carpet))) (n (carpet-n carpet)))
          (when (and (< -1 a n) (< -1 b n))
            (let ((k (nav-layer i j (+ y 0.05))))
              (when k (cell-index carpet a b k)))))))))

(defun cell-live-p (carpet w)
  "True if window cell W is rooted, not frosted."
  (and (= 1 (aref (carpet-state carpet) w)) (<= (aref (carpet-frost carpet) w) 0)))

(defun queue-cell (carpet w)
  (when (= 0 (sbit (carpet-queued carpet) w))
    (setf (sbit (carpet-queued carpet) w) 1)
    (vector-push-extend w (next-frontier carpet))))

(defun find-walls (carpet a b k)
  "Note the walls beside window cell A B K, for roots to climb."
  (let* ((w (cell-index carpet a b k))
         (walls (carpet-walls carpet))
         (floor (cell-floor carpet a b k))
         (c (nav-cell-size *nav-grid*)))
    (multiple-value-bind (x z) (cell-point carpet a b)
      (loop for side from 0
            for (dx dz) in '((1 0) (-1 0) (0 1) (0 -1))
            do (let ((y (+ floor 0.3))
                     (face NIL))
                 ;; The wall's face: the first solid out from the middle, within the cell's edge.
                 (loop for d from 0.05 to (+ (* 0.5 c) 0.06) by 0.03
                       when (solid-at (+ x (* dx d)) y (+ z (* dz d)))
                         do (setf face (- d 0.03)) (return))
                 (when face
                   (let ((top (loop for h from 0.5 to *root-climb* by 0.25
                                    while (solid-at (+ x (* dx (+ face 0.05))) (+ floor h) (+ z (* dz (+ face 0.05))))
                                    finally (return (- h 0.25)))))
                     (setf (aref walls (+ (* 8 w) (* 2 side))) (float face 0f0)
                           (aref walls (+ (* 8 w) (* 2 side) 1)) (float (max 0.25 top) 0f0)))))))))

(defun root-cell (carpet a b k)
  (let ((w (cell-index carpet a b k)))
    (setf (aref (carpet-state carpet) w) 1
          (aref (carpet-born carpet) w) *root-clock*
          *roots-dirty* T)
    (incf (rooted-count carpet))
    (find-walls carpet a b k)
    (queue-cell carpet w)))

(defun cell-allowed-p (carpet a b k)
  "True if roots may grow into window cell A B K: within its reach, not burnt, and not under the
arena's gate (a solid the nav grid doesn't know of)."
  (let ((w (cell-index carpet a b k)))
    (and (= 0 (aref (carpet-state carpet) w))
         (multiple-value-bind (x z) (cell-point carpet a b)
           (let ((at (carpet-centre carpet)) (floor (cell-floor carpet a b k)))
             (and (<= (+ (expt (- x (vx at)) 2) (expt (- z (vz at)) 2)) (expt (carpet-reach carpet) 2))
                  (not (solid-at x (+ floor 0.5) z))))))))

(defun start-carpet (owner kind at reach &key life (ring-time *root-ring-time*))
  "A carpet for OWNER, rooted on the floor cell at AT, or NIL if there is none there."
  (when *nav-grid*
    (let* ((carpet (make-instance 'root-carpet :owner owner :kind kind :centre (vcopy at) :reach reach
                                               :life life :ring-time ring-time))
           (w (carpet-cell-at carpet (vx at) (vy at) (vz at))))
      (when w
        (multiple-value-bind (a b k) (cell-coords carpet w)
          (root-cell carpet a b k)
          (swap-frontier carpet)
          carpet)))))

(defun swap-frontier (carpet)
  "The cells queued become the frontier."
  (let ((now (frontier carpet)) (next (next-frontier carpet)))
    (setf (fill-pointer now) 0)
    (loop for w across next do (vector-push-extend w now))
    (setf (fill-pointer next) 0)))

(defvar *lean-points* (make-array 16 :element-type 'single-float :fill-pointer 0)
  "X Z pairs a ring of growth leans toward.")

(defun note-lean-points (carpet target)
  "Fill *LEAN-POINTS* with TARGET's feet and the floor splats near CARPET's frontier."
  (let ((points *lean-points*))
    (setf (fill-pointer points) 0)
    (when target
      (let ((feet (body-feet target)))
        (vector-push (float (vx feet) 0f0) points)
        (vector-push (float (vz feet) 0f0) points)))
    (when *blood-pool*
      (let ((at (carpet-centre carpet))
            (reach (+ (carpet-reach carpet) *root-lean-reach*)))
        (dotimes (i (pool-size *blood-pool*))
          (when (and (< (fill-pointer points) 16) (splat-lying-p *blood-pool* i))
            (multiple-value-bind (x y z face) (splat-place *blood-pool* i)
              (when (and (= face 2) (< (abs (- y (vy at))) 1.5)
                         (< (+ (expt (- x (vx at)) 2) (expt (- z (vz at)) 2)) (* reach reach)))
                (vector-push x points)
                (vector-push z points)))))))
    points))

(defun leans-p (x z dx dz points)
  "True if a step DX DZ from X Z points at one of POINTS within *ROOT-LEAN-REACH*."
  (let ((len (sqrt (+ (* dx dx) (* dz dz)))))
    (loop for p from 0 below (fill-pointer points) by 2
          thereis (let* ((tx (- (aref points p) x)) (tz (- (aref points (1+ p)) z))
                         (tl (sqrt (+ (* tx tx) (* tz tz)))))
                    (and (< 0.01 tl *root-lean-reach*)
                         (<= *root-lean* (/ (+ (* tx dx) (* tz dz)) (* tl len))))))))

(defun grow-ring (carpet &optional points (all NIL))
  "Grow CARPET a ring: every frontier cell into the neighbours it may root, those POINTS lean
toward on every ring, the rest on every other (or all at once, ALL)."
  (let ((grid *nav-grid*)
        (state (carpet-state carpet))
        (frost (carpet-frost carpet))
        (n (carpet-n carpet))
        (even (evenp (carpet-ring carpet)))
        (*nav-hazards* :avoid)
        (*nav-bodies* NIL)
        (*nav-body-mask* NIL))
    (destructuring-bind (radius height step) *root-body*
      (loop for w across (frontier carpet)
            do (setf (sbit (carpet-queued carpet) w) 0)
               (when (= 1 (aref state w))
                 (multiple-value-bind (a b k) (cell-coords carpet w)
                   (let ((i (+ (carpet-i0 carpet) a)) (j (+ (carpet-j0 carpet) b))
                         (more NIL))
                     (if (< 0 (aref frost w))
                         (setf more T)
                         (multiple-value-bind (x z) (cell-point carpet a b)
                           (loop for di from -1 to 1
                                 do (loop for dj from -1 to 1
                                          unless (and (= di 0) (= dj 0))
                                            do (let ((na (+ a di)) (nb (+ b dj)))
                                                 (when (and (< -1 na n) (< -1 nb n))
                                                   (let ((nk (nav-step i j k (+ i di) (+ j dj) radius height step grid)))
                                                     (when (and nk (cell-allowed-p carpet na nb nk))
                                                       (if (or all even (and points (leans-p x z di dj points)))
                                                           (root-cell carpet na nb nk)
                                                           (setf more T))))))))))
                     (when more (queue-cell carpet w))))))))
    (incf (carpet-ring carpet))
    (swap-frontier carpet))

(defun regrow-cells (carpet dt)
  "Count CARPET's burnt cells' and frost's time down; a burnt cell that may grow again is empty,
and the rooted cells round it grow into it."
  (let ((state (carpet-state carpet)) (hold (carpet-hold carpet)) (frost (carpet-frost carpet))
        (n (carpet-n carpet)) (dt (float dt 0f0)))
    (dotimes (w (length state))
      (when (< 0 (aref frost w))
        (setf (aref frost w) (max 0f0 (- (aref frost w) dt)))
        (when (= 0 (aref frost w)) (setf *roots-dirty* T)))
      (when (= 2 (aref state w))
        (when (<= (decf (aref hold w) dt) 0)
          (setf (aref state w) 0)
          (multiple-value-bind (a b k) (cell-coords carpet w)
            (declare (ignore k))
            (loop for di from -1 to 1
                  do (loop for dj from -1 to 1
                           do (let ((na (+ a di)) (nb (+ b dj)))
                                (when (and (< -1 na n) (< -1 nb n))
                                  (dotimes (nk (carpet-layers carpet))
                                    (let ((nw (cell-index carpet na nb nk)))
                                      (when (and (= 1 (aref state nw)) (= 0 (sbit (carpet-queued carpet) nw)))
                                        ;; Into the frontier now: it grows into the gap next ring.
                                        (setf (sbit (carpet-queued carpet) nw) 1)
                                        (vector-push-extend nw (frontier carpet)))))))))))))))

(defun touch-carpet (carpet at radius how)
  "Burn (:FIRE), frost (:FROST) or tear (:TEAR) CARPET's rooted cells within RADIUS of AT.
Returns how many."
  (let ((state (carpet-state carpet)) (touched 0) (n (carpet-n carpet)) (r2 (* radius radius)))
    (dotimes (a n)
      (dotimes (b n)
        (multiple-value-bind (x z) (cell-point carpet a b)
          (when (<= (+ (expt (- x (vx at)) 2) (expt (- z (vz at)) 2)) r2)
            (dotimes (k (carpet-layers carpet))
              (let ((w (cell-index carpet a b k)))
                (when (and (= 1 (aref state w))
                           (< (abs (- (cell-floor carpet a b k) (vy at))) *root-touch-height*))
                  (incf touched)
                  (if (eq how :frost)
                      (setf (aref (carpet-frost carpet) w) (float *root-frost-time* 0f0))
                      (setf (aref state w) 2
                            (aref (carpet-hold carpet) w) (float *root-burn-hold* 0f0)
                            (aref (carpet-frost carpet) w) 0f0
                            (rooted-count carpet) (1- (rooted-count carpet)))))))))))
    (when (< 0 touched) (setf *roots-dirty* T))
    touched))

(defmacro do-bloodroots ((root) &body body)
  "Run BODY with ROOT each bloodroot of the level, live or withering."
  `(loop for ,root across *creatures*
         when (typep ,root 'bloodroot) do (progn ,@body)))

(defmacro do-carpets ((carpet bloodroot) &body body)
  "Run BODY with CARPET each of BLOODROOT's carpets, its main one first."
  (let ((root (gensym "ROOT")))
    `(let ((,root ,bloodroot))
       (let ((,carpet (carpet ,root)))
         (when ,carpet ,@body))
       (dolist (,carpet (patches ,root))
         ,@body))))

(defun all-carpets (bloodroot)
  (let ((main (carpet bloodroot)))
    (if main (cons main (patches bloodroot)) (patches bloodroot))))

(defun touch-roots (at radius element)
  "A hit of ELEMENT reached the floor round AT out to RADIUS: fire burns roots there, frost holds
them, :TEAR tears them up."
  (let ((how (case element (:fire :fire) (:frost :frost) (:tear :tear)))
        (radius (max radius *bolt-scorch-radius*)))
    (when (and how (< 0 (fill-pointer *creatures*)))
      (let ((touched 0))
        (do-bloodroots (root)
          (do-carpets (carpet root)
            (incf touched (touch-carpet carpet at radius how))))
        (when (< 0 touched)
          (case how
            (:fire (spray-sparks at NIL (min 24 (+ 4 (floor touched 4))) :kind :ember :ramp :fire)
                   (play-sound :roots-burn at))
            (:frost (spray-sparks at NIL (min 16 (+ 3 (floor touched 6))) :kind :grit :ramp :frost))
            (:tear (spray-sparks at NIL (min 20 (+ 4 (floor touched 4))) :kind :grit :ramp :drain))))
        touched))))

(defun frost-under-rime (carpet)
  "A rime patch (skins.lisp) lying over CARPET holds the roots under it, as frost does."
  (dolist (skin *skins*)
    (when (and (typep skin 'frost-patch) (container skin) (skin-entry skin))
      (let ((at (location skin)) (r (aref (skin-entry skin) 3)) (c (carpet-centre carpet)))
        (when (< (+ (expt (- (vx at) (vx c)) 2) (expt (- (vz at) (vz c)) 2))
                 (expt (+ r (carpet-reach carpet)) 2))
          (touch-carpet carpet at r :frost))))))

(defun tear-roots (at radius)
  (touch-roots at radius :tear))

(defun roots-at (x y z)
  "The bloodroot whose live roots (not frosted) X Y Z stands on, the nearest if several; NIL."
  (let ((best NIL) (best-d 0.0))
    (do-bloodroots (root)
      (unless (dead root)
        (do-carpets (carpet root)
          (unless (carpet-wither carpet)
            (let ((w (carpet-cell-at carpet x y z)))
              (when (and w (cell-live-p carpet w))
                (let* ((at (location root))
                       (d (+ (expt (- (vx at) x) 2) (expt (- (vy at) y) 2) (expt (- (vz at) z) 2))))
                  (when (or (null best) (< d best-d))
                    (setf best root best-d d)))))))))
    best))

;;; The tick.

(define-handler (bloodroot tick :before) ()
  ;; Rooted: nothing moves it.
  (let ((m (momentum bloodroot)))
    (setf (vx m) 0f0 (vy m) 0f0 (vz m) 0f0)))

(defun bloodroot-target (bloodroot)
  "The player, if BLOODROOT hunts them or would: its roots feed only on them."
  (let ((target (hunt-target bloodroot)))
    (and (typep target 'player) (target-live-p target) target)))

(defun on-floor-p (player)
  (and (grounded player) (not (swimming player)) (not (whirl player)) (not (climbing player))
       (<= (vy (velocity player)) 0.01)))

(defun grow-carpets (bloodroot dt)
  (let ((target (bloodroot-target bloodroot))
        (speed (root-speed bloodroot)))
    (do-carpets (carpet bloodroot)
      (when (<= (decf (ring-timer carpet) (* speed dt)) 0)
        (setf (ring-timer carpet) (ring-time carpet))
        (regrow-cells carpet (ring-time carpet))
        (frost-under-rime carpet)
        ;; The main carpet grows while it hunts; a seed's at once.
        (when (or (eq (carpet-kind carpet) :seed) (hunting-p bloodroot))
          (grow-ring carpet (note-lean-points carpet target) (eq (carpet-kind carpet) :seed)))))
    ;; Seed patches go when their time is up, shrinking over their last second.
    (dolist (patch (patches bloodroot))
      (when (carpet-life patch)
        (decf (carpet-life patch) dt)
        (when (< (carpet-life patch) 1.0)
          (setf (carpet-wither patch) (max 0.0 (- 1.0 (carpet-life patch)))
                *roots-dirty* T))))
    (when (find-if (lambda (p) (<= (carpet-life p) 0)) (patches bloodroot))
      (setf (patches bloodroot) (delete-if (lambda (p) (<= (carpet-life p) 0)) (patches bloodroot))
            *roots-dirty* T))))

(defun feed-on (bloodroot dt)
  "Drain and slow the player standing on BLOODROOT's roots, and close them on one who stays."
  (let* ((player (bloodroot-target bloodroot))
         (feet (and player (feet player)))
         (on (and player (on-floor-p player)
                  (eq bloodroot (roots-at (vx feet) (vy feet) (vz feet)))))
         (snare (and player (snare player)))
         (mine (and snare (eq bloodroot (getf snare :root)))))
    (when on
      (afflict player :slow *root-slow* 0.6 :caster bloodroot)
      (setf (alert bloodroot) (max (alert bloodroot) (alert-time))))
    (let ((rate (cond ((and mine (eq :held (getf snare :phase))) *snare-drain*)
                      (on *root-drain*)
                      (T 0.0))))
      (incf (drain-carry bloodroot) (* rate dt))
      (when (<= (decf (drain-timer bloodroot) dt) 0)
        (setf (drain-timer bloodroot) *root-drain-tick*)
        (let ((whole (floor (drain-carry bloodroot))))
          (when (and player (< 0 whole))
            (decf (drain-carry bloodroot) whole)
            (let ((before (health player)))
              (hurt-player player whole feet :shove NIL :unblockable T :by bloodroot)
              (heal-caster bloodroot (- before (max 0 (health player))))))
          (when (= 0 rate) (setf (drain-carry bloodroot) 0.0)))))
    ;; The snare: on the roots long enough, they bulge, then grab.
    (setf (stand bloodroot) (if on (+ (stand bloodroot) dt) 0.0))
    (when (and on (null snare) (<= (snare-guard player) 0) (<= *snare-stand* (stand bloodroot)))
      (setf (snare player) (list :root bloodroot :phase :tell :left *snare-tell* :at (vcopy feet)))
      (kick-grit (vx feet) (vy feet) (vz feet))
      (play-sound :snare-tell))
    (when mine
      (update-snare bloodroot player dt))))

(defun snare-cell-live-p (bloodroot at)
  (eq bloodroot (roots-at (vx at) (vy at) (vz at))))

(defun update-snare (bloodroot player dt)
  (let* ((snare (snare player))
         (at (getf snare :at))
         (left (- (getf snare :left) dt)))
    (setf (getf (snare player) :left) left)
    (cond ((not (snare-cell-live-p bloodroot at))
           ;; Burnt, frosted or torn up under the feet.
           (break-snare player))
          ((< 0 left))
          ((eq :tell (getf snare :phase))
           (let ((feet (feet player)))
             (if (and (on-floor-p player)
                      (< (sqrt (+ (expt (- (vx feet) (vx at)) 2) (expt (- (vz feet) (vz at)) 2))) *snare-reach*))
                 (progn
                   (setf (snare player) (list :root bloodroot :phase :held :left *snare-hold* :at at))
                   (kick-grit (vx at) (vy at) (vz at))
                   (play-sound :snare-grab))
                 ;; Jumped or stepped off in time.
                 (break-snare player NIL))))
          (T (break-snare player)))))

(define-shader-entity snare-sprite (upright-fx) ()
  (:documentation "Roots of a bloodroot's snare round the player's feet. A save leaves them out: the
snare's state (the player's SNARE) brings them back."))

(defun ensure-snare-sprites (bloodroot)
  "Show BLOODROOT's snare round the player's feet while it holds or closes on them."
  (let* ((player *player*)
         (snare (and player (snare player)))
         (mine (and snare (eq bloodroot (getf snare :root)) (container bloodroot))))
    (cond (mine
           (let* ((at (getf snare :at))
                  (animation (find-fx-animation 'snare-roots))
                  (fps (animation-fps animation))
                  (left (getf snare :left))
                  (frame (if (eq :tell (getf snare :phase))
                             (min 1 (floor (* 2 (- 1 (/ left *snare-tell*)))))
                             (let ((held (- *snare-hold* left)))
                               (cond ((< held 0.1) 2) ((< held 0.2) 3)
                                     (T (+ 4 (mod (floor held 0.15) 2))))))))
             (unless (snare-sprites bloodroot)
               (setf (snare-sprites bloodroot)
                     (loop for (dx dz) in '((1 0) (-1 0) (0 1) (0 -1))
                           collect (spawn-standing-fx 'snare-roots (+ (vx at) (* dx *snare-sprite-ring*)) (vy at)
                                                      (+ (vz at) (* dz *snare-sprite-ring*)) (container bloodroot)
                                                      :class 'snare-sprite))))
             (dolist (sprite (snare-sprites bloodroot))
               (setf (age sprite) (/ (+ frame 0.5) fps)))))
          ((snare-sprites bloodroot)
           (mapc #'despawn (snare-sprites bloodroot))
           (setf (snare-sprites bloodroot) ())))))

;;; Drinking: splats its live roots reach, on the floor or the walls they climb.

(defun splat-on-roots-p (bloodroot x y z face)
  "True if a splat at X Y Z on FACE (gore.lisp's) lies on BLOODROOT's live roots: on a rooted floor,
or on a wall beside one, below the roots' climb."
  (multiple-value-bind (dx dz)
      ;; Off a wall, into the room in front of it.
      (case face (0 (values 0.3 0.0)) (1 (values -0.3 0.0)) (4 (values 0.0 0.3)) (5 (values 0.0 -0.3))
            (T (values 0.0 0.0)))
    (unless (= face 3)
      (do-carpets (carpet bloodroot)
        (unless (carpet-wither carpet)
          (let ((w (carpet-cell-at carpet (+ x dx) y (+ z dz))))
            (when (and w (cell-live-p carpet w))
              (multiple-value-bind (a b k) (cell-coords carpet w)
                (when (or (= face 2)
                          (<= (- y (cell-floor carpet a b k))
                              (* *root-climb* (min 1.0 (/ (- *root-clock* (aref (carpet-born carpet) w))
                                                          *root-climb-time*)))))
                  (return-from splat-on-roots-p T))))))))))

(defun drink-splats (bloodroot dt)
  (let ((pool *blood-pool*)
        (drinking (drinking bloodroot)))
    (when pool
      (setf (drunk-left bloodroot) (max 0.0 (- (drunk-left bloodroot) dt)))
      (when (<= (drunk-left bloodroot) 0) (setf (drunk bloodroot) 0.0))
      (let ((scan (<= (decf (drink-timer bloodroot) dt) 0)))
        (when scan (setf (drink-timer bloodroot) *drink-scan*))
        (dotimes (i (min (length drinking) (pool-size pool)))
          (let ((time (aref drinking i)))
            (cond ((not (splat-lying-p pool i))
                   (setf (aref drinking i) -1f0))
                  ((<= 0 time)
                   (if (< (incf (aref drinking i) (float dt 0f0)) *drink-time*)
                       NIL
                       (multiple-value-bind (x y z face area) (splat-place pool i)
                         (declare (ignore face))
                         (setf (aref drinking i) -1f0)
                         (dissolve-splat pool i)
                         (let ((heal (min *drink-max* (* area *drink-per-area*))))
                           (incf (heal-carry bloodroot) heal)
                           (incf (drunk bloodroot) heal)
                           (setf (drunk-left bloodroot) 1.0)
                           (play-sound :root-drink (vec x y z))))))
                  (scan
                   (multiple-value-bind (x y z face) (splat-place pool i)
                     (when (splat-on-roots-p bloodroot x y z face)
                       (setf (aref drinking i) 0f0))))))))
      (let ((whole (floor (heal-carry bloodroot))))
        (when (< 0 whole)
          (decf (heal-carry bloodroot) whole)
          (heal-caster bloodroot whole)))
      (when (<= *glut-drink* (drunk bloodroot))
        (setf (drunk bloodroot) 0.0)
        (start-glut bloodroot)))))

(defun start-glut (bloodroot)
  (setf (glut bloodroot) (float *glut-time* 0f0)))

;;; Its hunt: bloom, or spit, never move.

(defun bloom-crowd (bloodroot)
  "How many bodies its Bloom would reach now."
  (length (burst-victims (bloom-origin bloodroot) *bloom-radius* bloodroot)))

(defun bloom-origin (bloodroot)
  (v+ (location bloodroot) (vec 0 (* 0.5 (sprite-height bloodroot)) 0)))

(defmethod hunt-from-range ((bloodroot bloodroot))
  (let* ((target (hunt-target bloodroot))
         (distance (target-distance bloodroot))
         (seen (clear-path-p (location bloodroot) (body-feet target) (cast-height bloodroot))))
    (cond ((and (ready-p bloodroot :bloom)
                (or (and seen (< distance *bloom-radius*))
                    (and (< *bloom-crowd-gap* (last-bloom bloodroot))
                         (<= *bloom-crowd* (bloom-crowd bloodroot)))))
           (setf (swelled bloodroot) NIL)
           (start-ability bloodroot :bloom))
          ((and (ready-p bloodroot :spit) seen (< distance *spit-range*)
                (not (target-swimming-p target)))
           (start-ability bloodroot :spit))
          (T (stop-walking bloodroot *chase-replan*)))))

(defun lob-velocity (from to apex gravity)
  "The velocity that throws a body from FROM to TO under GRAVITY, topping out APEX metres over the
higher of them."
  (let* ((top (+ (max (vy from) (vy to)) apex))
         (up (sqrt (* 2 gravity (- top (vy from)))))
         (time (+ (/ up gravity) (sqrt (/ (* 2 (- top (vy to))) gravity))))
         (dx (- (vx to) (vx from))) (dz (- (vz to) (vz from))))
    (vec (/ dx time) up (/ dz time))))

(define-shader-entity lobbed-projectile (spell-projectile)
  ((gravity :initarg :gravity :initform *seed-gravity* :accessor gravity))
  (:documentation "A projectile that arcs under its GRAVITY: a bloodroot's seed."))

(define-handler (lobbed-projectile tick :before) (dt)
  (unless (frozen-p)
    (decf (vy (projectile-velocity lobbed-projectile)) (* (gravity lobbed-projectile) (float dt 0f0)))))

(defun spit-aim (target)
  "Where a seed spat at TARGET lands: the floor under TARGET, ahead of its walk, off by a little."
  (let* ((feet (body-feet target))
         (v (if (typep target 'player) (velocity target) (vec 0 0 0)))
         (lead (min *seed-lead-max* (* *seed-lead* (sqrt (+ (expt (vx v) 2) (expt (vz v) 2))))))
         (speed (max 0.01 (sqrt (+ (expt (vx v) 2) (expt (vz v) 2)))))
         (angle (* 2 pi (random 1.0 *roll-random*)))
         (off (* *seed-scatter* (random 1.0 *roll-random*)))
         (point (vec (+ (vx feet) (* lead (/ (vx v) speed)) (* off (cos angle)))
                     (vy feet)
                     (+ (vz feet) (* lead (/ (vz v) speed)) (* off (sin angle))))))
    (or (floor-under point) feet)))

(defun spit-seed (bloodroot)
  (let* ((target (hunt-target bloodroot))
         (to (spit-aim target))
         (from (v+ (location bloodroot) (vec 0 (* 0.8 (sprite-height bloodroot)) 0)))
         (spell (find-spell 'blood-seed))
         (projectile (launch-projectile spell from (vec 0 1 0) (container bloodroot) bloodroot
                                        :class 'lobbed-projectile)))
    (v<- (projectile-velocity projectile) (lob-velocity from to *seed-apex* (gravity projectile)))
    (play-sound :bloodroot-spit from)))

(defmethod spell-impact ((name (eql 'blood-seed)) spell at caster container victim)
  (declare (ignore spell container victim))
  (when (and (typep caster 'bloodroot) (not (dead caster)))
    (plant-seed caster at)))

(defun plant-seed (bloodroot at)
  "Grow a seed's patch of roots for BLOODROOT on the floor under AT."
  (let ((floor (nav-floor-at (vx at) (+ (vy at) 0.3) (vz at))))
    (when (and floor (< (- (vy at) floor) *seed-floor-drop*)
               (not (liquid-at (vx at) (+ floor 0.05) (vz at))))
      (let ((patch (start-carpet bloodroot :seed (vec (vx at) floor (vz at)) *seed-patch-radius*
                                 :life *seed-patch-time* :ring-time *seed-ring-time*)))
        (when patch
          (play-sound :seed-impact at)
          (push patch (patches bloodroot))
          (when (< *max-seed-patches* (length (patches bloodroot)))
            (setf (patches bloodroot) (subseq (patches bloodroot) 0 *max-seed-patches*)
                  *roots-dirty* T)))))))

(defmethod release-attack ((bloodroot bloodroot))
  (let ((ability (current-ability bloodroot)))
    (ecase (ability-name ability)
      (:spit
       (spit-seed bloodroot)
       (setf (getf (cooldowns bloodroot) :spit)
             (* (if (< 0 (glut bloodroot)) *glut-spit-cooldown* (ability-cooldown ability)) (depth-scale :cooldown))))
      (:bloom
       (cast-spell (find-spell (bloom-spell bloodroot)) (bloom-origin bloodroot) (vec 0 0 -1) (container bloodroot)
                   :caster bloodroot)
       (setf (last-bloom bloodroot) 0.0
             (getf (cooldowns bloodroot) :bloom) (* (ability-cooldown ability) (depth-scale :cooldown)))
       (start-glut bloodroot)
       (let ((carpet (carpet bloodroot)))
         (when carpet
           (dotimes (i *bloom-surge*)
             (grow-ring carpet NIL T))))))))

(defgeneric bloom-spell (bloodroot)
  (:method ((bloodroot bloodroot)) 'bloom))

(defun update-bloodroot-light (bloodroot)
  (let ((lamp (bloodroot-lamp bloodroot)))
    (unless (and lamp (find lamp *lamps* :test #'eq))
      (setf lamp (attach-glow bloodroot *bloodroot-light* *bloodroot-light-radius*)
            (bloodroot-lamp bloodroot) lamp))
    (let* ((tell (and (eq (brain bloodroot) :attacking) (eq :bloom (ability-name (current-ability bloodroot)))
                      (winding-up-p bloodroot)
                      (min 1.0 (/ (attack-time bloodroot) (attack-hit-time bloodroot)))))
           (k (cond ((dead bloodroot) 0.0)
                    (tell (+ 0.2 (* 0.8 tell tell)))
                    ((< 0 (glut bloodroot)) (+ 0.15 (* 0.1 (sin (* 2 pi *glut-pulse* (glut bloodroot))))))
                    (T 0.0)))
           (color (color lamp)))
      (setf (vx color) (+ (* (- 1 k) (if (dead bloodroot) 0.0 (vx *bloodroot-light*))) (* k (vx *bloom-light*)))
            (vy color) (+ (* (- 1 k) (if (dead bloodroot) 0.0 (vy *bloodroot-light*))) (* k (vy *bloom-light*)))
            (vz color) (+ (* (- 1 k) (if (dead bloodroot) 0.0 (vz *bloodroot-light*))) (* k (vz *bloom-light*)))
            (radius lamp) (float (+ (* (- 1 k) *bloodroot-light-radius*) (* k *bloom-light-radius*)) 0f0))
      (when (and tell (< 0.3 tell) (not (swelled bloodroot)))
        (setf (swelled bloodroot) T)
        (play-sound :bloom-swell (location bloodroot)))
      ;; Blood motes drawn in to it through the tell.
      (when (and tell (< (random 1.0) 0.4))
        (let* ((a (random (* 2 pi))) (r (+ 2.0 (random 3.0)))
               (from (v+ (location bloodroot) (vec (* r (cos a)) (+ 0.2 (random 1.2)) (* r (sin a))))))
          (spray-sparks from (v- (bloom-origin bloodroot) from) 1 :kind :ember :ramp :drain :speed '(3.0 5.0)
                                                                 :spread 0.1))))))

(define-handler (bloodroot tick :after) (dt)
  (unless (frozen-p)
    (let ((dt (min (float dt 0f0) 0.05)))
      (run-cooldowns bloodroot dt)
      (incf (last-bloom bloodroot) dt)
      (setf (glut bloodroot) (max 0.0 (- (glut bloodroot) dt)))
      (when (and (null (carpet bloodroot)) *nav-grid* (not (dead bloodroot)))
        (let ((carpet (start-carpet bloodroot :main (location bloodroot) (root-reach bloodroot))))
          (when carpet
            (setf (carpet bloodroot) carpet)
            (dotimes (i *root-start-rings*) (grow-ring carpet NIL T)))))
      (cond ((dead bloodroot)
             (do-carpets (carpet bloodroot)
               (when (< (or (carpet-wither carpet) 0.0) 1.0)
                 (setf (carpet-wither carpet) (min 1.0 (+ (or (carpet-wither carpet) 0.0) (/ dt *root-wither-time*)))
                       *roots-dirty* T)))
             (when (and (carpet bloodroot) (<= 1.0 (carpet-wither (carpet bloodroot))))
               (setf (carpet bloodroot) NIL (patches bloodroot) () *roots-dirty* T)))
            ((not (dormant-p bloodroot))
             ;; One view: it notices all round, turned always to what it would hunt.
             (let ((target (hunt-target bloodroot)))
               (when (and target (target-live-p target))
                 (face-target bloodroot 0.0 target)))
             (grow-carpets bloodroot dt)
             (feed-on bloodroot dt)
             (drink-splats bloodroot dt)))))
  (ensure-snare-sprites bloodroot)
  (update-bloodroot-light bloodroot))

(defmethod creature-died :after ((bloodroot bloodroot) by)
  (declare (ignore by))
  (when (and *player* (eq bloodroot (getf (snare *player*) :root)))
    (break-snare *player*)))

(defmethod creature-revived ((bloodroot bloodroot))
  (setf *roots-dirty* T
        (carpet bloodroot) NIL (patches bloodroot) () (glut bloodroot) 0.0 (stand bloodroot) 0.0
        (drain-carry bloodroot) 0.0 (heal-carry bloodroot) 0.0 (last-bloom bloodroot) 100.0)
  (fill (drinking bloodroot) -1f0))

;;; Its looks: the idle pulse (quicker in Glut), and the red wash of Glut.

(defmethod show-own-pose ((bloodroot bloodroot) squash)
  (unless (dead bloodroot)
    (let* ((animation (find-fx-animation 'bloodroot-idle))
           (frames (getf (animation-atlas animation) :frames))
           (rate (* (animation-fps animation) (if (< 0 (glut bloodroot)) 2.0 1.0) 0.25)))
      (show-view-frame bloodroot 'bloodroot-idle (mod (floor (* (age-of bloodroot) rate frames)) frames) squash)
      T)))

(defun age-of (bloodroot)
  "A clock for its pulse: the light clock, which stops while the world is frozen."
  (declare (ignore bloodroot))
  *light-clock*)

(defmethod own-tint ((bloodroot bloodroot) tint)
  (when (< 0 (glut bloodroot))
    (destructuring-bind (low high) *glut-tint*
      (let ((k (+ low (* (- high low) (+ 0.5 (* 0.5 (sin (* 2 pi *glut-pulse* (glut bloodroot)))))))))
        (when (< (vw tint) k)
          (setf (vx tint) (vx *glut-color*) (vy tint) (vy *glut-color*) (vz tint) (vz *glut-color*)
                (vw tint) k))))))

;;; The root floor: every carpet's rooted cells, drawn in one call from a stream buffer as the
;;; blood pool is (gore.lisp): a quad on each cell's floor, and one up each wall beside it as high
;;; as the roots have climbed. Each corner carries how much of the four cells round it are rooted
;;; (COVER), so the edge is cut ragged in whole texels rather than along the cells; a frosted cell
;;; is drawn rimed, and a withering carpet's cover falls away.

(defparameter *max-root-quads* 6000 "Quads the root floor draws at most, every carpet together.")
(defparameter *root-floor-lift* 0.014 "Metres above its floor, or off its wall, roots are drawn.")
(defparameter *root-vertex-floats* 10
  "Per vertex: position, normal, cover, frost, height up a wall, and when its cell rooted.")

(defvar *root-floor* NIL "The root floor in the current scene.")

(define-shader-entity root-floor (lit-entity renderable listener)
  ((data :reader root-data)
   (vbo :reader root-vbo)
   (vao :reader root-vao)
   (count :initform 0 :accessor root-vertex-count :documentation "Vertices written when the carpets last changed.")))

(defmethod initialize-instance :after ((floor root-floor) &key)
  (let* ((data (make-array (* *max-root-quads* 6 *root-vertex-floats*) :element-type 'single-float
                                                                       :initial-element 0f0))
         (vbo (make-instance 'vertex-buffer :buffer-data data :data-usage :dynamic-draw))
         (stride (* 4 *root-vertex-floats*)))
    (setf (slot-value floor 'data) data
          (slot-value floor 'vbo) vbo
          (slot-value floor 'vao) (make-instance 'vertex-array
                                                 :vertex-form :triangles
                                                 :bindings `((,vbo :size 3 :offset 0 :stride ,stride :index 0)
                                                             (,vbo :size 3 :offset 12 :stride ,stride :index 1)
                                                             (,vbo :size 3 :offset 24 :stride ,stride :index 2)
                                                             (,vbo :size 1 :offset 36 :stride ,stride :index 3))))
    (setf *roots-dirty* T)))

(defmethod stage :after ((floor root-floor) (area staging-area))
  (stage (root-vao floor) area)
  (stage (// 'hexmaw 'bloodroot-roots) area))

(defmethod bind-textures :after ((floor root-floor))
  (bind (// 'hexmaw 'bloodroot-roots) :texture0))

(defun add-root-floor (scene)
  (setf *root-floor* (make-instance 'root-floor))
  (enter *root-floor* scene))

(define-handler (root-floor tick) (dt)
  (unless (frozen-p) (incf *root-clock* (float dt 0f0))))

(defun corner-cover (carpet a b k floor da db)
  "The share of the four cells round corner DA DB (each 0 or 1) of window cell A B K that are rooted
at about FLOOR."
  (let ((n (carpet-n carpet)) (state (carpet-state carpet)) (count 0))
    (loop for ca in (list (+ a da -1) (+ a da))
          do (loop for cb in (list (+ b db -1) (+ b db))
                   do (when (and (< -1 ca n) (< -1 cb n))
                        (if (and (= 1 (aref state (cell-index carpet ca cb k)))
                                 (let ((f (cell-floor carpet ca cb k))) (and f (< (abs (- f floor)) 0.3))))
                            (incf count)
                            (dotimes (ok (carpet-layers carpet))
                              (unless (= ok k)
                                (let ((f (cell-floor carpet ca cb ok)))
                                  (when (and f (< (abs (- f floor)) 0.3)
                                             (= 1 (aref state (cell-index carpet ca cb ok))))
                                    (incf count)
                                    (return)))))))))
    (/ count 4.0)))

(defun write-root-vertices (floor)
  "Write every carpet's cells into FLOOR's data; how many vertices. Only when a carpet changed: how a
cell spreads over its floor and climbs its wall runs in the shader, from when it rooted."
  (let ((data (root-data floor))
        (k 0)
        (most (* *max-root-quads* 6 *root-vertex-floats*))
        (stride *root-vertex-floats*)
        (c (nav-cell-size *nav-grid*)))
    (declare (type (simple-array single-float (*)) data) (type fixnum k most))
    (flet ((put (x y z nx ny nz cover frost up born)
             (setf (aref data k) (float x 0f0) (aref data (+ k 1)) (float y 0f0) (aref data (+ k 2)) (float z 0f0)
                   (aref data (+ k 3)) (float nx 0f0) (aref data (+ k 4)) (float ny 0f0) (aref data (+ k 5)) (float nz 0f0)
                   (aref data (+ k 6)) (float cover 0f0) (aref data (+ k 7)) (float frost 0f0)
                   (aref data (+ k 8)) (float up 0f0) (aref data (+ k 9)) (float born 0f0))
             (incf k stride)))
      (do-bloodroots (root)
        (do-carpets (carpet root)
          (let* ((state (carpet-state carpet))
                 (walls (carpet-walls carpet))
                 (keep (- 1.0 (or (carpet-wither carpet) 0.0))))
            (dotimes (w (length state))
              (when (and (= 1 (aref state w)) (<= (+ k (* 6 stride)) most))
                (multiple-value-bind (a b kk) (cell-coords carpet w)
                  (let* ((f (cell-floor carpet a b kk))
                         (born (aref (carpet-born carpet) w))
                         (frost (if (< 0 (aref (carpet-frost carpet) w)) 1.0 0.0))
                         (y (+ f *root-floor-lift*)))
                    (multiple-value-bind (cx cz) (cell-point carpet a b)
                      (let* ((x0 (- cx (* 0.5 c))) (x1 (+ cx (* 0.5 c)))
                             (z0 (- cz (* 0.5 c))) (z1 (+ cz (* 0.5 c)))
                             (c00 (* keep (corner-cover carpet a b kk f 0 0)))
                             (c10 (* keep (corner-cover carpet a b kk f 1 0)))
                             (c01 (* keep (corner-cover carpet a b kk f 0 1)))
                             (c11 (* keep (corner-cover carpet a b kk f 1 1))))
                        (put x0 y z0 0 1 0 c00 frost 0 born) (put x1 y z1 0 1 0 c11 frost 0 born)
                        (put x1 y z0 0 1 0 c10 frost 0 born)
                        (put x0 y z0 0 1 0 c00 frost 0 born) (put x0 y z1 0 1 0 c01 frost 0 born)
                        (put x1 y z1 0 1 0 c11 frost 0 born)
                        ;; Up the walls beside it, as high as they go; the shader shows the climb.
                        (loop for side from 0 below 4
                              for (dx dz) in '((1 0) (-1 0) (0 1) (0 -1))
                              do (let ((face (aref walls (+ (* 8 w) (* 2 side))))
                                       (top (aref walls (+ (* 8 w) (* 2 side) 1))))
                                   (when (and (<= 0 face) (<= (+ k (* 6 stride)) most))
                                     (let* ((h (min top *root-climb*))
                                            (off (- face *root-floor-lift*))
                                            (px (+ cx (* dx off))) (pz (+ cz (* dz off)))
                                            ;; Along the wall: across the cell.
                                            (ax (* 0.5 c (abs dz))) (az (* 0.5 c (abs dx)))
                                            (nx (- dx)) (nz (- dz)))
                                       (put (- px ax) f (- pz az) nx 0 nz keep frost 0 born)
                                       (put (+ px ax) (+ f h) (+ pz az) nx 0 nz keep frost h born)
                                       (put (+ px ax) f (+ pz az) nx 0 nz keep frost 0 born)
                                       (put (- px ax) f (- pz az) nx 0 nz keep frost 0 born)
                                       (put (- px ax) (+ f h) (- pz az) nx 0 nz keep frost h born)
                                       (put (+ px ax) (+ f h) (+ pz az) nx 0 nz keep frost h born))))))))))))))
    (floor k stride))))

(defun any-carpets-p ()
  (do-bloodroots (root)
    (when (or (carpet root) (patches root))
      (return-from any-carpets-p T))))

(defmethod render ((floor root-floor) (program shader-program))
  (when (and *nav-grid* (any-carpets-p))
    (when *roots-dirty*
      (setf *roots-dirty* NIL
            (root-vertex-count floor) (write-root-vertices floor))
      (when (< 0 (root-vertex-count floor))
        (update-buffer-data (root-vbo floor) (root-data floor)
                            :count (* (root-vertex-count floor) *root-vertex-floats* 4))))
    (let ((count (root-vertex-count floor)))
      (when (< 0 count)
        (setf (uniform program "view_matrix") (view-matrix))
        (setf (uniform program "projection_matrix") (projection-matrix))
        (set-fog-uniforms program)
        (setf (uniform program "texels_per_metre") *texels-per-metre*)
        (setf (uniform program "clock") *root-clock*)
        (setf (uniform program "grow_in") (float *root-grow-in* 0f0))
        (setf (uniform program "climb") (float *root-climb* 0f0))
        (setf (uniform program "climb_time") (float *root-climb-time* 0f0))
        (setf (uniform program "light_snap") 0.0)
        (setf (uniform program "light_bands") 0.0)
        (render-array (root-vao floor) :vertex-count count)))))

(define-class-shader (root-floor :vertex-shader)
  "layout (location = 0) in vec3 position;
layout (location = 1) in vec3 in_normal;
layout (location = 2) in vec3 in_cover;
layout (location = 3) in float in_born;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;
out vec3 v_world_position;
out vec3 v_view_position;
out vec3 v_normal;
out vec3 v_cover;
flat out float v_born;

void main(){
  vec4 view_position = view_matrix * vec4(position, 1.0);
  gl_Position = projection_matrix * view_position;
  v_world_position = position;
  v_view_position = view_position.xyz;
  v_normal = in_normal;
  v_cover = in_cover;
  v_born = in_born;
}")

(define-class-shader (root-floor :fragment-shader)
  "in vec3 v_world_position;
in vec3 v_view_position;
in vec3 v_normal;
in vec3 v_cover;
flat in float v_born;
uniform sampler2D texture_image;
uniform float texels_per_metre;
uniform float clock;
uniform float grow_in;
uniform float climb;
uniform float climb_time;
out vec4 color;

float hash2(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void main(){
  bool wall = abs(v_normal.y) < 0.5;
  // Whole texels of the world's grid, as the floors and walls are.
  vec2 uv = wall ? (abs(v_normal.x) > 0.5 ? vec2(v_world_position.z, -v_world_position.y)
                                         : vec2(v_world_position.x, -v_world_position.y))
                 : v_world_position.xz;
  vec2 texel = floor(uv * texels_per_metre) + 0.5;
  vec4 roots = texture(texture_image, texel / vec2(textureSize(texture_image, 0)));
  if(roots.a < 0.5) discard;
  float age = clock - v_born;
  // The edge: where the cover, spreading in as the cell roots, falls short of a ragged threshold,
  // in clumps of texels.
  float noise = hash2(floor(texel / 3.0)) * 0.35 + hash2(texel) * 0.15;
  if(v_cover.x * clamp(age / grow_in, 0.0, 1.0) < 0.3 + noise) discard;
  // Up a wall, V_COVER.Z is the height over the floor: the roots climb to CLIMB over CLIMB_TIME,
  // thinning out raggedly toward the top of the climb.
  if(wall && v_cover.z > climb * clamp(age / climb_time, 0.0, 1.0) * (1.0 - 1.2 * noise)) discard;
  vec3 surface = roots.rgb;
  // Frost holds them: rimed over.
  if(v_cover.y > 0.5) surface = mix(surface, vec3(0.74, 0.86, 0.95), 0.55 + 0.25 * hash2(texel + 7.0));
  vec3 normal = normalize(v_normal);
  vec3 light = band_light(light_at(snap_position(v_world_position), normal, 1.0, v_world_position + normal * 0.05));
  vec3 lamp = lamp_part(light);
  color = vec4(fog_lit(surface * (light - lamp), surface * lamp, length(v_view_position)), 1.0);
}")

;;; Elites and the Mother Root.

(define-shader-entity elite-bloodroot (elite bloodroot) ())

(defmethod root-speed ((elite elite-bloodroot))
  (* (call-next-method) (if (eq (elite-trait elite) :haste) *elite-haste* 1.0)))

(defparameter *mother-root-reach* 20.0 "Metres the Mother Root's roots reach: the whole arena.")

(define-shader-entity bloodroot-boss (boss bloodroot) ())

(defmethod root-reach ((boss bloodroot-boss)) *mother-root-reach*)
(defmethod power-animation ((boss bloodroot-boss)) 'bloodroot-spit)

;;; Preloading what appears mid-game.

(defun preload-bloodroot (scene)
  "Load what a bloodroot spawns mid-game: its seeds, their bursts and its snare, and the root floor."
  (preload (make-instance 'lobbed-projectile :spell (find-spell 'blood-seed) :animation (find-fx-animation 'seed-flight))
           scene)
  (preload (make-instance 'snare-sprite :animation (find-fx-animation 'snare-roots)) scene)
  (preload (make-instance 'fx-sprite :animation (find-fx-animation 'seed-burst)) scene))
