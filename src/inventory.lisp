(in-package #:hexmaw)

;;; The inventory: the bag of items the player carries, the hotbar whose keys 1 to 9 take a
;;; weapon or spell in the bag in hand, a quickslot Q drinks a kind of potion from, and a panel to
;;; move them around in. A stack is a list (KIND COUNT), a rune's (:RUNE 1 SPELL); a slot is a
;;; cell's index in the player's INVENTORY, one of *HOTBAR-SLOTS* or :QUICK. The hotbar and the
;;; quickslot hold nothing themselves: they point into the bag, so binding a key frees no room.
;;; The hotbar is shown in play above the bars, the quickslot above it, and the mouse wheel
;;; binds Q to the potion kinds the bag holds in turn; I opens the panel above them
;;; (*GAME-STATE* :INVENTORY), which freezes the world as the map does.
;;; Icons come from data/sprites/icons/items (tools/draw_item_icons.py), a weapon's and a rune's
;;; from the weapon icons (sword.lisp).

(define-fx-animation item-icons "sprites/icons/items")

(defparameter *item-kinds*
  '((:health-potion :name "Health potion" :icon 0 :resource :health :amount 40 :stack 5)
    (:mana-potion :name "Mana potion" :icon 1 :resource :mana :amount 50 :stack 5)
    (:dust :name "Arcane dust" :icon 2 :stack 999
     :about "Spent at an altar to make spells and enchant weapons")
    (:gold :name "Gold" :icon 3 :stack 999 :note "coins" :about "Coin, for trade")
    (:relic :name "Reliquary" :icon 4 :stack 1 :about "Lost in the undercroft: the quest-giver wants it back")
    (:sword :name "Sword" :weapon :sword :stack 1)
    (:spear :name "Spear" :weapon :spear :stack 1)
    (:maul :name "Maul" :weapon :maul :stack 1)
    (:rune :name "Rune" :stack 1))
  "What each kind of item is: its name, its frame in the icon strip, what it restores, and how
many fit in one stack. A pickup that gives one (*PICKUP-KINDS*) counts its :AMOUNT in a level's
budget, so keep the two the same. A weapon's :WEAPON is what it puts in the player's hand
(sword.lisp); a rune is a spell the hands cast, its stack (:RUNE 1 SPELL). Neither stacks.")

(defparameter *hotbar-slots* '(:hot-1 :hot-2 :hot-3 :hot-4 :hot-5 :hot-6 :hot-7 :hot-8 :hot-9)
  "The hotbar's slots, keys 1 to 9, *HOTBAR-SIZE* of them (player.lisp).")
(defparameter *offhand-slots* '(:off-1 :off-2 :off-3 :off-4 :off-5 :off-6 :off-7 :off-8 :off-9)
  "The hotbar slots' off hands, each the rune the right button casts while its slot's rune is in hand.")
(defparameter *hotbar-columns* 5
  "Hotbar slots in a row, from the top one down: in one row of nine the hands covered the last.")

(defparameter *inventory-columns* 5 "Cells across the panel; *INVENTORY-SIZE* decides the rows.")
(defparameter *inventory-padding* 8 "Pixels between the panel's edge and what's in it.")
(defparameter *inventory-hint* "Drag onto ~a or ~a to bind"
  "The panel's hint with no item under the pointer, given the hotbar's keys and the quickslot's.")
(defparameter *inventory-back-color* (vec4 0.20 0.16 0.13 0.92))
(defparameter *tooltip-lines* 14 "Most lines an item's tooltip shows.")
(defparameter *tooltip-width* 36 "Characters a tooltip line holds; a longer one wraps (WRAP-TEXT, hud.lisp).")
(defparameter *tooltip-padding* 7 "Pixels between the tooltip's edge and its text.")
(defparameter *tooltip-offset* 20 "Pixels between the pointer and the tooltip.")
(defparameter *tooltip-line-gap* 3 "Pixels between the tooltip's lines.")
(defparameter *glyph-width* 11
  "Pixels a HUD text character takes across on average, for wrapping by characters (TEXT-WIDTH,
hud.lisp, measures a line).")
(defparameter *inventory-border-color* (vec4 0.60 0.48 0.28 1))

(defun item-property (kind key)
  (getf (rest (or (assoc kind *item-kinds*) (error "No item kind ~s." kind))) key))

;;; The model. The bag holds every item; the hotbar and the quickslot only point into it: a
;;; hotbar slot at a stack in the bag (EQ), the quickslot at a kind of potion, so binding a key
;;; never takes an item out of the bag.

(defun hotbar-index (slot)
  "SLOT's place on the hotbar, from 0, or NIL if it isn't one of *HOTBAR-SLOTS*."
  (position slot *hotbar-slots*))

(defun offhand-index (slot)
  "The hotbar slot, from 0, whose off hand SLOT is, or NIL if it isn't one of *OFFHAND-SLOTS*."
  (position slot *offhand-slots*))

(defvar *quick-view* (list NIL 0)
  "Scratch: the quickslot as a stack to draw, (KIND TOTAL), rewritten as it is asked for.")

(defun kind-total (player kind)
  "How many of KIND PLAYER's bag holds, every stack together."
  (loop for stack in (inventory player)
        when (and stack (eq kind (first stack))) sum (second stack)))

(defun item-room (player kind)
  "How many more of KIND PLAYER's bag takes: what its stacks still hold and its empty cells."
  (loop for stack in (inventory player)
        sum (cond ((null stack) (item-property kind :stack))
                  ((eq kind (first stack)) (stack-room stack))
                  (T 0))))

(defun gold (player)
  "The coin PLAYER carries: the bag's :GOLD, in stacks of 999 like any item."
  (kind-total player :gold))

(defun (setf gold) (amount player)
  "Make the bag hold AMOUNT gold, giving or taking the difference. An older save's purse, a slot
of its own, comes back through this, after the bag (RESTORE-STATE): what won't fit is lost."
  (let ((have (gold player)))
    (if (< have amount)
        (give-item player :gold (- amount have))
        (take-item player :gold (- have amount))))
  amount)

(defun slot-stack (player slot)
  "What SLOT shows: a bag cell's stack, the bag stack a hotbar slot points at, or for :QUICK
its kind and the bag's total of it (*QUICK-VIEW*), NIL when it is unbound; an off hand's rune."
  (let ((hot (hotbar-index slot))
        (off (offhand-index slot)))
    (cond ((eq slot :quick)
           (let ((kind (quickslot player)))
             (when kind
               (setf (first *quick-view*) kind
                     (second *quick-view*) (kind-total player kind))
               *quick-view*)))
          (hot (nth hot (hotbar player)))
          (off (nth off (offhands player)))
          (T (nth slot (inventory player))))))

(defun potion-p (stack)
  (item-property (first stack) :resource))

(defun bindable-p (stack)
  "True if STACK may go on the hotbar: a weapon or a rune."
  (let ((kind (first stack)))
    (or (eq kind :rune) (item-property kind :weapon))))

(defun stack-spell (stack)
  "The spell a rune's STACK casts, or NIL."
  (and (eq :rune (first stack)) (third stack)))

(defun weapon-stack-p (stack)
  (and (consp stack) (item-property (first stack) :weapon) T))

(defun stack-enchantment (stack)
  "The spell a weapon's STACK, (KIND 1 SPELL), strikes with on every blow (ENCHANT-STRIKE,
sword.lisp), or NIL for a plain one: each weapon has its own, as a rune its spell."
  (and (weapon-stack-p stack) (third stack)))

(defun (setf stack-enchantment) (spell stack)
  (if (cddr stack)
      (setf (third stack) spell)
      (setf (cdr (cdr stack)) (list spell)))
  spell)

(defun stack-label (stack)
  "STACK in a word or two, for TOOLS/HD STATUS: -, sword, bolt, health-potion*3."
  (cond ((null stack) "-")
        ((eq :rune (first stack)) (substitute #\- #\Space (string-downcase (spell-title (stack-spell stack)))))
        ((stack-enchantment stack)
         (format NIL "~(~a~)[~a]" (first stack)
                 (substitute #\- #\Space (string-downcase (spell-title (stack-enchantment stack))))))
        ((= 1 (second stack)) (string-downcase (first stack)))
        (T (format NIL "~(~a~)*~d" (first stack) (second stack)))))

(defun carried-stacks (player)
  "Every stack PLAYER carries: the bag's."
  (remove NIL (inventory player)))

(defun stack-slot (player stack)
  "The bag cell STACK lives in, or NIL."
  (position stack (inventory player)))

(defun stack-key (player stack)
  "The hotbar slot, from 0, bound to STACK, or NIL."
  (position stack (hotbar player)))

(defun offhand-key (player stack)
  "The hotbar slot, from 0, whose off hand holds STACK, or NIL."
  (position stack (offhands player)))

(defun prune-bindings (player)
  "Unbind every hotbar slot and off hand whose stack has left the bag, and the off hand of a slot
that holds no rune. Allocates nothing."
  (let ((bag (inventory player)))
    (loop for cell on (hotbar player)
          when (and (car cell) (not (member (car cell) bag :test #'eq)))
            do (setf (car cell) NIL))
    (loop for cell on (offhands player)
          for main in (hotbar player)
          when (and (car cell) (or (not (member (car cell) bag :test #'eq))
                                   (not (eq :rune (first main)))))
            do (setf (car cell) NIL))))

(defun unbind-stack (player stack)
  "Take STACK off every hotbar slot and off hand: a rune is in one place at a time."
  (loop for cell on (hotbar player)
        when (eq (car cell) stack) do (setf (car cell) NIL))
  (loop for cell on (offhands player)
        when (eq (car cell) stack) do (setf (car cell) NIL)))

(defun bind-stack (player stack index)
  "Bind hotbar slot INDEX to STACK, a bag stack, taking it off any other slot or off hand."
  (unbind-stack player stack)
  (setf (nth index (hotbar player)) stack)
  (prune-bindings player))

(defun bind-offhand (player stack index)
  "Put STACK, a rune, in hotbar slot INDEX's off hand, taking it off any other: only while that
slot holds a rune. True if it was put there."
  (when (and (eq :rune (first stack)) (eq :rune (first (nth index (hotbar player)))))
    (unbind-stack player stack)
    (setf (nth index (offhands player)) stack)
    T))

(defun offhand-spell (player)
  "The spell the right button casts: the off-hand rune of the hotbar slot asked for, while that
slot's rune is what the hands hold."
  (let ((slot (wanted-slot player)))
    (and (eq (weapon player) :hands) (held-spell player)
         (stack-spell (nth slot (offhands player))))))

(defun give-stack (player stack)
  "Put STACK, a weapon or a rune, in the first empty bag cell, bound to the first free hotbar key
if there is one. Its bag cell and its key (from 0, or NIL), or NIL if the bag is full."
  (let ((cell (position NIL (inventory player)))
        (key (position NIL (hotbar player))))
    (when cell
      (setf (nth cell (inventory player)) stack)
      (when key (setf (nth key (hotbar player)) stack))
      (values cell key))))

(defun give-rune (player spell)
  "Put a new rune of SPELL in the bag (GIVE-STACK)."
  (give-stack player (list :rune 1 spell)))

(defun destroy-stack (player stack)
  "Take STACK out of the bag, and off any key bound to it."
  (let ((cell (stack-slot player stack)))
    (when cell
      (setf (nth cell (inventory player)) NIL)
      (prune-bindings player)
      T)))

(defun stack-room (stack)
  (- (item-property (first stack) :stack) (second stack)))

(defun give-item (player kind &optional (count 1))
  "Put COUNT of KIND in the bag: onto its stacks with room first, then into empty cells. How many
went in; the rest stays out. The first potion found binds the quickslot if nothing is bound
to it, so Q works straight away."
  (let ((bag (inventory player))
        (left count))
    (dolist (stack bag)
      (when (and stack (eq kind (first stack)) (< 0 left))
        (let ((moved (min left (stack-room stack))))
          (incf (second stack) moved)
          (decf left moved))))
    (loop for cell on bag
          while (< 0 left)
          unless (car cell)
            do (let ((moved (min left (item-property kind :stack))))
                 (setf (car cell) (list kind moved))
                 (decf left moved)))
    (when (and (< left count) (null (quickslot player)) (item-property kind :resource))
      (setf (quickslot player) kind))
    (- count left)))

(defun take-item (player kind count)
  "Take COUNT of KIND from the bag, smallest stacks first. True if it held that many; if not,
nothing is taken."
  (when (<= count (kind-total player kind))
    (let ((bag (inventory player)))
      (loop while (< 0 count)
            do (let* ((stack (loop with best = NIL
                                   for s in bag
                                   when (and s (eq kind (first s)) (or (null best) (< (second s) (second best))))
                                     do (setf best s)
                                   finally (return best)))
                      (taken (min count (second stack))))
                 (decf count taken)
                 (when (= 0 (decf (second stack) taken))
                   (setf (nth (position stack bag) bag) NIL)))))
    T))

(defun steal-item (player)
  "Take one potion from PLAYER, as a thief does (imp.lisp): of the quickslot's kind if the bag
holds any, else of the first kind in the bag. Returns its kind, or NIL if there was none."
  (let ((kind (or (let ((quick (quickslot player)))
                    (and quick (< 0 (kind-total player quick)) quick))
                  (first (find-if (lambda (stack) (and stack (potion-p stack) (< 0 (second stack))))
                                  (inventory player))))))
    (when (and kind (take-item player kind 1))
      kind)))

(defun use-quickslot (player)
  "Drink one of the quickslot's kind, from its smallest stack in the bag. True if one was drunk;
at full, or with none, none is."
  (let ((kind (quickslot player)))
    (when (and kind (< 0 (kind-total player kind)) (< 0 (health player))
               (restore-resource player (item-property kind :resource) (item-property kind :amount)))
      (take-item player kind 1)
      T)))

(defun move-stack (player from to)
  "Drop what slot FROM shows onto slot TO. Between bag cells a stack moves into an empty cell,
merges onto its own kind as far as the stack limit allows, or swaps; the keys bound to it follow
it. A bag stack dropped on a hotbar slot binds that key (only a weapon or a rune), a potion on
the quickslot binds Q to its kind, and two hotbar slots swap their bindings. A hotbar slot or the
quickslot dropped anywhere else (TO NIL, nowhere) is unbound. True if anything changed."
  (let ((source (slot-stack player from))
        (from-hot (hotbar-index from))
        (to-hot (and to (hotbar-index to))))
    (cond ((or (null source) (eql from to)) NIL)
          ;; From a key: onto another, the two swap, off hands and all; onto an off hand, its rune
          ;; goes there; anywhere but the quickslot, it is unbound.
          (from-hot
           (cond (to-hot (rotatef (nth from-hot (hotbar player)) (nth to-hot (hotbar player)))
                         (rotatef (nth from-hot (offhands player)) (nth to-hot (offhands player)))
                         (prune-bindings player)
                         T)
                 ((offhand-index to) (bind-offhand player source (offhand-index to)))
                 ((eq to :quick) NIL)
                 (T (setf (nth from-hot (hotbar player)) NIL) (prune-bindings player) T)))
          ;; From an off hand: onto another, it moves there; onto a key, it is that key's rune;
          ;; anywhere else, it is unbound.
          ((offhand-index from)
           (cond ((offhand-index to) (bind-offhand player source (offhand-index to)))
                 (to-hot (bind-stack player source to-hot) T)
                 ((eq to :quick) NIL)
                 (T (setf (nth (offhand-index from) (offhands player)) NIL) T)))
          ((eq from :quick)
           (unless (or to-hot (eq to :quick))
             (setf (quickslot player) NIL)
             T))
          ;; From the bag.
          ((offhand-index to)
           (bind-offhand player source (offhand-index to)))
          (to-hot
           (when (bindable-p source)
             (bind-stack player source to-hot)
             T))
          ((eq to :quick)
           (when (potion-p source)
             (setf (quickslot player) (first source))
             T))
          ((null to) NIL)
          (T
           (let ((target (nth to (inventory player)))
                 (bag (inventory player)))
             (cond ((null target)
                    (setf (nth to bag) source (nth from bag) NIL)
                    T)
                   ((and (eq (first source) (first target)) (< 1 (item-property (first source) :stack)))
                    (let ((moved (min (second source) (stack-room target))))
                      (incf (second target) moved)
                      (when (= 0 (decf (second source) moved))
                        (setf (nth from bag) NIL))
                      (< 0 moved)))
                   (T
                    (setf (nth to bag) source (nth from bag) target)
                    T)))))))

(defun cycle-quickslot (player step)
  "Bind the quickslot to the next potion kind STEP places round *ITEM-KINDS* that the bag
holds; a negative STEP goes back. True if it changed."
  (let* ((kinds (loop for (kind . properties) in *item-kinds*
                      when (getf properties :resource) collect kind))
         (current (quickslot player))
         (start (or (position current kinds) (if (< 0 step) -1 0)))
         (n (length kinds)))
    (loop for i from 1 to n
          for kind = (nth (mod (+ start (* i step)) n) kinds)
          when (and (not (eq kind current)) (< 0 (kind-total player kind)))
            do (setf (quickslot player) kind)
               (return T))))

;;; The starting kit, and what a save or the stairs bring.

(defun kit-spell (spell)
  "A starting kit's SPELL: a defined spell's name, or a spec whose first element is its name."
  (if (consp spell) (spec-spell spell) (find-spell spell)))

(defun kit-entry (entry)
  "A starting kit's ENTRY (*STARTING-HOTBAR*) as its slot's spell or weapon and its off hand's spell:
a weapon's item kind, a spell, or a list of two spells."
  (cond ((keywordp entry) (values entry NIL))
        ((and (consp entry) (not (stringp (first entry)))) (values (first entry) (second entry)))
        (T (values entry NIL))))

(defun give-starting-kit (player)
  "Fill PLAYER's empty bag with *STARTING-HOTBAR*'s weapons and spells (player.lisp), each bound
to its key and an off-hand rune to its key's off hand; on the debug level, *DEBUG-STARTING-HOTBAR*'s."
  (let ((bag (make-list *inventory-size*))
        (hotbar (make-list *hotbar-size*))
        (offhands (make-list *hotbar-size*))
        (cell 0))
    (loop for entry in (if (eq *level* :test) *debug-starting-hotbar* *starting-hotbar*)
          for i from 0
          do (multiple-value-bind (main off) (kit-entry entry)
               (let ((stack (if (keywordp main) (list main 1) (list :rune 1 (kit-spell main)))))
                 (setf (nth cell bag) stack (nth i hotbar) stack)
                 (incf cell))
               (when off
                 (let ((stack (list :rune 1 (kit-spell off))))
                   (setf (nth cell bag) stack (nth i offhands) stack)
                   (incf cell)))))
    (setf (inventory player) bag
          (hotbar player) hotbar
          (offhands player) offhands)))

(defun hotbar-cells (player)
  "The hotbar as the bag cells its slots point at, NIL for an empty one: how a save keeps it."
  (mapcar (lambda (stack) (and stack (stack-slot player stack))) (hotbar player)))

(defun (setf hotbar-cells) (cells player)
  (setf (hotbar player)
        (loop for i from 0 below *hotbar-size*
              for cell = (nth i cells)
              collect (and cell (nth cell (inventory player)))))
  cells)

(defun offhand-cells (player)
  "The off hands as the bag cells they point at, NIL for an empty one: how a save keeps them."
  (mapcar (lambda (stack) (and stack (stack-slot player stack))) (offhands player)))

(defun (setf offhand-cells) (cells player)
  (setf (offhands player)
        (loop for i from 0 below *hotbar-size*
              for cell = (nth i cells)
              collect (and cell (nth cell (inventory player)))))
  cells)

(defun migrate-known-effects (player)
  "Teach PLAYER whatever a run now starts knowing (*STARTING-EFFECTS*) that a save made before it
did not: Absorb, to a save from before it was. Harmless on a current one."
  (dolist (effect *starting-effects*)
    (pushnew effect (known-effects player))))

(defun migrate-enchantments (player)
  "Bring PLAYER's enchantments from an older save's layout, where a sword's or spear's was the
player's (ENCHANTMENTS, keyed by weapon), onto the first stack of that weapon in the bag. Only the
shield's stays the player's. Harmless on a current one."
  (dolist (weapon '(:sword :spear))
    (let ((spell (getf (enchantments player) weapon)))
      (when spell
        (let ((stack (find-if (lambda (stack) (and stack (eq weapon (item-property (first stack) :weapon))
                                                   (null (stack-enchantment stack))))
                              (inventory player))))
          (when stack (setf (stack-enchantment stack) spell)))
        (remf (enchantments player) weapon)))))

(defun migrate-bindings (player)
  "Bring PLAYER from an older save's layout to this one: a hotbar that held its items moves them
into the bag, still bound, and a quickslot that held a stack pours it into the bag and is bound
to its kind. Whatever won't fit is lost. Harmless on a current one."
  (let ((bag (inventory player)))
    (loop for cell on (hotbar player)
          for stack = (car cell)
          when (and stack (not (member stack bag :test #'eq)))
            do (let ((free (position NIL bag)))
                 (if free
                     (setf (nth free bag) stack)
                     (setf (car cell) NIL)))))
  (let ((quick (quickslot player)))
    (when (consp quick)
      (setf (quickslot player) (first quick))
      (when (< 0 (second quick))
        (give-item player (first quick) (second quick))))))

;;; What's drawn. The hotbar's slots and the quickslot are weapon slots (sword.lisp); the panel's
;;; parts draw last and in order (LATE-RANK), so its see-through back never covers world drawn
;;; after it.

(define-shader-entity item-icon (weapon-icon)
  ((animation :initform (find-fx-animation 'item-icons))
   (shown :initform NIL :accessor shown)))

(defmethod hud-shown-p ((icon item-icon))
  (and (call-next-method) (shown icon)))

(define-shader-entity inventory-part () ())

(defmethod hud-shown-p ((part inventory-part))
  (and (call-next-method) (eq *game-state* :inventory)))

(define-shader-entity inventory-back (inventory-part weapon-slot) ())
;; An off hand's cell, small in its hotbar slot's top-right corner: shown in play while it holds a
;; rune, and in the panel for every slot that holds one, to drop a rune on.
(define-shader-entity offhand-frame (weapon-slot)
  ((shown :initform NIL :accessor shown)))
(defmethod hud-shown-p ((frame offhand-frame))
  (and (call-next-method) (shown frame)))
(define-shader-entity inventory-cell (inventory-part weapon-slot) ())
(define-shader-entity inventory-icon (inventory-part item-icon) ())
(define-shader-entity inventory-text (inventory-part hud-text) ())
(define-shader-entity inventory-drag-icon (inventory-icon) ())

;; The tooltip: a box of lines by the pointer, over everything else in the panel.
(define-shader-entity tooltip-part ()
  ((shown :initform NIL :accessor shown)))

(defmethod hud-shown-p ((part tooltip-part))
  (and (call-next-method) (shown part)))

(define-shader-entity tooltip-back (tooltip-part inventory-back) ())
(define-shader-entity tooltip-text (tooltip-part inventory-text) ())

;; After WEAPON-SLOT's :BEFORE, so the cells stand out on it.
(defmethod render ((back inventory-back) (program shader-program))
  (setf (uniform program "back_color") *inventory-back-color*)
  (setf (uniform program "border_color") *inventory-border-color*)
  (call-next-method))

(defmethod late-rank ((part inventory-back)) 2)
(defmethod late-rank ((part inventory-cell)) 3)
(defmethod late-rank ((part inventory-icon)) 4)
(defmethod late-rank ((part inventory-text)) 5)
(defmethod late-rank ((part inventory-drag-icon)) 6)
(defmethod late-rank ((part tooltip-back)) 7)
(defmethod late-rank ((part tooltip-text)) 8)

(defclass item-cell ()
  ((slot :initarg :slot :reader cell-slot)
   (frame :initarg :frame :reader cell-frame)
   (icon :initarg :icon :reader cell-icon)
   (number :initarg :number :reader cell-number)
   (key :initarg :key :initform NIL :reader cell-key
        :documentation "A hotbar slot's key, or a bag cell's mark of the key bound to its stack.")
   (shown-count :initform NIL :accessor shown-count)
   (shown-key :initform NIL :accessor shown-key :documentation "The bag cell's key mark shown, or NIL."))
  (:documentation "A slot on screen: its frame, its stack's icon, the count over it and a hotbar
slot's key."))

(defun cell-parts (cell)
  ;; Back to front.
  (remove NIL (list (cell-frame cell) (cell-icon cell) (cell-number cell) (cell-key cell))))

;;; The tooltip's text: an item in detail, one string a line, its name first.

(defun range-text (range)
  "A magnitude range (LOW HIGH) as 6-10, or 4 when both are one."
  (destructuring-bind (low high) range
    (if (= low high) (format NIL "~d" low) (format NIL "~d-~d" low high))))

(defun effect-lines (effect)
  "What EFFECT does, as lines for a tooltip."
  (let* ((kind (effect-kind effect))
         (range (range-text (effect-magnitude effect)))
         (duration (effect-duration effect))
         (area (effect-area effect))
         (over-time (and (< 0 duration) (member kind '(:damage :heal))))
         (burst (if (< 0 area) (format NIL ", in ~,1f m" area) ""))
         (line (case kind
                 (:damage (format NIL "~:(~a~) damage ~a~:[~*~; a second for ~d s~]~a"
                                  (or (effect-element effect) :fire) range over-time duration burst))
                 (:heal (format NIL "Heals you ~a~:[~*~; a second for ~d s~]" range over-time duration))
                 (:knockback (format NIL "Knocks back at ~a m/s~a" range burst))
                 (:slow (format NIL "Slows ~a% for ~d s~a" range duration burst))
                 (:drain (format NIL "Drains ~a health, you gain half" range))
                 (:ward (format NIL "Wards off ~a damage for ~d s" range duration))
                 (:absorb (format NIL "Takes projectiles from in front, ~d% of their power as mana, a stamina a point"
                                  (second (effect-magnitude effect))))
                 (:whirl (format NIL "Whirls up all it catches, ~a a second" range))
                 (T (format NIL "~:(~a~) ~a" kind range)))))
    (append (list line)
            (case (and (eq kind :damage) (effect-element effect))
              (:frost (list (format NIL "  Chills: ~d% slower for ~d s" *frost-chill* (round *frost-chill-time*))))
              (:shock (list (format NIL "  Staggers: +~d% to the pain roll" *shock-pain-bonus*)))))))

(defun spell-cost-text (spell)
  "What a cast of SPELL takes, for the forge's readout and a tooltip: free, 28 SP a cast, 30 MP a second."
  (multiple-value-bind (resource amount) (spell-price spell)
    (let ((beam (eq (spell-delivery spell) :beam)))
      (case resource
        (:stamina (cond (beam (format NIL "~d SP a second" (beam-stamina-rate spell)))
                        ((absorb-spell-p spell) (format NIL "~d SP a second" amount))
                        (T (format NIL "~d SP a cast" amount))))
        (:mana (if beam (format NIL "~d MP a second" (beam-mana-rate spell)) (format NIL "~d MP a cast" amount)))
        (T (format NIL "Free, every ~,1f s" *free-cast-cooldown*))))))

(defun tier-line (spell)
  "Why SPELL isn't free, a line: Stamina: power 28 is over 14. NIL for a free one, whose cost says so."
  (let ((reason (tier-reason spell)))
    (when reason
      (format NIL "~:(~a~): ~a" (spell-tier spell) reason))))

(defun spell-lines (spell)
  "SPELL's delivery and what it takes, why it isn't free, then each effect, for a tooltip."
  (append (list (format NIL "~a, ~a"
                        (case (spell-delivery spell)
                          (:projectile "Projectile")
                          (:seeker "Seeker, homing on what you aim at")
                          (:beam "Beam held, to 12 m")
                          (:nova (format NIL "Nova, ~,1f m round you" (+ (spell-nova-radius spell) (spell-burst-radius spell))))
                          (:touch "Touch")
                          (:self (if (absorb-spell-p spell) "Held on yourself" "Cast on yourself"))
                          (:vortex (format NIL "Tornado for ~d s" (round (effect-duration (first (spell-effects spell))))))
                          (T (string-capitalize (spell-delivery spell))))
                        (spell-cost-text spell)))
          (let ((line (tier-line spell))) (when line (list line)))
          (when (and (forged-kinds-p spell) (overchargeable-p spell))
            (list (format NIL "Hold to overcharge: up to x~,1f for twice the cost; full, it breaks a guard"
                          (+ 1 *overcharge-strength*))))
          (mapcan #'effect-lines (spell-effects spell))))

(defun enchantment-lines (label spell)
  (if spell
      (cons (format NIL "~a: ~a, ~d MP a blow" label (spell-title spell) (enchant-cost spell))
            (mapcar (lambda (line) (concatenate 'string "  " line))
                    (mapcan #'effect-lines (spell-effects spell))))
      (list (format NIL "~a: plain (enchant it at an altar)" label))))

(defgeneric weapon-lines (weapon)
  (:documentation "What WEAPON's tooltip says it does, as lines: its blow, then its other actions.")
  (:method (weapon)
    (let ((blow (swing-blow weapon)))
      (list (format NIL "Damage ~a, reach ~,1f m" (range-text (blow-damage blow)) (blow-reach blow))
            (format NIL "~,2f s a swing" (blow-duration blow))
            "Right button: shield up, click to bash")))
  (:method ((weapon (eql :spear)))
    (let ((blow (swing-blow weapon)))
      (list (format NIL "Damage ~a, reach ~,1f m" (range-text (blow-damage blow)) (blow-reach blow))
            (format NIL "~,2f s a thrust" (blow-duration blow))
            "A thrust counters a leap or dive"
            "Right button: sweep, shove all near")))
  (:method ((weapon (eql :maul)))
    (let ((blow (swing-blow weapon)))
      (list (format NIL "Damage ~a to ~a, reach ~,1f m" (range-text (blow-damage blow)) (range-text (blow-full-damage blow))
                    (blow-reach blow))
            (format NIL "A blow ~d SP; hold to charge it" (round (blow-stamina blow)))
            "A full charge breaks a shield's guard"
            (format NIL "Right button: earthshake, ~d SP" (round (blow-stamina (second-blow weapon))))
            "  staggers all standing round you"))))

(defun stack-details (player stack)
  "STACK in detail, as lines for its tooltip: its name, then what it does."
  (let ((kind (first stack)))
    (cond ((eq kind :rune)
           (let ((spell (stack-spell stack)))
             (list* (spell-title spell) (spell-lines spell))))
          ((item-property kind :weapon)
           (let ((weapon (item-property kind :weapon)))
             (append
              (list (item-property kind :name))
              (weapon-lines weapon)
              (enchantment-lines "Enchanted" (stack-enchantment stack))
              (when (eq weapon :sword)
                (enchantment-lines "Shield" (getf (enchantments player) :shield))))))
          ((potion-p stack)
           (list (item-property kind :name)
                 (format NIL "Restores ~d ~(~a~)" (item-property kind :amount) (item-property kind :resource))
                 (format NIL "~d here, ~d in all, ~d to a stack" (second stack) (kind-total player kind)
                         (item-property kind :stack))
                 "Drag onto Q, then Q drinks one"))
          (T
           (list (item-property kind :name)
                 (item-property kind :about)
                 (format NIL "~d here, ~d in all" (second stack) (kind-total player kind)))))))

(defun stack-icon (stack)
  "The strip and frame of STACK's icon: a potion's in the item icons, a weapon's or a rune's in
the weapon icons (sword.lisp), a rune's by its spell's look."
  (let ((kind (first stack)))
    (cond ((eq kind :rune)
           (values (find-fx-animation 'weapon-icons) (spell-icon (stack-spell stack))))
          ((item-property kind :weapon)
           (values (find-fx-animation 'weapon-icons) (weapon-icon-frame (find-weapon (item-property kind :weapon)))))
          (T
           (values (find-fx-animation 'item-icons) (item-property kind :icon))))))

(defun show-stack-icon (icon stack)
  (multiple-value-bind (strip frame) (stack-icon stack)
    (swap-animation icon strip)
    (setf (frame icon) frame)))

(defclass inventory-view (entity listener)
  ((name :initform :inventory-view)
   (quick-cell :initform (make-instance 'item-cell :slot :quick
                                                   :frame (make-instance 'weapon-slot)
                                                   :icon (make-instance 'item-icon)
                                                   :number (make-hud-text))
               :reader quick-cell)
   (quick-key :initform (make-hud-text) :reader quick-key)
   (key-revision :initform NIL :accessor key-revision
                 :documentation "The *BINDINGS-REVISION* the keys shown were named for.")
   (hot-cells :initform (loop for i from 0 below *hotbar-size*
                              collect (make-instance 'item-cell :slot (nth i *hotbar-slots*)
                                                                :frame (make-instance 'weapon-slot)
                                                                :icon (make-instance 'item-icon :animation (find-fx-animation 'weapon-icons))
                                                                :number (make-hud-text)
                                                                :key (make-hud-text)))
              :reader hot-cells)
   (off-cells :initform (loop for i from 0 below *hotbar-size*
                              collect (make-instance 'item-cell :slot (nth i *offhand-slots*)
                                                                :frame (make-instance 'offhand-frame)
                                                                :icon (make-instance 'item-icon :animation (find-fx-animation 'weapon-icons))
                                                                :number (make-hud-text)))
              :reader off-cells)
   (back :initform (make-instance 'inventory-back) :reader panel-back)
   (title :initform (make-hud-text "Inventory" 'inventory-text) :reader panel-title-text)
   (hints :initform (loop repeat 3 collect (make-hud-text "" 'inventory-text)) :reader panel-hints
          :documentation "The hint's lines, up to three; the panel grows to hold those it has.")
   (shown-hint :initform :none :accessor shown-hint
               :documentation "The stack under the pointer the hint was last laid out for, NIL for none.")
   (cells :initform (loop for slot from 0 below *inventory-size*
                          collect (make-instance 'item-cell :slot slot
                                                            :frame (make-instance 'inventory-cell)
                                                            :icon (make-instance 'inventory-icon)
                                                            :number (make-hud-text "" 'inventory-text)
                                                            :key (make-hud-text "" 'inventory-text)))
          :reader bag-cells)
   (drag-icon :initform (make-instance 'inventory-drag-icon) :reader drag-icon)
   (tooltip-back :initform (make-instance 'tooltip-back) :reader tooltip-back)
   (tooltip-lines :initform (loop repeat *tooltip-lines* collect (make-hud-text "" 'tooltip-text))
                  :reader tooltip-lines)
   (shown-tooltip :initform NIL :accessor shown-tooltip
                  :documentation "The stack the tooltip describes, or NIL.")
   (dragging :initform NIL :accessor dragging :documentation "The slot a stack is being dragged from, or NIL.")
   (pointer :initform (vec2 -1 -1) :reader pointer :documentation "Where the mouse is, in HUD pixels.")))

(defvar *inventory-view* NIL "The current scene's INVENTORY-VIEW.")

(defun add-inventory-view (container)
  (let ((view (make-instance 'inventory-view)))
    (enter view container)
    (dolist (part (append (cell-parts (quick-cell view))
                          (mapcan #'cell-parts (hot-cells view))
                          (mapcan #'cell-parts (off-cells view))
                          (list (quick-key view) (panel-back view) (panel-title-text view)
                                (drag-icon view) (tooltip-back view))
                          (panel-hints view)
                          (tooltip-lines view)
                          (mapcan #'cell-parts (bag-cells view))))
      (enter part container))
    (setf *inventory-view* view)))

;;; Where things are, in HUD pixels.

(defun item-icon-size ()
  (* (hud-pixel-scale) (getf (animation-atlas (find-fx-animation 'item-icons)) :cell-width)))

(defun item-cell-size ()
  (+ (item-icon-size) (slot-padding) (slot-padding)))

(defun hotbar-rows ()
  (ceiling *hotbar-size* *hotbar-columns*))

(defun hot-position (index)
  "The corner of hotbar slot INDEX: in rows over the bars on the left, keys 1 to 5 on top."
  (let ((step (+ (item-cell-size) (slot-gap))))
    (multiple-value-bind (row column) (floor index *hotbar-columns*)
      (values (+ *hud-margin* (* column step))
              (+ (hud-top) (slot-gap) (* step (- (hotbar-rows) row 1)))))))

(defun offhand-icon-size ()
  "Pixels across an off hand's icon: the icons' own art pixels, at half the HUD's scale or more."
  (* (max 1 (floor (hud-pixel-scale) 2)) (getf (animation-atlas (find-fx-animation 'item-icons)) :cell-width)))

(defun offhand-cell-size ()
  (+ (offhand-icon-size) (* 2 (hud-pixel-scale))))

(defun offhand-position (index)
  "The corner of hotbar slot INDEX's off-hand cell: in its top-right corner."
  (multiple-value-bind (x y) (hot-position index)
    (let ((d (- (item-cell-size) (offhand-cell-size))))
      (values (+ x d) (+ y d)))))

(defun offhand-cell-shown-p (index open)
  "True if hotbar slot INDEX's off-hand cell shows: while it holds a rune, and, with the panel
OPEN, for every slot that holds one."
  (and *player*
       (eq :rune (first (nth index (hotbar *player*))))
       (or open (nth index (offhands *player*)))
       T))

(defun quick-position ()
  "The quickslot's corner: on the left, in a row of its own above the hotbar."
  (values *hud-margin*
          (+ (hud-top) (slot-gap) (* (hotbar-rows) (+ (item-cell-size) (slot-gap))))))

(defun inventory-rows ()
  (ceiling *inventory-size* *inventory-columns*))

(defparameter *hint-line-gap* 2 "Pixels between the panel hint's lines.")

(defun bag-panel-width ()
  (+ *inventory-padding* *inventory-padding*
     (- (* (+ (item-cell-size) (slot-gap)) *inventory-columns*) (slot-gap))))

(defun hotbar-keys-text ()
  "The hotbar's keys for a hint: \"1-9\" while they run 1 to 9, else each slot's."
  (let ((keys (loop for slot in *hotbar-slots* collect (action-key slot))))
    (if (equal keys '("1" "2" "3" "4" "5" "6" "7" "8" "9"))
        "1-9"
        (format NIL "~{~a~^ ~}" keys))))

(defvar *hint-lines* (cons NIL NIL)
  "The *BINDINGS-REVISION* and hint size HINT-LINES last wrapped the hint for, and its lines.")

(defun hint-lines ()
  "*INVENTORY-HINT* wrapped to the panel's width (WRAP-TEXT, hud.lisp): asked every tick, so
wrapped again only when the bindings or the panel's width change."
  (let ((key (+ *bindings-revision* (* 65536 (bag-panel-width)))))
    (unless (eql key (car *hint-lines*))
      (setf *hint-lines*
            (cons key (wrap-text (format NIL *inventory-hint* (hotbar-keys-text) (action-key :drink))
                                 (floor (- (bag-panel-width) *inventory-padding* *inventory-padding*) *glyph-width*)))))
    (cdr *hint-lines*)))

(defun panel-box ()
  "The panel's corner and size: on the left, right above the quickslot, tall enough for its
title, its cells and its hint's lines."
  (let* ((step (+ (item-cell-size) (slot-gap)))
         (pad *inventory-padding*)
         (lines (length (hint-lines)))
         (hint (+ pad (* lines *glyph-height*) (* (1- lines) *hint-line-gap*))))
    (values *hud-margin*
            (+ (nth-value 1 (quick-position)) step)
            (bag-panel-width)
            (+ pad pad *glyph-height* pad hint (- (* step (inventory-rows)) (slot-gap))))))

(defun bag-position (cell)
  "The corner of bag cell number CELL, counted across from the top left."
  (multiple-value-bind (x y w h) (panel-box)
    (declare (ignore w))
    (let ((step (+ (item-cell-size) (slot-gap)))
          (pad *inventory-padding*))
      (multiple-value-bind (row column) (floor cell *inventory-columns*)
        (values (+ x pad (* column step))
                (- (+ y h) pad *glyph-height* pad (item-cell-size) (* row step)))))))

(defun slot-position (slot)
  (let ((hot (hotbar-index slot)))
    (cond ((eq slot :quick) (quick-position))
          ((offhand-index slot) (offhand-position (offhand-index slot)))
          (hot (hot-position hot))
          (T (bag-position slot)))))

(defun slot-at (x y)
  "The slot on screen under pixel X, Y, or NIL."
  (let ((size (item-cell-size)))
    (flet ((in-p (slot)
             (multiple-value-bind (sx sy) (slot-position slot)
               (and (<= sx x) (< x (+ sx size)) (<= sy y) (< y (+ sy size))))))
      (or (when (in-p :quick) :quick)
          ;; The off hands lie over their slots' corners.
          (loop for slot in *offhand-slots*
                for index from 0
                when (and (offhand-cell-shown-p index T)
                          (multiple-value-bind (sx sy) (slot-position slot)
                            (let ((size (offhand-cell-size)))
                              (and (<= sx x) (< x (+ sx size)) (<= sy y) (< y (+ sy size))))))
                  return slot)
          (loop for slot in *hotbar-slots*
                when (in-p slot) return slot)
          (loop for cell from 0 below *inventory-size*
                when (in-p cell) return cell)))))

;;; Opening, closing, the keys and the mouse.

(defun open-inventory ()
  (when (and (eq *game-state* :playing) *player*)
    (play-sound :bag-open)
    (setf *game-state* :inventory)
    (release-mouse *player*)
    ;; No move has told it yet where the released pointer is.
    (when *inventory-view*
      (setf (shown-hint *inventory-view*) :none)
      (v<- (pointer *inventory-view*) (cursor-position *context*)))))

(defun close-inventory ()
  (when (eq *game-state* :inventory)
    ;; A drag in hand goes back where it was: its stack never left that slot.
    (when *inventory-view*
      (setf (dragging *inventory-view*) NIL))
    (play-sound :bag-close)
    (setf *game-state* :playing)
    (when *player* (capture-mouse *player*))))

(define-handler (inventory-view key-press) (key (repeat trial::repeat))
  (unless repeat
    (let ((action (input-action key :play)))
      (case *game-state*
        (:playing (case action
                    (:inventory (open-inventory))
                    (:drink (when *player*
                              (play-sound (if (use-quickslot *player*) :potion-drink :refused))))))
        (:inventory (when (eq action :inventory) (close-inventory)))))))

(define-handler (inventory-view mouse-scroll) (delta)
  ;; Wheel down (negative delta) for the next kind, up for the previous one.
  (when (and (eq *game-state* :playing) *player* (/= 0 delta))
    (when (cycle-quickslot *player* (if (< delta 0) 1 -1))
      (play-sound :item-drop))))

(define-handler (inventory-view mouse-move) (pos)
  (when (eq *game-state* :inventory)
    (v<- (pointer inventory-view) pos)))

(define-handler (inventory-view mouse-press) (button pos)
  (when (and (eq *game-state* :inventory) (eq button :left))
    (v<- (pointer inventory-view) pos)
    (let ((slot (slot-at (vx pos) (vy pos))))
      (when (and slot (slot-stack *player* slot))
        (play-sound :item-pick)
        (setf (dragging inventory-view) slot)))))

(define-handler (inventory-view mouse-release) (button pos)
  (when (and (eq button :left) (dragging inventory-view))
    (let ((from (dragging inventory-view))
          (to (slot-at (vx pos) (vy pos))))
      (setf (dragging inventory-view) NIL)
      (when (eq *game-state* :inventory)
        ;; Dropped on nothing, a bag stack goes back and a key or Q is unbound.
        (play-sound (if (or (eql from to) (move-stack *player* from to) (and (null to) (integerp from)))
                        :item-drop
                        :refused))))))

;;; Keeping it all in line with the player, a tick at a time.

(defparameter *tier-colors* '(:stamina (0.35 0.85 0.3) :mana (0.3 0.5 1.0))
  "The border a rune's cell takes by its spell's tier (SPELL-TIER, spells.lisp); a free one's is plain.")

(defun place-item-cell (cell x y frame-z icon-z number-z active &optional (lit T)
                                                                          (size (item-cell-size))
                                                                          (icon-size (item-icon-size))
                                                                          (pad (slot-padding)))
  "Lay CELL out at X, Y, SIZE pixels across: its frame lit up if ACTIVE, its icon dimmed unless LIT."
  (let* ((slot (cell-slot cell))
         (stack (slot-stack *player* slot))
         (count (second stack))
         (frame (cell-frame cell))
         (icon (cell-icon cell))
         (dragged (and *inventory-view* (eql (cell-slot cell) (dragging *inventory-view*))))
         (weapon (and stack (item-property (first stack) :weapon)))
         (enchantment (and weapon (weapon-enchantment *player* stack))))
    (setf (active frame) active
          (shown icon) (and stack T)
          ;; Dim while it's in hand, or remembered with none left.
          (active icon) (and stack (< 0 count) (not dragged) lit)
          (vx (scaling frame)) (float size 0f0)
          (vy (scaling frame)) (float size 0f0)
          (vx (scaling icon)) (float icon-size 0f0)
          (vy (scaling icon)) (float icon-size 0f0))
    (when stack
      (show-stack-icon icon stack))
    ;; An enchanted weapon's border takes its spell's colour, dim while mana can't pay a blow; a
    ;; rune's its tier's, unless it is free.
    (let ((tier (and stack (stack-spell stack) (getf *tier-colors* (spell-tier (stack-spell stack))))))
      (setf (enchanted frame) (and (or enchantment tier) T))
      (cond (enchantment
             (spell-tint enchantment (enchant-color frame)
                         (if (<= (enchant-cost enchantment) (mana *player*)) 1.0 *enchant-dim*)))
            (tier
             (destructuring-bind (r g b) tier
               (let ((c (enchant-color frame)))
                 (setf (vx c) r (vy c) g (vz c) b (vw c) 1.0))))))
    ;; Re-uploading text costs a buffer update, so only when the number changes. The quickslot
    ;; shows how many of its kind the bag holds, even one or none; a stack, more than one.
    (unless (eql count (shown-count cell))
      (setf (shown-count cell) count
            (text (cell-number cell)) (if (and count (or (eq slot :quick) (/= 1 count))) (princ-to-string count) "")))
    ;; A bag cell marks the key its stack is bound to, or whose off hand it is in (a ').
    (when (and (integerp slot) (cell-key cell))
      (let* ((key (and stack (stack-key *player* stack)))
             (off (and stack (null key) (offhand-key *player* stack)))
             (mark (or key (and off (+ 100 off)))))
        (unless (eql mark (shown-key cell))
          (setf (shown-key cell) mark
                (text (cell-key cell)) (cond (key (action-key (nth key *hotbar-slots*)))
                                             (off (format NIL "~a'" (action-key (nth off *hotbar-slots*))))
                                             (T ""))))))
    (place frame x y frame-z)
    (place icon (+ x pad) (+ y pad) icon-z)
    ;; The count in the bottom-right corner, right-aligned.
    (place (cell-number cell) (- (+ x size) pad (text-width (text (cell-number cell)))) (+ y 1) number-z)
    ;; A hotbar slot's key in the top-left corner, which the icons leave empty.
    (when (cell-key cell)
      (place (cell-key cell) (+ x pad) (- (+ y size) pad *glyph-height*) number-z))))

(defun update-panel-hint (view hovered)
  "The panel's hint, blank while the pointer is on a stack: its tooltip says what it is."
  (let ((stack (and hovered (slot-stack *player* hovered))))
    (unless (eq stack (shown-hint view))
      (setf (shown-hint view) stack)
      (let ((lines (and (null stack) (hint-lines))))
        (dolist (line (panel-hints view))
          (setf (text line) (or (pop lines) "")))))))

(defun update-tooltip (view hovered)
  "Show the tooltip of the stack in slot HOVERED by the pointer, or hide it for NIL. Its text
is re-uploaded only when the stack under the pointer changes."
  (let* ((stack (and hovered (slot-stack *player* hovered)))
         (stack (and stack (< 0 (second stack)) stack))
         (back (tooltip-back view))
         (lines (tooltip-lines view)))
    (unless (eq stack (shown-tooltip view))
      (setf (shown-tooltip view) stack)
      (let ((details (and stack (loop for line in (stack-details *player* stack)
                                      append (wrap-text line *tooltip-width*)))))
        (loop for line in lines
              for text = (pop details)
              do (setf (text line) (or text "")
                       (shown line) (and text T)))))
    (setf (shown back) (and stack T))
    (when stack
      (let* ((pad *tooltip-padding*)
             (step (+ *glyph-height* *tooltip-line-gap*))
             (count (count-if #'shown lines))
             (w (+ pad pad (loop for line in lines when (shown line) maximize (text-width (text line)))))
             (h (+ pad pad (- (* step count) *tooltip-line-gap*)))
             (px (floor (vx (pointer view))))
             (py (floor (vy (pointer view))))
             (sw (width *context*))
             (sh (height *context*))
             ;; Up and right of the pointer, clear of the slot it is on and the hotbar under it;
             ;; left of it where that runs off the screen, and down where the top does.
             (x (if (< (+ px *tooltip-offset* w) (- sw *hud-margin*))
                    (+ px *tooltip-offset*)
                    (max *hud-margin* (- px *tooltip-offset* w))))
             (top (min (- sh *hud-margin*) (+ py *tooltip-offset* h))))
        (setf (vx (scaling back)) (float w 0f0)
              (vy (scaling back)) (float h 0f0))
        (place back x (- top h) -0.02)
        (loop for line in lines
              for i from 0
              when (shown line)
                do (place line (+ x pad) (- top pad *glyph-height* (* i step)) -0.01))))))

(defun name-keys (view)
  "Name the quickslot's and the hotbar's keys as bound, and have the bag cells name theirs again."
  (setf (key-revision view) *bindings-revision*
        (text (quick-key view)) (action-key :drink))
  (dolist (cell (hot-cells view))
    (setf (text (cell-key cell)) (action-key (cell-slot cell))))
  (dolist (cell (bag-cells view))
    (setf (shown-key cell) :stale)))

(define-handler (inventory-view tick) ()
  (when *player*
    (unless (eql (key-revision inventory-view) *bindings-revision*)
      (name-keys inventory-view))
    (let* ((view inventory-view)
           (open (eq *game-state* :inventory))
           (x (vx (pointer view)))
           (y (vy (pointer view)))
           (hovered (and open (slot-at x y)))
           (from (dragging view)))
      ;; The frames light up under the pointer: where a click takes a stack or a drag drops it.
      (multiple-value-bind (qx qy) (quick-position)
        (place-item-cell (quick-cell view) qx qy -0.2 -0.1 -0.08 (eq hovered :quick))
        (place (quick-key view) (+ qx (slot-padding))
               (- (+ qy (item-cell-size)) (slot-padding) *glyph-height*) -0.08))
      ;; The slot asked for is framed in gold, and in play the others' icons are dimmed.
      (loop for cell in (hot-cells view)
            for index from 0
            for wanted = (eql index (wanted-slot *player*))
            do (multiple-value-bind (hx hy) (hot-position index)
                 (place-item-cell cell hx hy -0.2 -0.1 -0.08 (or wanted (eq hovered (cell-slot cell)))
                                  (or open wanted))))
      ;; Each off hand over its slot's corner, in front of it.
      (loop for cell in (off-cells view)
            for index from 0
            for shown = (offhand-cell-shown-p index open)
            do (setf (shown (cell-frame cell)) shown)
               (if shown
                   (multiple-value-bind (ox oy) (offhand-position index)
                     (place-item-cell cell ox oy -0.07 -0.06 -0.05 (eq hovered (cell-slot cell))
                                      (or open (eql index (wanted-slot *player*)))
                                      (offhand-cell-size) (offhand-icon-size) (hud-pixel-scale)))
                   (setf (shown (cell-icon cell)) NIL)))
      (when open
        (multiple-value-bind (px py pw ph) (panel-box)
          (let ((back (panel-back view))
                (pad *inventory-padding*))
            (setf (vx (scaling back)) (float pw 0f0)
                  (vy (scaling back)) (float ph 0f0))
            (place back px py -0.4)
            (place (panel-title-text view) (+ px pad) (- (+ py ph) pad *glyph-height*) -0.15)
            ;; The hint's lines from the bottom up.
            (let ((n (length (hint-lines))))
              (loop for line in (panel-hints view)
                    for i from 0 below n
                    do (place line (+ px pad) (+ py pad (* (- n 1 i) (+ *glyph-height* *hint-line-gap*))) -0.15)))))
        (dolist (cell (bag-cells view))
          (multiple-value-bind (cx cy) (bag-position (cell-slot cell))
            (place-item-cell cell cx cy -0.3 -0.2 -0.15 (eql hovered (cell-slot cell)))))
        (update-panel-hint view hovered)
        (let ((icon (drag-icon view))
              (stack (and from (slot-stack *player* from)))
              (size (item-icon-size)))
          (setf (shown icon) (and stack T)
                (active icon) T
                (vx (scaling icon)) (float size 0f0)
                (vy (scaling icon)) (float size 0f0))
          (when stack
            (show-stack-icon icon stack)
            ;; In front of everything, on whole pixels, the pointer at its middle.
            (place icon (- (floor x) (floor size 2)) (- (floor y) (floor size 2)) -0.05))))
      ;; No tooltip while a stack is in hand: the drag shows where it goes.
      (update-tooltip view (and open (not from) hovered)))))
