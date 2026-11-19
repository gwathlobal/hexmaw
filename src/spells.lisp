(in-package #:hexmaw)

;;; Daggerfall-style spells. A spell is a delivery (how it reaches its target)
;;; plus a list of effects. Each effect has a kind, a magnitude range, a duration,
;;; an area, a target type and, for damage, an element, and the spell's cost is derived
;;; from that composition, so the spellforge (forge.lisp) builds new spells from the same
;;; parts. What an effect kind does is a method on APPLY-EFFECT (here, and in magic.lisp
;;; for statuses, elements, healing and the rest).

(defclass effect ()
  ((kind :initarg :kind :reader effect-kind
         :documentation "Keyword naming what the effect does: :DAMAGE, :KNOCKBACK, ...")
   (magnitude :initarg :magnitude :initform '(1 1) :reader effect-magnitude
              :documentation "(MIN MAX); each application rolls an integer in that range.")
   (duration :initarg :duration :initform 0 :reader effect-duration
             :documentation "Seconds; 0 is instant. An over-time kind's magnitude is then per
second (damage, heal), a status kind's what it holds for that long (*EFFECT-KINDS*).")
   (area :initarg :area :initform 0 :reader effect-area
         :documentation "Radius in metres; 0 is a single target. A :CIRCLE delivery's reach,
otherwise a burst where the spell strikes.")
   (target-type :initarg :target-type :initform :target :reader effect-target-type
                :documentation ":SELF (the caster) or :TARGET (whatever the delivery hits;
:TOUCH means the same).")
   (element :initarg :element :initform NIL :reader effect-element
            :documentation "A damage effect's element, :FIRE, :FROST or :SHOCK, or NIL.")))

(defclass spell ()
  ((name :initarg :name :reader spell-name)
   (title :initarg :title :initform NIL :reader title-of
          :documentation "The name the player reads, if not its symbol's (SPELL-TITLE).")
   (delivery :initarg :delivery :initform :projectile :reader spell-delivery)
   (projectile-speed :initarg :projectile-speed :initform 20.0 :reader projectile-speed)
   (projectile-animation :initarg :projectile-animation :initform NIL :reader projectile-animation
                         :documentation "Effect animation the projectile flies as.")
   (impact-animation :initarg :impact-animation :initform NIL :reader impact-animation
                     :documentation "Effect animation played where the projectile hits, or NIL.")
   (light-color :initarg :light-color :initform *bolt-light-color* :reader light-color
                :documentation "Colour of the glow the projectile and its impact cast.")
   (light-radius :initarg :light-radius :initform *bolt-light-radius* :reader light-radius)
   (homing :initarg :homing :initform NIL :reader spell-homing
           :documentation "Radians a second a creature's projectile turns after the player; NIL flies straight.")
   (pain-bonus :initarg :pain-bonus :initform 0 :reader spell-pain-bonus
               :documentation "Percent its damage adds to a creature's PAIN-CHANCE.")
   (lifetime :initarg :lifetime :initform NIL :reader spell-lifetime
             :documentation "Seconds a projectile that hit nothing flies; NIL for *PROJECTILE-LIFETIME*.")
   (windup :initarg :windup :initform 2.5 :reader spell-windup
           :documentation "Seconds a :CIRCLE delivery glows on the floor before it strikes.")
   (circle-animation :initarg :circle-animation :initform NIL :reader circle-animation
                     :documentation "A :CIRCLE's sign on the floor: frames drawing it in, then a pulsing loop of 4.")

   (strike-animation :initarg :strike-animation :initform NIL :reader strike-animation
                     :documentation "What bursts up out of a :CIRCLE's floor when it strikes, played many times over it.")
   (nova-radius :initarg :nova-radius :initform NIL :reader nova-radius-of
                :documentation "Metres a :NOVA delivery reaches round its caster, besides its effects'
area; NIL for *NOVA-RADIUS* (SPELL-NOVA-RADIUS).")
   (overcharge :initarg :overcharge :initform 0.0 :accessor spell-overcharge
               :documentation "How far the cast that made this copy was overcharged, 0 to 1 (OVERCHARGED-SPELL).")
   (effects :initarg :effects :reader spell-effects)))

(defvar *spells* (make-hash-table :test 'eq))

(defun find-spell (name)
  (or (gethash name *spells*) (error "No spell named ~s." name)))

(defun spell-title (spell)
  "SPELL's name as the player reads it: a forged spell's own, or a defined one's title or symbol."
  (let ((name (spell-name spell)))
    (cond ((stringp name) name)
          ((title-of spell))
          (T (substitute #\Space #\- (string-capitalize name))))))

(defmacro define-spell (name (&rest options) &body effects)
  "Define spell NAME. OPTIONS are SPELL initargs; each effect is (KIND &rest EFFECT-INITARGS):

  (define-spell bolt (:delivery :projectile :projectile-speed 20.0)
    (:damage :magnitude '(6 10))
    (:knockback :magnitude '(4 4)))"
  `(setf (gethash ',name *spells*)
         (make-instance 'spell :name ',name ,@options
                               :effects (list ,@(loop for (kind . args) in effects
                                                      collect `(make-instance 'effect :kind ,kind ,@args))))))

;;; Power: each effect's base times its average magnitude, scaled by how long it lasts, by its
;;; area and by its delivery (a touch costs the caster a step into reach; a seeker and a beam
;;; hardly miss; a nova strikes all round). A spell's power is the sum, rounded up: what dust and
;;; enchantments are priced by (forge.lisp, sword.lisp) and found runes sized to (loot.lisp).
;;;
;;; Its tier follows from it (SPELL-TIER): a weak, simple spell is free, a stronger one costs
;;; stamina, and the strongest, and every heal, ward and drain, cost mana. A mana cast takes
;;; its power with striking effects at *CAST-STRIKE-SCALE* (SPELL-COST).

(defparameter *effect-kinds*
  '((:damage :base 1.5 :timing :over-time :targets (:target) :magnitude 30 :duration 8 :area 3.0)
    (:heal :base 1.0 :timing :over-time :targets (:self) :magnitude 40 :duration 10 :area 0)
    (:knockback :base 0.5 :timing :instant :targets (:target) :magnitude 12 :duration 0 :area 3.0)
    (:slow :base 0.12 :timing :status :targets (:target) :magnitude 60 :duration 10 :area 3.0)
    (:drain :base 2.0 :timing :instant :targets (:target) :magnitude 20 :duration 0 :area 0)
    (:ward :base 0.4 :timing :status :targets (:self) :magnitude 40 :duration 20 :area 0)
    (:absorb :base 0.2 :timing :instant :targets (:self) :magnitude 100 :duration 0 :area 0))
  "What each effect kind the spellforge offers is: power per point of average magnitude
(:BASE), how its duration counts (:TIMING: :INSTANT ignores it, :OVER-TIME makes the
magnitude per second, :STATUS holds the magnitude that long), who it may strike
(:TARGETS), and the most magnitude, duration and area the forge allows. Kinds not
listed (creatures' :WHIRL, :GUST) cost 1 a point, their duration counting as a status's.")

(defparameter *element-costs* '(:fire 1.5 :frost 1.7 :shock 1.7)
  "Power per point of damage, by element: frost and shock do more than fire.")
(defparameter *over-time-discount* 0.6
  "An over-time effect costs its magnitude a second times its duration times this.")
(defparameter *delivery-cost-scales* '(:touch 0.75 :seeker 1.3 :beam 1.4 :nova 1.5)
  "A spell's power by its delivery, against the same as a plain projectile.")

(defun kind-property (kind property &optional default)
  (getf (rest (assoc kind *effect-kinds*)) property default))

(defun effect-cost (effect &optional delivery)
  "EFFECT's share of a spell's power, delivered by DELIVERY."
  (destructuring-bind (lo hi) (effect-magnitude effect)
    (let* ((kind (effect-kind effect))
           (duration (effect-duration effect))
           (base (or (and (eq kind :damage) (getf *element-costs* (effect-element effect)))
                     (kind-property kind :base 1.0)))
           (time (ecase (kind-property kind :timing :status)
                   (:instant 1)
                   (:over-time (if (< 0 duration) (* duration *over-time-discount*) 1))
                   (:status (+ 1 (/ duration 5))))))
      (* base (/ (+ lo hi) 2) time
         (+ 1 (effect-area effect))
         (getf *delivery-cost-scales* delivery 1)))))

(defun spell-power (spell)
  "SPELL's strength as one number: its effects' costs, summed and rounded up."
  (ceiling (reduce #'+ (spell-effects spell)
                   :key (lambda (effect) (effect-cost effect (spell-delivery spell))))))

;;; Tiers. Each tier's rules are checked in turn, free first; the first whose every rule the
;;; spell meets is its tier.

(defparameter *free-max-power* 14 "Most power a free spell may have: the starting Fire Bolt's.")
(defparameter *free-max-knockback* 4 "Most knockback a free spell may carry beside its damage.")
(defparameter *free-deliveries* '(:projectile :touch :seeker))
(defparameter *stamina-max-power* 40)
(defparameter *stamina-max-beam-power* 20 "Most power a stamina beam may have: it strikes four times a second.")
(defparameter *stamina-max-effects* 2)
(defparameter *stamina-max-duration* 4 "Most seconds a stamina spell's damage over time or slow may last.")
(defparameter *stamina-max-area* 1.5)
(defparameter *stamina-kinds* '(:damage :knockback :slow))
(defparameter *stamina-deliveries* '(:projectile :touch :seeker :beam :nova))
(defparameter *cast-strike-scale* 0.5
  "Mana a mana spell's striking effects take a cast, against their power: what the same spell
costs a blow as an enchantment (*ENCHANT-COST-SCALE*, sword.lisp).")

(defun absorb-spell-p (spell)
  (find :absorb (spell-effects spell) :key #'effect-kind))

(defun tier-fault (spell tier)
  "Why SPELL isn't of TIER (:FREE or :STAMINA), a short phrase, or NIL if it meets its rules."
  (let* ((effects (spell-effects spell))
         (delivery (spell-delivery spell))
         (power (spell-power spell)))
    (flet ((kinds () (mapcar #'effect-kind effects)))
      (ecase tier
        (:free
         (cond ((absorb-spell-p spell) "it turns projectiles into mana")
               ((not (member delivery *free-deliveries*))
                (format NIL "a ~(~a~) is never free" delivery))
               ((not (eq :damage (effect-kind (first effects)))) "a free spell is damage")
               ((or (< 2 (length effects))
                    (and (rest effects) (not (eq :knockback (effect-kind (second effects))))))
                "a free spell is damage, with knockback at most")
               ((find-if (lambda (e) (< 0 (effect-duration e))) effects) "it lasts")
               ((find-if (lambda (e) (< 0 (effect-area e))) effects) "it bursts")
               ((find-if (lambda (e) (and (eq :knockback (effect-kind e))
                                          (< *free-max-knockback* (second (effect-magnitude e)))))
                         effects)
                (format NIL "its knockback is over ~d" *free-max-knockback*))
               ((< *free-max-power* power)
                (format NIL "power ~d is over ~d" power *free-max-power*))))
        (:stamina
         (let ((top (if (eq delivery :beam) *stamina-max-beam-power* *stamina-max-power*)))
           (cond ((find :heal (kinds)) "it heals")
                 ((find :ward (kinds)) "it wards")
                 ((find :drain (kinds)) "it drains")
                 ((eq delivery :self) "it is cast on yourself")
                 ((not (member delivery *stamina-deliveries*))
                  (format NIL "a ~(~a~) costs mana" delivery))
                 ((< *stamina-max-effects* (length effects))
                  (format NIL "it has over ~d effects" *stamina-max-effects*))
                 ((set-difference (kinds) *stamina-kinds*) "its effects cost mana")
                 ((find-if (lambda (e) (< *stamina-max-duration* (effect-duration e))) effects)
                  (format NIL "it lasts over ~d s" *stamina-max-duration*))
                 ((find-if (lambda (e) (< *stamina-max-area* (effect-area e))) effects)
                  (format NIL "its area is over ~,1f m" *stamina-max-area*))
                 ((< top power) (format NIL "power ~d is over ~d" power top)))))))))

(defun forged-kinds-p (spell)
  "True if every effect of SPELL is of a kind the forge makes (*EFFECT-KINDS*)."
  (every (lambda (e) (assoc (effect-kind e) *effect-kinds*)) (spell-effects spell)))

(defun spell-tier (spell)
  "SPELL's tier: :FREE, :STAMINA or :MANA. The creatures' spells and the tornado, which the forge
doesn't make, are :MANA."
  (cond ((not (forged-kinds-p spell)) :mana)
        ;; An Absorb turns projectiles into mana, so it is held on stamina (ABSORBS-P, magic.lisp).
        ((absorb-spell-p spell) :stamina)
        ((null (tier-fault spell :free)) :free)
        ((null (tier-fault spell :stamina)) :stamina)
        (T :mana)))

(defun tier-reason (spell)
  "Why SPELL is of its tier and not the one below, a short phrase, or NIL for a free spell."
  (ecase (spell-tier spell)
    (:free NIL)
    (:stamina (tier-fault spell :free))
    (:mana (or (tier-fault spell :stamina) "the forge can't make it"))))

(defun spell-cost (spell)
  "The mana a cast of SPELL takes: none for a free or stamina spell; for a mana spell its power,
striking effects at *CAST-STRIKE-SCALE* (one the forge can't make, the tornado, its whole power)."
  (cond ((not (eq (spell-tier spell) :mana)) 0)
        ((not (forged-kinds-p spell)) (spell-power spell))
        (T (max 1 (ceiling (reduce #'+ (spell-effects spell)
                                   :key (lambda (effect)
                                          (* (if (eq (effect-target-type effect) :self) 1 *cast-strike-scale*)
                                             (effect-cost effect (spell-delivery spell))))))))))

(defun spell-stamina (spell)
  "The stamina a cast of SPELL takes: its power for a stamina spell, else none; for an Absorb, which
is held, its power a second."
  (if (eq (spell-tier spell) :stamina) (spell-power spell) 0))

(defparameter *absorb-take-stamina* 1.0
  "Stamina a point of mana an Absorb gains from a projectile costs, beside its hold's.")

(defun roll (magnitude)
  (destructuring-bind (lo hi) magnitude
    (+ lo (random (1+ (- hi lo)) *roll-random*))))

;;; Effects.

(defgeneric apply-effect (kind effect target source)
  (:documentation "Apply EFFECT, whose kind is KIND, to TARGET. SOURCE is what delivered
it (a SPELL-PROJECTILE for projectile spells, a SPELL-CIRCLE for circles)."))

(defmethod apply-effect (kind effect target source)
  (v:warn :hexmaw "No ~s effect for ~a; ignored." kind target))

(defgeneric effect-origin (source)
  (:documentation "The point an effect delivered by SOURCE strikes from, or NIL.")
  (:method (source) NIL))

(defgeneric effect-direction (source target)
  (:documentation "The way an effect delivered by SOURCE pushes TARGET, a vector whose
horizontal part counts."))

(defgeneric effect-unblockable-p (source)
  (:documentation "True if the player's raised shield does nothing against an effect
delivered by SOURCE.")
  (:method (source) NIL))

(defparameter *unblockable-spells* '(bloom)
  "Spells whose bursts and novas no raised shield stops: they come up from the floor (a
bloodroot's Bloom, bloodroot.lisp).")

(defmethod apply-effect ((kind (eql :knockback)) effect (target creature) source)
  ;; A flash, so a push alone reads as a hit; it carries the creature (SHOVED-P) until it slows.
  (setf (flash target) (max (flash target) *flash-time*))
  (push-creature target (effect-direction source target) (float (roll (effect-magnitude effect)) 0f0)))

(defun target-effect-p (effect)
  (member (effect-target-type effect) '(:target :touch)))

(defun apply-spell (spell target source)
  "Apply SPELL's effects on what it reaches to TARGET, whatever their area (a circle's)."
  (dolist (effect (spell-effects spell))
    (when (target-effect-p effect)
      (apply-effect (effect-kind effect) effect target source))))

(defun apply-self-effects (spell caster source)
  (dolist (effect (spell-effects spell))
    (when (eq :self (effect-target-type effect))
      (apply-effect (effect-kind effect) effect caster source))))

;;; Striking: a projectile or a touch reaches a point, hitting a body there or nothing (a
;;; wall). Its single-target effects strike that body; an effect with an area bursts over
;;; every body within it that the point can see, but its caster and those it spares.

(defclass strike ()
  ((spell :initarg :spell :reader spell)
   (caster :initarg :caster :initform NIL :reader caster)
   (origin :initarg :origin :reader strike-origin
           :documentation "Where it strikes from: what it pushes away from."))
  (:documentation "The source of effects that land without a projectile in flight: a burst,
a touch, a weapon's enchantment."))

(defmethod effect-origin ((source strike))
  (strike-origin source))

(defmethod effect-unblockable-p ((source strike))
  (and (member (spell-name (spell source)) *unblockable-spells*) T))

(defmethod effect-direction ((source strike) target)
  (v- (if (typep target 'player) (feet target) (location target)) (strike-origin source)))

(defgeneric effect-shove (source)
  (:documentation "What an effect delivered by SOURCE does to the player besides its damage, as
HURT-PLAYER's SHOVE: T for a blow's shove and hit-stop, NIL for none (a creature's held beam, whose
pulses would otherwise shove and freeze four times a second).")
  (:method (source) T))

(defgeneric effect-block-cost (source)
  (:documentation "Stamina the player's raised shield pays for a blow delivered by SOURCE, or NIL for
the usual *BLOCK-STAMINA-SCALE* a point of its damage.")
  (:method (source) NIL))

(defclass beam-pulse (strike)
  ((block-cost :initarg :block-cost :initform NIL :reader beam-pulse-block-cost))
  (:documentation "The source of one strike of a beam a creature holds (votary.lisp): no shove or
hit-stop, and its own stamina against a raised shield."))

(defmethod effect-shove ((source beam-pulse)) NIL)
(defmethod effect-block-cost ((source beam-pulse)) (beam-pulse-block-cost source))

(defun burst-spell (spell point caster)
  "Burst SPELL's effects that have an area over every body within it of POINT, and over the skins
it reaches (STRIKE-SKINS, skins.lisp: fire melts rime)."
  (dolist (effect (spell-effects spell))
    (when (and (target-effect-p effect) (< 0 (effect-area effect)))
      (when (effect-element effect)
        (strike-skins (effect-element effect) point (effect-area effect) caster))
      (let ((burst (make-instance 'strike :spell spell :caster caster :origin point)))
        (dolist (body (burst-victims point (effect-area effect) caster))
          (apply-effect (effect-kind effect) effect body burst))))))

(defun strike-with-spell (spell victim origin caster &optional (at origin))
  "SPELL, cast by CASTER, strikes without a projectile (a touch, an enchanted blow): its
single-target effects strike VICTIM (or no one) from point ORIGIN, those with an area
burst over every body within it of point AT."
  (when victim
    (let ((source (make-instance 'strike :spell spell :caster caster :origin origin)))
      (dolist (effect (spell-effects spell))
        (when (and (target-effect-p effect) (= 0 (effect-area effect)))
          (apply-effect (effect-kind effect) effect victim source)))))
  (burst-spell spell at caster))

(defun spell-burst-radius (spell)
  "The widest area of SPELL's effects on what it strikes, 0 for none."
  (loop for effect in (spell-effects spell)
        when (target-effect-p effect) maximize (effect-area effect)))

;;; Projectile delivery.

(defun projectile-delivery-p (delivery)
  "True if DELIVERY flies as a projectile: a plain one or a seeker (SEEKER-MARK)."
  (member delivery '(:projectile :seeker)))

(defparameter *seeker-cone* 0.35 "Radians either side of the aim a seeker looks for its mark in.")
(defparameter *seeker-range* 30.0 "Metres out a seeker looks for its mark.")
(defparameter *seeker-turn* 2.5 "Radians a second a seeker turns after its mark.")

(defparameter *projectile-lifetime* 3.0 "Seconds before a projectile that hit nothing vanishes.")
(defparameter *free-projectile-lifetime* 1.0
  "Seconds the player's free spells fly before they vanish: 20 m at the bolt's speed.")
(defparameter *projectile-size* 0.18 "Collision diameter in metres; the sprite can be bigger.")
(defparameter *wind-gust* '(0.6 1.4)
  "Least and most of a wind's turn that one projectile takes (its GUST, drawn from *ROLL-RANDOM*).")

(defparameter *impact-pullback* 0.25
  "Metres back along the flight path where the impact plays, so it isn't buried in the wall.")

(define-shader-entity spell-projectile (fx-sprite)
  ((spell :initarg :spell :initform NIL :reader spell)
   (caster :initarg :caster :initform NIL :accessor caster
           :documentation "Who fired it (the player or a creature), whom it never hits.")
   (launcher :initarg :launcher :initform NIL :accessor launcher
             :documentation "Who first fired it: its CASTER until a shield turned it back.")
   (homing :initarg :homing :initform NIL :accessor homing
           :documentation "Radians a second it turns after HOMING-TARGET, or NIL; a shield that
turns it aside ends it.")
   (homing-target :initarg :homing-target :initform NIL :accessor homing-target
                  :documentation "What it homes in on: what its creature caster hunted as it cast, or NIL
for the player.")
   (projectile-velocity :initform (vec 0 0 0) :reader projectile-velocity)
   (submerged :initform NIL :accessor submerged
              :documentation "True while it is in a liquid: one cast under water flies on in it,
and bursts only on entering one from outside.")
   (gust :initform 1.0 :accessor gust
         :documentation "How hard the winds it flies through bend it, from *WIND-GUST*, drawn as it
leaves (BLOW-PROJECTILE): so a long shot through a wind can't be aimed off to allow for it.")
   (evade-asked :initform NIL :accessor evade-asked
                :documentation "The creature last asked whether it evades this (the player's)
projectile about to reach it, so each is asked once.")
   (sound :initform NIL :accessor projectile-sound
          :documentation "Its flight's loop (sound.lisp), from its first tick until it leaves.")))

(defparameter *spell-sounds*
  '(bolt (:flight :bolt-flight :impact :bolt-impact)
    cinder (:flight :cinder-flight :impact :cinder-impact)
    grave-skull (:cast :skull-cast :flight :skull-flight :impact :skull-impact)
    grave-spikes (:circle :grave-circle :strike :grave-spikes)
    firestorm (:circle :firestorm-sign :ignite :firestorm-ignite :storm :firestorm-roar)
    gust (:cast :gust-cast)
    rift-pull (:cast :rift-cast :flight :rift-flight :impact :rift-impact)
    rift-swap (:cast :rift-cast :flight :rift-flight :impact :rift-impact)
    rift-push (:cast :rift-cast :flight :rift-flight :impact :rift-impact)
    rime-shard (:flight :shard-flight :impact :shard-impact)
    rime-field (:flight :shard-flight :impact :rime-form)
    hag-nova (:impact :frost-nova)
    hag-nova-boss (:impact :frost-nova)
    static-recoil (:impact :votary-recoil)
    hierophant-recoil (:impact :votary-recoil)
    bloom (:impact :bloom))
  "Each spell's clips (sound.lisp) by event: :CAST where a creature lets it go, :FLIGHT its
projectile's loop, :IMPACT its burst, :CIRCLE a circle's loop through its wind-up and :STRIKE
its strike, and the acolyte's firestorm :IGNITE as it comes down and :STORM while it burns. The player's own casts sound from the hands (player.lisp).")

(defun spell-sound (spell event)
  ;; A forged spell (named by a string, SPEC-SPELL) sounds like the bolt.
  (getf (getf *spell-sounds* (if (stringp (spell-name spell)) 'bolt (spell-name spell))) event))

;; A reset, a rebuild or its end takes it away: its flight falls silent.
(defmethod leave :after ((projectile spell-projectile) container)
  (setf (projectile-sound projectile) (stop-loop (projectile-sound projectile))))


;; It strikes from behind itself, along its flight, and pushes along it.
(defmethod effect-origin ((source spell-projectile))
  (v- (location source) (projectile-velocity source)))

(defmethod effect-direction ((source spell-projectile) target)
  (projectile-velocity source))

(defun launch-projectile (spell origin direction container caster &key (class 'spell-projectile))
  "Fire SPELL from ORIGIN along unit vector DIRECTION, on behalf of CASTER, as a projectile of
CLASS (a LOBBED-PROJECTILE arcs, bloodroot.lisp)."
  (let ((projectile (make-instance class
                                  :spell spell :caster caster :launcher caster :location (vcopy origin)
                                  :homing (if (eq (spell-delivery spell) :seeker)
                                              *seeker-turn*
                                              (spell-homing spell))
                                  :homing-target (cond ((eq (spell-delivery spell) :seeker)
                                                        (seeker-mark origin direction caster))
                                                       ((and (spell-homing spell) (typep caster 'creature))
                                                        (hunt-target caster)))
                                  :animation (find-fx-animation (projectile-animation spell)))))
    (v<- (projectile-velocity projectile) direction)
    (setf (submerged projectile) (and (liquid-at (vx origin) (vy origin) (vz origin)) T)
          (gust projectile) (let ((range *wind-gust*))
                              (+ (first range) (random (float (- (second range) (first range)) 0f0) *roll-random*))))
    (nv* (projectile-velocity projectile) (float (projectile-speed spell) 0f0))
    (enter projectile container)
    (attach-glow projectile (light-color spell) (light-radius spell))
    projectile))

(defparameter *burst-size* 0.45
  "Radius in metres an impact animation's burst stands for: one bursting over an area is
drawn bigger, up to *BURST-SCALE-LIMIT*, and shells of bursts fill the rest of its ball.")
(defparameter *burst-scale-limit* 1.5
  "The most an impact is scaled up. Further, its art pixels grow far coarser than everything
around it (a 2 m burst was drawn at 12 px a metre, against the monsters' 64).")
(defparameter *burst-shell-step* 1.0 "Metres between the shells of bursts filling an area, and over each.")
(defparameter *burst-max-copies* 120
  "The most bursts that fill an area: past it, the shells and the bursts on them are spaced wider.")

(defun impact-point (projectile)
  "Where PROJECTILE's impact plays: a little back along its flight, out of the wall."
  (let ((velocity (projectile-velocity projectile)))
    (v- (location projectile) (v* velocity (/ *impact-pullback* (max 0.001 (vlength velocity)))))))

(defun shell-counts (radius step)
  "How many bursts go on each shell filling a ball of RADIUS STEP metres apart, innermost first."
  (let ((shells (max 1 (round radius step))))
    (loop for shell from 1 to shells
          for r = (* radius (/ shell shells))
          collect (max 4 (round (* 4 pi r r) (* step step))))))

(defun burst-shells (name at radius container &key (inner 0))
  "Fill the ball RADIUS metres round AT with bursts of NAME at their own size: shells
*BURST-SHELL-STEP* apart out to RADIUS, the bursts on each as far apart (a Fibonacci sphere,
turned from shell to shell so they don't line up), spaced wider when there would be more than
*BURST-MAX-COPIES*. None goes inside a solid or behind one from AT, so on a floor it is a dome
and on a wall half a ball. They start a frame or two apart, so they don't pulse as one. Shells
nearer AT than INNER are left out (a nova's, round its caster's eye)."
  (let* ((total (reduce #'+ (shell-counts radius *burst-shell-step*)))
         (step (* *burst-shell-step* (max 1.0 (sqrt (/ total *burst-max-copies*)))))
         (counts (shell-counts radius step))
         (shells (length counts))
         (golden (float (* pi (- 3 (sqrt 5.0))) 0f0)))
    (loop for shell from 1
          for count in counts
          for r = (float (* radius (/ shell shells)) 0f0)
          do (dotimes (i count)
               (let* ((y (- 1.0 (/ (* 2.0 (+ i 0.5)) count)))
                      (across (* r (sqrt (- 1.0 (* y y)))))
                      (angle (+ (* i golden) (* 1.3 shell)))
                      (point (vec (+ (vx at) (* across (cos angle)))
                                  (+ (vy at) (* r y))
                                  (+ (vz at) (* across (sin angle))))))
                 (unless (or (< r inner)
                             (solid-at (vx point) (vy point) (vz point))
                             (not (clear-line-p at point)))
                   (setf (age (spawn-fx name point container)) (* 0.04 (mod (+ i shell) 3)))))))))

(defun play-impact (spell at container &key water quiet)
  "Play SPELL's impact animation at AT, its burst over its area, with its glow and its sound. Into
WATER it hisses out; QUIET, it makes no sound (a held beam's, which has its own)."
  (let ((name (impact-animation spell)))
    (when (and name container)
      (let* ((radius (spell-burst-radius spell))
             (k (max 1.0 (/ radius *burst-size*)))
             (sprite (spawn-fx name at container)))
        (nv* (scaling sprite) (min k *burst-scale-limit*))
        (when (< *burst-scale-limit* k)
          (burst-shells name at radius container))
        (attach-glow sprite (light-color spell) (* (light-radius spell) (sqrt k)))
        (unless quiet
          (play-sound (if water :bolt-hiss-water (spell-sound spell :impact)) at))))))

(defun impact (projectile &key water (at (impact-point projectile)))
  "Play the spell's impact where PROJECTILE hit, and remove it. Into WATER it hisses out."
  (play-impact (spell projectile) at (container projectile) :water water)
  (despawn projectile))

;; The player's own projectiles never hit them, nor a creature's that creature.
(defun projectile-victim (projectile point margin)
  "The body PROJECTILE hits at POINT, MARGIN metres around it: a live creature or the player."
  (let ((caster (caster projectile)))
    (or (creature-at point margin caster)
        (and *player* (not (eq caster *player*)) (player-at-p *player* point margin)
             *player*))))

;;; Shields. A spell striking a shield from the front (SHIELDED-P, creature.lisp: the
;;; views of the sprite its shield covers) does nothing to the bearer. A shield that
;;; reflects sends it back the way it came, mirrored off the shield's face, as the
;;; bearer's own; one that doesn't, stops it.

(defgeneric deflects-p (target projectile)
  (:documentation "True if TARGET turns PROJECTILE aside instead of taking its effects.")
  (:method (target projectile) NIL))

(defmethod deflects-p ((target creature) (projectile spell-projectile))
  (and (not (full-overcharge-p (spell projectile)))
       (shielded-p target (v- (location target) (projectile-velocity projectile)))))

;;; Overcharge: a striking stamina or mana spell held before it goes (player.lisp) is cast as a
;;; copy of itself, stronger by its overcharge. Full, it strikes past a shield or ward: the guard
;;; is knocked aside (KNOCK-GUARD-ASIDE, maul.lisp, the maul's full blow's) and the blow always
;;; makes its target flinch.

(defparameter *overcharge-strength* 0.6 "How much stronger a full overcharge makes a spell's magnitudes.")
(defparameter *overcharge-pain-bonus* 60 "Percent a full overcharge adds to a boss's pain roll; the rest always flinch.")

(defun full-overcharge-p (spell) (and spell (<= 1.0 (spell-overcharge spell))))

(defun scaled-spell (spell k &key (pain-bonus (spell-pain-bonus spell)))
  "A copy of SPELL, its look and flight kept, its magnitudes times K."
  (let ((copy (spec-spell
               (destructuring-bind (name delivery &rest effects) (spell-spec spell)
                 (list* name delivery
                        (loop for e in effects
                              collect (let ((m (getf e :magnitude)))
                                        (list* :magnitude (list (max 1 (round (* k (first m))))
                                                                (max 1 (round (* k (second m)))))
                                               e))))))))
    (dolist (slot '(title projectile-speed projectile-animation impact-animation light-color light-radius
                    homing lifetime nova-radius))
      (setf (slot-value copy slot) (slot-value spell slot)))
    (setf (slot-value copy 'pain-bonus) pain-bonus)
    copy))

(defun overcharged-spell (spell charge)
  "SPELL as an overcharge of CHARGE (0 to 1) casts it: itself at none."
  (if (<= charge 0.0)
      spell
      (let ((copy (scaled-spell spell (+ 1 (* *overcharge-strength* charge)))))
        (setf (spell-overcharge copy) (min 1.0 charge))
        copy)))

(defun overcharge-breaks-guard (spell target from)
  "A full overcharge of SPELL strikes TARGET from FROM: knock its shield or ward aside if it covers."
  (when (and (full-overcharge-p spell) (typep target 'creature) (shielded-p target from))
    (knock-guard-aside target)))

(defun deflect (target projectile)
  "TARGET's shield takes PROJECTILE: reflect it, or stop it if the shield doesn't reflect."
  (block-hit target)
  (play-sound :shield-deflect (location projectile))
  (cond ((shield-reflects target)
         ;; Mirror the flight off the shield's face, whose normal is the way TARGET faces,
         ;; and send it back up or down too: straight on, it returns to its caster.
         (let* ((v (projectile-velocity projectile))
                (nx (sin (facing target)))
                (nz (- (cos (facing target))))
                (d (+ (* (vx v) nx) (* (vz v) nz))))
           (setf (vx v) (- (vx v) (* 2 d nx))
                 (vz v) (- (vz v) (* 2 d nz))
                 (vy v) (- (vy v))))
         (setf (caster projectile) target
               (homing projectile) NIL
               (age projectile) 0.0))
        (T
         (impact projectile))))

(defun steer (projectile dt target)
  "Turn PROJECTILE's flight toward TARGET's chest by at most its HOMING rate for DT seconds,
keeping its speed."
  (let* ((v (projectile-velocity projectile))
         (loc (location projectile))
         (feet (body-feet target))
         (tx (- (vx feet) (vx loc)))
         (ty (- (+ (vy feet) (aim-height target)) (vy loc)))
         (tz (- (vz feet) (vz loc)))
         (tl (sqrt (+ (* tx tx) (* ty ty) (* tz tz))))
         (speed (vlength v)))
    (when (and (< 1f-3 tl) (< 1f-3 speed))
      (let* ((ux (/ (vx v) speed)) (uy (/ (vy v) speed)) (uz (/ (vz v) speed))
             (dx (/ tx tl)) (dy (/ ty tl)) (dz (/ tz tl))
             (cos-a (max -1f0 (min 1f0 (+ (* ux dx) (* uy dy) (* uz dz)))))
             (step (* (homing projectile) dt)))
        (if (<= (acos cos-a) step)
            (setf (vx v) (* speed dx) (vy v) (* speed dy) (vz v) (* speed dz))
            ;; Rotate toward the target in the plane of the flight and the target: W is the
            ;; part of the way to the target square to the flight.
            (let* ((wx (- dx (* cos-a ux))) (wy (- dy (* cos-a uy))) (wz (- dz (* cos-a uz)))
                   (wl (sqrt (+ (* wx wx) (* wy wy) (* wz wz)))))
              (when (< 1f-5 wl)
                (let ((c (cos step)) (s (/ (sin step) wl)))
                  (setf (vx v) (* speed (+ (* c ux) (* s wx)))
                        (vy v) (* speed (+ (* c uy) (* s wy)))
                        (vz v) (* speed (+ (* c uz) (* s wz))))))))))))

;;; Winds: what blows across a projectile in flight and holds back what walks in it, the tornado
;;; (vortex.lisp) and the rime hag's blizzard (hag.lisp). Each is in *WINDS* (sparks.lisp) while it
;;; blows, and answers WIND-TURN and WIND-SLOW, and WIND-CARRY for the snow it blows round. A wind
;;; turns a flight about +Y, the way it blows round, so a projectile is bent the further it flies
;;; through it: one from close in strikes, one from across it goes wide.

(defparameter *wind-volume* 0.6
  "How loud the rushing wind the player hears in a wind that holds them back (a blizzard), against a
tornado's hold.")

(defgeneric wind-turn (wind projectile)
  (:documentation "Radians a second WIND turns PROJECTILE's flight about +Y, from +X toward +Z (its
way round); 0 where it doesn't reach it.")
  (:method (wind projectile) (declare (ignore wind projectile)) 0.0))

(defgeneric wind-slow (wind actor)
  (:documentation "The fraction of its speed WIND leaves ACTOR (the player or a creature); 1 where
it doesn't reach it.")
  (:method (wind actor) (declare (ignore wind actor)) 1.0))

(defun add-wind (wind)
  (unless (find wind *winds*) (vector-push-extend wind *winds*)))

(defun remove-wind (wind)
  (let ((at (position wind *winds*)))
    (when at
      (replace *winds* *winds* :start1 at :start2 (1+ at))
      (decf (fill-pointer *winds*)))))

(defun wind-slow-factor (actor)
  "The fraction of its speed the winds leave ACTOR."
  (let ((k 1.0))
    (loop for wind across *winds* do (setf k (* k (wind-slow wind actor))))
    k))

(defun blow-projectile (projectile dt)
  "Turn PROJECTILE's flight by the winds it is in, for DT seconds."
  (when (< 0 (fill-pointer *winds*))
    (let ((turn 0.0))
      (loop for wind across *winds* do (incf turn (wind-turn wind projectile)))
      (unless (= turn 0.0)
        (let* ((a (* turn (gust projectile) dt))
               (c (cos a)) (s (sin a))
               (v (projectile-velocity projectile))
               (x (vx v)) (z (vz v)))
          (setf (vx v) (- (* c x) (* s z))
                (vz v) (+ (* s x) (* c z))))))))

(defparameter *evade-look-ahead* 0.2
  "Seconds of flight ahead of the player's projectile that a creature sees it coming (EVADE-PROJECTILE).")

(defgeneric evade-projectile (creature projectile)
  (:documentation "Give CREATURE, which the player's PROJECTILE is about to reach, its chance
to get out of the way (the riftwalker's blink, riftwalker.lisp). Asked once per projectile.")
  (:method (creature projectile) NIL))

(defvar *evade-probe* (vec 0 0 0))

(defun look-ahead (projectile r)
  "Ask the creature the player's PROJECTILE will reach within *EVADE-LOOK-AHEAD* whether it evades it."
  (let ((probe *evade-probe*)
        (loc (location projectile))
        (v (projectile-velocity projectile))
        (k (float *evade-look-ahead* 0f0)))
    (setf (vx probe) (+ (vx loc) (* k (vx v)))
          (vy probe) (+ (vy loc) (* k (vy v)))
          (vz probe) (+ (vz loc) (* k (vz v))))
    (let ((c (creature-at probe r *player*)))
      (when (and c (not (eq c (evade-asked projectile))))
        (setf (evade-asked projectile) c)
        (evade-projectile c projectile)))))

(defun projectile-lifetime (projectile)
  "Seconds PROJECTILE flies before it vanishes: its spell's own, short for the player's free ones."
  (let ((spell (spell projectile)))
    (cond ((spell-lifetime spell))
          ((and *player* (eq (caster projectile) *player*) (eq (spell-tier spell) :free))
           *free-projectile-lifetime*)
          (T *projectile-lifetime*))))

(defgeneric absorbs-p (target projectile)
  (:documentation "True if TARGET swallows PROJECTILE instead of being struck (the player's Absorb, magic.lisp).")
  (:method (target projectile) NIL))

(defgeneric absorb-projectile (target projectile)
  (:documentation "TARGET swallows PROJECTILE."))

;; After FX-SPRITE's tick, which animates and ages it.
(defgeneric spell-impact (name spell at caster container victim)
  (:documentation "What the spell named NAME (a symbol of *SPELLS*; a forged spell's name is a
string) does where its projectile struck, AT, besides its effects: VICTIM is the body it struck,
or NIL for a wall, floor or liquid (the rime field lays its patch, hag.lisp).")
  (:method (name spell at caster container victim)
    (declare (ignore name spell at caster container victim))
    NIL))

(defparameter *impact-skin-reach* 1.0
  "Metres round where a projectile strikes that its element reaches the skins (STRIKE-SKINS), at
least: so the plain Fire Bolt melts rime.")

(defun projectile-landed (projectile at victim)
  "PROJECTILE struck at AT (VICTIM, or NIL): its element on the skins there, and its spell's own hook."
  (let* ((spell (spell projectile))
         (element (spell-element spell)))
    (when element
      (strike-skins element at (max *impact-skin-reach* (spell-burst-radius spell)) (caster projectile)))
    (spell-impact (spell-name spell) spell at (caster projectile) (container projectile) victim)))

(define-handler (spell-projectile tick :after) (dt)
  (unless (frozen-p)
    (let* ((loc (location spell-projectile))
           (r (* 0.5 (float *projectile-size* 0f0))))
      (when (homing spell-projectile)
        (let ((target (or (homing-target spell-projectile)
                          (and (not (eq (caster spell-projectile) *player*)) *player*))))
          (when (and target (not (eq target (caster spell-projectile))) (target-live-p target))
            (steer spell-projectile (float dt 0f0) target))))
      (blow-projectile spell-projectile (float dt 0f0))
      (when (and *player* (eq (caster spell-projectile) *player*))
        (look-ahead spell-projectile r))
      (nv+* loc (projectile-velocity spell-projectile) dt)
      (let ((sound (projectile-sound spell-projectile)))
        (if sound
            (move-loop sound loc)
            (setf (projectile-sound spell-projectile)
                  (start-loop (spell-sound (spell spell-projectile) :flight) loc))))
      (let ((victim (projectile-victim spell-projectile loc r))
            (entered (and (not (submerged spell-projectile)) (liquid-at (vx loc) (vy loc) (vz loc)))))
        (setf (submerged spell-projectile) (and (liquid-at (vx loc) (vy loc) (vz loc)) T))
        (cond ((and victim (deflects-p victim spell-projectile))
               (deflect victim spell-projectile))
              ((absorbs-p victim spell-projectile)
               (absorb-projectile victim spell-projectile))
              (victim
               (overcharge-breaks-guard (spell spell-projectile) victim
                                        (v- (location victim) (projectile-velocity spell-projectile)))
               ;; Its own effects strike from along its flight; a burst from where it hit.
               (dolist (effect (spell-effects (spell spell-projectile)))
                 (when (and (target-effect-p effect) (= 0 (effect-area effect)))
                   (apply-effect (effect-kind effect) effect victim spell-projectile)))
               (let ((at (impact-point spell-projectile)))
                 (burst-spell (spell spell-projectile) at (caster spell-projectile))
                 (projectile-landed spell-projectile at victim)
                 (impact spell-projectile :at at)))
              ((or entered (solid-overlapping (vx loc) (- (vy loc) r) (vz loc) r (* 2 r)))
               (let ((at (impact-point spell-projectile)))
                 (burst-spell (spell spell-projectile) at (caster spell-projectile))
                 (projectile-landed spell-projectile at NIL)
                 (impact spell-projectile :at at
                                          :water (and entered (liquid-property (liquid-kind entered) :swim)))))
              ((< (projectile-lifetime spell-projectile) (age spell-projectile))
               (despawn spell-projectile)))))))

;;; Circle delivery: a sign glows on the floor around a point for the spell's WINDUP,
;;; an aurora rising round it and a lamp brightening over it, so it shows from
;;; anywhere in the room; then it strikes everything living that stands in it, once
;;; (the effects' AREA is its radius), and its STRIKE-ANIMATION bursts up all over it.
;;; Once cast it goes on by itself: hitting or killing its caster doesn't stop it. Nor
;;; does it spare the caster's allies, only the caster and the undead.

(defparameter *aurora-height* '(0.3 3.2) "Metres a circle's aurora rises from and to as it winds up.")
(defparameter *aurora-light-steps* 10.0
  "Brightness levels an aurora's light is stepped into, as the art's few hard tones are.")
(defparameter *aurora-segments* 128 "Quads round an aurora's ring. Read when the ring is made (a restart).")
(defparameter *circle-draw-in* 0.45 "Fraction of the wind-up a circle's sign takes to draw itself.")
(defparameter *circle-pulse-fps* 8.0)
(defparameter *circle-light-color* (vec 0.5 2.2 0.6) "Its lamp's colour at full strength, just before it strikes.")
(defparameter *circle-light-radius* 7.0)
(defparameter *circle-flash* 2.0 "How much brighter the lamp flashes as the circle strikes.")
(defparameter *circle-linger* 0.8 "Seconds the sign and its light fade after the strike.")
(defparameter *circle-reach-height* 1.0 "Metres above or below the sign that feet can be to be struck.")
(defparameter *strike-rings* '((0.0 1) (0.5 4) (0.9 6))
  "Where the strike bursts up: (FRACTION-OF-RADIUS COUNT) rings, from the middle out.")
(defparameter *strike-ring-delay* 0.06 "Seconds between one ring of the strike and the next.")
(defparameter *harvest-blood* 30 "Drops the strike wrenches up out of each living thing it hits.")

(define-shader-entity upright-fx (fx-sprite) ()
  (:documentation "An effect sprite turned only about +Y, standing upright as a billboard does."))

(define-handler (upright-fx tick :after) ()
  (let ((camera (camera (scene +main+))))
    (when (typep camera 'fps-camera)
      (!qfrom-angle (orientation upright-fx) +vy+ (- (vy (rotation camera)))))))

(defun spawn-standing-fx (name x y z container &key (class 'upright-fx))
  "Play effect animation NAME once, upright, standing on the floor at X Y Z."
  (let* ((animation (find-fx-animation name))
         (sprite (make-instance class :animation animation
                                      :location (vec x (+ y (* 0.5 (animation-size animation))) z))))
    (enter sprite container)
    sprite))

;;; The aurora: a curtain of light standing on a circle's rim like the northern lights:
;;; soft vertical streaks of many heights, drifting and shimmering along it, a bright band
;;; along its foot, its colour wandering through the necromancer's greens round the ring
;;; and deepening toward the top. It is a ring of quads whose vertices are
;;; an angle round the ring and a height up it; the shader sways the upper part (the foot
;;; stays on the rim) and adds its light over what is behind it, writing no depth, so it
;;; needs no sorting against other glows. COLORS gives it another caster's look, and
;;; SPIN and TWIST make its streaks a wind's, running round it and leaning.

(defparameter *grave-aurora-colors*
  (list (vec 0.1 1.0 0.35) (vec 0.5 1.0 0.15) (vec 0.15 0.95 0.65) (vec 0.05 0.55 0.25) (vec 0.8 1.0 0.7))
  "An aurora's colours: the three its foot wanders through round the ring, its top, its band.")

(define-shader-entity aurora (renderable listener)
  ((centre :initarg :centre :reader centre)
   (radius :initarg :radius :reader aurora-radius)
   (colors :initarg :colors :initform *grave-aurora-colors* :reader aurora-colors)
   (spin :initarg :spin :initform 0.0 :reader aurora-spin :documentation "Turns a second its streaks run round the ring.")
   (twist :initarg :twist :initform 0.0 :reader aurora-twist :documentation "Whole turns its streaks lean, foot to top.")
   (arc :initarg :arc :initform pi :accessor aurora-arc
        :documentation "Radians either side of ARC-MIDDLE it stands on: pi for the whole ring, less for an arc.")
   (arc-middle :initarg :arc-middle :initform pi :accessor aurora-arc-middle
               :documentation "Angle round the ring, from +X toward +Z, of its arc's middle.")
   (height :initform (first *aurora-height*) :accessor aurora-height)
   (strength :initform 0.0 :accessor aurora-strength :documentation "0 (none) to 1 (full).")
   (clock :initform (random 100.0) :accessor aurora-clock)))

(defvar *aurora-vao* NIL
  "The ring every aurora draws, shared: one made mid-game would never be loaded onto the
GPU. PRELOAD-SPELLS stages it with the scene.")

(defun aurora-vao ()
  (or *aurora-vao*
      (let* ((n *aurora-segments*)
             (data (make-array (* n 12) :element-type 'single-float))
             (k 0))
        ;; Two triangles a segment, each vertex (fraction of the way round, fraction up).
        (dotimes (i n)
          (let ((a0 (float (/ i n) 0f0)) (a1 (float (/ (1+ i) n) 0f0)))
            (loop for v in (list a0 0f0 a1 0f0 a1 1f0 a0 0f0 a1 1f0 a0 1f0)
                  do (setf (aref data k) v) (incf k))))
        (setf *aurora-vao*
              (make-instance 'vertex-array
                             :vertex-form :triangles
                             :bindings `((,(make-instance 'vertex-buffer :buffer-data data) :size 2 :offset 0 :stride 8 :index 0))
                             :size (* n 6))))))

(defmethod stage :after ((aurora aurora) (area staging-area))
  (stage (aurora-vao) area))

(define-handler (aurora tick) (dt)
  (unless (frozen-p)
    (incf (aurora-clock aurora) dt)))

(defmethod render ((aurora aurora) (program shader-program))
  (when (< 0 (aurora-strength aurora))
    (setf (uniform program "view_matrix") (view-matrix)
          (uniform program "projection_matrix") (projection-matrix)
          (uniform program "centre") (centre aurora)
          (uniform program "radius") (float (aurora-radius aurora) 0f0)
          (uniform program "height") (float (aurora-height aurora) 0f0)
          (uniform program "strength") (float (aurora-strength aurora) 0f0)
          (uniform program "spin") (float (aurora-spin aurora) 0f0)
          (uniform program "twist") (float (aurora-twist aurora) 0f0)
          (uniform program "arc") (float (aurora-arc aurora) 0f0)
          (uniform program "texels_per_metre") *texels-per-metre*
          (uniform program "light_steps") *aurora-light-steps*
          (uniform program "arc_middle") (float (aurora-arc-middle aurora) 0f0)
          (uniform program "time") (float (aurora-clock aurora) 0f0))
    (destructuring-bind (foot-1 foot-2 foot-3 top band) (aurora-colors aurora)
      (setf (uniform program "foot_1") foot-1
            (uniform program "foot_2") foot-2
            (uniform program "foot_3") foot-3
            (uniform program "top_color") top
            (uniform program "band_color") band))
    ;; Light added over what is behind it, seen from outside the ring and from inside.
    (gl:disable :cull-face)
    (gl:depth-mask NIL)
    (gl:blend-func :one :one)
    (render-array (aurora-vao))
    (gl:blend-func :src-alpha :one-minus-src-alpha)
    (gl:depth-mask T)
    (gl:enable :cull-face)))

(define-class-shader (aurora :vertex-shader)
  "layout (location = 0) in vec2 in_ah;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;
uniform vec3 centre;
uniform float radius;
uniform float height;
uniform float time;
uniform float arc;
uniform float arc_middle;
out vec2 v_ah;

void main(){
  // The ring's segments spread over its arc: the whole ring when ARC is pi.
  float a = arc_middle + (in_ah.x - 0.5) * 2.0 * arc;
  // Folds that drift round the ring and sway, growing toward the top: the foot stays
  // on the circle's rim.
  float lean = in_ah.y * in_ah.y;
  float fold = 0.08 * sin(5.0 * a + time * 0.9) + 0.04 * sin(12.0 * a - time * 1.6)
             + 0.08 * sin(3.0 * a + time * 0.7);
  float r = radius * (1.0 + lean * fold);
  vec3 p = centre + vec3(cos(a) * r, in_ah.y * height, sin(a) * r);
  gl_Position = projection_matrix * (view_matrix * vec4(p, 1.0));
  v_ah = in_ah;
}")

(define-class-shader (aurora :fragment-shader)
  "in vec2 v_ah;
uniform float strength;
uniform float spin;
uniform float twist;
uniform float time;
uniform float arc;
uniform float radius;
uniform float height;
uniform float texels_per_metre;
uniform float light_steps;
uniform vec3 foot_1;
uniform vec3 foot_2;
uniform vec3 foot_3;
uniform vec3 top_color;
uniform vec3 band_color;
out vec4 color;

float hash(float n){ return fract(sin(n * 127.1) * 43758.5453); }

// Smooth noise along the ring, repeating every PERIOD cells, so it meets itself.
float ring_noise(float x, float period){
  float i = floor(x);
  float f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(hash(mod(i, period)), hash(mod(i + 1.0, period)), f);
}

void main(){
  // Whole texels of the world's grid round the ring and up it, as the art's pixels are.
  float cols = max(16.0, floor(2.0 * arc * radius * texels_per_metre));
  float rows = max(8.0, floor(height * texels_per_metre));
  vec2 ah = (floor(v_ah * vec2(cols, rows)) + 0.5) / vec2(cols, rows);
  float y = ah.y;
  float u = ah.x + fract(spin * time) + twist * y;
  // Streaks: a broad set and a fine one, sharpened into separate rays, drifting.
  float broad = ring_noise(u * 70.0 + time * 0.8, 70.0);
  float fine = ring_noise(u * 190.0 - time * 1.9, 190.0);
  float streak = 0.75 * pow(broad, 2.5) + 0.6 * pow(fine, 4.0);
  // Each ray has its own height, the tallest the whole curtain, and they rise and fall.
  float top = 0.25 + 0.75 * ring_noise(u * 40.0 + 7.0 + time * 0.35, 40.0);
  float rise = smoothstep(0.0, 0.03, y) * (1.0 - smoothstep(top * 0.3, top, y));
  // The glowing band along its foot.
  float band = exp(-y * 14.0) * (0.45 + 0.55 * broad);
  float light = (streak * rise + 0.7 * band) * strength;
  // An arc fades out toward its ends; a whole ring meets itself.
  if(arc < 3.14) light *= smoothstep(0.0, 0.12, min(ah.x, 1.0 - ah.x));
  // Stepped into a few levels, and its colour into a few hues, not a smooth gradient.
  light = floor(light * light_steps + 0.35) / light_steps;
  // Its colour wanders round the ring through its three foot colours (the necromancer's
  // greens: emerald, acid and sea-green) and deepens toward the top.
  float hue = floor(ring_noise(u * 5.0 + time * 0.12, 5.0) * 4.0 + 0.5) / 2.0;
  vec3 low = hue < 1.0 ? mix(foot_1, foot_2, hue) : mix(foot_2, foot_3, hue - 1.0);
  vec3 c = mix(low, top_color, floor(4.0 * smoothstep(0.25, 0.95, y / max(top, 0.3)) + 0.5) / 4.0);
  c = mix(c, band_color, band * 0.6);
  color = vec4(c * light * 1.3, 1.0);
}")

;;; The nova: a sphere growing from the caster's chest to its reach over *NOVA-GROW-TIME*, striking
;;; each body as it reaches it (SPELL-NOVA). Its look is its element's (*NOVA-STYLES*, NOVA-STYLE):
;;; a dome of aurora curtains (NOVA-DOME, drawn like the grave circle's aurora, its streaks sized in
;;; metres on its surface so that from inside they recede as it grows), shaped by element: fire's
;;; licking flames, frost's hard shards, drain's curtains hanging from the top, force's plain
;;; streaks; shock's is a cage of lightning instead (BOLT-LINE, sparks.lisp). Where the sphere meets
;;; the level and the monsters a bright band runs (NOVA_SWEEP in the lit shaders, greybox.lisp),
;;; and behind it fire leaves a scorch and frost a rime for *NOVA-TRAIL-TIME*. Each element throws
;;; its own particles (sparks.lisp).

(defparameter *nova-radius* 5.0 "Metres a nova reaches round its caster, besides its effects' area,
unless the spell says otherwise (SPELL-NOVA-RADIUS).")

(defun spell-nova-radius (spell)
  "Metres SPELL's nova reaches round its caster, besides its effects' area."
  (or (nova-radius-of spell) *nova-radius*))

(defun spell-element (spell)
  "The element of SPELL's first striking damage effect, or NIL."
  (loop for effect in (spell-effects spell)
        when (and (target-effect-p effect) (eq :damage (effect-kind effect)) (effect-element effect))
          return (effect-element effect)))
(defparameter *nova-grow-time* 0.4 "Seconds a nova takes to grow to its reach.")
(defparameter *nova-start-radius* 0.7 "Metres a nova's sphere starts at.")
(defparameter *nova-trail-time* 1.2 "Seconds a nova's scorch or rime lies after it has grown.")
(defparameter *nova-band-width* 0.12 "Metres of the band where a nova's sphere meets the level.")
(defparameter *nova-crackle* 0.035 "Seconds between a shock nova's lightning drawn anew.")
(defparameter *nova-cage-bolts* 40 "Bolts in a shock nova's cage.")
(defparameter *nova-camera-shake* 0.3 "How hard a nova the player casts kicks the view.")

(defun nova-hex (hex)
  (vec (/ (parse-integer hex :start 0 :end 2 :radix 16) 255.0)
       (/ (parse-integer hex :start 2 :end 4 :radix 16) 255.0)
       (/ (parse-integer hex :start 4 :end 6 :radix 16) 255.0)))

(defparameter *nova-styles*
  (loop for (name code colors band ramp)
          in '((:force 0 ("94bdfe" "c58bfd" "73daea" "4663c4" "efc9fc") "b48cff" :ward)
               (:fire 1 ("fb6403" "fcb918" "fe901f" "ac0f07" "fceab6") "ff8020" :fire)
               (:frost 2 ("a9d4fa" "94bdfe" "73daea" "254670" "deebfd") "8ccdff" :frost)
               (:shock 3 ("f8ec3b" "f8e87c" "fceab6" "8d6b24" "f9f9f3") "fff259" :shock)
               (:drain 4 ("f52a5a" "f98497" "ce326c" "490404" "feccd4") "f52a5a" :drain))
        collect (list name code (mapcar #'nova-hex colors) (nova-hex band) ramp))
  "Per look: its name, the dome shader's style, the dome's colours (three for its foot, its top,
its band, as an aurora's), the band's colour and the spark ramp of its particles.")

(defun nova-style (spell)
  "SPELL's nova look: its first damage effect's element, else :DRAIN for a drain, else :FORCE."
  (let ((damage (find :damage (spell-effects spell) :key #'effect-kind)))
    (cond ((and damage (member (effect-element damage) '(:fire :frost :shock))) (effect-element damage))
          ((find :drain (spell-effects spell) :key #'effect-kind) :drain)
          (T :force))))

(defun nova-slowed-p (spell)
  (and (find :slow (spell-effects spell) :key #'effect-kind) T))

;; The newest nova draws the band and its trail; the lit shaders read these (greybox.lisp).
(defvar *newest-nova* NIL)

(define-shader-entity nova-dome (renderable listener)
  ((centre :initarg :centre :initform (vec 0 0 0) :reader centre)
   (floor-y :initform 0.0 :accessor dome-floor)
   (radius :initform 0.0 :accessor dome-radius)
   (strength :initform 0.0 :accessor dome-strength)
   (colors :initform (third (first *nova-styles*)) :accessor dome-colors)
   (style :initform 0 :accessor dome-style)
   (clock :initform 0.0 :accessor dome-clock)))

(defvar *nova-dome-vao* NIL
  "The sphere every nova's dome draws, shared, as the aurora's ring is; PRELOAD-SPELLS stages it.")

(defun nova-dome-vao ()
  (or *nova-dome-vao*
      (let* ((slices 96) (stacks 48)
             (data (make-array (* slices stacks 12) :element-type 'single-float))
             (k 0))
        ;; Two triangles a cell, each vertex (fraction round, fraction up).
        (dotimes (i slices)
          (dotimes (j stacks)
            (let ((u0 (float (/ i slices) 0f0)) (u1 (float (/ (1+ i) slices) 0f0))
                  (v0 (float (/ j stacks) 0f0)) (v1 (float (/ (1+ j) stacks) 0f0)))
              (loop for v in (list u0 v0 u1 v0 u1 v1 u0 v0 u1 v1 u0 v1)
                    do (setf (aref data k) v) (incf k)))))
        (setf *nova-dome-vao*
              (make-instance 'vertex-array
                             :vertex-form :triangles
                             :bindings `((,(make-instance 'vertex-buffer :buffer-data data) :size 2 :offset 0 :stride 8 :index 0))
                             :size (* slices stacks 6))))))

(defmethod stage :after ((dome nova-dome) (area staging-area))
  (stage (nova-dome-vao) area))

(defmethod render ((dome nova-dome) (program shader-program))
  (when (and (< 0 (dome-strength dome)) (< 0 (dome-radius dome)))
    (setf (uniform program "view_matrix") (view-matrix)
          (uniform program "projection_matrix") (projection-matrix)
          (uniform program "centre") (centre dome)
          (uniform program "radius") (float (dome-radius dome) 0f0)
          (uniform program "floor_y") (float (dome-floor dome) 0f0)
          (uniform program "strength") (float (dome-strength dome) 0f0)
          (uniform program "texels_per_metre") *texels-per-metre*
          (uniform program "light_steps") *aurora-light-steps*
          (uniform program "time") (float (dome-clock dome) 0f0)
          (uniform program "style") (dome-style dome))
    (destructuring-bind (foot-1 foot-2 foot-3 top band) (dome-colors dome)
      (setf (uniform program "foot_1") foot-1
            (uniform program "foot_2") foot-2
            (uniform program "foot_3") foot-3
            (uniform program "top_color") top
            (uniform program "band_color") band))
    ;; Light added over what is behind it, seen from inside and out, as the aurora's.
    (gl:disable :cull-face)
    (gl:depth-mask NIL)
    (gl:blend-func :one :one)
    (render-array (nova-dome-vao))
    (gl:blend-func :src-alpha :one-minus-src-alpha)
    (gl:depth-mask T)
    (gl:enable :cull-face)))

(define-class-shader (nova-dome :vertex-shader)
  "layout (location = 0) in vec2 in_uv;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;
uniform vec3 centre;
uniform float radius;
out vec3 v_world;

void main(){
  float a = in_uv.x * 6.2831853;
  float b = (in_uv.y - 0.5) * 3.1415927;
  vec3 p = centre + radius * vec3(cos(b) * cos(a), sin(b), cos(b) * sin(a));
  v_world = p;
  gl_Position = projection_matrix * (view_matrix * vec4(p, 1.0));
}")

(define-class-shader (nova-dome :fragment-shader)
  "in vec3 v_world;
uniform vec3 centre;
uniform float radius;
uniform float floor_y;
uniform float strength;
uniform float time;
uniform int style;
uniform float texels_per_metre;
uniform float light_steps;
uniform vec3 foot_1;
uniform vec3 foot_2;
uniform vec3 foot_3;
uniform vec3 top_color;
uniform vec3 band_color;
out vec4 color;

float hash(float n){ return fract(sin(n * 127.1) * 43758.5453); }
float hash2(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

// Smooth noise along the ring, repeating every PERIOD cells, so it meets itself.
float ring_noise(float x, float period){
  float i = floor(x);
  float f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(hash(mod(i, period)), hash(mod(i + 1.0, period)), f);
}

void main(){
  vec3 d = v_world - centre;
  // Round the dome and up it from the floor, in whole texels of the world's grid.
  float circ = 6.2831853 * radius;
  float cols = max(16.0, floor(circ * texels_per_metre));
  float u = (floor((atan(d.z, d.x) / 6.2831853 + 0.5) * cols) + 0.5) / cols;
  float tall = centre.y + radius - floor_y;
  float ym = (floor((v_world.y - floor_y) * texels_per_metre) + 0.5) / texels_per_metre;
  float y = clamp(ym / tall, 0.0, 1.0);
  // Fire's streaks sway across as they climb, the sway rising up them.
  if(style == 1) u += 0.18 * sin(ym * 7.0 - time * 14.0 + floor(u * circ * 1.5) * 2.1) / circ;
  // Streaks a set width in metres: more of them round a bigger dome, so they recede as it grows.
  float pb = max(8.0, floor(circ * 4.5));
  float pf = max(8.0, floor(circ * 12.0));
  float pt = max(8.0, floor(circ * 2.5));
  float speed = 1.0;
  if(style == 2) speed = 0.1;
  if(style == 1) speed = 1.8;
  float broad = ring_noise(u * pb + time * 0.8 * speed, pb);
  float fine = ring_noise(u * pf - time * 1.9 * speed, pf);
  float streak = 0.75 * pow(broad, 2.5) + 0.6 * pow(fine, 4.0);
  float top = 0.3 + 0.7 * ring_noise(u * pt + 7.0 + time * 0.35 * speed, pt);
  // Drain's curtains hang from the top instead of rising from the floor.
  float yr = y;
  if(style == 4) yr = 1.0 - y;
  float rise;
  if(style == 2){
    // Frost: hard shards, each a tooth narrowing to a point, flat-coloured, not streaked.
    float cell = u * pb * 0.5;
    float k = hash(mod(floor(cell), pb));
    float x = fract(cell);
    float tip = (0.25 + 0.75 * k) * (1.0 - 2.0 * abs(x - 0.5));
    streak = step(0.35, k) * (0.55 + 0.45 * step(0.5, x));
    rise = smoothstep(0.0, 0.03, y) * step(y, tip);
  } else {
    rise = smoothstep(0.0, 0.03, yr) * (1.0 - smoothstep(top * 0.3, top, yr));
  }
  if(style == 1){
    // Flame: pulses climb each streak, and its top tears into ragged tongues.
    streak *= 0.55 + 0.45 * ring_noise(ym * 6.0 - time * 9.0 + u * pb, 1000.0);
    float tear = hash2(vec2(u * cols, ym * texels_per_metre + floor(time * 12.0)));
    rise *= 1.0 - step(top * 0.5, y) * step(tear, (y - top * 0.5) / (top * 0.5));
  }
  float band = exp(-y * 10.0) * (0.45 + 0.55 * broad);
  float light = (streak * rise + 0.7 * band) * strength;
  // Stepped into a few levels, and its colour into a few hues, as the aurora's.
  light = floor(light * light_steps + 0.35) / light_steps;
  float hue = floor(ring_noise(u * 5.0 + time * 0.12, 5.0) * 4.0 + 0.5) / 2.0;
  vec3 low = hue < 1.0 ? mix(foot_1, foot_2, hue) : mix(foot_2, foot_3, hue - 1.0);
  vec3 c = mix(low, top_color, floor(4.0 * smoothstep(0.25, 0.95, yr / max(top, 0.3)) + 0.5) / 4.0);
  c = mix(c, band_color, band * 0.6);
  color = vec4(c * light * 1.3, 1.0);
}")

(define-shader-entity spell-nova (fx-sprite)
  ((spell :initarg :spell :reader spell)
   (caster :initarg :caster :initform NIL :reader caster)
   (centre :initarg :centre :reader centre :documentation "Where it bursts from: the caster's chest.")
   (floor-y :initarg :floor-y :initform 0.0 :accessor nova-floor)
   (reach :initarg :reach :initform 2.0 :accessor nova-reach)
   (victims :initarg :victims :initform () :accessor nova-victims
            :documentation "(body distance) for each body it is yet to reach, nearest first.")
   (struck :initform () :accessor nova-struck
           :documentation "(body . age) for each body it has struck, for shock's arcs.")
   (dome :initform NIL :accessor nova-dome)
   (started :initform NIL :accessor nova-started)
   (crackle :initform 0.0 :accessor nova-crackle)
   (emit :initform 0.0 :accessor nova-emit :documentation "Particles owed, a fraction carried over.")))

;; All that shows of it is its dome, its band, its lightning and its particles.
(defmethod render :around ((nova spell-nova) (program shader-program)))

(defun nova-distance (centre body)
  "Metres from CENTRE to the nearest point of BODY's upright cylinder."
  (let* ((f (body-feet body))
         (dx (- (vx f) (vx centre))) (dz (- (vz f) (vz centre)))
         (across (max 0.0 (- (sqrt (+ (* dx dx) (* dz dz))) (body-radius body))))
         (y (vy centre)) (top (+ (vy f) (body-height body)))
         (up (cond ((< y (vy f)) (- (vy f) y)) ((< top y) (- y top)) (T 0.0))))
    (sqrt (+ (* across across) (* up up)))))

(defun place-nova (spell origin container caster)
  "Burst SPELL round ORIGIN for CASTER: its sphere grows from there and strikes what it reaches."
  (let* ((reach (+ (spell-nova-radius spell) (spell-burst-radius spell)))
         (victims (sort (mapcar (lambda (body) (list body (nova-distance origin body)))
                                (burst-victims origin reach caster))
                        #'< :key #'second))
         (floor (and *nav-grid* (nav-floor-at (vx origin) (vy origin) (vz origin))))
         (nova (make-instance 'spell-nova :spell spell :caster caster :centre (vcopy origin)
                                          :location (vcopy origin) :reach reach :victims victims
                                          :floor-y (or floor (- (vy origin) 1.0))
                                          :animation (find-fx-animation 'ogre-dust))))
    (enter nova container)
    (let ((element (spell-element spell)))
      (when element
        (strike-skins element origin reach caster)))
    (play-sound (spell-sound spell :impact) origin)
    (when (eq caster *player*)
      (kick-camera *nova-camera-shake*))
    nova))

(defun nova-radius-at (nova age)
  "How far NOVA's sphere has grown AGE seconds after it burst."
  (let* ((reach (nova-reach nova))
         (r0 (min *nova-start-radius* (* 0.5 reach)))
         (tt (min 1.0 (/ age *nova-grow-time*))))
    (+ r0 (* (- reach r0) (- 1.0 (expt (- 1.0 tt) 2))))))

(defun start-nova (nova)
  "Give NOVA its dome, unless it is shock's, which is lightning."
  (setf *newest-nova* nova)
  (destructuring-bind (code colors band ramp) (rest (assoc (nova-style (spell nova)) *nova-styles*))
    (declare (ignore band ramp))
    (unless (= code 3)
      (let ((dome (make-instance 'nova-dome :centre (vcopy (centre nova)))))
        (setf (dome-colors dome) colors
              (dome-style dome) code
              (dome-floor dome) (nova-floor nova))
        (enter dome (container nova))
        (setf (nova-dome nova) dome)))))

(defun nova-strike-body (nova body distance)
  (let* ((spell (spell nova))
         (origin (centre nova))
         (source (make-instance 'strike :spell spell :caster (caster nova) :origin origin)))
    (overcharge-breaks-guard spell body origin)
    (dolist (effect (spell-effects spell))
      (when (and (target-effect-p effect) (<= distance (+ (spell-nova-radius spell) (effect-area effect) 0.05)))
        (apply-effect (effect-kind effect) effect body source)))
    (push (cons body (age nova)) (nova-struck nova))
    (let ((chest (vec (vx (body-feet body)) (+ (vy (body-feet body)) (* 0.55 (body-height body))) (vz (body-feet body)))))
      (case (nova-style spell)
        (:shock (spray-sparks chest (v- origin chest) 8 :ramp :shock))
        (:drain
         ;; Motes stream back from the wound toward the caster.
         (when (caster nova)
           (spray-sparks chest (v- (body-feet (caster nova)) (body-feet body)) 10 :kind :ember :ramp :drain
                         :speed '(2.5 4.5) :spread 0.35)))))))

(defun random-on-sphere (c r floor-y &optional toward)
  "A point on the sphere round C of radius R above FLOOR-Y and not in rock; with TOWARD, a unit
vec, most of them on its side (the view's: the rest is unseen). NIL if none is found soon."
  (loop repeat 6
        do (let* ((yaw (if (and toward (< (random 1.0) 0.7))
                           (+ (atan (vz toward) (vx toward)) (- (random 2.2) 1.1))
                           (random #.(float (* 2 pi) 0f0))))
                  (z (- (random 1.8) 0.8)) (s (sqrt (- 1 (* z z))))
                  (x (+ (vx c) (* r s (cos yaw)))) (y (+ (vy c) (* r z))) (zz (+ (vz c) (* r s (sin yaw)))))
             (when (and (< (+ floor-y 0.05) y) (not (solid-at x y zz)))
               (return (vec x y zz))))))

(defun random-on-floor-ring (c r floor-y)
  "A point on the floor where the sphere round C of radius R meets it, not in rock, or NIL."
  (let ((h (- (vy c) floor-y)))
    (when (< h r)
      (let ((across (sqrt (- (* r r) (* h h)))))
        (loop repeat 6
              do (let* ((a (random #.(float (* 2 pi) 0f0)))
                        (x (+ (vx c) (* across (cos a)))) (z (+ (vz c) (* across (sin a)))))
                   (unless (solid-at x (+ floor-y 0.1) z)
                     (return (vec x (+ floor-y 0.05) z)))))))))

(defparameter *nova-particles*
  '((:force (:ring :grit :dust 60))
    (:fire (:ring :ember :fire 40) (:dome :ember :fire 60))
    (:frost (:dome :flake :frost 90) (:ring :grit :frost 25))
    (:shock (:ring :spark :shock 40))
    (:drain (:dome :flake :drain 30)))
  "Per look, what its sphere throws while it grows, a second: from where it meets the floor (:RING)
or its surface (:DOME), of what kind (:FLAKE an ember that sinks) and ramp, how many.")

(defun emit-nova-particles (nova r dt)
  (let* ((spell (spell nova)) (c (centre nova)) (floor-y (nova-floor nova))
         (look (and *player* (look-direction *player*)))
         (sets (rest (assoc (nova-style spell) *nova-particles*))))
    (when (nova-slowed-p spell)
      (push '(:dome :flake :dust 30) sets))
    (dolist (set sets)
      (destructuring-bind (where kind ramp rate) set
        (multiple-value-bind (count rest) (floor (+ (nova-emit nova) (* rate dt)))
          (setf (nova-emit nova) rest)
          (dotimes (i count)
            (let ((p (if (eq where :ring) (random-on-floor-ring c r floor-y) (random-on-sphere c r floor-y look))))
              ;; Not at the eye, where one is a great square.
              (when (and p (or (null *player*) (< 1.8 (vdistance p (location *player*)))))
                (ecase kind
                  (:grit (spray-sparks p NIL 2 :kind :grit :ramp ramp))
                  (:ember (spray-sparks p NIL 1 :kind :ember :ramp ramp :speed '(0.6 1.4)))
                  (:flake (spray-sparks p (vec 0 -1 0) 1 :kind :ember :ramp ramp :speed '(0.25 0.6) :spread 0.3))
                  (:spark (spray-sparks p (vec (- (vx p) (vx c)) 1.0 (- (vz p) (vz c))) 3 :ramp ramp
                                                                                     :speed '(3.0 6.0))))))))))))

(defun nova-lightning (nova r breakup cage)
  "Draw NOVA's lightning anew: with CAGE its cage, BREAKUP (0 to 1) of it broken off; and the arcs
at what it struck."
  (let* ((c (centre nova)) (floor-y (nova-floor nova)) (sphere (list c r))
         (look (and *player* (look-direction *player*)))
         (life (* 1.4 *nova-crackle*)))
    (dotimes (i (if cage *nova-cage-bolts* 0))
      (let ((p (random-on-sphere c r floor-y look))
            (q (random-on-sphere c r floor-y look)))
        ;; A bolt runs at most a third of the way round.
        (when (and p q (< (vdistance p q) (* 1.2 r)))
          (bolt-line (vx p) (vy p) (vz p) (vx q) (vy q) (vz q) 5 :sphere sphere :branch 0.5 :drop breakup :life life))))
    (loop for (body . at) in (nova-struck nova)
          for since = (- (age nova) at)
          when (< since 0.15)
            do (let* ((f (body-feet body)) (h (body-height body)) (rr (* 0.8 (body-radius body)))
                      (cx (vx f)) (cy (+ (vy f) (* 0.55 h))) (cz (vz f)))
                 ;; A bolt in from the cage at first, then bolts crawling round its body.
                 (when (< since *nova-crackle*)
                   (let* ((dx (- cx (vx c))) (dy (- cy (vy c))) (dz (- cz (vz c)))
                          (len (max 0.01 (sqrt (+ (* dx dx) (* dy dy) (* dz dz)))))
                          (k (/ (max 0.6 (- len 1.4)) len)))
                     (bolt-line (+ (vx c) (* k dx)) (+ (vy c) (* k dy)) (+ (vz c) (* k dz)) cx cy cz 4
                                :roughness 0.22 :branch 0.3 :white 0.4 :life life)))
                 (dotimes (j 5)
                   (let ((a (random #.(float (* 2 pi) 0f0))) (b (+ (random #.(float (* 2 pi) 0f0)))))
                     (bolt-line (+ cx (* rr (cos a))) (+ (vy f) (* h (+ 0.15 (random 0.7)))) (+ cz (* rr (sin a)))
                                (+ cx (* rr (cos b))) (+ (vy f) (* h (+ 0.15 (random 0.7)))) (+ cz (* rr (sin b)))
                                4 :roughness 0.25 :white 0.3 :life life)))
                 ;; And on to the nearest other creature within 3.5 m, chaining.
                 (when (< since 0.07)
                   (let ((next (loop for o across *creatures*
                                     when (and (not (eq o body)) (not (dead o))
                                               (< 0.5 (vdistance (location o) f) 3.5))
                                       return o)))
                     (when next
                       (let ((nl (location next)))
                         (bolt-line cx cy cz (vx nl) (+ (vy nl) (* 0.55 (sprite-height next))) (vz nl) 4
                                    :branch 0.25 :life life)))))))))

(defun nova-trail (nova)
  "How strong NOVA's scorch or rime is: rising as it grows, fading over *NOVA-TRAIL-TIME* after."
  (let ((age (age nova)))
    (if (< age *nova-grow-time*)
        (min 1.0 (* 3 (/ age *nova-grow-time*)))
        (max 0.0 (- 1.0 (/ (- age *nova-grow-time*) *nova-trail-time*))))))

(defun show-nova-sweep (nova r live)
  "Set the band and trail the lit shaders draw to NOVA's."
  (destructuring-bind (code colors band ramp) (rest (assoc (nova-style (spell nova)) *nova-styles*))
    (declare (ignore colors ramp))
    (v<- *nova-sweep-centre* (centre nova))
    (v<- *nova-sweep-color* band)
    (setf *nova-sweep-style* code
          *nova-sweep-radius* (float r 0f0)
          *nova-sweep-width* (if live *nova-band-width* 0.0)
          *nova-sweep-trail* (if (member code '(1 2)) (nova-trail nova) 0.0))))

(define-handler (spell-nova tick) (dt)
  (when (and (container spell-nova) (not (nova-started spell-nova)))
    (setf (nova-started spell-nova) T)
    (start-nova spell-nova))
  (unless (frozen-p)
    (let* ((age (incf (age spell-nova) dt))
           (live (< age *nova-grow-time*))
           (r (nova-radius-at spell-nova age))
           (spell (spell spell-nova))
           (dome (nova-dome spell-nova)))
      ;; What it reaches, it strikes.
      (loop while (and (nova-victims spell-nova) (<= (second (first (nova-victims spell-nova))) r))
            do (destructuring-bind (body distance) (pop (nova-victims spell-nova))
                 (when (or (eq body *player*) (not (dead body)))
                   (nova-strike-body spell-nova body distance))))
      (when dome
        (v<- (centre dome) (centre spell-nova))
        (setf (dome-radius dome) r
              (dome-strength dome) (if live (expt (- 1.0 (/ age *nova-grow-time*)) 1.3) 0.0)
              (dome-clock dome) (* age (if (nova-slowed-p spell) 0.5 1.0))))
      (when live
        (emit-nova-particles spell-nova r dt))
      (when (and (eq (nova-style spell) :shock)
                 (or live (some (lambda (s) (< (- age (cdr s)) 0.15)) (nova-struck spell-nova)))
                 (<= (decf (nova-crackle spell-nova) dt) 0))
        (setf (nova-crackle spell-nova) *nova-crackle*)
        (nova-lightning spell-nova r (max 0.0 (/ (- (/ age *nova-grow-time*) 0.45) 0.55)) live))
      (when (eq *newest-nova* spell-nova)
        (show-nova-sweep spell-nova (nova-reach spell-nova) live)
        (when live (setf *nova-sweep-radius* (float r 0f0))))
      (when (< (+ *nova-grow-time* *nova-trail-time*) age)
        (despawn spell-nova)))))

(defmethod leave :after ((nova spell-nova) container)
  (when (nova-dome nova)
    (despawn (nova-dome nova))
    (setf (nova-dome nova) NIL))
  (when (eq *newest-nova* nova)
    (setf *newest-nova* NIL *nova-sweep-radius* 0.0 *nova-sweep-trail* 0.0)))

(define-shader-entity spell-circle (fx-sprite)
  ((spell :initarg :spell :reader spell)
   (caster :initarg :caster :initform NIL :reader caster)
   (centre :initarg :centre :reader centre :documentation "The point on the floor it is drawn round.")
   (aurora :initform NIL :accessor circle-aurora)
   (lamp :initform NIL :accessor circle-lamp)
   (struck :initform NIL :accessor struck :documentation "Seconds since it struck, or NIL.")
   (rings-left :initform () :accessor rings-left :documentation "Rings of the strike yet to burst.")
   (sound :initform NIL :accessor circle-sound :documentation "Its loop through the wind-up.")))

(defun circle-radius (spell)
  (reduce #'max (spell-effects spell) :key #'effect-area :initial-value 0))

(defmethod initialize-instance :after ((circle spell-circle) &key)
  ;; Flat on the floor, facing up, just off it. Drawn for a radius of the strip's
  ;; :RADIUS metres (tools/draw_grave_circle.py), scaled to the spell's.
  (let* ((atlas (animation-atlas (sprite-animation circle)))
         (k (/ (circle-radius (spell circle)) (getf atlas :radius 2.5))))
    (nv* (scaling circle) (float k 0f0)))
  (!qfrom-angle (orientation circle) +vx+ #.(float (- (/ pi 2)) 0f0))
  (incf (vy (location circle)) 0.01))

(defmethod effect-origin ((source spell-circle)) (centre source))

(defmethod effect-direction ((source spell-circle) target)
  (v- (if (typep target 'creature) (location target) (feet target)) (centre source)))

;; It comes up from the floor, under any shield.
(defmethod effect-unblockable-p ((source spell-circle)) T)

(defun circle-strength (circle)
  "How bright CIRCLE's light is: rising through the wind-up, a flash as it strikes,
then fading."
  (let ((struck (struck circle)))
    (if struck
        (* (+ 1 *circle-flash*) (max 0.0 (- 1 (/ struck *circle-linger*))))
        (expt (min 1.0 (/ (age circle) (spell-windup (spell circle)))) 1.5))))

(defun light-circle (circle)
  "Raise CIRCLE's aurora and lamp, the first time it ticks in the scene."
  (let ((c (centre circle)))
    (setf (circle-sound circle) (start-loop (spell-sound (spell circle) :circle) c))
    (setf (circle-aurora circle) (make-instance 'aurora :centre c :radius (circle-radius (spell circle))))
    (enter (circle-aurora circle) (container circle))
    (setf (circle-lamp circle)
          (add-lamp (vec (vx c) (+ (vy c) 0.8) (vz c)) *circle-light-color* *circle-light-radius*
                    :flicker 0.15))))

(defun drop-aurora (circle)
  (when (circle-aurora circle)
    (despawn (circle-aurora circle))
    (setf (circle-aurora circle) NIL)))

(defun drop-circle-light (circle)
  (drop-aurora circle)
  (when (circle-lamp circle)
    (remove-lamp (circle-lamp circle))
    (setf (circle-lamp circle) NIL)))

;; A reset or rebuild takes the circle away before it is done.
(defmethod leave :after ((circle spell-circle) container)
  (setf (circle-sound circle) (stop-loop (circle-sound circle)))
  (drop-circle-light circle))

(defun in-circle-p (circle point radius)
  "True if feet at POINT, of a body RADIUS wide, stand in CIRCLE."
  (let* ((c (centre circle))
         (r (+ (circle-radius (spell circle)) (* 0.5 radius)))
         (dx (- (vx point) (vx c)))
         (dz (- (vz point) (vz c))))
    (and (< (+ (* dx dx) (* dz dz)) (* r r))
         (< (abs (- (vy point) (vy c))) *circle-reach-height*))))

(defun harvest (at height)
  "Wrench blood straight up out of something struck, standing at AT, HEIGHT tall."
  (spray-blood (vec (vx at) (+ (vy at) (* 0.5 height)) (vz at)) 0.0 0.0 *harvest-blood*
               :speed '(0.3 1.5) :rise '(1.2 1.5) :lift 5.0))

(defun strike-circle (circle)
  "CIRCLE strikes: everything living in it takes the spell, and the strike's first ring bursts up."
  (let ((spell (spell circle))
        (caster (caster circle)))
    (setf (struck circle) 0.0
          (rings-left circle) *strike-rings*
          (circle-sound circle) (stop-loop (circle-sound circle)))
    (play-sound (spell-sound spell :strike) (centre circle))
    (drop-aurora circle)
    (loop for c across *creatures*
          when (and (not (dead c)) (not (undead c)) (not (eq c caster))
                    (in-circle-p circle (location c) (body-radius c)))
            do (when (bleeds c) (harvest (location c) (sprite-height c)))
               (apply-spell spell c circle))
    (when (and *player* (< 0 (health *player*)) (in-circle-p circle (feet *player*) *player-radius*))
      (harvest (feet *player*) *player-height*)
      (apply-spell spell *player* circle))))

(defun burst-ring (circle ring)
  (destructuring-bind (fraction count) ring
    (let* ((c (centre circle))
           (r (* fraction (circle-radius (spell circle))))
           (turn (random (float (* 2 pi) 0f0))))
      (dotimes (k count)
        (let* ((a (+ turn (* k (/ (* 2 pi) count))))
               ;; A little scatter, so the rings don't look drawn with a compass.
               (rr (+ r (if (< 0 r) (- (random 0.3) 0.15) 0.0))))
          (spawn-standing-fx (strike-animation (spell circle)) (+ (vx c) (* rr (cos a))) (vy c)
                             (+ (vz c) (* rr (sin a))) (container circle)))))))

(defun sign-frame (age windup count)
  "The frame of a strip of COUNT, frames drawing a sign in and then a pulsing loop of 4, to
show AGE seconds into a wind-up of WINDUP."
  (let ((draw-in (- count 4))
        (progress (/ age (* *circle-draw-in* windup))))
    (if (< progress 1)
        (min (1- draw-in) (floor (* progress draw-in)))
        (+ draw-in (mod (floor (* age *circle-pulse-fps*)) 4)))))

;; Its own tick, not FX-SPRITE's: the frame follows the wind-up, and it lies flat.
(define-handler (spell-circle tick) (dt)
  (let* ((spell (spell spell-circle))
         (windup (spell-windup spell))
         (atlas (animation-atlas (sprite-animation spell-circle)))
         (count (getf atlas :frames)))
    (when (and (null (circle-lamp spell-circle)) (null (struck spell-circle)) (container spell-circle))
      (light-circle spell-circle))
    (unless (frozen-p)
      (incf (age spell-circle) dt)
      (let ((struck (struck spell-circle)))
        (cond (struck
               (setf struck (+ struck dt)
                     (struck spell-circle) struck)
               (let ((ring (first (rings-left spell-circle))))
                 (when (and ring (<= (* *strike-ring-delay* (- (length *strike-rings*) (length (rings-left spell-circle))))
                                     struck))
                   (burst-ring spell-circle ring)
                   (pop (rings-left spell-circle))))
               (when (< *circle-linger* struck)
                 (despawn spell-circle)))
              ((<= windup (age spell-circle))
               (strike-circle spell-circle)
               (burst-ring spell-circle (pop (rings-left spell-circle)))))))
    ;; The sign draws itself in, then pulses.
    (strip-uv (frame-uv spell-circle) atlas (sign-frame (age spell-circle) windup count) count)
    ;; The aurora rises and brightens, and so does the lamp.
    (let ((k (circle-strength spell-circle))
          (lamp (circle-lamp spell-circle))
          (aurora (circle-aurora spell-circle)))
      (when aurora
        (raise-aurora aurora (age spell-circle) windup k))
      (when lamp
        (let ((color (color lamp)))
          (setf (vx color) (* k (vx *circle-light-color*))
                (vy color) (* k (vy *circle-light-color*))
                (vz color) (* k (vz *circle-light-color*))))))))

(defun raise-aurora (aurora age windup k)
  "Bring AURORA up, AGE seconds into a wind-up of WINDUP, as bright as a lamp at K of its full."
  (destructuring-bind (low high) *aurora-height*
    (setf (aurora-height aurora) (+ low (* (- high low) (min 1.0 (/ age (* 0.8 windup)))))
          (aurora-strength aurora) (min 1.0 (* 1.6 k)))))

(defun place-circle (spell centre container caster)
  "Draw SPELL's circle on the floor round point CENTRE for CASTER."
  (let ((circle (make-instance 'spell-circle :spell spell :caster caster :centre (vcopy centre)
                                             :location (vcopy centre)
                                             :animation (find-fx-animation (circle-animation spell)))))
    (enter circle container)
    circle))

;;; Seeker delivery: a projectile that, as it leaves, picks the creature nearest the
;;; crosshair and turns after it (STEER), so a strafing target is still hit. With no creature
;;; in its cone it flies straight. A shield that turns it aside ends the homing, as a skull's.

(defun seeker-mark (origin direction caster)
  "The live creature nearest to unit vector DIRECTION from ORIGIN, within *SEEKER-CONE* and
*SEEKER-RANGE* and in sight, that CASTER may strike; NIL if none."
  (let ((best NIL) (best-angle 0.0))
    (loop for c across *creatures*
          unless (or (dead c) (eq c caster) (and caster (spares-p caster c)) (calm-p c))
            do (let* ((feet (body-feet c))
                      (dx (- (vx feet) (vx origin)))
                      (dy (- (+ (vy feet) (aim-height c)) (vy origin)))
                      (dz (- (vz feet) (vz origin)))
                      (d (sqrt (+ (* dx dx) (* dy dy) (* dz dz)))))
                 (when (< 0.1 d *seeker-range*)
                   (let ((angle (acos (max -1.0 (min 1.0 (/ (+ (* dx (vx direction)) (* dy (vy direction))
                                                               (* dz (vz direction)))
                                                            d))))))
                     (when (and (< angle *seeker-cone*) (or (null best) (< angle best-angle))
                                (clear-path-p origin feet (- (+ (vy feet) (aim-height c)) (vy origin))))
                       (setf best c best-angle angle))))))
    best))

;;; Beam delivery: no flight at all. The spell strikes the first body or wall along the aim
;;; within *BEAM-RANGE*, at once, and a ribbon of its light shows from the hands to there
;;; (BEAM). A shield that covers it stops it, turning nothing back. The player holds a beam
;;; rather than casting it (HOLD-BEAM, player.lisp): it strikes every *BEAM-PULSE* with a
;;; share of its effects (PULSE-SPELL) for the same share of its mana, *BEAM-CAST-TIME* of it
;;; doing and costing what one cast would.

(defparameter *beam-range* 12.0 "Metres a beam reaches.")
(defparameter *beam-step* 0.1 "Metres between the points a beam is tested at.")
(defparameter *beam-reach* 0.2 "Metres from the beam within which it strikes a creature's body.")
(defparameter *beam-time* 0.18 "Seconds a beam's light lingers.")
(defparameter *beam-width* 0.07 "Metres from a beam's middle to the edge of its ribbon.")
(defparameter *beam-cast-time* 0.5
  "Seconds of holding a beam that do and cost what one cast of its spell would.")
(defparameter *beam-pulse* 0.25 "Seconds between a held beam's strikes.")

(defun beam-pulse-share () (/ *beam-pulse* *beam-cast-time*))

(defun beam-mana-rate (spell)
  "Mana a second a held beam of SPELL takes, rounded for showing."
  (round (spell-cost spell) *beam-cast-time*))

(defun beam-stamina-rate (spell)
  "Stamina a second a held beam of SPELL takes, rounded for showing."
  (round (spell-stamina spell) *beam-cast-time*))

(defun pulse-spell (spell &key (pain-bonus (spell-pain-bonus spell)))
  "A copy of SPELL whose instant effects hold BEAM-PULSE-SHARE of its magnitudes, for one strike of
a held beam: its effects over time and statuses are whole, since a strike only renews them."
  (let* ((k (beam-pulse-share))
         (pulse (spec-spell
                 (destructuring-bind (name delivery &rest effects) (spell-spec spell)
                   (list* name delivery
                          (loop for e in effects
                                for timing = (kind-property (getf e :kind) :timing :status)
                                collect (if (or (eq timing :instant)
                                                (and (eq timing :over-time) (= 0 (getf e :duration))))
                                            (let ((m (getf e :magnitude)))
                                              (list* :magnitude (list (max 1 (round (* k (first m))))
                                                                      (max 1 (round (* k (second m)))))
                                                     e))
                                            e)))))))
    (setf (slot-value pulse 'pain-bonus) pain-bonus)
    pulse))

(defun beam-end (origin direction caster)
  "Where a beam from ORIGIN along unit vector DIRECTION stops, and the body it reached there (a
creature, or the player when CASTER is anyone else) or NIL."
  (let ((point (vcopy origin))
        (r 0.04)
        (wet (liquid-at (vx origin) (vy origin) (vz origin)))
        (player (and *player* (not (eq caster *player*)) (< 0 (health *player*)) *player*)))
    (loop repeat (ceiling *beam-range* *beam-step*)
          do (nv+* point direction *beam-step*)
             (let ((victim (or (creature-at point *beam-reach* caster)
                               (and player (player-at-p player point *beam-reach*) player))))
               (when victim
                 (return-from beam-end (values point victim))))
             (when (or (solid-overlapping (vx point) (- (vy point) r) (vz point) r (* 2 r))
                       (and (not wet) (liquid-at (vx point) (vy point) (vz point))))
               (nv+* point direction (- *beam-step*))
               (return)))
    (values point NIL)))

(defun beam-strike (spell origin direction container caster &key quiet)
  "Strike with SPELL along unit vector DIRECTION from ORIGIN for CASTER, at once. Returns where it
stopped. QUIET, it makes no sound."
  (multiple-value-bind (end victim) (beam-end origin direction caster)
    ;; A creature's shield stops it here; the player's is HURT-PLAYER's to meet.
    (cond ((and (typep victim 'creature) (shielded-p victim origin))
           (block-hit victim)
           (unless quiet (play-sound :shield-deflect end)))
          (T
           (strike-with-spell spell victim origin caster end)))
    (let ((element (spell-element spell)))
      (when element
        (strike-skins element end *impact-skin-reach* caster)))
    (play-impact spell end container :quiet quiet)
    end))

(defun fire-beam (spell origin direction container caster)
  "Strike once with SPELL along unit vector DIRECTION from ORIGIN for CASTER, its light flashing."
  (let ((end (beam-strike spell origin direction container caster)))
    (enter (make-instance 'beam :start (vcopy origin) :end end :color (light-color spell)) container)))

(define-shader-entity beam (renderable listener)
  ((start :initarg :start :initform (vec 0 0 0) :reader beam-start)
   (end :initarg :end :initform (vec 0 0 1) :reader beam-end-point)
   (color :initarg :color :initform (vec 1 1 1) :reader beam-color)
   (held :initarg :held :initform NIL :accessor beam-held
         :documentation "True while its caster holds it: it stays lit, and fades once let go.")
   (age :initform 0.0 :accessor age)))

(defparameter *beam-segments* 48 "Quads along a beam's ribbon. Read when it is made (a restart).")

(defvar *beam-vao* NIL
  "The ribbon every beam draws, shared, as the aurora's ring is; PRELOAD-SPELLS stages it.")

(defun beam-vao ()
  (or *beam-vao*
      (let* ((n *beam-segments*)
             (data (make-array (* n 12) :element-type 'single-float))
             (k 0))
        ;; Two triangles a segment, each vertex (fraction of the way along, side -1 or 1).
        (dotimes (i n)
          (let ((a0 (float (/ i n) 0f0)) (a1 (float (/ (1+ i) n) 0f0)))
            (loop for v in (list a0 -1f0 a1 -1f0 a1 1f0 a0 -1f0 a1 1f0 a0 1f0)
                  do (setf (aref data k) v) (incf k))))
        (setf *beam-vao*
              (make-instance 'vertex-array
                             :vertex-form :triangles
                             :bindings `((,(make-instance 'vertex-buffer :buffer-data data) :size 2 :offset 0 :stride 8 :index 0))
                             :size (* n 6))))))

(defmethod stage :after ((beam beam) (area staging-area))
  (stage (beam-vao) area))

(define-handler (beam tick) (dt)
  (unless (or (frozen-p) (beam-held beam))
    (when (< *beam-time* (incf (age beam) dt))
      (despawn beam))))

(defmethod render ((beam beam) (program shader-program))
  (let ((camera (camera (scene +main+))))
    (setf (uniform program "view_matrix") (view-matrix)
          (uniform program "projection_matrix") (projection-matrix)
          (uniform program "start") (beam-start beam)
          (uniform program "end_point") (beam-end-point beam)
          (uniform program "eye") (location camera)
          (uniform program "width") (float *beam-width* 0f0)
          (uniform program "fade") (float (- 1.0 (/ (age beam) *beam-time*)) 0f0)
          (uniform program "beam_color") (beam-color beam)
          (uniform program "texels_per_metre") *texels-per-metre*
          (uniform program "light_steps") *aurora-light-steps*
          (uniform program "seed") (float (mod (+ (vx (beam-end-point beam)) (vz (beam-end-point beam))) 100.0) 0f0))
    ;; Light added over what is behind it, as the aurora's.
    (gl:disable :cull-face)
    (gl:depth-mask NIL)
    (gl:blend-func :one :one)
    (render-array (beam-vao))
    (gl:blend-func :src-alpha :one-minus-src-alpha)
    (gl:depth-mask T)
    (gl:enable :cull-face)))

(define-class-shader (beam :vertex-shader)
  "layout (location = 0) in vec2 in_ts;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;
uniform vec3 start;
uniform vec3 end_point;
uniform vec3 eye;
uniform float width;
out vec2 v_ts;
out float v_length;

void main(){
  vec3 along = end_point - start;
  vec3 p = start + along * in_ts.x;
  // Turned about its own line to face the eye, as a billboard is about +Y.
  vec3 side = cross(along, eye - p);
  float sl = length(side);
  side = sl > 0.00001 ? side / sl : vec3(0.0, 1.0, 0.0);
  gl_Position = projection_matrix * (view_matrix * vec4(p + side * width * in_ts.y, 1.0));
  v_ts = in_ts;
  v_length = length(along);
}")

(define-class-shader (beam :fragment-shader)
  "in vec2 v_ts;
in float v_length;
uniform float width;
uniform float fade;
uniform float seed;
uniform float texels_per_metre;
uniform float light_steps;
uniform vec3 beam_color;
out vec4 color;

float hash(float n){ return fract(sin(n * 127.1 + seed) * 43758.5453); }

void main(){
  // Whole texels of the world's grid along it and across it, as the art's pixels are.
  float cols = max(4.0, floor(v_length * texels_per_metre));
  float rows = max(3.0, floor(2.0 * width * texels_per_metre));
  float t = (floor(v_ts.x * cols) + 0.5) / cols;
  float s = (floor((v_ts.y * 0.5 + 0.5) * rows) + 0.5) / rows * 2.0 - 1.0;
  // A core that wavers a texel's worth along it, thinning as it fades.
  float wobble = (hash(floor(t * cols / 3.0)) - 0.5) * 0.5;
  float d = abs(s - wobble);
  float core = 1.0 - smoothstep(0.15, 0.35 + 0.4 * fade, d);
  float halo = 0.45 * (1.0 - smoothstep(0.3, 1.0, d));
  // Brightest at the hands' end and where it strikes.
  float ends = 0.8 + 0.2 * max(smoothstep(0.85, 1.0, t), 1.0 - smoothstep(0.0, 0.08, t));
  float light = (core + halo) * fade * ends;
  light = floor(light * light_steps + 0.35) / light_steps;
  vec3 c = mix(beam_color, vec3(1.0), 0.5 * core);
  color = vec4(c * light, 1.0);
}")

;;; Nova delivery: a burst centred on the caster, sparing them, out to *NOVA-RADIUS* plus its
;;; effects' area. Every effect it strikes with, area or not, lands on every body in reach, and
;;; pushes away from the caster's chest. Its impact plays on the ring's outer shell only, so it
;;; doesn't fill the caster's own view.


(defun cast-spell (spell origin direction container &key caster)
  "Deliver SPELL from ORIGIN along unit vector DIRECTION for CASTER, the player or a
creature; a :CIRCLE is drawn round ORIGIN, on the floor, and DIRECTION doesn't count.
Mana is the caster's business."
  (ecase (spell-delivery spell)
    ((:projectile :seeker) (launch-projectile spell origin direction container caster))
    (:beam (fire-beam spell origin direction container caster))
    (:nova (place-nova spell origin container caster))
    (:circle (place-circle spell origin container caster))
    (:vortex (place-vortex spell origin direction container caster))))

(defparameter *spell-looks*
  '((:fire bolt-flight bolt-burst (1.5 0.8 0.3))
    (:frost frost-flight frost-burst (0.45 1.0 1.8))
    (:shock shock-flight shock-burst (1.6 1.5 0.5))
    (:drain drain-flight drain-burst (1.6 0.3 0.5))
    (:heal heal-flight heal-burst (0.5 1.6 0.4))
    (:arcane arcane-flight arcane-burst (1.1 0.4 1.7))
    ;; Cast on yourself only, so their flight and burst are never seen.
    (:ward heal-flight heal-burst (1.6 1.3 0.5))
    (:absorb arcane-flight arcane-burst (0.4 0.7 1.8)))
  "(LOOK FLIGHT BURST LIGHT-COLOR) for each look a forged spell can have.")

;;; The spells.

(defun preload-spells (scene)
  "Load the sprites of every spell, which only appear mid-game, and of every look a forged
spell may have, which no spell in *SPELLS* need use."
  (loop for (nil flight burst) in *spell-looks*
        do (preload (make-instance 'fx-sprite :animation (find-fx-animation burst)) scene)
           (preload (make-instance 'spell-projectile :animation (find-fx-animation flight)) scene))
  (loop for spell being the hash-values of *spells*
        do (when (eq (spell-delivery spell) :vortex)
             (preload-vortex spell scene))
           (dolist (name (list (projectile-animation spell) (impact-animation spell)))
             (when name
               (preload (make-instance 'fx-sprite :animation (find-fx-animation name)) scene)))
           (when (strike-animation spell)
             (preload (make-instance 'upright-fx :animation (find-fx-animation (strike-animation spell))) scene))
           (when (projectile-animation spell)
             (preload (make-instance 'spell-projectile :spell spell
                                                       :animation (find-fx-animation (projectile-animation spell)))
                      scene))
           (when (circle-animation spell)
             (preload (make-instance 'spell-circle :spell spell :centre (vec 0 0 0)
                                                   :animation (find-fx-animation (circle-animation spell)))
                      scene)
             (preload (make-instance 'aurora :centre (vec 0 0 0) :radius 1.0) scene)))
  (preload (make-instance 'beam) scene)
  (preload (make-instance 'nova-dome) scene)
  (preload (make-instance 'spell-nova :spell (find-spell 'bolt) :centre (vec 0 0 0)
                                      :animation (find-fx-animation 'ogre-dust))
           scene))

(define-fx-animation bolt-flight "sprites/bolt/flight" :fps 12 :loop T :size 0.4)
(define-fx-animation bolt-burst "sprites/bolt/burst" :fps 14 :size 0.9)

;; The player's starting spells. Each is one the spellforge makes (FORGEABLE-P, forge.lisp): its
;; ranges are a forged effect's (*MAGNITUDE-SPREAD* of the top up to it), the bolt's speed, pain
;; bonus and frames are a forged projectile's (SPEC-SPELL), so its power is what the forge's would be:
;; the bolt fire damage at 9 and knockback at 4, power 14, free (*FREE-MAX-POWER*); the heal 20,
;; power 17, 17 mana a cast.
(define-spell bolt (:delivery :projectile :projectile-speed 20.0 :pain-bonus 10 :title "Fire Bolt"
                    :projectile-animation 'bolt-flight :impact-animation 'bolt-burst)
  (:damage :element :fire :magnitude '(7 9))
  (:knockback :magnitude '(3 4)))

;; Cast on themself, it needs no projectile.
(define-spell heal (:delivery :self)
  (:heal :magnitude '(14 20) :target-type :self))

;; Held on themself: while held, the hostile projectiles reaching the player from in front are
;; swallowed into mana (ABSORBS-P, magic.lisp), up to 50% of their power. Free, as Absorb always is.
(define-spell absorb (:delivery :self :title "Absorb Projectiles")
  (:absorb :magnitude '(35 50) :target-type :self))

;;; Looks: a forged spell (forge.lisp) flies and bursts as its element, or, with no
;;; damage, as its first effect: the bolt's frames, recoloured (tools/recolor_hue.py,
;;; data/sprites/spells/), with a glow to match.

(define-fx-animation frost-flight "sprites/spells/frost-flight" :fps 12 :loop T :size 0.4)
(define-fx-animation frost-burst "sprites/spells/frost-burst" :fps 14 :size 0.9)
(define-fx-animation shock-flight "sprites/spells/shock-flight" :fps 16 :loop T :size 0.4)
(define-fx-animation shock-burst "sprites/spells/shock-burst" :fps 16 :size 0.9)
(define-fx-animation drain-flight "sprites/spells/drain-flight" :fps 10 :loop T :size 0.4)
(define-fx-animation drain-burst "sprites/spells/drain-burst" :fps 14 :size 0.9)
(define-fx-animation heal-flight "sprites/spells/heal-flight" :fps 10 :loop T :size 0.4)
(define-fx-animation heal-burst "sprites/spells/heal-burst" :fps 14 :size 0.9)
(define-fx-animation arcane-flight "sprites/spells/arcane-flight" :fps 12 :loop T :size 0.4)
(define-fx-animation arcane-burst "sprites/spells/arcane-burst" :fps 14 :size 0.9)

(defun spell-look (spell)
  "The look of SPELL: a tornado's :STORM, else its effects' (EFFECTS-LOOK)."
  (if (eq (spell-delivery spell) :vortex) :storm (effects-look (spell-effects spell))))

(defun effects-look (effects)
  "The look of a spell of EFFECTS, a list of EFFECT: its first damage's element, else its
first effect's kind."
  (let ((damage (find :damage effects :key #'effect-kind)))
    (cond ((and damage (effect-element damage)))
          (damage :fire)
          (T (case (and effects (effect-kind (first effects)))
               (:drain :drain)
               (:heal :heal)
               (:ward :ward)
               (:absorb :absorb)
               (:slow :frost)
               (T :arcane))))))

;;; Specs: a spell as plain data, for forged spells, which aren't in *SPELLS* and are saved
;;; by what they hold (save.lisp): (NAME DELIVERY &rest EFFECTS), each effect a plist of
;;; EFFECT initargs.

(defun spell-spec (spell)
  (list* (spell-name spell) (spell-delivery spell)
         (loop for e in (spell-effects spell)
               collect (list :kind (effect-kind e) :magnitude (copy-list (effect-magnitude e))
                             :duration (effect-duration e) :area (effect-area e)
                             :target-type (effect-target-type e) :element (effect-element e)))))

(defun spec-spell (spec)
  "A new spell made from SPEC, (NAME DELIVERY &rest EFFECT-PLISTS), with its look."
  (destructuring-bind (name delivery &rest effect-specs) spec
    (let* ((effects (loop for args in effect-specs
                          collect (apply #'make-instance 'effect
                                         :magnitude (copy-list (getf args :magnitude '(1 1)))
                                         args)))
           (look (assoc (effects-look effects) *spell-looks*)))
      (destructuring-bind (flight burst (r g b)) (rest look)
        (make-instance 'spell :name name :delivery delivery :effects effects
                              :projectile-speed 20.0 :pain-bonus 10
                              :projectile-animation flight :impact-animation burst
                              :light-color (vec r g b) :light-radius *bolt-light-radius*)))))

;; The acolyte's spell (creature.lisp): slower than the bolt, so a sidestep dodges it.
;; It flies on the bolt's frames, bigger and redder, until it has its own.
(define-fx-animation cinder-flight "sprites/bolt/flight" :fps 9 :loop T :size 0.55)

(define-spell cinder (:delivery :projectile :projectile-speed 9.0
                      :projectile-animation 'cinder-flight :impact-animation 'bolt-burst
                      :light-color (vec 1.8 0.35 0.12) :light-radius 4.5)
  (:damage :magnitude '(5 8)))

;; The necromancer's spells (creature.lisp). The grave skull flies slowly and curves
;; after the player, but turns slower than a late sidestep.
(define-fx-animation grave-skull-flight "sprites/grave/flight" :fps 10 :loop T :size 0.5)
(define-fx-animation grave-skull-burst "sprites/grave/burst" :fps 14 :size 1.0)

(define-spell grave-skull (:delivery :projectile :projectile-speed 6.0 :homing 1.0 :lifetime 5.0
                           :projectile-animation 'grave-skull-flight :impact-animation 'grave-skull-burst
                           :light-color (vec 0.4 1.8 0.5) :light-radius 4.0)
  (:damage :magnitude '(6 9)))

;; The grave circle: a pentagram drawn for a 2.5 m radius (tools/draw_grave_circle.py),
;; its cell 328 px at 64 px a metre; an aurora round it; then bone spikes burst up all
;; over it, the tallest 1.8 m.
(define-fx-animation grave-circle "sprites/grave/circle" :loop T :size (/ 328 64.0))
(define-fx-animation grave-spikes "sprites/grave/spikes" :fps 12 :size (/ 115 64.0))

(define-spell grave-spikes (:delivery :circle :windup 2.5
                            :circle-animation 'grave-circle
                            :strike-animation 'grave-spikes)
  (:damage :magnitude '(14 22) :area 2.5)
  (:knockback :magnitude '(3 3) :area 2.5))
