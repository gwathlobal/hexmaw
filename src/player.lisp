(in-package #:hexmaw)

;;; First-person controller. The player is the camera: FEET is the position on
;;; the ground, the eye sits EYE-HEIGHT above it. Collision is box-vs-box
;;; against *SOLIDS*, resolved one axis at a time.

(defparameter *walk-speed* 4.0)
(defparameter *run-speed* 7.0)
(defparameter *crouch-speed* 2.0)
(defparameter *backpedal-scale* 0.75 "Fraction of the speed the player keeps walking backward.")
(defparameter *ground-acceleration* 40.0)
(defparameter *air-control* 0.3)
(defparameter *gravity* 20.0)
(defparameter *jump-speed* 6.5)
(defparameter *eye-height* 1.6)
(defparameter *crouch-eye-height* 0.9)
(defparameter *eye-height-speed* 6.0)
(defparameter *step-height* 0.45)
(defparameter *player-radius* 0.3)
(defparameter *player-height* 1.8)
(defparameter *mouse-sensitivity* 0.0025
  "Radians a pixel of mouse movement turns the view, at the middle of Settings' slider
(MOUSE-SENSITIVITY, settings.lisp).")
(defparameter *player-max-health* 100)
(defparameter *max-mana* 50.0)
(defparameter *max-stamina* 100.0)
(defparameter *stamina-regen* 8.0 "Stamina per second while not running.")
(defparameter *run-stamina* 15.0 "Stamina per second a run costs.")
(defparameter *jump-stamina* 15.0 "Stamina a jump costs; with less, no jump.")
(defparameter *block-stamina-scale* 2.0
  "Stamina a blow on the raised shield costs, per point of its damage before the shield.")
(defparameter *winded-recover* 25.0 "Stamina a player who ran it empty needs before running again.")
(defparameter *stamina-guard-break* 1.0
  "Seconds a blow the shield hasn't the stamina for knocks it aside (BREAK-GUARD).")
(defparameter *cast-cooldown* 0.35 "Seconds between casts.")
(defparameter *free-cast-cooldown* 0.5 "Seconds between casts of a free spell (SPELL-TIER).")
(defparameter *cast-release* 0.2
  "Seconds from the click until the spell leaves the hands: the cast animation's release frame.")
(defparameter *player-knockback* 3.0 "Speed in m/s a blow shoves the player away from it.")
(defparameter *block-arc* 1.0 "Radians either side of the view the raised shield covers.")
(defparameter *block-damage-scale* 0.25 "Fraction of a blocked blow's damage that gets through.")
(defparameter *block-shove-scale* 0.4 "Fraction of a blocked blow's shove that gets through.")
(defparameter *block-speed-scale* 0.6
  "Fraction of the walking speed the player keeps with the shield fully raised; no running.")
(defparameter *pain-time* 0.35 "Seconds the screen flashes red after the player is hurt.")
(defparameter *restore-flash-time* 0.25 "Seconds the screen flashes after a pickup restores something.")
(defparameter *swim-speed* 3.0)
(defparameter *swim-run-speed* 4.5)
(defparameter *swim-acceleration* 10.0 "Metres per second squared toward the swim wished for.")
(defparameter *water-drag* 3.0
  "Per second, the share of speed water takes from something moving faster than a swim (a
dive in, a shove), as an exponential.")
(defparameter *swim-sink* 0.4 "Metres per second a player sinks at below the surface, swimming nowhere.")
(defparameter *swim-waist* 0.9 "Metres above the feet that must be in water to swim.")
(defparameter *float-eye* 0.15 "Metres above the surface the eye floats at.")
(defparameter *climb-out-height* 0.8 "The highest a ledge may stand over the surface for the player to climb out onto it.")
(defparameter *climb-out-depth* 0.3
  "The deepest a ledge's top may lie under the surface for the player to climb onto it: a ford's
sill, 0.15 m under, or a waterfall's lip. Deeper, the player swims over it.")
(defparameter *climb-speed* 3.0 "Metres per second a climb out rises.")
(defparameter *climb-time* 1.0 "Seconds a climb out may take before it gives up.")
(defparameter *breath-time* 20.0 "Seconds the player can stay under water.")
(defparameter *breath-refill* 5.0 "Seconds of breath regained per second in air.")
(defparameter *drown-damage* 10.0 "Health per second lost under water with no breath left.")
(defparameter *spawn-point* (vec 0 0 5))
(defparameter *kill-height* -20.0)
(defparameter *death-eye-height* 0.25 "Metres above the feet the eye comes to rest at when the player falls dead.")
(defparameter *death-fall-gravity* 7.0 "Metres per second squared the dead player's eye falls at.")
(defparameter *death-roll* 0.45 "Radians the view has rolled by when the fall is over.")
(defparameter *death-roll-time* 0.7 "Seconds the view takes to roll over.")
(defparameter *death-panel-delay* 1.2 "Seconds from death to the death screen (menu.lisp).")
(defparameter *inventory-size* 20 "Cells in the player's inventory (inventory.lisp).")
(defparameter *starting-effects* '(:damage :heal :knockback :fire :absorb)
  "What the player can forge with at the start of a run; glyphs (pickups.lisp) teach the rest.")
(defparameter *hotbar-size* 9 "Slots on the hotbar (inventory.lisp), keys 1 to 9.")
(defparameter *starting-hotbar* '(:sword (bolt absorb) heal)
  "What a run starts with in the bag, from its first cell, each bound to the hotbar key of its
place, from 1: a weapon's item kind, a spell's name, which the player carries as a rune, or a list
of two spells, the slot's rune and its off hand's (inventory.lisp). A spell may also be a spec
(SPEC-SPELL, spells.lisp), a list whose first element is its name, a string. The rest is found in
the dungeon (loot.lisp). Every spell here must be one the spellforge makes
(CHECK-STARTING-SPELLS, forge.lisp).")
(defparameter *debug-starting-hotbar*
  '(:sword (bolt absorb) :spear tempest heal :maul
    ("Flame Lance" :projectile (:kind :damage :element :fire :magnitude (21 30) :target-type :target))
    ("Fire Ray" :beam (:kind :damage :element :fire :magnitude (11 15) :target-type :target))
    ("Force Nova" :nova (:kind :knockback :magnitude (9 12) :area 1.0 :target-type :target)))
  "What the debug level starts with instead: the spear, the tornado and the maul too, and a stamina
projectile, a mana beam and a stamina nova, to try them.")
(defparameter *starting-slot* 0 "The hotbar slot, from 0, a run starts with in hand: the sword.")
(defparameter *footstep-stride* 2.0 "Metres walked on foot from one footstep to the next.")
(defparameter *footstep-volume* 0.5)
(defparameter *swim-stroke-stride* 2.2 "Metres swum from one stroke to the next.")
(defparameter *land-sound-speed* 3.0 "Metres per second a landing must come down at to be heard.")
(defparameter *splash-gap* 0.6
  "Seconds after a splash before the next: wading at the waist goes in and out of the water.")
(defparameter *gasp-breath* 0.5 "Fraction of *BREATH-TIME* left, under which surfacing gasps.")
(defparameter *ice-slide-speed* 6.0 "Metres per second at which the slide on ice is at full volume.")

(defclass player (fps-camera whirlable afflicted)
  ((name :initform :player)
   (fov :initform 75.0)
   (near-plane :initform 0.05f0)
   (far-plane :initform 200.0f0)
   (feet :initform (vcopy *spawn-point*) :accessor feet)
   (velocity :initform (vec 0 0 0) :accessor velocity)
   (grounded :initform NIL :accessor grounded)
   (snare :initform NIL :accessor snare
          :documentation "NIL, or a bloodroot's roots closing on or holding the player (bloodroot.lisp): a
plist :ROOT (the bloodroot), :PHASE (:TELL, then :HELD), :LEFT (seconds of it) and :AT (its point).")
   (snare-guard :initform 0.0 :accessor snare-guard
                :documentation "Seconds until roots may close on the player again, after a snare.")
   (footing :initform NIL :accessor footing
            :documentation "The footing (*FOOTINGS*) of the floor it stood on last tick, or NIL.")
   (eye :initform *eye-height* :accessor eye)
   (mouse-look :initform NIL :accessor mouse-look)
   (health :initform *player-max-health* :accessor health)
   (pain :initform 0.0 :accessor pain :documentation "Seconds of the pain flash left.")
   (restore-flash :initform 0.0 :accessor restore-flash
                  :documentation "Seconds of the flash left after a pickup restored something.")
   (restored :initform NIL :accessor restored
             :documentation "What the last pickup restored, :HEALTH or :MANA: the flash's colour.")
   (burn-timer :initform 0.0 :accessor burn-timer
               :documentation "Seconds until the next burn can land (liquids.lisp).")
   (wading :initform NIL :accessor wading
           :documentation "Kind of the liquid last stood in, NIL on dry ground: it slows a jump from it.")
   (swimming :initform NIL :accessor swimming :documentation "True while in water up to the waist.")
   (climbing :initform NIL :accessor climbing
             :documentation "Seconds left of a climb out of the water onto a ledge, or NIL.")
   (breath :initform *breath-time* :accessor breath :documentation "Seconds of breath left.")
   (drown-timer :initform 0.0 :accessor drown-timer
                :documentation "Seconds until the next drowning damage can land (BURN-DUE).")
   (mana :initform *max-mana* :accessor mana)
   (inventory :initform (make-list *inventory-size*) :accessor inventory
              :documentation "A list of cells, each a stack, (KIND COUNT), or NIL (inventory.lisp).")
   (quickslot :initform NIL :accessor quickslot
              :documentation "The kind of potion Q drinks from the bag, or NIL.")
   (stamina :initform *max-stamina* :accessor stamina)
   (winded :initform NIL :accessor winded
           :documentation "True from running out of stamina until *WINDED-RECOVER*: no running.")
   (cast-timer :initform 0.0 :accessor cast-timer)
   (cast-time :initform NIL :accessor cast-time
              :documentation "Seconds since the last cast began, or NIL before the first.")
   (pending-spell :initform NIL :accessor pending-spell
                  :documentation "Spell being cast, launched at *CAST-RELEASE*, or once let go if overcharged.")
   (last-cast :initform NIL :accessor last-cast
               :documentation "The spell last cast or held, whose look both hands take while it plays (hands.lisp).")
   (cast-hand :initform :main :accessor cast-hand
              :documentation "The hand the spell being cast or held is in: :MAIN (the left button) or :OFF (the right).")
   (cast-held :initform 0.0 :accessor cast-held
              :documentation "Seconds a spell has been held past its release, overcharging.")
   (overcharge :initform 0.0 :accessor overcharge
               :documentation "How far the pending spell is overcharged and paid for, 0 to 1.")
   (offhands :initform (make-list *hotbar-size*) :accessor offhands
             :documentation "Each hotbar slot's off-hand rune, a stack in the INVENTORY (EQ), or NIL:
cast with the right button while that slot's rune is in hand. Saved as OFFHAND-CELLS.")
   (channel :initform NIL :accessor channel
            :documentation "The spell being held (HOLD-CHANNEL): a beam or an Absorb; NIL. Not saved: a load lets go.")
   (channel-pulses :initform NIL :accessor channel-pulses
                   :documentation "A beam's strikes, (CALM . STAGGER): PULSE-SPELLs without and with its flinch roll.")
   (channel-time :initform 0.0 :accessor channel-time :documentation "Seconds it has been held.")
   (channel-timer :initform 0.0 :accessor channel-timer :documentation "Seconds to its next strike.")
   (channel-count :initform 0 :accessor channel-count :documentation "Strikes it has made.")
   (channel-beam :initform NIL :accessor channel-beam :documentation "Its light, a BEAM, or NIL before the first strike.")
   (channel-aim :initform 0.0 :accessor channel-aim :documentation "Seconds to its light's next aim.")
   (channel-sound :initform NIL :accessor channel-sound :documentation "Its loop while it strikes, or NIL.")
   (known-effects :initform (copy-list *starting-effects*) :accessor known-effects
                  :documentation "Effect kinds and elements, and :AREA, the player can forge with.")
   (hotbar :initform (make-list *hotbar-size*) :accessor hotbar
           :documentation "A list of *HOTBAR-SIZE* slots, each a weapon's or a rune's stack in the
INVENTORY (EQ), or NIL (inventory.lisp): what keys 1 to 9 take in hand. Saved as HOTBAR-CELLS.")
   (wanted-slot :initform *starting-slot* :accessor wanted-slot
                :documentation "The hotbar slot, from 0, whose weapon or spell is asked for.")
   (held-spell :initform NIL :accessor held-spell :documentation "The spell the hands on screen cast.")
   (wanted-spell :initform NIL :accessor wanted-spell
                 :documentation "The spell asked for; differs from HELD-SPELL while switching.")
   (enchantments :initform () :accessor enchantments
                 :documentation "A plist from :SHIELD to the spell the shield's bash carries
(ENCHANT-STRIKE, sword.lisp). A sword's or spear's is its own stack's (STACK-ENCHANTMENT).")
   (weapon :initform NIL :accessor weapon
           :documentation "Weapon on screen (sword.lisp): :SWORD, :SPEAR, :MAUL, :HANDS or NIL.")
   (wanted-weapon :initform NIL :accessor wanted-weapon
                  :documentation "Weapon asked for, from the wanted hotbar slot (SYNC-WANTED);
differs from WEAPON while switching.")
   (weapon-lower :initform 0.0 :accessor weapon-lower
                 :documentation "How far the weapon on screen is lowered: 0 up, 1 gone.")
   (swing-time :initform NIL :accessor swing-time
               :documentation "Seconds since the sword swing began, or NIL when not swinging.")
   (swing-pending :initform NIL :accessor swing-pending
                  :documentation "True until the swing's blow has landed.")
   (attack-held :initform NIL :accessor attack-held
                :documentation "True while the attack button (the left one) is down: the maul charges,
a beam stays on, a spell overcharges.")
   (charge-time :initform NIL :accessor charge-time
                :documentation "Seconds the maul's blow has been charging (maul.lisp), or NIL.")
   (charge-voice :initform NIL :accessor charge-voice :documentation "The maul's cry while it charges, or NIL (maul.lisp).")
   (blow-charge :initform 0.0 :accessor blow-charge
                :documentation "The maul's charge, 0 to 1, as its blow was released.")
   (block-held :initform NIL :accessor block-held
               :documentation "True while the block button (the right one) is down.")
   (block-raise :initform 0.0 :accessor block-raise
                :documentation "How far the shield is raised to block: 0 down, 1 up.")
   (bash-time :initform NIL :accessor bash-time
              :documentation "Seconds since the shield bash began, or NIL when not bashing.")
   (bash-pending :initform NIL :accessor bash-pending
                 :documentation "True until the bash's blow has landed.")
   (spear-jolt :initform 0.0 :accessor spear-jolt
               :documentation "Seconds the spear still shows the jolt of a counter (spear.lisp).")
   (guard-broken :initform 0.0 :accessor guard-broken
                 :documentation "Seconds left before the shield can be raised again, after a
blow knocked it aside (BREAK-GUARD).")
   (run-time :initform 0.0 :accessor run-time
             :documentation "Seconds of this run in play: not paused, not on the map, not in hit-stop.")
   (damage-taken :initform 0 :accessor damage-taken
                 :documentation "Health this run has cost, for the death screen.")
   (level-records :initform () :accessor level-records
                  :documentation "A LEVEL-RECORD for each level this run has left, the latest first.")
   (killed-by :initform NIL :accessor killed-by
              :documentation "What killed the player: a creature's type, :LAVA or :DROWNING.")
   (death-time :initform 0.0 :accessor death-time
               :documentation "Seconds since the player died (*GAME-STATE* :DEAD).")
   (reputation :initform () :accessor reputation
               :documentation "Standing with each faction (*FACTIONS*), a plist from -100 to 100.")
   (max-health :initform *player-max-health* :accessor max-health :documentation "Raised by the trainer.")
   (max-mana :initform *max-mana* :accessor max-mana)
   (max-stamina :initform *max-stamina* :accessor max-stamina)
   (blessed :initform 0.0 :accessor blessed
            :documentation "Seconds of play the priest's blessing has left (BLESSING-SCALE).")
   (stride-left :initform 0.0 :accessor stride-left
                :documentation "Metres to walk or swim before the next footstep or stroke.")
   (splash-timer :initform 0.0 :accessor splash-timer :documentation "Seconds before a splash may sound again.")
   (breath-under :initform NIL :accessor breath-under :documentation "True if the eye was under water last tick.")
   (slide-sound :initform NIL :accessor slide-sound :documentation "The loop of a slide on ice, or NIL.")
   (underwater-sound :initform NIL :accessor underwater-sound :documentation "The loop heard under water, or NIL.")
   (whirl-sound :initform NIL :accessor whirl-sound :documentation "The wind's loop while a vortex holds the player, or NIL.")
   (shake-strength :initform 0.0 :accessor shake-strength
                   :documentation "Strength, 0 to 1, of the camera shake running (KICK-CAMERA), or 0.")
   (shake-age :initform 0.0 :accessor shake-age :documentation "Seconds of play since the shake's kick.")
   (shake-step :initform 0.0 :accessor shake-step
               :documentation "Seconds into the shake's swing from SHAKE-FROM to SHAKE-TO.")
   (shake-from :initform (vec 0 0 0) :accessor shake-from
               :documentation "Where the swing started: pitch, yaw and roll in radians, at full strength.")
   (shake-to :initform (vec 0 0 0) :accessor shake-to :documentation "Where the swing ends.")
   (shake-offset :initform (vec 0 0 0) :accessor shake-offset
                 :documentation "The view's turn now, pitch, yaw and roll, applied by PROJECT-VIEW.")))

;; Trial's camera has no roll; the player's view rolls as it falls dead (FALL-DEAD).
;; The starting kit, in the bag and bound to its keys (GIVE-STARTING-KIT, inventory.lisp).
(defmethod initialize-instance :after ((player player) &key)
  (give-starting-kit player))

(defmethod project-view ((camera player))
  (let* ((rot (rotation camera))
         (loc (location camera))
         (shake (camera-shake-view camera))
         (roll (if shake (+ (vz rot) (vz shake)) (vz rot))))
    (reset-matrix (view-matrix))
    ;; The shake turns the view about its own axes, after it has turned.
    (when shake
      (rotate +vx+ (vx shake) (view-matrix))
      (rotate +vy+ (vy shake) (view-matrix)))
    (unless (= 0.0 roll)
      (rotate +vz+ roll (view-matrix)))
    (rotate +vx+ (vx rot) (view-matrix))
    (rotate +vy+ (vy rot) (view-matrix))
    (translate-by (- (vx loc)) (- (vy loc)) (- (vz loc)) (view-matrix))))

(defun capture-mouse (player)
  (lock-cursor (context +main+))
  (setf (mouse-look player) T))

(defun release-mouse (player)
  (show-cursor (context +main+))
  (setf (mouse-look player) NIL))

(defun look-direction (player)
  "Unit vector the player is looking along, pitch included."
  (let ((pitch (vx (rotation player)))
        (yaw (vy (rotation player))))
    (vec (* (sin yaw) (cos pitch)) (- (sin pitch)) (- (* (cos yaw) (cos pitch))))))

(defun spell-price (spell)
  "What a cast of SPELL takes, by its tier (SPELL-TIER): :STAMINA or :MANA and how much, or NIL
for a free spell."
  (ecase (spell-tier spell)
    (:free (values NIL 0))
    (:stamina (values :stamina (spell-stamina spell)))
    (:mana (values :mana (spell-cost spell)))))

(defun can-pay-p (player resource amount)
  (case resource
    (:stamina (<= amount (stamina player)))
    (:mana (<= amount (mana player)))
    (T T)))

(defun pay (player resource amount)
  (case resource
    (:stamina (decf (stamina player) amount))
    (:mana (decf (mana player) amount))))

(defun held-spell-p (spell)
  "True if SPELL is held rather than cast: a beam, or an Absorb (magic.lisp)."
  (or (eq (spell-delivery spell) :beam) (absorb-spell-p spell)))

(defun overchargeable-p (spell)
  "True if SPELL may be overcharged: a striking stamina or mana spell that isn't held."
  (and (not (eq (spell-tier spell) :free))
       (member (spell-delivery spell) '(:projectile :touch :seeker :nova))
       (not (held-spell-p spell))))

(defun hand-held-p (player hand)
  "True while the button of HAND, :MAIN or :OFF, is down."
  (if (eq hand :off) (block-held player) (attack-held player)))

(defun hand-spell (player hand)
  "The spell in HAND, :MAIN or :OFF (OFFHAND-SPELL, inventory.lisp), while the hands are up."
  (if (eq hand :off) (offhand-spell player) (held-spell player)))

(defun busy-casting-p (player)
  "True while a cast is under way: wound up, overcharging or held."
  (or (pending-spell player) (channel player)))

(defun player-cast (player spell &key (hand :main))
  "Start casting SPELL, a spell or the name of one, from HAND, if what it takes (SPELL-PRICE) and
the cooldown allow. The hands wind up and the spell leaves *CAST-RELEASE* seconds later
(RELEASE-SPELL), or, held past then, once let go, overcharged; a beam or an Absorb is held from
then instead (HOLD-CHANNEL). Returns true if it was cast."
  (let* ((spell (if (symbolp spell) (find-spell spell) spell))
         (held (held-spell-p spell)))
    (multiple-value-bind (resource cost) (spell-price spell)
      ;; A beam is held, and pays as it strikes: it needs only its first strike's.
      (let ((cost (if held (* cost (beam-pulse-share)) cost)))
        (when (and (<= (cast-timer player) 0) (not (busy-casting-p player)))
          (cond ((not (can-pay-p player resource cost))
                 (play-sound :cast-fizzle)
                 NIL)
                (T
                 (setf (cast-timer player) (if (eq (spell-tier spell) :free) *free-cast-cooldown* *cast-cooldown*)
                       (last-cast player) spell
                       (cast-hand player) hand
                       (overcharge player) 0.0)
                 ;; A held spell's hands play no cast (hands.lisp).
                 (if held
                     ;; The last cast's clock stops: its spell is no longer the one in hand.
                     (progn (setf (cast-time player) NIL)
                            (hold-channel player spell))
                     (progn (pay player resource cost)
                            (setf (pending-spell player) spell
                                  (cast-time player) 0.0
                                  (cast-held player) 0.0)))
                 ;; The Ashen Temple's rule: no spell within the town's walls (settlement.lisp).
                 (when (and *settlement* (eq (faction-property :rule) :no-casting) (in-settlement-p (feet player)))
                   (report-crime :rule))
                 T)))))))

;;; Overcharge: a striking stamina or mana spell still held when the hands reach its release
;;; stays in them, and grows stronger and dearer from *OVERCHARGE-DELAY* after the press to
;;; *OVERCHARGE-FULL* (OVERCHARGED-SPELL, spells.lisp), paying as it grows; it stops growing when
;;; what it draws on runs dry. Let go, it leaves. Meanwhile the player walks at
;;; *OVERCHARGE-SPEED*, with no run or jump, and no stamina comes back, as with the maul's charge.

(defparameter *overcharge-delay* 0.25 "Seconds from the press before a held spell starts to overcharge.")
(defparameter *overcharge-full* 1.35 "Seconds from the press to a full overcharge.")
(defparameter *overcharge-speed* 0.6 "Fraction of a walk the player keeps while overcharging.")

(defun overcharging-p (player)
  "True while PLAYER holds a spell past its release to overcharge it."
  (let ((spell (pending-spell player)))
    (and spell (cast-time player) (<= *cast-release* (cast-time player))
         (overchargeable-p spell) (hand-held-p player (cast-hand player)))))

(defun overcharge-step (player dt)
  "Hold the pending spell DT seconds more, overcharging it as far as PLAYER can pay."
  (let* ((spell (pending-spell player))
         ;; The cast's clock stops at its release; the hold counts on from there.
         (held (+ (cast-time player) (incf (cast-held player) dt)))
         (want (max 0.0 (min 1.0 (/ (- held *overcharge-delay*) (- *overcharge-full* *overcharge-delay*))))))
    (multiple-value-bind (resource cost) (spell-price spell)
      (let ((more (* cost (- want (overcharge player)))))
        (when (and (< 0 more) (can-pay-p player resource more))
          (pay player resource more)
          (setf (overcharge player) want))))))

;;; Channelling: a beam rune or an Absorb is held, not cast. While its button is held a beam stays
;;; on from the hands' release, striking every *BEAM-PULSE* with a share of its effects for the
;;; same share of its price (PULSE-SPELL, spells.lisp), so a second of it does and costs what two
;;; casts would. Only every *BEAM-PAIN-EVERY*th strike rolls for a flinch, so it can't hold a
;;; creature in one. An Absorb strikes nothing: while it is held the hostile projectiles reaching
;;; the player from in front are swallowed (ABSORBS-P, magic.lisp). Let go, out of what it draws
;;; on, or with the hands switched, it ends. The player walks at *CHANNEL-SPEED-SCALE*, and the
;;; hands sink with their small flames for a beam (CHANNEL-EASE, hands.lisp) so the ray stays in sight.

(defparameter *beam-pain-every* 4 "A held beam's strikes between the ones that may make a creature flinch.")
(defparameter *channel-speed-scale* 0.5 "The player's walk while holding a beam or an Absorb, against a walk.")
(defparameter *channel-aim-time* 0.05 "Seconds between aims of a held beam's light at where it would strike.")

(defun hold-channel (player spell)
  "Begin holding SPELL, a beam or an Absorb: its effects on the caster land now, and a beam strikes
from the hands' release."
  (apply-self-effects spell player player)
  (setf (channel player) spell
        (channel-pulses player) (unless (absorb-spell-p spell)
                                  (cons (pulse-spell spell :pain-bonus -100) (pulse-spell spell)))
        (channel-time player) 0.0
        (channel-timer player) *cast-release*
        (channel-count player) 0
        (channel-aim player) 0.0))

(defun end-channel (player)
  "Let go of the beam or the Absorb: a beam's light fades."
  (when (channel player)
    (let ((beam (channel-beam player)))
      (when beam (setf (beam-held beam) NIL)))
    (setf (channel player) NIL
          (channel-pulses player) NIL
          (channel-beam player) NIL
          (channel-sound player) (stop-loop (channel-sound player))
          (cast-timer player) *cast-cooldown*)))

(defun start-held-casts (player)
  "A hand's button held down with a held spell (an Absorb, a beam) in it starts it as soon as the
hands are free: the press may have come during a cast's cooldown or a weapon switch, or the spell
may have ended under a button still held. Silent while it can't be paid for, so a beam run dry
doesn't fizzle again and again."
  (when (and (eq (weapon player) :hands) (eq *game-state* :playing) (<= (cast-timer player) 0)
             (not (busy-casting-p player)) (weapon-ready-p player))
    (dolist (hand '(:main :off))
      (let ((spell (hand-spell player hand)))
        (when (and spell (held-spell-p spell) (hand-held-p player hand)
                   (multiple-value-bind (resource cost) (spell-price spell)
                     (can-pay-p player resource (* cost (beam-pulse-share)))))
          (player-cast player spell :hand hand)
          (return))))))

(defun channelling-beam-p (player)
  (let ((spell (channel player)))
    (and spell (eq (spell-delivery spell) :beam))))

(defun channel-origin (player direction)
  "Where a held beam strikes from: just below the eye, as a cast, so it goes where the player aims."
  (v+ (location player) (v* direction 0.5) (vec 0 -0.2 0)))

(defparameter *channel-light-low* 0.3
  "Metres below the line of sight, half a metre out, a held beam's light starts: between the
lowered hands, so it rises to what it strikes through open view.")

(defun channel-light-start (player direction)
  "Where a held beam's light starts: half a metre out along DIRECTION, *CHANNEL-LIGHT-LOW* down the
view, below the middle of the screen whichever way the player looks."
  (let* ((yaw (vy (rotation player)))
         ;; The view's up: its right, (cos yaw, 0, sin yaw), crossed with DIRECTION.
         (rx (cos yaw)) (rz (sin yaw))
         (ux (* rz (vy direction)))
         (uy (- (* rz (vx direction)) (* rx (vz direction))))
         (uz (- (* rx (vy direction)))))
    (vec (- (+ (vx (location player)) (* 0.5 (vx direction))) (* *channel-light-low* ux))
         (- (+ (vy (location player)) (* 0.5 (vy direction))) (* *channel-light-low* uy))
         (- (+ (vz (location player)) (* 0.5 (vz direction))) (* *channel-light-low* uz)))))

(defun update-channel (player dt)
  "Hold the beam or the Absorb: a beam strikes when due, paying for it, and keeps its light on the
aim; or let it go."
  (let ((spell (channel player))
        (hand (cast-hand player)))
    (when spell
      (incf (channel-time player) dt)
      (cond ((or (not (hand-held-p player hand)) (not (eq (hand-spell player hand) spell))
                 (not (weapon-in-hand-p player)))
             (end-channel player))
            ((absorb-spell-p spell)
             ;; Held on stamina, its power a second: out of it, the Absorb drops.
             (let ((cost (* (spell-stamina spell) dt)))
               (if (can-pay-p player :stamina cost)
                   (progn (pay player :stamina cost)
                          (setf (channel-sound player) (hold-loop (channel-sound player) :absorb-channel (location player))))
                   (progn (play-sound :cast-fizzle) (end-channel player)))))
            (T (update-beam player spell dt))))))

(defun update-beam (player spell dt)
  (let ((released (<= *cast-release* (channel-time player))))
    (when released
      (setf (channel-sound player) (hold-loop (channel-sound player) :beam-channel (location player))))
    (decf (channel-timer player) dt)
    (decf (channel-aim player) dt)
    (when (<= (channel-timer player) 0.0)
      (multiple-value-bind (resource price) (spell-price spell)
        (let ((cost (* price (beam-pulse-share))))
          (if (not (can-pay-p player resource cost))
              (progn (play-sound :cast-fizzle) (end-channel player))
              (let* ((dir (look-direction player))
                     (origin (channel-origin player dir))
                     (pulses (channel-pulses player))
                     (pulse (if (= 0 (mod (channel-count player) *beam-pain-every*)) (cdr pulses) (car pulses)))
                     (first (= 0 (channel-count player)))
                     (end (beam-strike pulse origin dir (container player) player :quiet (not first))))
                (when first
                  (play-sound :beam-cast)
                  (break-snare player))
                (pay player resource cost)
                (incf (channel-timer player) *beam-pulse*)
                (incf (channel-count player))
                (setf (channel-aim player) *channel-aim-time*)
                (if (channel-beam player)
                    (v<- (beam-end-point (channel-beam player)) end)
                    (let ((beam (make-instance 'beam :start (channel-light-start player dir) :end end :held T
                                                     :color (light-color spell))))
                      (enter beam (container player))
                      (setf (channel-beam player) beam))))))))
    ;; Between strikes the light follows the aim.
    (let ((beam (channel-beam player)))
      (when (and beam (channel player))
        (let ((dir (look-direction player)))
          (v<- (beam-start beam) (channel-light-start player dir))
          (when (<= (channel-aim player) 0.0)
            (setf (channel-aim player) *channel-aim-time*)
            (v<- (beam-end-point beam) (beam-end (channel-origin player dir) dir player))))))))

(defparameter *touch-reach* 1.6 "Metres a touch spell reaches, like a short blade.")
(defparameter *touch-arc* 0.6 "Radians either side of the view a touch spell reaches.")
(defparameter *nova-height* 1.0 "Metres above the feet a nova bursts from.")

(defun release-spell (player)
  "Let the pending spell go, as far as it was overcharged: its effects on the caster land on
PLAYER, then a projectile leaves from just below the eye toward where the player looks now, a touch
strikes the creature in reach (glancing off a shield that covers it, as a bash does, unless fully
overcharged), or a nova bursts round the player."
  (let ((spell (overcharged-spell (pending-spell player) (overcharge player))))
    (setf (pending-spell player) NIL
          (overcharge player) 0.0)
    ;; As it leaves the hands, it tears free of roots holding the player (bloodroot.lisp).
    (break-snare player)
    (play-sound (if (eq (spell-name spell) 'tempest) :tempest-cast :bolt-cast))
    (apply-self-effects spell player player)
    (case (spell-delivery spell)
      (:self)
      (:touch
       (let ((target (swing-target player *touch-reach* *touch-arc*)))
         (when target
           (let ((at (vec (vx (location target)) (+ (vy (location target)) (* 0.5 (sprite-height target)))
                          (vz (location target)))))
             (cond ((not (shielded-p target (feet player)))
                    (strike-with-spell spell target (feet player) player at))
                   ((full-overcharge-p spell)
                    (knock-guard-aside target)
                    (strike-with-spell spell target (feet player) player at))
                   (T
                    (block-hit target)))
             (play-impact spell at (container player))))))
      (:nova
       (cast-spell spell (v+ (feet player) (vec 0 *nova-height* 0)) (look-direction player)
                   (container player) :caster player))
      (T
       (let* ((dir (look-direction player))
              (origin (v+ (location player) (v* dir 0.5) (vec 0 -0.2 0))))
         (cast-spell spell origin dir (container player) :caster player))))))

;;; Clicks in a menu belong to the menu (menu.lisp), as does Esc.

(defun player-press (player input)
  "What a press of INPUT, a key or a mouse button (input.lisp), does in play."
  (let ((action (input-action input :play :global)))
    (if (eq action :screenshot)
        (screenshot)
        (when (eq *game-state* :playing)
          (case action
            (:attack (setf (attack-held player) T)
             (player-attack player))
            ;; Held, the shield rises; with the spear, a press sweeps with the haft, with the
            ;; maul it shakes the floor, and with the hands it casts the off-hand rune.
            (:block (setf (block-held player) T)
             (case (weapon player)
               (:spear (player-sweep player))
               (:maul (player-earthshake player))
               (:hands (let ((spell (offhand-spell player)))
                         (when (and spell (weapon-ready-p player))
                           (player-cast player spell :hand :off))))))
            ;; Talk to the townsperson looked at, or use the altar stood at (INTERACT-TARGET).
            (:interact (player-interact player))
            (T (let ((slot (position action *hotbar-slots*)))
                 (when slot (select-slot player slot)))))))))

(defun player-release (player input)
  (when (member input (action-inputs :attack))
    (setf (attack-held player) NIL))
  (when (member input (action-inputs :block))
    (setf (block-held player) NIL)))

(define-handler (player mouse-press) (button)
  (when (eq *game-state* :playing)
    (if (mouse-look player)
        (player-press player (mouse-input button))
        (capture-mouse player))))

(define-handler (player mouse-release) (button)
  (player-release player (mouse-input button)))

(define-handler (player key-press) (key (repeat trial::repeat))
  (unless repeat
    (player-press player key)))

(define-handler (player key-release) (key)
  (player-release player key))

(define-handler (player mouse-move) (old-pos pos)
  (when (mouse-look player)
    (let ((rot (rotation player)))
      ;; Mouse Y grows upward here, while positive pitch looks down; hence the minus.
      (setf (vx rot) (max -1.55 (min 1.55 (- (vx rot) (* (mouse-sensitivity) (- (vy pos) (vy old-pos)))))))
      (setf (vy rot) (mod (+ (vy rot) (* (mouse-sensitivity) (- (vx pos) (vx old-pos)))) #.(float (* 2 pi) 0f0))))))

(defmethod body-feet ((player player)) (feet player))
(defmethod body-radius ((player player)) *player-radius*)
(defmethod body-height ((player player)) *player-height*)
(defmethod body-solid-p ((player player)) (not (whirl player)))

;; The player as a creature's target (creature.lisp).
(defmethod allegiance ((player player)) :player)
(defmethod aim-height ((player player)) *cast-aim-height*)
(defmethod target-facing ((player player)) (vy (rotation player)))
(defmethod target-live-p ((player player)) (< 0 (health player)))
(defmethod target-guarding-p ((player player) from &optional (margin 0.0)) (shield-facing-p player from margin))
(defmethod target-swimming-p ((player player)) (swimming player))
(defmethod strike-target ((player player) amount from &rest args &key by shove lift guard-break unblockable)
  (declare (ignore by shove lift guard-break unblockable))
  (apply #'hurt-player player amount from args))
(defmethod shove-target ((player player) from speed &optional lift)
  (shove-player player from speed lift))

(defvar *walk-through-bodies* NIL
  "True while the player already overlaps a body (something revived on it), so it can walk out.")

(defun overlapping-solid (feet)
  "Return the first solid or body the player box at FEET overlaps, or NIL."
  (let ((r (float *player-radius* 0f0)) (h (float *player-height* 0f0)))
    (or (solid-overlapping (vx feet) (vy feet) (vz feet) r h)
        (unless *walk-through-bodies*
          (body-overlapping (vx feet) (vy feet) (vz feet) r h *player*)))))

(defun move-axis (player axis delta)
  "Move along AXIS (0 x, 1 y, 2 z) by DELTA, stopping flush against solids. Returns the
wedge whose diagonal stopped it, if one did, and how far short of DELTA it stopped."
  (let ((feet (feet player))
        (vel (velocity player))
        (wedge NIL))
    (flet ((ref (v) (ecase axis (0 (vx v)) (1 (vy v)) (2 (vz v))))
           (put (v x) (ecase axis (0 (setf (vx v) x)) (1 (setf (vy v) x)) (2 (setf (vz v) x)))))
      (let* ((start (ref feet))
             (target (+ start delta))
             ;; Already inside a solid (a bug): pushed out wherever its edge is, not held there.
             (inside (and (/= axis 1) (overlapping-solid feet))))
        (put feet target)
        (loop repeat 8
              for s = (overlapping-solid feet)
              while s
              ;; Up or down, a solid stops the move short of it, never past where it started:
              ;; one the body already overlapped (beside it, not over or under) put the feet
              ;; under its bottom, and so under the floor, or on its top, up through a ceiling.
              ;; Across too: pressed against a body beside a wedge's diagonal, rounding left the
              ;; feet a hair behind the start, in the diagonal, and the wedge's flush for a body
              ;; moving toward its cut corner is its far face, so out through the rock.
              do (cond ((/= axis 1)
                        (multiple-value-bind (at diagonal)
                            (solid-flush s axis delta (vx feet) (vz feet) (float *player-radius* 0f0))
                          (put feet (cond (inside at) ((< 0 delta) (max start at)) (T (min start at))))
                          (setf wedge (and diagonal s))))
                       ((< 0 delta)
                        (put feet (max start (- (aref s 1) (float *player-height* 0f0)))))
                       (T
                        (put feet (min start (aref s 4)))
                        (setf (grounded player) T)))
                 (put vel 0f0)
                 (when (= 0 delta) (return)))
        (values wedge (- target (ref feet)))))))

(defun move-flat (player dx dz)
  "Move by DX then DZ against solids, sliding along a wedge's diagonal where it stops one."
  (flet ((go-axis (axis delta)
           (multiple-value-bind (wedge blocked) (move-axis player axis delta)
             (when wedge
               ;; Along the wall: first the other axis, which leads away from it, then this one.
               (multiple-value-bind (sx sz) (slide-along wedge axis blocked)
                 (if (= axis 0)
                     (progn (move-axis player 2 sz) (move-axis player 0 sx))
                     (progn (move-axis player 0 sx) (move-axis player 2 sz))))))))
    (go-axis 0 dx)
    (go-axis 2 dz)))

(defun horizontal-distance-squared (feet x0 z0)
  (+ (expt (- (vx feet) x0) 2) (expt (- (vz feet) z0) 2)))

(defun move-horizontal (player dx dz can-step)
  "Move by DX, DZ against solids. When CAN-STEP and the move is blocked, also try it
raised by up to *STEP-HEIGHT* and dropped back down, and keep whichever got further.
On a step the eye keeps its height and eases to the new one."
  (let* ((feet (feet player)) (vel (velocity player))
         (x0 (vx feet)) (y0 (vy feet)) (z0 (vz feet))
         (vx0 (vx vel)) (vy0 (vy vel)) (vz0 (vz vel)))
    (move-flat player dx dz)
    ;; MOVE-AXIS zeroes the velocity component it was blocked on.
    (when (and can-step (or (/= (vx vel) vx0) (/= (vz vel) vz0)))
      (let ((px (vx feet)) (pz (vz feet)) (pvx (vx vel)) (pvz (vz vel))
            (plain (horizontal-distance-squared feet x0 z0)))
        (setf (vx feet) x0 (vy feet) y0 (vz feet) z0 (vx vel) vx0 (vy vel) vy0 (vz vel) vz0)
        (move-axis player 1 (float *step-height* 0f0))
        (move-flat player dx dz)
        (move-axis player 1 (- y0 (vy feet)))
        (if (< (+ plain 1f-8) (horizontal-distance-squared feet x0 z0))
            (decf (eye player) (- (vy feet) y0))
            (setf (vx feet) px (vy feet) y0 (vz feet) pz
                  (vx vel) pvx (vy vel) vy0 (vz vel) pvz
                  (grounded player) NIL))))))

(defun move-pulled (player dt can-step)
  "Move PLAYER by its velocity for DT seconds, plus the drag of any vortex (vortex.lisp),
which walking would otherwise cancel: the drag moves it but stays out of its velocity."
  (let ((vel (velocity player))
        (pull (pull player)))
    (incf (vx vel) (vx pull))
    (incf (vz vel) (vz pull))
    (move-horizontal player (* (vx vel) dt) (* (vz vel) dt) can-step)
    ;; MOVE-AXIS zeroes the component it was blocked on: nothing to take back.
    (unless (= 0 (vx vel)) (decf (vx vel) (vx pull)))
    (unless (= 0 (vz vel)) (decf (vz vel) (vz pull)))))

(defun snap-to-ground (player)
  "Keep a walking player on the floor when it drops away by up to *STEP-HEIGHT*
(walking down steps) instead of letting them fall off each one."
  (let* ((feet (feet player)) (vel (velocity player))
         (y0 (vy feet)) (vy0 (vy vel)))
    (move-axis player 1 (- (float *step-height* 0f0)))
    (if (grounded player)
        (incf (eye player) (- y0 (vy feet)))
        (setf (vy feet) y0 (vy vel) vy0))))

(defun place-camera (player)
  "Put the camera at the player's eye, and note whether it is under water (the fog)."
  (let ((loc (location player))
        (feet (feet player)))
    (setf (vx loc) (vx feet)
          (vy loc) (+ (vy feet) (float (eye player) 0f0))
          (vz loc) (vz feet))
    (setf *eye-underwater* (swim-liquid-at (vx loc) (vy loc) (vz loc)))))

;;; Camera shake, for heavy blows: the maul's, the earthshake, the ogre's landing and slam,
;;; the boss's shockwave, a crash, a hard blow taken. A kick of a strength from 0 to 1 jerks
;;; the view to and fro, up and down and across, and rolls it, dying away over
;;; *CAMERA-SHAKE-TIME*. At full strength that is about 21 screen pixels at 720 rows (moving the
;;; eye a few centimetres instead was invisible past a metre or two). It turns only the view
;;; matrix (PROJECT-VIEW): the eye's LOCATION and ROTATION, which aim, hear and are hit,
;;; stay put. It holds while the world is frozen (a hit-stop
;;; comes first, then the shake), shows only in play, draws from RANDOM, never *ROLL-RANDOM*,
;;; and nothing of it is saved.

(defvar *screen-shake* T "True if heavy blows shake the view (Settings).")
(defparameter *camera-shake-angle* 0.045 "Radians the view pitches and turns at most at full strength.")
(defparameter *camera-shake-roll* 0.03 "Radians the view rolls at most at full strength.")
(defparameter *camera-shake-time* 0.5 "Seconds a shake takes to die away, whatever its strength.")
(defparameter *camera-shake-rate* 15.0 "Swings a second: how often the shake picks a new point to swing to.")
(defparameter *camera-shake-swing* 0.6 "The least part of the most a swing goes, the rest at random.")
(defparameter *camera-shake-hurt-from* 8 "The least damage a blow taken must do to shake the view.")
(defparameter *camera-shake-hurt-full* 25 "Damage of a blow taken that shakes it at *CAMERA-SHAKE-HURT*.")
(defparameter *camera-shake-hurt* '(0.3 0.9)
  "Strength of the shake from a blow taken: of *CAMERA-SHAKE-HURT-FROM* damage, and of *CAMERA-SHAKE-HURT-FULL*.")
(defparameter *camera-shake-impact* '(0.4 1.0)
  "Strength of the shake from a crash (HIT-SURFACE): the least impact's, and one of *IMPACT-MAX*.")

(defun kick-camera (strength &optional (player *player*))
  "Shake PLAYER's view with STRENGTH, 0 to 1 (more is taken as 1). A kick weaker than what the
shake running has left does nothing."
  (let ((strength (min 1.0 (float strength 0f0))))
    (when (and player (< 0.0 strength) *screen-shake* (< (camera-shake-left player) strength))
      ;; From rest, it swings out from the middle, a random way.
      (when (<= (shake-strength player) 0.0)
        (vsetf (shake-from player) 0.0 0.0 0.0)
        (vsetf (shake-to player) (* *camera-shake-angle* (- (random 2.0) 1.0))
               (* *camera-shake-angle* (- (random 2.0) 1.0)) (* *camera-shake-roll* (- (random 2.0) 1.0)))
        (setf (shake-step player) 0.0))
      (setf (shake-strength player) strength
            (shake-age player) 0.0))))

(defun kick-camera-from (at strength reach &optional (player *player*))
  "A kick of STRENGTH from something at AT, the vec it struck: full within 2 m of PLAYER's
feet and falling off to nothing REACH metres off."
  (when player
    (let* ((feet (feet player))
           (d (sqrt (+ (expt (- (vx at) (vx feet)) 2) (expt (- (vy at) (vy feet)) 2)
                       (expt (- (vz at) (vz feet)) 2)))))
      (kick-camera (* strength (max 0.0 (min 1.0 (/ (- reach d) (- reach 2.0))))) player))))

(defun camera-shake-left (player)
  "The strength the shake running has left: its kick's, falling evenly to 0 over *CAMERA-SHAKE-TIME*.
Eased out (squared), it was down to a quarter by 0.2 s: one nod and some wiggles, not a shake."
  (let ((left (- 1.0 (/ (shake-age player) *camera-shake-time*))))
    (if (< 0.0 left)
        (* (shake-strength player) left)
        0.0)))

(defun update-camera-shake (player dt)
  "Run PLAYER's shake on DT seconds of play: on to the next swing, and SHAKE-OFFSET where it is now."
  (let ((offset (shake-offset player)))
    (cond ((<= (shake-strength player) 0.0))
          ((<= *camera-shake-time* (incf (shake-age player) dt))
           (setf (shake-strength player) 0.0)
           (vsetf offset 0.0 0.0 0.0))
          (T
           (let ((from (shake-from player))
                 (to (shake-to player))
                 (swing (/ 1.0 *camera-shake-rate*)))
             (when (<= swing (incf (shake-step player) dt))
               (setf (shake-step player) (mod (shake-step player) swing))
               (v<- from to)
               ;; To the other side each swing, by a random part of the way.
               (flet ((next (was most)
                        (* (if (< 0.0 was) -1.0 1.0) most (+ *camera-shake-swing* (random (- 1.0 *camera-shake-swing*))))))
                 (vsetf to (next (vx from) *camera-shake-angle*) (next (vy from) *camera-shake-angle*)
                        (next (vz from) *camera-shake-roll*))))
             (let ((u (/ (shake-step player) swing))
                   (k (camera-shake-left player)))
               (vsetf offset (* k (+ (vx from) (* u (- (vx to) (vx from)))))
                      (* k (+ (vy from) (* u (- (vy to) (vy from)))))
                      (* k (+ (vz from) (* u (- (vz to) (vz from))))))))))))

(defun camera-shake-view (player)
  "PLAYER's shake offset for the view, or NIL when there is none to show: only in play."
  (and (< 0.0 (shake-strength player))
       (eq *game-state* :playing)
       (shake-offset player)))

;;; Swimming, Quake-style: in water to the waist the player swims where they look (W and S
;;; along the view, A and D level), Space up and C or Ctrl down, against the water's drag,
;;; sinking slowly when swimming nowhere and floating with the eye just over the surface.
;;; Pushing forward against a ledge at the surface climbs out onto it.

(defun swim-water (player)
  "The water PLAYER is in up to the waist, or NIL."
  (let ((feet (feet player)))
    (swim-liquid-at (vx feet) (+ (vy feet) *swim-waist*) (vz feet))))

(defun ledge-ahead-p (player surface yaw)
  "True if a ledge stands ahead of PLAYER no more than *CLIMB-OUT-HEIGHT* over the water's
SURFACE, or no more than *CLIMB-OUT-DEPTH* under it (a ford's sill, a waterfall's lip), with
room to stand on it."
  (let* ((feet (feet player))
         (reach (+ *player-radius* 0.35))
         (x (+ (vx feet) (* reach (sin yaw))))
         (z (- (vz feet) (* reach (cos yaw)))))
    (and (solid-overlapping x (- surface *climb-out-depth*) z 0.05 (+ *climb-out-depth* *climb-out-height*))
         (not (solid-overlapping x (+ surface *climb-out-height*) z *player-radius* *player-height*)))))

(defun swim (player water dt ix iz up running yaw)
  "Move PLAYER through WATER for DT seconds: IX IZ the strafe and forward keys, UP the
up and down keys (1, 0 or -1)."
  (let* ((vel (velocity player))
         (feet (feet player))
         (surface (aref (liquid-bounds water) 4))
         (pitch (vx (rotation player)))
         (cp (cos pitch))
         (wx (+ (* iz (sin yaw) cp) (* ix (cos yaw))))
         (wy (+ (* iz (- (sin pitch))) up))
         (wz (+ (* iz (- (cos yaw)) cp) (* ix (sin yaw))))
         (len (sqrt (+ (* wx wx) (* wy wy) (* wz wz))))
         (speed (if running *swim-run-speed* *swim-speed*))
         (float-y (+ surface *float-eye*))
         (eye-y (+ (vy feet) *eye-height*))
         (at-surface (< (- float-y 0.3) eye-y)))
    (when (< 1.0 len)
      (setf wx (/ wx len) wy (/ wy len) wz (/ wz len)))
    ;; Faster than a swim, the water's drag slows it.
    (when (< (* speed speed) (+ (expt (vx vel) 2) (expt (vy vel) 2) (expt (vz vel) 2)))
      (let ((keep (exp (- (* *water-drag* dt)))))
        (setf (vx vel) (* (vx vel) keep) (vy vel) (* (vy vel) keep) (vz vel) (* (vz vel) keep))))
    ;; Toward the wished velocity. Swimming nowhere, it floats up to the surface when near
    ;; it, and sinks slowly when below.
    (let* ((tx (* wx speed))
           (ty (cond ((< 0 (abs wy)) (* wy speed))
                     (at-surface (max (- *swim-sink*) (min speed (* 2.0 (- float-y eye-y)))))
                     (T (- *swim-sink*))))
           (tz (* wz speed))
           (dx (- tx (vx vel))) (dy (- ty (vy vel))) (dz (- tz (vz vel)))
           (dlen (sqrt (+ (* dx dx) (* dy dy) (* dz dz))))
           (max-dv (* *swim-acceleration* dt)))
      (when (< max-dv dlen)
        (let ((f (/ max-dv dlen))) (setf dx (* dx f) dy (* dy f) dz (* dz f))))
      (incf (vx vel) dx) (incf (vy vel) dy) (incf (vz vel) dz))
    (let ((vx0 (vx vel)) (vz0 (vz vel)))
      (setf (grounded player) NIL)
      (move-pulled player dt NIL)
      (move-axis player 1 (* (vy vel) dt))
      ;; The surface holds the eye: swimming up stops there.
      (let ((over (- (+ (vy feet) *eye-height*) float-y)))
        (when (and (< 0 over) (< 0 (vy vel)))
          (setf (vy vel) 0f0)))
      ;; Pushing forward into a ledge at the surface: climb out.
      (when (and at-surface (< 0 iz)
                 (or (/= vx0 (vx vel)) (/= vz0 (vz vel)))
                 (ledge-ahead-p player surface yaw))
        (play-sound :climb-out)
        (setf (climbing player) *climb-time*)))))

(defun climb-out (player dt yaw)
  "Rise for DT seconds of a climb out, then step forward onto the ledge once clear of it."
  (let* ((feet (feet player))
         (vel (velocity player))
         (fx (sin yaw)) (fz (- (cos yaw)))
         (x0 (vx feet)) (z0 (vz feet)))
    (setf (vx vel) 0f0 (vz vel) 0f0 (vy vel) (float *climb-speed* 0f0)
          (grounded player) NIL)
    (move-axis player 1 (* *climb-speed* dt))
    (move-flat player (* fx 1.5 dt) (* fz 1.5 dt))
    (decf (climbing player) dt)
    ;; Over the ledge, or out of time: on with walking, a little forward.
    (when (or (< (* 1.0 dt) (sqrt (+ (expt (- (vx feet) x0) 2) (expt (- (vz feet) z0) 2))))
              (<= (climbing player) 0))
      (setf (climbing player) NIL
            (vx vel) (float (* fx 2.0) 0f0) (vy vel) 0f0 (vz vel) (float (* fz 2.0) 0f0)))))

(defun update-breath (player dt)
  "Use up PLAYER's breath while its eye is under water, regain it in air, and drown it
with none left."
  (let* ((feet (feet player))
         (under (swim-liquid-at (vx feet) (+ (vy feet) (eye player)) (vz feet))))
    (when (and (breath-under player) (not under) (< (breath player) (* *gasp-breath* *breath-time*)))
      (play-sound :surface-gasp))
    (setf (breath-under player) (and under T))
    (setf (breath player) (if under
                              (max 0.0 (- (breath player) dt))
                              (min *breath-time* (+ (breath player) (* *breath-refill* dt)))))
    (multiple-value-bind (timer damage)
        (burn-due (drown-timer player) dt (if (and under (<= (breath player) 0)) *drown-damage* 0.0))
      (setf (drown-timer player) timer)
      (when (< 0 damage)
        (hurt-player player damage feet :shove NIL :by :drowning)))))

(defun fall-dead (player dt)
  "The moment after death, with the world frozen: the view drops to the floor and rolls
over, the weapons sink off screen, and a body in mid-air comes down. The death screen
follows *DEATH-PANEL-DELAY* after it began, when the mouse goes back to the menu."
  (let* ((time (incf (death-time player) dt))
         (roll (min 1.0 (/ time *death-roll-time*)))
         (vel (velocity player)))
    (setf (eye player) (max *death-eye-height* (- (eye player) (* *death-fall-gravity* time dt)))
          ;; Eased both ways: it topples, then settles.
          (vz (rotation player)) (float (* *death-roll* roll roll (- 3.0 (* 2.0 roll))) 0f0)
          (weapon-lower player) (min 1.0 (+ (weapon-lower player) (* 2.0 dt))))
    (unless (or (grounded player) (swimming player))
      (decf (vy vel) (* *gravity* dt))
      (move-axis player 1 (* (vy vel) dt)))
    (when (and (mouse-look player) (<= *death-panel-delay* time))
      (release-mouse player))))

(defun update-stamina (player running dt)
  "Spend PLAYER's stamina while RUNNING, regain it otherwise. Running it empty leaves the
player WINDED until *WINDED-RECOVER*, so they don't stutter between a run and a walk."
  (if running
      (when (<= (decf (stamina player) (* *run-stamina* dt)) 0.0)
        (unless (winded player)
          (play-sound :winded))
        (setf (stamina player) 0.0
              (winded player) T))
      ;; Nor does it come back while the maul is charged or shakes the floor (maul.lisp), nor while
      ;; a spell overcharges or a stamina beam or an Absorb is held.
      (unless (or (maul-heaving-p player) (overcharging-p player)
                  (and (channel player) (eq (spell-tier (channel player)) :stamina)))
        (setf (stamina player) (min (max-stamina player) (+ (stamina player) (* *stamina-regen* dt))))))
  (when (and (winded player) (<= *winded-recover* (stamina player)))
    (setf (winded player) NIL)))

(defparameter *exit-reach* 1.6
  "Metres across from an exit's point at which the player leaves: the whole of the descent's
landing, 3 m wide, and not through its walls from the room next door.")
(defparameter *exit-height* 0.25
  "How far from an exit's floor the player's feet may be: under a riser, so it is the landing
and not the last step of the stair.")

(defun at-level-exit-p (player)
  (let ((feet (feet player)))
    (loop for exit across *level-exits*
          for at = (car exit)
          thereis (and (< (abs (- (vy feet) (vy at))) *exit-height*)
                       (< (+ (expt (- (vx feet) (vx at)) 2) (expt (- (vz feet) (vz at)) 2))
                          (* *exit-reach* *exit-reach*))))))

(define-handler (player tick :after) ()
  (when (and (not (frozen-p)) (< 0 (health player)) (not (whirl player)) (at-level-exit-p player))
    ;; Not now: DESCEND's rebuild has to wait for the menu controller's tick.
    (queue-menu-action 'descend)))

(define-handler (player tick) (dt)
  (when (frozen-p)
    (when (eq *game-state* :dead)
      (fall-dead player dt))
    ;; Still place the camera, so a game that starts frozen (the main menu) shows the level.
    (place-camera player)
    (return))
  (incf (run-time player) dt)
  (setf (blessed player) (max 0.0 (- (blessed player) dt)))
  (setf (cast-timer player) (max 0.0 (- (cast-timer player) dt))
        (pain player) (max 0.0 (- (pain player) dt))
        (restore-flash player) (max 0.0 (- (restore-flash player) dt))
        (guard-broken player) (max 0.0 (- (guard-broken player) dt))
        (snare-guard player) (max 0.0 (- (snare-guard player) dt)))
  ;; Roots let go of a player whose bloodroot is dead or gone (a reset, a rebuild).
  (let ((root (getf (snare player) :root)))
    (when (and root (or (dead root) (not (find root *creatures* :test #'eq))))
      (break-snare player NIL)))
  (when (statuses player)
    (update-statuses player dt))
  (when (cast-time player)
    (if (overcharging-p player)
        (overcharge-step player dt)
        (progn
          (incf (cast-time player) dt)
          (when (and (pending-spell player) (<= *cast-release* (cast-time player)) (not (overcharging-p player)))
            (release-spell player)))))
  (update-channel player dt)
  (start-held-casts player)
  (update-weapons player dt)
  (let* ((dt (min dt 0.05))
         (yaw (vy (rotation player)))
         (crouching (held-p :crouch))
         (ix (- (if (held-p :strafe-right) 1.0 0.0) (if (held-p :strafe-left) 1.0 0.0)))
         (iz (- (if (held-p :forward) 1.0 0.0) (if (held-p :back) 1.0 0.0)))
         (wx (+ (* iz (sin yaw)) (* ix (cos yaw))))
         (wz (+ (* iz (- (cos yaw))) (* ix (sin yaw))))
         (wlen (sqrt (+ (* wx wx) (* wz wz))))
         (liquid (let ((feet (feet player))) (liquid-at (vx feet) (+ (vy feet) 0.05) (vz feet))))
         ;; A jump from a liquid stays slowed until it lands outside one.
         (kind (if (grounded player)
                   (let ((now (and liquid (liquid-kind liquid))))
                     (when (and now (not (eq (wading player) now)) (liquid-property now :step-sound))
                       (play-sound (liquid-property now :step-sound)))
                     (setf (wading player) now))
                   (if liquid (liquid-kind liquid) (wading player))))
         (raise (block-raise player))
         (heaving (or (maul-heaving-p player) (overcharging-p player)))
         (running (and (held-p :run) (< 0.0 wlen) (not crouching) (= 0.0 raise) (not heaving) (not (channel player))
                       (not (winded player)) (not (whirl player))))
         ;; The raised shield slows the player to a walk and below, and so does the maul's charge
         ;; and its earthshake (maul.lisp).
         (speed (* (cond (crouching *crouch-speed*)
                         (running *run-speed*)
                         (T *walk-speed*))
                   (+ 1.0 (* raise (- *block-speed-scale* 1.0)))
                   (maul-speed-scale player)
                   (cond ((channel player) *channel-speed-scale*)
                         ((overcharging-p player) *overcharge-speed*)
                         (T 1.0))
                   (if (< iz 0.0) *backpedal-scale* 1.0)
                   (if kind (liquid-property kind :speed) 1.0)
                   (slow-factor player)
                   ;; Held by a bloodroot's roots: no walk, though the hands still work.
                   (if (snared-p player) 0.0 1.0))))
    (when (< 1.0 wlen)
      (setf wx (/ wx wlen) wz (/ wz wlen)))
    (whirl-transitions player dt)
    (let ((water (swim-water player))
          (vx0 (vx (velocity player)))
          (vy0 (vy (velocity player)))
          (vz0 (vz (velocity player))))
      (setf (splash-timer player) (max 0.0 (- (splash-timer player) dt)))
      (unless (eq (swimming player) (and water T))
        (when (<= (splash-timer player) 0.0)
          (play-sound (if water :splash-in :splash-out))
          (setf (splash-timer player) *splash-gap*)))
      (setf (swimming player) (and water T))
      (cond ((whirl player)
             (orbit-player player dt wx wz))
            ((climbing player)
             (climb-out player dt yaw))
            (water
             (setf (footing player) NIL)
             (swim player water dt ix iz
                   (- (if (held-p :jump) 1.0 0.0) (if crouching 1.0 0.0))
                   running yaw))
            (T (walk player dt wx wz wlen speed kind crouching)))
      (note-impacts player vx0 vy0 vz0 dt)
      (body-sounds player dt))
    (update-stamina player running dt)
    (note-fall-trace player)
    (when (< (vy (feet player)) *kill-height*)
      (report-fall player)
      (respawn player))
    ;; Standing in lava burns, and so does the wind of a vortex holding the player; under
    ;; water with no breath left, drowning.
    (let ((feet (feet player)))
      (multiple-value-bind (timer damage)
          (burn-due (burn-timer player) dt (+ (hazard-at (vx feet) (+ (vy feet) 0.05) (vz feet))
                                              (whirl-damage player)))
        (setf (burn-timer player) timer)
        (when (< 0 damage)
          (hurt-player player damage feet :shove NIL :by (if (whirl player) :tornado :lava)))))
    (update-breath player dt)
    ;; Ease the eye toward standing or crouching height, then place the camera.
    (let ((target (if (and crouching (not (swimming player))) *crouch-eye-height* *eye-height*)))
      (setf (eye player) (+ (eye player) (* (- target (eye player)) (min 1.0 (* *eye-height-speed* dt))))))
    (update-camera-shake player dt)
    (place-camera player)))

(defun body-sounds (player dt)
  "Footsteps on foot (in snow on snow), a stroke now and then swimming, and the loops of a
slide on ice, of the water round an eye under it and of a vortex's wind."
  (let* ((vel (velocity player))
         (feet (feet player))
         (speed (sqrt (+ (expt (vx vel) 2) (expt (vz vel) 2))))
         (on-foot (and (grounded player) (not (swimming player)) (not (whirl player))
                       (not (climbing player)) (< 0.5 speed)))
         (sliding (and on-foot (footing player))))
    (cond ((and on-foot (not sliding))
           (when (<= (decf (stride-left player) (* speed dt)) 0.0)
             (setf (stride-left player) *footstep-stride*)
             (play-sound (if (eq (floor-tread (vx feet) (vy feet) (vz feet) *player-radius*) :snow)
                             :footstep-snow
                             :footstep-stone)
                         NIL *footstep-volume*)))
          ((and (swimming player) (not (climbing player)))
           (when (<= (decf (stride-left player) (* (+ speed (abs (vy vel))) dt)) 0.0)
             (setf (stride-left player) *swim-stroke-stride*)
             (play-sound :swim-stroke)))
          ;; Standing, or in the air: the first step after comes soon.
          (T (setf (stride-left player) (* 0.4 *footstep-stride*))))
    (let ((at (location player)))
      (setf (slide-sound player) (hold-loop (slide-sound player) (and sliding :ice-slide) at
                                            (min 1.0 (/ speed *ice-slide-speed*)))
            (underwater-sound player) (hold-loop (underwater-sound player) (and *eye-underwater* :underwater) at)
            (whirl-sound player) (hold-loop (whirl-sound player)
                                           (and (or (whirl player) (< (wind-slow-factor player) 1.0)) :whirl-wind)
                                           at (if (whirl player) 1.0 *wind-volume*))))))

(defmethod hit-surface ((player player) speed x y z &key (threshold *impact-speed*) by)
  (declare (ignore x y z))
  ;; No shove, so the shield can't help.
  (when (< threshold speed)
    (play-sound :body-impact)
    (let ((damage (impact-damage speed threshold)))
      (hurt-player player damage (feet player) :shove NIL
                   :by (or by (if (or (whirl player) (flung player)) :tornado :impact)))
      (kick-camera (destructuring-bind (least most) *camera-shake-impact*
                     (+ least (* (- most least) (/ damage *impact-max*))))
                   player))
    (hit-stop)))

(defun note-impacts (player vx0 vy0 vz0 dt)
  "After PLAYER, moving at VX0 VY0 VZ0, has moved this DT-second tick: what stopped them
hurts if they hit it fast enough (HIT-SURFACE), and landing ends a throw. A wall doesn't
while they slide on ice, nor a floor under water, and their own falls only from higher up."
  (let ((vel (velocity player)))
    ;; MOVE-AXIS zeroes the component it was blocked on.
    (unless (or (footing player) (and (= 0 vx0) (= 0 vz0)))
      (hit-across player (if (= 0 (vx vel)) vx0 0f0) (if (= 0 (vz vel)) vz0 0f0) dt))
    (cond ((and (grounded player) (< vy0 0) (not (swimming player)))
           (when (< *land-sound-speed* (- vy0))
             (play-sound :land))
           (if (flung player)
               (hit-surface player (- vy0) 0.0 -1.0 0.0)
               (hit-surface player (- vy0) 0.0 -1.0 0.0 :threshold *fall-impact-speed* :by :fall)))
          ((and (< 0 vy0) (= 0 (vy vel)))
           (hit-surface player vy0 0.0 1.0 0.0)))
    (when (and (flung player) (or (grounded player) (swimming player)))
      (setf (flung player) NIL))))

(defun snared-p (player)
  "True while a bloodroot's roots hold PLAYER (bloodroot.lisp): no walk, run or jump."
  (eq :held (getf (snare player) :phase)))

(defparameter *snare-guard* 2.5 "Seconds after a snare ends before roots may close on the player again.")

(defun break-snare (player &optional (sound :snare-break))
  "End the roots' snare on PLAYER, closing or holding: torn free, burnt, or let go."
  (when (snare player)
    (setf (snare player) NIL
          (snare-guard player) (float *snare-guard* 0f0))
    (when sound (play-sound sound))))

(defun walk (player dt wx wz wlen speed kind crouching)
  "Move PLAYER on foot or through the air for DT seconds, wishing along WX WZ (WLEN long)
at SPEED, out of liquid KIND if any."
  (let ((vel (velocity player)))
    (setf (footing player) (and (grounded player)
                                (let ((feet (feet player))) (floor-footing (vx feet) (vy feet) (vz feet) *player-radius*))))
    (cond ((footing player)
           ;; On ice the wish only pushes the momentum (footing.lisp).
           (footing-drag vel (footing player) dt (= 0 wlen))
           (footing-push vel wx wz speed (footing player) dt))
          ;; Thrown by a vortex, no wish means no change: nothing slows the flight.
          ((and (flung player) (= 0 wlen)))
          (T
           ;; Accelerate horizontal velocity toward the wished velocity. In the air that steers,
           ;; and only an empty wish brakes: a launch faster than a run (off ice) keeps its speed.
           (let* ((speed (if (grounded player)
                             speed
                             (max speed (sqrt (+ (expt (vx vel) 2) (expt (vz vel) 2))))))
                  (dvx (- (* wx speed) (vx vel)))
                  (dvz (- (* wz speed) (vz vel)))
                  (dlen (sqrt (+ (* dvx dvx) (* dvz dvz))))
                  (max-dv (* *ground-acceleration* (if (grounded player) 1.0 *air-control*) dt)))
             (when (< max-dv dlen)
               (setf dvx (* dvx (/ max-dv dlen)) dvz (* dvz (/ max-dv dlen))))
             (incf (vx vel) dvx)
             (incf (vz vel) dvz))))
    ;; Roots hold the feet, on ice too.
    (when (snared-p player)
      (setf (vx vel) 0f0 (vz vel) 0f0))
    (when (and (grounded player) (held-p :jump) (not crouching) (not (maul-heaving-p player)) (not (overcharging-p player))
               (not (snared-p player))
               (<= *jump-stamina* (stamina player)))
      (decf (stamina player) *jump-stamina*)
      (play-sound :jump)
      (setf (vy vel) (float (* *jump-speed* (if kind (liquid-property kind :jump) 1.0)) 0f0)))
    (decf (vy vel) (* *gravity* dt))
    ;; Steps only while walking: not mid-air, and not on the frame a jump starts.
    (let ((walking (and (grounded player) (<= (vy vel) 0)))
          (*walk-through-bodies* (let ((feet (feet player)))
                                   (body-overlapping (vx feet) (vy feet) (vz feet)
                                                     (float *player-radius* 0f0) (float *player-height* 0f0)
                                                     player))))
      (setf (grounded player) NIL)
      (move-pulled player dt walking)
      (move-axis player 1 (* (vy vel) dt))
      (when (and walking (not (grounded player)))
        (snap-to-ground player)))))

(defun shove-player (player from speed &optional lift)
  "Push PLAYER away from point FROM at SPEED m/s, and with LIFT, up at that many m/s. From
right under them (a grave circle on someone who stood still), back from where they face."
  (let* ((feet (feet player))
         (vel (velocity player))
         (speed (float speed 0f0))
         (dx (- (vx feet) (vx from)))
         (dz (- (vz feet) (vz from)))
         (len (sqrt (+ (* dx dx) (* dz dz)))))
    (cond ((< 1f-4 len)
           (incf (vx vel) (* speed (/ dx len)))
           (incf (vz vel) (* speed (/ dz len))))
          (T
           (let ((yaw (vy (rotation player))))
             (decf (vx vel) (* speed (sin yaw)))
             (incf (vz vel) (* speed (cos yaw))))))
    (when lift
      (setf (vy vel) (max (vy vel) (float lift 0f0))))))

(defun facing-point-p (player from arc)
  "True if point FROM lies within ARC radians across of where PLAYER faces."
  (let* ((feet (feet player))
         (dx (- (vx from) (vx feet)))
         (dz (- (vz from) (vz feet)))
         (len (sqrt (+ (* dx dx) (* dz dz))))
         (yaw (vy (rotation player))))
    (and (< 1f-4 len)
         (< (acos (max -1.0 (min 1.0 (/ (- (* dx (sin yaw)) (* dz (cos yaw))) len)))) arc))))

(defun shield-facing-p (player from &optional (margin 0.0))
  "True if PLAYER's shield is raised at all (sword.lisp) and point FROM lies within
*BLOCK-ARC*, plus MARGIN radians, of where the player faces."
  (and (eq (weapon player) :sword)
       (< 0.0 (block-raise player))
       (facing-point-p player from (+ *block-arc* margin))))

(defun shield-blocks-p (player from)
  "True if PLAYER's shield is fully raised and a blow from point FROM comes from within
*BLOCK-ARC* of where the player faces."
  (and (<= 1.0 (block-raise player))
       (shield-facing-p player from)))

(defun break-guard (player seconds)
  "Knock PLAYER's shield aside: down at once, a bash in progress cut off, and not raised
again for SECONDS."
  (setf (guard-broken player) (max (guard-broken player) (float seconds 0f0))
        (block-raise player) 0.0
        (bash-time player) NIL
        (bash-pending player) NIL))

(defun player-dies (player by)
  "PLAYER's health ran out, to BY. On a generated level the run is over: the world freezes,
PLAYER falls (FALL-DEAD) and the death screen comes up. Elsewhere the run starts over."
  (play-sound :player-death)
  (cond ((not (eq *level* :generated))
         ;; Not now: this runs inside a creature's tick, and RESET-RUN despawns entities.
         (queue-menu-action 'reset-run))
        ((not (eq *game-state* :dead))
         ;; A vortex lets go of the dead: they fall, with no wind across the view.
         (clear-whirl player)
         (setf *game-state* :dead
               ;; A boss by its title (boss.lisp), a string; any other creature by its kind.
               (killed-by player) (typecase by
                                    (boss (boss-title by))
                                    (creature (type-of by))
                                    (T by))
               (death-time player) 0.0
               (vy (velocity player)) (min 0f0 (vy (velocity player)))))))

(defun hurt-player (player amount from &key (shove T) lift guard-break unblockable blockable block-cost by)
  "Take AMOUNT health from PLAYER, struck from point FROM: a red flash, a shove away
from FROM and hit-stop. SHOVE is T for *PLAYER-KNOCKBACK*, a speed in m/s, or NIL (a
burn: only the flash). LIFT, in m/s, also throws the player up off their feet, where a
shove carries much further than on the ground. A blow the raised shield meets
(SHIELD-BLOCKS-P; never an UNBLOCKABLE one) costs *BLOCK-STAMINA-SCALE* stamina a point of
damage, does *BLOCK-DAMAGE-SCALE* of its damage, at least 1, and shoves and lifts
*BLOCK-SHOVE-SCALE* as far; with GUARD-BREAK it also knocks the shield aside for that many
seconds (BREAK-GUARD). BLOCKABLE lets the shield meet a blow with no SHOVE (a creature's held
beam's pulse), and BLOCK-COST, stamina, replaces what it costs the shield. With too little stamina
the blow goes through in full, takes what
stamina is left and knocks the shield aside for at least *STAMINA-GUARD-BREAK*. BY is what
did it, a creature, :LAVA or :DROWNING, for the death screen. At zero health the player
dies (PLAYER-DIES). Once the boss is dead (RUN-WON-P, boss.lisp), nothing hurts the player.
Returns true if the shield took the blow."
  (let ((blocked NIL))
    (when (and (< 0 (health player)) (not (run-won-p)))
      (setf blocked (and (or shove blockable) (not unblockable) (shield-blocks-p player from)))
      (when blocked
        (let ((cost (or block-cost (* amount *block-stamina-scale*))))
          (cond ((<= cost (stamina player))
                 (decf (stamina player) cost)
                 (setf amount (max 1 (round (* amount *block-damage-scale*))))
                 (play-sound (if guard-break :shield-guard-break :shield-block))
                 (when guard-break
                   (break-guard player guard-break)))
                (T
                 (setf (stamina player) 0.0
                       blocked NIL)
                 (play-sound :shield-guard-break)
                 (break-guard player (max *stamina-guard-break* (or guard-break 0)))))))
      ;; The priest's blessing (dialogue.lisp).
      (when (< (blessing-scale player) 1.0)
        (flare-veil :bless))
      (setf amount (max 1 (round (* amount (blessing-scale player)))))
      ;; A ward (magic.lisp) takes what it can of what gets past the shield.
      (setf amount (absorb-ward player amount))
      ;; A burn's every tick would grunt: only a blow or a crash does.
      (when (and (not blocked) (< amount (health player)))
        (cond ((or shove (member by '(:impact :fall)))
               (play-sound :player-hurt))
              ((member by '(:lava :tornado))
               (play-sound :player-burn))
              ((eq by :drowning)
               (play-sound :drowning))))
      (incf (damage-taken player) (min amount (health player)))
      (decf (health player) amount)
      (when (< 0 amount)
        (setf (pain player) *pain-time*))
      (when shove
        (let ((k (if blocked *block-shove-scale* 1.0)))
          (shove-player player from (* k (if (eq shove T) *player-knockback* shove)) (and lift (* k lift))))
        (hit-stop)
        (kick-camera (hurt-shake amount) player)))
    (when (<= (health player) 0)
      (player-dies player by))
    blocked))

(defun hurt-shake (amount)
  "The camera shake a blow taken of AMOUNT damage gives: none under *CAMERA-SHAKE-HURT-FROM*."
  (if (< amount *camera-shake-hurt-from*)
      0.0
      (destructuring-bind (least most) *camera-shake-hurt*
        (+ least (* (- most least)
                    (min 1.0 (/ (- amount *camera-shake-hurt-from*)
                                (float (- *camera-shake-hurt-full* *camera-shake-hurt-from*)))))))))

(defun player-at-p (player point margin)
  "True if POINT lies in PLAYER's body, grown by MARGIN metres."
  (let ((feet (feet player))
        (r (+ *player-radius* margin)))
    (and (< (abs (- (vx point) (vx feet))) r)
         (< (abs (- (vz point) (vz feet))) r)
         (< (- (vy feet) margin) (vy point) (+ (vy feet) *player-height* margin)))))

;; A creature's spell, hitting the player: the shove goes the way its source pushes.
(defmethod apply-effect ((kind (eql :knockback)) effect (target player) source)
  (let ((blocked (and (not (effect-unblockable-p source))
                      (shield-blocks-p target (effect-origin source)))))
    (shove-player target (v- (feet target) (effect-direction source target))
                  (* (float (roll (effect-magnitude effect)) 0f0)
                     (if blocked *block-shove-scale* 1.0)))))

(defun teleport-player (player to &key yaw)
  "Put PLAYER's feet at TO at once, stopped, out of any vortex, the eye at standing height
(no step's easing), turned to YAW if given; the view flashes as a pickup's does."
  (clear-whirl player)
  (v<- (feet player) to)
  (let ((vel (velocity player)))
    (setf (vx vel) 0f0 (vy vel) 0f0 (vz vel) 0f0))
  (setf (eye player) *eye-height*
        (wading player) NIL
        (restore-flash player) *restore-flash-time*
        (restored player) :rift)
  (when yaw
    (setf (vy (rotation player)) (float yaw 0f0)))
  (place-camera player))

;;; Falling out of the world is a bug in the level or in collision, and by the time the player
;;; is put back at the start nothing shows where it happened. So the last *FALL-TRACE-TICKS*
;;; ticks of the player's movement are kept, and a fall logs them.

(defparameter *fall-trace-ticks* 200 "Ticks of movement kept for REPORT-FALL: 2 s.")
(defvar *fall-trace* (make-array (* 8 200) :element-type 'single-float :initial-element 0f0)
  "Per tick: the feet, the velocity, grounded and whether the body overlaps a solid (1 or 0).")
(defvar *fall-trace-index* 0 "The tick NOTE-FALL-TRACE writes next.")

(defun note-fall-trace (player)
  (let* ((trace *fall-trace*)
         (i (* 8 (mod *fall-trace-index* *fall-trace-ticks*)))
         (feet (feet player))
         (vel (velocity player)))
    (setf (aref trace i) (vx feet) (aref trace (+ i 1)) (vy feet) (aref trace (+ i 2)) (vz feet)
          (aref trace (+ i 3)) (vx vel) (aref trace (+ i 4)) (vy vel) (aref trace (+ i 5)) (vz vel)
          (aref trace (+ i 6)) (if (grounded player) 1f0 0f0)
          (aref trace (+ i 7)) (if (overlapping-solid feet) 1f0 0f0))
    (incf *fall-trace-index*)))

(defun report-fall (player)
  "Log where PLAYER fell out of the world: every tick that moved the feet more than 0.3 m up or
down or ended inside a solid, and a sample every 0.2 s, oldest first."
  (declare (ignore player))
  (let ((trace *fall-trace*) (n *fall-trace-ticks*) (lines ()) (py NIL))
    (loop for k from (max 0 (- *fall-trace-index* n)) below *fall-trace-index*
          for i = (* 8 (mod k n))
          for y = (aref trace (+ i 1))
          for age = (* 0.01 (- *fall-trace-index* k))
          do (when (or (zerop (mod k 20)) (< 0.5 (aref trace (+ i 7))) (and py (< 0.3 (abs (- y py)))))
               (push (format NIL "-~,2fs feet ~,2f ~,2f ~,2f vel ~,1f ~,1f ~,1f~:[~; grounded~]~:[~; INSIDE A SOLID~]"
                             age (aref trace i) y (aref trace (+ i 2))
                             (aref trace (+ i 3)) (aref trace (+ i 4)) (aref trace (+ i 5))
                             (< 0.5 (aref trace (+ i 6))) (< 0.5 (aref trace (+ i 7))))
                     lines))
             (setf py y))
    (v:warn :hexmaw "The player fell out of the world (level ~a, seed ~a) and goes back to the start. Last ticks:~%~{  ~a~%~}"
            *level* *last-level-seed* (nreverse lines))))

(defun respawn (player)
  (clear-whirl player)
  (let ((feet (feet player)))
    (setf (vx feet) (vx *spawn-point*) (vy feet) (vy *spawn-point*) (vz feet) (vz *spawn-point*)))
  (setf (vx (velocity player)) 0f0 (vy (velocity player)) 0f0 (vz (velocity player)) 0f0))
