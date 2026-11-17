(in-package #:hexmaw)

;;; The arc votary: a blind storm-priest that holds a beam of lightning on its target, the first monster
;;; whose attack is held rather than thrown. A crackle builds between its hands for *VOTARY-CHARGE*
;;; seconds while a faint ranging line shows where it aims; then it holds the beam for up to
;;; *VOTARY-HOLD* seconds, striking every *BEAM-PULSE* (spells.lisp) and turning after its target at
;;; only *VOTARY-BEAM-TURN*, so a player who circles it at a run slips out of the beam, and one who
;;; steps behind cover makes it let go. Each pulse is a blow the raised shield meets, at
;;; *ARC-BLOCK-STAMINA* a pulse, so the shield doesn't hold a whole beam; Absorb takes only
;;; projectiles, so it does nothing. A beam that reaches one of its allies jumps from it to the
;;; nearest hostile body within CHAIN-REACH; one that strikes a body in water, or the water itself,
;;; strikes harder and runs through it to every body in the water within *ARC-WATER-REACH*.

(defparameter *votary-height* 2.0 "Votary height in metres, its crown of rods to its feet.")
(defparameter *votary-hand-height* 0.6
  "Share of its height its hands are held at, where the beam and the crackle start.")
(defparameter *votary-range* 11.0 "Metres from its target it starts a beam from (*BEAM-RANGE* is 12).")
(defparameter *votary-charge* 0.9 "Seconds of the charge's tell before the beam.")
(defparameter *votary-hold* 3.0 "Seconds it holds the beam at most.")
(defparameter *votary-turn* 2.5 "Radians a second it turns, walking or charging: a deliberate turner.")
(defparameter *votary-beam-turn* 1.2 "Radians a second it turns after its target while it holds the beam.")
(defparameter *votary-pain-bonus* 20 "Percent added to its pain chance while it holds the beam.")
(defparameter *votary-lost-time* 0.75
  "Seconds of pulses striking nothing hostile after which it lets go of the beam and recovers.")
(defparameter *arc-chain-reach* 3.5 "Metres between bodies a beam jumps from one of the votary's allies.")
(defparameter *arc-water-reach* 6.0 "Metres across water a beam runs from what it strikes in it.")
(defparameter *arc-water-scale* 1.5 "How much harder a beam strikes what stands in water.")
(defparameter *arc-block-stamina* 12.0
  "Stamina a pulse costs the player's raised shield: 48 a second against a regen of 8, so a full bar
gives out before the beam does.")
(defparameter *votary-light-color* (vec 1.5 1.35 0.7)
  "Its lamp's colour at full strength: its lightning's yellow-white.")
(defparameter *votary-light-radius* 5.0)
(defparameter *votary-idle-glow* 0.35
  "How bright its lamp is at rest, against the beam's: its idle lightning lights it and what is near.")
(defparameter *votary-arc-time* 0.08 "Seconds between redrawings of its idle lightning.")
(defparameter *votary-hand-arc-chance* 0.75 "Chance each redrawing puts an arc between its hands at rest.")
(defparameter *votary-crown-arc-chance* 0.45 "Chance each redrawing puts an arc between two of its crown's rods.")
(defparameter *votary-arc-reach* 25.0 "Metres from the player within which it draws its idle lightning.")
(defparameter *votary-crackle-time* 0.06 "Seconds between redrawings of the crackle between its hands.")
(defparameter *votary-burst-clearance* 2.5
  "Metres from the player's eye within which the beam's burst isn't drawn where it stops: sparks instead.")
(defparameter *votary-bolt-time* 0.04 "Seconds between redrawings of the held beam's lightning.")
(defparameter *votary-bolt-roughness* 0.06
  "How far the beam's lightning strays from its line, a share of its length at the first fork.")
(defparameter *votary-bolt-clearance* 1.5
  "Metres from the player's eye short of which the beam's lightning stops: nearer, perspective blew its
jitter up across the whole view. The pain flash and the sparks show the strike.")
(defparameter *votary-aim-time* 0.05 "Seconds between aims of its ranging line and beam at what they reach.")

;; Sliced at 128 px tall for its 2 m, crown included, at the monsters' 64 px a metre.
(define-asset (hexmaw votary-turnaround) image
    #p"sprites/votary/turnaround.png"
  :min-filter :nearest :mag-filter :nearest)

;; A slow, measured step, the hands held apart; four frames per view, the frame following the
;; distance walked (STRIDE).
(define-fx-animation votary-walk "sprites/votary/walk" :loop T :size (* *votary-height* 129/128))
;; The beam: the hands wide apart with an arc between them, brought together on a knot of
;; lightning (the charge's held frame), thrust forward (the frame the hold holds), recover. Four
;; frames per view, on ATTACK-FRAME-TIMES.
(define-fx-animation votary-cast "sprites/votary/cast" :size (* *votary-height* 130/128))
;; The flinch: jolt, then stagger, two frames per view over *STAGGER-TIME*.
(define-fx-animation votary-hurt "sprites/votary/hurt" :size *votary-height*)
;; Lightning crawls over it along the wire, and it falls face down. Front view only.
(define-fx-animation votary-death "sprites/votary/death" :fps 9 :size (* *votary-height* 129/128))

;; What each pulse strikes with, whole: the beam is the votary's own (VOTARY-PULSE), the spell its
;; damage, look and light.
(define-spell arc-beam (:delivery :beam :title "Arc Beam" :impact-animation 'shock-burst
                        :light-color (vec 1.6 1.5 0.6) :light-radius 2.5)
  (:damage :magnitude '(3 4) :element :shock))

(define-spell hierophant-beam (:delivery :beam :title "Arc Beam" :impact-animation 'shock-burst
                               :light-color (vec 1.6 1.5 0.6) :light-radius 3.0)
  (:damage :magnitude '(4 6) :element :shock))

(defun votary-abilities ()
  ;; Gather and charge (the tell), the beam held, recover.
  (list (make-instance 'ability :name :arc-beam :spell 'arc-beam :animation 'votary-cast
                                :frame-times (list 0.3 (- *votary-charge* 0.3) *votary-hold* 0.4)
                                :hit-frame 2 :pause 1.0)))

(define-shader-entity arc-votary (ability-user creature)
  ((texture :initform (// 'hexmaw 'votary-turnaround))
   (atlas :initform (read-atlas "sprites/votary/turnaround.lisp"))
   (sprite-height :initform *votary-height*)
   (walk-animation :initform 'votary-walk)
   ;; What a boss's powers show (POWER-ANIMATION, boss.lisp); the ability answers otherwise.
   (attack-animation :initform 'votary-cast)
   (hurt-animation :initform 'votary-hurt)
   (death-animation :initform 'votary-death)
   (gibs :initform '((:flesh 0 0 1 1 2 3 4 5 6 6 7 7)))
   (abilities :initform (votary-abilities))
   (attack-range :initform *votary-range*)
   (keep-away :initform 4.0)
   ;; Both hands, in front of its middle.
   (cast-offset :initform 0.0)
   (walk-speed :initform 0.9)
   (chase-speed :initform 1.5)
   (wander-radius :initform 2.0)
   (turn-speed :initform *votary-turn*)
   (pain-chance :initform 20)
   (max-health :initform 30)
   (pulse-timer :initform 0.0 :accessor pulse-timer :documentation "Seconds to the beam's next strike.")
   (lost-timer :initform 0.0 :accessor lost-timer
               :documentation "Seconds of the beam's pulses that struck nothing hostile, in a row.")
   (crackle-timer :initform 0.0 :accessor crackle-timer)
   (arc-timer :initform 0.0 :accessor arc-timer :documentation "Seconds to its idle lightning's next redrawing.")
   (aim-timer :initform 0.0 :accessor aim-timer)
   (lamp :initform NIL :accessor votary-lamp)
   (beam-sound :initform NIL :accessor beam-sound :documentation "The held beam's loop.")
   (wet-spell :initform NIL :documentation "Its beam's spell, stronger, for what stands in water: made once.")
   (aim-origin :initform (vec 0 0 0) :reader aim-origin)
   (aim-direction :initform (vec 0 0 -1) :reader aim-direction)
   (bolt-end :initform (vec 0 0 0) :reader bolt-end :documentation "Where the held beam's lightning ends.")
   (bolt-timer :initform 0.0 :accessor bolt-timer :documentation "Seconds to the held beam's next redrawing.")
   (chain-from :initform NIL :accessor chain-from
               :documentation "The ally the beam jumps from at its last pulse, or NIL: its jump is drawn with the beam.")
   (chain-to :initform NIL :accessor chain-to :documentation "What that jump strikes.")))

(define-creature-sounds arc-votary
  :alert :votary-alert :pain :votary-pain :death :votary-death :windup :votary-charge :step :step-light)

;; Killed by a player who doesn't know shock, it drops the shock glyph (pickups.lisp).
(defmethod taught-effect ((votary arc-votary)) :shock)

(defgeneric votary-beam-spell (votary)
  (:documentation "The name of the spell VOTARY's beam strikes with.")
  (:method ((votary arc-votary)) 'arc-beam))

(defgeneric chain-reach (votary)
  (:documentation "Metres between bodies VOTARY's beam jumps from one of its allies.")
  (:method ((votary arc-votary)) *arc-chain-reach*))

(defun wet-spell (votary)
  (or (slot-value votary 'wet-spell)
      (setf (slot-value votary 'wet-spell)
            (scaled-spell (find-spell (votary-beam-spell votary)) *arc-water-scale*))))

(defun votary-power-p (votary)
  "True while VOTARY, a boss, uses one of its powers rather than its beam."
  (and (typep votary 'boss) (boss-power votary)))

(defun charging-arc-p (votary)
  "True while VOTARY's beam has yet to leave: the charge's tell."
  (and (not (dead votary)) (ability-p votary :arc-beam) (not (votary-power-p votary)) (winding-up-p votary)))

(defun holding-beam-p (votary)
  "True while VOTARY holds its beam: past the release, within the frame held for it."
  (and (not (dead votary))
       (eq (brain votary) :attacking)
       (ability-p votary :arc-beam)
       (not (votary-power-p votary))
       (not (attack-pending votary))
       (let ((time (attack-time votary))
             (hit (attack-hit-time votary)))
         (and time (<= hit time) (< time (+ hit (third (attack-frame-times votary))))))))

;; Holding the beam, it is easier to break, and slow to turn.
(defmethod pain-chance :around ((votary arc-votary))
  (if (holding-beam-p votary)
      (+ (call-next-method) *votary-pain-bonus*)
      (call-next-method)))

(defmethod turn-speed :around ((votary arc-votary))
  (if (holding-beam-p votary) *votary-beam-turn* (call-next-method)))

(defmethod hunt-from-range ((votary arc-votary))
  "Back off from a target too close; with one in range and sight, charge the beam; or close in."
  (let ((distance (target-distance votary))
        (target (hunt-target votary)))
    (cond ((and (< distance (keep-away votary)) (retreat votary)))
          ((and (< distance (attack-range votary))
                (clear-path-p (location votary) (body-feet target) (cast-height votary)))
           (start-ability votary :arc-beam))
          (T (chase votary)))))

(defmethod release-attack ((votary arc-votary))
  ;; The beam leaves: it strikes at once, then every *BEAM-PULSE* while it is held.
  (setf (pulse-timer votary) 0.0
        (lost-timer votary) 0.0
        (aim-timer votary) 0.0)
  (play-sound :votary-beam-start (aim-origin votary)))

(defun votary-aim (votary)
  "Where VOTARY's beam leaves from, its hands, and its way: across, the way it faces (its turning
is what aims it), tipped up or down to its target's chest. Both are VOTARY's own vecs."
  (let* ((loc (location votary))
         (yaw (facing votary))
         (fx (sin yaw))
         (fz (- (cos yaw)))
         (out (+ (body-radius votary) 0.15))
         (o (aim-origin votary))
         (d (aim-direction votary))
         (target (hunt-target votary))
         (across 1.0)
         (dy 0.0))
    (setf (vx o) (+ (vx loc) (* out fx))
          (vy o) (+ (vy loc) (* *votary-hand-height* (sprite-height votary)))
          (vz o) (+ (vz loc) (* out fz)))
    (when target
      (let ((feet (body-feet target)))
        (setf across (max 0.5 (sqrt (+ (expt (- (vx feet) (vx o)) 2) (expt (- (vz feet) (vz o)) 2))))
              dy (- (+ (vy feet) (aim-height target)) (vy o)))))
    (let ((len (sqrt (+ (* across across) (* dy dy)))))
      (setf (vx d) (float (/ (* fx across) len) 0f0)
            (vy d) (float (/ dy len) 0f0)
            (vz d) (float (/ (* fz across) len) 0f0)))
    (values o d)))

(defun body-chest (body)
  (let ((feet (body-feet body)))
    (vec (vx feet) (+ (vy feet) (* 0.6 (body-height body))) (vz feet))))

(defun in-water-p (body)
  "True if BODY stands or swims in water: deep water or a ford's shallows."
  (or (and (typep body 'creature) (afloat-p body))
      (let* ((feet (body-feet body))
             (liquid (liquid-at (vx feet) (+ (vy feet) 0.05) (vz feet))))
        (and liquid (member (liquid-kind liquid) '(:water :shallows)) T))))

(defun live-bodies ()
  "Every live creature, and the player while alive."
  (let ((bodies (loop for c across *creatures* unless (dead c) collect c)))
    (if (and *player* (< 0 (health *player*))) (cons *player* bodies) bodies)))

(defun arc-strike (votary body from at &key wet)
  "One pulse of VOTARY's beam strikes BODY from point FROM, reaching it at point AT: a covering
shield on a creature stops it; WET, it strikes harder."
  (let ((spell (if wet (wet-spell votary) (find-spell (votary-beam-spell votary)))))
    (cond ((and (typep body 'creature) (shielded-p body from))
           (block-hit body)
           (spray-sparks at NIL 4 :ramp :shock))
          (T
           (when (and (typep body 'player) (shield-blocks-p body from))
             (spray-sparks at NIL 4 :ramp :shock :speed '(1.0 3.0)))
           (let ((source (make-instance 'beam-pulse :spell spell :caster votary :origin from
                                                    :block-cost *arc-block-stamina*)))
             (dolist (effect (spell-effects spell))
               (when (target-effect-p effect)
                 (apply-effect (effect-kind effect) effect body source))))))))

(defun chain-target (votary ally)
  "The nearest body hostile to VOTARY within its CHAIN-REACH of ALLY, edge to edge, in a clear line."
  (let ((at (body-feet ally))
        (from (body-chest ally))
        (best NIL)
        (best-gap (chain-reach votary)))
    (dolist (body (live-bodies) best)
      (unless (or (eq body ally) (eq body votary) (not (hostile-p votary body)))
        (let* ((feet (body-feet body))
               (gap (- (sqrt (+ (expt (- (vx feet) (vx at)) 2) (expt (- (vz feet) (vz at)) 2)))
                       (body-radius body) (body-radius ally))))
          (when (and (< gap best-gap) (< (abs (- (vy feet) (vy at))) 2.0)
                     (clear-line-p from (body-chest body)))
            (setf best body best-gap gap)))))))

(defun arc-bolt (from to &key (life 0.12))
  "Draw a jagged arc of lightning between points FROM and TO."
  (bolt-line (vx from) (vy from) (vz from) (vx to) (vy to) (vz to) 3
             :roughness 0.18 :width 2.0 :branch 0.15 :life life))

(defun water-strike (votary point struck)
  "A pulse of VOTARY's beam reached water at POINT: strike every other body in water within
*ARC-WATER-REACH* of it, in a clear line, with an arc over the surface to each. STRUCK is the body
already struck there, or NIL. True if it struck anything hostile."
  (let ((hostile NIL)
        (from (vec (vx point) (+ (vy point) 0.1) (vz point))))
    (dolist (body (live-bodies))
      (unless (or (eq body votary) (eq body struck) (not (in-water-p body)))
        (let ((feet (body-feet body)))
          (when (and (< (+ (expt (- (vx feet) (vx point)) 2) (expt (- (vz feet) (vz point)) 2))
                        (expt *arc-water-reach* 2))
                     (< (abs (- (vy feet) (vy point))) 2.0)
                     (clear-line-p from (vec (vx feet) (+ (vy feet) 0.3) (vz feet))))
            (let ((to (vec (vx feet) (+ (vy feet) 0.3) (vz feet))))
              (arc-bolt from to)
              (arc-strike votary body from to :wet T)
              (when (hostile-p votary body) (setf hostile T)))))))
    (when hostile
      (play-sound :arc-zap point))
    hostile))

(defun water-beyond-p (end direction)
  "True if a beam that stopped at END along DIRECTION stopped on the surface of water."
  (let ((liquid (liquid-at (+ (vx end) (* 1.5 *beam-step* (vx direction)))
                           (+ (vy end) (* 1.5 *beam-step* (vy direction)))
                           (+ (vz end) (* 1.5 *beam-step* (vz direction))))))
    (and liquid (member (liquid-kind liquid) '(:water :shallows)) T)))

(defun votary-pulse (votary)
  "One strike of VOTARY's held beam: what it reaches along its aim, a jump from an ally, and the
water. Returns where the beam stops and the body it reached there, or NIL."
  (multiple-value-bind (origin dir) (votary-aim votary)
    (multiple-value-bind (end victim) (beam-end origin dir votary)
      (let ((hit NIL) (wet-at NIL) (wet-body NIL))
        (setf (chain-from votary) NIL
              (chain-to votary) NIL)
        (cond ((null victim))
              ((hostile-p votary victim)
               (setf hit T)
               (let ((wet (in-water-p victim)))
                 (arc-strike votary victim origin end :wet wet)
                 (when wet (setf wet-at (body-feet victim) wet-body victim))))
              (T
               ;; An ally: the beam jumps from it to the nearest of its foes, sparing it.
               (let ((next (chain-target votary victim)))
                 (when next
                   (let ((from (body-chest victim))
                         (to (body-chest next))
                         (wet (in-water-p next)))
                     (setf hit T
                           (chain-from votary) victim
                           (chain-to votary) next)
                     ;; Its jump is redrawn with the beam (BEAM-BOLTS); a burst of sparks off the ally.
                     (spray-sparks from NIL 5 :ramp :shock :speed '(1.0 3.0))
                     (play-sound :arc-zap from)
                     (arc-strike votary next from to :wet wet)
                     (when wet (setf wet-at (body-feet next) wet-body next)))))))
        (when (and (null wet-at) (null victim) (water-beyond-p end dir))
          (setf wet-at end))
        (when (and wet-at (water-strike votary wet-at wet-body))
          (setf hit T))
        (setf (lost-timer votary) (if hit 0.0 (+ (lost-timer votary) *beam-pulse*)))
        (strike-skins :shock end *impact-skin-reach* votary)
        ;; Its burst, but not on or right by the player (on the water they swim in), where it would
        ;; fill the view.
        (if (or (typep victim 'player)
                (and *player* (< (vdistance end (location *player*)) *votary-burst-clearance*)))
            (spray-sparks end NIL 2 :ramp :shock :speed '(0.5 2.0))
            (play-impact (find-spell (votary-beam-spell votary)) end (container votary) :quiet T))
        (values end victim)))))

(defun aim-bolt-end (votary end victim)
  "Set where VOTARY's lightning ends: at END, where its beam stopped, or, on a creature, at that
height in the middle of its body, where its sprite is drawn: the beam touches a body at the edge of
its reach, an imp's 0.55 m and an ogre's 1.2 m short of the sprite."
  (let ((e (bolt-end votary)))
    (if (typep victim 'creature)
        (let ((loc (location victim)))
          (setf (vx e) (vx loc) (vy e) (vy end) (vz e) (vz loc)))
        (v<- e end))))

(defun votary-glow (votary k)
  "VOTARY's lamp at its hands, K of its full strength."
  (let ((lamp (votary-lamp votary)))
    (unless (and lamp (find lamp *lamps*))
      (setf lamp (add-lamp (aim-origin votary) *votary-light-color* *votary-light-radius* :flicker 0.3)
            (votary-lamp votary) lamp))
    (v<- (location lamp) (aim-origin votary))
    (let ((color (color lamp)))
      (setf (vx color) (* k (vx *votary-light-color*))
            (vy color) (* k (vy *votary-light-color*))
            (vz color) (* k (vz *votary-light-color*))))))

;; Where its hands are drawn in each view of its sprite (BILLBOARD-VIEW, 0 front .. 4 back), measured
;; on its 128 px turnaround: (ACROSS SPREAD HIGH), the middle between them in metres across the sprite
;; (image right, for a 2 m votary), how far either side of it they are, and their height as a share of
;; its own. From behind its body hides them: NIL.
(defparameter *votary-hand-spots*
  #((-0.01 0.24 0.61) (-0.14 0.13 0.62) (-0.19 0.06 0.63) (-0.2 0.07 0.63) NIL))

;; Where the hold pose (the cast strip's third frame) draws its palms in each view: (ACROSS HIGH), as
;; *VOTARY-HAND-SPOTS*. From behind they are hidden: the beam starts from its middle (SPRITE-POINT).
(defparameter *votary-palm-spots*
  #((0.0 0.61) (-0.36 0.64) (-0.37 0.64) (-0.37 0.65) (0.0 0.62)))

(defun sprite-frame (votary)
  "The camera's view of VOTARY's sprite: its eye, the view's right across the sprite (RX RZ), the
way from the eye to it (FX FZ, unit), and the view (0 front .. 4 back) and whether it is mirrored."
  (let* ((loc (location votary))
         (eye (location (camera (scene +main+))))
         (fx (- (vx loc) (vx eye)))
         (fz (- (vz loc) (vz eye)))
         (fl (max 1f-4 (sqrt (+ (* fx fx) (* fz fz))))))
    (multiple-value-bind (view mirrored) (billboard-view votary eye)
      (values (/ (- fz) fl) (/ fx fl) (/ fx fl) (/ fz fl) view mirrored))))

(defun spot-place (spot spots)
  "ACROSS and HIGH of SPOT, an entry of SPOTS: *VOTARY-HAND-SPOTS*' are (ACROSS SPREAD HIGH),
*VOTARY-PALM-SPOTS*' (ACROSS HIGH). A hidden one (NIL) is its middle at its hands' height."
  (cond ((null spot) (values 0.0 0.61))
        ((eq spots *votary-hand-spots*) (values (first spot) (third spot)))
        (T (values (first spot) (second spot)))))

(defun sprite-point (votary spots)
  "Where its sprite, as the camera sees it, draws what SPOTS (*VOTARY-HAND-SPOTS* or
*VOTARY-PALM-SPOTS*, by view) places: in the sprite's plane, a few centimetres toward the camera:
X Y Z."
  (multiple-value-bind (rx rz fx fz view mirrored) (sprite-frame votary)
    (multiple-value-bind (across high) (spot-place (aref spots view) spots)
      (let* ((loc (location votary))
             (h (sprite-height votary))
             (c (* (/ h *votary-height*) (if mirrored (- across) across))))
        (values (- (+ (vx loc) (* rx c)) (* 0.05 fx))
                (+ (vy loc) (* h high))
                (- (+ (vz loc) (* rz c)) (* 0.05 fz)))))))

(defun bolt-span (votary spots)
  "Where a bolt of VOTARY's from what SPOTS places (SPRITE-POINT) to BOLT-END is drawn: X0 Y0 Z0 X1
Y1 Z1, and whether it comes at the camera. One ending at the player's eye stops
*VOTARY-BOLT-CLEARANCE* short of it, back along its line."
  (multiple-value-bind (x0 y0 z0) (sprite-point votary spots)
    (let* ((e (bolt-end votary))
           (x1 (vx e)) (y1 (vy e)) (z1 (vz e))
           (eye (location (camera (scene +main+))))
           (near (sqrt (+ (expt (- x1 (vx eye)) 2) (expt (- y1 (vy eye)) 2) (expt (- z1 (vz eye)) 2))))
           (close (< near *votary-bolt-clearance*)))
      (when close
        (let* ((dx (- x0 x1)) (dy (- y0 y1)) (dz (- z0 z1))
               (len (max 1f-4 (sqrt (+ (* dx dx) (* dy dy) (* dz dz)))))
               (back (min (* 0.9 len) (- *votary-bolt-clearance* near))))
          (setf x1 (+ x1 (* back (/ dx len)))
                y1 (+ y1 (* back (/ dy len)))
                z1 (+ z1 (* back (/ dz len))))))
      (values x0 y0 z0 x1 y1 z1 close))))

(defparameter *votary-bolt-chest* '(0.6 0.45)
  "Where a bolt struck at the player's eye runs into their view from *VOTARY-BOLT-CLEARANCE* off:
(OUT DOWN), metres out along the way to the bolt and down from the eye, below the view's middle, where
their chest is.")

(defun last-stretch (x1 y1 z1 &rest bolt-args &key (side 0.0) (lower 0.0) &allow-other-keys)
  "Carry a bolt that stopped short of the player's eye, at X1 Y1 Z1, the rest of the way into their
view: a short stretch, nearly straight (its jitter scales with its length, and so close to the camera
any more crosses the view), to the bottom of the view where their chest is; SIDE metres to the view's
right and LOWER further down, for a jump's scattered landings."
  (let* ((eye (location (camera (scene +main+))))
         (dx (- x1 (vx eye))) (dy (- y1 (vy eye))) (dz (- z1 (vz eye)))
         (len (max 1f-4 (sqrt (+ (* dx dx) (* dy dy) (* dz dz)))))
         (hl (max 1f-4 (sqrt (+ (* dx dx) (* dz dz)))))
         ;; The view's right, across the way to the bolt.
         (rx (/ (- dz) hl))
         (rz (/ dx hl)))
    (let ((args (copy-list bolt-args)))
      (remf args :side)
      (remf args :lower)
      (destructuring-bind (out down) *votary-bolt-chest*
        (apply #'bolt-line x1 y1 z1
               (+ (vx eye) (* out (/ dx len)) (* side rx))
               (- (+ (vy eye) (* out (/ dy len))) down lower)
               (+ (vz eye) (* out (/ dz len)) (* side rz))
               2 args)))))

(defun eye-bolt (x0 y0 z0 x1 y1 z1 depth &key (roughness 0.2) (width 2.0) (white 0.0) (branch 0.0)
                                               (drop 0.0) (life 0.05) (side 0.0) (lower 0.0))
  "A bolt from X0 Y0 Z0 to X1 Y1 Z1 that keeps out of the player's eye: ending within
*VOTARY-BOLT-CLEARANCE* of it, its jagged part stops that far off, with no forks, and LAST-STRETCH
carries it on into the bottom of the view."
  (let* ((eye (location (camera (scene +main+))))
         (near (sqrt (+ (expt (- x1 (vx eye)) 2) (expt (- y1 (vy eye)) 2) (expt (- z1 (vz eye)) 2))))
         (close (< near *votary-bolt-clearance*)))
    (when close
      (let* ((dx (- x0 x1)) (dy (- y0 y1)) (dz (- z0 z1))
             (len (max 1f-4 (sqrt (+ (* dx dx) (* dy dy) (* dz dz)))))
             (back (min (* 0.9 len) (- *votary-bolt-clearance* near))))
        (setf x1 (+ x1 (* back (/ dx len)))
              y1 (+ y1 (* back (/ dy len)))
              z1 (+ z1 (* back (/ dz len))))))
    (bolt-line x0 y0 z0 x1 y1 z1 depth :roughness roughness :width width :white white
                                       :branch (if close 0.0 branch) :drop drop :life life)
    (when close
      (last-stretch x1 y1 z1 :roughness 0.04 :width width :white white :drop drop :life life
                             :side side :lower lower))))

(defparameter *votary-jump-bolts* '(2 3) "Least and most bolts a jump is drawn as at each redrawing.")

(defun body-spot (body)
  "A random spot on BODY as the camera sees it: across its sprite within its body's radius, from a
third to nine tenths of its height up: X Y Z."
  (let* ((feet (body-feet body))
         (eye (location (camera (scene +main+))))
         (fx (- (vx feet) (vx eye)))
         (fz (- (vz feet) (vz eye)))
         (fl (max 1f-4 (sqrt (+ (* fx fx) (* fz fz)))))
         (across (* (body-radius body) (- (random 2.0) 1.0))))
    (values (+ (vx feet) (* across (/ (- fz) fl)))
            (+ (vy feet) (* (body-height body) (+ 0.33 (random 0.57))))
            (+ (vz feet) (* across (/ fx fl))))))

(defun chain-bolt (votary life)
  "Redraw the jump of VOTARY's beam from the ally it reached to what it strikes, while both live: not
one bolt, which read as the beam going on through the ally, but two or three, each from a random spot
on the ally to a random spot on what it strikes, more jagged and forked than the beam and redrawn every
time, so it crackles. On the player they land scattered over the bottom of the view."
  (let ((from (chain-from votary))
        (to (chain-to votary)))
    (when (and from to (not (dead from)) (target-live-p to))
      (destructuring-bind (least most) *votary-jump-bolts*
        (dotimes (i (+ least (random (1+ (- most least)))))
          (multiple-value-bind (x0 y0 z0) (body-spot from)
            (multiple-value-bind (x1 y1 z1) (body-spot to)
              (eye-bolt x0 y0 z0 x1 y1 z1 4 :roughness 0.25 :width 2.0 :white 0.4 :branch 0.3
                                            :life (* 0.6 life)
                                            :side (- (random 0.7) 0.35) :lower (random 0.15)))))))))

(defun beam-bolts (votary)
  "Redraw VOTARY's held beam as lightning from its palms to where it ends: a broad bolt with a white
core and a thinner one forking about it, as the shock nova's are, each lasting two redrawings."
  (multiple-value-bind (x0 y0 z0 x1 y1 z1 close) (bolt-span votary *votary-palm-spots*)
    (let ((life (* 2.2 *votary-bolt-time*))
          (r *votary-bolt-roughness*)
          ;; Its forks fly wide near the camera: none on a bolt coming at it.
          (fork (if close 0.0 1.0)))
      (bolt-line x0 y0 z0 x1 y1 z1 6 :roughness r :width 3.0 :white 0.6 :branch (* fork 0.15) :life life)
      (bolt-line x0 y0 z0 x1 y1 z1 5 :roughness (* 1.8 r) :width 1.5 :white 0.2 :branch (* fork 0.35)
                                     :drop 0.15 :life life)
      (when close
        (last-stretch x1 y1 z1 :roughness 0.04 :width 3.0 :white 0.6 :life life))
      (chain-bolt votary life))))

(defun ranging-bolt (votary k)
  "Redraw the charge's ranging line as faint lightning from the knot between its hands to where the
beam would strike: one thread an art pixel wide, broken up, that firms as K, the charge, grows."
  (when (< (random 1.0) (+ 0.5 (* 0.4 k)))
    (multiple-value-bind (x0 y0 z0 x1 y1 z1 close) (bolt-span votary *votary-hand-spots*)
      (let ((drop (- 0.6 (* 0.4 k)))
            (life (* 1.2 *votary-aim-time*)))
        (bolt-line x0 y0 z0 x1 y1 z1 5 :roughness (* 0.8 *votary-bolt-roughness*) :width 1.0
                                       :drop drop :life life)
        (when close
          (last-stretch x1 y1 z1 :roughness 0.04 :width 1.0 :drop drop :life life))))))

(defun hand-arc (votary spread-scale &rest bolt-args)
  "Draw an arc between VOTARY's hands as its sprite shows them from the camera: in the plane the sprite
is drawn in, at the hands of the view it shows, mirrored with it, SPREAD-SCALE times as wide; none from
behind, where its body hides them. BOLT-ARGS go to BOLT-LINE."
  (multiple-value-bind (rx rz fx fz view mirrored) (sprite-frame votary)
    (let ((spot (aref *votary-hand-spots* view))
          (loc (location votary)))
      (when spot
        (destructuring-bind (across spread high) spot
          (let* ((h (sprite-height votary))
                 (s (/ h *votary-height*))
                 ;; Across the sprite, and a few centimetres toward the camera.
                 (c (* s (if mirrored (- across) across)))
                 (cx (- (+ (vx loc) (* rx c)) (* 0.05 fx)))
                 (cz (- (+ (vz loc) (* rz c)) (* 0.05 fz)))
                 (d (* s spread spread-scale))
                 (y (+ (vy loc) (* h high))))
            (apply #'bolt-line (- cx (* rx d)) y (- cz (* rz d)) (+ cx (* rx d)) y (+ cz (* rz d)) 3
                   bolt-args)))))))

(defun crackle (votary k)
  "Redraw the arc between VOTARY's hands, closer and fiercer as K, the charge, grows."
  (hand-arc votary (- 1.3 (* 0.6 k))
            :roughness (+ 0.2 (* 0.2 k)) :width (+ 1.0 k) :branch (* 0.3 k)
            :life (* 1.3 *votary-crackle-time*)))

(defun end-hold (votary)
  "Let go of the beam: on to the recover frame."
  (setf (attack-time votary) (+ (attack-hit-time votary) (third (attack-frame-times votary)))))

(defun release-beam (votary)
  "Stop the held beam's loop."
  (setf (beam-sound votary) (stop-loop (beam-sound votary))))

(defun douse-votary (votary)
  "Put VOTARY's light out for good: dead, or gone from the scene."
  (release-beam votary)
  (when (votary-lamp votary)
    (remove-lamp (votary-lamp votary))
    (setf (votary-lamp votary) NIL)))

(defun rest-votary (votary)
  "Neither charging nor holding: the beam's loop stops; its idle lightning keeps the lamp lit low."
  (release-beam votary)
  (votary-aim votary)
  (votary-glow votary *votary-idle-glow*))

(defun idle-arcs (votary)
  "Redraw VOTARY's idle lightning: an arc between its hands (not while it charges, whose own crackle
is there; HAND-ARC, where its sprite draws its hands) and arcs between the tips of its crown's rods,
as the shock nova's bolts. Both lie in the plane its sprite is drawn in, so they sit on it from any
side."
  (let* ((loc (location votary))
         (h (sprite-height votary))
         (s (/ h *votary-height*))
         (yaw (facing votary))
         (camera (camera (scene +main+)))
         (eye (location camera))
         (fx (- (vx loc) (vx eye)))
         (fz (- (vz loc) (vz eye)))
         (fl (max 1f-4 (sqrt (+ (* fx fx) (* fz fz)))))
         ;; The view's right, across the sprite.
         (rx (/ (- fz) fl))
         (rz (/ fx fl)))
    (unless (or (charging-arc-p votary) (holding-beam-p votary))
      (when (< (random 1.0) *votary-hand-arc-chance*)
        (hand-arc votary 1.0 :roughness 0.25 :branch 0.3 :white 0.3 :life (* 1.3 *votary-arc-time*))))
    ;; Five rod tips in a fan, 0.18 m either side of the head, 0.97 to 0.91 of its height; the head
    ;; leans 8 cm toward its face, which shows only from the side.
    (flet ((tip (i)
             (let ((a (- (* 0.5 i) 1.0)))
               (values (+ (vx loc) (* rx 0.18 s a) (* 0.08 s (sin yaw)))
                       (+ (vy loc) (* h (- 0.97 (* 0.06 a a))))
                       (- (+ (vz loc) (* rz 0.18 s a)) (* 0.08 s (cos yaw)))))))
      (dotimes (i 4)
        (when (< (random 1.0) *votary-crown-arc-chance*)
          (multiple-value-bind (x0 y0 z0) (tip i)
            (multiple-value-bind (x1 y1 z1) (tip (1+ i))
              (bolt-line x0 y0 z0 x1 y1 z1 2 :roughness 0.3 :branch 0.2 :white 0.3
                                             :life (* 1.3 *votary-arc-time*)))))))))

(defun votary-sparks (votary dt)
  "VOTARY's idle lightning, redrawn every *VOTARY-ARC-TIME* while the player is near enough to see it."
  (when (<= (decf (arc-timer votary) dt) 0.0)
    (setf (arc-timer votary) *votary-arc-time*)
    (let ((player *player*))
      (when player
        (let ((a (location votary))
              (b (location player)))
          (when (< (+ (expt (- (vx a) (vx b)) 2) (expt (- (vz a) (vz b)) 2)) (expt *votary-arc-reach* 2))
            (idle-arcs votary)))))))

(defun charge-votary (votary dt)
  (let ((k (min 1.0 (/ (attack-time votary) (attack-hit-time votary)))))
    (votary-aim votary)
    (votary-glow votary (+ *votary-idle-glow* (* (- 0.8 *votary-idle-glow*) k)))
    (when (<= (decf (crackle-timer votary) dt) 0.0)
      (setf (crackle-timer votary) *votary-crackle-time*)
      (crackle votary k))
    (when (<= (decf (aim-timer votary) dt) 0.0)
      (setf (aim-timer votary) *votary-aim-time*)
      (multiple-value-call #'aim-bolt-end votary (beam-end (aim-origin votary) (aim-direction votary) votary))
      (ranging-bolt votary k))))

(defun hold-votary-beam (votary dt)
  (let ((target (hunt-target votary)))
    (if (not (and target (target-live-p target)))
        (end-hold votary)
        (progn
          (face-target votary dt target)
          (votary-aim votary)
          (votary-glow votary 1.0)
          (setf (beam-sound votary) (hold-loop (beam-sound votary) :votary-beam (aim-origin votary)))
          (when (<= (decf (pulse-timer votary) dt) 0.0)
            (incf (pulse-timer votary) *beam-pulse*)
            (setf (aim-timer votary) *votary-aim-time*)
            (multiple-value-call #'aim-bolt-end votary (votary-pulse votary)))
          ;; Between strikes the lightning follows the aim.
          (when (<= (decf (aim-timer votary) dt) 0.0)
            (setf (aim-timer votary) *votary-aim-time*)
            (multiple-value-call #'aim-bolt-end votary (beam-end (aim-origin votary) (aim-direction votary) votary)))
          (when (<= (decf (bolt-timer votary) dt) 0.0)
            (setf (bolt-timer votary) *votary-bolt-time*)
            (beam-bolts votary))
          (when (<= *votary-lost-time* (lost-timer votary))
            (end-hold votary))))))

(define-handler (arc-votary tick :after) (dt)
  (unless (frozen-p)
    (run-cooldowns arc-votary dt)
    (cond ((dead arc-votary) (douse-votary arc-votary))
          (T
           (cond ((charging-arc-p arc-votary) (charge-votary arc-votary dt))
                 ((holding-beam-p arc-votary) (hold-votary-beam arc-votary dt))
                 (T (rest-votary arc-votary)))
           (votary-sparks arc-votary dt)))))

(defmethod leave :after ((votary arc-votary) container)
  (douse-votary votary))

;;; As a boss (boss.lisp): the Arc Hierophant, its beam stronger and its jump longer. Its powers'
;;; attacks show its cast. And as an elite (elite.lisp).

(define-shader-entity votary-boss (boss arc-votary) ())
(define-shader-entity elite-votary (elite arc-votary) ())

(defmethod votary-beam-spell ((boss votary-boss)) 'hierophant-beam)
(defmethod chain-reach ((boss votary-boss)) 5.0)
