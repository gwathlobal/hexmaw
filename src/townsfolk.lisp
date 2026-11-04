(in-package #:hexmaw)

;;; Townsfolk: the settlement's people (settlement.lisp), creatures that keep to their posts
;;; and never notice the player while calm (CALM-P). Each is one picture, seen from the front
;;; from every side, as Daggerfall's town folk are. A blueprint's npc action places them
;;; (PLACE-NPC), by role: the shopkeeper, the priest, the trainer and the quest-giver offer
;;; their services (dialogue.lisp), commoners stand about, and the watch's guards keep the
;;; faction's rule. A blow at one is a crime (REPORT-CRIME): the watch warns, then fines, then
;;; turns on the player. E talks to the one the player looks at (INTERACT).

(defparameter *townsfolk-height* 1.75 "Metres from a townsperson's feet to the top of its head.")

;; One picture each, a cell of art/townsfolk/lineup-*.png sliced at the monsters' 64 px per
;; metre (CLAUDE.md, "Townsfolk"). The guard's tabard is recoloured per faction.
(define-asset (hexmaw townsfolk-shopkeeper) image #p"sprites/townsfolk/shopkeeper.png" :min-filter :nearest :mag-filter :nearest)
(define-asset (hexmaw townsfolk-priest) image #p"sprites/townsfolk/priest.png" :min-filter :nearest :mag-filter :nearest)
(define-asset (hexmaw townsfolk-trainer) image #p"sprites/townsfolk/trainer.png" :min-filter :nearest :mag-filter :nearest)
(define-asset (hexmaw townsfolk-quest-giver) image #p"sprites/townsfolk/quest-giver.png" :min-filter :nearest :mag-filter :nearest)
(define-asset (hexmaw townsfolk-commoner-a) image #p"sprites/townsfolk/commoner-a.png" :min-filter :nearest :mag-filter :nearest)
(define-asset (hexmaw townsfolk-commoner-b) image #p"sprites/townsfolk/commoner-b.png" :min-filter :nearest :mag-filter :nearest)
(define-asset (hexmaw townsfolk-guard-ashen-temple) image #p"sprites/townsfolk/guard-ashen-temple.png" :min-filter :nearest :mag-filter :nearest)
(define-asset (hexmaw townsfolk-guard-deepwardens) image #p"sprites/townsfolk/guard-deepwardens.png" :min-filter :nearest :mag-filter :nearest)
(define-asset (hexmaw townsfolk-guard-free-company) image #p"sprites/townsfolk/guard-free-company.png" :min-filter :nearest :mag-filter :nearest)

(defvar *townsfolk-atlases* (make-hash-table :test 'equal)
  "Read atlases by sprite name: a strip of one cell, with one view.")

(defun townsfolk-atlas (sprite)
  (or (gethash sprite *townsfolk-atlases*)
      (setf (gethash sprite *townsfolk-atlases*)
            (append (read-atlas (format NIL "sprites/townsfolk/~a.lisp" sprite)) (list :views '(:front))))))

(defparameter *townsfolk-names*
  '((shopkeeper "Odo the Chandler" "Merra Coinwise" "Fat Hobb" "Tarvel Ash")
    (priest "Brother Aldric" "Mother Ysolde" "Father Cenwin" "Sister Bray")
    (trainer "Old Garrick" "Hask the Scarred" "Wenna Ironhand" "Dunmore")
    (quest-giver "Lisbet Vane" "Corwin the Lamp" "Ressa Mapwright" "One-Eyed Tam")
    ("commoner-a" "a townsman" "a labourer" "a porter")
    ("commoner-b" "a townswoman" "a washerwoman" "a beggar")
    (guard "a guard"))
  "The names a townsperson of each role may have, or of each sprite, where the sprite decides
(a commoner's).")

(defparameter *townsfolk-greetings*
  '((shopkeeper "Coin first, questions after." "Everything here came down the stairs on someone's back.")
    (priest "The light is thin this deep. Sit a while." "Be blessed, wanderer, and be careful.")
    (trainer "You hold that blade like a shovel." "Soft hands. Let's fix that.")
    (quest-giver "There's work, if you've the stomach for the undercroft." "The undercroft's been noisy. I pay for quiet.")
    (commoner "Mind the gates." "They say the stairs go down forever." "Spare a coin?")
    (guard "The watch of ~a. Keep the peace and we'll keep you." "Move along. This town answers to ~a."))
  "What a townsperson of each role may say first. A guard's names its faction, as ~A.")

(define-shader-entity townsfolk (creature)
  ((role :initarg :role :reader role :documentation "Its role, as a blueprint names it: \"priest\".")
   (npc-name :initarg :npc-name :initform "" :reader npc-name)
   (greeting :initarg :greeting :initform "" :reader greeting)
   (provoked :initform NIL :accessor provoked
             :documentation "True while it is set against the player: it hunts like a monster if it can fight.")
   (last-assault :initform NIL :accessor last-assault
                 :documentation "The player's RUN-TIME at their last blow at it, or NIL (HARMED).")
   (sprite-height :initform *townsfolk-height*)
   (wander-radius :initform 0.0)
   (walk-speed :initform 1.1)
   (max-health :initform 25)
   (pain-chance :initform 50)
   (gibs :initform '((:flesh 0 0 1 1 2 4 5 6 7))))
  (:documentation "One of the settlement's people."))

(define-shader-entity commoner (townsfolk) ((wander-radius :initform 3.0)))
(define-shader-entity shopkeeper (townsfolk) ())
(define-shader-entity priest (townsfolk) ())
(define-shader-entity quest-giver (townsfolk) ())
(define-shader-entity trainer (townsfolk)
  ((attack-damage :initform '(4 8))
   (attack-reach :initform 0.8)
   (chase-speed :initform 3.0)
   (max-health :initform 50)
   (pain-chance :initform 20)))
(define-shader-entity guard (townsfolk)
  ((attack-damage :initform '(8 12))
   ;; A spear: a long reach, a slow thrust.
   (attack-reach :initform 1.2)
   (attack-arc :initform 0.5)
   (attack-frame-times :initform '(0.35 0.15 0.2 0.35))
   (attack-pause :initform 0.4)
   (chase-speed :initform 3.2)
   (walk-speed :initform 1.2)
   (wander-radius :initform 1.5)
   (guard-break :initform 0.6)
   (max-health :initform 60)
   (pain-chance :initform 20)))

(defmethod townsfolk-p ((townsfolk townsfolk)) T)
(defmethod calm-p ((townsfolk townsfolk)) (not (provoked townsfolk)))

(defparameter *roles*
  '(("shopkeeper" shopkeeper "shopkeeper") ("priest" priest "priest") ("trainer" trainer "trainer")
    ("quest-giver" quest-giver "quest-giver") ("commoner" commoner ("commoner-a" "commoner-b"))
    ("guard" guard :faction))
  "Each role a blueprint's npc may name: its class, and its sprite, or a list of them to pick
from, or :FACTION for the settlement's own (the guard's tabard).")

(defun role-sprite (spec)
  (cond ((eq spec :faction)
         (format NIL "guard-~(~a~)" (if *settlement* (settlement-faction *settlement*) :free-company)))
        ((listp spec) (nth (random (length spec) *block-random*) spec))
        (T spec)))

(defun place-npc (role at yaw container)
  "A townsperson of ROLE standing at AT facing YAW, from a blueprint's npc action (PLACE-BLOCK)."
  (let ((entry (assoc role *roles* :test #'string-equal)))
    (if (null entry)
        (v:warn :hexmaw "No townsfolk role ~s; npc ignored." role)
        (destructuring-bind (class sprite) (rest entry)
          (let* ((sprite (role-sprite sprite))
                 (atlas (townsfolk-atlas sprite))
                 (names (rest (or (assoc sprite *townsfolk-names* :test #'equal) (assoc class *townsfolk-names*))))
                 (greetings (rest (assoc class *townsfolk-greetings*))))
            (spawn-creature (make-instance class :role (string-downcase role)
                                                 :location at :facing yaw
                                                 :texture (// 'hexmaw (intern (format NIL "TOWNSFOLK-~:@(~a~)" sprite) '#:hexmaw))
                                                 :atlas atlas
                                                 ;; Sliced at the monsters' 64 px per metre.
                                                 :sprite-height (/ (getf atlas :cell-height) 64.0)
                                                 :npc-name (nth (random (length names) *block-random*) names)
                                                 :greeting (nth (random (length greetings) *block-random*) greetings))
                            container))))))

(defun townsfolk-title (townsfolk)
  "What the HUD and the dialogue call TOWNSFOLK: its name and, for one with a name, its role."
  (let ((name (npc-name townsfolk)))
    (if (or (typep townsfolk '(or commoner guard)) (string= name ""))
        name
        (format NIL "~a, the ~a" name (substitute #\Space #\- (role townsfolk))))))

;;; E: the player looks at someone (or, later, something) and does what they offer.

(defvar *interact-prompt* NIL "What E would do now, as the HUD shows it, or NIL. A new string each time it changes.")
(defparameter *interact-reach* 2.5 "Metres from the player within which E reaches what they look at.")
(defparameter *interact-arc* 0.4 "Radians either side of the view that E reaches.")

(defgeneric interactable-p (thing)
  (:documentation "True if E does something with THING when the player looks at it.")
  (:method (thing) (declare (ignore thing)) NIL))

(defgeneric interact (thing player)
  (:documentation "What E does with THING."))

(defgeneric interact-label (thing)
  (:documentation "What the HUD's prompt says E does with THING: \"Talk to Brother Aldric\"."))

(defmethod interactable-p ((townsfolk townsfolk))
  ;; Only in a settlement: the gallery's have nothing to offer. A dead shopkeeper's stock is
  ;; there for the taking (LOOT-ITEM, dialogue.lisp).
  (and *settlement*
       (if (dead townsfolk)
           (typep townsfolk 'shopkeeper)
           (or (calm-p townsfolk) (bribable-p townsfolk)))))

(defmethod interact ((townsfolk townsfolk) player)
  (declare (ignore player))
  (start-talk townsfolk))

(defmethod interact-label ((townsfolk townsfolk))
  (cond ((dead townsfolk) "Search the stall")
        ((provoked townsfolk) (format NIL "Buy off ~a" (npc-name townsfolk)))
        (T (format NIL "Talk to ~a" (townsfolk-title townsfolk)))))

(defun interact-target (player)
  "What E reaches: a townsperson the player looks at, else the altar they stand at (:ALTAR,
forge.lisp; anywhere with *FORGE-ANYWHERE* in a debug version), else NIL."
  (or (looked-at-creature player *interact-reach* *interact-arc* :test #'interactable-p :dead T)
      (and (or (near-altar-p player) (and *debug-version* *forge-anywhere*)) :altar)))

(defun player-interact (player)
  "E in play: do what the thing looked at offers."
  (let ((target (interact-target player)))
    (when target
      (interact target player))))

;;; The watch. Crimes add up: a broken rule counts 1, a blow at one of the townsfolk 2, a
;;; killing 3. From 1 the watch warns, from 2 the nearest guard comes to fine the player, and
;;; from 3, or on refusing the fine, or letting it go unpaid, every guard turns on them. The
;;; faction says which crimes count (*FACTIONS*' :CRIMES): the Free Company punishes only
;;; killing, and its guards take a bribe.

(defparameter *crime-weights* '(:rule 1 :assault 2 :murder 3))
(defparameter *fine-base* 25 "Gold a fine costs per crime counted, at the first depth.")
(defparameter *fine-time* 60.0 "Seconds of play the player has to pay a fine before the watch turns on them.")
(defparameter *bribe-share* 0.6 "What a Free Company guard takes to look away, as a share of the fine.")
(defparameter *watch-alert* 30.0 "Seconds a hostile watch hunts; the director keeps it up while the watch is hostile.")
(defparameter *fine-reach* 2.5 "Metres from the player at which the guard sent to collect the fine speaks.")

(defun settlement-guards ()
  (loop for c across *creatures* when (and (typep c 'guard) (not (dead c))) collect c))

(defun fine-amount (&optional (settlement *settlement*))
  (round (* *fine-base* (max 1 (settlement-strikes settlement)) (gold-scale (settlement-depth-of settlement)))))

(defun report-crime (kind &optional victim)
  "The player has committed a crime of KIND (:RULE, :ASSAULT or :MURDER) in the settlement,
against VICTIM (a townsperson) if anyone."
  (let ((s *settlement*))
    (when (and s (not (eq (settlement-condition s) :sacked)) (settlement-guards)
               (member kind (faction-property :crimes s)))
      (let ((weight (getf *crime-weights* kind))
            (patience (if (<= *patient-reputation* (faction-reputation *player* (settlement-faction s))) 1 0)))
        (incf (settlement-strikes s) weight)
        (adjust-reputation *player* (settlement-faction s) (- (* 4 weight)))
        (cond ((settlement-hostile s))
              ((or (eq kind :murder) (<= 3 (- (settlement-strikes s) patience)))
               (watch-turns-hostile (case kind (:murder "Murderer! Seize them!") (T "That's enough. Take them!"))))
              ((<= 2 (- (settlement-strikes s) patience))
               (demand-fine (case kind (:assault "Hold! You'll answer for that.") (T "You were warned."))))
              (T
               (hud-say "The watch: ~a" (case kind
                                          (:rule (faction-property :rule-text s))
                                          (T "Hands off the townsfolk!")))))
        (when victim
          (setf (provoked victim) (and (attacker-p-ignoring-calm victim) T)))))))

(defun attacker-p-ignoring-calm (creature)
  (or (attack-damage creature) (attack-spell creature)))

(defun demand-fine (shout)
  "Send the nearest guard to the player to collect a fine."
  (let ((s *settlement*))
    (setf (settlement-fine s) (fine-amount s)
          (settlement-fine-left s) *fine-time*)
    (hud-say "The watch: ~a ~d gold." shout (settlement-fine s))))

(defun watch-turns-hostile (shout)
  "Every guard turns on the player; the townsfolk offer nothing until the watch is calmed."
  (let ((s *settlement*))
    (setf (settlement-hostile s) T
          (settlement-fine s) NIL)
    (hud-say "The watch: ~a" shout)
    (dolist (g (settlement-guards))
      (setf (provoked g) T
            (alert g) *watch-alert*))))

(defun calm-watch ()
  "The fine is paid or the watch bought off: the guards go back to their posts."
  (let ((s *settlement*))
    (setf (settlement-hostile s) NIL
          (settlement-fine s) NIL
          (settlement-strikes s) 0)
    (loop for c across *creatures*
          when (and (typep c 'townsfolk) (not (dead c)))
            do (setf (provoked c) NIL (alert c) 0.0)
               (unless (eq (brain c) :idle) (stop-walking c 0.5)))))

(defun bribable-p (townsfolk)
  "True if TOWNSFOLK, a guard set against the player, would take a bribe."
  (and (typep townsfolk 'guard) (provoked townsfolk) *settlement*
       (faction-property :bribable) (settlement-hostile *settlement*)))

(defparameter *assault-window* 3.0
  "Seconds of play after the player's blow at one of the townsfolk in which more blows at it,
or a burn's every tick (magic.lisp), are the same assault.")

(defmethod harmed ((townsfolk townsfolk) amount by)
  (declare (ignore amount))
  (cond ((dead townsfolk))
        ((eq by *player*)
         (let ((now (run-time *player*)) (last (last-assault townsfolk)))
           (setf (last-assault townsfolk) now)
           (when (or (null last) (< *assault-window* (- now last)))
             (report-crime :assault townsfolk))))
        ;; A monster's blow: a townsperson who can fight fights back.
        ((and (typep by 'creature) (not (townsfolk-p by)) (fighter-p townsfolk) (not (foe townsfolk)))
         (setf (foe townsfolk) by (replan-timer townsfolk) 0.0))))

(defmethod creature-died :after ((townsfolk townsfolk) by)
  (when (eq by *player*)
    (report-crime :murder))
  (when (and *settlement* (typep townsfolk 'guard) (null (settlement-guards)))
    (sack-town (if (eq by *player*) :player :monsters))))

;;; Sacking: once the last guard is dead the town is the taking. Killed by the player, its
;;; faction hates them, and the townsfolk refuse them (REFUSING-P, dialogue.lisp); the trainer
;;; fights. A dead shopkeeper's stall can be searched either way.

(defparameter *sack-reputation* 100 "Standing the player loses with the faction for sacking its town.")

(defun sack-town (by)
  "The watch is dead, killed last by BY, :PLAYER or :MONSTERS."
  (let ((s *settlement*))
    (unless (eq (settlement-condition s) :sacked)
      (setf (settlement-condition s) :sacked
            (sacked-by s) by
            (settlement-hostile s) NIL
            (settlement-fine s) NIL)
      (cond ((eq by :player)
             (adjust-reputation *player* (settlement-faction s) (- *sack-reputation*))
             (loop for c across *creatures*
                   when (and (typep c 'trainer) (not (dead c)))
                     do (setf (provoked c) T (alert c) *watch-alert*))
             (hud-say "The watch is dead. ~a is yours to plunder." (settlement-name s)))
            (T (hud-say "The watch has fallen!"))))))

;;; The settlement director: what the settlement does in play, ten times a second. On every
;;; level it keeps the HUD's E prompt; in the settlement also the fine's deadline and the guard sent for it, the Deepwardens' rule, a
;;; hostile watch's hunt, the guards' eye for monsters in town, and the besieged town's raids.

(defparameter *director-step* 0.1 "Seconds between the director's looks.")
(defparameter *rule-grace* 3.0 "Seconds a warned player has to put the blade away before it counts.")
(defparameter *raid-interval* 150.0 "Seconds of play between raids on a besieged town.")
(defparameter *raid-size* '(2 3) "Fewest and most monsters in a raid.")
(defparameter *raid-classes* '(imp knight acolyte skeleton-warrior)
  "The monsters that raid: plain fighters, whose attacks FIGHT-FOE can aim at a guard.")
(defparameter *guard-sight* 14.0 "Metres within which a guard takes on a monster in town.")

(defclass settlement-director (entity listener)
  ((name :initform :settlement-director)
   (clock :initform 0.0 :accessor director-clock)
   (prompt-target :initform NIL :accessor prompt-target :documentation "What the E prompt names now.")
   (fine-spoken :initform NIL :accessor fine-spoken :documentation "True once the guard sent for this fine has spoken.")))

(defun add-settlement-director (container)
  "The director, on every level: E's prompt is wanted wherever there is something to use."
  (setf *interact-prompt* NIL)
  (when (and *settlement* (zerop (raid-timer *settlement*)))
    (setf (raid-timer *settlement*) *raid-interval*))
  (enter (make-instance 'settlement-director) container))

(defun update-prompt (director)
  (let ((target (and (eq *game-state* :playing) *player* (interact-target *player*))))
    (unless (eq target (prompt-target director))
      (setf (prompt-target director) target
            *interact-prompt* (and target (format NIL "[E] ~a" (interact-label target)))))))

(defun nearest-guard (point)
  (let ((best NIL) (best-d 0.0))
    (dolist (g (settlement-guards) best)
      (let ((d (vdistance (location g) point)))
        (when (or (null best) (< d best-d)) (setf best g best-d d))))))

(defun send-for-fine (director dt)
  "Count down the fine, and walk the nearest guard to the player to ask for it."
  (let ((s *settlement*))
    (cond ((null (settlement-fine s)) (setf (fine-spoken director) NIL))
          ((<= (decf (settlement-fine-left s) dt) 0)
           (watch-turns-hostile "Unpaid! Take them!"))
          ((not (fine-spoken director))
           (let ((guard (nearest-guard (feet *player*))))
             (when guard
               (cond ((< (vdistance (location guard) (feet *player*)) *fine-reach*)
                      (setf (fine-spoken director) T)
                      (stop-walking guard 1.0)
                      (start-talk guard))
                     ((not (eq (brain guard) :walking))
                      (let ((path (nav-path-to (ground-point guard) (feet *player*) (body-radius guard)
                                               (sprite-height guard) (step-height guard) :max-walk *foe-max-walk*)))
                        (when path
                          (setf (path guard) path (brain guard) :walking)))))))))))

(defun check-drawn-blade (dt)
  "The Deepwardens' rule: no sword or spear in hand in the market or the temple."
  (let* ((s *settlement*)
         (feet (feet *player*))
         (drawn (member (weapon *player*) '(:sword :spear)))
         (in-zone (and drawn
                       (loop for (name low high) across *level-zones*
                             thereis (and (member name (faction-property :zones s))
                                          (<= (vx low) (vx feet) (vx high)) (<= (vy low) (+ (vy feet) 0.1) (vy high))
                                          (<= (vz low) (vz feet) (vz high)))))))
    (cond ((not in-zone) (setf (rule-grace s) NIL))
          ((null (rule-grace s))
           (setf (rule-grace s) *rule-grace*)
           (hud-say "The watch: ~a Put it away." (faction-property :rule-text s)))
          ((<= (decf (rule-grace s) dt) 0)
           (setf (rule-grace s) (* 2 *rule-grace*))
           (report-crime :rule)))))

(defun raiders ()
  (loop for c across *creatures* when (and (monster-p c) (not (dead c)) (foe c) (townsfolk-p (foe c))) collect c))

(defun start-raid ()
  "Send the wing's nearest raiders at the guards."
  (let* ((s *settlement*)
         (centre (let ((b (settlement-block s))) (v* (v+ (map-block-low b) (map-block-high b)) 0.5)))
         (pool (sort (loop for c across *creatures*
                           when (and (monster-p c) (not (dead c)) (not (foe c))
                                     (some (lambda (class) (typep c class)) *raid-classes*)
                                     (not (in-settlement-p (location c))))
                             collect c)
                     #'< :key (lambda (c) (vdistance (location c) centre))))
         (size (+ (first *raid-size*) (random (1+ (- (second *raid-size*) (first *raid-size*)))))))
    (cond ((null pool) (setf (raid-timer s) 0.0))
          (T (loop for c in pool repeat size
                   do (let ((guard (nearest-guard (location c))))
                        (when guard (setf (foe c) guard (replan-timer c) 0.0))))
             (hud-say "The watch: To the gates! The undercroft is coming!")))))

(defun run-siege (dt)
  (let ((s *settlement*))
    (when (and (eq (settlement-condition s) :besieged) (settlement-guards))
      (cond ((raid-on-p s)
             (unless (raiders)
               (setf (raid-on-p s) NIL)
               (incf (raids-held s))
               (hud-say "The watch: They're beaten back!")))
            ((< 0 (raid-timer s))
             (when (<= (decf (raid-timer s) dt) 0)
               (start-raid)
               (when (raiders)
                 (setf (raid-on-p s) T
                       (raid-timer s) *raid-interval*))))))))

(defun guards-watch ()
  "Each free guard takes on the nearest monster in town it can see that is up to something."
  (dolist (g (settlement-guards))
    (unless (or (foe g) (hunting-p g))
      (loop for c across *creatures*
            when (and (monster-p c) (not (dead c)) (or (hunting-p c) (foe c))
                      (in-settlement-p (location c))
                      (< (vdistance (location c) (location g)) *guard-sight*)
                      (clear-path-p (location g) (location c) 1.0))
              do (setf (foe g) c (replan-timer g) 0.0)
                 (return)))))

(define-handler (settlement-director tick) (dt)
  (when *player*
    (when (<= (decf (director-clock settlement-director) dt) 0)
      (let ((dt *director-step*))
        (setf (director-clock settlement-director) dt)
        (update-prompt settlement-director)
        (when (and *settlement* (not (frozen-p)))
          (send-for-fine settlement-director dt)
          (when (eq (faction-property :rule) :no-drawn-weapon)
            (check-drawn-blade dt))
          (when (settlement-hostile *settlement*)
            (dolist (g (settlement-guards))
              (setf (provoked g) T (alert g) (max (alert g) *watch-alert*))))
          (guards-watch)
          (run-siege dt))))))
