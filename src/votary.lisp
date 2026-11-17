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
(defparameter *votary-hand-height* 0.58
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
(defparameter *votary-light-color* (vec 1.3 1.4 1.6) "Its lamp's colour at full strength, near white.")
(defparameter *votary-light-radius* 5.0)
(defparameter *votary-ranging-strength* 0.25 "How bright the ranging line is against the beam.")
(defparameter *votary-crackle-time* 0.06 "Seconds between redrawings of the crackle between its hands.")
(defparameter *votary-burst-clearance* 2.5
  "Metres from the player's eye within which the beam's burst isn't drawn where it stops: sparks instead.")
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
   (aim-timer :initform 0.0 :accessor aim-timer)
   (beam-light :initform NIL :accessor beam-light :documentation "Its BEAM while it charges or holds.")
   (lamp :initform NIL :accessor votary-lamp)
   (beam-sound :initform NIL :accessor beam-sound :documentation "The held beam's loop.")
   (wet-spell :initform NIL :documentation "Its beam's spell, stronger, for what stands in water: made once.")
   (aim-origin :initform (vec 0 0 0) :reader aim-origin)
   (aim-direction :initform (vec 0 0 -1) :reader aim-direction)))

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
water. Returns where the beam stops."
  (multiple-value-bind (origin dir) (votary-aim votary)
    (multiple-value-bind (end victim) (beam-end origin dir votary)
      (let ((hit NIL) (wet-at NIL) (wet-body NIL))
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
                     (setf hit T)
                     (arc-bolt from to)
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
        end))))

(defun votary-light (votary strength)
  "VOTARY's beam light, made if it has none, held, at STRENGTH."
  (let ((beam (beam-light votary)))
    (unless (and beam (container beam))
      (setf beam (make-instance 'beam :start (vcopy (aim-origin votary)) :end (vcopy (aim-origin votary))
                                      :held T :color (light-color (find-spell (votary-beam-spell votary))))
            (beam-light votary) beam)
      (enter beam (container votary)))
    (setf (beam-strength beam) (float strength 0f0))
    beam))

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

(defun crackle (votary k)
  "Redraw the arc between VOTARY's hands, nearer together and fiercer as K, the charge, grows."
  (let* ((o (aim-origin votary))
         (yaw (facing votary))
         (spread (- 0.35 (* 0.22 k)))
         (rx (* spread (cos yaw)))
         (rz (* spread (sin yaw))))
    (bolt-line (- (vx o) rx) (vy o) (- (vz o) rz) (+ (vx o) rx) (vy o) (+ (vz o) rz) 3
               :roughness (+ 0.2 (* 0.2 k)) :width (+ 1.0 k) :branch (* 0.3 k) :life (* 1.3 *votary-crackle-time*))))

(defun end-hold (votary)
  "Let go of the beam: on to the recover frame."
  (setf (attack-time votary) (+ (attack-hit-time votary) (third (attack-frame-times votary)))))

(defun rest-votary (votary)
  "Neither charging nor holding: the light fades, the lamp and the loop stop."
  (let ((beam (beam-light votary)))
    (when beam
      (setf (beam-held beam) NIL
            (beam-light votary) NIL)))
  (when (votary-lamp votary)
    (remove-lamp (votary-lamp votary))
    (setf (votary-lamp votary) NIL))
  (setf (beam-sound votary) (stop-loop (beam-sound votary))))

(defun charge-votary (votary dt)
  (let ((k (min 1.0 (/ (attack-time votary) (attack-hit-time votary)))))
    (votary-aim votary)
    (votary-glow votary (* 0.8 k))
    (when (<= (decf (crackle-timer votary) dt) 0.0)
      (setf (crackle-timer votary) *votary-crackle-time*)
      (crackle votary k))
    (when (<= (decf (aim-timer votary) dt) 0.0)
      (setf (aim-timer votary) *votary-aim-time*)
      (let ((beam (votary-light votary (* *votary-ranging-strength* (+ 0.4 (random 0.6))))))
        (v<- (beam-start beam) (aim-origin votary))
        (v<- (beam-end-point beam) (beam-end (aim-origin votary) (aim-direction votary) votary))))))

(defun hold-votary-beam (votary dt)
  (let ((target (hunt-target votary)))
    (if (not (and target (target-live-p target)))
        (end-hold votary)
        (progn
          (face-target votary dt target)
          (votary-aim votary)
          (votary-glow votary 1.0)
          (setf (beam-sound votary) (hold-loop (beam-sound votary) :votary-beam (aim-origin votary)))
          (let ((beam (votary-light votary 1.0)))
            (v<- (beam-start beam) (aim-origin votary))
            (when (<= (decf (pulse-timer votary) dt) 0.0)
              (incf (pulse-timer votary) *beam-pulse*)
              (setf (aim-timer votary) *votary-aim-time*)
              (v<- (beam-end-point beam) (votary-pulse votary)))
            ;; Between strikes the light follows the aim.
            (when (<= (decf (aim-timer votary) dt) 0.0)
              (setf (aim-timer votary) *votary-aim-time*)
              (v<- (beam-end-point beam) (beam-end (aim-origin votary) (aim-direction votary) votary))))
          (when (<= *votary-lost-time* (lost-timer votary))
            (end-hold votary))))))

(define-handler (arc-votary tick :after) (dt)
  (unless (frozen-p)
    (run-cooldowns arc-votary dt)
    (cond ((charging-arc-p arc-votary) (charge-votary arc-votary dt))
          ((holding-beam-p arc-votary) (hold-votary-beam arc-votary dt))
          (T (rest-votary arc-votary)))))

(defmethod leave :after ((votary arc-votary) container)
  (rest-votary votary))

;;; As a boss (boss.lisp): the Arc Hierophant, its beam stronger and its jump longer. Its powers'
;;; attacks show its cast. And as an elite (elite.lisp).

(define-shader-entity votary-boss (boss arc-votary) ())
(define-shader-entity elite-votary (elite arc-votary) ())

(defmethod votary-beam-spell ((boss votary-boss)) 'hierophant-beam)
(defmethod chain-reach ((boss votary-boss)) 5.0)
