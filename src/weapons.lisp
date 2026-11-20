(in-package #:hexmaw)

;;; What a weapon is. A WEAPON-TEMPLATE is a kind of weapon (the sword, the spear, the maul, the
;;; casting hands): its name, which is also its item kind (inventory.lisp) and what the player's
;;; WEAPON holds while it is in hand, its icon, strip and sounds, and its moves. Each move is a
;;; BLOW: its frames, reach, damage and the rest, and, by its class, what it does when it lands.
;;; The left button's move is the template's SWING; the right button's is its ALTERNATE, pressed
;;; (the spear's sweep, the maul's earthshake), or, held, its GUARD's (the sword's shield, whose
;;; BASH a click lands while it is up).
;;;
;;; DEFINE-WEAPON and DEFINE-GUARD register them by name, replacing a definition already there in
;;; its place, so reloading a weapon's file updates the one in hand. Everything that holds a weapon
;;; (the player, a bag stack, a sprite) holds its name and looks the template up: FIND-WEAPON,
;;; FIND-GUARD.

(defclass blow ()
  ((name :initarg :name :initform NIL :reader blow-name
         :documentation "The blow's name: :SWORD, :SPEAR, :MAUL, :SHIELD (the bash), :HAFT (the sweep), :SHAKE.")
   (frame-times :initarg :frame-times :initform () :reader blow-frame-times
                :documentation "Seconds each frame of the blow shows. It is over after the last.")
   (hit-frame :initarg :hit-frame :initform 0 :reader blow-hit-frame
              :documentation "The frame the blow lands on, counted from 0.")
   (hit-time :initform 0.0 :reader blow-hit-time
             :documentation "Seconds from the blow's start to its hit frame.")
   (reach :initarg :reach :initform 0.0 :reader blow-reach
          :documentation "Metres from the player to the nearest edge of a body the blow reaches.")
   (arc :initarg :arc :initform 0.0 :reader blow-arc
        :documentation "Radians either side of the view the blow reaches.")
   (damage :initarg :damage :initform '(0 0) :reader blow-damage)
   (knockback :initarg :knockback :initform 0.0 :reader blow-knockback
              :documentation "Speed in m/s the blow slides a creature away.")
   (pain-bonus :initarg :pain-bonus :initform 0 :reader blow-pain-bonus
               :documentation "Percent the blow adds to the creature's PAIN-CHANCE.")
   (stamina :initarg :stamina :initform 0.0 :reader blow-stamina
            :documentation "Stamina the blow costs to start; with less, it doesn't.")
   (sound :initarg :sound :initform NIL :reader blow-sound :documentation "The clip played as it starts.")
   (speed :initarg :speed :initform NIL :reader blow-speed
          :documentation "Fraction of a walk the player keeps while it runs, with no run or jump, or NIL.")
   (verb :initarg :verb :initform "swing" :reader blow-verb :documentation "What its tooltip calls one: a swing.")
   (wall :initarg :wall :initform NIL :reader blow-wall
         :documentation "What it throws striking a wall when it finds no one (WALL-STRIKE, sword.lisp):
WALL-SPARKS' :SPARKS, :GRIT, :SPEED and :SPREAD before the surface's share, the :SOUND on stone or ice
and the :WOOD-SOUND on wood, and its feel, a :CAMERA kick, :HIT-STOP and a :RECOIL in m/s. A value
(:CHARGE least full) runs between the two by a charged blow's charge. NIL: it strikes no wall.")
   (tip :initarg :tip :initform NIL :reader blow-tip
        :documentation "(SPRITE X Y): the sprite (a key of *WEAPON-SPRITES*) and the art pixel of its
strip's cell, from the cell's top-left corner, where the weapon strikes in the blow's hit frame, which
WALL-STRIKE's line goes through; measured as that frame's topmost (or leading) opaque pixel."))
  (:documentation "One move of a weapon: its timing and numbers, and by its class what it does."))

(defmethod shared-initialize :after ((blow blow) slots &key)
  (declare (ignore slots))
  (setf (slot-value blow 'hit-time)
        (reduce #'+ (subseq (blow-frame-times blow) 0 (blow-hit-frame blow)))))

(defun blow-duration (blow)
  "Seconds the whole of BLOW takes."
  (reduce #'+ (blow-frame-times blow)))

(defclass thrust (blow)
  ((counter-damage :initarg :counter-damage :initform '(0 0) :reader blow-counter-damage
                   :documentation "Damage of a thrust that meets a charge.")
   (counter-sparks :initarg :counter-sparks :initform 0 :reader blow-counter-sparks
                   :documentation "Sparks the point throws as it meets a charge.")
   (counter-knockback :initarg :counter-knockback :initform 0.0 :reader blow-counter-knockback
                      :documentation "Speed in m/s a counter throws the creature back.")
   (counter-pain-bonus :initarg :counter-pain-bonus :initform 0 :reader blow-counter-pain-bonus
                       :documentation "Percent a counter adds to a boss's PAIN-CHANCE: anything else always flinches.")
   (jolt-time :initarg :jolt-time :initform 0.0 :reader blow-jolt-time
              :documentation "Seconds the weapon shows the jolt of a counter or a brace.")
   (brace-recoil :initarg :brace-recoil :initform 0.0 :reader blow-brace-recoil
                 :documentation "Speed in m/s the point set against a shield charge pushes the player back.")
   (brace-hit-stop :initarg :brace-hit-stop :initform 0.0 :reader blow-brace-hit-stop))
  (:documentation "A thrust: a blow that lands on a creature charging through the air is a counter, and
one set against a knight's shield charge stops it (spear.lisp)."))

(defclass charged-blow (blow)
  ((min-charge :initarg :min-charge :initform 0.0 :reader blow-min-charge
               :documentation "Seconds the weapon takes to rise: the least charge a blow has.")
   (full-charge :initarg :full-charge :initform 1.0 :reader blow-full-charge
                :documentation "Seconds from the press to a full charge.")
   (cry-delay :initarg :cry-delay :initform 0.0 :reader blow-cry-delay
              :documentation "Seconds the button must be held before the charge's cry: a click is shorter.")
   (charge-stamina :initarg :charge-stamina :initform 0.0 :reader blow-charge-stamina
                   :documentation "Stamina a second the charge costs while it grows past the least.")
   (charge-speed :initarg :charge-speed :initform 1.0 :reader blow-charge-speed
                 :documentation "Fraction of a walk the player keeps while charging, with no run or jump.")
   (raise-frame-time :initarg :raise-frame-time :initform 0.0 :reader blow-raise-frame-time
                     :documentation "Seconds the charge shows the raised frame before the wound-up one.")
   (tremble-rate :initarg :tremble-rate :initform 0.0 :reader blow-tremble-rate
                 :documentation "Times a second a full charge trembles from one frame to the other.")
   (full-damage :initarg :full-damage :initform '(0 0) :reader blow-full-damage
                :documentation "Damage of a full charge; between, by the charge. DAMAGE is the least's.")
   (full-knockback :initarg :full-knockback :initform 0.0 :reader blow-full-knockback)
   (full-pain-bonus :initarg :full-pain-bonus :initform 0 :reader blow-full-pain-bonus
                    :documentation "Percent a full charge adds to a boss's PAIN-CHANCE: anything else always flinches.")
   (hit-stop :initarg :hit-stop :initform '(0.0 0.0) :reader blow-hit-stop
             :documentation "Seconds the world freezes when the least charge lands, and a full one.")
   (sparks :initarg :sparks :initform '(0 0) :reader blow-sparks
           :documentation "Sparks the least charge's blow throws, and the full one's.")
   (camera-shake :initarg :camera-shake :initform '(0.0 0.0) :reader blow-camera-shake
                 :documentation "Strength of the camera shake (KICK-CAMERA, player.lisp) the least charge
gives, and an almost full one.")
   (full-camera-shake :initarg :full-camera-shake :initform 0.0 :reader blow-full-camera-shake)
   (gib-overkill :initarg :gib-overkill :initform 0.3 :reader blow-gib-overkill
                 :documentation "A killing blow tears a creature apart from this overkill, a fraction of
its most (its own if less); the undead's at any overkill."))
  (:documentation "A blow charged by holding the button (maul.lisp): it rises for MIN-CHARGE whatever the
button does, winds on for stamina to FULL-CHARGE while held, and comes down once let go, harder the
longer it was held."))

(defclass bash (blow) ()
  (:documentation "A guard's blow (the shield's): it glances off a shield that covers the creature, and
otherwise staggers only one winding up an attack and not poised (sword.lisp)."))

(defclass sweep (blow) ()
  (:documentation "A blow through every creature in its arc, by the bash's rules (spear.lisp)."))

(defclass earthshake (blow)
  ((reach-height :initarg :reach-height :initform 0.0 :reader blow-reach-height
                 :documentation "Metres from the player's floor within which a creature's feet must be to feel it.")
   (boss-pain-bonus :initarg :boss-pain-bonus :initform 0 :reader blow-boss-pain-bonus
                    :documentation "Percent it adds to a boss's PAIN-CHANCE: the rest always flinch.")
   (poise-time :initarg :poise-time :initform 0.0 :reader blow-poise-time
               :documentation "Seconds after it in which it, a bash or a sweep can't flinch a creature.")
   (hit-stop :initarg :hit-stop :initform 0.0 :reader blow-hit-stop)
   (camera-shake :initarg :camera-shake :initform 0.0 :reader blow-camera-shake)
   (dust-radius :initarg :dust-radius :initform 0.0 :reader blow-dust-radius
                :documentation "Metres out its ring of dust puffs is (KICK-DUST, ogre.lisp).")
   (dust-puffs :initarg :dust-puffs :initform 0 :reader blow-dust-puffs)
   (spark-reach :initarg :spark-reach :initform 0.0 :reader blow-spark-reach
                :documentation "Metres in front of the player's feet the weapon strikes sparks."))
  (:documentation "The weapon driven into the floor: everything standing within its REACH (all round)
flinches and is shoved out (maul.lisp)."))

(defclass guard-template ()
  ((name :initarg :name :reader guard-name :documentation "Its key: :SHIELD, also its enchantment's.")
   (title :initarg :title :initform "" :reader guard-title)
   (strip :initarg :strip :reader guard-strip :documentation "Its strip, a DEFINE-FX-ANIMATION name.")
   (raise-time :initarg :raise-time :initform 0.1 :reader guard-raise-time
               :documentation "Seconds to raise it to block, and again to lower it.")
   (raise-frames :initarg :raise-frames :initform 0 :reader guard-raise-frames
                 :documentation "Strip frames between the idle one and the held block.")
   (margin :initarg :margin :initform 0 :reader guard-margin
           :documentation "Art pixels the strip reaches past the screen's left and bottom edges:
make_shield.py's --margin. More than the sway, or the strip's edge shows.")
   (sound :initarg :sound :initform NIL :reader guard-sound :documentation "The clip played as it rises.")
   (forge-noun :initarg :forge-noun :initform "" :reader guard-forge-noun
               :documentation "The noun its enchantments are named with (DRAFT-NAME, forge.lisp).")
   (bash :initarg :bash :reader guard-bash :documentation "Its blow, a click while it is up."))
  (:documentation "An off-hand guard, the shield: held up with the right button, it blocks
(SHIELD-BLOCKS-P, player.lisp), and a click while it is up bashes with it."))

(defclass weapon-template ()
  ((name :initarg :name :reader weapon-name
         :documentation "Its key: the item kind (*ITEM-KINDS*), and the player's WEAPON while in hand.")
   (title :initarg :title :initform "" :reader weapon-title)
   (icon :initarg :icon :initform 0 :reader weapon-icon-frame :documentation "Frame of its icon in the weapon icons.")
   (strip :initarg :strip :initform NIL :reader weapon-strip
          :documentation "Its strip on screen, a DEFINE-FX-ANIMATION name.")
   (frames :initarg :frames :initform () :reader weapon-frames
           :documentation "Where its strip's parts start: :IDLE, the idle loop's frames from the
first; :SWING, the swing's first; :ALTERNATE, the alternate blow's first; :JOLT, the jolt's;
:CHARGE, the charge's first.")
   (aim :initarg :aim :initform NIL :reader weapon-aim-pixels
        :documentation "Art pixels left from the strip's screen corner to where it points, which goes
on the screen's middle; NIL keeps the strip against the bottom-right corner.")
   (sounds :initarg :sounds :initform () :reader weapon-sounds :documentation "Its clips: :DRAW as it comes up.")
   (loot :initarg :loot :initform NIL :reader weapon-loot-p :documentation "True if a level may hand it out.")
   (loot-strip :initarg :loot-strip :initform NIL :reader weapon-loot-strip
               :documentation "Its pickup's strip on the floor, a DEFINE-FX-ANIMATION name.")
   (forge-noun :initarg :forge-noun :initform "" :reader weapon-forge-noun
               :documentation "The noun its enchantments are named with (DRAFT-NAME, forge.lisp).")
   (swing :initarg :swing :initform NIL :reader weapon-swing :documentation "Its blow, the left button.")
   (alternate :initarg :alternate :initform NIL :reader weapon-alternate-blow
              :documentation "Its blow on a press of the right button, or NIL.")
   (guard :initarg :guard :initform NIL :reader weapon-guard-name
          :documentation "The name of its guard (DEFINE-GUARD), held up with the right button, or NIL."))
  (:documentation "A kind of weapon (DEFINE-WEAPON)."))

(defvar *weapon-templates* ()
  "Every weapon template (DEFINE-WEAPON), a plist by name in the order they were defined: a level's
loot draws from them in that order.")
(defvar *guards* () "Every guard (DEFINE-GUARD), a plist by name.")

(defun register-named (place name value)
  "PLACE, a plist, with NAME's value VALUE: in place if it has one, else at the end."
  (let ((cell (member name place)))
    (if cell
        (progn (setf (second cell) value) place)
        (append place (list name value)))))

(defun find-weapon (name &optional (errorp T))
  "The weapon template named NAME, or NIL (with ERRORP NIL, else an error) if there is none."
  (or (and name (getf *weapon-templates* name))
      (and errorp (error "No weapon ~s." name))))

(defun find-guard (name &optional (errorp T))
  (or (and name (getf *guards* name))
      (and errorp (error "No guard ~s." name))))

(defun weapon-guard (template)
  "TEMPLATE's guard, or NIL."
  (find-guard (weapon-guard-name template) NIL))

(defun weapon-frame-index (template part &optional (default 0))
  "Where TEMPLATE's strip's PART (a key of its FRAMES) starts."
  (getf (weapon-frames template) part default))

(defun make-blow (spec)
  "A blow from SPEC, (CLASS . INITARGS), or NIL."
  (and spec (apply #'make-instance (first spec) (rest spec))))

(defun weapon-templates ()
  "Every weapon template, in the order they were defined."
  (loop for (nil template) on *weapon-templates* by #'cddr collect template))

(defmacro define-weapon (name &body initargs)
  "Define the weapon template NAME (a keyword). INITARGS are WEAPON-TEMPLATE's, :CLASS its class
(WEAPON-TEMPLATE by default), and :SWING and :ALTERNATE each (BLOW-CLASS . BLOW-INITARGS). Nothing
is evaluated. Redefining one replaces it in its place."
  (let ((class (getf initargs :class 'weapon-template))
        (args (loop for (key value) on initargs by #'cddr
                    unless (member key '(:class :swing :alternate))
                      append (list key value))))
    `(setf *weapon-templates*
           (register-named *weapon-templates* ,name
                     (make-instance ',class :name ,name
                                            :swing (make-blow ',(getf initargs :swing))
                                            :alternate (make-blow ',(getf initargs :alternate))
                                            ,@(loop for (key value) on args by #'cddr
                                                    append (list key `',value)))))))

(defmacro define-guard (name &body initargs)
  "Define the guard NAME (a keyword). INITARGS are GUARD's, :BASH (BLOW-CLASS . BLOW-INITARGS).
Nothing is evaluated."
  (let ((args (loop for (key value) on initargs by #'cddr
                    unless (eq key :bash) append (list key value))))
    `(setf *guards*
           (register-named *guards* ,name
                     (make-instance 'guard-template :name ,name :bash (make-blow ',(getf initargs :bash))
                                           ,@(loop for (key value) on args by #'cddr
                                                   append (list key `',value)))))))

(defun swing-blow (weapon)
  "The swing of WEAPON, a template's name, or NIL."
  (let ((template (find-weapon weapon NIL)))
    (and template (weapon-swing template))))

(defun second-blow (weapon)
  "The blow WEAPON (a template's name) runs on the player's BASH-TIME: its alternate blow, or its
guard's bash; or NIL."
  (let ((template (find-weapon weapon NIL)))
    (and template
         (or (weapon-alternate-blow template)
             (let ((guard (weapon-guard template)))
               (and guard (guard-bash guard)))))))

(defun weapon-guard-of (weapon)
  "The guard of WEAPON, a template's name, or NIL."
  (let ((template (find-weapon weapon NIL)))
    (and template (weapon-guard template))))

;;; What the weapons do: generics a template, a blow or a guard answers, so a new weapon is a
;;; definition reusing these classes, and a new kind of move a blow subclass with its methods.

(defgeneric weapon-attack (template player)
  (:documentation "A click of the left button with TEMPLATE in hand and ready: start its swing, or with
its guard fully raised its guard's bash (sword.lisp); the hands cast (hands.lisp)."))

(defgeneric weapon-alternate (template player)
  (:documentation "A press of the right button with TEMPLATE in hand: start its alternate blow, if it has
one (a guard is held up instead, UPDATE-WEAPONS); the hands cast the off-hand rune."))

(defgeneric start-blow (blow player)
  (:documentation "Start BLOW: a swing on SWING-TIME, a charge on CHARGE-TIME (a CHARGED-BLOW), a second
blow on BASH-TIME, each as its class says, paying what it costs."))

(defgeneric swing-strike (player blow target)
  (:documentation "The swing BLOW lands on TARGET: hurt, shoved, and the enchantment of the weapon in
hand (sword.lisp). A thrust may counter a charge (spear.lisp), a charged blow runs by its charge
(maul.lisp)."))

(defgeneric swing-miss (player blow)
  (:documentation "The swing BLOW found no one living to land on: it strikes the wall in its reach
(WALL-STRIKE); a charged blow first pulps a corpse (maul.lisp)."))

(defgeneric bash-strike (player blow)
  (:documentation "The second blow BLOW (SECOND-BLOW) lands: the shield's bash, the spear's sweep, the
maul's earthshake."))

(defgeneric blow-lines (blow)
  (:documentation "What a weapon's tooltip says of BLOW as its swing, as lines (inventory.lisp)."))

(defgeneric second-blow-lines (thing)
  (:documentation "What a weapon's tooltip says of THING, its alternate blow or its guard: the right
button's, as lines."))

(defun heave-speed (player)
  "The fraction of a walk the blow PLAYER is charging or running keeps (an alternate's SPEED, a
charged blow's CHARGE-SPEED), or NIL if none slows the player: while it does, no run, no jump and
no stamina coming back."
  (let ((weapon (weapon player)))
    (cond ((bash-time player)
           (let ((blow (second-blow weapon)))
             (and blow (blow-speed blow))))
          ((charge-time player)
           (let ((blow (swing-blow weapon)))
             (and (typep blow 'charged-blow) (blow-charge-speed blow))))
          (T NIL))))

(defun heaving-p (player)
  "True while PLAYER charges a blow or runs one that slows them (HEAVE-SPEED): the maul's."
  (and (heave-speed player) T))

(defun heave-speed-scale (player)
  "Fraction of a walk PLAYER keeps for the blow they heave: 1 when none."
  (or (heave-speed player) 1.0))
