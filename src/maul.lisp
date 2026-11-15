(in-package #:hexmaw)

;;; The maul, held in both hands, so no shield: the slowest weapon, and the heaviest. Its blow
;;; is charged: the left button raises it (the least charge, *MAUL-MIN-CHARGE*), holding it
;;; winds it further up to *MAUL-FULL-CHARGE* for stamina, and letting go brings it down, a
;;; swing (SWING-TIME, sword.lisp) on one creature, harder the longer it was held. Its knockback
;;; has heft (PUSH-CREATURE's :HEFT): it moves the heavy too, and what it throws into a wall, a
;;; body, lava, deep water or across ice pays for it there ("Impacts", creature.lisp). A full
;;; blow always flinches (a boss only rolls), knocks a shield or a ward aside for a moment (REEL,
;;; creature.lisp), and its kills come apart easily, a skeleton's always, so the necromancer
;;; can't raise it. A blow that finds no one living pulps a corpse in its reach.
;;;
;;; The right button (the shield's action, :BLOCK) is the earthshake: the head driven into the
;;; floor, flinching everything standing round the player, behind them too, and shoving it out.
;;; No shield stops it, but nothing off the floor feels it (a hovering flyer, a leap in the air),
;;; it costs stamina and leaves the player slowed. The bash's poise (BASH-POISE) keeps it from
;;; flinching the same creature again at once.
;;;
;;; Its sprite is the sword's, drawn from its own strip (data/sprites/maul): 4 idle frames, the
;;; charge's 3 (raised, wound up, wound up trembling), the blow's 4 (falling, the impact, the
;;; impact a little lower, recovery) and the earthshake's 5 (lifted, coming over, the slam, held,
;;; recovery).

(define-fx-animation maul "sprites/maul/maul" :fps 5 :loop T)

(defparameter *maul-idle-frames* 4 "Strip frames the idle loop steps through, from the first.")
(defparameter *maul-charge-first* 4 "Strip index of the charge's first frame: raised.")
(defparameter *maul-swing-first* 7 "Strip index of the blow's first frame.")
(defparameter *maul-shake-first* 11 "Strip index of the earthshake's first frame.")
(defparameter *maul-aim* 177
  "Art pixels left from the strip's screen corner to where the head lands (the impact frame,
placed by art/maul/maul-frames.txt), which goes on the screen's middle.")

(defparameter *maul-min-charge* 0.4 "Seconds the maul takes to rise: the least charge a blow has.")
(defparameter *maul-full-charge* 1.35 "Seconds from the press to a full charge.")
(defparameter *maul-cry-delay* 0.2
  "Seconds the left button must be held before the charge's cry: a click is shorter.")
(defparameter *maul-blow-stamina* 15.0
  "Stamina every blow costs, paid as the maul is raised; with less, it isn't raised.")
(defparameter *maul-charge-stamina* 30.0
  "Stamina a second the charge costs while it grows past the least; with none, it stops growing.")
(defparameter *maul-raise-frame-time* 0.17 "Seconds the charge shows the raised frame before the wound-up one.")
(defparameter *maul-tremble-rate* 12.0 "Times a second the fully charged maul trembles from one frame to the other.")
(defparameter *maul-charge-speed* 0.6 "Fraction of a walk the player keeps while charging, with no run or jump.")

(defparameter *maul-frame-times* '(0.19 0.12 0.12 0.16)
  "Seconds each frame of the blow shows once released: falling, the impact, lower, recovery.")
(defparameter *maul-hit-frame* 1 "Blow frame it lands on, counted from 0: the impact.")
(defparameter *maul-reach* 2.2 "Metres from the player to the nearest edge of a creature's body.")
(defparameter *maul-arc* 0.6 "Radians either side of the view the blow reaches.")
(defparameter *maul-damage* '(18 24) "Damage of the least charge.")
(defparameter *maul-full-damage* '(34 44) "Damage of a full charge; between, by the charge.")
(defparameter *maul-knockback* 8.0 "Speed in m/s the least charge throws a creature, before heft.")
(defparameter *maul-full-knockback* 15.0 "Speed in m/s a full charge throws a creature, before heft.")
(defparameter *maul-pain-bonus* 10 "Percent the least charge adds to the creature's PAIN-CHANCE.")
(defparameter *maul-full-pain-bonus* 60
  "Percent a full charge adds to a boss's PAIN-CHANCE: anything else always flinches.")
(defparameter *maul-hit-stop* 0.06 "Seconds the world freezes when the least charge lands.")
(defparameter *maul-full-hit-stop* 0.12 "Seconds the world freezes when a full charge lands.")
(defparameter *maul-camera-shake* '(0.45 0.8)
  "Strength of the camera shake (KICK-CAMERA, player.lisp) when the least charge lands, and an
almost full one; a full one shakes at *MAUL-FULL-CAMERA-SHAKE*.")
(defparameter *maul-full-camera-shake* 1.0)
(defparameter *maul-reel-time* 1.2
  "Seconds a creature whose shield or ward a full blow struck reels (REEL): its guard down.")
(defparameter *maul-boss-reel-time* 0.5 "Seconds a boss's ward stays knocked aside.")
(defparameter *maul-gib-overkill* 0.1
  "A maul's killing blow tears a creature apart from this overkill, a fraction of its most (its
own if less); the undead's at any overkill.")

(defparameter *shake-frame-times* '(0.22 0.08 0.12 0.18 0.2)
  "Seconds each frame of the earthshake shows: lifted, coming over, the slam, held, recovery.")
(defparameter *shake-hit-frame* 2 "Earthshake frame it lands on, counted from 0: the slam.")
(defparameter *shake-radius* 3.0 "Metres across from the player's feet to a creature's body the earthshake reaches.")
(defparameter *shake-reach-height* 0.4
  "Metres from the player's floor within which a creature's feet must be to feel the earthshake.")
(defparameter *shake-damage* '(3 6))
(defparameter *shake-knockback* 5.0 "Speed in m/s the earthshake shoves each creature out, before heft.")
(defparameter *shake-boss-pain-bonus* 50 "Percent the earthshake adds to a boss's PAIN-CHANCE: the rest always flinch.")
(defparameter *shake-poise-time* 2.0 "Seconds after the earthshake in which it, a bash or a sweep can't flinch a creature.")
(defparameter *shake-stamina* 30.0 "Stamina an earthshake costs; with less, none.")
(defparameter *shake-speed* 0.3 "Fraction of a walk the player keeps through an earthshake.")
(defparameter *shake-hit-stop* 0.08)
(defparameter *shake-camera-shake* 0.7 "Strength of the camera shake the earthshake gives.")
(defparameter *shake-dust-radius* 1.5 "Metres out the earthshake's ring of dust puffs is (KICK-DUST, ogre.lisp).")
(defparameter *shake-dust-puffs* 8)

(defmethod swing-frame-times ((weapon (eql :maul))) *maul-frame-times*)
(defmethod swing-hit-frame ((weapon (eql :maul))) *maul-hit-frame*)
(defmethod swing-reach ((weapon (eql :maul))) *maul-reach*)
(defmethod swing-arc ((weapon (eql :maul))) *maul-arc*)
(defmethod swing-damage ((weapon (eql :maul))) *maul-damage*)
(defmethod swing-knockback ((weapon (eql :maul))) *maul-knockback*)
(defmethod swing-pain-bonus ((weapon (eql :maul))) *maul-pain-bonus*)

(defmethod bash-frame-times ((weapon (eql :maul))) *shake-frame-times*)
(defmethod bash-hit-frame ((weapon (eql :maul))) *shake-hit-frame*)
(defmethod bash-strike (player (weapon (eql :maul))) (earthshake-hit player))

;;; The charge.

(defun maul-charge (time)
  "The charge, 0 to 1, of a blow TIME seconds into its charging."
  (max 0.0 (min 1.0 (/ (- time *maul-min-charge*) (- *maul-full-charge* *maul-min-charge*)))))

(defun maul-heaving-p (player)
  "True while PLAYER charges the maul or shakes the floor with it: no run, no jump."
  (and (eq (weapon player) :maul) (or (charge-time player) (bash-time player)) T))

(defun maul-speed-scale (player)
  "Fraction of a walk PLAYER keeps for the maul in hand: slowed by its charge and its earthshake."
  (cond ((not (eq (weapon player) :maul)) 1.0)
        ((bash-time player) *shake-speed*)
        ((charge-time player) *maul-charge-speed*)
        (T 1.0)))

(defun player-maul (player)
  "The left button with the maul: start raising it, for *MAUL-BLOW-STAMINA*."
  (unless (or (swing-time player) (charge-time player) (bash-time player)
              (< (stamina player) *maul-blow-stamina*))
    (decf (stamina player) *maul-blow-stamina*)
    (setf (charge-time player) 0.0)))

(defun update-maul-charge (player dt)
  "Wind the maul's charge up while the left button is held (stamina buys it past the least), and
bring the blow down once it is let go and the maul is up. The strain's cry starts once the
button has been held *MAUL-CRY-DELAY*, and the blow cuts it off."
  (let ((time (charge-time player)))
    (when time
      (cond ((< time *maul-min-charge*)
             (setf (charge-time player) (min *maul-min-charge* (+ time dt)))
             (when (and (attack-held player) (< time *maul-cry-delay*) (<= *maul-cry-delay* (charge-time player)))
               (setf (charge-voice player) (play-sound :maul-charge))))
            ((and (attack-held player) (< time *maul-full-charge*) (< 0.0 (stamina player)))
             (let ((grow (min dt (- *maul-full-charge* time) (/ (stamina player) *maul-charge-stamina*))))
               (decf (stamina player) (* grow *maul-charge-stamina*))
               (setf (charge-time player) (+ time grow))
               (when (<= *maul-full-charge* (charge-time player))
                 (play-sound :maul-full)))))
      (when (and (not (attack-held player)) (<= *maul-min-charge* (charge-time player)))
        (setf (blow-charge player) (maul-charge (charge-time player))
              (charge-time player) NIL
              (charge-voice player) (cut-sound (charge-voice player)))
        (player-swing player)))))

;;; The blow.

(defun maul-lerp (charge least full)
  (+ least (* charge (- full least))))

(defun maul-damage (charge)
  (round (maul-lerp charge (roll *maul-damage*) (roll *maul-full-damage*))))

(defun knock-guard-aside (creature)
  "A full blow struck CREATURE's shield or ward: it reels, its guard down (REEL)."
  (let ((time (if (typep creature 'boss) *maul-boss-reel-time* *maul-reel-time*)))
    (play-sound :maul-guard-break (location creature))
    (setf (reel creature) time
          (brace creature) 0.0)
    (stop-walking creature time)))

(defmethod swing-strike (player (weapon (eql :maul)) target)
  (let* ((charge (blow-charge player))
         (full (<= 1.0 charge))
         (feet (feet player))
         (boss (typep target 'boss)))
    (play-sound :maul-hit (location target))
    (when (and full (shielded-p target feet))
      (knock-guard-aside target))
    (hurt target (maul-damage charge) :from feet :by player
                                      :pain-bonus (round (maul-lerp charge *maul-pain-bonus* *maul-full-pain-bonus*))
                                      :force-pain (and full (not boss))
                                      :gib-overkill (if (undead target) 0.0 *maul-gib-overkill*))
    (when (gibbed target)
      (play-sound :maul-crush (location target)))
    (hit-stop (maul-lerp charge *maul-hit-stop* *maul-full-hit-stop*))
    (kick-camera (if full *maul-full-camera-shake* (apply #'maul-lerp charge *maul-camera-shake*)) player)
    (push-creature target (v- (location target) feet)
                   (float (maul-lerp charge *maul-knockback* *maul-full-knockback*) 0f0)
                   :heft (not boss))
    (enchant-strike player :maul target)))

;; A blow that finds no one living comes down on a corpse in its reach, if one could be raised.
(defmethod swing-miss (player (weapon (eql :maul)))
  (let ((corpse (looked-at-creature player *maul-reach* *maul-arc*
                                    :dead T :test (lambda (c) (and (dead c) (raisable-p c))))))
    (when corpse
      (play-sound :maul-crush (location corpse))
      (tear-apart corpse :from (feet player)))))

;;; The earthshake.

(defun player-earthshake (player)
  (when (and (weapon-ready-p player) (not (attacking-p player)) (<= *shake-stamina* (stamina player)))
    (decf (stamina player) *shake-stamina*)
    (play-sound (weapon-sound :maul :swing))
    (setf (bash-time player) 0.0
          (bash-pending player) T)))

(defun shaken-p (player creature)
  "True if CREATURE, alive, stands on the floor PLAYER shakes, within its reach and with no wall between."
  (let* ((feet (feet player))
         (loc (location creature))
         (dx (- (vx loc) (vx feet)))
         (dz (- (vz loc) (vz feet))))
    (and (not (dead creature))
         (< (abs (- (vy loc) (vy feet))) *shake-reach-height*)
         (< (sqrt (+ (* dx dx) (* dz dz))) (+ *shake-radius* (body-radius creature)))
         (clear-path-p feet loc 0.3))))

(defun earthshake-hit (player)
  "The maul strikes the floor: everything standing within its reach flinches, unless poised (a boss
only rolls), and is shoved out."
  (let ((feet (feet player)))
    (play-sound :earthshake feet)
    (kick-dust feet *shake-dust-radius* *shake-dust-puffs* (container player))
    (hit-stop *shake-hit-stop*)
    (kick-camera *shake-camera-shake* player)
    (loop for c across *creatures*
          when (shaken-p player c)
            do (let ((poised (< 0.0 (bash-poise c)))
                     (boss (typep c 'boss)))
                 (setf (bash-poise c) (max (bash-poise c) *shake-poise-time*))
                 (hurt c (roll *shake-damage*) :from feet :by player
                                               :pain-bonus (cond (poised -100) (boss *shake-boss-pain-bonus*) (T 0))
                                               :force-pain (not (or poised boss)))
                 (push-creature c (v- (location c) feet)
                                (float (* *shake-knockback* (if poised *poised-bash-knockback* 1.0)) 0f0)
                                :heft (not boss))))))

;;; The sprite.

(define-shader-entity maul (sword)
  ((animation :initform (find-fx-animation 'maul))))

(defmethod held-weapon ((maul maul)) :maul)
(defmethod idle-frames ((maul maul)) *maul-idle-frames*)
(defmethod swing-first ((maul maul)) *maul-swing-first*)
(defmethod weapon-aim ((maul maul)) *maul-aim*)

(defmethod weapon-frame ((maul maul) player)
  (let ((shake (and (bash-time player) (frame-at (bash-time player) *shake-frame-times*)))
        (charge (charge-time player)))
    (cond (shake (+ *maul-shake-first* shake))
          ((null charge) (call-next-method))
          ((< charge *maul-raise-frame-time*) *maul-charge-first*)
          ((< charge *maul-full-charge*) (+ 1 *maul-charge-first*))
          ;; Full: trembling from one wound-up frame to the other.
          (T (+ 1 *maul-charge-first* (mod (floor (* (age maul) *maul-tremble-rate*)) 2))))))

(defun add-maul (container)
  (enter (make-instance 'maul) container))
