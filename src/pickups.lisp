(in-package #:hexmaw)

;;; Pickups: things hovering in the level that the player takes by touching them. Herbs give
;;; health back at once and a shard mana; at full, one stays where it is. A potion goes into the
;;; inventory (inventory.lisp) instead, to be drunk later, unless there's no room for it.
;;; The blocks say where one may go (`pickup` in a blueprint, *PICKUP-SPOTS*), and each
;;; generated level puts as many in those spots as its monsters call for (PLACE-PICKUPS).
;;; A taken pickup stays in the scene, undrawn, so a reset only has to clear the flag.

;; The strips' cell heights, at the monsters' 64 px per metre.
(define-fx-animation pickup-herbs "sprites/pickups/herbs" :fps 5 :loop T :size (/ 32 64.0))
(define-fx-animation pickup-health-potion "sprites/pickups/flask" :fps 5 :loop T :size (/ 38 64.0))
(define-fx-animation pickup-shard "sprites/pickups/shard" :fps 5 :loop T :size (/ 28 64.0))
(define-fx-animation pickup-mana-potion "sprites/pickups/mana-potion" :fps 5 :loop T :size (/ 38 64.0))
(define-fx-animation pickup-gold "sprites/pickups/gold" :fps 4 :loop T :size (/ 14 64.0))

(defparameter *pickup-kinds*
  '((:herbs :animation pickup-herbs :resource :health :amount 15)
    (:health-potion :animation pickup-health-potion :item :health-potion :resource :health :amount 40)
    (:shard :animation pickup-shard :resource :mana :amount 28)
    (:mana-potion :animation pickup-mana-potion :item :mana-potion :resource :mana :amount 50)
    (:gold :animation pickup-gold :resource :gold :amount 12))
  "What each kind of pickup restores, and how much, at once or as the :ITEM it gives (keep :AMOUNT
the item's, *ITEM-KINDS*: a level's budget counts it).")

(defparameter *pickup-hover* 0.15 "Metres from the floor to the bottom of a pickup.")
(defparameter *pickup-bob* 0.04 "Metres a pickup bobs up and down from its height.")
(defparameter *pickup-bob-rate* 2.5 "Radians per second of the bob.")
(defparameter *pickup-reach* 0.9 "Metres across from the player's centre at which a pickup is touched.")
(defparameter *pickup-below* 0.4
  "How far under the floor a pickup stands on the player's feet may be and still touch it: a
step's height, so one on a 0.8 m sarcophagus takes a jump.")
(defparameter *pickup-above* 0.8
  "How far over that floor the player's feet may be: the top of the pickup, about.")

(defparameter *health-per-monster* 10 "Health a generated level's pickups restore, per monster in it.")
(defparameter *mana-per-monster* 15 "Mana a generated level's pickups restore, per monster in it.")
(defparameter *pickup-potion-every* 2 "Every so many pickups of a resource, one is a potion, on a reward spot if one is free.")
(defparameter *pickup-room-weight* 2 "How much likelier a spot in a room is than one in a corridor.")
(defparameter *gold-per-monster* 6
  "Gold a generated level's gold pickups hold, per monster in it, at the first depth (GOLD-SCALE).
Placed after the health and mana, on the spots they leave.")
(defparameter *kill-gold* '((imp 4) (skeleton-warrior 3) (acolyte 7) (harpy 7) (knight 10) (necromancer 14)
                            (gale-wraith 12) (ogre 16) (boss 120))
  "Coin a monster the player kills drops straight into the purse, by class (the first that it is
of), at the first depth (GOLD-SCALE). One that is no class here drops 5.")
(defparameter *gold-depth-step* 0.3 "How much more gold each depth past the first is worth.")

(defun gold-scale (&optional (depth *run-depth*))
  "How much a coin count at the first depth is worth at DEPTH."
  (+ 1.0 (* *gold-depth-step* (1- depth))))

(defun monster-p (creature)
  "True if CREATURE counts as one of the level's monsters: built with it, not raised in play,
and not one of the settlement's townsfolk."
  (and (not (summoned creature)) (not (townsfolk-p creature))))

(defparameter *jump-reach* 1.0 "Metres above a floor the player can jump to get onto: a reward spot's limit.")

(defun pickup-property (kind key)
  (getf (rest (or (assoc kind *pickup-kinds*) (error "No pickup kind ~s." kind))) key))

(defvar *pickups* (make-array 0 :adjustable T :fill-pointer T)
  "Every pickup in the level, taken or not, in the order they were placed: a save names the
taken ones by their place here. BUILD-LEVEL empties it.")

(define-shader-entity pickup (upright-fx)
  ((kind :initarg :kind :reader pickup-kind)
   (ground :initarg :ground :reader pickup-ground :documentation "Height of the floor it stands on.")
   (taken :initform NIL :accessor taken)))

(defun add-pickup (container kind x y z &key (phase 0.0))
  "A pickup of KIND standing on the floor at X Y Z. PHASE is seconds into its glint and bob."
  (let* ((animation (find-fx-animation (pickup-property kind :animation)))
         (pickup (make-instance 'pickup :animation animation :kind kind :ground (float y 0f0)
                                        :location (vec x (+ y *pickup-hover* (* 0.5 (animation-size animation))) z))))
    (setf (age pickup) phase)
    (vector-push-extend pickup *pickups*)
    (enter pickup container)
    pickup))

(defgeneric collect-pickup (pickup player)
  (:documentation "Give PICKUP to PLAYER. True if it was used up, NIL if it stays where it is."))

(defun flash-resource (player resource)
  "Flash the view in RESOURCE's colour (RESTORE-FLASH, hud.lisp)."
  (setf (restore-flash player) *restore-flash-time*
        (restored player) resource))

(defun give-gold (player amount)
  "Put AMOUNT coin in PLAYER's purse, flash the view and say so."
  (incf (gold player) amount)
  (flash-resource player :gold)
  (hud-say "+~d gold" amount))

(defun restore-resource (player resource amount)
  "Give PLAYER AMOUNT of RESOURCE, :HEALTH or :MANA (or :GOLD, never full), and flash the view.
NIL if it was full."
  (when (eq resource :gold)
    (give-gold player (round (* amount (gold-scale))))
    (return-from restore-resource T))
  (when (ecase resource
          (:health (when (< (health player) (max-health player))
                     (setf (health player) (min (max-health player) (+ (health player) amount)))))
          (:mana (when (< (mana player) (max-mana player))
                   (setf (mana player) (min (max-mana player) (+ (mana player) amount))))))
    (flash-resource player resource)
    T))

(defmethod collect-pickup ((pickup pickup) player)
  (let* ((kind (pickup-kind pickup))
         (resource (pickup-property kind :resource))
         (item (pickup-property kind :item)))
    (if item
        (when (give-item player item)
          (flash-resource player resource)
          T)
        (restore-resource player resource (pickup-property kind :amount)))))

(defun touching-pickup-p (pickup player)
  (let* ((feet (feet player))
         (at (location pickup))
         (dx (- (vx at) (vx feet)))
         (dz (- (vz at) (vz feet)))
         (dy (- (vy feet) (pickup-ground pickup))))
    (and (< (+ (* dx dx) (* dz dz)) (* *pickup-reach* *pickup-reach*))
         (< (- *pickup-below*) dy *pickup-above*))))

(define-handler (pickup tick :after) ()
  (unless (or (taken pickup) (frozen-p))
    (setf (vy (location pickup))
          (+ (pickup-ground pickup) *pickup-hover* (* 0.5 (animation-size (sprite-animation pickup)))
             (* *pickup-bob* (sin (* *pickup-bob-rate* (age pickup))))))
    (when (and *player* (< 0 (health *player*)) (touching-pickup-p pickup *player*)
               (collect-pickup pickup *player*))
      (setf (taken pickup) T))))

(defmethod render :around ((pickup pickup) (program shader-program))
  (unless (taken pickup)
    (call-next-method)))

(defun restore-pickups ()
  "Every pickup back in its place, for a new run."
  (loop for pickup across *pickups* do (setf (taken pickup) NIL)))

(defun taken-pickup-indices ()
  (loop for pickup across *pickups*
        for i from 0
        when (taken pickup) collect i))

(defun take-pickups-at (indices)
  (dolist (i indices)
    (when (< i (length *pickups*))
      (setf (taken (aref *pickups* i)) T))))

;;; Where they go.

(defun spot-reached-p (spot seen)
  "True if the player, who can walk to the cells SEEN (NAV-REACHED), can get to SPOT. A floor
spot's own cell must be one of them. A reward spot's may instead be up to *JUMP-REACH* above
one of them, within 2 m across: a jump onto what it stands on."
  (let* ((p (getf spot :position))
         (r *player-radius*) (h *player-height*)
         (y (+ (vy p) 0.1)))
    (or (multiple-value-bind (i j k) (nav-nearest-fitting (vec (vx p) y (vz p)) r h :search 1 :reach 0.5)
          (and i (= 1 (sbit seen (nav-index i j k)))))
        (and (eq :reward (getf spot :tier))
             (multiple-value-bind (ci cj) (nav-cell (vx p) (vz p))
               (and ci
                    (loop for i from (- ci 4) to (+ ci 4)
                          thereis (loop for j from (- cj 4) to (+ cj 4)
                                        thereis (loop for k from 0 below (nav-layers *nav-grid*)
                                                      thereis (and (nav-fits-p i j k r h)
                                                                   (<= (- (vy p) *jump-reach*) (nav-floor i j k) (vy p))
                                                                   (= 1 (sbit seen (nav-index i j k)))))))))))))

(defun pick-spot (spots tiers used random &key fresh)
  "One of SPOTS at random, of the first of TIERS with any in a block not in USED, a room's
*PICKUP-ROOM-WEIGHT* times as likely as a corridor's; failing those, unless FRESH, of the first
with any at all. NIL if there are none."
  (flet ((pick (candidates)
           (flet ((weight (spot)
                    (if (member :room (block-tags (map-block-name (getf spot :block))))
                        *pickup-room-weight*
                        1)))
             (let ((roll (random (reduce #'+ candidates :key #'weight) random)))
               (dolist (spot candidates)
                 (decf roll (weight spot))
                 (when (< roll 0) (return spot)))))))
    (flet ((try (keep)
             (dolist (tier tiers)
               (let ((candidates (remove-if-not (lambda (spot) (and (eq tier (getf spot :tier)) (funcall keep spot)))
                                                spots)))
                 (when candidates (return (pick candidates)))))))
      (or (try (lambda (spot) (not (member (getf spot :block) used))))
          (and (not fresh) (try (constantly T)))))))

(defun scatter-pickups (container)
  "Fill a generated level's spots until its pickups restore what its monsters call for. Drawn
from a random state of their own, so the level and its monsters don't change."
  (let* ((random (sb-ext:seed-random-state *last-level-seed*))
         (*nav-hazards* :swim)
         (seen (multiple-value-bind (i j k) (nav-nearest-fitting *spawn-point* *player-radius* *player-height*)
                 (and i (nav-reached i j k *player-radius* *player-height* *step-height*))))
         ;; The player starts full, so nothing goes in the first room.
         (start (map-block-at (vx *spawn-point*) (+ (vy *spawn-point*) 0.1) (vz *spawn-point*)))
         (spots (when seen
                  (loop for spot across *pickup-spots*
                        when (and (not (eq start (getf spot :block))) (spot-reached-p spot seen))
                          collect spot)))
         (monsters (count-if #'monster-p *creatures*))
         (health-owed (* monsters *health-per-monster*))
         (mana-owed (* monsters *mana-per-monster*))
         (health-count 0) (mana-count 0)
         (used ()))
    (flet ((place (health-p)
             ;; True if there was somewhere to put it.
             (let* ((potion (= (1- *pickup-potion-every*)
                               (mod (if health-p health-count mana-count) *pickup-potion-every*)))
                    ;; A reward spot, but never at the cost of a block with two while another has none.
                    (spot (or (and potion (pick-spot spots '(:reward) used random :fresh T))
                              (pick-spot spots '(:floor :reward) used random))))
               (when spot
                 (let ((kind (if health-p
                                 (if potion :health-potion :herbs)
                                 (if potion :mana-potion :shard)))
                       (p (getf spot :position)))
                   (add-pickup container kind (vx p) (vy p) (vz p) :phase (random 10.0 random))
                   (setf spots (remove spot spots))
                   (push (getf spot :block) used)
                   (if health-p
                       (progn (incf health-count) (decf health-owed (pickup-property kind :amount)))
                       (progn (incf mana-count) (decf mana-owed (pickup-property kind :amount)))))
                 T))))
      ;; Whichever resource still owes the larger part of its budget goes next.
      (loop while (or (< 0 health-owed) (< 0 mana-owed))
            while (place (< (/ mana-owed (max 1 *mana-per-monster*)) (/ health-owed (max 1 *health-per-monster*)))))
      ;; Gold last, on what is left, so the pickups above keep their places in *PICKUPS*.
      (let ((gold-owed (* monsters *gold-per-monster*)))
        (loop while (< 0 gold-owed)
              do (let ((spot (pick-spot spots '(:floor :reward) used random)))
                   (unless spot (return))
                   (let ((p (getf spot :position)))
                     (add-pickup container :gold (vx p) (vy p) (vz p) :phase (random 10.0 random))
                     (setf spots (remove spot spots))
                     (push (getf spot :block) used)
                     (decf gold-owed (pickup-property :gold :amount)))))))
    (v:info :hexmaw "~d pickups for ~d monsters: ~d health, ~d mana~@[, ~d health and ~d mana short~]."
            (length *pickups*) monsters health-count mana-count
            (when (or (< 0 health-owed) (< 0 mana-owed)) (max 0 health-owed))
            (max 0 mana-owed))))

(defun fill-pickup-spots (container)
  "A pickup on every spot, alternating health and mana, to look them over in the gallery."
  (loop for spot across *pickup-spots*
        for p = (getf spot :position)
        for health-p = T then (not health-p)
        do (add-pickup container
                       (if (eq :reward (getf spot :tier))
                           (if health-p :health-potion :mana-potion)
                           (if health-p :herbs :shard))
                       (vx p) (vy p) (vz p))))

(defun place-pickups (container)
  "Put the level's pickups in. Last in BUILD-LEVEL: it asks the nav grid who can reach what."
  (case *level*
    (:generated (scatter-pickups container)
     (when *settlement* (place-settlement-pickups container)))
    (:gallery (fill-pickup-spots container))))

;;; Coin from kills: straight into the purse, nothing to pick up.

(defun kill-gold (creature)
  "Coin CREATURE drops, killed by the player, at this depth."
  (let ((entry (find-if (lambda (e) (typep creature (first e))) *kill-gold*)))
    (round (* (if entry (second entry) 5) (gold-scale)))))

(defmethod creature-died :after ((creature creature) by)
  (when (and (eq by *player*) (monster-p creature) (eq *level* :generated))
    (give-gold *player* (kill-gold creature))))

;;; The quest-giver's relic (dialogue.lisp): a pickup in the settlement's wing, hidden and out of
;;; reach until the quest for it is taken.

(define-fx-animation pickup-relic "sprites/pickups/relic" :fps 4 :loop T :size (/ 32 64.0))

(define-shader-entity quest-pickup (pickup) ())

(defun relic-sought-p ()
  (let ((quest (and *settlement* (settlement-quest *settlement*))))
    (and quest (eq :relic (getf quest :kind)) (eq :active (getf quest :state)))))

(defmethod collect-pickup ((pickup quest-pickup) player)
  (declare (ignore player))
  (when (relic-sought-p)
    (setf (getf (settlement-quest *settlement*) :carried) T)
    (hud-say "The reliquary. Take it back to the quest-giver.")
    T))

(defmethod render :around ((pickup quest-pickup) (program shader-program))
  (when (relic-sought-p)
    (call-next-method)))

(defun spot-free-p (spot)
  "True if no pickup stands on SPOT."
  (let ((p (getf spot :position)))
    (loop for pickup across *pickups*
          for at = (location pickup)
          never (< (+ (expt (- (vx at) (vx p)) 2) (expt (- (vz at) (vz p)) 2)) 0.01))))

(defun place-settlement-pickups (container)
  "The settlement's own: the relic on the free reward spot (or failing one, floor spot) in the
wing furthest from the town; and in a sacked town, its loot on the town's spots. After
SCATTER-PICKUPS, so its pickups keep their places in *PICKUPS*."
  (let* ((*nav-hazards* :swim)
         (seen (multiple-value-bind (i j k) (nav-nearest-fitting *spawn-point* *player-radius* *player-height*)
                 (and i (nav-reached i j k *player-radius* *player-height* *step-height*))))
         (wing (when seen
                 (loop for spot across *pickup-spots*
                       when (and (not (in-settlement-p (getf spot :position))) (spot-free-p spot)
                                 (spot-reached-p spot seen))
                         collect spot)))
         (far (first (sort (copy-list wing) #'>
                           :key (lambda (spot) (+ (if (eq :reward (getf spot :tier)) 1000 0)
                                                  (vdistance (getf spot :position) *spawn-point*)))))))
    (when far
      (let ((p (getf far :position))
            (animation (find-fx-animation 'pickup-relic)))
        (let ((relic (make-instance 'quest-pickup :animation animation :kind :relic :ground (float (vy p) 0f0)
                                                  :location (vec (vx p) (+ (vy p) *pickup-hover* (* 0.5 (animation-size animation))) (vz p)))))
          (vector-push-extend relic *pickups*)
          (enter relic container))))
    (when (eq (built-condition *settlement*) :sacked)
      (let ((loot '(:health-potion :gold :mana-potion :gold)))
        (loop for spot across *pickup-spots*
              when (and (in-settlement-p (getf spot :position)) (spot-free-p spot))
                do (let ((p (getf spot :position)))
                     (add-pickup container (pop loot) (vx p) (vy p) (vz p))
                     (unless loot (return))))))))
