(in-package #:hexmaw)

;;; The settlement: once a run, a level grown from the town block (data/blueprints/town.txt)
;;; instead of a start block, with a small wing of crypts and cells off its gates
;;; (*SETTLEMENT-LEVEL*, run.lisp). Its way down is in the town. Its faction, condition and
;;; name are drawn from the level's seed when it is built (MAKE-SETTLEMENT); the faction
;;; decides the watch's rule and prices, the condition who is there (a blueprint's npc and
;;; spawn conditions) and what happens in play. Townsfolk are in townsfolk.lisp, what they
;;; offer in dialogue.lisp.

;; The priest's blessing (dialogue.lisp), here since the HUD's status row shows it (status-icons.lisp).
(defparameter *bless-time* 300.0 "Seconds of play a blessing lasts.")
(defparameter *bless-scale* 0.75 "What blows do to a blessed player, as a share of their damage.")

(defparameter *factions*
  '((:ashen-temple :name "the Ashen Temple" :rule :no-casting
     :rule-text "No spell is cast within these walls."
     :crimes (:rule :assault :murder)
     :prices (:heal 0.6 :mana 0.6 :bless 0.8 :goods 1.1 :training 1.2) :bribable NIL)
    (:deepwardens :name "the Deepwardens" :rule :no-drawn-weapon :zones (:market :temple)
     :rule-text "No blade is drawn in the market or the temple."
     :crimes (:rule :assault :murder)
     :prices (:heal 1.0 :mana 1.0 :bless 1.0 :goods 1.0 :training 0.7) :bribable NIL)
    (:free-company :name "the Free Company" :rule NIL
     :rule-text "Keep your blade out of honest folk, and we'll get along."
     :crimes (:murder)
     :prices (:heal 1.1 :mana 1.1 :bless 1.2 :goods 0.8 :training 1.1) :bribable T :random-stock T))
  "The factions a settlement may belong to: the name, the watch's rule (what RULE-BROKEN-P
looks for), which crimes it punishes (REPORT-CRIME), price multipliers by service, and
whether its watch takes bribes.")

(defparameter *conditions* '((:thriving 3) (:besieged 2) (:sacked 1))
  "The conditions a settlement may be in, each with its weight: thriving, everything open;
besieged, the wing's monsters raid the gates; sacked, a few survivors, no watch, monsters in
the streets. A blueprint's npc and spawn conditions (CONDITION-EXCLUDED-P) say who is there.")

(defparameter *settlement-names*
  '("Emberwick" "Lowgate" "Saltmere" "Cinderhold" "Greywell" "Duskhollow" "Ashfall" "Brackenmoor"
    "Stonereach" "Mirewatch")
  "The names a settlement may have.")

(defparameter *shop-goods* '(:health-potion :mana-potion) "The items the shop sells (*ITEM-KINDS*).")

(defparameter *base-prices*
  '(:health-potion 30 :mana-potion 36 :heal 0.8 :mana 1.0 :bless 45 :training 60 :glyph 90)
  "Gold at the first depth: an item; healing a point of health or restoring one of mana; a
blessing; the trainer's first step (each step after costs more, TRAINING-PRICE); a glyph the
shopkeeper teaches (dialogue.lisp).")
(defparameter *price-groups* '(:health-potion :goods :mana-potion :goods :heal :heal :mana :mana :bless :bless
                               :training :training :glyph :goods)
  "Which of a faction's :PRICES multipliers each price takes.")
(defparameter *price-depth-step* 0.25 "How much dearer everything is per depth past the first.")
(defparameter *sell-share* 0.4 "What the shop pays for an item, as a share of its price.")
(defparameter *patient-reputation* 25 "Standing from which the watch lets one more broken rule go with a warning.")

(defclass settlement ()
  ((name :initarg :name :reader settlement-name)
   (faction :initarg :faction :reader settlement-faction :documentation "A key of *FACTIONS*.")
   (built-condition :initarg :condition :reader built-condition
                    :documentation "The condition the level was built in, which decides who is there.")
   (condition :initarg :condition :accessor settlement-condition
              :documentation "The condition now: a thriving or besieged town the player sacks is :SACKED.")
   (depth :initarg :depth :reader settlement-depth-of :documentation "The run's depth it stands at.")
   (seed :initarg :seed :reader settlement-seed)
   (block :initform NIL :accessor settlement-block :documentation "The town's MAP-BLOCK, once placed.")
   (strikes :initform 0 :accessor settlement-strikes
            :documentation "The player's crimes since the watch was last calmed, weighed (REPORT-CRIME).")
   (fine :initform NIL :accessor settlement-fine :documentation "Gold the watch wants paid, or NIL.")
   (fine-left :initform 0.0 :accessor settlement-fine-left :documentation "Seconds left to pay it.")
   (hostile :initform NIL :accessor settlement-hostile :documentation "True while the watch hunts the player.")
   (sacked-by :initform NIL :accessor sacked-by
              :documentation "Who killed the last guard in play: :PLAYER or :MONSTERS, or NIL.")
   (stock :initform () :accessor settlement-stock :documentation "What the shop has left: a plist of item kind and count.")
   (trained :initform () :accessor settlement-trained
            :documentation "Steps the trainer has given: a plist of :HEALTH, :MANA or :STAMINA and count.")
   (quest :initform NIL :accessor settlement-quest
          :documentation "The quest-giver's quest (QUEST-KINDS), a plist, or NIL before it is offered.")
   (raid-timer :initform 0.0 :accessor raid-timer :documentation "Seconds of play until the next raid, while besieged.")
   (raids-held :initform 0 :accessor raids-held :documentation "Raids beaten off: every raider dead.")
   (raid-on :initform NIL :accessor raid-on-p :documentation "True while a raid's monsters are coming.")
   (rule-grace :initform NIL :accessor rule-grace
               :documentation "Seconds left before a rule the player has been warned of counts as broken, or NIL."))
  (:documentation "The settlement of the level in play: what it is, drawn when the level is built,
and what has happened to it since."))

(defmethod print-object ((settlement settlement) stream)
  (print-unreadable-object (settlement stream :type T)
    (format stream "~a, ~(~a~), ~(~a~)" (settlement-name settlement) (settlement-faction settlement)
            (settlement-condition settlement))))

(defun weighted-pick (choices random)
  "One of CHOICES, a list of (thing weight), by weight, from RANDOM."
  (let ((pick (random (reduce #'+ choices :key #'second) random)))
    (loop for (thing weight) in choices
          do (decf pick weight)
          when (< pick 0) return thing
          finally (return (first (car (last choices)))))))

(defun make-settlement (seed depth &key faction condition)
  "The settlement of the level built from SEED at DEPTH: its faction, condition and name
drawn from SEED, unless FACTION and CONDITION (a save's) or *SETTLEMENT-OVERRIDE* fix them."
  (let* ((random (sb-ext:seed-random-state (logxor seed #x70E1)))
         (drawn-faction (nth (random (length *factions*) random) (mapcar #'first *factions*)))
         (drawn-condition (weighted-pick *conditions* random))
         (name (nth (random (length *settlement-names*) random) *settlement-names*)))
    (make-instance 'settlement
                   :name name :seed seed :depth depth
                   :faction (or faction (getf *settlement-override* :faction) drawn-faction)
                   :condition (or condition (getf *settlement-override* :condition) drawn-condition))))

(defmethod initialize-instance :after ((settlement settlement) &key)
  ;; The stock, from its own seed: 2 of each per depth, the Free Company's a random few more.
  (let ((random (sb-ext:seed-random-state (logxor (settlement-seed settlement) #x570C)))
        (depth (settlement-depth-of settlement)))
    (setf (settlement-stock settlement)
          (loop for kind in *shop-goods*
                collect kind
                collect (+ 1 depth (if (faction-property :random-stock settlement) (random 3 random) 0))))))

(defun note-town (map-block)
  "PLACE-BLOCK has placed a block tagged town: the settlement's."
  (when *settlement*
    (setf (settlement-block *settlement*) map-block)))

(defun faction-reputation (player faction)
  (getf (reputation player) faction 0))

(defun adjust-reputation (player faction amount)
  (setf (getf (reputation player) faction)
        (max -100 (min 100 (+ (faction-reputation player faction) amount)))))

(defun price (key &key (base (getf *base-prices* key)) (settlement *settlement*))
  "What KEY (an item, or a service of *BASE-PRICES*) costs here: dearer with depth, by the
faction's multiplier, and cheaper or dearer by the player's standing with it."
  (let ((faction (rest (assoc (settlement-faction settlement) *factions*)))
        (standing (if *player* (faction-reputation *player* (settlement-faction settlement)) 0)))
    (max 1 (round (* base
                     (+ 1 (* *price-depth-step* (1- (settlement-depth-of settlement))))
                     (getf (getf faction :prices) (getf *price-groups* key) 1.0)
                     (- 1 (/ standing 400)))))))

(defun faction-property (key &optional (settlement *settlement*))
  (getf (rest (assoc (settlement-faction settlement) *factions*)) key))

(defun settlement-condition-name ()
  "The condition the level is being built in, as a blueprint names it, or NIL with no settlement."
  (and *settlement* (string-downcase (built-condition *settlement*))))

(defun in-settlement-p (point)
  "True if POINT is inside the town block."
  (and *settlement* (settlement-block *settlement*)
       (let ((block (settlement-block *settlement*)))
         (and (<= (vx (map-block-low block)) (vx point) (vx (map-block-high block)))
              (<= (vy (map-block-low block)) (vy point) (vy (map-block-high block)))
              (<= (vz (map-block-low block)) (vz point) (vz (map-block-high block)))))))

(defun settlement-status ()
  "The settlement, for STATUS, or NIL without one."
  (let ((s *settlement*))
    (when s
      (format NIL "settlement ~a of ~a, ~(~a~)~:[ (built ~(~a~))~;~*~], wing of ~d room~:p"
              (settlement-name s) (faction-property :name s) (settlement-condition s)
              (eq (settlement-condition s) (built-condition s)) (built-condition s) *last-wing-rooms*))))
