(in-package #:hexmaw)

;;; The spellforge: at an altar (ADD-ALTAR, pickups.lisp; the town's, or a level's altar
;;; room) the player makes spells out of the effects they know (glyphs, pickups.lisp) and
;;; binds each to one of the casting hands' slots, the spellbook, or to a weapon, whose
;;; blows then carry it (ENCHANT-STRIKE, sword.lisp). It works on a draft: a delivery and up
;;; to *MAX-SPELL-EFFECTS* effects, each a kind, an element for damage, and the dials the
;;; kind has (*EFFECT-KINDS*: magnitude, duration, area). The screen (FORGE-PANEL, an Alloy
;;; panel like the menus) shows the draft and changes it through the FORGE- commands, which
;;; also work from the REPL: (game (open-forge)), (forge-select :sword), (forge-add-effect).
;;; A change of what the screen shows bumps *FORGE-REVISION*, and the menu controller
;;; remakes the panel (PANEL-STALE-P); a slider only changes the draft and the readout.

(defparameter *altar-reach* 1.8 "Metres across from an altar's middle the player can use it from.")
(defparameter *altar-height* 1.3 "Metres up or down from an altar's top the player's feet may be.")
(defvar *forge-anywhere* NIL "True to open the forge anywhere with E, in a debug version.")

(defparameter *max-spell-effects* 3)
(defparameter *max-enchant-effects* 2)
(defparameter *max-enchant-cost* 6 "Most mana a blow of an enchanted weapon may cost.")
(defparameter *forge-weapons* '(:sword :spear :shield) "The weapons the forge can enchant.")
(defparameter *forge-elements* '(:fire :frost :shock))

(defun near-altar-p (player)
  (let ((feet (feet player)))
    (loop for top across *level-altars*
          thereis (and (< (abs (- (vy feet) (vy top))) *altar-height*)
                       (< (+ (expt (- (vx feet) (vx top)) 2) (expt (- (vz feet) (vz top)) 2))
                          (* *altar-reach* *altar-reach*))))))

(defun forge-allowed-p (player)
  (or (near-altar-p player)
      (and *debug-version* *forge-anywhere*)))

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
         :documentation "What it is for: a spellbook slot, 0 to *SPELLBOOK-SIZE* - 1, or a weapon.")
   (delivery :initarg :delivery :initform :projectile :accessor draft-delivery)
   (effects :initarg :effects :initform () :accessor draft-effects)))

(defparameter *magnitude-spread* 0.7 "A forged effect's least roll, against its most.")
(defparameter *new-effects*
  '((:damage 8 0) (:heal 15 0) (:knockback 4 0) (:slow 30 4) (:drain 6 0) (:ward 10 10))
  "(KIND MAGNITUDE DURATION) an effect starts at when added or turned to that kind.")

(defvar *forge-draft* NIL "The draft on the forge.")
(defvar *forge-revision* 0 "Bumped whenever the forge's screen should be made again.")
(defvar *forge-note* NIL "What the forge says under the cost: why it can't, or what it did.")

(defun weapon-sink-p (sink) (keywordp sink))

(defun sink-title (sink)
  (if (weapon-sink-p sink) (string-capitalize sink) (format NIL "Hands ~d" (1+ sink))))

(defun sink-spell (player sink)
  (if (weapon-sink-p sink)
      (getf (enchantments player) sink)
      (nth sink (spellbook player))))

(defun known-kinds (player)
  (loop for (kind) in *effect-kinds* when (member kind (known-effects player)) collect kind))

(defun known-elements (player)
  (remove-if-not (lambda (e) (member e (known-effects player))) *forge-elements*))

(defun area-known-p (player) (member :area (known-effects player)))

(defun self-kind-p (kind) (equal '(:self) (kind-property kind :targets)))

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
                                :delivery (if (and spell (member (spell-delivery spell) '(:projectile :touch :self)))
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
         (noun (cond ((eq (draft-sink draft) :sword) "Edge")
                     ((eq (draft-sink draft) :spear) "Point")
                     ((eq (draft-sink draft) :shield) "Bulwark")
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

(defun draft-problem (draft)
  "Why DRAFT can't be inscribed, as a sentence, or NIL."
  (let* ((effects (draft-effects draft))
         (strikes (some (lambda (e) (not (self-kind-p (draft-kind e)))) effects))
         (weapon (weapon-sink-p (draft-sink draft)))
         (spell (and effects (draft-spell draft))))
    (cond ((null effects) "Add an effect.")
          ((and weapon (< *max-enchant-effects* (length effects)))
           (format NIL "A weapon holds at most ~d effects." *max-enchant-effects*))
          ((and weapon (< *max-enchant-cost* (enchant-cost spell)))
           (format NIL "Too strong for a weapon: at most ~d mana a blow." *max-enchant-cost*))
          (weapon NIL)
          ((and (eq (draft-delivery draft) :self) strikes)
           "Cast on yourself, it strikes nothing: deliver it, or keep to self effects.")
          ((and (not (eq (draft-delivery draft) :self)) (not strikes))
           "Nothing in it strikes: cast it on yourself.")
          ((< *max-mana* (spell-cost spell))
           (format NIL "It costs more mana than you can hold (~d)." (floor *max-mana*))))))

(defun draft-cost-text (draft player)
  (if (null (draft-effects draft))
      ""
      (let ((spell (draft-spell draft)))
        (if (weapon-sink-p (draft-sink draft))
            (let ((cost (enchant-cost spell)))
              (format NIL "~d MP a blow, ~d blows on your ~d" cost (floor (mana player) cost) (floor (mana player))))
            (format NIL "~d MP a cast, you have ~d" (spell-cost spell) (floor (mana player)))))))

;;; Commands: each changes the draft or what the player holds, and says the screen is stale.

(defun forge-changed ()
  (incf *forge-revision*))

(defun forge-select (sink &optional (player *player*))
  "Put what SINK holds on the forge: a spellbook slot's spell, a weapon's enchantment."
  (let ((sink (if (weapon-sink-p sink) sink (max 0 (min sink (length (spellbook player)) (1- *spellbook-size*))))))
    (setf *forge-draft* (draft-from-spell (sink-spell player sink) sink)
          *forge-note* NIL)
    (dolist (e (draft-effects *forge-draft*)) (clamp-effect e player))
    (forge-changed)
    *forge-draft*))

(defun forge-add-effect (&optional (kind :damage) (player *player*))
  (let ((draft *forge-draft*))
    (when (< (length (draft-effects draft))
             (if (weapon-sink-p (draft-sink draft)) *max-enchant-effects* *max-spell-effects*))
      (setf (draft-effects draft)
            (append (draft-effects draft)
                    (list (clamp-effect (new-effect (if (member kind (known-kinds player)) kind :damage)) player))))
      (forge-changed))))

(defun forge-remove-effect (index)
  (setf (draft-effects *forge-draft*) (remove (nth index (draft-effects *forge-draft*)) (draft-effects *forge-draft*)))
  (forge-changed))

(defun next-in (list item)
  (or (second (member item list)) (first list)))

(defun forge-cycle-kind (index &optional (player *player*))
  (let* ((effect (nth index (draft-effects *forge-draft*)))
         (kind (next-in (known-kinds player) (draft-kind effect)))
         (fresh (new-effect kind)))
    (setf (draft-kind effect) kind
          (draft-magnitude effect) (draft-magnitude fresh)
          (draft-duration effect) (draft-duration fresh)
          (draft-element effect) (draft-element fresh))
    (clamp-effect effect player)
    (forge-changed)))

(defun forge-cycle-element (index &optional (player *player*))
  (let ((effect (nth index (draft-effects *forge-draft*))))
    (when (eq :damage (draft-kind effect))
      (setf (draft-element effect) (next-in (known-elements player) (draft-element effect)))
      (forge-changed))))

(defun forge-cycle-delivery ()
  (setf (draft-delivery *forge-draft*) (next-in '(:projectile :touch :self) (draft-delivery *forge-draft*)))
  (forge-changed))

(defun forge-inscribe (&optional (player *player*))
  "Bind the draft to its sink: write the spell into the spellbook slot, or enchant the weapon.
Returns the spell, or NIL (and *FORGE-NOTE* says why) if it can't be."
  (let* ((draft *forge-draft*)
         (problem (draft-problem draft))
         (sink (draft-sink draft)))
    (cond (problem
           (setf *forge-note* problem)
           (forge-changed)
           NIL)
          (T
           (let ((spell (draft-spell draft)))
             (if (weapon-sink-p sink)
                 (setf (getf (enchantments player) sink) spell)
                 (let ((book (spellbook player)))
                   (if (< sink (length book))
                       (setf (nth sink book) spell)
                       (setf (spellbook player) (append book (list spell))
                             (draft-sink draft) (1- (length (spellbook player)))))))
             (setf *forge-note* (format NIL "~a: ~a." (sink-title (draft-sink draft)) (spell-title spell)))
             (forge-changed)
             spell)))))

(defun forge-set-active (&optional (player *player*))
  (let ((sink (draft-sink *forge-draft*)))
    (when (and (not (weapon-sink-p sink)) (< sink (length (spellbook player))))
      (setf (active-spell player) sink
            *forge-note* (format NIL "The hands cast ~a." (spell-title (current-spell player))))
      (forge-changed))))

(defun forge-erase (&optional (player *player*))
  "Take the spell out of the draft's spellbook slot (the last one stays), or a weapon's enchantment."
  (let ((sink (draft-sink *forge-draft*)))
    (cond ((weapon-sink-p sink)
           (remf (enchantments player) sink)
           (setf *forge-note* (format NIL "~a: plain." (sink-title sink))))
          ((and (< sink (length (spellbook player))) (< 1 (length (spellbook player))))
           (setf (spellbook player) (remove (nth sink (spellbook player)) (spellbook player) :count 1)
                 (active-spell player) (min (active-spell player) (1- (length (spellbook player)))))
           (setf *forge-note* (format NIL "~a erased." (sink-title sink)))))
    (forge-select (if (weapon-sink-p sink) sink (min sink (1- (length (spellbook player))))) player)))

(defun open-forge ()
  (when (and (eq *game-state* :playing) *player*)
    (setf *game-state* :forge)
    (release-mouse *player*)
    (forge-select (if *forge-draft* (draft-sink *forge-draft*) (active-spell *player*)))))

(defun close-forge ()
  (when (eq *game-state* :forge)
    (setf *game-state* :playing)
    (when *player* (capture-mouse *player*))))

;;; The screen: what the player holds down the left, the draft on the right.

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

(defclass forge-panel (menu-panel)
  ((revision :initform *forge-revision* :reader panel-revision)
   (readout :initform (make-instance 'alloy:value-data :value "") :reader readout
            :documentation "The draft's name, its cost against the player's mana: a slider changes it.")
   (note :initform (make-instance 'alloy:value-data :value "") :reader note
         :documentation "*FORGE-NOTE*, or why the draft can't be inscribed as it stands.")))

(defmethod panel-title ((panel forge-panel)) "Spellforge")
(defmethod panel-buttons ((panel forge-panel)) ())
(defmethod panel-stale-p ((panel forge-panel))
  (/= (panel-revision panel) *forge-revision*))

(defun forge-readout-text ()
  (let ((draft *forge-draft*))
    (format NIL "~a~@[  -  ~a~]" (draft-name draft) (and *player* (draft-cost-text draft *player*)))))

(defun refresh-readout (panel)
  (setf (alloy:value (readout panel)) (forge-readout-text)
        (alloy:value (note panel)) (or *forge-note* (draft-problem *forge-draft*) "")))

(defun forge-row (parent sizes)
  "A row of cells SIZES wide in PARENT, a grid to enter widgets into by :COL."
  (let ((row (make-instance 'alloy:grid-layout :col-sizes sizes :row-sizes (list *forge-row-height*)
                                               :cell-margins (alloy:margins 3 0))))
    (alloy:enter row parent)
    row))

(defun forge-button (label action row col focus)
  "A button LABEL in ROW's cell COL that runs ACTION, a function, on the next tick."
  (let ((button (alloy:represent-with 'menu-button (make-instance 'alloy:value-data :value label)
                                      :focus-parent focus)))
    (alloy:enter button row :row 0 :col col)
    (alloy:on (alloy:activate button) ()
      (queue-menu-action action))
    button))

(defun forge-text (text row col &optional (value ""))
  (alloy:enter (alloy:represent-with 'menu-stat (make-instance 'alloy:value-data :value text) :value value)
               row :row 0 :col col))

(defun forge-dial (panel label getter setter range step describe row col focus)
  (let ((slider (alloy:represent-with 'forge-slider
                                      (make-instance 'alloy:place-data
                                                     :getter getter
                                                     :setter (lambda (value)
                                                               (funcall setter value)
                                                               (setf *forge-note* NIL)
                                                               (refresh-readout panel)))
                                      :text label :range range :step step :grid step
                                      :describe describe :focus-parent focus)))
    (alloy:enter slider row :row 0 :col col)
    slider))

(defun build-effect-rows (panel column effect index focus player)
  (let ((kind (draft-kind effect))
        (row (forge-row column '(250 250 T))))
    (forge-button (format NIL "Effect: ~:(~a~)" kind) (lambda () (forge-cycle-kind index)) row 0 focus)
    (if (eq kind :damage)
        (forge-button (format NIL "Element: ~:(~a~)" (draft-element effect)) (lambda () (forge-cycle-element index)) row 1 focus)
        (forge-text (if (self-kind-p kind) "On you" "On what it strikes") row 1))
    (forge-button "Remove" (lambda () (forge-remove-effect index)) row 2 focus)
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
                  dials 0 focus)
      (if (eq :instant (kind-property kind :timing))
          (forge-text "Instant" dials 1)
          (forge-dial panel "Time"
                      (lambda () (draft-duration effect))
                      (lambda (v) (setf (draft-duration effect) (round v)))
                      (cons (if (eq :status (kind-property kind :timing)) 1 0) (kind-property kind :duration)) 1
                      (lambda (v) (if (< 0 (round v)) (format NIL "~d s" (round v)) "at once"))
                      dials 1 focus))
      (if (and (area-known-p player) (not (self-kind-p kind)) (< 0 (kind-property kind :area)))
          (forge-dial panel "Area"
                      (lambda () (draft-area effect))
                      (lambda (v) (setf (draft-area effect) (/ (round (* 2 v)) 2)))
                      (cons 0 (kind-property kind :area)) 0.5
                      (lambda (v) (if (< 0 v) (format NIL "~,1f m" (/ (round (* 2 v)) 2)) "one"))
                      dials 2 focus)
          (forge-text (if (self-kind-p kind) "" "No area") dials 2)))))

(defmethod build-panel ((panel forge-panel))
  (unless *forge-draft*
    (forge-select 0))
  (let* ((player *player*)
         (draft *forge-draft*)
         (sink (draft-sink draft))
         (weapon (weapon-sink-p sink))
         (step (+ *forge-row-height* *forge-gap*))
         (backdrop (make-instance 'menu-backdrop
                                  :col-sizes `(T ,*forge-left-width* 24 ,*forge-right-width* T)
                                  :row-sizes `(T ,(* 14 step) T)))
         (left (make-instance 'alloy:vertical-linear-layout
                              :min-size (alloy:size *forge-left-width* *forge-row-height*)
                              :cell-margins (alloy:margins 0 (/ *forge-gap* 2))))
         (right (make-instance 'alloy:vertical-linear-layout
                               :min-size (alloy:size *forge-right-width* *forge-row-height*)
                               :cell-margins (alloy:margins 0 (/ *forge-gap* 2))))
         (focus (make-instance 'alloy:focus-list)))
    (alloy:enter left backdrop :row 1 :col 1)
    (alloy:enter right backdrop :row 1 :col 3)
    ;; What the player holds: the spellbook's slots, one more while it has room, and the weapons.
    (alloy:enter (alloy:represent "Spellforge" 'menu-title) left)
    (loop for i from 0 below (min *spellbook-size* (1+ (length (spellbook player))))
          for spell = (nth i (spellbook player))
          do (let ((i i))
               (forge-button (format NIL "~:[  ~;> ~]~a: ~a~:[~; *~]" (eql i sink) (sink-title i)
                                     (if spell (spell-title spell) "empty") (and spell (= i (active-spell player))))
                             (lambda () (forge-select i)) (forge-row left '(T)) 0 focus)))
    (dolist (w *forge-weapons*)
      (let ((w w) (spell (getf (enchantments player) w)))
        (forge-button (format NIL "~:[  ~;> ~]~a: ~a" (eq w sink) (sink-title w) (if spell (spell-title spell) "plain"))
                      (lambda () (forge-select w)) (forge-row left '(T)) 0 focus)))
    (forge-text "Glyphs" (forge-row left '(T)) 0
                (format NIL "~d of ~d" (count-if (lambda (e) (not (member e *starting-effects*))) (known-effects player))
                        (length (glyph-kinds))))
    ;; The draft.
    (alloy:enter (alloy:represent-with 'menu-title (make-instance 'alloy:value-data :value (sink-title sink))) right)
    (if weapon
        (forge-text "Its blows carry it, for mana" (forge-row right '(T)) 0)
        (forge-button (format NIL "Delivery: ~:(~a~)" (draft-delivery draft)) 'forge-cycle-delivery
                      (forge-row right '(T)) 0 focus))
    (loop for effect in (draft-effects draft)
          for index from 0
          do (build-effect-rows panel right effect index focus player))
    (when (< (length (draft-effects draft)) (if weapon *max-enchant-effects* *max-spell-effects*))
      (forge-button "Add an effect" 'forge-add-effect (forge-row right '(T)) 0 focus))
    (alloy:enter (alloy:represent-with 'menu-stat (readout panel) :value "") (forge-row right '(T)) :row 0 :col 0)
    (alloy:enter (alloy:represent-with 'menu-stat (note panel) :value "") (forge-row right '(T)) :row 0 :col 0)
    (refresh-readout panel)
    (let ((row (forge-row right '(220 220 T))))
      (forge-button (if weapon "Enchant" "Inscribe") 'forge-inscribe row 0 focus)
      (if weapon
          (forge-button "Make it plain" 'forge-erase row 1 focus)
          (forge-button "Cast this one" 'forge-set-active row 1 focus))
      (forge-button "Leave" 'close-forge row 2 focus))
    (alloy:finish-structure panel backdrop focus)))
