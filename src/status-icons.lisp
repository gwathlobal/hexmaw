(in-package #:hexmaw)

;;; The player's statuses (magic.lisp) as a row of icons in the top-left corner: one cell per
;;; status, like a hotbar slot, its border in the status's colour, its icon (a frame of
;;; data/sprites/icons/statuses, tools/draw_status_icons.py), the seconds it has left (a ward's
;;; points instead, which run out first) over the bottom-right corner, and a bar along the bottom
;;; for the time left of its whole. In its last *STATUS-WARN-TIME* the icon blinks. An actor has
;;; one status of each kind at most, so four cells do, and a fifth for the priest's blessing
;;; (dialogue.lisp), which isn't a status but shows as one; the ones not needed don't draw.

(define-fx-animation status-strip "sprites/icons/statuses")

(defparameter *status-icon-frames* '(:fire 0 :frost 1 :shock 2 :heal 3 :slow 4 :ward 5 :bless 6)
  "The strip frame for a damage status by its element, and for the other kinds by kind.")
(defparameter *status-colors*
  (list :fire (vec4 1.0 0.55 0.15 1) :frost (vec4 0.45 0.75 1.0 1) :shock (vec4 0.95 0.85 0.25 1)
        :heal (vec4 0.4 0.85 0.35 1) :slow (vec4 0.6 0.7 0.95 1) :ward (vec4 0.7 0.45 1.0 1)
        :bless (vec4 1.0 0.85 0.4 1))
  "The border and time bar of each status, keyed as *STATUS-ICON-FRAMES* is.")
(defparameter *status-order* '(:damage :slow :heal :ward :bless)
  "Left to right, the kinds of status shown; :BLESS is the priest's blessing.")
(defparameter *status-warn-time* 3.0 "Seconds left from which a status's icon blinks.")
(defparameter *status-blink-rate* 4.0 "Blinks a second in the last *STATUS-WARN-TIME*.")
(defparameter *status-bar-height* 4 "Pixels: the time bar along a cell's bottom.")

(defun status-key (status)
  "STATUS's key in *STATUS-ICON-FRAMES* and *STATUS-COLORS*: its element for damage."
  (if (eq :damage (status-kind status))
      (or (status-element status) :fire)
      (status-kind status)))

(define-shader-entity status-part ()
  ((shown :initform NIL :accessor shown)))

(defmethod hud-shown-p ((part status-part))
  (and (call-next-method) (shown part)))

(define-shader-entity status-frame (status-part weapon-slot) ())
(define-shader-entity status-icon (status-part weapon-icon)
  ((animation :initform (find-fx-animation 'status-strip))))
(define-shader-entity status-number (status-part hud-text) ())
(define-shader-entity status-bar (status-part hud-bar) ())

(defclass status-cell ()
  ((frame :initform (make-instance 'status-frame) :reader cell-frame)
   (icon :initform (make-instance 'status-icon) :reader cell-icon)
   (number :initform (make-hud-text "" 'status-number) :reader cell-number)
   (bar :initform (make-instance 'status-bar) :reader cell-bar)
   (shown-number :initform NIL :accessor shown-number))
  (:documentation "One status on screen: its frame, icon, number and time bar."))

(defun status-cell-parts (cell)
  ;; Back to front.
  (list (cell-frame cell) (cell-icon cell) (cell-bar cell) (cell-number cell)))

(defclass status-icons (entity listener)
  ((name :initform :status-icons)
   (cells :initform (loop repeat (length *status-order*) collect (make-instance 'status-cell))
          :reader status-cells)))

(defun add-status-icons (container)
  (let ((row (make-instance 'status-icons)))
    (enter row container)
    (dolist (cell (status-cells row))
      (dolist (part (status-cell-parts cell))
        (enter part container)))
    row))

(defun hide-status-cell (cell)
  (dolist (part (status-cell-parts cell))
    (setf (shown part) NIL)))

(defun show-status-cell (cell key left whole count x y)
  "Lay CELL out at X, Y, its bottom-left corner, for a status of KEY (in *STATUS-ICON-FRAMES*)
with LEFT of WHOLE seconds to run, showing COUNT."
  (let* ((frame (cell-frame cell))
         (icon (cell-icon cell))
         (number (cell-number cell))
         (bar (cell-bar cell))
         (color (getf *status-colors* key))
         (size (item-cell-size))
         (icon-size (item-icon-size))
         (pad *weapon-slot-padding*)
         (left (max 0.0 left))
         (whole (max 0.001 whole)))
    (dolist (part (status-cell-parts cell))
      (setf (shown part) T))
    ;; The border in the status's colour, as an enchanted weapon's is.
    (setf (active frame) NIL
          (enchanted frame) T
          (vx (scaling frame)) (float size 0f0)
          (vy (scaling frame)) (float size 0f0))
    (v<- (enchant-color frame) color)
    (place frame x y -0.2)
    (setf (frame icon) (getf *status-icon-frames* key 0)
          ;; Dimmed every other beat in its last seconds.
          (active icon) (or (< *status-warn-time* left)
                            (evenp (floor (* left *status-blink-rate* 2))))
          (vx (scaling icon)) (float icon-size 0f0)
          (vy (scaling icon)) (float icon-size 0f0))
    (place icon (+ x pad) (+ y pad) -0.1)
    (setf (fill-fraction bar) (min 1.0 (/ left whole))
          (vx (scaling bar)) (float (- size pad pad) 0f0)
          (vy (scaling bar)) (float *status-bar-height* 0f0))
    (v<- (fill-color bar) color)
    (place bar (+ x pad) (+ y 1) -0.05)
    ;; Re-uploading text costs a buffer update, so only when the number changes.
    (unless (eql count (shown-number cell))
      (setf (shown-number cell) count
            (text number) (princ-to-string count)))
    (place number (- (+ x size) pad (* 9 (length (text number)))) (+ y 1 *status-bar-height*) 0)))

(define-handler (status-icons tick) ()
  (when *player*
    (let* ((size (item-cell-size))
           (step (+ size *weapon-slot-gap*))
           ;; Under the frame counter's line while it shows.
           (top (- (height *context*) *hud-margin* (if *show-fps* (+ +glyph-height+ *weapon-slot-gap*) 0)))
           (cells (status-cells status-icons))
           (index 0))
      (dolist (kind *status-order*)
        (let ((x (+ *hud-margin* (* index step)))
              (y (- top size)))
          (if (eq kind :bless)
              (let ((left (blessed *player*)))
                (when (< 0.0 left)
                  (show-status-cell (nth index cells) :bless left *bless-time* (ceiling left) x y)
                  (incf index)))
              (let ((status (status-of *player* kind)))
                (when (and status (< 0.0 (status-left status)))
                  (let ((left (status-left status)))
                    (show-status-cell (nth index cells) (status-key status) left
                                      (or (status-duration status) left)
                                      (ceiling (if (eq :ward kind) (status-magnitude status) left))
                                      x y))
                  (incf index))))))
      (loop for cell in (nthcdr index cells)
            do (hide-status-cell cell)))))
