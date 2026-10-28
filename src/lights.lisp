(in-package #:hexmaw)

;;; Point lights for the lit shaders (LIT-ENTITY in greybox.lisp): the level and
;;; billboards. Effects and the HUD stay unlit; fire is its own light. A light is a
;;; LAMP in *LAMPS*, which the level rebuilds. Each frame GATHER-LIGHTS drops the lamps
;;; the fog hides, sorts the rest nearest first, and writes up to *MAX-LIGHTS* of them
;;; into the LAMP-BLOCK uniform buffer that every lit shader reads.

(defparameter *ambient-color* (vec 0.65 0.63 0.67)
  "Light on every surface, from no direction. It multiplies the face shading, so 0.65 keeps
the hall about as bright as with Trial's renderer at 0.5.")
(defparameter *light-falloff* 2.0 "Metres from a light at which it is down to half.")
;; Retro looks, per kind of surface: the world grid, in metres, light is worked out on
;; (blocky pools), and brightness steps per unit of light (rings). 0 turns either off.
(defparameter *wall-light-snap* 0.0)
(defparameter *wall-light-bands* 0.0)
(defparameter *sprite-light-snap* 0.0)
(defparameter *sprite-light-bands* 0.0)
(defparameter *torch-color* (vec 1.3 0.8 0.4))
(defparameter *torch-radius* 7.0)
(defparameter *torch-flicker* 0.12 "How far a torch's brightness wavers, as a fraction.")
(defparameter *torch-flame-size* 0.35 "Height of the flame drawn at a torch, in metres.")
(defparameter *bolt-light-color* (vec 1.5 0.8 0.3))
(defparameter *bolt-light-radius* 4.0)

;; The size of LAMP-BLOCK's light array (greybox.lisp); change both together and restart.
(defparameter *max-lights* 128)

(defclass lamp ()
  ((location :initarg :location :accessor location)
   (color :initarg :color :accessor color)
   (radius :initarg :radius :accessor radius)
   (flicker :initarg :flicker :initform 0.0 :accessor flicker
            :documentation "How far the brightness wavers, as a fraction; 0 for steady.")
   (flicker-phase :initform (random 100.0) :reader flicker-phase)
   (source :initarg :source :initform NIL :reader source
           :documentation "Entity the lamp follows; it goes out when the entity leaves the scene.")
   (camera-distance :initform 0.0 :accessor camera-distance
                    :documentation "Metres from the camera, as of the last GATHER-LIGHTS.")
   (room-a :initform NIL :accessor room-a
           :documentation "The room it stands in, or the first room of the portal it is in.")
   (room-b :initform NIL :accessor room-b
           :documentation "The second room of the portal it is in.")
   (located :initform NIL :accessor located
            :documentation "True once ROOM-A and ROOM-B are found; a lamp with a source is found again every frame.")))

(defvar *lamps* (make-array 0 :adjustable T :fill-pointer T)
  "Every light in the level. BUILD-LEVEL empties it.")

(defun add-lamp (location color radius &key (flicker 0.0) source)
  (let ((lamp (make-instance 'lamp :location (vcopy location) :color (vcopy color)
                                   :radius (float radius 0f0) :flicker (float flicker 0f0)
                                   :source source)))
    (vector-push-extend lamp *lamps*)
    lamp))

;;; Torches: a steady, flickering lamp with a flame drawn where it hangs.

(define-shader-entity torch-flame (fx-sprite) ()
  (:documentation "The flame drawn at a torch. Unlike other effects, it stays through RESET-RUN."))

(defun add-torch (container x y z)
  (add-lamp (vec x y z) *torch-color* *torch-radius* :flicker *torch-flicker*)
  (let* ((animation (find-fx-animation 'bolt-flight))
         (flame (make-instance 'torch-flame :animation animation :location (vec x y z))))
    (nv* (scaling flame) (/ *torch-flame-size* (animation-size animation)))
    (enter flame container)))

(defun attach-glow (source color radius)
  "Light SOURCE, an entity, with a lamp that follows it until it leaves the scene."
  (add-lamp (location source) color radius :source source))

;;; Flicker runs on its own clock, wrapped at 2 pi: the flicker's frequencies are whole
;;; numbers, so the wrap doesn't show, and the clock stays a small single-float.

(defvar *light-clock* 0.0)

(defun advance-light-clock (dt)
  (incf *light-clock* (float dt 0f0))
  (when (< #.(float (* 2 pi) 0f0) *light-clock*)
    (decf *light-clock* #.(float (* 2 pi) 0f0))))

(defun lamp-brightness (lamp)
  "How bright LAMP is now, from its flicker: steady while the world is frozen."
  (let ((p (flicker-phase lamp))
        (time *light-clock*))
    (if (frozen-p)
        1.0
        (+ 1.0 (* (flicker lamp) (+ (* 0.6 (sin (+ (* time 9.0) p)))
                                    (* 0.4 (sin (+ (* time 23.0) (* 2 p))))))))))

;;; Each frame: follow sources, drop lamps whose source has gone or that the fog hides,
;;; sort the rest by distance and send the nearest. Nothing here allocates once
;;; *LIT-LAMPS* has grown to the level's lamp count.

(defvar *lit-lamps* (make-array 0 :adjustable T :fill-pointer T)
  "The lamps that can light something visible this frame, nearest first.")
(defvar *light-color* (vec3) "Scratch: colour of the light being sent.")

(defun locate-lamp (lamp)
  "Find the rooms LAMP shines in directly (rooms.lisp)."
  (let ((at (location lamp)))
    (multiple-value-bind (a b) (rooms-at (vx at) (vy at) (vz at))
      (setf (room-a lamp) a (room-b lamp) b (located lamp) T))))

(defun update-lamps ()
  "Move lamps with a source onto it, remove those whose source left the scene, and find
the rooms of those that moved or are new."
  (let ((j 0))
    (loop for lamp across *lamps*
          for source = (source lamp)
          do (cond ((null source)
                    (unless (located lamp) (locate-lamp lamp))
                    (setf (aref *lamps* j) lamp) (incf j))
                   ((container source)
                    (v<- (location lamp) (location source))
                    (locate-lamp lamp)
                    (setf (aref *lamps* j) lamp) (incf j))))
    (setf (fill-pointer *lamps*) j)))

(defun sort-lit-lamps (camera)
  "Fill *LIT-LAMPS* with the lamps that can reach a point closer than the fog's far end,
nearest CAMERA first. A lamp further than that plus its radius only lights fogged-out
surfaces. Insertion sort: the order barely changes from frame to frame."
  (let ((lit *lit-lamps*)
        (reach (float *fog-end* 0f0)))
    (setf (fill-pointer lit) 0)
    (loop for lamp across *lamps*
          for at = (location lamp)
          for d = (sqrt (+ (expt (- (vx at) (vx camera)) 2)
                           (expt (- (vy at) (vy camera)) 2)
                           (expt (- (vz at) (vz camera)) 2)))
          do (setf (camera-distance lamp) d)
             (when (< d (+ reach (radius lamp)))
               (vector-push-extend lamp lit)
               (loop for j downfrom (1- (fill-pointer lit)) above 0
                     while (< (camera-distance (aref lit j)) (camera-distance (aref lit (1- j))))
                     do (rotatef (aref lit j) (aref lit (1- j))))))
    lit))

(defun slot-offset (struct slot)
  "Byte offset of SLOT in the buffer memory of gl-struct STRUCT."
  (org.shirakumo.fraf.trial::slot-offset struct slot))

;; Inline, so the raw memory pointer isn't boxed (allocated) to pass it in.
(declaim (inline put-floats))
(defun put-floats (memory offset vector)
  "Write the X, Y and Z of VECTOR as floats at OFFSET bytes into MEMORY."
  (setf (cffi:mem-ref memory :float offset) (vx vector)
        (cffi:mem-ref memory :float (+ offset 4)) (vy vector)
        (cffi:mem-ref memory :float (+ offset 8)) (vz vector)))

;; These two take the block rather than its memory pointer, and get the pointer
;; themselves: passing a raw pointer to a function that isn't inline boxes (allocates) it.
(defun put-lamp-rooms (block light lamp)
  "Write LAMP's room mask and the portals it shines through into LIGHT, its entry in
LAMP-BLOCK, BLOCK, sending those rooms and portals too."
  (let ((memory (memory-region-pointer (storage block)))
        (mask 0)
        (offset (slot-offset light 'portal-ids))
        (n 0))
    (declare (type (unsigned-byte 32) mask) (type fixnum n))
    (flet ((add (room)
             (when room
               (let ((index (send-room room)))
                 (when (<= 0 index) (setf mask (logior mask (ash 1 index))))))))
      (add (room-a lamp))
      (add (room-b lamp)))
    ;; The portals out of its rooms that it reaches, up to the four LAMP-LIGHT holds.
    (flet ((try (room)
             (when room
               (dolist (portal (portals room))
                 (when (and (< n 4)
                            (not (and (member (room-a lamp) (rooms portal))
                                      (member (room-b lamp) (rooms portal))))
                            (< (box-distance (box portal) (location lamp)) (radius lamp)))
                   (let ((index (send-portal portal)))
                     (when (<= 0 index)
                       (setf (cffi:mem-ref memory :int (+ offset (* 4 n))) index)
                       (incf n))))))))
      (try (room-a lamp))
      (try (room-b lamp)))
    (loop for k from n below 4
          do (setf (cffi:mem-ref memory :int (+ offset (* 4 k))) -1))
    (setf (cffi:mem-ref memory :uint (slot-offset light 'room-mask)) mask)))

(defun put-rooms (block)
  "Write the rooms and portals sent this frame into LAMP-BLOCK, BLOCK."
  ;; Every array element, a vec4 or a uint, takes 16 bytes. SLOT-OFFSET on the block
  ;; only handles single values, so array offsets come from its class.
  (flet ((array-offset (slot)
           (+ (org.shirakumo.fraf.trial::base-offset block) (slot-offset (class-of block) slot))))
    (let ((memory (memory-region-pointer (storage block)))
          (room-lows (array-offset 'room-lows))
          (room-highs (array-offset 'room-highs))
          (portal-lows (array-offset 'portal-lows))
          (portal-highs (array-offset 'portal-highs))
          (portal-masks (array-offset 'portal-masks)))
      (loop for room across *sent-rooms*
            for at = (* 16 (buffer-index room))
            do (put-box memory (+ room-lows at) (+ room-highs at) (box room)))
      (loop for portal across *sent-portals*
            for at = (* 16 (buffer-index portal))
            do (put-box memory (+ portal-lows at) (+ portal-highs at) (box portal))
               (setf (cffi:mem-ref memory :float (+ portal-lows at 12)) (float (axis portal) 0f0)
                     (cffi:mem-ref memory :uint (+ portal-masks at))
                     (let ((mask 0))
                       (declare (type (unsigned-byte 32) mask))
                       (dolist (room (rooms portal) mask)
                         (when (<= 0 (buffer-index room))
                           (setf mask (logior mask (ash 1 (buffer-index room)))))))))
      (setf (cffi:mem-ref memory :int (slot-offset block 'room-count)) (length *sent-rooms*)
            (cffi:mem-ref memory :int (slot-offset block 'portal-count)) (length *sent-portals*)))))

(defun gather-lights ()
  "Send the nearest lamps the fog doesn't hide to the LAMP-BLOCK uniform buffer, with
the rooms and portals they light."
  (update-lamps)
  (clear-sent-rooms)
  (let ((buffer (// 'hexmaw 'lamp-block))
        (camera (location (camera (scene +main+)))))
    (when (allocated-p buffer)
      (let* ((lit (sort-lit-lamps camera))
             (count (min *max-lights* (length lit))))
        (with-buffer-tx (block buffer)
          ;; Fields are written straight into the buffer's memory: setting them through
          ;; SLOT-VALUE allocates, which a per-frame function mustn't.
          (let ((memory (memory-region-pointer (storage block)))
                (lights (slot-value block 'lights))
                (color *light-color*))
            (put-floats memory (slot-offset block 'ambient-light) *ambient-color*)
            (put-floats memory (slot-offset block 'camera-position) camera)
            (setf (cffi:mem-ref memory :float (slot-offset block 'light-falloff)) (float *light-falloff* 0f0)
                  (cffi:mem-ref memory :int (slot-offset block 'light-count)) count)
            (dotimes (i count)
              (let ((lamp (aref lit i))
                    (light (aref lights i)))
                (let ((offset (slot-offset light 'sphere)))
                  (put-floats memory offset (location lamp))
                  (setf (cffi:mem-ref memory :float (+ offset 12)) (radius lamp)))
                (v<- color (color lamp))
                (nv* color (lamp-brightness lamp))
                (put-floats memory (slot-offset light 'color) color)
                (put-lamp-rooms block light lamp)))
            (put-rooms block)))))))

