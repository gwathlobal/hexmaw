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
(defparameter *snare-sprite-ring* 1.1
  "Metres out from the snared feet its roots shoot up: far enough out that from the eye they reach the
lower third of the view looking straight ahead.")
(defparameter *snare-sprites* 6 "Roots in the ring round the feet, so one stands ahead whichever way the player looks.")
(defparameter *snare-rise* 0.15 "Seconds the tell's roots take to shoot up out of the floor.")
(defparameter *snare-lash-time* 0.1 "Seconds a frame of the tell's writhing lasts.")

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

(defparameter *drink-time* 1.0 "Seconds a splat takes to be drunk, before its light leaves for the bulb.")
(defparameter *drink-per-area* 0.03 "Health a splat's art pixel squared of blood gives.")
(defparameter *drink-max* 25 "Health one splat gives at most.")
(defparameter *drink-scan* 0.25 "Seconds between looks for splats to drink.")
(defparameter *drink-delay* 1.0
  "Seconds a splat glows on the roots, to be seen, before they drink it.")
(defparameter *drink-flow-speed* 4.0 "M/s a drink's light runs along the roots to the bulb.")
(defparameter *drink-flow-tail* 1.6 "Metres of roots behind its head a drink's light lights.")
(defparameter *drink-flow-width* 0.35 "Metres either side of its lane a drink's light reaches.")
(defparameter *drink-merge* 1.0 "Metres within which a splat's drink joins one not yet on its way.")
(defparameter *max-drinks* 8 "Drinks on their way to one bulb at most; more join the nearest.")
(defparameter *drink-motes* 8 "Blood motes a splat sends up as it is drunk.")
(defparameter *gulp-time* 0.35 "Seconds the bulb flushes red as a drink reaches it.")
(defparameter *gulp-tint* 0.55 "How red that flush washes it at its height.")

(defparameter *root-burn-hold* 5.0 "Seconds burnt or torn roots take to start growing back.")
(defparameter *root-frost-time* 6.0 "Seconds frost holds roots: no growth, no drain, no snare.")
(defparameter *root-wither-time* 1.5 "Seconds its roots take to wither when it dies.")
(defparameter *bolt-scorch-radius* 0.75 "Metres a single fire or frost hit with no area touches roots round it.")
(defparameter *root-touch-height* 1.5 "Metres above or below a hit roots it touches may lie.")

(defparameter *bloodroot-light* (vec 0.16 0.02 0.02) "Its veins' glow at rest: dim, since it stands in it.")
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
(define-fx-animation snare-roots "sprites/bloodroot/snare" :fps 10 :loop T :size (/ 89 64.0))
(define-fx-animation snare-grip "sprites/bloodroot/snare-grip" :fps 10 :loop T :size (/ 141 64.0))
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
   (drinks :initform () :accessor drinks
           :documentation "Blood on its way to it: per drink, a list of the splat's X Y Z, the metres
to the bulb, how far along the roots its light has run (negative while the splat is still being
drunk) and the health it brings.")
   (gulp :initform 0.0 :accessor gulp :documentation "Seconds left of its flush as a drink reaches it.")
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
   (floors :reader carpet-floors :documentation "Each rooted cell's floor height, for drawing.")
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
          (slot-value carpet 'floors) (make-array size :element-type 'single-float :initial-element 0f0)
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
    (setf (aref (carpet-floors carpet) w) (float floor 0f0))
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

;;; Saving: a carpet as plain data, its cells by window index with how long ago they rooted; a
;;; load lays them again on the same nav grid (the seed builds the same level) and finds their
;;; walls and frontier anew.

(defun carpet-record (carpet)
  (let ((cells ()))
    (dotimes (w (length (carpet-state carpet)))
      (let ((state (aref (carpet-state carpet) w)))
        (unless (= 0 state)
          (push (list w state (- *root-clock* (aref (carpet-born carpet) w))
                      (aref (carpet-hold carpet) w) (aref (carpet-frost carpet) w))
                cells))))
    (let ((at (carpet-centre carpet)))
      (list :kind (carpet-kind carpet) :centre (list (vx at) (vy at) (vz at)) :reach (carpet-reach carpet)
            :life (carpet-life carpet) :wither (carpet-wither carpet) :ring-time (ring-time carpet)
            :ring (carpet-ring carpet) :cells (nreverse cells)))))

(defun restore-carpet (owner record)
  (destructuring-bind (&key kind centre reach life wither ring-time ring cells) record
    (let ((carpet (make-instance 'root-carpet :owner owner :kind kind :centre (apply #'vec centre)
                                              :reach reach :life life :ring-time ring-time)))
      (setf (carpet-wither carpet) wither
            (carpet-ring carpet) ring)
      (loop for (w state age hold frost) in cells
            do (setf (aref (carpet-state carpet) w) state
                     (aref (carpet-born carpet) w) (float (- *root-clock* age) 0f0)
                     (aref (carpet-hold carpet) w) (float hold 0f0)
                     (aref (carpet-frost carpet) w) (float frost 0f0))
               (when (= state 1)
                 (incf (rooted-count carpet))
                 (multiple-value-bind (a b k) (cell-coords carpet w)
                   (find-walls carpet a b k))
                 (queue-cell carpet w)))
      (swap-frontier carpet)
      carpet)))

(defun root-state (bloodroot)
  (list :main (and (carpet bloodroot) (carpet-record (carpet bloodroot)))
        :patches (mapcar #'carpet-record (patches bloodroot))))

(defun (setf root-state) (state bloodroot)
  (setf (carpet bloodroot) (and (getf state :main) *nav-grid* (restore-carpet bloodroot (getf state :main)))
        (patches bloodroot) (and *nav-grid* (mapcar (lambda (r) (restore-carpet bloodroot r)) (getf state :patches)))
        *roots-dirty* T)
  state)

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
    ;; Off the floor at any moment of the tell, a jump, and the roots close on nothing.
    (when (and (eq :tell (getf snare :phase)) (not (on-floor-p player)))
      (setf (getf (snare player) :jumped) T))
    (cond ((not (snare-cell-live-p bloodroot at))
           ;; Burnt, frosted or torn up under the feet.
           (break-snare player))
          ((< 0 left))
          ((eq :tell (getf snare :phase))
           (let ((feet (feet player)))
             (if (and (on-floor-p player) (not (getf (snare player) :jumped))
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

(defun snare-sprite-spot (at angle radius)
  "Where a snare root stands RADIUS out from AT at ANGLE, pulled in to half that where a wall is."
  (flet ((spot (r) (values (float (+ (vx at) (* r (cos angle))) 0f0) (float (+ (vz at) (* r (sin angle))) 0f0))))
    (multiple-value-bind (x z) (spot radius)
      (if (solid-at x (+ (vy at) 0.7) z)
          (spot (* 0.5 radius))
          (values x z)))))

(defun ensure-snare-sprites (bloodroot)
  "Show BLOODROOT's snare round the player's feet while it holds or closes on them. In the tell its roots
shoot up out of the floor in a ring and writhe, tall enough to be seen looking straight ahead; once they
hold, taller ones surge up in their place, arch over the player and coil."
  (let* ((player *player*)
         (snare (and player (snare player)))
         (mine (and snare (eq bloodroot (getf snare :root)) (container bloodroot))))
    (cond (mine
           (let* ((at (getf snare :at))
                  (left (getf snare :left))
                  (tell (eq :tell (getf snare :phase)))
                  (animation (find-fx-animation (if tell 'snare-roots 'snare-grip)))
                  (fps (animation-fps animation))
                  (size (animation-size animation))
                  (since (if tell (- *snare-tell* left) (- *snare-hold* left)))
                  (rise (if tell (min 1.0 (/ since *snare-rise*)) 1.0))
                  (frame (if tell
                             (if (< rise 1.0) 2 (+ 2 (mod (floor (- since *snare-rise*) *snare-lash-time*) 2)))
                             (cond ((< since 0.1) 0) ((< since 0.2) 1) (T (+ 2 (mod (floor since 0.15) 2)))))))
             (unless (and (snare-sprites bloodroot)
                          (eq animation (sprite-animation (first (snare-sprites bloodroot)))))
               (mapc #'despawn (snare-sprites bloodroot))
               (setf (snare-sprites bloodroot)
                     (loop repeat *snare-sprites*
                           collect (spawn-standing-fx (if tell 'snare-roots 'snare-grip) (vx at) (vy at) (vz at)
                                                      (container bloodroot) :class 'snare-sprite))))
             (loop for sprite in (snare-sprites bloodroot)
                   for i from 0
                   for angle = (float (* i (/ (* 2 pi) *snare-sprites*)) 0f0)
                   do (multiple-value-bind (x z) (snare-sprite-spot at angle *snare-sprite-ring*)
                        (let ((location (location sprite)))
                          ;; Rising, the part still under the floor is hidden by it.
                          (setf (vx location) x
                                (vy location) (+ (vy at) (* size (- rise 0.5)))
                                (vz location) z)))
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

(defun start-drink (bloodroot x y z heal)
  "Start BLOODROOT drinking HEAL health of blood lying at X Y Z: one drink, or into one near it
whose blood is still being drunk, or, with too many under way, into the one nearest it."
  (let ((joined (loop for d in (drinks bloodroot)
                      when (and (< (fifth d) 0)
                                (< (+ (expt (- (first d) x) 2) (expt (- (third d) z) 2)) (expt *drink-merge* 2)))
                        return d)))
    (when (and (not joined) (<= *max-drinks* (length (drinks bloodroot))))
      (setf joined (loop with best and best-d = most-positive-single-float
                         for d in (drinks bloodroot)
                         for dd = (+ (expt (- (first d) x) 2) (expt (- (third d) z) 2))
                         when (< dd best-d) do (setf best d best-d dd)
                         finally (return best))))
    (if joined
        (incf (sixth joined) heal)
        (let* ((loc (location bloodroot))
               (len (max 0.0 (- (sqrt (+ (expt (- (vx loc) x) 2) (expt (- (vz loc) z) 2)))
                                (* 0.5 (body-radius bloodroot))))))
          ;; Its light waits under the splat, at -(*drink-time* x speed), until the blood is gone.
          (push (list (float x 0f0) (float y 0f0) (float z 0f0) (float len 0f0)
                      (float (- (* *drink-time* *drink-flow-speed*)) 0f0) (float heal 0f0))
                (drinks bloodroot))))))

(defun drink-arrives (bloodroot heal)
  "A drink of HEAL health reaches BLOODROOT: it flushes red and heals."
  (incf (heal-carry bloodroot) heal)
  (incf (drunk bloodroot) heal)
  (setf (drunk-left bloodroot) 1.0
        (gulp bloodroot) (float *gulp-time* 0f0)))

(defun flow-drinks (bloodroot dt)
  "Move BLOODROOT's drinks on: blood motes rise off a splat while it is drunk, then its light runs
along the roots, and it heals as each reaches it."
  (when (drinks bloodroot)
    (let ((step (* dt *drink-flow-speed*))
          (mote-chance (/ (* dt *drink-motes*) (max 0.1 *drink-time*))))
      (setf (drinks bloodroot)
            (delete-if (lambda (d)
                         (let ((run (fifth d)))
                           (when (and (< run 0) (< (random 1.0) mote-chance))
                             (spray-sparks (vec (+ (first d) (- (random 0.5) 0.25)) (+ (second d) 0.05)
                                                (+ (third d) (- (random 0.5) 0.25)))
                                           NIL 1 :kind :ember :ramp :drain :speed '(0.4 0.9)))
                           (setf (fifth d) (+ run step))
                           (when (<= (fourth d) (fifth d))
                             (drink-arrives bloodroot (sixth d))
                             T)))
                       (drinks bloodroot))))))

(defun drink-splats (bloodroot dt)
  "Every *DRINK-SCAN*, start drinking the splats that have lain *DRINK-DELAY* on BLOODROOT's live
roots: each dissolves
over *DRINK-TIME*, sending up blood motes, then its light runs along the roots to the bulb, which
heals as it arrives."
  (let ((pool *blood-pool*))
    (setf (drunk-left bloodroot) (max 0.0 (- (drunk-left bloodroot) dt))
          (gulp bloodroot) (max 0.0 (- (gulp bloodroot) dt)))
    (when (<= (drunk-left bloodroot) 0) (setf (drunk bloodroot) 0.0))
    (when (and pool (<= (decf (drink-timer bloodroot) dt) 0))
      (setf (drink-timer bloodroot) *drink-scan*)
      (dotimes (i (pool-size pool))
        ;; Once on the roots, it glows while they drink it; after *DRINK-DELAY* there it goes.
        (when (splat-lying-p pool i)
          (multiple-value-bind (x y z face area) (splat-place pool i)
            (when (or (splat-glows-p pool i) (splat-on-roots-p bloodroot x y z face))
              (cond ((not (splat-glows-p pool i))
                     (set-splat-glow pool i)
                     (setf (aref (pool-ages pool) i) 0f0))
                    ((<= *drink-delay* (aref (pool-ages pool) i))
                     (dissolve-splat pool i)
                     (start-drink bloodroot x y z (min *drink-max* (* area *drink-per-area*)))
                     (play-sound :root-drink (vec x y z)))))))))
    (flow-drinks bloodroot dt)
    (let ((whole (floor (heal-carry bloodroot))))
      (when (< 0 whole)
        (decf (heal-carry bloodroot) whole)
        (heal-caster bloodroot whole)))
    (when (<= *glut-drink* (drunk bloodroot))
      (setf (drunk bloodroot) 0.0)
      (start-glut bloodroot))))

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
    (play-sound (spell-sound spell :cast) from)))

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
                    ((< 0 (glut bloodroot)) (+ 0.06 (* 0.04 (sin (* 2 pi *glut-pulse* (glut bloodroot))))))
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
        (drain-carry bloodroot) 0.0 (heal-carry bloodroot) 0.0 (last-bloom bloodroot) 100.0
        (drinks bloodroot) () (gulp bloodroot) 0.0)
  ;; Fresh blood for it on the debug level, so each life shows it feeding.
  (when (eq *level* :test)
    (lay-debug-blood bloodroot)))

;;; Blood on the debug level: puddles round each bloodroot at several distances, which its roots
;;; reach and drink one after another as they spread.

(defparameter *debug-blood-spots* '((0.0 2.5) (3.5 -0.5) (2.0 -3.5) (-2.5 -4.5) (4.5 4.0) (-1.0 7.0))
  "Puddles laid round a bloodroot on the debug level: X and Z off it, in metres.")
(defparameter *debug-blood-drops* 40 "Drops in each of those puddles.")

(defun lay-debug-blood (&optional bloodroot)
  "Lay *DEBUG-BLOOD-SPOTS*' puddles round BLOODROOT, or round every bloodroot of the level."
  (if bloodroot
      (when *blood-pool*
        (let ((loc (location bloodroot)))
          (loop for (dx dz) in *debug-blood-spots*
                do (spray-blood (vec (+ (vx loc) dx) (+ (vy loc) 0.3) (+ (vz loc) dz)) 0 0 *debug-blood-drops*
                                :speed '(0.4 1.4)))))
      (do-bloodroots (root)
        (unless (dead root) (lay-debug-blood root)))))

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
  ;; A drink reaching it: a red flush, gone in a moment.
  (when (< 0 (gulp bloodroot))
    (let ((k (* *gulp-tint* (/ (gulp bloodroot) *gulp-time*))))
      (when (< (vw tint) k)
        (setf (vx tint) (vx *glut-color*) (vy tint) (vy *glut-color*) (vz tint) (vz *glut-color*)
              (vw tint) k))))
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
(defparameter *root-floor-lift* 0.0025
  "Metres above its floor, or off its wall, roots are drawn: under the blood splats (gore.lisp's
*SPLAT-LIFT*), so the blood they drink shows on them.")
(defparameter *root-vertex-floats* 11
  "Per vertex: position, normal, cover, frost, height up a wall, when its cell rooted, and how far it
is from its bulb, for the heartbeat running out along the veins.")
(defparameter *root-beat-period* 1.3 "Seconds between the bulb's heartbeats.")
(defparameter *root-beat-speed* 6.0 "Metres a second a heartbeat runs out along the roots.")
(defparameter *root-vein-glow* 0.45 "How brightly the roots' veins glow between heartbeats, unlit.")
(defparameter *root-beat-glow* 1.6 "How much more brightly they glow as a heartbeat passes.")

(defvar *root-floor* NIL "The root floor in the current scene.")
(defvar *root-tufts* NIL "The root tufts in the current scene.")

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
                                                             (,vbo :size 2 :offset 36 :stride ,stride :index 3))))
    (setf *roots-dirty* T)))

(defmethod stage :after ((floor root-floor) (area staging-area))
  (stage (root-vao floor) area)
  (stage (// 'hexmaw 'bloodroot-roots) area))

(defmethod bind-textures :after ((floor root-floor))
  (bind (// 'hexmaw 'bloodroot-roots) :texture0))

(defun add-root-floor (scene)
  "Enter the root floor and the tufts standing on it."
  (setf *root-floor* (make-instance 'root-floor)
        *root-tufts* (make-instance 'root-tufts))
  (enter *root-floor* scene)
  (enter *root-tufts* scene))

(define-handler (root-floor tick) (dt)
  (unless (frozen-p) (incf *root-clock* (float dt 0f0))))

(declaim (inline corner-cover))
(defun corner-cover (state floors n layers a b k floor da db)
  "The share of the four cells round corner DA DB (each 0 or 1) of window cell A B K that are rooted
at about FLOOR: the same layer's, or another's within 0.3 m of it."
  (declare (type (simple-array (unsigned-byte 8) (*)) state) (type (simple-array single-float (*)) floors)
           (type fixnum n layers a b k da db) (type single-float floor) (optimize speed (safety 0) (debug 0)))
  (let ((count 0))
    (declare (type fixnum count))
    (dotimes (ia 2)
      (dotimes (ib 2)
        (let ((ca (+ a da -1 ia)) (cb (+ b db -1 ib)))
          (declare (type fixnum ca cb))
          (when (and (< -1 ca n) (< -1 cb n))
            (let ((w (+ ca (* n (+ cb (* n k))))))
              (if (and (= 1 (aref state w)) (< (abs (- (aref floors w) floor)) 0.3))
                  (incf count)
                  (dotimes (ok layers)
                    (let ((ow (+ ca (* n (+ cb (* n ok))))))
                      (when (and (/= ok k) (= 1 (aref state ow)) (< (abs (- (aref floors ow) floor)) 0.3))
                        (incf count)
                        (return))))))))))
    (* 0.25 count)))

(defun write-root-vertices (floor)
  "Write every carpet's cells into FLOOR's data; how many vertices. Only when a carpet changed: how a
cell spreads over its floor and climbs its wall runs in the shader, from when it rooted."
  (let ((data (root-data floor))
        (k 0)
        (most (* *max-root-quads* 6 *root-vertex-floats*))
        (c (float (nav-cell-size *nav-grid*) 0f0))
        (x0 (float (nav-x0 *nav-grid*) 0f0))
        (z0 (float (nav-z0 *nav-grid*) 0f0))
        (lift (float *root-floor-lift* 0f0))
        (climb (float *root-climb* 0f0)))
    (declare (type (simple-array single-float (*)) data) (type fixnum k most)
             (type single-float c x0 z0 lift climb) (optimize speed (safety 0) (debug 0)))
    (let ((dist 0f0))
     (declare (type single-float dist))
     (flet ((put (x y z nx nz ny cover frost up born)
             (declare (type single-float x y z nx ny nz cover frost up born))
             (setf (aref data k) x (aref data (+ k 1)) y (aref data (+ k 2)) z
                   (aref data (+ k 3)) nx (aref data (+ k 4)) ny (aref data (+ k 5)) nz
                   (aref data (+ k 6)) cover (aref data (+ k 7)) frost
                   (aref data (+ k 8)) up (aref data (+ k 9)) born (aref data (+ k 10)) dist)
             (incf k 11)))
      (declare (inline put))
      (do-bloodroots (root)
       (let ((bx (float (vx (location root)) 0f0)) (bz (float (vz (location root)) 0f0)))
        (declare (type single-float bx bz))
        (do-carpets (carpet root)
          (let* ((state (carpet-state carpet))
                 (floors (carpet-floors carpet))
                 (borns (carpet-born carpet))
                 (frosts (carpet-frost carpet))
                 (walls (carpet-walls carpet))
                 (n (carpet-n carpet))
                 (layers (carpet-layers carpet))
                 (i0 (carpet-i0 carpet)) (j0 (carpet-j0 carpet))
                 (keep (float (- 1.0 (or (carpet-wither carpet) 0.0)) 0f0)))
            (declare (type (simple-array (unsigned-byte 8) (*)) state)
                     (type (simple-array single-float (*)) floors borns frosts walls)
                     (type fixnum n layers i0 j0) (type single-float keep))
            (dotimes (w (length state))
              (when (and (= 1 (aref state w)) (<= (+ k 66) most))
                (multiple-value-bind (rest a) (floor w n)
                  (multiple-value-bind (kk b) (floor rest n)
                    (let* ((f (aref floors w))
                           (born (aref borns w))
                           (frost (if (< 0 (aref frosts w)) 1f0 0f0))
                           (y (+ f lift))
                           (cx (+ x0 (* (+ i0 a 0.5f0) c)))
                           (cz (+ z0 (* (+ j0 b 0.5f0) c)))
                           (h (* 0.5f0 c))
                           (xa (- cx h)) (xb (+ cx h)) (za (- cz h)) (zb (+ cz h))
                           (c00 (* keep (corner-cover state floors n layers a b kk f 0 0)))
                           (c10 (* keep (corner-cover state floors n layers a b kk f 1 0)))
                           (c01 (* keep (corner-cover state floors n layers a b kk f 0 1)))
                           (c11 (* keep (corner-cover state floors n layers a b kk f 1 1))))
                      (declare (type single-float f born frost y cx cz h xa xb za zb c00 c10 c01 c11))
                      (setf dist (sqrt (+ (expt (- cx bx) 2) (expt (- cz bz) 2))))
                      (put xa y za 0f0 0f0 1f0 c00 frost 0f0 born) (put xb y zb 0f0 0f0 1f0 c11 frost 0f0 born)
                      (put xb y za 0f0 0f0 1f0 c10 frost 0f0 born)
                      (put xa y za 0f0 0f0 1f0 c00 frost 0f0 born) (put xa y zb 0f0 0f0 1f0 c01 frost 0f0 born)
                      (put xb y zb 0f0 0f0 1f0 c11 frost 0f0 born)
                      ;; Up the walls beside it, as high as they go; the shader shows the climb.
                      (dotimes (side 4)
                        (let ((face (aref walls (+ (* 8 w) (* 2 side))))
                              (top (aref walls (+ (* 8 w) (* 2 side) 1))))
                          (when (and (<= 0 face) (<= (+ k 66) most))
                            (let* ((dx (case side (0 1f0) (1 -1f0) (T 0f0)))
                                   (dz (case side (2 1f0) (3 -1f0) (T 0f0)))
                                   (wh (min top climb))
                                   (off (- face lift))
                                   (px (+ cx (* dx off))) (pz (+ cz (* dz off)))
                                   ;; Along the wall: across the cell.
                                   (ax (* h (abs dz))) (az (* h (abs dx)))
                                   (nx (- dx)) (nz (- dz))
                                   (top-y (+ f wh)))
                              (declare (type single-float dx dz wh off px pz ax az nx nz top-y))
                              (put (- px ax) f (- pz az) nx nz 0f0 keep frost 0f0 born)
                              (put (+ px ax) top-y (+ pz az) nx nz 0f0 keep frost wh born)
                              (put (+ px ax) f (+ pz az) nx nz 0f0 keep frost 0f0 born)
                              (put (- px ax) f (- pz az) nx nz 0f0 keep frost 0f0 born)
                              (put (- px ax) top-y (- pz az) nx nz 0f0 keep frost wh born)
                              (put (+ px ax) top-y (+ pz az) nx nz 0f0 keep frost wh born))))))))))))))))
    (floor k 11)))

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
                            :count (* (root-vertex-count floor) *root-vertex-floats* 4)))
      (when *root-tufts* (write-tufts *root-tufts*)))
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
        (set-beat-uniforms program)
        (render-array (root-vao floor) :vertex-count count)))))

(defun set-beat-uniforms (program)
  "The heartbeat's uniforms, which the root floor and its tufts share (ROOT_BEAT in their shaders)."
  (setf (uniform program "beat_period") (float *root-beat-period* 0f0))
  (setf (uniform program "beat_speed") (float *root-beat-speed* 0f0))
  (setf (uniform program "vein_glow") (float *root-vein-glow* 0f0))
  (setf (uniform program "beat_glow") (float *root-beat-glow* 0f0))
  (set-drink-uniforms program))

;;; A drink's light: once a splat's blood is gone, a short streak of light runs along the roots,
;;; straight from where it lay to the bulb, so the player sees what its roots drank. Up to
;;; *MAX-DRINK-LANES* at once, the ones on their way, in uniform arrays (DRINK_GLOW in the shaders).

(defparameter *max-drink-lanes* 8 "Drinks whose light the shaders draw at once; the size of their arrays.")
(defvar *drink-lanes* (coerce (loop repeat 8 collect (vec4)) 'simple-vector))
(defvar *drink-runs* (coerce (loop repeat 8 collect (vec2)) 'simple-vector))
(defvar *drink-lane-names* (coerce (loop for i below 8 collect (format NIL "drink_lanes[~d]" i)) 'simple-vector))
(defvar *drink-run-names* (coerce (loop for i below 8 collect (format NIL "drink_runs[~d]" i)) 'simple-vector))

(defun set-drink-uniforms (program)
  (let ((n 0))
    (block gather
      (do-bloodroots (root)
        (let ((loc (location root)))
          (dolist (d (drinks root))
            (when (<= 0 (fifth d))
              (when (<= *max-drink-lanes* n) (return-from gather))
              (let ((lane (svref *drink-lanes* n)) (run (svref *drink-runs* n)))
                (setf (vx lane) (first d) (vy lane) (third d) (vz lane) (vx loc) (vw lane) (vz loc)
                      (vx run) (fifth d) (vy run) (fourth d))
                (setf (uniform program (svref *drink-lane-names* n)) lane)
                (setf (uniform program (svref *drink-run-names* n)) run)
                (incf n)))))))
    (setf (uniform program "drink_count") n)
    (setf (uniform program "drink_tail") (float *drink-flow-tail* 0f0))
    (setf (uniform program "drink_width") (float *drink-flow-width* 0f0))))


(define-class-shader (root-floor :vertex-shader)
  "layout (location = 0) in vec3 position;
layout (location = 1) in vec3 in_normal;
layout (location = 2) in vec3 in_cover;
layout (location = 3) in vec2 in_born;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;
out vec3 v_world_position;
out vec3 v_view_position;
out vec3 v_normal;
out vec3 v_cover;
flat out float v_born;
out float v_dist;

void main(){
  vec4 view_position = view_matrix * vec4(position, 1.0);
  gl_Position = projection_matrix * view_position;
  v_world_position = position;
  v_view_position = view_position.xyz;
  v_normal = in_normal;
  v_cover = in_cover;
  v_born = in_born.x;
  v_dist = in_born.y;
}")

(define-class-shader (root-floor :fragment-shader)
  "in vec3 v_world_position;
in vec3 v_view_position;
in vec3 v_normal;
in vec3 v_cover;
flat in float v_born;
in float v_dist;
uniform sampler2D texture_image;
uniform float texels_per_metre;
uniform float clock;
uniform float grow_in;
uniform float climb;
uniform float climb_time;
out vec4 color;

float hash2(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
uniform float beat_period;
uniform float beat_speed;
uniform float vein_glow;
uniform float beat_glow;
uniform int drink_count;
uniform vec4 drink_lanes[8];
uniform vec2 drink_runs[8];
uniform float drink_tail;
uniform float drink_width;

// How much a drink's light lights a root at P: a streak DRINK_TAIL long running from the splat
// (a lane's XY) to the bulb (its ZW), its head DRINK_RUNS.x along, brightest at the head.
float drink_glow(vec3 p){
  float g = 0.0;
  for(int i = 0; i < drink_count; i++){
    vec2 a = drink_lanes[i].xy;
    vec2 d = drink_lanes[i].zw - a;
    float len = length(d);
    if(len < 0.01) continue;
    vec2 dir = d / len;
    vec2 r = p.xz - a;
    float along = dot(r, dir);
    float across = abs(r.x * dir.y - r.y * dir.x);
    float behind = drink_runs[i].x - along;
    if(across < drink_width && along > -0.2 && behind > -0.1 && behind < drink_tail)
      g = max(g, 1.0 - max(behind, 0.0) / drink_tail);
  }
  return floor(g * 4.0 + 0.5) / 4.0;
}

// Its colour: blood red down the tail, a pale hot pink at the head, so it stands out on the
// carpet's own reds.
vec3 drink_color(float g){
  return g > 0.7 ? vec3(2.2, 0.55, 0.42) * g : vec3(1.8, 0.16, 0.1) * g;
}

float vein_of(vec3 c){ return (c.r > 0.4 && c.g + c.b < 0.45 * c.r) ? 1.0 : 0.0; }

// How much a root texel at DIST metres from its bulb glows now: its veins (saturated reds) only,
// faintly at rest and flaring as each heartbeat, a lub and a dub, runs out from the bulb. Stepped,
// as the aurora's light is, so it stays on the art's few tones.
float root_beat(vec3 surface, float dist, float clock){
  float vein = (surface.r > 0.4 && surface.g + surface.b < 0.45 * surface.r) ? 1.0 : 0.0;
  float p = fract((clock - dist / beat_speed) / beat_period);
  float beat = exp(-p * p / 0.002) + exp(-(1.0 - p) * (1.0 - p) / 0.002)
             + 0.6 * exp(-(p - 0.16) * (p - 0.16) / 0.002);
  return vein * floor((vein_glow + beat_glow * beat) * 4.0) / 4.0;
}

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
  // The veins glow on their own, fogged as lamp light is, so the carpet shows across a dark room.
  vec3 glow = surface * lamp + roots.rgb * root_beat(roots.rgb, v_dist, clock) * (1.0 - v_cover.y);
  float drink = drink_glow(v_world_position) * mix(0.35, 1.0, vein_of(roots.rgb));
  if(drink > 0.0){ surface *= 1.0 - drink; glow += drink_color(drink); }
  color = vec4(fog_lit(surface * (light - lamp), glow, length(v_view_position)), 1.0);
}")

;;; Tufts: the roots standing up out of the carpet, so it has height and shows from across a room
;;; (a carpet lying flat, dark red-brown on a brown floor, was easy to miss). One of the strip's
;;; tufts stands on most rooted floor cells, chosen, placed and sized by a hash of the cell, turned
;;; about +Y to face the camera plane as a billboard is, all drawn in one call from the buffer the
;;; root floor's cells are written with. A cell's tuft rises out of its floor as the cell roots and
;;; sinks back as its carpet withers; the floor hides what is under it.

(define-fx-animation root-tendrils "sprites/bloodroot/tendrils" :size (/ 34 64.0))

(defparameter *root-tuft-share* 0.55 "Share of rooted floor cells a tuft stands on.")
(defparameter *root-tuft-jitter* 0.16 "Metres a tuft stands off its cell's middle, at most, each way.")
(defparameter *root-tuft-scale* '(0.8 1.1) "Smallest and largest a tuft is drawn, of its art's size.")
(defparameter *root-tuft-grow* 0.6 "Seconds a tuft takes to rise out of the floor.")
(defparameter *root-tuft-stagger* 0.5 "Seconds, at most, a tuft rises after its cell roots.")
(defparameter *root-tuft-sink* 0.03 "Metres a tuft's foot stands under its floor.")
(defparameter *root-tuft-sway* 1.5 "Art pixels a tuft's tip sways each way.")
(defparameter *max-root-tufts* 4000 "Tufts drawn at most, every carpet together.")
(defparameter *root-tuft-floats* 12
  "Per vertex: the foot, the corner (across, up), the size, the frame, when it rose, frost, how
much of its carpet is left, and its distance from its bulb.")

(define-shader-entity root-tufts (lit-entity renderable listener)
  ((data :reader tuft-data)
   (vbo :reader tuft-vbo)
   (vao :reader tuft-vao)
   (count :initform 0 :accessor tuft-vertex-count)))

(defmethod initialize-instance :after ((tufts root-tufts) &key)
  (let* ((data (make-array (* *max-root-tufts* 6 *root-tuft-floats*) :element-type 'single-float
                                                                       :initial-element 0f0))
         (vbo (make-instance 'vertex-buffer :buffer-data data :data-usage :dynamic-draw))
         (stride (* 4 *root-tuft-floats*)))
    (setf (slot-value tufts 'data) data
          (slot-value tufts 'vbo) vbo
          (slot-value tufts 'vao) (make-instance 'vertex-array
                                                 :vertex-form :triangles
                                                 :bindings `((,vbo :size 3 :offset 0 :stride ,stride :index 0)
                                                             (,vbo :size 4 :offset 12 :stride ,stride :index 1)
                                                             (,vbo :size 4 :offset 28 :stride ,stride :index 2)
                                                             (,vbo :size 1 :offset 44 :stride ,stride :index 3))))))

(defmethod stage :after ((tufts root-tufts) (area staging-area))
  (stage (tuft-vao tufts) area)
  (stage (// 'hexmaw 'root-tendrils) area))

(defmethod bind-textures :after ((tufts root-tufts))
  (bind (// 'hexmaw 'root-tendrils) :texture0))

(declaim (inline tuft-hash))
(defun tuft-hash (i j k salt)
  "A number from 0 below 1 for world nav cell I J K and SALT, the same every time it is asked."
  (declare (type fixnum i j k salt) (optimize speed (safety 0)))
  (let ((h (logand #xfffffff (+ (* i 73856093) (* j 19349663) (* k 83492791) (* salt 50331653)))))
    (declare (type (unsigned-byte 28) h))
    (setf h (logand #xfffffff (* (logxor h (ash h -13)) 73856093)))
    (setf h (logand #xfffffff (* (logxor h (ash h -11)) 19349663)))
    (/ (float (logxor h (ash h -15)) 0f0) 268435456f0)))

(defun write-tufts (tufts)
  "Write a tuft for every rooted floor cell that has one into TUFTS' data, when a carpet changed."
  (let* ((data (tuft-data tufts))
         (k 0)
         (most (* *max-root-tufts* 6 *root-tuft-floats*))
         (atlas (animation-atlas (find-fx-animation 'root-tendrils)))
         (frames (getf atlas :frames))
         (art-w (/ (float (getf atlas :cell-width) 0f0) (float *texels-per-metre* 0f0)))
         (art-h (/ (float (getf atlas :cell-height) 0f0) (float *texels-per-metre* 0f0)))
         (c (float (nav-cell-size *nav-grid*) 0f0))
         (x0 (float (nav-x0 *nav-grid*) 0f0))
         (z0 (float (nav-z0 *nav-grid*) 0f0))
         (share (float *root-tuft-share* 0f0))
         (jitter (float *root-tuft-jitter* 0f0))
         (small (float (first *root-tuft-scale*) 0f0))
         (big (float (second *root-tuft-scale*) 0f0))
         (stagger (float *root-tuft-stagger* 0f0))
         (sink (float *root-tuft-sink* 0f0))
         (dist 0f0))
    (declare (type (simple-array single-float (*)) data) (type fixnum k most frames)
             (type single-float art-w art-h c x0 z0 share jitter small big stagger sink dist))
    (flet ((put (x y z u v w h frame born frost keep)
             (declare (type single-float x y z u v w h frame born frost keep))
             (setf (aref data k) x (aref data (+ k 1)) y (aref data (+ k 2)) z
                   (aref data (+ k 3)) u (aref data (+ k 4)) v (aref data (+ k 5)) w (aref data (+ k 6)) h
                   (aref data (+ k 7)) frame (aref data (+ k 8)) born (aref data (+ k 9)) frost
                   (aref data (+ k 10)) keep (aref data (+ k 11)) dist)
             (incf k 12)))
      (declare (inline put))
      (do-bloodroots (root)
        (let ((bx (float (vx (location root)) 0f0)) (bz (float (vz (location root)) 0f0)))
          (declare (type single-float bx bz))
          (do-carpets (carpet root)
            (let ((state (carpet-state carpet))
                  (floors (carpet-floors carpet))
                  (borns (carpet-born carpet))
                  (frosts (carpet-frost carpet))
                  (n (carpet-n carpet))
                  (i0 (carpet-i0 carpet)) (j0 (carpet-j0 carpet))
                  (keep (float (- 1.0 (or (carpet-wither carpet) 0.0)) 0f0)))
              (declare (type (simple-array (unsigned-byte 8) (*)) state)
                       (type (simple-array single-float (*)) floors borns frosts)
                       (type fixnum n i0 j0) (type single-float keep))
              (dotimes (w (length state))
                (when (and (= 1 (aref state w)) (<= (+ k 72) most))
                  (multiple-value-bind (rest a) (floor w n)
                    (multiple-value-bind (kk b) (floor rest n)
                      (let ((i (+ i0 a)) (j (+ j0 b)))
                        (when (< (tuft-hash i j kk 0) share)
                          (let* ((cx (+ x0 (* (+ i 0.5f0) c) (* jitter (- (* 2 (tuft-hash i j kk 1)) 1))))
                                 (cz (+ z0 (* (+ j 0.5f0) c) (* jitter (- (* 2 (tuft-hash i j kk 2)) 1))))
                                 (y (- (aref floors w) sink))
                                 (scale (+ small (* (- big small) (tuft-hash i j kk 3))))
                                 (tw (* art-w scale)) (th (* art-h scale))
                                 (frame (float (min (1- frames) (floor (* frames (tuft-hash i j kk 4)))) 0f0))
                                 (born (+ (aref borns w) (* stagger (tuft-hash i j kk 5))))
                                 (frost (if (< 0 (aref frosts w)) 1f0 0f0)))
                            (declare (type single-float cx cz y scale tw th frame born frost))
                            (setf dist (sqrt (+ (expt (- cx bx) 2) (expt (- cz bz) 2))))
                            (put cx y cz -0.5f0 0f0 tw th frame born frost keep)
                            (put cx y cz 0.5f0 0f0 tw th frame born frost keep)
                            (put cx y cz 0.5f0 1f0 tw th frame born frost keep)
                            (put cx y cz -0.5f0 0f0 tw th frame born frost keep)
                            (put cx y cz 0.5f0 1f0 tw th frame born frost keep)
                            (put cx y cz -0.5f0 1f0 tw th frame born frost keep)))))))))))))
    (setf (tuft-vertex-count tufts) (floor k 12))
    (when (< 0 k)
      (update-buffer-data (tuft-vbo tufts) data :count (* k 4)))))

(defmethod render ((tufts root-tufts) (program shader-program))
  (let ((count (tuft-vertex-count tufts)))
    (when (and *nav-grid* (< 0 count) (any-carpets-p))
      (let ((atlas (animation-atlas (find-fx-animation 'root-tendrils))))
        (setf (uniform program "view_matrix") (view-matrix))
        (setf (uniform program "projection_matrix") (projection-matrix))
        (set-fog-uniforms program)
        (setf (uniform program "clock") *root-clock*)
        (setf (uniform program "grow") (float *root-tuft-grow* 0f0))
        (setf (uniform program "sway") (/ (float *root-tuft-sway* 0f0) (float *texels-per-metre* 0f0)))
        (setf (uniform program "cell_width") (float (getf atlas :cell-width) 0f0))
        (setf (uniform program "cell_height") (float (getf atlas :cell-height) 0f0))
        (setf (uniform program "cell_gap") (float (getf atlas :gap) 0f0))
        (setf (uniform program "light_snap") 0.0)
        (setf (uniform program "light_bands") 0.0)
        (set-beat-uniforms program)
        (render-array (tuft-vao tufts) :vertex-count count)))))

(define-class-shader (root-tufts :vertex-shader)
  "layout (location = 0) in vec3 foot;
layout (location = 1) in vec4 quad;
layout (location = 2) in vec4 info;
layout (location = 3) in float in_dist;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;
uniform float clock;
uniform float grow;
uniform float sway;
out vec3 v_world_position;
out vec3 v_view_position;
out vec2 v_uv;
flat out float v_frame;
flat out float v_frost;
flat out vec3 v_probe;
out float v_dist;

void main(){
  // Turned about +Y to face the camera plane, as a billboard is.
  vec3 right = vec3(view_matrix[0][0], 0.0, view_matrix[2][0]);
  right = length(right) > 0.001 ? normalize(right) : vec3(1.0, 0.0, 0.0);
  float rise = clamp((clock - info.y) / grow, 0.0, 1.0) * info.w;
  // Rising out of the floor and sinking back into it: the floor hides the rest.
  float up = quad.y * quad.w - (1.0 - rise) * quad.w;
  // The tip sways, in whole art pixels.
  float lean = floor(sin(clock * 1.7 + foot.x * 3.1 + foot.z * 2.3) * 1.5 + 0.5) * sway * quad.y;
  vec3 position = foot + right * (quad.x * quad.z + lean) + vec3(0.0, up, 0.0);
  vec4 view_position = view_matrix * vec4(position, 1.0);
  gl_Position = projection_matrix * view_position;
  v_world_position = position;
  v_view_position = view_position.xyz;
  v_uv = vec2(quad.x + 0.5, quad.y);
  v_frame = info.x;
  v_frost = info.z;
  v_probe = foot + vec3(0.0, 0.3, 0.0);
  v_dist = in_dist;
}")

(define-class-shader (root-tufts :fragment-shader)
  "in vec3 v_world_position;
in vec3 v_view_position;
in vec2 v_uv;
flat in float v_frame;
flat in float v_frost;
flat in vec3 v_probe;
in float v_dist;
uniform sampler2D texture_image;
uniform float clock;
uniform float cell_width;
uniform float cell_height;
uniform float cell_gap;
out vec4 color;
uniform float beat_period;
uniform float beat_speed;
uniform float vein_glow;
uniform float beat_glow;
uniform int drink_count;
uniform vec4 drink_lanes[8];
uniform vec2 drink_runs[8];
uniform float drink_tail;
uniform float drink_width;

// How much a drink's light lights a root at P: a streak DRINK_TAIL long running from the splat
// (a lane's XY) to the bulb (its ZW), its head DRINK_RUNS.x along, brightest at the head.
float drink_glow(vec3 p){
  float g = 0.0;
  for(int i = 0; i < drink_count; i++){
    vec2 a = drink_lanes[i].xy;
    vec2 d = drink_lanes[i].zw - a;
    float len = length(d);
    if(len < 0.01) continue;
    vec2 dir = d / len;
    vec2 r = p.xz - a;
    float along = dot(r, dir);
    float across = abs(r.x * dir.y - r.y * dir.x);
    float behind = drink_runs[i].x - along;
    if(across < drink_width && along > -0.2 && behind > -0.1 && behind < drink_tail)
      g = max(g, 1.0 - max(behind, 0.0) / drink_tail);
  }
  return floor(g * 4.0 + 0.5) / 4.0;
}

// Its colour: blood red down the tail, a pale hot pink at the head, so it stands out on the
// carpet's own reds.
vec3 drink_color(float g){
  return g > 0.7 ? vec3(2.2, 0.55, 0.42) * g : vec3(1.8, 0.16, 0.1) * g;
}

float vein_of(vec3 c){ return (c.r > 0.4 && c.g + c.b < 0.45 * c.r) ? 1.0 : 0.0; }

// How much a root texel at DIST metres from its bulb glows now: its veins (saturated reds) only,
// faintly at rest and flaring as each heartbeat, a lub and a dub, runs out from the bulb. Stepped,
// as the aurora's light is, so it stays on the art's few tones.
float root_beat(vec3 surface, float dist, float clock){
  float vein = (surface.r > 0.4 && surface.g + surface.b < 0.45 * surface.r) ? 1.0 : 0.0;
  float p = fract((clock - dist / beat_speed) / beat_period);
  float beat = exp(-p * p / 0.002) + exp(-(1.0 - p) * (1.0 - p) / 0.002)
             + 0.6 * exp(-(p - 0.16) * (p - 0.16) / 0.002);
  return vein * floor((vein_glow + beat_glow * beat) * 4.0) / 4.0;
}

void main(){
  vec2 size = vec2(textureSize(texture_image, 0));
  vec2 texel = min(floor(v_uv * vec2(cell_width, cell_height)), vec2(cell_width, cell_height) - 1.0);
  vec4 tuft = texture(texture_image, vec2(v_frame * (cell_width + cell_gap) + texel.x + 0.5, texel.y + 0.5) / size);
  if(tuft.a < 0.5) discard;
  vec3 surface = tuft.rgb;
  if(v_frost > 0.5) surface = mix(surface, vec3(0.74, 0.86, 0.95), 0.55);
  vec3 light = band_light(light_at(snap_position(v_world_position), vec3(0), 0.0, v_probe));
  vec3 lamp = lamp_part(light);
  vec3 glow = surface * lamp + tuft.rgb * root_beat(tuft.rgb, v_dist, clock) * (1.0 - v_frost);
  float drink = drink_glow(v_world_position) * mix(0.35, 1.0, vein_of(tuft.rgb));
  if(drink > 0.0){ surface *= 1.0 - drink; glow += drink_color(drink); }
  color = vec4(fog_lit(surface * (light - lamp), glow, length(v_view_position)), 1.0);
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
  (preload (make-instance 'snare-sprite :animation (find-fx-animation 'snare-grip)) scene)
  (preload (make-instance 'fx-sprite :animation (find-fx-animation 'seed-burst)) scene))
