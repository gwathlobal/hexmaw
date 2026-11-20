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

;;; Its strip: 4 idle frames, the charge's 3 (raised, wound up, wound up a pixel aside), the
;;; blow's 4 and the earthshake's 5. It is placed by its aim, where the head lands (the impact
;;; frame, placed by art/maul/maul-frames.txt), which goes on the screen's middle.
(define-weapon :maul
  :title "Maul" :icon 11 :strip maul :frames (:idle 4 :charge 4 :swing 7 :alternate 11) :aim 177
  :loot T :loot-strip loot-maul :forge-noun "Maul"
  :sounds (:draw :draw-maul)
  ;; The blow: it rises for 0.4 s (the least charge), whatever the button does, and while held winds
  ;; on to a full charge 1.35 s from the press, for 30 stamina a second past the least. The cry starts
  ;; once the button has been held 0.2 s. Once released: falling, the impact (where it lands),
  ;; lower, recovery. Each number given twice runs from the least charge's to the full one's.
  :swing (charged-blow :name :maul :frame-times (0.19 0.12 0.12 0.16) :hit-frame 1
                       :reach 2.2 :arc 0.6 :damage (18 24) :full-damage (34 44)
                       :knockback 8.0 :full-knockback 15.0 :pain-bonus 10 :full-pain-bonus 60
                       :hit-stop (0.06 0.12) :sparks (6 26)
                       :camera-shake (0.45 0.8) :full-camera-shake 1.0 :gib-overkill 0.1
                       :stamina 15.0 :sound :maul-swing :verb "blow"
                       :min-charge 0.4 :full-charge 1.35 :cry-delay 0.2 :charge-stamina 30.0
                       :charge-speed 0.6 :raise-frame-time 0.17 :tremble-rate 12.0
                       ;; (:CHARGE least full): the least charge's, then the full one's.
                       :wall (:sparks (:charge 8 20) :grit (:charge 8 16) :speed (:charge (3.0 6.0) (3.0 9.0))
                              :spread 1.0 :sound :maul-hit-stone :wood-sound :blade-hit-wood
                              :camera (:charge 0.2 0.4) :hit-stop (:charge 0.02 0.04))
                       ;; The head's top, strip frame 8.
                       :tip (:maul 111 117))
  ;; The earthshake: lifted, coming over, the slam (where it lands), held, recovery. It reaches 3 m
  ;; across from the feet to a body, feet within 0.4 m of the player's floor.
  :alternate (earthshake :name :shake :frame-times (0.22 0.08 0.12 0.18 0.2) :hit-frame 2
                         :reach 3.0 :reach-height 0.4 :damage (3 6) :knockback 5.0
                         :boss-pain-bonus 50 :poise-time 2.0 :stamina 30.0 :speed 0.3 :sound :maul-swing
                         :hit-stop 0.08 :camera-shake 0.7 :dust-radius 1.5 :dust-puffs 8 :spark-reach 0.9))

(defparameter *maul-reel-time* 1.2
  "Seconds a creature whose shield or ward a full blow struck reels (REEL): its guard down.")
(defparameter *maul-boss-reel-time* 0.5 "Seconds a boss's ward stays knocked aside.")

;;; The charge (a CHARGED-BLOW's, weapons.lisp).

(defun blow-charge-at (blow time)
  "The charge, 0 to 1, of BLOW (a charged blow) TIME seconds into its charging."
  (let ((least (blow-min-charge blow)))
    (max 0.0 (min 1.0 (/ (- time least) (- (blow-full-charge blow) least))))))

;; The left button raises it, for its STAMINA; with less, it isn't raised.
(defmethod start-blow ((blow charged-blow) player)
  (let ((cost (blow-stamina blow)))
    (unless (or (swing-time player) (charge-time player) (bash-time player)
                (< (stamina player) cost))
      (decf (stamina player) cost)
      (setf (charge-time player) 0.0))))

(defun update-blow-charge (player dt)
  "Wind the charge of the weapon in hand up while the left button is held (stamina buys it past the
least), and bring the blow down once it is let go and the weapon is up. The strain's cry starts
once the button has been held its CRY-DELAY, and the blow cuts it off."
  (let ((time (charge-time player))
        (blow (swing-blow (weapon player))))
    (when (and time (typep blow 'charged-blow))
      (let ((least (blow-min-charge blow))
            (full (blow-full-charge blow))
            (cry (blow-cry-delay blow))
            (rate (blow-charge-stamina blow)))
        (cond ((< time least)
               (setf (charge-time player) (min least (+ time dt)))
               (when (and (attack-held player) (< time cry) (<= cry (charge-time player)))
                 (setf (charge-voice player) (play-sound :maul-charge))))
              ((and (attack-held player) (< time full) (< 0.0 (stamina player)))
               (let ((grow (min dt (- full time) (/ (stamina player) rate))))
                 (decf (stamina player) (* grow rate))
                 (setf (charge-time player) (+ time grow))
                 (when (<= full (charge-time player))
                   (play-sound :maul-full)))))
        (when (and (not (attack-held player)) (<= least (charge-time player)))
          (setf (blow-charge player) (blow-charge-at blow (charge-time player))
                (charge-time player) NIL
                (charge-voice player) (cut-sound (charge-voice player)))
          (player-swing player))))))

;;; The blow.

(defun charge-lerp (charge least full)
  "LEAST at no charge, FULL at a full one."
  (+ least (* charge (- full least))))

(defun charged-damage (blow charge)
  (round (charge-lerp charge (roll (blow-damage blow)) (roll (blow-full-damage blow)))))

(defun knock-guard-aside (creature)
  "A full blow struck CREATURE's shield or ward: it reels, its guard down (REEL)."
  (let ((time (if (typep creature 'boss) *maul-boss-reel-time* *maul-reel-time*)))
    (play-sound :maul-guard-break (location creature))
    (setf (reel creature) time
          (brace creature) 0.0)
    (stop-walking creature time)))

(defmethod swing-strike (player (blow charged-blow) target)
  (let* ((charge (blow-charge player))
         (full (<= 1.0 charge))
         (feet (feet player))
         (boss (typep target 'boss)))
    (play-sound :maul-hit (location target))
    (strike-sparks target feet (round (apply #'charge-lerp charge (blow-sparks blow)))
                   :speed (list 3.0 (charge-lerp charge 6.0 9.0)))
    (when (and full (shielded-p target feet))
      (shield-sparks target)
      (knock-guard-aside target))
    (hurt target (charged-damage blow charge) :from feet :by player
                                              :pain-bonus (round (charge-lerp charge (blow-pain-bonus blow) (blow-full-pain-bonus blow)))
                                              :force-pain (and full (not boss))
                                              :gib-overkill (if (undead target) 0.0 (blow-gib-overkill blow)))
    (when (gibbed target)
      (play-sound :maul-crush (location target)))
    (hit-stop (apply #'charge-lerp charge (blow-hit-stop blow)))
    (kick-camera (if full (blow-full-camera-shake blow) (apply #'charge-lerp charge (blow-camera-shake blow))) player)
    (push-creature target (v- (location target) feet)
                   (float (charge-lerp charge (blow-knockback blow) (blow-full-knockback blow)) 0f0)
                   :heft (not boss))
    (enchant-strike player (weapon player) target)))

;; A blow that finds no one living comes down on a corpse in its reach, if one could be raised,
;; and else on the wall or floor the crosshair meets (WALL-STRIKE, sword.lisp).
(defmethod swing-miss (player (blow charged-blow))
  (let ((corpse (looked-at-creature player (blow-reach blow) (blow-arc blow)
                                    :dead T :test (lambda (c) (and (dead c) (raisable-p c))))))
    (if corpse
        (progn
          (play-sound :maul-crush (location corpse))
          (tear-apart corpse :from (feet player)))
        (wall-strike player blow :charge (blow-charge player)))))

(defmethod blow-lines ((blow charged-blow))
  (list (format NIL "Damage ~a to ~a, reach ~,1f m" (range-text (blow-damage blow)) (range-text (blow-full-damage blow))
                (blow-reach blow))
        (format NIL "A blow ~d SP; hold to charge it" (round (blow-stamina blow)))
        "A full charge breaks a shield's guard"))

;;; The earthshake.

(defmethod start-blow ((blow earthshake) player)
  (start-alternate player blow))

(defmethod bash-strike (player (blow earthshake))
  (earthshake-hit player blow))

(defmethod second-blow-lines ((blow earthshake))
  (list (format NIL "Right button: earthshake, ~d SP" (round (blow-stamina blow)))
        "  staggers all standing round you"))

(defun shaken-p (player creature shake)
  "True if CREATURE, alive, stands on the floor PLAYER shakes with SHAKE (an earthshake), within its
reach and with no wall between."
  (let* ((feet (feet player))
         (loc (location creature))
         (dx (- (vx loc) (vx feet)))
         (dz (- (vz loc) (vz feet))))
    (and (not (dead creature))
         (< (abs (- (vy loc) (vy feet))) (blow-reach-height shake))
         (< (sqrt (+ (* dx dx) (* dz dz))) (+ (blow-reach shake) (body-radius creature)))
         (clear-path-p feet loc 0.3))))

(defun earthshake-hit (player shake)
  "The weapon strikes the floor (the earthshake SHAKE): everything standing within its reach flinches,
unless poised (a boss only rolls), and is shoved out."
  (let ((feet (feet player)))
    (play-sound :earthshake feet)
    (kick-dust feet (blow-dust-radius shake) (blow-dust-puffs shake) (container player))
    ;; It tears up a bloodroot's roots round the feet, and any snare with them (bloodroot.lisp).
    (break-snare player)
    (tear-roots feet (blow-reach shake))
    ;; And shatters the windows round it (glass.lisp).
    (strike-panes feet (blow-reach shake) :quake T)
    (let ((dir (look-direction player)))
      (floor-sparks (+ (vx feet) (* (blow-spark-reach shake) (vx dir))) (vy feet)
                    (+ (vz feet) (* (blow-spark-reach shake) (vz dir)))))
    (hit-stop (blow-hit-stop shake))
    (kick-camera (blow-camera-shake shake) player)
    (loop for c across *creatures*
          when (shaken-p player c shake)
            do (let ((poised (< 0.0 (bash-poise c)))
                     (boss (typep c 'boss)))
                 (setf (bash-poise c) (max (bash-poise c) (blow-poise-time shake)))
                 (hurt c (roll (blow-damage shake)) :from feet :by player
                                                    :pain-bonus (cond (poised -100) (boss (blow-boss-pain-bonus shake)) (T 0))
                                                    :force-pain (not (or poised boss)))
                 (push-creature c (v- (location c) feet)
                                (float (* (blow-knockback shake) (if poised *poised-bash-knockback* 1.0)) 0f0)
                                :heft (not boss))))))

;;; The sprite.

(define-shader-entity maul (sword)
  ((animation :initform (find-fx-animation 'maul))))

(defmethod held-weapon ((maul maul)) :maul)

(defmethod weapon-frame ((maul maul) player)
  (let* ((template (find-weapon :maul))
         (blow (weapon-swing template))
         (first (weapon-frame-index template :charge))
         (shake (and (bash-time player)
                     (frame-at (bash-time player) (blow-frame-times (weapon-alternate-blow template)))))
         (charge (charge-time player)))
    (cond (shake (+ (weapon-frame-index template :alternate) shake))
          ((null charge) (call-next-method))
          ((< charge (blow-raise-frame-time blow)) first)
          ((< charge (blow-full-charge blow)) (+ 1 first))
          ;; Full: trembling from one wound-up frame to the other.
          (T (+ 1 first (mod (floor (* (age maul) (blow-tremble-rate blow))) 2))))))

(defun add-maul (container)
  (add-weapon-sprite 'maul container))
