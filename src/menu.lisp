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
(defparameter *title-menu-top* 130
  "UI units from the top of the screen to the main menu, which keeps the dagger in the
lower middle of its splash clear.")

(defclass splash-backdrop (menu-backdrop)
  ((splash :initarg :splash :reader splash
           :documentation "The picture's path under data/splash/, without extension."))
  (:documentation "A MENU-BACKDROP that draws a picture over the whole screen, cropped to cover it."))

(defun splash-image (renderer name)
  ;; The renderer caches images by path, and the menu pass outlives scenes, so each
  ;; picture is read once. Nearest filtering keeps its pixels hard.
  (simple:request-image renderer (merge-pathnames (format NIL "data/splash/~a.png" name) (root))
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

(defclass menu-button (alloy:button) ())

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

;; The mouse moves the keyboard's selection too, so only one button is ever lit.
(defmethod (setf alloy:hovered-p) :after (value (button menu-button))
  (when (and value (not (alloy:focus button)))
    (setf (alloy:focus button) :weak)))

(defclass menu-panel (trial-alloy:panel) ()
  (:documentation "A full-screen menu: a title over a column of buttons."))

(defgeneric panel-title (panel))
(defgeneric panel-splash (panel)
  (:documentation "The splash picture behind PANEL (see SPLASH-BACKDROP), or NIL to dim the game.")
  (:method ((panel menu-panel)) NIL))
(defgeneric panel-top (panel)
  (:documentation "UI units from the top of the screen to PANEL's title, or T to centre it.")
  (:method ((panel menu-panel)) T))
(defgeneric panel-buttons (panel)
  (:documentation "A list of (LABEL ACTION): ACTION is a function name, called on the next tick after a click."))

(defmethod initialize-instance :after ((panel menu-panel) &key)
  (let* ((buttons (panel-buttons panel))
         (rows (1+ (length buttons)))
         (splash (panel-splash panel))
         (backdrop (apply #'make-instance (if splash 'splash-backdrop 'menu-backdrop)
                                  :col-sizes `(T ,*menu-width* T)
                                  :row-sizes `(,(panel-top panel) ,(+ (* rows *menu-row-height*) (* (1- rows) *menu-row-gap*)) T)
                                  (when splash (list :splash splash))))
         (column (make-instance 'alloy:vertical-linear-layout
                                :min-size (alloy:size *menu-width* *menu-row-height*)
                                :cell-margins (alloy:margins 0 (/ *menu-row-gap* 2))))
         (focus (make-instance 'alloy:focus-list)))
    (alloy:enter column backdrop :row 1 :col 1)
    (let ((title (panel-title panel)))
      (alloy:enter (alloy:represent title 'menu-title) column))
    (loop for (label action) in buttons
          ;; REPRESENT binds to the variable itself, so each button needs its own.
          do (let* ((label label)
                    (action action)
                    (button (alloy:represent label 'menu-button :layout-parent column :focus-parent focus)))
               (alloy:on (alloy:activate button) ()
                 (queue-menu-action action))))
    (alloy:finish-structure panel backdrop focus)))

(defclass main-menu (menu-panel) ())
(defmethod panel-title ((panel main-menu)) "HEXMAW")
(defmethod panel-splash ((panel main-menu)) "title")
(defmethod panel-top ((panel main-menu)) *title-menu-top*)
(defmethod panel-buttons ((panel main-menu))
  '(("Start game" start-game) ("Debug level" start-debug-level) ("Exit game" exit-game)))

(defclass loading-screen (menu-panel) ()
  (:documentation "Up while a level is built (:LOADING), which freezes the frame for a second or two."))
(defmethod panel-title ((panel loading-screen)) "Building the level...")
(defmethod panel-splash ((panel loading-screen)) "loading")
(defmethod panel-buttons ((panel loading-screen)) ())

(defclass pause-menu (menu-panel) ())
(defmethod panel-title ((panel pause-menu)) "Paused")
(defmethod panel-buttons ((panel pause-menu)) '(("Resume game" resume-game) ("Exit to main menu" exit-to-title)))

(defun state-menu ()
  "The panel class that belongs on screen in the current state, or NIL."
  (case *game-state*
    (:title 'main-menu)
    (:loading 'loading-screen)
    (:paused 'pause-menu)))

;;; Transitions.

(defun reset-player (player)
  "PLAYER back at the spawn point, looking north, with full health and mana."
  (respawn player)
  (setf (health player) *player-max-health*
        (pain player) 0.0
        (mana player) *max-mana*
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
    (setf *game-state* :playing)
    (when *player* (capture-mouse *player*))))

(defun show-title ()
  (setf *game-state* :title)
  (when *player* (release-mouse *player*)))

(defun reset-run ()
  "Put the level back as it was built, in place: the player at the spawn point, every
creature alive at home, no spells or effects in flight. Rebuilding the scene would do
the same but freezes for half a second (a forced full GC, reloaded resources)."
  (when *player* (reset-player *player*))
  (setf *hit-stop* 0.0)
  (clear-blood)
  (loop for creature across *creatures*
        do (revive creature)
           (update-creature-look creature))
  (when (and +main+ (scene +main+))
    (let ((leftovers ()))
      (for:for ((entity over (scene +main+)))
        ;; Projectiles and impacts; effect sprites drawn on the HUD stay.
        (when (and (typep entity 'fx-sprite) (not (typep entity '(or hud-element torch))))
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
  (when (eq key :escape)
    (case *game-state*
      (:playing (pause-game))
      (:paused (resume-game)))))

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
