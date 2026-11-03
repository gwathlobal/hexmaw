(in-package #:hexmaw)

;;; The inventory: items the player carries, a quickslot Q drinks from, and a panel to move them
;;; around in. A stack is a list (KIND COUNT); a slot, where one lives, is a cell's index in the
;;; player's INVENTORY or :QUICK. The quickslot is shown in play above the weapon slots; I opens
;;; the panel above it (*GAME-STATE* :INVENTORY), which freezes the world as the map does.
;;; Icons come from data/sprites/icons/items (tools/draw_item_icons.py).

(define-fx-animation item-icons "sprites/icons/items")

(defparameter *item-kinds*
  '((:health-potion :name "Health potion" :icon 0 :resource :health :amount 40 :stack 5)
    (:mana-potion :name "Mana potion" :icon 1 :resource :mana :amount 50 :stack 5))
  "What each kind of item is: its name, its frame in the icon strip, what it restores, and how
many fit in one stack. A pickup that gives one (*PICKUP-KINDS*) counts its :AMOUNT in a level's
budget, so keep the two the same.")

(defparameter *inventory-columns* 5 "Cells across the panel; *INVENTORY-SIZE* decides the rows.")
(defparameter *inventory-padding* 8 "Pixels between the panel's edge and what's in it.")
(defparameter *inventory-hint* "Drag a potion to the Q slot" "The panel's hint with no item under the pointer.")
(defparameter *inventory-back-color* (vec4 0.20 0.16 0.13 0.92))
(defparameter *inventory-border-color* (vec4 0.60 0.48 0.28 1))

(defun item-property (kind key)
  (getf (rest (or (assoc kind *item-kinds*) (error "No item kind ~s." kind))) key))

;;; The model.

(defun slot-stack (player slot)
  (if (eq slot :quick)
      (quickslot player)
      (nth slot (inventory player))))

(defun (setf slot-stack) (stack player slot)
  (if (eq slot :quick)
      (setf (quickslot player) stack)
      (setf (nth slot (inventory player)) stack)))

(defun stack-room (stack)
  (- (item-property (first stack) :stack) (second stack)))

(defun give-item (player kind)
  "Put one KIND in the first place with room: the quickslot if it holds that kind, a stack of it
in the bag, the quickslot if it is empty, so Q works straight away, then an empty cell. NIL if
there is none."
  (flet ((takes-p (stack)
           (and stack (eq kind (first stack)) (< 0 (stack-room stack)))))
    (let ((quick (quickslot player))
          (bag (inventory player)))
      (cond ((takes-p quick)
             (incf (second quick))
             T)
            ((find-if #'takes-p bag)
             (incf (second (find-if #'takes-p bag)))
             T)
            ((null quick)
             (setf (quickslot player) (list kind 1))
             T)
            ((position NIL bag)
             (setf (nth (position NIL bag) bag) (list kind 1))
             T)))))

(defun refill-quickslot (player)
  "The first stack in the bag of the kind the empty quickslot remembers moves into it."
  (let* ((bag (inventory player))
         (cell (position (first (quickslot player)) bag :key #'first)))
    (when cell
      (setf (quickslot player) (nth cell bag)
            (nth cell bag) NIL))))

(defun take-item (player)
  "Take one item from PLAYER, as a thief does (imp.lisp): from the quickslot if it holds any,
else from the first stack in the bag. Returns its kind, or NIL if there was nothing."
  (let ((quick (quickslot player))
        (cell (position-if (lambda (stack) (and stack (< 0 (second stack)))) (inventory player))))
    (cond ((and quick (< 0 (second quick)))
           (when (= 0 (decf (second quick)))
             (refill-quickslot player))
           (first quick))
          (cell
           (let ((stack (nth cell (inventory player))))
             (when (= 0 (decf (second stack)))
               (setf (nth cell (inventory player)) NIL))
             (first stack))))))

(defun use-quickslot (player)
  "Drink one from the quickslot. True if one was drunk; at full, none is."
  (let ((stack (quickslot player)))
    (when (and stack (< 0 (second stack)) (< 0 (health player))
               (restore-resource player (item-property (first stack) :resource)
                                 (item-property (first stack) :amount)))
      (when (= 0 (decf (second stack)))
        (refill-quickslot player))
      T)))

(defun move-stack (player from to)
  "Drop the stack in slot FROM onto slot TO: into an empty cell or over a remembered kind it
moves, onto its own kind it merges as far as the stack limit allows, and with another it swaps."
  (let ((source (slot-stack player from))
        (target (slot-stack player to)))
    (cond ((or (null source) (eql from to)))
          ;; The quickslot remembering a kind: nothing to move, it just forgets.
          ((= 0 (second source))
           (setf (slot-stack player from) NIL))
          ((or (null target) (= 0 (second target)))
           (setf (slot-stack player to) source
                 (slot-stack player from) NIL))
          ((eq (first source) (first target))
           (let ((moved (min (second source) (stack-room target))))
             (incf (second target) moved)
             (when (= 0 (decf (second source) moved))
               (setf (slot-stack player from) NIL))))
          (T
           (setf (slot-stack player to) source
                 (slot-stack player from) target)))))

;;; What's drawn. The quickslot is a weapon slot of its own; the panel's parts draw last and in
;;; order (LATE-RANK), so its see-through back never covers world drawn after it.

(define-shader-entity item-icon (weapon-icon)
  ((animation :initform (find-fx-animation 'item-icons))
   (shown :initform NIL :accessor shown)))

(defmethod hud-shown-p ((icon item-icon))
  (and (call-next-method) (shown icon)))

(define-shader-entity inventory-part () ())

(defmethod hud-shown-p ((part inventory-part))
  (and (call-next-method) (eq *game-state* :inventory)))

(define-shader-entity inventory-back (inventory-part weapon-slot) ())
(define-shader-entity inventory-cell (inventory-part weapon-slot) ())
(define-shader-entity inventory-icon (inventory-part item-icon) ())
(define-shader-entity inventory-text (inventory-part hud-text) ())
(define-shader-entity inventory-drag-icon (inventory-icon) ())

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

(defclass item-cell ()
  ((slot :initarg :slot :reader cell-slot)
   (frame :initarg :frame :reader cell-frame)
   (icon :initarg :icon :reader cell-icon)
   (number :initarg :number :reader cell-number)
   (shown-count :initform NIL :accessor shown-count))
  (:documentation "A slot on screen: its frame, its stack's icon and the count over it."))

(defun cell-parts (cell)
  ;; Back to front, as in the weapon bar.
  (list (cell-frame cell) (cell-icon cell) (cell-number cell)))

(defclass inventory-view (entity listener)
  ((name :initform :inventory-view)
   (quick-cell :initform (make-instance 'item-cell :slot :quick
                                                   :frame (make-instance 'weapon-slot)
                                                   :icon (make-instance 'item-icon)
                                                   :number (make-hud-text))
               :reader quick-cell)
   (quick-key :initform (make-hud-text "Q") :reader quick-key)
   (back :initform (make-instance 'inventory-back) :reader panel-back)
   (title :initform (make-hud-text "Inventory" 'inventory-text) :reader panel-title-text)
   (hint :initform (make-hud-text *inventory-hint* 'inventory-text) :reader panel-hint)
   (shown-hint :initform NIL :accessor shown-hint :documentation "The kind the hint names, or NIL.")
   (cells :initform (loop for slot from 0 below *inventory-size*
                          collect (make-instance 'item-cell :slot slot
                                                            :frame (make-instance 'inventory-cell)
                                                            :icon (make-instance 'inventory-icon)
                                                            :number (make-hud-text "" 'inventory-text)))
          :reader bag-cells)
   (drag-icon :initform (make-instance 'inventory-drag-icon) :reader drag-icon)
   (dragging :initform NIL :accessor dragging :documentation "The slot a stack is being dragged from, or NIL.")
   (pointer :initform (vec2 -1 -1) :reader pointer :documentation "Where the mouse is, in HUD pixels.")))

(defvar *inventory-view* NIL "The current scene's INVENTORY-VIEW.")

(defun add-inventory-view (container)
  (let ((view (make-instance 'inventory-view)))
    (enter view container)
    (dolist (part (append (cell-parts (quick-cell view))
                          (list (quick-key view) (panel-back view) (panel-title-text view) (panel-hint view)
                                (drag-icon view))
                          (mapcan #'cell-parts (bag-cells view))))
      (enter part container))
    (setf *inventory-view* view)))

;;; Where things are, in HUD pixels.

(defun item-icon-size ()
  (* *weapon-icon-scale* (getf (animation-atlas (find-fx-animation 'item-icons)) :cell-width)))

(defun item-cell-size ()
  (+ (item-icon-size) *weapon-slot-padding* *weapon-slot-padding*))

(defun quick-position ()
  "The quickslot's corner: on the left, in a row of its own above the weapon bar."
  (values *hud-margin*
          (+ (hud-top) *weapon-slot-gap* (item-cell-size) *weapon-slot-gap*)))

(defun inventory-rows ()
  (ceiling *inventory-size* *inventory-columns*))

(defun panel-box ()
  "The panel's corner and size: on the left, right above the quickslot."
  (let* ((step (+ (item-cell-size) *weapon-slot-gap*))
         (pad *inventory-padding*)
         (text (+ +glyph-height+ pad)))
    (values *hud-margin*
            (+ (nth-value 1 (quick-position)) step)
            (+ pad pad (- (* step *inventory-columns*) *weapon-slot-gap*))
            (+ pad pad text text (- (* step (inventory-rows)) *weapon-slot-gap*)))))

(defun bag-position (cell)
  "The corner of bag cell number CELL, counted across from the top left."
  (multiple-value-bind (x y w h) (panel-box)
    (declare (ignore w))
    (let ((step (+ (item-cell-size) *weapon-slot-gap*))
          (pad *inventory-padding*))
      (multiple-value-bind (row column) (floor cell *inventory-columns*)
        (values (+ x pad (* column step))
                (- (+ y h) pad +glyph-height+ pad (item-cell-size) (* row step)))))))

(defun slot-position (slot)
  (if (eq slot :quick) (quick-position) (bag-position slot)))

(defun slot-at (x y)
  "The slot on screen under pixel X, Y, or NIL."
  (let ((size (item-cell-size)))
    (flet ((in-p (slot)
             (multiple-value-bind (sx sy) (slot-position slot)
               (and (<= sx x) (< x (+ sx size)) (<= sy y) (< y (+ sy size))))))
      (or (when (in-p :quick) :quick)
          (loop for cell from 0 below *inventory-size*
                when (in-p cell) return cell)))))

;;; Opening, closing, the keys and the mouse.

(defun open-inventory ()
  (when (and (eq *game-state* :playing) *player*)
    (setf *game-state* :inventory)
    (release-mouse *player*)
    ;; No move has told it yet where the released pointer is.
    (when *inventory-view*
      (v<- (pointer *inventory-view*) (cursor-position *context*)))))

(defun close-inventory ()
  (when (eq *game-state* :inventory)
    ;; A drag in hand goes back where it was: its stack never left that slot.
    (when *inventory-view*
      (setf (dragging *inventory-view*) NIL))
    (setf *game-state* :playing)
    (when *player* (capture-mouse *player*))))

(define-handler (inventory-view key-press) (key)
  (case *game-state*
    (:playing (case key
                (:i (open-inventory))
                (:q (when *player* (use-quickslot *player*)))))
    (:inventory (when (eq key :i) (close-inventory)))))

(define-handler (inventory-view mouse-move) (pos)
  (when (eq *game-state* :inventory)
    (v<- (pointer inventory-view) pos)))

(define-handler (inventory-view mouse-press) (button pos)
  (when (and (eq *game-state* :inventory) (eq button :left))
    (v<- (pointer inventory-view) pos)
    (let ((slot (slot-at (vx pos) (vy pos))))
      (when (and slot (slot-stack *player* slot))
        (setf (dragging inventory-view) slot)))))

(define-handler (inventory-view mouse-release) (button pos)
  (when (and (eq button :left) (dragging inventory-view))
    (let ((from (dragging inventory-view))
          (to (slot-at (vx pos) (vy pos))))
      (setf (dragging inventory-view) NIL)
      (when (eq *game-state* :inventory)
        (cond (to
               (move-stack *player* from to))
              ;; Dropped on nothing a stack goes back, but a remembered kind is forgotten.
              ((eql 0 (second (slot-stack *player* from)))
               (setf (slot-stack *player* from) NIL)))))))

;;; Keeping it all in line with the player, a tick at a time.

(defun place-item-cell (cell x y frame-z icon-z number-z active)
  (let* ((stack (slot-stack *player* (cell-slot cell)))
         (count (second stack))
         (frame (cell-frame cell))
         (icon (cell-icon cell))
         (size (item-cell-size))
         (icon-size (item-icon-size))
         (pad *weapon-slot-padding*)
         (dragged (and *inventory-view* (eql (cell-slot cell) (dragging *inventory-view*)))))
    (setf (active frame) active
          (shown icon) (and stack T)
          ;; Dim while it's in hand, or remembered with none left.
          (active icon) (and stack (< 0 count) (not dragged))
          (vx (scaling frame)) (float size 0f0)
          (vy (scaling frame)) (float size 0f0)
          (vx (scaling icon)) (float icon-size 0f0)
          (vy (scaling icon)) (float icon-size 0f0))
    (when stack
      (setf (frame icon) (item-property (first stack) :icon)))
    ;; Re-uploading text costs a buffer update, so only when the number changes.
    (unless (eql count (shown-count cell))
      (setf (shown-count cell) count
            (text (cell-number cell)) (if (and count (/= 1 count)) (princ-to-string count) "")))
    (place frame x y frame-z)
    (place icon (+ x pad) (+ y pad) icon-z)
    ;; The count in the bottom-right corner, a digit wide.
    (place (cell-number cell) (- (+ x size) pad 9) (+ y 1) number-z)))

(defun update-panel-hint (view hovered)
  (let ((kind (first (and hovered (slot-stack *player* hovered)))))
    (unless (eq kind (shown-hint view))
      (setf (shown-hint view) kind
            (text (panel-hint view))
            (if kind
                (format NIL "~a: +~d ~(~a~)" (item-property kind :name) (item-property kind :amount)
                        (item-property kind :resource))
                *inventory-hint*)))))

(define-handler (inventory-view tick) ()
  (when *player*
    (let* ((view inventory-view)
           (open (eq *game-state* :inventory))
           (x (vx (pointer view)))
           (y (vy (pointer view)))
           (hovered (and open (slot-at x y)))
           (from (dragging view)))
      ;; The frames light up under the pointer: where a click takes a stack or a drag drops it.
      (multiple-value-bind (qx qy) (quick-position)
        (place-item-cell (quick-cell view) qx qy -0.2 -0.1 0 (eq hovered :quick))
        (place (quick-key view) (+ qx *weapon-slot-padding*)
               (- (+ qy (item-cell-size)) *weapon-slot-padding* +glyph-height+)))
      (when open
        (multiple-value-bind (px py pw ph) (panel-box)
          (let ((back (panel-back view))
                (pad *inventory-padding*))
            (setf (vx (scaling back)) (float pw 0f0)
                  (vy (scaling back)) (float ph 0f0))
            (place back px py -0.4)
            (place (panel-title-text view) (+ px pad) (- (+ py ph) pad +glyph-height+) -0.15)
            (place (panel-hint view) (+ px pad) (+ py pad) -0.15)))
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
            (setf (frame icon) (item-property (first stack) :icon))
            ;; In front of everything, on whole pixels, the pointer at its middle.
            (place icon (- (floor x) (floor size 2)) (- (floor y) (floor size 2)) -0.05)))))))
