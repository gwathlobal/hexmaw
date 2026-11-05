(in-package #:hexmaw)

;;; Key bindings. Every key and mouse button the game reacts to is an action's input in
;;; *BINDINGS*, an alist from action to inputs that the Controls screen (settings.lisp)
;;; rebinds and the settings file keeps. An input is a key's keyword, as Trial names it
;;; (:W, :LEFT-SHIFT, :F5), or a mouse button's (:MOUSE-LEFT, :MOUSE-RIGHT, :MOUSE-MIDDLE,
;;; :MOUSE-4 ...). Handlers ask (INPUT-ACTION key :PLAY) what a press means, and the tick
;;; asks (HELD-P :FORWARD) what is held. Esc, the mouse wheel and the map's mouse drags stay
;;; fixed.
;;;
;;; What is held comes from *HELD*, kept by a Trial mapping function from every input event.
;;; Trial's own RETAINED keeps the arrow key :LEFT and the mouse button :LEFT under one
;;; name, so the game keeps its own.

(defparameter *actions*
  '((:forward "Move forward" (:play :map) (:w))
    (:back "Move back" (:play :map) (:s))
    (:strafe-left "Strafe left" (:play :map) (:a))
    (:strafe-right "Strafe right" (:play :map) (:d))
    (:run "Run" (:play) (:left-shift))
    (:jump "Jump, swim up" (:play) (:space))
    (:crouch "Crouch, dive" (:play) (:c :left-control))
    (:attack "Attack" (:play) (:mouse-left))
    (:block "Raise shield" (:play) (:mouse-right))
    (:interact "Talk, use" (:play) (:e))
    (:drink "Drink potion" (:play) (:q))
    (:inventory "Inventory" (:play) (:i))
    (:map "Automap" (:play :map) (:m))
    (:quicksave "Quicksave" (:global) (:f5))
    (:quickload "Quickload" (:global) (:f9))
    (:screenshot "Screenshot" (:global) (:f12))
    (:hot-1 "Hotbar 1" (:play) (:1))
    (:hot-2 "Hotbar 2" (:play) (:2))
    (:hot-3 "Hotbar 3" (:play) (:3))
    (:hot-4 "Hotbar 4" (:play) (:4))
    (:hot-5 "Hotbar 5" (:play) (:5))
    (:hot-6 "Hotbar 6" (:play) (:6))
    (:hot-7 "Hotbar 7" (:play) (:7))
    (:hot-8 "Hotbar 8" (:play) (:8))
    (:hot-9 "Hotbar 9" (:play) (:9))
    (:map-turn-left "Turn left" (:map) (:e))
    (:map-turn-right "Turn right" (:map) (:q))
    (:map-tilt-up "Tilt up" (:map) (:r))
    (:map-tilt-down "Tilt down" (:map) (:f))
    (:map-zoom-in "Zoom in" (:map) (:equal :kp-add))
    (:map-zoom-out "Zoom out" (:map) (:minus :kp-subtract))
    (:map-storey-up "Storey up" (:map) (:page-up))
    (:map-storey-down "Storey down" (:map) (:page-down))
    (:map-centre "Centre on player" (:map) (:space)))
  "Every action: its name, its label on the Controls screen, the contexts it acts in and its
default inputs. :PLAY is the game, :MAP the automap screen, :GLOBAL every state. Two actions
may share an input only if their contexts don't overlap (:GLOBAL overlaps everything).")

(defun default-bindings ()
  "A fresh binding alist with every action's default inputs."
  (loop for (action nil nil inputs) in *actions*
        collect (cons action (copy-list inputs))))

(defvar *bindings* (default-bindings)
  "The player's bindings: (ACTION . INPUTS) for every action in *ACTIONS*. A defvar, so a
reload keeps a rebinding; RESET-BINDINGS goes back to the defaults.")

(defvar *bindings-revision* 0
  "Bumped whenever *BINDINGS* changes, for what shows a key's name (the hotbar, the hints).")

(defvar *held* (make-hash-table :test 'eq)
  "The inputs held down now, each to T.")

(defvar *capturing* NIL
  "While the Controls screen waits for an input to bind (settings.lisp): the action, then
:DONE until every input is let go. INPUT-ACTION answers NIL meanwhile, so the input bound
does nothing else.")

(defun action-entry (action) (assoc action *actions*))
(defun action-label (action) (second (action-entry action)))
(defun action-contexts (action) (third (action-entry action)))
(defun action-inputs (action) (cdr (assoc action *bindings*)))

(defun input-held (input) (gethash input *held*))
(defun (setf input-held) (value input)
  "Hold INPUT down, or let it go: also how to drive the game from the REPL,
(setf (input-held :w) T)."
  (if value
      (setf (gethash input *held*) T)
      (remhash input *held*))
  value)

(defun held-p (action)
  "True if an input of ACTION is held down."
  (dolist (input (action-inputs action) NIL)
    (when (gethash input *held*)
      (return T))))

(defun contexts-overlap-p (a b)
  (or (member :global a) (member :global b)
      (intersection a b)))

(defun input-action (input &rest contexts)
  "The action INPUT is bound to among those acting in CONTEXTS, or NIL. :GLOBAL actions
answer only when CONTEXTS has :GLOBAL. NIL while the Controls screen captures an input."
  (unless *capturing*
    (loop for (action . inputs) in *bindings*
          when (and (member input inputs)
                    (intersection contexts (action-contexts action)))
            return action)))

(defun mouse-input (button)
  "The input a mouse BUTTON is bound as."
  (case button
    (:left :mouse-left)
    (:right :mouse-right)
    (:middle :mouse-middle)
    (T button)))

(defun note-input (event)
  "Keep *HELD* in line with EVENT."
  (typecase event
    (key-press (setf (gethash (key event) *held*) T))
    (key-release (remhash (key event) *held*))
    (mouse-press (setf (gethash (mouse-input (button event)) *held*) T))
    (mouse-release (remhash (mouse-input (button event)) *held*))
    (lose-focus (clrhash *held*))))

;; Trial's controller hands every event to each mapping function; registering by name
;; means a reload replaces it.
(setf (mapping-function 'hexmaw-bindings)
      (lambda (loop event)
        (declare (ignore loop))
        (note-input event)))

;;; Rebinding.

(defun rebind (action input)
  "Bind ACTION to INPUT alone. Any other action in an overlapping context loses INPUT;
those actions are returned."
  (let ((contexts (action-contexts action))
        (taken ()))
    (dolist (entry *bindings*)
      (let ((other (car entry)))
        (when (and (not (eq other action))
                   (member input (cdr entry))
                   (contexts-overlap-p contexts (action-contexts other)))
          (setf (cdr entry) (remove input (cdr entry)))
          (push other taken))))
    (let ((entry (assoc action *bindings*)))
      (if entry
          (setf (cdr entry) (list input))
          (setf *bindings* (append *bindings* (list (list action input))))))
    (incf *bindings-revision*)
    (nreverse taken)))

(defun reset-bindings ()
  (setf *bindings* (default-bindings))
  (incf *bindings-revision*))

(defun merge-bindings (saved)
  "Bindings from SAVED, a list of (ACTION . INPUTS) read from the settings file, for the
actions it names and *ACTIONS* knows, and the defaults for the rest."
  (loop for (action nil nil inputs) in *actions*
        for entry = (assoc action saved)
        collect (cons action (if (and entry (listp (cdr entry)) (every #'keywordp (cdr entry)))
                                 (copy-list (cdr entry))
                                 (copy-list inputs)))))

;;; Names.

(defparameter *input-names*
  '((:mouse-left . "Mouse left") (:mouse-right . "Mouse right") (:mouse-middle . "Mouse middle")
    (:mouse-4 . "Mouse 4") (:mouse-5 . "Mouse 5") (:mouse-6 . "Mouse 6") (:mouse-7 . "Mouse 7")
    (:mouse-8 . "Mouse 8")
    (:left-shift . "Left Shift") (:right-shift . "Right Shift")
    (:left-control . "Left Ctrl") (:right-control . "Right Ctrl")
    (:left-alt . "Left Alt") (:right-alt . "Right Alt")
    (:left-super . "Left Super") (:right-super . "Right Super")
    (:page-up . "Page Up") (:page-down . "Page Down")
    (:equal . "=") (:minus . "-") (:comma . ",") (:period . ".") (:slash . "/")
    (:semicolon . ";") (:apostrophe . "'") (:left-bracket . "[") (:right-bracket . "]")
    (:backslash . "\\") (:section . "`")
    (:kp-add . "Keypad +") (:kp-subtract . "Keypad -") (:kp-multiply . "Keypad *")
    (:kp-divide . "Keypad /") (:kp-decimal . "Keypad .") (:kp-enter . "Keypad Enter")
    (:kp-equal . "Keypad =")
    (:up . "Up") (:down . "Down") (:left . "Left") (:right . "Right")
    (:caps-lock . "Caps Lock") (:num-lock . "Num Lock") (:scroll-lock . "Scroll Lock")
    (:print-screen . "Print Screen"))
  "Names of the inputs a plain capitalised keyword doesn't name well.")

(defun key-label (input)
  "INPUT's name for the player: \"W\", \"Left Shift\", \"Mouse left\", \"Keypad 4\"."
  (or (cdr (assoc input *input-names*))
      (let ((name (string input)))
        (cond ((and (< 3 (length name)) (string= "KP-" name :end2 3))
               (format NIL "Keypad ~a" (subseq name 3)))
              ((= 1 (length name)) name)
              ((and (char= #\F (char name 0)) (every #'digit-char-p (subseq name 1))) name)
              (T (substitute #\Space #\- (string-capitalize name)))))))

(defun action-keys-label (action)
  "ACTION's inputs, \"C / Left Ctrl\", or \"-\" with none."
  (let ((inputs (action-inputs action)))
    (if inputs
        (format NIL "~{~a~^ / ~}" (mapcar #'key-label inputs))
        "-")))

(defparameter *input-short-names*
  '((:mouse-left . "LMB") (:mouse-right . "RMB") (:mouse-middle . "MMB")
    (:mouse-4 . "M4") (:mouse-5 . "M5") (:mouse-6 . "M6") (:mouse-7 . "M7") (:mouse-8 . "M8")
    (:left-shift . "LShift") (:right-shift . "RShift") (:left-control . "LCtrl")
    (:right-control . "RCtrl") (:left-alt . "LAlt") (:right-alt . "RAlt")
    (:page-up . "PgUp") (:page-down . "PgDn") (:backspace . "Bksp") (:insert . "Ins")
    (:delete . "Del") (:escape . "Esc") (:enter . "Enter"))
  "Shorter names for the HUD, where a key's name stands in a hotbar slot's corner or a hint.")

(defun key-short-label (input)
  (or (cdr (assoc input *input-short-names*))
      (let ((name (string input)))
        (if (and (< 3 (length name)) (string= "KP-" name :end2 3))
            (format NIL "Kp~a" (key-label (intern (subseq name 3) :keyword)))
            (key-label input)))))

(defun action-key (action)
  "The short name of ACTION's first input, for the HUD's hints and prompts, or \"?\" with none."
  (let ((input (first (action-inputs action))))
    (if input (key-short-label input) "?")))
