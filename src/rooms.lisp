(in-package #:hexmaw)

;;; Rooms and portals, which keep light in the room it is in. A room is a box of air:
;;; its walls, floor and ceiling lie outside it. A portal is a box joining two rooms,
;;; a doorway through a wall's thickness or a flat opening where two rooms touch. A
;;; lamp lights the rooms it stands in, and the rooms beyond their portals only along
;;; lines that pass through the opening (LIGHT_AT in greybox.lisp; GATHER-LIGHTS sends
;;; the rooms and portals it needs). Rooms shouldn't overlap.
;;;
;;; Something in no room is lit only by lamps in no room, and a lamp in no room lights
;;; everything, so a level without rooms is lit as if light went through walls.

;; The sizes of LAMP-BLOCK's room and portal arrays (greybox.lisp); change both together
;; and restart. Rooms can't go past 32: each lamp's rooms are bits of one 32-bit mask.
(defparameter *max-rooms* 32)
(defparameter *max-portals* 32)
(defparameter *portal-probe* 0.25
  "How far past each face of a portal LINK-ROOMS looks for the room it opens into.")

(defclass level-room ()
  ((box :initarg :box :reader box
        :documentation "#(min-x min-y min-z max-x max-y max-z), as a solid.")
   (portals :initform () :accessor portals :documentation "The portals out of it.")
   (buffer-index :initform -1 :accessor buffer-index
                 :documentation "Its index in LAMP-BLOCK's rooms this frame, or -1.")))

(defclass portal ()
  ((box :initarg :box :reader box)
   (axis :initform 0 :accessor axis
         :documentation "The axis light crosses it along, 0 to 2 for X to Z: its thinnest.")
   (rooms :initform () :accessor rooms :documentation "The two rooms it joins.")
   (buffer-index :initform -1 :accessor buffer-index
                 :documentation "Its index in LAMP-BLOCK's portals this frame, or -1.")))

(defvar *rooms* (make-array 0 :adjustable T :fill-pointer T) "The level's rooms. BUILD-LEVEL empties it.")
(defvar *portals* (make-array 0 :adjustable T :fill-pointer T) "The level's portals. BUILD-LEVEL empties it.")

(defun add-room (x0 y0 z0 x1 y1 z1)
  "Add a room, the box of air between the two corners, in metres."
  (let ((room (make-instance 'level-room :box (make-solid x0 y0 z0 x1 y1 z1))))
    (vector-push-extend room *rooms*)
    room))

(defun add-portal (x0 y0 z0 x1 y1 z1)
  "Add a portal, the opening between the two corners. LINK-ROOMS finds the rooms it joins."
  (let ((portal (make-instance 'portal :box (make-solid x0 y0 z0 x1 y1 z1))))
    (vector-push-extend portal *portals*)
    portal))

(declaim (inline box-contains-p))
(defun box-contains-p (box x y z)
  "True if X Y Z is inside BOX or on its faces."
  (and (<= (aref box 0) x (aref box 3))
       (<= (aref box 1) y (aref box 4))
       (<= (aref box 2) z (aref box 5))))

(defun room-at (x y z)
  "The room X Y Z is in, or NIL."
  (loop for room across *rooms*
        when (box-contains-p (box room) x y z)
          return room))

(defun rooms-at (x y z)
  "The rooms light at X Y Z reaches directly: the room it is in, or the two rooms joined
by the portal it is in, or none. Two values, either of them NIL."
  (let ((room (room-at x y z)))
    (if room
        (values room NIL)
        (loop for portal across *portals*
              when (and (rooms portal) (box-contains-p (box portal) x y z))
                return (values (first (rooms portal)) (second (rooms portal)))
              finally (return (values NIL NIL))))))

(defun link-rooms ()
  "Join each portal to the rooms either side of it, and drop the portals that don't open
into a room on both sides, such as a walled-off doorway. Run once every room and portal
is in."
  (loop for room across *rooms* do (setf (portals room) ()))
  (let ((j 0))
    (loop for portal across *portals*
          for box = (box portal)
          for axis = (let ((sizes (loop for a below 3 collect (- (aref box (+ a 3)) (aref box a)))))
                       (position (reduce #'min sizes) sizes))
          for centre = (loop for a below 3 collect (/ (+ (aref box a) (aref box (+ a 3))) 2))
          for reach = (+ (/ (- (aref box (+ axis 3)) (aref box axis)) 2) *portal-probe*)
          for sides = (loop for sign in '(-1 1)
                            collect (let ((p (copy-list centre)))
                                      (incf (nth axis p) (* sign reach))
                                      (apply #'room-at p)))
          do (setf (axis portal) axis
                   (rooms portal) ())
             (when (and (first sides) (second sides) (not (eq (first sides) (second sides))))
               (setf (rooms portal) sides)
               (dolist (room sides) (push portal (portals room)))
               (setf (aref *portals* j) portal)
               (incf j)))
    (setf (fill-pointer *portals*) j)))

(defun box-distance (box point)
  "Metres from POINT to the nearest point of BOX; 0 inside it."
  (flet ((gap (lo hi v) (max 0.0 (- lo v) (- v hi))))
    (let ((dx (gap (aref box 0) (aref box 3) (vx point)))
          (dy (gap (aref box 1) (aref box 4) (vy point)))
          (dz (gap (aref box 2) (aref box 5) (vz point))))
      (sqrt (+ (* dx dx) (* dy dy) (* dz dz))))))

;;; Each frame GATHER-LIGHTS sends the rooms and portals the lit lamps need, up to
;;; *MAX-ROOMS* and *MAX-PORTALS*; a lamp that would need more loses those rooms.

(defvar *sent-rooms* (make-array 32 :fill-pointer 0) "The rooms sent this frame, by BUFFER-INDEX.")
(defvar *sent-portals* (make-array 32 :fill-pointer 0) "The portals sent this frame, by BUFFER-INDEX.")

(defun clear-sent-rooms ()
  (loop for room across *sent-rooms* do (setf (buffer-index room) -1))
  (loop for portal across *sent-portals* do (setf (buffer-index portal) -1))
  (setf (fill-pointer *sent-rooms*) 0
        (fill-pointer *sent-portals*) 0))

(defun send-room (room)
  "ROOM's index in this frame's rooms, sending it if it isn't yet; -1 if they're full."
  (cond ((<= 0 (buffer-index room)) (buffer-index room))
        ((< (fill-pointer *sent-rooms*) (min *max-rooms* (array-dimension *sent-rooms* 0)))
         (setf (buffer-index room) (vector-push room *sent-rooms*)))
        (T -1)))

(defun send-portal (portal)
  "PORTAL's index in this frame's portals, sending it and its rooms if it isn't yet; -1
if they're full."
  (cond ((<= 0 (buffer-index portal)) (buffer-index portal))
        ((< (fill-pointer *sent-portals*) (min *max-portals* (array-dimension *sent-portals* 0)))
         (dolist (room (rooms portal)) (send-room room))
         (setf (buffer-index portal) (vector-push portal *sent-portals*)))
        (T -1)))

(declaim (inline put-box))
(defun put-box (memory low high box)
  "Write BOX's corners as two vec3s at byte offsets LOW and HIGH into MEMORY."
  (dotimes (a 3)
    (setf (cffi:mem-ref memory :float (+ low (* 4 a))) (aref box a)
          (cffi:mem-ref memory :float (+ high (* 4 a))) (aref box (+ a 3)))))
