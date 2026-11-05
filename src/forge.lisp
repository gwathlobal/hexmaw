(in-package #:hexmaw)

;;; The spellforge: at an altar (ADD-ALTAR, pickups.lisp; the town's, or a level's altar room)
;;; the player spends arcane dust (an item, inventory.lisp; found in the dungeon) to make spells
;;; out of the effects they know (glyphs teach them, pickups.lisp) and to enchant weapons, whose
;;; blows then carry a spell (ENCHANT-STRIKE, sword.lisp). Two tabs (*FORGE-TAB*): Spells, where
;;; a new spell is made into a rune in the bag (GIVE-RUNE), bound to the first free key, and an
;;; old one unweaved for half its dust; and Enchanting, where a plain weapon (a sword or spear in
;;; the bag, each its own, or the shield) is enchanted and an enchanted one disenchanted,
;;; likewise. A rune or an enchantment is never changed in place: make another, or destroy it. What is being made is a draft: a delivery and
;;; up to *MAX-SPELL-EFFECTS* effects, each a kind, an element for damage, and the dials the kind
;;; has (*EFFECT-KINDS*: magnitude, duration, area). The screen (FORGE-PANEL, an Alloy panel like
;;; the menus) changes it through the FORGE- commands, which also work from the REPL: (game
;;; (open-forge)), (forge-tab :enchant), (forge-select :sword), (forge-add-effect), (forge-make).
;;; A change of what the screen shows bumps *FORGE-REVISION*, and the menu controller remakes the
;;; panel (PANEL-STALE-P); a slider only changes the draft and the readout.

(defparameter *altar-reach* 1.8 "Metres across from an altar's middle the player can use it from.")
(defparameter *altar-height* 1.3 "Metres up or down from an altar's top the player's feet may be.")
(defvar *forge-anywhere* NIL "True to open the forge anywhere with E, in a debug version.")

(defparameter *max-spell-effects* 3)
(defparameter *max-enchant-effects* 2)
(defparameter *max-enchant-cost* 6 "Most mana a blow of an enchanted weapon may cost.")
(defparameter *forge-deliveries* '(:projectile :touch :self) "How a forged spell can strike.")
(defparameter *forge-elements* '(:fire :frost :shock))
(defparameter *dust-per-mana* 1 "Arcane dust a spell costs to make for each mana a cast of it costs.")
(defparameter *enchant-dust-scale* 3 "Arcane dust an enchantment costs for each mana a blow of it costs.")
(defparameter *dust-refund* 0.5 "Fraction of its dust unweaving a spell or disenchanting a weapon gives back.")
;; The character counts here and in dialogue.lisp are guessed for the menu font, Jersey 15
;; (*menu-font*, menu.lisp), which draws about 1.24 times as wide as Arial at a size.
(defparameter *forge-label-width* 19 "Characters a left-column label may take; a longer one is cut.")
(defparameter *forge-list-rows* 7 "Runes the Spells tab lists at a time; more page.")
(defparameter *forge-note-chars* 50 "Characters a right-column line holds before it wraps.")

;;; The draft.

(defclass effect-draft ()
  ((kind :initarg :kind :accessor draft-kind)
   (element :initarg :element :initform NIL :accessor draft-element)
   (magnitude :initarg :magnitude :accessor draft-magnitude
              :documentation "The top of its range; the bottom is *MAGNITUDE-SPREAD* of it.")
   (duration :initarg :duration :initform 0 :accessor draft-duration)
   (area :initarg :area :initform 0 :accessor draft-area)))

(defclass forge-draft ()
  ((sink :initarg :sink :accessor draft-sink
         :documentation "What it is for: a rune's stack, :NEW for a new rune, or a weapon.")
   (delivery :initarg :delivery :initform :projectile :accessor draft-delivery)
   (effects :initarg :effects :initform () :accessor draft-effects)))

(defparameter *magnitude-spread* 0.7 "A forged effect's least roll, against its most.")
(defparameter *new-effects*
  '((:damage 8 0) (:heal 15 0) (:knockback 8 0) (:slow 30 4) (:drain 6 0) (:ward 10 10))
  "(KIND MAGNITUDE DURATION) an effect starts at when added or turned to that kind.")

(defvar *forge-tab* :spells "The forge's tab: :SPELLS, making and unweaving runes, or :ENCHANT.")
(defvar *forge-sink* :new
  "What the forge is on: :NEW (a spell to make), a rune's stack, or a weapon of *FORGE-WEAPONS*.")
(defvar *forge-draft* NIL
  "The draft being made, for :NEW or a plain weapon; NIL for a rune or an enchanted weapon, which
are only shown, to unweave or disenchant.")
(defvar *forge-drafts* () "A plist from sink (:NEW or a weapon) to its draft, kept while the forge is left.")
(defvar *forge-armed* NIL "The sink a first click of Unweave or Disenchant armed: a second does it.")
(defvar *forge-page* 0 "The page of runes the Spells tab lists.")
(defvar *forge-about-index* 0
  "Which of the draft's effects the forge explains: the one whose controls last had the focus (a
hover gives it), or that was last added or changed.")
(defvar *forge-revision* 0 "Bumped whenever the forge's screen should be made again.")
(defvar *forge-note* NIL "What the forge says under the readout: why it can't, or what it did.")

(defun weapon-sink-p (sink)
  "True if SINK is a weapon: one in the bag (its stack, with its own enchantment), or the shield."
  (or (eq sink :shield) (weapon-stack-p sink)))

(defun sink-weapon (sink)
  "The weapon SINK is, :SWORD, :SPEAR or :SHIELD, or NIL."
  (if (eq sink :shield) :shield (and (weapon-stack-p sink) (item-property (first sink) :weapon))))

(defun player-runes (player)
  "The runes PLAYER's bag holds, in its order."
  (remove :rune (carried-stacks player) :key #'first :test-not #'eq))

(defun carried-weapons (player)
  "The weapons PLAYER carries, each its own bag stack, and the shield, which goes with a sword."
  (let ((stacks (remove-if-not #'weapon-stack-p (carried-stacks player))))
    (append stacks (when (find :sword stacks :key #'sink-weapon) (list :shield)))))

(defun sink-title (sink)
  (cond ((eq sink :shield) "Shield")
        ((weapon-sink-p sink) (item-property (first sink) :name))
        ((eq sink :new) "New spell")
        (T (spell-title (stack-spell sink)))))

(defun sink-spell (player sink)
  "The spell SINK holds: a weapon's enchantment, a rune's; NIL for :NEW."
  (cond ((eq sink :shield) (getf (enchantments player) :shield))
        ((weapon-sink-p sink) (stack-enchantment sink))
        ((eq sink :new) NIL)
        (T (stack-spell sink))))

(defun (setf sink-spell) (spell player sink)
  "Enchant the weapon SINK with SPELL, or with NIL disenchant it."
  (cond ((not (eq sink :shield)) (setf (stack-enchantment sink) spell))
        (spell (setf (getf (enchantments player) :shield) spell))
        (T (remf (enchantments player) :shield) NIL)))

(defun rune-place (player stack)
  "Where STACK is, as the forge says it: its key, or the bag."
  (let ((key (stack-key player stack)))
    (if key (format NIL "key ~d" (1+ key)) "bag")))

(defun spell-dust (spell) (max 1 (ceiling (* *dust-per-mana* (spell-cost spell)))))
(defun enchant-dust (spell) (max 1 (ceiling (* *enchant-dust-scale* (enchant-cost spell)))))
(defun sink-dust (sink spell)
  "The dust SPELL costs to make for SINK: an enchantment's, or a rune's."
  (if (weapon-sink-p sink) (enchant-dust spell) (spell-dust spell)))
(defun refund-dust (cost) (floor (* *dust-refund* cost)))
(defun player-dust (player) (kind-total player :dust))

(defun editable-p (player sink)
  "True if the forge makes something for SINK: a new spell, or a weapon not yet enchanted."
  (or (eq sink :new) (and (weapon-sink-p sink) (null (sink-spell player sink)))))

(defun valid-sink-p (player sink tab)
  (if (eq tab :enchant)
      (member sink (carried-weapons player) :test #'eq)
      (or (eq sink :new) (member sink (player-runes player) :test #'eq))))

(defun default-sink (player tab)
  "What a tab opens on: a new spell, or the first weapon carried."
  (if (eq tab :enchant) (or (first (carried-weapons player)) :shield) :new))

(defun fit-label (text &optional (width *forge-label-width*))
  "TEXT cut to WIDTH characters, ending in .. where it was longer."
  (if (<= (length text) width) text (concatenate 'string (subseq text 0 (- width 2)) "..")))

(defun known-kinds (player)
  (loop for (kind) in *effect-kinds* when (member kind (known-effects player)) collect kind))

(defun known-elements (player)
  (remove-if-not (lambda (e) (member e (known-effects player))) *forge-elements*))

(defun area-known-p (player) (member :area (known-effects player)))

(defun self-kind-p (kind) (equal '(:self) (kind-property kind :targets)))

(defun draft-strikes-p (draft)
  "True if DRAFT's effects land on what it reaches (a weapon's blows, a delivered spell),
NIL if on the caster (a spell cast on yourself)."
  (or (weapon-sink-p (draft-sink draft)) (not (eq (draft-delivery draft) :self))))

(defun draft-kinds (draft player)
  "The effect kinds DRAFT may hold: those PLAYER knows that land where it does, so the forge
never offers damage cast on yourself or a heal thrown at a monster."
  (let ((strikes (draft-strikes-p draft)))
    (remove-if (lambda (kind) (if strikes (self-kind-p kind) (not (self-kind-p kind)))) (known-kinds player))))

(defun fit-effects (draft player)
  "Turn each of DRAFT's effects that can't land where it does into the first kind that can."
  (let ((kinds (draft-kinds draft player)))
    (setf (draft-effects draft)
          (loop for e in (draft-effects draft)
                when (member (draft-kind e) kinds) collect e
                else when kinds collect (clamp-effect (new-effect (first kinds)) player)))))

(defun new-effect (kind)
  (destructuring-bind (magnitude duration) (rest (assoc kind *new-effects*))
    (make-instance 'effect-draft :kind kind :magnitude magnitude :duration duration
                                 :element (when (eq kind :damage) :fire))))

(defun draft-from-spell (spell sink)
  "A draft of SPELL, for SINK; one damage effect if there is no SPELL."
  (let ((effects (loop for e in (and spell (spell-effects spell))
                       when (assoc (effect-kind e) *effect-kinds*)
                         collect (make-instance 'effect-draft :kind (effect-kind e)
                                                              :element (effect-element e)
                                                              :magnitude (second (effect-magnitude e))
                                                              :duration (effect-duration e)
                                                              :area (effect-area e)))))
    (make-instance 'forge-draft :sink sink
                                :delivery (if (and spell (member (spell-delivery spell) *forge-deliveries*))
                                              (spell-delivery spell)
                                              :projectile)
                                :effects (or effects (list (new-effect :damage))))))

(defun clamp-effect (effect player)
  "Keep EFFECT's dials within what its kind allows and the player knows."
  (let ((kind (draft-kind effect)))
    (setf (draft-magnitude effect) (max 1 (min (kind-property kind :magnitude) (draft-magnitude effect))))
    (setf (draft-duration effect)
          (ecase (kind-property kind :timing)
            (:instant 0)
            (:over-time (max 0 (min (kind-property kind :duration) (draft-duration effect))))
            (:status (max 1 (min (kind-property kind :duration) (draft-duration effect))))))
    (setf (draft-area effect)
          (if (and (area-known-p player) (not (self-kind-p kind)))
              (max 0 (min (kind-property kind :area) (draft-area effect)))
              0))
    (setf (draft-element effect)
          (when (eq kind :damage)
            (let ((known (known-elements player)))
              (if (member (draft-element effect) known) (draft-element effect) (first known)))))
    effect))

(defparameter *element-words* '(:fire ("Fire" "Flame") :frost ("Frost" "Frost") :shock ("Shock" "Lightning")))
(defparameter *kind-words*
  '(:heal ("Healing" "Mending") :knockback ("Force" "Force") :slow ("Binding" "Binding")
    :drain ("Draining" "Thirst") :ward ("Warding" "Warding"))
  "(ADJECTIVE NOUN) each effect kind names a spell by.")

(defun effect-words (effect)
  (if (eq (draft-kind effect) :damage)
      (getf *element-words* (or (draft-element effect) :fire))
      (getf *kind-words* (draft-kind effect))))

(defun draft-name (draft)
  "A name for DRAFT: its first effect's adjective, a noun for how it strikes, and its second's."
  (let* ((effects (draft-effects draft))
         (first (first effects))
         (weapon (sink-weapon (draft-sink draft)))
         (noun (cond ((eq weapon :sword) "Edge")
                     ((eq weapon :spear) "Point")
                     ((eq weapon :shield) "Bulwark")
                     ((eq (draft-delivery draft) :touch) "Touch")
                     ((eq (draft-delivery draft) :self) (if (eq :ward (and first (draft-kind first))) "Aegis" "Blessing"))
                     ((some (lambda (e) (< 0 (draft-area e))) effects) "Burst")
                     (T "Bolt"))))
    (if first
        (let ((other (find (effect-words first) (rest effects) :key #'effect-words :test-not #'equal)))
          (format NIL "~a ~a~@[ of ~a~]" (first (effect-words first)) noun
                  (and other (second (effect-words other)))))
        noun)))

(defun draft-spec (draft)
  "DRAFT as a spell spec (SPEC-SPELL, spells.lisp)."
  (list* (draft-name draft)
         (if (weapon-sink-p (draft-sink draft)) :touch (draft-delivery draft))
         (loop for e in (draft-effects draft)
               for top = (draft-magnitude e)
               collect (list :kind (draft-kind e)
                             :magnitude (list (max 1 (ceiling (* *magnitude-spread* top))) top)
                             :duration (draft-duration e) :area (draft-area e)
                             :target-type (if (self-kind-p (draft-kind e)) :self :target)
                             :element (draft-element e)))))

(defun draft-spell (draft) (spec-spell (draft-spec draft)))

;;; Parity: a spell the player starts with must be one the forge makes, so that what it costs is
;;; what the forge would ask for it, and the player can make it again.

(defun forgeable-p (spell &optional (known *starting-effects*))
  "True if the forge, knowing the effects KNOWN, makes SPELL as it is: the same delivery, effects
(kinds, elements, ranges, durations, areas), cost, and for a projectile the same flight. A
second value says what differs."
  (let* ((draft (draft-from-spell spell :new))
         (made (draft-spell draft))
         (ours (spell-effects spell))
         (theirs (spell-effects made)))
    (flet ((same-effect-p (a b)
             (and (eq (effect-kind a) (effect-kind b)) (equal (effect-magnitude a) (effect-magnitude b))
                  (eq (effect-element a) (effect-element b)) (= (effect-duration a) (effect-duration b))
                  (= (effect-area a) (effect-area b)) (eq (effect-target-type a) (effect-target-type b)))))
      (let ((problem
              (cond ((not (member (spell-delivery spell) *forge-deliveries*)) "its delivery isn't the forge's")
                    ((or (/= (length ours) (length theirs)) (notevery #'same-effect-p ours theirs))
                     (format NIL "its effects aren't forged ones: ~s against the forge's ~s"
                             (rest (rest (spell-spec spell))) (rest (rest (spell-spec made)))))
                    ((loop for e in ours
                           thereis (or (not (member (effect-kind e) known))
                                       (and (effect-element e) (not (member (effect-element e) known)))
                                       (and (< 0 (effect-area e)) (not (member :area known)))))
                     "it uses an effect the player doesn't know")
                    ((/= (spell-cost spell) (spell-cost made))
                     (format NIL "it costs ~d, the forge's ~d" (spell-cost spell) (spell-cost made)))
                    ((and (eq (spell-delivery spell) :projectile)
                          (not (and (= (projectile-speed spell) (projectile-speed made))
                                    (= (spell-pain-bonus spell) (spell-pain-bonus made))
                                    (eq (projectile-animation spell) (projectile-animation made))
                                    (eq (impact-animation spell) (impact-animation made))
                                    (eq (spell-homing spell) (spell-homing made))
                                    (eq (spell-lifetime spell) (spell-lifetime made)))))
                     "it flies unlike a forged projectile"))))
        (values (null problem) problem)))))

(defun check-starting-spells ()
  "Warn of each spell in *STARTING-HOTBAR* the forge doesn't make (FORGEABLE-P). True if none."
  (loop with all = T
        for entry in *starting-hotbar*
        unless (keywordp entry)
          do (multiple-value-bind (ok problem) (forgeable-p (find-spell entry))
               (unless ok
                 (setf all NIL)
                 (v:warn :hexmaw "The starting spell ~(~a~) isn't one the forge makes: ~a." entry problem)))
        finally (return all)))

(check-starting-spells)

(defun draft-fault (draft max-mana)
  "Why DRAFT isn't a spell the forge makes, its maker holding MAX-MANA, as a sentence, or NIL:
what it holds, not what making it takes (DRAFT-PROBLEM). Generated loot asks it too (loot.lisp)."
  (let* ((effects (draft-effects draft))
         (strikes (some (lambda (e) (not (self-kind-p (draft-kind e)))) effects))
         (weapon (weapon-sink-p (draft-sink draft)))
         (spell (and effects (draft-spell draft))))
    (cond ((null effects) "Add an effect.")
          ((and weapon (< *max-enchant-effects* (length effects)))
           (format NIL "A weapon holds at most ~d effects." *max-enchant-effects*))
          ((and weapon (< *max-enchant-cost* (enchant-cost spell)))
           (format NIL "Too strong for a weapon: at most ~d mana a blow." *max-enchant-cost*))
          ((and (not weapon) (eq (draft-delivery draft) :self) strikes)
           "Cast on yourself, it strikes nothing: deliver it, or keep to self effects.")
          ((and (not weapon) (not (eq (draft-delivery draft) :self)) (not strikes))
           "Nothing in it strikes: cast it on yourself.")
          ((and (not weapon) (< max-mana (spell-cost spell)))
           (format NIL "It costs more mana than you can hold (~d)." (floor max-mana))))))

(defun draft-problem (draft &optional (player *player*))
  "Why DRAFT can't be made, as a sentence, or NIL."
  (let ((sink (draft-sink draft))
        (weapon (weapon-sink-p (draft-sink draft))))
    (cond ((draft-fault draft (max-mana player)))
          ((< (player-dust player) (sink-dust sink (draft-spell draft)))
           (format NIL "It needs ~d arcane dust and you have ~d: find more in the dungeon, or unweave a spell."
                   (sink-dust sink (draft-spell draft)) (player-dust player)))
          ((and (not weapon) (null (position NIL (inventory player))))
           "No free bag cell for the rune."))))

(defun draft-cost-text (draft player)
  (declare (ignore player))
  (if (null (draft-effects draft))
      ""
      (let ((spell (draft-spell draft)))
        (if (weapon-sink-p (draft-sink draft))
            (format NIL "~d MP a blow, ~d dust to enchant" (enchant-cost spell) (enchant-dust spell))
            (format NIL "~d MP a cast, ~d dust to make" (spell-cost spell) (spell-dust spell))))))

;;; Commands: each changes the draft or what the player holds, and says the screen is stale.

(defun forge-changed ()
  (incf *forge-revision*))

(defun sink-draft (player sink)
  "SINK's draft, kept from the last time it was on the forge, or a fresh one."
  (or (getf *forge-drafts* sink)
      (let ((draft (draft-from-spell NIL sink)))
        (dolist (e (draft-effects draft)) (clamp-effect e player))
        (fit-effects draft player)
        (setf (getf *forge-drafts* sink) draft))))

(defun forge-select (sink &optional (player *player*))
  "Put SINK on the forge: a new spell or a plain weapon to make, or a rune or an enchanted weapon
to look at. One the player no longer carries falls back to the tab's first. :SWORD or :SPEAR, as
from the REPL, is the first one carried."
  (let* ((sink (if (member sink '(:sword :spear))
                   (or (find sink (carried-weapons player) :key #'sink-weapon) sink)
                   sink))
         (sink (if (valid-sink-p player sink *forge-tab*) sink (default-sink player *forge-tab*))))
    (setf *forge-sink* sink
          *forge-armed* NIL
          *forge-note* NIL
          *forge-about-index* 0
          *forge-draft* (and (editable-p player sink) (sink-draft player sink)))
    (forge-changed)
    sink))

(defun forge-tab (tab &optional (player *player*))
  "Turn to TAB, :SPELLS or :ENCHANT."
  (setf *forge-tab* tab)
  (forge-select (if (valid-sink-p player *forge-sink* tab) *forge-sink* (default-sink player tab)) player))

(defun forge-page (step &optional (player *player*))
  (let ((pages (max 1 (ceiling (length (player-runes player)) *forge-list-rows*))))
    (setf *forge-page* (mod (+ *forge-page* step) pages))
    (forge-changed)))

(defun forge-add-effect (&optional (kind :damage) (player *player*))
  (let* ((draft *forge-draft*)
         (kinds (and draft (draft-kinds draft player))))
    (when (and kinds
               (< (length (draft-effects draft))
                  (if (weapon-sink-p (draft-sink draft)) *max-enchant-effects* *max-spell-effects*)))
      (setf (draft-effects draft)
            (append (draft-effects draft)
                    (list (clamp-effect (new-effect (if (member kind kinds) kind (first kinds))) player)))
            *forge-about-index* (1- (length (draft-effects draft))))
      (forge-changed))))

(defun forge-remove-effect (index)
  (setf (draft-effects *forge-draft*) (remove (nth index (draft-effects *forge-draft*)) (draft-effects *forge-draft*)))
  (when (< index *forge-about-index*)
    (decf *forge-about-index*))
  (forge-changed))

(defun next-in (list item)
  (or (second (member item list)) (first list)))

(defun unknown-phrase (things)
  "THINGS, keywords, as \"frost and shock\"."
  (format NIL "~{~(~a~)~#[~; and ~:;, ~]~}" things))

(defun forge-cycle-kind (index &optional (player *player*))
  "The next kind PLAYER knows that this draft can hold; with no other, the note says which
glyphs would teach more."
  (let* ((effect (nth index (draft-effects *forge-draft*)))
         (kinds (draft-kinds *forge-draft* player))
         (kind (next-in kinds (draft-kind effect)))
         (fresh (new-effect kind)))
    (setf *forge-about-index* index)
    (when (eq kind (draft-kind effect))
      (let* ((strikes (draft-strikes-p *forge-draft*))
             (missing (loop for (k) in *effect-kinds*
                            when (and (not (member k (known-effects player)))
                                      (if strikes (not (self-kind-p k)) (self-kind-p k)))
                              collect k)))
        (setf *forge-note*
              (format NIL "~:(~a~) is the only effect you know ~:[cast on yourself~;that strikes~]~@[: glyphs in the dungeon teach ~a~]."
                      kind strikes (and missing (unknown-phrase missing))))
        (forge-changed)
        (return-from forge-cycle-kind NIL)))
    (setf (draft-kind effect) kind
          (draft-magnitude effect) (draft-magnitude fresh)
          (draft-duration effect) (draft-duration fresh)
          (draft-element effect) (draft-element fresh))
    (clamp-effect effect player)
    (forge-changed)))

(defun forge-cycle-element (index &optional (player *player*))
  "The next element PLAYER knows; with no other, the note says which glyphs would teach more."
  (let ((effect (nth index (draft-effects *forge-draft*))))
    (setf *forge-about-index* index)
    (when (eq :damage (draft-kind effect))
      (let ((next (next-in (known-elements player) (draft-element effect))))
        (if (eq next (draft-element effect))
            (setf *forge-note*
                  (format NIL "~:(~a~) is the only element you know: glyphs in the dungeon teach ~a."
                          next (unknown-phrase (remove-if (lambda (e) (member e (known-effects player)))
                                                          *forge-elements*))))
            (setf (draft-element effect) next
                  *forge-note* NIL)))
      (forge-changed))))

(defun forge-cycle-delivery (&optional (player *player*))
  "The next delivery; effects that can't land where it does become ones that can."
  (setf (draft-delivery *forge-draft*) (next-in *forge-deliveries* (draft-delivery *forge-draft*)))
  (fit-effects *forge-draft* player)
  (forge-changed))

(defun forge-make (&optional (player *player*))
  "Make the draft, for its dust: a new rune in the bag, on the first free key, or the plain
weapon's enchantment. The spell, or NIL (and *FORGE-NOTE* says why) if it can't be made."
  (let* ((draft *forge-draft*)
         (sink *forge-sink*)
         (problem (and draft (draft-problem draft player))))
    (cond ((null draft) NIL)
          (problem
           (setf *forge-note* problem)
           (forge-changed)
           NIL)
          (T
           (let* ((spell (draft-spell draft))
                  (cost (sink-dust sink spell)))
             (take-item player :dust cost)
             (remf *forge-drafts* sink)
             (if (weapon-sink-p sink)
                 (progn
                   (setf (sink-spell player sink) spell)
                   (forge-select sink player)
                   (setf *forge-note* (format NIL "~a enchanted with ~a, for ~d dust."
                                              (sink-title sink) (spell-title spell) cost)))
                 (multiple-value-bind (cell key) (give-rune player spell)
                   (forge-select (nth cell (inventory player)) player)
                   (setf *forge-note* (format NIL "Made ~a for ~d dust: ~:[in the bag~;on key ~:*~d~]."
                                              (spell-title spell) cost (and key (1+ key))))))
             spell)))))

(defun forge-destroy (&optional (player *player*))
  "Unweave the rune on the forge, or disenchant its weapon, for half its dust back. The first
call only arms it (*FORGE-ARMED*); a second does it."
  (let* ((sink *forge-sink*)
         (spell (sink-spell player sink))
         (weapon (weapon-sink-p sink)))
    (cond ((null spell) NIL)
          ((not (eq *forge-armed* sink))
           (setf *forge-armed* sink
                 *forge-note* NIL)
           (forge-changed))
          (T
           (let ((back (refund-dust (sink-dust sink spell)))
                 (title (spell-title spell)))
             (if weapon
                 (setf (sink-spell player sink) NIL)
                 (destroy-stack player sink))
             (give-item player :dust back)
             (forge-select (if weapon sink :new) player)
             (setf *forge-note* (format NIL "~:[Unweaved~;Disenchanted~] ~a: ~d dust back." weapon title back))
             T)))))

(defun near-altar-p (player)
  "True if PLAYER stands at an altar: within *ALTAR-REACH* across of its middle, the feet within
*ALTAR-HEIGHT* of its top."
  (let ((feet (feet player)))
    (loop for top across *level-altars*
          thereis (and (< (+ (expt (- (vx top) (vx feet)) 2) (expt (- (vz top) (vz feet)) 2))
                          (expt *altar-reach* 2))
                       (< (abs (- (vy feet) (vy top))) *altar-height*)))))

;; E at an altar (INTERACT-TARGET, townsfolk.lisp) opens the forge.
(defmethod interactable-p ((thing (eql :altar))) T)
(defmethod interact ((thing (eql :altar)) player)
  (declare (ignore player))
  (open-forge))
(defmethod interact-label ((thing (eql :altar))) "Spellforge")

(defun open-forge ()
  (when (and (eq *game-state* :playing) *player*)
    (setf *game-state* :forge)
    (release-mouse *player*)
    (forge-tab *forge-tab*)))

(defun close-forge ()
  (when (eq *game-state* :forge)
    (setf *game-state* :playing)
    (when *player* (capture-mouse *player*))))

;;; The screen: the tabs, what the player holds down the left, the work on the right.

(defparameter *forge-row-height* 34)
(defparameter *forge-gap* 6)
(defparameter *forge-left-width* 300)
(defparameter *forge-right-width* 660)

(defclass forge-slider (menu-slider)
  ((describe :initarg :describe :reader slider-describe
             :documentation "A function of the value giving the text at the slider's right."))
  (:documentation "A MENU-SLIDER over any range, its value written as DESCRIBE writes it."))

(presentations:define-realization (presentations:default-look-and-feel forge-slider)
  ((:background simple:rectangle)
   (alloy:margins)
   :pattern *menu-button-color*)
  ((:fill simple:rectangle)
   (alloy:extent 0 0 0 (alloy:ph))
   :pattern *menu-slider-fill-color*)
  ((:border simple:rectangle)
   (alloy:margins)
   :line-width (alloy:un 2)
   :pattern *menu-border-color*)
  ((:label simple:text)
   (alloy:margins 10 1 1 1)
   (alloy:text alloy:renderable)
   :pattern *menu-text-color*
   :size (alloy:un 17)
   :halign :start :valign :middle)
  ((:value simple:text)
   (alloy:margins 1 1 10 1)
   ""
   :pattern *menu-text-color*
   :size (alloy:un 17)
   :halign :end :valign :middle))

(presentations:define-update (presentations:default-look-and-feel forge-slider)
  (:background
   :pattern (if (or alloy:focus alloy:hovered-p) *menu-button-hover-color* *menu-button-color*))
  (:fill
   :bounds (alloy:extent 0 0 (alloy:pw (alloy:slider-unit alloy:renderable)) (alloy:ph))
   :pattern *menu-slider-fill-color*)
  (:border
   :pattern *menu-border-color*
   :hidden-p NIL)
  (:label
   :text (alloy:text alloy:renderable)
   :pattern *menu-text-color*)
  (:value
   :text (funcall (slider-describe alloy:renderable) (alloy:value alloy:renderable))
   :pattern *menu-text-color*))

(defclass forge-note (alloy:label) ()
  (:documentation "Text that wraps within its row, which is as many lines tall as it needs."))

(presentations:define-realization (presentations:default-look-and-feel forge-note)
  ((:label simple:text)
   (alloy:margins 4 2 4 2)
   alloy:text
   :pattern *menu-text-color*
   :size (alloy:un 19)
   :wrap T
   :halign :start :valign :middle))

(presentations:define-update (presentations:default-look-and-feel forge-note)
  (:label
   :text alloy:text
   :pattern *menu-text-color*))

(defmethod presentations::compute-sizing-strategy ((renderer presentations:default-look-and-feel) (note forge-note))
  presentations::*fit-to-all-shapes*)

(defclass forge-panel (menu-panel)
  ((revision :initform *forge-revision* :reader panel-revision)
   (readout :initform (make-instance 'alloy:value-data :value "") :reader readout
            :documentation "The draft's name and costs: a slider changes it.")
   (note :initform (make-instance 'alloy:value-data :value "") :reader note
         :documentation "*FORGE-NOTE*, an armed Unweave's question, or why the draft can't be made.")
   (about :initform (make-instance 'alloy:value-data :value "") :reader about
          :documentation "The explanation of the effect *FORGE-ABOUT-INDEX* names.")
   (effect-buttons :initform () :accessor effect-buttons
                   :documentation "The effects' Effect buttons, redrawn when the one explained changes.")))

(defmethod panel-title ((panel forge-panel)) "Spellforge")
(defmethod panel-buttons ((panel forge-panel)) ())
(defmethod panel-stale-p ((panel forge-panel))
  (/= (panel-revision panel) *forge-revision*))

(defun forge-readout-text ()
  (let ((draft *forge-draft*))
    (if draft
        (format NIL "~a  -  ~a" (draft-name draft) (draft-cost-text draft *player*))
        "")))

(defun forge-note-text ()
  (or *forge-note*
      (and *forge-armed*
           (format NIL "~:[Unweave~;Disenchant~] ~a? Click again to do it."
                   (weapon-sink-p *forge-armed*) (spell-title (sink-spell *player* *forge-armed*))))
      (and *forge-draft* (draft-problem *forge-draft*))
      ""))

(defun forge-about-text ()
  (let ((effects (and *forge-draft* (draft-effects *forge-draft*))))
    (if effects
        (effect-about (nth (max 0 (min *forge-about-index* (1- (length effects)))) effects))
        "")))

(defun refresh-readout (panel)
  (setf (alloy:value (readout panel)) (forge-readout-text)
        (alloy:value (note panel)) (forge-note-text)
        (alloy:value (about panel)) (forge-about-text)))

(defun explain-effect (panel index)
  "Show the explanation of the draft's effect INDEX, and mark its Effect button."
  (unless (eql index *forge-about-index*)
    (setf *forge-about-index* index)
    (dolist (button (effect-buttons panel))
      (alloy:mark-for-render button)))
  (refresh-readout panel))

(defclass effect-control ()
  ((effect-index :initarg :effect-index :reader effect-index)
   (effect-panel :initarg :effect-panel :reader effect-panel))
  (:documentation "A control of one of the draft's effects: given the focus (a hover gives it), it
has the forge explain that effect."))

(defmethod (setf alloy:focus) :after (value (control effect-control))
  (when value
    (explain-effect (effect-panel control) (effect-index control))))

(defclass forge-effect-button (effect-control forge-choice) ()
  (:documentation "An effect's Effect button, drawn chosen while its effect is the one explained."))

(defmethod selected-p ((button forge-effect-button))
  (eql (effect-index button) *forge-about-index*))

(defclass forge-effect-action (effect-control menu-button) ()
  (:documentation "An effect's Element or Remove button."))

(defclass forge-effect-slider (effect-control forge-slider) ()
  (:documentation "One of an effect's dials."))

(defun forge-row (parent sizes &optional (height *forge-row-height*))
  "A row of cells SIZES wide in PARENT, HEIGHT tall, a grid to enter widgets into by :COL."
  (let ((row (make-instance 'alloy:grid-layout :col-sizes sizes :row-sizes (list height)
                                               :cell-margins (alloy:margins 3 0))))
    (alloy:enter row parent)
    row))

(defparameter *forge-selected-color* (chroma:color 0.30 0.22 0.07 0.95) "A selected choice's fill.")
(defparameter *forge-selected-border* (chroma:color 0.98 0.80 0.32) "A selected choice's border.")
(defparameter *forge-selected-text* (chroma:color 1.0 0.88 0.5) "A selected choice's label.")

(defclass forge-choice (menu-button)
  ((selected :initarg :selected :initform NIL :reader selected-p))
  (:documentation "A button for one of a set (a tab, a rune, a weapon): the one chosen has a gold
border, a warm fill and a gold label, apart from the hover's orange."))

(presentations:define-realization (presentations:default-look-and-feel forge-choice)
  ((:background simple:rectangle)
   (alloy:margins)
   :pattern *menu-button-color*)
  ((:border simple:rectangle)
   (alloy:margins)
   :line-width (alloy:un 2)
   :pattern *menu-border-color*)
  ((:label simple:text)
   (alloy:margins 1)
   alloy:text
   :pattern *menu-text-color*
   :size (alloy:un 20)
   :halign :middle :valign :middle))

(presentations:define-update (presentations:default-look-and-feel forge-choice)
  (:background
   :pattern (cond ((or alloy:focus alloy:hovered-p) *menu-button-hover-color*)
                  ((selected-p alloy:renderable) *forge-selected-color*)
                  (T *menu-button-color*)))
  (:border
   :pattern (if (selected-p alloy:renderable) *forge-selected-border* *menu-border-color*)
   :line-width (alloy:un (if (selected-p alloy:renderable) 3 2))
   :hidden-p NIL)
  (:label
   :text alloy:text
   :pattern (if (selected-p alloy:renderable) *forge-selected-text* *menu-text-color*)))

(defun forge-button (label action row col focus &key (selected NIL choice) effect)
  "A button LABEL in ROW's cell COL that runs ACTION, a function, on the next tick. With
:SELECTED, one of a set (FORGE-CHOICE), drawn chosen when it is true. With :EFFECT, (PANEL
INDEX), a control of that draft effect (EFFECT-CONTROL): its Effect button if :SELECTED is given
too, which is drawn chosen while that effect is explained."
  (let ((button (apply #'alloy:represent-with
                       (cond ((and effect choice) 'forge-effect-button)
                             (effect 'forge-effect-action)
                             (choice 'forge-choice)
                             (T 'menu-button))
                       (make-instance 'alloy:value-data :value label)
                       :focus-parent focus
                       (append (when choice (list :selected selected))
                               (when effect (list :effect-panel (first effect) :effect-index (second effect)))))))
    (alloy:enter button row :row 0 :col col)
    (alloy:on (alloy:activate button) ()
      (queue-menu-action action))
    button))

(defun forge-text (text row col &optional (value ""))
  (alloy:enter (alloy:represent-with 'menu-stat (make-instance 'alloy:value-data :value text) :value value)
               row :row 0 :col col))

(defun note-lines (text &optional (chars *forge-note-chars*))
  "Rows TEXT takes, broken at spaces into rows of about CHARS characters, as Alloy wraps it. A row
too short for its text draws none of it, so count words, not characters."
  (max 1 (length (wrap-text text chars))))

(defun forge-note-row (parent data &optional (lines 1))
  "A row of wrapping text LINES rows tall, showing DATA, a string or an ALLOY:VALUE-DATA."
  (let ((row (forge-row parent '(T) (+ (* lines (- *forge-row-height* 10)) 10))))
    (alloy:enter (alloy:represent-with 'forge-note
                                       (if (stringp data) (make-instance 'alloy:value-data :value data) data))
                 row :row 0 :col 0)
    row))

(defun forge-dial (panel label getter setter range step describe row col focus index)
  "A dial of the draft's effect INDEX."
  (let ((slider (alloy:represent-with 'forge-effect-slider
                                      (make-instance 'alloy:place-data
                                                     :getter getter
                                                     :setter (lambda (value)
                                                               (funcall setter value)
                                                               (setf *forge-note* NIL)
                                                               (refresh-readout panel)))
                                      :text label :range range :step step :grid step
                                      :describe describe :focus-parent focus
                                      :effect-panel panel :effect-index index)))
    (alloy:enter slider row :row 0 :col col)
    slider))

;;; What each effect does, under its dials: from the parameters, so it stays true when they're tuned.

(defparameter *forge-about-chars* 60
  "Characters a line of an effect's explanation holds before it wraps: about 62 at its size, but
Jersey 15 isn't fixed-width, so a little under.")

(defun resisters (element)
  "Who takes less of ELEMENT, as a phrase: \"acolytes take half\"."
  (let ((entries (remove element *element-resistances* :key #'second :test-not #'eq)))
    (when entries
      (format NIL "~{~a~^ and ~} take ~a"
              (mapcar (lambda (e) (string-downcase (substitute #\Space #\- (format NIL "~as" (first e))))) entries)
              (let ((fraction (third (first entries))))
                (if (= fraction 0.5) "half" (format NIL "~d% less" (round (* 100 fraction)))))))))

(defun effect-about (effect)
  "What EFFECT, an effect draft, does, in a sentence or two: its kind's rule, its element's quirk
and who resists it, and what its time and area change."
  (let* ((kind (draft-kind effect))
         (element (draft-element effect))
         (over-time (< 0 (draft-duration effect)))
         (area (< 0 (draft-area effect)))
         (text
           (case kind
             (:damage
              (format NIL "~a~@[ ~@(~a~).~]~:[~; Over time: that much a second, ticking on it, with no flinch~:[~;, so shock's pain bonus is lost~].~]"
                      (ecase (or element :fire)
                        (:fire "Fire: plain damage, the cheapest to cast.")
                        (:frost (format NIL "Frost: also chills what it hits, ~d% slower for ~d s. Costs more than fire."
                                        *frost-chill* (round *frost-chill-time*)))
                        (:shock (format NIL "Shock: +~d% to the pain roll, so foes flinch and break off their attacks more often. Costs more than fire."
                                        *shock-pain-bonus*)))
                      (resisters (or element :fire))
                      over-time (eq element :shock)))
             (:heal (if over-time
                        "Heals you that much a second for its time, rather than all at once."
                        "Heals you at once."))
             (:knockback "Pushes what it strikes away; while it slides it can't walk or lunge at you.")
             (:slow (format NIL "Slows what it strikes by that much for its time, never below ~d% of its speed."
                            (round (* 100 *slowest*))))
             (:drain "Takes health from what it strikes and gives you half of what it took. It has no element, so nothing resists it.")
             (:ward "Takes blows for you: absorbs that much damage before your health does, until it is spent or its time runs out.")
             (T ""))))
    (if area
        (concatenate 'string text " It bursts over its area: everything there in a clear line, but you.")
        text)))

(defclass forge-about (forge-note) ()
  (:documentation "A smaller, dimmer FORGE-NOTE: an effect's explanation under its dials."))

(defparameter *forge-about-color* (chroma:color 0.72 0.68 0.6) "An effect's explanation's text.")

(presentations:define-realization (presentations:default-look-and-feel forge-about)
  ((:label simple:text)
   (alloy:margins 6 0 4 0)
   alloy:text
   :pattern *forge-about-color*
   :size (alloy:un 15)
   :wrap T
   ;; From the top: the box is as tall as the longest explanation its effects can need.
   :halign :start :valign :top))

(presentations:define-update (presentations:default-look-and-feel forge-about)
  (:label
   :text alloy:text
   :pattern *forge-about-color*))

(defparameter *forge-about-line* 28
  "Height of a line of an explanation, in the units rows are measured in: Jersey 15 at size 15,
with a little to spare. A row too short for its text draws none of it.")

(defun forge-about-row (parent data lines)
  "The explanation box, LINES lines of small text showing DATA, an ALLOY:VALUE-DATA."
  (let ((row (forge-row parent '(T) (+ (* lines *forge-about-line*) 8))))
    (alloy:enter (alloy:represent-with 'forge-about data) row :row 0 :col 0)
    row))

(defun about-lines (effect player)
  "Lines EFFECT's explanation can take whatever its dials say: with its longest time and its area
on, since a dial changes the text but doesn't remake the panel."
  (let ((kind (draft-kind effect)))
    (note-lines (effect-about (make-instance 'effect-draft
                                             :kind kind :element (draft-element effect) :magnitude 1
                                             :duration (if (eq :instant (kind-property kind :timing)) 0
                                                           (kind-property kind :duration))
                                             :area (if (and (area-known-p player) (not (self-kind-p kind)))
                                                       (kind-property kind :area)
                                                       0)))
                *forge-about-chars*)))

(defun build-effect-rows (panel column effect index focus player)
  (let ((kind (draft-kind effect))
        (row (forge-row column '(250 250 T)))
        (control (list panel index)))
    (push (forge-button (format NIL "Effect: ~:(~a~)" kind) (lambda () (forge-cycle-kind index)) row 0 focus
                        :selected NIL :effect control)
          (effect-buttons panel))
    (if (eq kind :damage)
        (forge-button (format NIL "Element: ~:(~a~)" (draft-element effect)) (lambda () (forge-cycle-element index))
                      row 1 focus :effect control)
        (forge-text (if (self-kind-p kind) "On you" "On what it strikes") row 1))
    (forge-button "Remove" (lambda () (forge-remove-effect index)) row 2 focus :effect control)
    (let ((dials (forge-row column '(220 220 T))))
      (forge-dial panel (if (member kind '(:slow)) "Slow" "Power")
                  (lambda () (draft-magnitude effect))
                  (lambda (v) (setf (draft-magnitude effect) (max 1 (round v))))
                  (cons 1 (kind-property kind :magnitude)) 1
                  (lambda (v)
                    (let ((top (max 1 (round v))))
                      (if (eq kind :slow)
                          (format NIL "~d%" top)
                          (format NIL "~d-~d~:[~;/s~]" (max 1 (ceiling (* *magnitude-spread* top))) top
                                  (and (eq :over-time (kind-property kind :timing)) (< 0 (draft-duration effect)))))))
                  dials 0 focus index)
      (if (eq :instant (kind-property kind :timing))
          (forge-text "Instant" dials 1)
          (forge-dial panel "Time"
                      (lambda () (draft-duration effect))
                      (lambda (v) (setf (draft-duration effect) (round v)))
                      (cons (if (eq :status (kind-property kind :timing)) 1 0) (kind-property kind :duration)) 1
                      (lambda (v) (if (< 0 (round v)) (format NIL "~d s" (round v)) "at once"))
                      dials 1 focus index))
      (if (and (area-known-p player) (not (self-kind-p kind)) (< 0 (kind-property kind :area)))
          (forge-dial panel "Area"
                      (lambda () (draft-area effect))
                      (lambda (v) (setf (draft-area effect) (/ (round (* 2 v)) 2)))
                      (cons 0 (kind-property kind :area)) 0.5
                      (lambda (v) (if (< 0 v) (format NIL "~,1f m" (/ (round (* 2 v)) 2)) "one"))
                      dials 2 focus index)
          (forge-text (if (self-kind-p kind) "" "No area") dials 2)))))

(defun shown-spell-lines (player sink)
  "What the forge says of a rune or an enchanted weapon it only shows."
  (let ((spell (sink-spell player sink)))
    (if (weapon-sink-p sink)
        (cons (format NIL "~d MP a blow, ~d dust to make" (enchant-cost spell) (enchant-dust spell))
              (mapcan #'effect-lines (spell-effects spell)))
        (append (spell-lines spell)
                (list (format NIL "Made for ~d dust, ~a" (spell-dust spell)
                              (let ((key (stack-key player sink))) (if key (format NIL "on key ~d" (1+ key)) "in the bag"))))))))

(defmethod build-panel ((panel forge-panel))
  (let* ((player *player*)
         (tab *forge-tab*)
         ;; Only a choice that is gone (a rune unweaved, a weapon dropped) is chosen again: that
         ;; clears the note and an armed Unweave, which every remake would otherwise lose.
         (sink (if (valid-sink-p player *forge-sink* tab)
                   *forge-sink*
                   (forge-select (default-sink player tab) player)))
         (draft *forge-draft*)
         (weapon (weapon-sink-p sink))
         ;; The two columns side by side in one row as tall as the taller, so their tops are
         ;; level, and that row centred in a cell the screen's height (PANEL-BACKDROP).
         (backdrop (panel-backdrop panel (+ *forge-left-width* 24 *forge-right-width*)
                                   :cell-margins (alloy:margins 0)))
         (frame (make-instance 'alloy:vertical-linear-layout :align :middle :cell-margins (alloy:margins 0)))
         (sides (make-instance 'alloy:grid-layout :col-sizes `(,*forge-left-width* 24 ,*forge-right-width*)
                                                  :row-sizes '(T)))
         (left (make-instance 'alloy:vertical-linear-layout
                              :min-size (alloy:size *forge-left-width* *forge-row-height*)
                              :cell-margins (alloy:margins 0 (/ *forge-gap* 2))))
         (right (make-instance 'alloy:vertical-linear-layout
                               :min-size (alloy:size *forge-right-width* *forge-row-height*)
                               :cell-margins (alloy:margins 0 (/ *forge-gap* 2))))
         (focus (make-instance 'alloy:focus-list)))
    ;; FORGE-SELECT bumped the revision; this panel is the one for it.
    (setf (slot-value panel 'revision) *forge-revision*)
    (alloy:enter frame backdrop :row 0 :col 1)
    (alloy:enter sides frame)
    (alloy:enter left sides :row 0 :col 0)
    (alloy:enter right sides :row 0 :col 2)
    ;; The tabs, the dust, and what the player holds.
    (alloy:enter (alloy:represent "Spellforge" 'menu-title) left)
    (let ((row (forge-row left '(T T))))
      (forge-button "Spells" (lambda () (forge-tab :spells)) row 0 focus :selected (eq tab :spells))
      (forge-button "Enchant" (lambda () (forge-tab :enchant)) row 1 focus :selected (eq tab :enchant)))
    (forge-text "Arcane dust" (forge-row left '(T)) 0 (princ-to-string (player-dust player)))
    (if (eq tab :spells)
        (let* ((runes (player-runes player))
               (pages (max 1 (ceiling (length runes) *forge-list-rows*)))
               (page (min *forge-page* (1- pages))))
          (forge-button "New spell" (lambda () (forge-select :new)) (forge-row left '(T)) 0 focus
                        :selected (eq sink :new))
          (loop for rune in (nthcdr (* page *forge-list-rows*) runes)
                repeat *forge-list-rows*
                do (let ((rune rune))
                     (forge-button (fit-label (format NIL "~a (~a)" (sink-title rune) (rune-place player rune)))
                                   (lambda () (forge-select rune)) (forge-row left '(T)) 0 focus
                                   :selected (eq rune sink))))
          (when (< 1 pages)
            (let ((row (forge-row left '(T T))))
              (forge-button "< Prev" (lambda () (forge-page -1)) row 0 focus)
              (forge-button "Next >" (lambda () (forge-page 1)) row 1 focus))))
        (dolist (w (carried-weapons player))
          (let ((w w) (spell (sink-spell player w)))
            (forge-button (fit-label (format NIL "~a: ~a" (sink-title w) (if spell (spell-title spell) "plain")))
                          (lambda () (forge-select w)) (forge-row left '(T)) 0 focus
                          :selected (eq w sink)))))
    ;; The work: a draft to make, or a spell to look at and unweave.
    (alloy:enter (alloy:represent-with 'menu-title (make-instance 'alloy:value-data
                                                                  :value (if draft (sink-title sink)
                                                                             (spell-title (sink-spell player sink)))))
                 right)
    (cond (draft
           (if weapon
               (forge-text "Its blows carry it, for mana a blow" (forge-row right '(T)) 0)
               (forge-button (format NIL "Delivery: ~:(~a~)" (draft-delivery draft)) 'forge-cycle-delivery
                             (forge-row right '(T)) 0 focus))
           (setf *forge-about-index* (max 0 (min *forge-about-index* (1- (length (draft-effects draft))))))
           (loop for effect in (draft-effects draft)
                 for index from 0
                 do (build-effect-rows panel right effect index focus player))
           ;; What the effect in hand does: one box, as tall as the longest its effects can need.
           (when (draft-effects draft)
             (forge-about-row right (about panel)
                              (loop for effect in (draft-effects draft) maximize (about-lines effect player))))
           (when (and (draft-kinds draft player)
                      (< (length (draft-effects draft)) (if weapon *max-enchant-effects* *max-spell-effects*)))
             (forge-button "Add an effect" 'forge-add-effect (forge-row right '(T)) 0 focus))
           ;; The name and costs: two lines, since a three-effect name runs past one.
           (forge-note-row right (readout panel) 2))
          (T
           (dolist (line (shown-spell-lines player sink))
             (forge-note-row right line (note-lines line)))))
    (forge-note-row right (note panel) 2)
    (refresh-readout panel)
    (let ((row (forge-row right '(320 T 200))))
      (cond (draft
             (forge-button (if weapon "Enchant it" "Make the spell") 'forge-make row 0 focus))
            (T
             (forge-button (format NIL "~a~:[~;: sure?~] (+~d dust)"
                                   (if weapon "Disenchant" "Unweave") (eq *forge-armed* sink)
                                   (refund-dust (sink-dust sink (sink-spell player sink))))
                           'forge-destroy row 0 focus)))
      (forge-text "" row 1)
      (forge-button "Leave" 'close-forge row 2 focus))
    (alloy:finish-structure panel backdrop focus)))
