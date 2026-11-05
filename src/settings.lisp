(in-package #:hexmaw)

;;; The player's settings: fullscreen, mouse sensitivity, the volumes, Show FPS and the key
;;; bindings (input.lisp), kept in one file beside the saves, and the Controls screen that
;;; rebinds the keys. Trial's own settings file is shared by every Trial game and lives
;;; elsewhere on Windows, so the game writes its own: SETTINGS-FILE, read by LAUNCH
;;; (main.lisp) before the window opens and written when Settings or Controls closes and
;;; after each rebinding.

(defvar *save-directory*)               ; save.lisp

;;; Fullscreen.

(defvar *fullscreen* NIL
  "Fullscreen at the monitor's own resolution, or else a *WINDOW-SIZE* window: Settings'
checkbox, kept in the settings file. HEXMAW_FULLSCREEN=1 turns it on at launch.")

(defparameter *window-size* '(1280 720) "The window's size when not fullscreen.")

(defun apply-fullscreen (&optional (context *context*))
  "Put the window in or out of fullscreen as *FULLSCREEN* says. Trial's GLFW backend does it
from the context's event queue, so any thread may ask."
  (when context
    (if *fullscreen*
        (show context :fullscreen T :mode T)
        (show context :fullscreen NIL :mode *window-size*))))

(defmethod setting-changed ((variable (eql '*fullscreen*)))
  (apply-fullscreen))

;; A panel laid out at one size doesn't lay itself out again at another (its rows come back
;; from fullscreen uneven), so a resize has the menu controller make it again.
(define-handler (menu-controller resize) ()
  (setf *menu-refresh* T))

;;; Mouse sensitivity.

(defvar *mouse-sensitivity-setting* 0.5
  "Settings' mouse sensitivity slider, 0 to 1: the middle turns the view *MOUSE-SENSITIVITY*
(player.lisp) a pixel, and each end *MOUSE-SENSITIVITY-SPAN* times slower or faster.")

(defparameter *mouse-sensitivity-span* 4.0
  "How many times slower or faster than the middle the slider's ends turn the view.")

(defun sensitivity-factor (&optional (setting *mouse-sensitivity-setting*))
  (expt *mouse-sensitivity-span* (- (* 2.0 setting) 1.0)))

(defun sensitivity-text (setting)
  "The slider's value as the player reads it: 1.00x at the middle."
  (format NIL "~,2fx" (sensitivity-factor setting)))

(defvar *sensitivity-cache* (vector NIL NIL 0.0)
  "The setting and base MOUSE-SENSITIVITY last worked out, and its answer: it is asked per
mouse event, and EXPT allocates.")

(defun mouse-sensitivity ()
  "Radians a pixel of mouse movement turns the view."
  (let ((cache *sensitivity-cache*))
    (unless (and (eql (svref cache 0) *mouse-sensitivity-setting*)
                 (eql (svref cache 1) *mouse-sensitivity*))
      (setf (svref cache 0) *mouse-sensitivity-setting*
            (svref cache 1) *mouse-sensitivity*
            (svref cache 2) (float (* *mouse-sensitivity* (sensitivity-factor)) 0f0)))
    (svref cache 2)))

;;; Render scale: the world drawn at a whole fraction of the window, each of its pixels
;;; shown as a square of the screen's (the game pass, main.lisp). The HUD and menus stay at
;;; the window's size. Under software OpenGL (Mesa's llvmpipe, 4 cores, 1280×720) a frame took
;;; 190 ms at full size, 52 at a half and 23 at a quarter: drawing every pixel is the cost.

(defvar *render-scale-setting* 1.0
  "Settings' render scale slider, 0 to 1: the window's size at 1, down to *SMALLEST-RENDER-SCALE*
of it at 0, a whole fraction each step (RENDER-DIVISOR).")

(defparameter *smallest-render-scale* 4
  "The most the world is shrunk: a quarter of the window across, as Hexen's 320×200 was of a
screen.")

(defun render-divisor (&optional (setting *render-scale-setting*))
  "What the window's size is divided by for the world: 1, 2, 3 .. *SMALLEST-RENDER-SCALE*."
  (max 1 (round (+ 1 (* (- *smallest-render-scale* 1) (- 1.0 setting))))))

(defun render-size (size)
  "The world's size in pixels for a window SIZE pixels across (the game pass's texspec)."
  (max 1 (ceiling size (render-divisor))))

(defun render-scale-text (setting)
  (let ((divisor (render-divisor setting)))
    (if (= divisor 1)
        "Full"
        (format NIL "1/~d" divisor))))

(defmethod setting-changed ((variable (eql '*render-scale-setting*)))
  ;; The passes' textures are made for a size; the same size again makes the world's anew.
  (when *context*
    (resize (scene +main+) (width *context*) (height *context*))))

;;; The settings file.

(defparameter *settings-variables*
  '((:fullscreen *fullscreen* :boolean)
    (:render-scale *render-scale-setting* :fraction)
    (:mouse-sensitivity *mouse-sensitivity-setting* :fraction)
    (:music-volume *music-volume* :fraction)
    (:sound-volume *sound-volume* :fraction)
    (:show-fps *show-fps* :boolean))
  "What the settings file keeps besides the bindings: its key, the variable and the kind of
value, :BOOLEAN or :FRACTION (a number from 0 to 1).")

(defun settings-file ()
  "settings.lisp beside the saves' folder: $XDG_DATA_HOME/hexmaw/ (on Windows
%LOCALAPPDATA%\\hexmaw\\). It follows *SAVE-DIRECTORY*, which a standalone build sets as it
starts (dist.lisp)."
  (merge-pathnames "settings.lisp" (uiop:pathname-parent-directory-pathname *save-directory*)))

(defun setting-value (kind value)
  "VALUE read from the file as a setting of KIND, or :INVALID."
  (ecase kind
    (:boolean (if (member value '(T NIL)) value :invalid))
    (:fraction (if (and (realp value) (<= 0 value 1)) (float value 0f0) :invalid))))

(defun save-settings-file ()
  "Write every setting and binding to SETTINGS-FILE. True if it was written."
  (let ((file (settings-file)))
    (handler-case
        (let ((temp (make-pathname :type "tmp" :defaults file)))
          (ensure-directories-exist file)
          (with-open-file (out temp :direction :output :if-exists :supersede)
            (with-standard-io-syntax
              (let ((*package* (find-package '#:hexmaw))
                    (*print-case* :downcase))
                (format out ";; Hexmaw's settings, written by the game. Delete this file for the defaults.~%(:version 1")
                (loop for (key variable) in *settings-variables*
                      do (format out "~% ~s ~s" key (symbol-value variable)))
                (format out "~% :bindings (~{~s~^~%            ~}))~%" *bindings*))))
          (uiop:rename-file-overwriting-target temp file)
          T)
      (error (e)
        (v:warn :hexmaw.settings "Couldn't write the settings to ~a: ~a" file e)
        NIL))))

(defun load-settings-file ()
  "Read SETTINGS-FILE, if there is one: each setting it holds a valid value for, and its
bindings over the defaults. A file that can't be read leaves everything as it was, with a
warning. True if it was read."
  (let ((file (settings-file)))
    (when (probe-file file)
      (handler-case
          (let ((plist (with-open-file (in file)
                         (with-standard-io-syntax
                           (let ((*read-eval* NIL)
                                 (*package* (find-package '#:hexmaw)))
                             (read in))))))
            (unless (and (listp plist) (evenp (length plist)))
              (error "it holds no settings"))
            (loop for (key variable kind) in *settings-variables*
                  for read = (getf plist key :missing)
                  for value = (if (eq read :missing) :missing (setting-value kind read))
                  do (case value
                       (:missing)
                       (:invalid (v:warn :hexmaw.settings "Ignoring ~s ~s in ~a" key read file))
                       (T (setf (symbol-value variable) value))))
            (let ((bindings (getf plist :bindings)))
              (when (listp bindings)
                (setf *bindings* (merge-bindings (remove-if-not #'consp bindings)))
                (incf *bindings-revision*)))
            T)
        (error (e)
          (v:warn :hexmaw.settings "Couldn't read the settings in ~a, using the defaults: ~a" file e)
          NIL)))))

;;; The Controls screen.

(defparameter *controls-pages*
  '(("Play"
     ("Movement" :forward :back :strafe-left :strafe-right :run :jump :crouch)
     ("Actions" :attack :block :interact :drink :inventory :map :quicksave :quickload :screenshot))
    ("Hotbar & map"
     ("Hotbar" :hot-1 :hot-2 :hot-3 :hot-4 :hot-5 :hot-6 :hot-7 :hot-8 :hot-9)
     ("Automap" :map-turn-left :map-turn-right :map-tilt-up :map-tilt-down :map-zoom-in
                :map-zoom-out :map-storey-up :map-storey-down :map-centre)))
  "The Controls screen's pages: a tab's name and two columns, each a heading and its actions.")

(defparameter *controls-column-width* 440)
(defparameter *controls-column-gap* 24)
(defparameter *controls-row-height* 36 "Height of a binding row, in UI units.")
(defparameter *controls-row-gap* 4)
(defparameter *controls-rows* 9 "Binding rows the tallest column on a page holds.")

(defvar *controls-page* 0 "The page of *CONTROLS-PAGES* shown.")
(defvar *controls-note* NIL "What the Controls screen's note line says, or NIL for its hint.")

(defparameter *capture-color* (chroma:color 1.0 0.88 0.5) "A row's keys while it waits for one.")

(defclass binding-row (menu-button)
  ((keys :initarg :keys :reader row-keys)
   (waiting :initarg :waiting :initform NIL :reader row-waiting-p))
  (:documentation "An action's row: its name at the left, its inputs at the right. A click
waits for the next key or mouse button to bind."))

(presentations:define-realization (presentations:default-look-and-feel binding-row)
  ((:background simple:rectangle)
   (alloy:margins)
   :pattern *menu-button-color*)
  ((:border simple:rectangle)
   (alloy:margins)
   :line-width (alloy:un 2)
   :pattern *menu-border-color*)
  ((:label simple:text)
   (alloy:margins 14 1 1 1)
   alloy:text
   :pattern *menu-text-color*
   :size (alloy:un 19)
   :halign :start :valign :middle)
  ((:keys simple:text)
   (alloy:margins 1 1 14 1)
   (row-keys alloy:renderable)
   :pattern *menu-text-color*
   :size (alloy:un 19)
   :halign :end :valign :middle))

(presentations:define-update (presentations:default-look-and-feel binding-row)
  (:background
   :pattern (cond ((or alloy:focus alloy:hovered-p) *menu-button-hover-color*)
                  ((row-waiting-p alloy:renderable) *forge-selected-color*)
                  (T *menu-button-color*)))
  (:border
   :pattern (if (row-waiting-p alloy:renderable) *forge-selected-border* *menu-border-color*)
   :hidden-p NIL)
  (:label
   :text alloy:text
   :pattern *menu-text-color*)
  (:keys
   :text (row-keys alloy:renderable)
   :pattern (if (row-waiting-p alloy:renderable) *capture-color* *menu-text-color*)))

(defclass controls-menu (menu-panel) ())
(defmethod panel-title ((panel controls-menu)) "Controls")
(defmethod panel-splash ((panel controls-menu)) (when (eq *game-state* :title) "title"))

(defun controls-hint ()
  (or *controls-note*
      (if (and *capturing* (not (eq *capturing* :done)))
          (format NIL "Press a key or mouse button for ~a. Esc cancels." (action-label *capturing*))
          "Click an action, then press its new key or mouse button.")))

(defun controls-button (label action row col focus &key (selected NIL choice))
  "FORGE-BUTTON, but a click is ignored while a capture runs or has just ended: the input
captured may be a click, and it reaches the panel too."
  (let ((button (apply #'alloy:represent-with (if choice 'forge-choice 'menu-button)
                       (make-instance 'alloy:value-data :value label)
                       :focus-parent focus (when choice (list :selected selected)))))
    (alloy:enter button row :row 0 :col col)
    (alloy:on (alloy:activate button) ()
      (unless *capturing*
        (queue-menu-action action)))
    button))

(defmethod build-panel ((panel controls-menu))
  (destructuring-bind (tab-name . columns) (nth *controls-page* *controls-pages*)
    (declare (ignore tab-name))
    (let* ((width (+ (* 2 *controls-column-width*) *controls-column-gap*))
           (row-step (+ *controls-row-height* *controls-row-gap*))
           ;; The heading, the rows, and room for the columns' cell margins.
           (body-height (+ *menu-stat-height* (* *controls-rows* row-step) (* 2 *controls-row-gap*)))
           ;; Title, tabs, note, body and footer, each with a gap, as BUILD-PANEL counts them.
           (height (+ (* 3 *menu-row-height*) (- *forge-row-height* 10) body-height
                      (* 5 *menu-row-gap*) *menu-slack*))
           (splash (panel-splash panel))
           (backdrop (apply #'make-instance (if splash 'splash-backdrop 'menu-backdrop)
                            :col-sizes `(T ,width T)
                            :row-sizes `(T ,height T)
                            (when splash (list :splash splash))))
           (column (make-instance 'alloy:vertical-linear-layout
                                  :min-size (alloy:size width *menu-row-height*)
                                  :cell-margins (alloy:margins 0 (/ *menu-row-gap* 2))))
           (focus (make-instance 'alloy:focus-list)))
      (alloy:enter column backdrop :row 1 :col 1)
      (alloy:enter (alloy:represent "Controls" 'menu-title) column)
      (let ((row (forge-row column '(T T) *menu-row-height*)))
        (loop for (name) in *controls-pages*
              for page from 0
              do (let ((page page))
                   (controls-button name (lambda ()
                                           (play-sound :menu-select)
                                           (setf *controls-page* page *controls-note* NIL *menu-refresh* T))
                                    row page focus :selected (= page *controls-page*)))))
      (forge-note-row column (controls-hint))
      (let ((body (forge-row column `(,*controls-column-width* ,*controls-column-gap* ,*controls-column-width*)
                             body-height)))
        (loop for (heading . actions) in columns
              for col from 0 by 2
              do (let ((list (make-instance 'alloy:vertical-linear-layout
                                            :min-size (alloy:size *controls-column-width* *controls-row-height*)
                                            :cell-margins (alloy:margins 0 (/ *controls-row-gap* 2)))))
                   (alloy:enter list body :row 0 :col col)
                   (alloy:enter (alloy:represent-with 'menu-stat (make-instance 'alloy:value-data :value heading)
                                                      :value "")
                                (forge-row list '(T) (- *menu-stat-height* *controls-row-gap*)))
                   (dolist (action actions)
                     (let* ((action action)
                            (waiting (eq action *capturing*))
                            (button (alloy:represent-with 'binding-row
                                                          (make-instance 'alloy:value-data :value (action-label action))
                                                          :keys (if waiting "Press a key..." (action-keys-label action))
                                                          :waiting waiting :focus-parent focus)))
                       (alloy:enter button (forge-row list '(T) *controls-row-height*) :row 0 :col 0)
                       (alloy:on (alloy:activate button) ()
                         (unless *capturing*
                           (play-sound :menu-select)
                           (queue-menu-action (lambda () (begin-capture action))))))))))
      (let ((row (forge-row column '(T T) *menu-row-height*)))
        (controls-button "Reset to defaults" (lambda () (play-sound :menu-select) (reset-controls)) row 0 focus)
        (controls-button "Back" 'close-controls row 1 focus))
      (alloy:finish-structure panel backdrop focus))))

(defun open-controls ()
  (when *settings-open*
    (setf *controls-open* T *controls-note* NIL *capturing* NIL)))

(defun close-controls ()
  (play-sound :menu-back)
  (save-settings-file)
  (setf *controls-open* NIL *controls-note* NIL *capturing* NIL))

(defun begin-capture (action)
  "Wait for the next key or mouse button to bind ACTION to (CAPTURE-INPUT)."
  (when *controls-open*
    (setf *capturing* action *controls-note* NIL *menu-refresh* T)))

(defun capture-input (input)
  "The input pressed while the Controls screen waits: bind it, or with Esc, don't."
  (let ((action *capturing*))
    (when (and action (not (eq action :done)))
      (setf *capturing* :done *menu-refresh* T)
      (cond ((eq input :escape)
             (play-sound :menu-back)
             (setf *controls-note* NIL))
            (T
             (let ((taken (rebind action input)))
               (play-sound :menu-select)
               (setf *controls-note*
                     (format NIL "~a: ~a.~{ ~a~}" (action-label action) (key-label input)
                             (loop for other in taken
                                   collect (format NIL "~a was taken from ~a~:[~;, now unbound~]."
                                                   (key-label input) (action-label other)
                                                   (null (action-inputs other))))))
               (save-settings-file)))))))

(defun update-capture ()
  "From the menu controller's tick: a capture that has ended stays :DONE until every input is
let go, so the press it took does nothing else, and none survives Controls closing."
  (when (or (and (eq *capturing* :done) (zerop (hash-table-count *held*)))
            (and *capturing* (not *controls-open*)))
    (setf *capturing* NIL)))

(defun reset-controls ()
  (reset-bindings)
  (setf *controls-note* "Every control is back to its default." *menu-refresh* T)
  (save-settings-file))
