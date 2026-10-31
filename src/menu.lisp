(in-package #:hexmaw)

;;; Menus: the main menu at startup and the pause menu on Esc, built with Alloy,
;;; Trial's UI toolkit. Alloy draws into its own pass (MENU-UI), which setup-scene
;;; blends over the game. *GAME-STATE* (creature.lisp) says which menu is up; the
;;; transition functions below change it and can be called from tools/hd, e.g.
;;; tools/hd '(game (start-game))'. The MENU-CONTROLLER keeps the shown panel in
;;; line with the state, so a scene reset brings the right menu back by itself.

(defparameter *menu-dim* 0.6 "Opacity of the dark backdrop behind a menu.")
(defparameter *menu-width* 320 "Width of the button column, in UI units (pixels at 1280×720).")
(defparameter *menu-row-height* 48)
(defparameter *menu-row-gap* 8)

(define-shader-pass menu-ui (trial-alloy:base-ui) ())

(defvar *menu-ui* NIL "The menu pass, reused by every scene; see PERSISTENT-MENU-UI.")

(defun persistent-menu-ui ()
  "The menu pass for a new scene. Alloy keeps its fonts on the pass, and a fresh pass
re-reads every font from disk (about 300 ms), so a scene rebuild reuses the old one,
cut loose from the old scene's passes."
  (let ((ui *menu-ui*))
    (cond (ui
           ;; A node lives in one container at a time; the old scene is being replaced.
           (when (container ui)
             (leave ui (container ui)))
           (org.shirakumo.flow:sever ui)
           ui)
          (T
           (setf *menu-ui* (make-instance 'menu-ui))))))

;;; Panels.

(defclass menu-backdrop (alloy:grid-layout) ()
  (:documentation "Fills the screen with a dark veil and holds the menu in its centre cell."))

(presentations:define-realization (presentations:default-look-and-feel menu-backdrop)
  ((:veil simple:rectangle)
   (alloy:margins)
   :pattern (chroma:color 0 0 0 *menu-dim*)))

;; The main menu and the loading screen cover the game with a splash picture
;; (data/splash/, from tools/make_splash.py) instead of the veil.
(defparameter *splash-dim* 0.6 "Opacity of the veil over a splash, so the menu stands out.")
(defparameter *title-menu-top* 110
  "UI units from the top of the screen to the main menu, which keeps the dagger in the
lower middle of its splash clear.")

(defclass splash-backdrop (menu-backdrop)
  ((splash :initarg :splash :reader splash
           :documentation "The picture's path under data/splash/, without extension."))
  (:documentation "A MENU-BACKDROP that draws a picture over the whole screen, cropped to cover it."))

(defun splash-image (renderer name)
  ;; The renderer caches images by path, and the menu pass outlives scenes, so each
  ;; picture is read once. Nearest filtering keeps its pixels hard.
  (simple:request-image renderer (data-path (format NIL "splash/~a.png" name))
                        :filtering :nearest))

(presentations:define-realization (presentations:default-look-and-feel splash-backdrop)
  ((:splash simple:icon)
   (alloy:margins)
   (splash-image alloy:renderer (splash alloy:renderable))
   :sizing :cover :halign :middle :valign :middle)
  ((:veil simple:rectangle)
   (alloy:margins)
   :pattern (chroma:color 0 0 0 *splash-dim*)))

(defparameter *menu-text-color* (chroma:color 0.92 0.88 0.78))
(defparameter *menu-button-color* (chroma:color 0.13 0.11 0.10 0.92))
(defparameter *menu-button-hover-color* (chroma:color 0.38 0.20 0.10 0.95))
(defparameter *menu-border-color* (chroma:color 0.60 0.48 0.28))

(defclass menu-title (alloy:label) ())

(presentations:define-realization (presentations:default-look-and-feel menu-title)
  ((:label simple:text)
   (alloy:margins)
   alloy:text
   :pattern *menu-text-color*
   :size (alloy:un 32)
   :halign :middle :valign :middle))

(presentations:define-update (presentations:default-look-and-feel menu-title)
  (:label
   :text alloy:text
   :pattern *menu-text-color*))

(defclass menu-focusable () ()
  (:documentation "A menu row: hovering it with the mouse gives it the keyboard focus."))

;; The mouse moves the keyboard's selection too, so only one row is ever lit.
(defmethod (setf alloy:hovered-p) :after (value (row menu-focusable))
  (when (and value (not (alloy:focus row)))
    (setf (alloy:focus row) :weak)))

(defclass menu-button (menu-focusable alloy:button) ())

(presentations:define-realization (presentations:default-look-and-feel menu-button)
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

(presentations:define-update (presentations:default-look-and-feel menu-button)
  (:background
   ;; Hovered with the mouse or selected with the keyboard.
   :pattern (if (or alloy:focus alloy:hovered-p) *menu-button-hover-color* *menu-button-color*))
  (:border
   :pattern *menu-border-color*
   :hidden-p NIL)
  (:label
   :text alloy:text
   :pattern *menu-text-color*))

(defparameter *menu-check-size* 20 "Side of a toggle's check box, in UI units.")

(defclass menu-toggle (menu-focusable alloy:labelled-switch) ()
  (:documentation "A checkbox row the size of a button: the box at the left, its label beside it."))

(presentations:define-realization (presentations:default-look-and-feel menu-toggle)
  ((:background simple:rectangle)
   (alloy:margins)
   :pattern *menu-button-color*)
  ((:border simple:rectangle)
   (alloy:margins)
   :line-width (alloy:un 2)
   :pattern *menu-border-color*)
  ;; Rows are *MENU-ROW-HEIGHT* tall, so the box is centred from the bottom edge.
  ((:box simple:rectangle)
   (alloy:extent (alloy:un 16) (alloy:un (/ (- *menu-row-height* *menu-check-size*) 2))
                 (alloy:un *menu-check-size*) (alloy:un *menu-check-size*))
   :line-width (alloy:un 2)
   :pattern *menu-border-color*)
  ((:check simple:rectangle)
   (alloy:extent (alloy:un 20) (alloy:un (+ 4 (/ (- *menu-row-height* *menu-check-size*) 2)))
                 (alloy:un (- *menu-check-size* 8)) (alloy:un (- *menu-check-size* 8)))
   :pattern *menu-text-color*)
  ((:label simple:text)
   (alloy:margins (+ 16 *menu-check-size* 12) 1 1 1)
   alloy:text
   :pattern *menu-text-color*
   :size (alloy:un 20)
   :halign :start :valign :middle))

(presentations:define-update (presentations:default-look-and-feel menu-toggle)
  (:background
   :pattern (if (or alloy:focus alloy:hovered-p) *menu-button-hover-color* *menu-button-color*))
  (:border
   :pattern *menu-border-color*
   :hidden-p NIL)
  (:box
   :pattern *menu-border-color*)
  (:check
   :hidden-p (not (alloy:active-p alloy:renderable))
   :pattern *menu-text-color*)
  (:label
   :text alloy:text
   :pattern *menu-text-color*))

;; A labelled switch sizes itself to its label; a toggle fills its row as a button does.
(defmethod presentations::compute-sizing-strategy ((renderer presentations:default-look-and-feel) (toggle menu-toggle))
  presentations::*fit-to-all-shapes*)

(defclass menu-panel (trial-alloy:panel) ()
  (:documentation "A full-screen menu: a title over a column of buttons."))

(defgeneric panel-title (panel))
(defgeneric panel-splash (panel)
  (:documentation "The splash picture behind PANEL (see SPLASH-BACKDROP), or NIL to dim the game.")
  (:method ((panel menu-panel)) NIL))
(defgeneric panel-top (panel)
  (:documentation "UI units from the top of the screen to PANEL's title, or T to centre it.")
  (:method ((panel menu-panel)) T))
(defgeneric panel-width (panel)
  (:documentation "Width of PANEL's button column, in UI units.")
  (:method ((panel menu-panel)) *menu-width*))
(defgeneric panel-buttons (panel)
  (:documentation "A list of rows, each (LABEL ACTION), a button: ACTION is a function name,
called on the next tick after a click; or (LABEL :TOGGLE VARIABLE), a checkbox that sets the
special variable VARIABLE to T or NIL as it is clicked."))

(defmethod initialize-instance :after ((panel menu-panel) &key)
  (let* ((buttons (panel-buttons panel))
         (rows (1+ (length buttons)))
         (splash (panel-splash panel))
         (backdrop (apply #'make-instance (if splash 'splash-backdrop 'menu-backdrop)
                                  :col-sizes `(T ,(panel-width panel) T)
                                  :row-sizes `(,(panel-top panel) ,(+ (* rows *menu-row-height*) (* (1- rows) *menu-row-gap*)) T)
                                  (when splash (list :splash splash))))
         (column (make-instance 'alloy:vertical-linear-layout
                                :min-size (alloy:size (panel-width panel) *menu-row-height*)
                                :cell-margins (alloy:margins 0 (/ *menu-row-gap* 2))))
         (focus (make-instance 'alloy:focus-list)))
    (alloy:enter column backdrop :row 1 :col 1)
    (let ((title (panel-title panel)))
      (alloy:enter (alloy:represent title 'menu-title) column))
    (loop for (label action variable) in buttons
          ;; REPRESENT binds to the variable itself, so each button needs its own.
          do (let ((label label)
                   (action action)
                   (variable variable))
               (if (eq action :toggle)
                   (alloy:represent-with 'menu-toggle
                                         (make-instance 'alloy:place-data
                                                        :getter (lambda () (symbol-value variable))
                                                        :setter (lambda (value) (setf (symbol-value variable) value)))
                                         :text label :layout-parent column :focus-parent focus)
                   (let ((button (alloy:represent label 'menu-button :layout-parent column :focus-parent focus)))
                     (alloy:on (alloy:activate button) ()
                       (queue-menu-action action))))))
    (alloy:finish-structure panel backdrop focus)))

(defparameter *save-slots* '(1 2 3 :quick) "The slots the menus offer (save.lisp), :QUICK for F5 and F9.")
(defvar *save-note* NIL "What the pause menu's title says after a save, or NIL.")
(defvar *pending-load* NIL
  "A save being loaded (save.lisp): BUILD-LEVEL builds its seed and SETUP-SCENE restores it.")

(defclass main-menu (menu-panel) ())
(defmethod panel-title ((panel main-menu)) "HEXMAW")
(defmethod panel-splash ((panel main-menu)) "title")
(defmethod panel-top ((panel main-menu)) *title-menu-top*)
(defmethod panel-buttons ((panel main-menu))
  `(("Start game" start-game) ("Load game" open-load-menu)
    ;; The test level is for development only.
    ,@(when *debug-version* '(("Debug level" start-debug-level)))
    ("Settings" open-settings) ("Exit game" exit-game)))

(defclass loading-screen (menu-panel) ()
  (:documentation "Up while a level is built (:LOADING), which freezes the frame for a second or two."))
(defmethod panel-title ((panel loading-screen)) "Building the level...")
(defmethod panel-splash ((panel loading-screen)) "loading")
(defmethod panel-buttons ((panel loading-screen)) ())

(defclass pause-menu (menu-panel) ())
;; After a save, the title says where it went (*SAVE-NOTE*, save.lisp).
(defmethod panel-title ((panel pause-menu)) (or *save-note* "Paused"))
(defmethod panel-buttons ((panel pause-menu))
  `(("Resume game" resume-game)
    ;; Only a generated level can be saved.
    ,@(when (eq *level* :generated) '(("Save game" open-save-menu)))
    ("Load game" open-load-menu) ("Settings" open-settings) ("Exit to main menu" exit-to-title)))

(defvar *settings-open* NIL
  "True while the settings panel covers the main or pause menu, which Back returns to.")

(defclass settings-menu (menu-panel) ())
(defmethod panel-title ((panel settings-menu)) "Settings")
;; Over the main menu it keeps the main menu's picture, rather than showing the level.
(defmethod panel-splash ((panel settings-menu)) (when (eq *game-state* :title) "title"))
(defmethod panel-top ((panel settings-menu)) (if (eq *game-state* :title) *title-menu-top* T))
(defmethod panel-buttons ((panel settings-menu))
  `(("Show FPS" :toggle *show-fps*)
    ,@(when *debug-version* '(("Debug minimap" :toggle *map-debug*)))
    ("Back" close-settings)))

(defvar *slot-menu* NIL
  "While the save or load panel covers the main or pause menu, which: :SAVE or :LOAD.")

(defclass slot-menu (menu-panel) ()
  (:documentation "A row per save slot (save.lisp), labelled with what it holds, then Back."))
;; Over the main menu it keeps the main menu's picture, as settings does.
(defmethod panel-splash ((panel slot-menu)) (when (eq *game-state* :title) "title"))
(defmethod panel-top ((panel slot-menu)) (if (eq *game-state* :title) *title-menu-top* T))
;; Wide enough for a slot's label.
(defmethod panel-width ((panel slot-menu)) 440)

(defclass save-menu (slot-menu) ())
(defmethod panel-title ((panel save-menu)) "Save game")
(defmethod panel-buttons ((panel save-menu))
  (append (loop for slot in *save-slots*
                collect (let ((slot slot))
                          (list (slot-info slot) (lambda () (save-to-slot slot)))))
          '(("Back" close-slot-menu))))

(defclass load-menu (slot-menu) ())
(defmethod panel-title ((panel load-menu)) "Load game")
(defmethod panel-buttons ((panel load-menu))
  (append (loop for slot in *save-slots*
                collect (let ((slot slot))
                          (list (slot-info slot) (lambda () (when (slot-used-p slot) (load-game slot))))))
          '(("Back" close-slot-menu))))

(defun state-menu ()
  "The panel class that belongs on screen in the current state, or NIL."
  (case *game-state*
    (:title (cond (*settings-open* 'settings-menu)
                  ((eq *slot-menu* :load) 'load-menu)
                  (T 'main-menu)))
    (:loading 'loading-screen)
    (:paused (cond (*settings-open* 'settings-menu)
                   ((eq *slot-menu* :save) 'save-menu)
                   ((eq *slot-menu* :load) 'load-menu)
                   (T 'pause-menu)))))

;;; Transitions.

(defun reset-player (player)
  "PLAYER back at the spawn point, looking north, with full health and mana."
  (respawn player)
  (setf (health player) *player-max-health*
        (pain player) 0.0
        (restore-flash player) 0.0
        (mana player) *max-mana*
        (breath player) *breath-time*
        (drown-timer player) 0.0
        (climbing player) NIL
        (cast-timer player) 0.0
        ;; No cast in progress, or its bolt would leave at the start of the next game.
        (cast-time player) NIL
        (pending-spell player) NIL
        (eye player) *eye-height*)
  (let ((rot (rotation player))) (setf (vx rot) 0f0 (vy rot) 0f0 (vz rot) 0f0))
  (place-camera player))

(defvar *new-run* NIL
  "True while the scene is rebuilt for a new run: SETUP-SCENE then puts the new player at
the spawn point, fresh, instead of where the old one stood.")

(defparameter *loading-frames* 3
  "Ticks the loading screen is up before the level is built, so it is on screen while
the build holds the frame.")

(defvar *loading-countdown* NIL "Ticks left before START-LEVEL's rebuild, or NIL.")

(defun start-level (level)
  "Leave the main menu for a new run on LEVEL (see *LEVEL*): put the loading screen up,
then rebuild the scene with a fresh player at its spawn point. SETUP-SCENE starts play."
  (setf *level* level
        *settings-open* NIL
        *slot-menu* NIL
        *pending-load* NIL
        *new-run* T
        *game-state* :loading
        *loading-countdown* *loading-frames*))

(defun start-game ()
  "Start a run on a newly generated level (a new seed unless *LEVEL-SEED* is set)."
  (start-level :generated))

(defun start-debug-level ()
  "Start a run on the greybox test level, where the creatures in development live."
  (start-level :test))

(defun pause-game ()
  (when (eq *game-state* :playing)
    (setf *game-state* :paused)
    (when *player* (release-mouse *player*))))

(defun resume-game ()
  (when (eq *game-state* :paused)
    (setf *game-state* :playing
          *save-note* NIL)
    (when *player* (capture-mouse *player*))))

(defun show-title ()
  (setf *game-state* :title
        *settings-open* NIL
        *slot-menu* NIL
        *save-note* NIL)
  (when *player* (release-mouse *player*)))

(defun open-settings ()
  (when (member *game-state* '(:title :paused))
    (setf *settings-open* T)))

(defun close-settings ()
  (setf *settings-open* NIL))

(defun open-save-menu ()
  (when (eq *game-state* :paused)
    (setf *slot-menu* :save)))

(defun open-load-menu ()
  (when (member *game-state* '(:title :paused))
    (setf *slot-menu* :load)))

(defun close-slot-menu ()
  (setf *slot-menu* NIL))

(defun save-to-slot (slot)
  "The save panel's action: save, then back to the pause menu, which says where it went."
  (save-game slot)
  (close-slot-menu))

(defun quicksave ()
  (when (member *game-state* '(:playing :paused))
    (save-game :quick)))

(defun quickload ()
  (when (and (member *game-state* '(:title :playing :paused)) (slot-used-p :quick))
    (load-game :quick)))

(defun reset-run ()
  "Put the level back as it was built, in place: the player at the spawn point, every
creature alive at home, no spells or effects in flight. Rebuilding the scene would do
the same but freezes for half a second (a forced full GC, reloaded resources)."
  (when *player* (reset-player *player*))
  (setf *hit-stop* 0.0)
  (clear-blood)
  ;; A new run explores the level afresh.
  (clear-map-reveals)
  (restore-pickups)
  ;; What came into the level mid-game (raised skeletons) goes; the rest live again.
  (let ((j 0))
    (loop for creature across *creatures*
          do (cond ((summoned creature) (despawn creature))
                   (T (setf (aref *creatures* j) creature) (incf j))))
    (setf (fill-pointer *creatures*) j))
  (loop for creature across *creatures*
        do (revive creature)
           (update-creature-look creature))
  (when (and +main+ (scene +main+))
    (let ((leftovers ()))
      (for:for ((entity over (scene +main+)))
        ;; Projectiles and impacts; effect sprites drawn on the HUD stay.
        (when (and (typep entity 'fx-sprite) (not (typep entity '(or hud-element torch pickup))))
          (push entity leftovers)))
      (mapc #'despawn leftovers))))

(defun exit-to-title ()
  "Abandon the run: back to the main menu, the level reset as at launch."
  (reset-run)
  (show-title))

(defun exit-game ()
  (quit *context*))

;;; The controller: Esc, deferred button actions, and the shown panel.

(defvar *menu-action* NIL "A transition clicked in a menu, run on the next tick.")

(defun queue-menu-action (action)
  ;; Run later rather than inside Alloy's click handling: the same mouse event
  ;; still goes to the player after the UI, and must not see the game already
  ;; resumed (it would fire a bolt).
  (setf *menu-action* action))

(defclass menu-controller (entity listener)
  ((name :initform :menu-controller)
   (fresh :initform T :accessor fresh
          :documentation "True until the first tick. The menu pass outlives scenes, so a new
scene's controller rebuilds whatever panel it finds, picking up changed panel code.")))

(define-handler (menu-controller key-press) (key)
  (case key
    (:escape
     (cond (*settings-open* (close-settings))
           (*slot-menu* (close-slot-menu))
           ((eq *game-state* :map) (close-map))
           ((eq *game-state* :playing) (pause-game))
           ((eq *game-state* :paused) (resume-game))))
    (:f5 (queue-menu-action 'quicksave))
    (:f9 (queue-menu-action 'quickload))))

(define-handler (menu-controller tick) ()
  (let ((action *menu-action*))
    (when action
      (setf *menu-action* NIL)
      (funcall action)))
  (when *loading-countdown*
    (when (<= (decf *loading-countdown*) 0)
      (setf *loading-countdown* NIL)
      (maybe-reload-scene)))
  (when (fresh menu-controller)
    (setf (fresh menu-controller) NIL)
    (trial-alloy:hide-panel 'menu-panel))
  (let ((wanted (state-menu))
        (shown (trial-alloy:find-panel 'menu-panel)))
    (unless (and shown (eq (type-of shown) wanted))
      (when shown (trial-alloy:hide-panel 'menu-panel))
      (when wanted (trial:show (make-instance wanted))))))
