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
(defparameter *votary-hold* 2.0 "Seconds it holds the beam at most.")
(defparameter *votary-turn* 2.5 "Radians a second it turns, walking or charging: a deliberate turner.")
(defparameter *votary-beam-turn* 0.9 "Radians a second it turns after its target while it holds the beam.")
(defparameter *votary-pain-bonus* 20 "Percent added to its pain chance while it holds the beam.")
(defparameter *votary-lost-time* 0.75
  "Seconds of pulses striking nothing hostile after which it lets go of the beam and recovers.")
(defparameter *arc-floor-reach* 3.5
  "Metres round a body its beam strikes that the floor is electrified: whoever else stands there is struck.")
(defparameter *arc-floor-scale* 0.5 "How hard the electrified floor strikes, against the beam.")
(defparameter *votary-floor-bolts* 4 "Bolts drawn over the electrified floor at each redrawing of the beam.")
(defparameter *votary-floor-flash* (vec 1.6 1.45 0.75)
  "The flash on the electrified floor at its brightest: a lamp that jumps to a bolt's foot each redrawing.")
(defparameter *votary-floor-flash-radius* 2.2)
(defparameter *votary-water-bolts* 5 "Bolts drawn over the electrified water at each redrawing of the beam.")
(defparameter *votary-water-flash-radius* 3.0 "Reach of the flash that jumps over the electrified water.")
(defparameter *arc-water-reach* 6.0 "Metres across water a beam runs from what it strikes in it.")
(defparameter *arc-water-scale* 1.5 "How much harder a beam strikes what stands in water.")
(defparameter *arc-block-stamina* 12.0
  "Stamina a pulse costs the player's raised shield: 48 a second against a regen of 8, so a full bar
lasts about one hold and less doesn't.")
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
;; Static recoil (from level 3 of a run, `:static-recoil' in its abilities): the damage it takes is
;; stored, and full, it goes dark for a beat, bursts in a shock nova and blinks away along a bolt.
(defparameter *recoil-charge* 18.0
  "Damage it stores before its static recoil goes off: a sword blow (10 to 16) leaves it part dark, the next sets it off.")
(defparameter *recoil-bleed* 1.0 "Damage a second its stored charge loses.")
(defparameter *recoil-beat* 0.5 "Seconds of darkness and silence between the charge filling and the burst.")
(defparameter *recoil-cooldown* 14.0 "Seconds after a static recoil before it stores charge again.")
(defparameter *recoil-blink* '(6.0 9.0) "Metres it blinks away after the burst, to a spot in sight of its target.")
(defparameter *recoil-dim* 0.92 "How much of its lamp the full charge puts out.")
(defparameter *recoil-tint* (vec 0.03 0.03 0.07 0.6)
  "What its sprite darkens toward as the charge fills, and how far at full (W).")
(defparameter *recoil-motes* 36.0 "Sparks a second drawn in toward its chest at full charge.")
(defparameter *recoil-ring* '(1.0 2.2) "Metres from it that the drawn-in sparks start.")
(defparameter *recoil-flash* (vec 4.0 3.8 2.6) "The burst's flash.")

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

;; The static recoil's burst: everything round it, its allies too.
(define-spell static-recoil (:delivery :nova :nova-radius 4.0 :title "Static Recoil")
  (:damage :magnitude '(6 9) :element :shock)
  (:knockback :magnitude '(8 8)))

(define-spell hierophant-recoil (:delivery :nova :nova-radius 5.5 :title "Static Recoil")
  (:damage :magnitude '(8 12) :element :shock)
  (:knockback :magnitude '(9 9)))

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
   (floor-point :initform (vec 0 0 0) :reader floor-point
                :documentation "Where the floor under what the beam struck is, while FLOOR-LIVE.")
   (floor-live :initform NIL :accessor floor-live
               :documentation "True while the beam strikes a body: the floor round it is electrified.")
   (floor-spell :initform NIL :documentation "Its beam's spell, weaker, for the floor: made once.")
   (spark-at :initform (vec 0 0 0) :reader spark-at :documentation "A point for the floor's sparks, reused.")
   (floor-lamp :initform NIL :accessor floor-lamp
               :documentation "The flash on its electrified floor, while its beam electrifies one.")
   (water-point :initform (vec 0 0 0) :reader water-point
                :documentation "Where its beam reached water, on the surface, while WATER-LIVE.")
   (water-live :initform NIL :accessor water-live
               :documentation "True while its beam reaches water: the water round there is electrified.")
   (water-bodies :initform () :accessor water-bodies :documentation "What the water struck at the last pulse.")
   (water-lamp :initform NIL :accessor water-lamp :documentation "The flash on its electrified water.")
   (static-charge :initform 0.0 :accessor static-charge
                  :documentation "Damage it has stored toward its static recoil (STORE-STATIC).")
   (recoil :initform 0.0 :accessor recoil
           :documentation "Seconds left of the dark beat before its static recoil goes off, or 0.")
   (whine-sound :initform NIL :accessor whine-sound :documentation "The stored charge's whine.")
   (mote-timer :initform 0.0 :accessor mote-timer)))

(define-creature-sounds arc-votary
  :alert :votary-alert :pain :votary-pain :death :votary-death :windup :votary-charge :step :step-light)

;; Killed by a player who doesn't know shock, it drops the shock glyph (pickups.lisp).
(defmethod taught-effect ((votary arc-votary)) :shock)

(defgeneric votary-beam-spell (votary)
  (:documentation "The name of the spell VOTARY's beam strikes with.")
  (:method ((votary arc-votary)) 'arc-beam))

(defgeneric floor-reach (votary)
  (:documentation "Metres round what VOTARY's beam strikes that the floor is electrified.")
  (:method ((votary arc-votary)) *arc-floor-reach*))

(defun floor-spell (votary)
  (or (slot-value votary 'floor-spell)
      (setf (slot-value votary 'floor-spell)
            (scaled-spell (find-spell (votary-beam-spell votary)) *arc-floor-scale*))))

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

(defclass floor-pulse (beam-pulse) ()
  (:documentation "A strike of the floor a votary's beam electrifies: it comes up from below, so no
shield meets it."))

(defmethod effect-unblockable-p ((source floor-pulse)) T)

(defun floor-strike (votary victim)
  "VOTARY's beam struck VICTIM: electrify the floor under it out to FLOOR-REACH, striking with
FLOOR-SPELL every other live body standing on that floor there (feet within 0.4 m of it, so a jump
clears it; not in water, which WATER-STRIKE has; not VOTARY), in a clear line from the floor under
VICTIM. True if it struck anything hostile."
  (let* ((f (body-feet victim))
         (fy (or (and *nav-grid* (nav-floor-at (vx f) (+ (vy f) 0.3) (vz f))) (vy f)))
         (c (floor-point votary))
         (reach (floor-reach votary))
         (spell (floor-spell votary))
         (hostile NIL))
    (setf (vx c) (vx f) (vy c) fy (vz c) (vz f)
          (floor-live votary) T)
    (let ((from (vec (vx c) (+ fy 0.3) (vz c))))
      (dolist (body (live-bodies))
        (unless (or (eq body victim) (eq body votary) (in-water-p body))
          (let ((feet (body-feet body)))
            (when (and (< (abs (- (vy feet) fy)) 0.4)
                       (< (+ (expt (- (vx feet) (vx c)) 2) (expt (- (vz feet) (vz c)) 2))
                          (expt (+ reach (body-radius body)) 2))
                       (clear-line-p from (vec (vx feet) (+ fy 0.3) (vz feet))))
              (let ((source (make-instance 'floor-pulse :spell spell :caster votary
                                                        :origin (vec (vx feet) fy (vz feet)))))
                (dolist (effect (spell-effects spell))
                  (when (target-effect-p effect)
                    (apply-effect (effect-kind effect) effect body source))))
              (when (hostile-p votary body) (setf hostile T)))))))
    hostile))

(defun arc-bolt (from to &key (life 0.12))
  "Draw a jagged arc of lightning between points FROM and TO."
  (bolt-line (vx from) (vy from) (vz from) (vx to) (vy to) (vz to) 3
             :roughness 0.18 :width 2.0 :branch 0.15 :life life))

(defun water-strike (votary point struck)
  "A pulse of VOTARY's beam reached water at POINT: strike every other body in water within
*ARC-WATER-REACH* of it, in a clear line, with an arc over the surface to each. STRUCK is the body
already struck there, or NIL. True if it struck anything hostile."
  (let* ((hostile NIL)
         (surface (water-surface-at (vx point) (vy point) (vz point)))
         (from (vec (vx point) (+ surface 0.1) (vz point)))
         (c (water-point votary)))
    (setf (vx c) (vx point) (vy c) surface (vz c) (vz point)
          (water-live votary) T)
    (dolist (body (live-bodies))
      (unless (or (eq body votary) (eq body struck) (not (in-water-p body)))
        (let ((feet (body-feet body)))
          (when (and (< (+ (expt (- (vx feet) (vx point)) 2) (expt (- (vz feet) (vz point)) 2))
                        (expt *arc-water-reach* 2))
                     (< (abs (- (vy feet) (vy point))) 2.0)
                     (clear-line-p from (vec (vx feet) (+ (vy feet) 0.3) (vz feet))))
            (let ((to (vec (vx feet) (+ (vy feet) 0.3) (vz feet))))
              ;; Its arc is redrawn with the beam (WATER-BOLTS).
              (push body (water-bodies votary))
              (arc-strike votary body from to :wet T)
              (when (hostile-p votary body) (setf hostile T)))))))
    (when hostile
      (play-sound :arc-zap point))
    hostile))

(defun water-surface-at (x y z)
  "The height of the surface of the water (deep or shallows) at or about X Y Z, or Y if none is near."
  (loop for dy in '(0.05 -0.05 -0.3 0.3 -0.8)
        for liquid = (liquid-at x (+ y dy) z)
        when (and liquid (member (liquid-kind liquid) '(:water :shallows)))
          return (aref (liquid-bounds liquid) 4)
        finally (return y)))

(defun water-beyond-p (end direction)
  "True if a beam that stopped at END along DIRECTION stopped on the surface of water."
  (let ((liquid (liquid-at (+ (vx end) (* 1.5 *beam-step* (vx direction)))
                           (+ (vy end) (* 1.5 *beam-step* (vy direction)))
                           (+ (vz end) (* 1.5 *beam-step* (vz direction))))))
    (and liquid (member (liquid-kind liquid) '(:water :shallows)) T)))

(defun votary-pulse (votary)
  "One strike of VOTARY's held beam: what it reaches along its aim, its own allies too, the floor
round that, and the water. Returns where the beam stops and the body it reached there, or NIL."
  (multiple-value-bind (origin dir) (votary-aim votary)
    (multiple-value-bind (end victim) (beam-end origin dir votary)
      (let ((hit NIL) (wet-at NIL) (wet-body NIL))
        (setf (floor-live votary) NIL
              (water-live votary) NIL
              (water-bodies votary) ())
        ;; Whatever it reaches takes it, an ally too: a body in the way blocks it. The floor round
        ;; that body is electrified.
        (when victim
          (let ((wet (in-water-p victim)))
            (arc-strike votary victim origin end :wet wet)
            (when (hostile-p votary victim) (setf hit T))
            (when wet (setf wet-at (body-feet victim) wet-body victim))
            (when (floor-strike votary victim) (setf hit T))
            (when (< (random 1.0) 0.5)
              (play-sound :arc-zap (floor-point votary)))))
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
    ;; Moved, it finds its room again (a lamp with no source is placed once, update-lamps).
    (unless (v= (location lamp) (aim-origin votary))
      (v<- (location lamp) (aim-origin votary))
      (setf (located lamp) NIL))
    ;; Its stored charge drains its light (static recoil).
    (setf k (* k (- 1.0 (* *recoil-dim* (recoil-k votary)))))
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

(defun last-stretch (x1 y1 z1 &rest bolt-args)
  "Carry a bolt that stopped short of the player's eye, at X1 Y1 Z1, the rest of the way into their
view: a short stretch, nearly straight (its jitter scales with its length, and so close to the camera
any more crosses the view), to the bottom of the view where their chest is."
  (let* ((eye (location (camera (scene +main+))))
         (dx (- x1 (vx eye))) (dy (- y1 (vy eye))) (dz (- z1 (vz eye)))
         (len (max 1f-4 (sqrt (+ (* dx dx) (* dy dy) (* dz dz))))))
    (destructuring-bind (out down) *votary-bolt-chest*
      (apply #'bolt-line x1 y1 z1
             (+ (vx eye) (* out (/ dx len))) (- (+ (vy eye) (* out (/ dy len))) down) (+ (vz eye) (* out (/ dz len)))
             2 bolt-args))))

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
      (if (floor-live votary)
          (floor-bolts votary life)
          (douse-floor votary))
      (if (water-live votary)
          (water-bolts votary life)
          (douse-water votary)))))

(defun water-bolts (votary life)
  "Redraw the electrified water round where VOTARY's beam reached it, as its floor is: bolts skating
over the surface at random spots out to *ARC-WATER-REACH*, thinning toward it, only where there is
water under them, none through a wall from the middle or by the player's eye, a few spiking up off it,
the flash jumping between them; and an arc over the surface to each body the water strikes. Sparks go
out in water, so there are none."
  (let* ((c (water-point votary))
         (cx (vx c)) (cy (+ (vy c) 0.02)) (cz (vz c))
         (reach *arc-water-reach*)
         (eye (location (camera (scene +main+))))
         (flashed NIL))
    (dotimes (i *votary-water-bolts*)
      (let* ((a (random #.(float (* 2 pi) 0f0)))
             (d (* reach (expt (random 1.0) 0.75)))
             (x (+ cx (* d (cos a))))
             (z (+ cz (* d (sin a))))
             (water (liquid-at x (- cy 0.07) z)))
        (when (and water (member (liquid-kind water) '(:water :shallows))
                   (<= 0.81 (+ (expt (- x (vx eye)) 2) (expt (- z (vz eye)) 2)))
                   (or (< d 0.5) (clear-line-p (vec cx (+ cy 0.15) cz) (vec x (+ cy 0.15) z))))
          (unless flashed
            (flash-lamp votary 'water-lamp x cy z *votary-water-flash-radius*)
            (setf flashed T))
          (let ((b (+ a (- (random 2.4) 1.2)))
                (len (+ 0.5 (random 0.9))))
            (bolt-line x cy z (+ x (* len (cos b))) cy (+ z (* len (sin b))) 3
                       :roughness 0.3 :width 1.5 :white 0.3 :branch 0.3 :life life))
          (when (< (random 1.0) 0.3)
            (bolt-line x cy z (+ x (- (random 0.3) 0.15)) (+ cy 0.15 (random 0.3)) (+ z (- (random 0.3) 0.15)) 2
                       :roughness 0.35 :width 1.5 :white 0.4 :life life)))))
    (dolist (body (water-bodies votary))
      (when (and (not (typep body 'player)) (target-live-p body))
        (let ((feet (body-feet body))
              (a (random #.(float (* 2 pi) 0f0)))
              (d (random 0.8)))
          (bolt-line (+ cx (* d (cos a))) cy (+ cz (* d (sin a)))
                     (vx feet) (+ (max cy (vy feet)) 0.2) (vz feet) 3
                     :roughness 0.25 :width 1.5 :white 0.3 :branch 0.2 :life life))))))

(defun floor-bolts (votary life)
  "Redraw the electrified floor round what VOTARY's beam strikes, as the shock nova's bolts are drawn:
*VOTARY-FLOOR-BOLTS* bolts, most rising off the floor and the rest crawling over it, at random spots
thinning out toward FLOOR-REACH so it has no drawn edge, none through a wall from the middle or right at
the player's eye; now and then a spray of sparks."
  (let* ((c (floor-point votary))
         (cx (vx c)) (cy (+ (vy c) 0.03)) (cz (vz c))
         (reach (floor-reach votary))
         (eye (location (camera (scene +main+)))))
    (dotimes (i *votary-floor-bolts*)
      (let* ((a (random #.(float (* 2 pi) 0f0)))
             (d (* reach (expt (random 1.0) 0.75)))
             (x (+ cx (* d (cos a))))
             (z (+ cz (* d (sin a)))))
        (unless (or (< (+ (expt (- x (vx eye)) 2) (expt (- z (vz eye)) 2)) 0.81)
                    (solid-at x (+ cy 0.2) z)
                    (and (< 0.5 d)
                         (not (clear-line-p (vec cx (+ cy 0.2) cz) (vec x (+ cy 0.2) z)))))
          ;; Its foot throws a spark or two, so it stands in the room and not on the screen, and the
          ;; flash jumps there.
          (let ((at (spark-at votary)))
            (setf (vx at) x (vy at) (+ cy 0.02) (vz at) z)
            (spray-sparks at NIL (+ 1 (random 2)) :ramp :shock :speed '(0.6 1.8)))
          (when (= i 0)
            (flash-floor votary x cy z))
          (if (< (random 1.0) 0.65)
              (bolt-line x cy z (+ x (- (random 0.5) 0.25)) (+ cy 0.25 (random 0.75)) (+ z (- (random 0.5) 0.25)) 3
                         :roughness 0.35 :width 1.5 :white 0.3 :branch 0.3 :life life)
              (let ((b (+ a (- (random 1.6) 0.8)))
                    (len (+ 0.4 (random 0.8))))
                (bolt-line x cy z (+ x (* len (cos b))) cy (+ z (* len (sin b))) 3
                           :roughness 0.3 :width 1.5 :white 0.2 :branch 0.2 :life life))))))
    (when (< (random 1.0) 0.3)
      (let* ((at (spark-at votary))
             (a (random #.(float (* 2 pi) 0f0)))
             (d (* reach (random 0.7))))
        (setf (vx at) (+ cx (* d (cos a))) (vy at) (+ cy 0.05) (vz at) (+ cz (* d (sin a))))
        (spray-sparks at NIL 3 :ramp :shock :speed '(1.0 2.5))))))

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
  "Stop the held beam's loop, and put out the flash on its floor."
  (setf (beam-sound votary) (stop-loop (beam-sound votary)))
  (douse-floor votary)
  (douse-water votary))

(defun douse-floor (votary)
  (setf (floor-live votary) NIL)
  (when (floor-lamp votary)
    (remove-lamp (floor-lamp votary))
    (setf (floor-lamp votary) NIL)))

(defun flash-floor (votary x y z)
  "Light the flash on VOTARY's electrified floor at X Y Z, the foot of a bolt, at a flickering strength."
  (flash-lamp votary 'floor-lamp x y z *votary-floor-flash-radius*))

(defun douse-water (votary)
  (setf (water-live votary) NIL
        (water-bodies votary) ())
  (when (water-lamp votary)
    (remove-lamp (water-lamp votary))
    (setf (water-lamp votary) NIL)))

(defun flash-lamp (votary slot x y z radius)
  "Light the flash VOTARY keeps in SLOT (FLOOR-LAMP or WATER-LAMP) at X Y Z, the foot of a bolt, at a
flickering strength: made if it has none, and placed in its room again since it moved."
  (let ((lamp (slot-value votary slot))
        (k (+ 0.5 (random 0.7))))
    (unless (and lamp (find lamp *lamps*))
      (setf lamp (add-lamp (vec x y z) *votary-floor-flash* radius)
            (slot-value votary slot) lamp))
    (let ((at (location lamp))
          (color (color lamp)))
      (setf (vx at) x (vy at) (+ y 0.3) (vz at) z
            (located lamp) NIL
            (vx color) (* k (vx *votary-floor-flash*))
            (vy color) (* k (vy *votary-floor-flash*))
            (vz color) (* k (vz *votary-floor-flash*))))))

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
         (rz (/ fx fl))
         ;; Its stored charge drains its idle lightning away (static recoil).
         (live (- 1.0 (recoil-k votary))))
    (unless (or (charging-arc-p votary) (holding-beam-p votary))
      (when (< (random 1.0) (* live *votary-hand-arc-chance*))
        (hand-arc votary 1.0 :roughness 0.25 :branch 0.3 :white 0.3 :life (* 1.3 *votary-arc-time*))))
    ;; Five rod tips in a fan, 0.18 m either side of the head, 0.97 to 0.91 of its height; the head
    ;; leans 8 cm toward its face, which shows only from the side.
    (flet ((tip (i)
             (let ((a (- (* 0.5 i) 1.0)))
               (values (+ (vx loc) (* rx 0.18 s a) (* 0.08 s (sin yaw)))
                       (+ (vy loc) (* h (- 0.97 (* 0.06 a a))))
                       (- (+ (vz loc) (* rz 0.18 s a)) (* 0.08 s (cos yaw)))))))
      (dotimes (i 4)
        (when (< (random 1.0) (* live *votary-crown-arc-chance*))
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
      (when (< (recoil-k votary) (random 1.0))
        (crackle votary k)))
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

;;; Static recoil (from level 3 of a run): what strikes it is stored as charge, which drains its own
;;; light, *RECOIL-CHARGE* of damage filling it. As it fills it goes dark: its lamp dims toward nothing,
;;; its idle lightning dies away, its sprite darkens, sparks stream in from round it into its chest and
;;; a whine rises; in a lit room, the one figure going out. Full, it stands *RECOIL-BEAT* dark and
;;; silent, unflinching, then bursts in a shock nova round itself (its allies too) and blinks away along
;;; a bolt to a spot in sight of its target.

(defgeneric recoil-spell (votary)
  (:documentation "The name of the nova VOTARY's static recoil bursts in.")
  (:method ((votary arc-votary)) 'static-recoil))

(defun recoil-ready-p (votary)
  "True if VOTARY stores the damage it takes toward its static recoil."
  (and (not (dead votary))
       (not (dormant-p votary))
       (<= (recoil votary) 0.0)
       (<= (or (getf (cooldowns votary) :static-recoil) 0.0) 0.0)
       (level-ability-p :static-recoil)))

(defun recoil-k (votary)
  "How full VOTARY's stored charge is, 0 to 1; 1 through the dark beat."
  (if (< 0.0 (recoil votary))
      1.0
      (min 1.0 (/ (static-charge votary) *recoil-charge*))))

(defmethod harmed :after ((votary arc-votary) amount by)
  (declare (ignore by))
  (when (recoil-ready-p votary)
    (when (<= *recoil-charge* (incf (static-charge votary) amount))
      (begin-recoil votary))))

(defun begin-recoil (votary)
  "VOTARY's charge is full: it lets go of whatever it was doing and stands dark for the beat."
  (setf (static-charge votary) *recoil-charge*
        (recoil votary) *recoil-beat*
        (stagger votary) 0.0)
  (stop-walking votary (+ *recoil-beat* 0.2))
  (release-beam votary)
  (setf (whine-sound votary) (stop-loop (whine-sound votary))))

;; Through the dark beat a blow doesn't make it flinch.
(defmethod react-to-hit :after ((votary arc-votary))
  (when (< 0.0 (recoil votary))
    (setf (stagger votary) 0.0)))

;; Through the beat it stands with its hands brought together, the knot between them gone out.
(defmethod show-own-pose ((votary arc-votary) squash)
  (when (and (< 0.0 (recoil votary)) (not (dead votary)))
    (show-view-frame votary 'votary-cast 1 squash)
    T))

(defun votary-chest (votary)
  (let ((loc (location votary)))
    (vec (vx loc) (+ (vy loc) (* 0.55 (sprite-height votary))) (vz loc))))

(defun recoil-spot (votary)
  "Where VOTARY blinks after its burst: a free spot *RECOIL-BLINK* metres off, away from its target
first, in sight of it, with a clear line from where it stands; or NIL."
  (let* ((loc (location votary))
         (target (hunt-target votary))
         (feet (and target (body-feet target)))
         (away (if feet (+ (bearing feet loc) 0.0) (random (* 2 pi)))))
    (loop for i in '(0 1 -1 2 -2 3 -3 4)
          for yaw = (+ away (* i (/ pi 4)) (- (random 0.4) 0.2))
          for d = (random-between *recoil-blink*)
          for p = (vec (+ (vx loc) (* d (sin yaw))) (vy loc) (- (vz loc) (* d (cos yaw))))
          for to = (free-spot p (body-radius votary) (sprite-height votary)
                              :search 1 :ignore votary :sight-of feet :from loc)
          when (and to
                    (clear-path-p loc to 1.2)
                    (< (abs (- (vy to) (vy loc))) 1.0)
                    (or (null feet)
                        (< (+ (keep-away votary) (body-radius votary))
                           (sqrt (+ (expt (- (vx to) (vx feet)) 2) (expt (- (vz to) (vz feet)) 2))))))
            return to)))

(defun discharge-static (votary)
  "The beat is over: VOTARY bursts in its nova, a flash and a kick of the view, and blinks away along
a bolt (not a boss, which keeps to its place in the arena)."
  (let ((chest (votary-chest votary))
        (container (container votary)))
    (setf (static-charge votary) 0.0
          (recoil votary) 0.0
          (getf (cooldowns votary) :static-recoil) (* *recoil-cooldown* (depth-scale :cooldown)))
    (cast-spell (find-spell (recoil-spell votary)) chest (vec 0 0 -1) container :caster votary)
    (attach-glow (spawn-fx 'shock-burst chest container) *recoil-flash* 8.0)
    (spray-sparks chest NIL 24 :ramp :shock :speed '(2.0 6.0))
    (kick-camera-from chest 0.7 12.0)
    (let ((to (and (not (typep votary 'boss)) (recoil-spot votary))))
      (when to
        (teleport-actor votary to :yaw (and (hunt-target votary) (bearing to (body-feet (hunt-target votary)))))
        (let ((there (votary-chest votary)))
          (bolt-line (vx chest) (vy chest) (vz chest) (vx there) (vy there) (vz there) 6
                     :roughness 0.12 :width 4.0 :white 0.7 :branch 0.3 :life 0.3)
          (bolt-line (vx chest) (vy chest) (vz chest) (vx there) (vy there) (vz there) 5
                     :roughness 0.2 :width 1.5 :white 0.3 :branch 0.4 :drop 0.2 :life 0.25)
          (attach-glow (spawn-fx 'shock-burst there container) *votary-floor-flash* 5.0)
          (spray-sparks there NIL 10 :ramp :shock :speed '(1.0 4.0))
          (play-sound :arc-zap there))))
    (setf (alert votary) (max (alert votary) (alert-time)))))

(defun update-recoil (votary dt)
  "Run VOTARY's stored charge: the dark beat and its burst, the charge bleeding away otherwise, and
what shows of it: the sparks drawn in, and the whine."
  (let ((k (recoil-k votary))
        (beat (< 0.0 (recoil votary))))
    (cond (beat
           (setf (idle-timer votary) (max (idle-timer votary) (+ (recoil votary) 0.2)))
           (when (<= (decf (recoil votary) dt) 0.0)
             (discharge-static votary)))
          ((< 0.0 (static-charge votary))
           (setf (static-charge votary) (max 0.0 (- (static-charge votary) (* *recoil-bleed* dt))))
           ;; Sparks stream in from round it into its chest, more as it fills.
           (decf (mote-timer votary) (* dt k))
           (loop while (<= (mote-timer votary) 0.0)
                 do (incf (mote-timer votary) (/ 1.0 *recoil-motes*))
                    (let* ((loc (location votary))
                           (a (random (* 2 pi)))
                           (r (+ (first *recoil-ring*) (random (- (second *recoil-ring*) (first *recoil-ring*)))))
                           (from (vec (+ (vx loc) (* r (cos a)))
                                      (+ (vy loc) 0.2 (random (* 0.8 (sprite-height votary))))
                                      (+ (vz loc) (* r (sin a)))))
                           (chest (votary-chest votary)))
                      (spray-sparks from (v- chest from) 1 :ramp :shock :speed '(3.5 4.5) :spread 0.05)))))
    (setf (whine-sound votary)
          (hold-loop (whine-sound votary) (and (not beat) (< 0.1 k) :votary-whine) (location votary)
                     (+ 0.3 (* 0.7 k))))))

(defun darken-votary (votary)
  "Darken VOTARY's sprite as its charge fills, unless its hit flash is stronger."
  (let ((k (recoil-k votary)))
    (when (and (< 0.0 k) (not (dead votary)))
      (let ((tint (tint votary))
            (w (* (vw *recoil-tint*) (if (< 0.0 (recoil votary)) 1.3 k))))
        (when (< (vw tint) w)
          (setf (vx tint) (vx *recoil-tint*) (vy tint) (vy *recoil-tint*) (vz tint) (vz *recoil-tint*)
                (vw tint) w))))))

(define-handler (arc-votary tick :after) (dt)
  (unless (frozen-p)
    (run-cooldowns arc-votary dt)
    (cond ((dead arc-votary)
           (setf (static-charge arc-votary) 0.0 (recoil arc-votary) 0.0
                 (whine-sound arc-votary) (stop-loop (whine-sound arc-votary)))
           (douse-votary arc-votary))
          (T
           (update-recoil arc-votary dt)
           (cond ((< 0.0 (recoil arc-votary))
                  (votary-aim arc-votary)
                  (votary-glow arc-votary 0.0))
                 ((charging-arc-p arc-votary) (charge-votary arc-votary dt))
                 ((holding-beam-p arc-votary) (hold-votary-beam arc-votary dt))
                 (T (rest-votary arc-votary)))
           (unless (< 0.0 (recoil arc-votary))
             (votary-sparks arc-votary dt)))))
  (darken-votary arc-votary))

(defmethod leave :after ((votary arc-votary) container)
  (setf (whine-sound votary) (stop-loop (whine-sound votary)))
  (douse-votary votary))

;;; As a boss (boss.lisp): the Arc Hierophant, its beam stronger and its jump longer. Its powers'
;;; attacks show its cast. And as an elite (elite.lisp).

(define-shader-entity votary-boss (boss arc-votary) ())
(define-shader-entity elite-votary (elite arc-votary) ())

(defmethod votary-beam-spell ((boss votary-boss)) 'hierophant-beam)
(defmethod floor-reach ((boss votary-boss)) 5.0)
(defmethod recoil-spell ((boss votary-boss)) 'hierophant-recoil)
