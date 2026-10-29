(in-package #:hexmaw)

;;; Point lights for the lit shaders (LIT-ENTITY in greybox.lisp): the level and
;;; billboards. Effects and the HUD stay unlit; fire is its own light. A light is a
;;; LAMP in *LAMPS*, which the level rebuilds. Each frame GATHER-LIGHTS drops the lamps
;;; the fog hides (lamp light carries to *LAMP-FOG-END*, further than ambient light),
;;; sorts the rest nearest first, and writes up to *MAX-LIGHTS* of them into the
;;; LAMP-BLOCK uniform buffer that every lit shader reads.

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
(defparameter *torch-size* 0.96
  "Height of the torch sprite, flame tip to handle end, in metres. 0.96 makes the unlit
torch 0.69 m, at about 135 art pixels per metre.")
(defparameter *torch-stand-off* 0.1
  "Metres from the wall to the torch's centre line: more than half the sprite's width, so
the sprite, which turns to face the camera, doesn't sink into the wall seen from the side.")
(defparameter *torch-wall-reach* 1.0
  "How far from where a torch is placed ADD-TORCH looks for a wall to hang it on.")
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

;;; Torches: a burning torch in an iron collar, one camera-facing sprite standing off the
;;; wall, and a flickering lamp in the flame. Like the effects, it is fullbright.

(define-fx-animation torch "sprites/torch/torch" :fps 10 :loop T :size *torch-size*)

(define-shader-entity torch (fx-sprite) ()
  (:documentation "A wall torch. Unlike other effects, it stays through RESET-RUN."))

;; Turned only about +Y, as a billboard is, so it stands upright when the view tilts.
(define-handler (torch tick :after) ()
  (let ((camera (camera (scene +main+))))
    (when (typep camera 'fps-camera)
      (!qfrom-angle (orientation torch) +vy+ (- (vy (rotation camera)))))))

(defun wall-near (x y z reach)
  "The wall face nearest X Y Z along +-X or +-Z within REACH metres: its distance and the
X and Z of its outward normal, or NIL."
  (let ((best reach) nx nz)
    (loop for s across *solids*
          do (when (< (aref s 1) y (aref s 4))
               (when (< (aref s 2) z (aref s 5))
                 (let ((west (- x (aref s 3))) (east (- (aref s 0) x)))
                   (when (< 0 west best) (setf best west nx 1.0 nz 0.0))
                   (when (< 0 east best) (setf best east nx -1.0 nz 0.0))))
               (when (< (aref s 0) x (aref s 3))
                 (let ((north (- z (aref s 5))) (south (- (aref s 2) z)))
                   (when (< 0 north best) (setf best north nx 0.0 nz 1.0))
                   (when (< 0 south best) (setf best south nx 0.0 nz -1.0))))))
    (when nx (values best nx nz))))

(defun add-torch (container x y z)
  "A torch whose flame stands on X Y Z, moved to *TORCH-STAND-OFF* from the nearest wall
within *TORCH-WALL-REACH*, if there is one."
  (multiple-value-bind (distance nx nz) (wall-near x y z *torch-wall-reach*)
    (when distance
      (setf x (+ x (* nx (- *torch-stand-off* distance)))
            z (+ z (* nz (- *torch-stand-off* distance)))))
    ;; The sprite is centred on its location; the flame's base is :OVERLAY-BOTTOM rows
    ;; down from its top (tools/overlay_strip.py), and the lamp halfway up the flame.
    (let* ((animation (find-fx-animation 'torch))
           (atlas (animation-atlas animation))
           (base (/ (getf atlas :overlay-bottom) (getf atlas :cell-height)))
           (torch (make-instance 'torch :animation animation
                                        :location (vec x (+ y (* (- base 0.5) *torch-size*)) z))))
      (add-lamp (vec x (+ y (* 0.5 base *torch-size*)) z) *torch-color* *torch-radius*
                :flicker *torch-flicker*)
      (enter torch container)
      torch)))

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

(declaim (inline sphere-in-view-p))
(defun sphere-in-view-p (dx dy dz r cos-yaw sin-yaw cos-pitch sin-pitch tan-x tan-y)
  "True if the sphere of radius R at DX DY DZ from an FPS camera, turned by the cosines
and sines of its yaw and pitch, reaches into its view frustum, whose sides are TAN-X and
TAN-Y out per metre ahead. The near and far planes don't count."
  (declare (type single-float dx dy dz r cos-yaw sin-yaw cos-pitch sin-pitch tan-x tan-y))
  ;; Into view space as the camera does it (Trial's PROJECT-VIEW for an FPS-CAMERA): turn
  ;; about Y by the yaw, then about X by the pitch. AHEAD is the distance along the view.
  (let* ((x (+ (* cos-yaw dx) (* sin-yaw dz)))
         (z (- (* cos-yaw dz) (* sin-yaw dx)))
         (y (- (* cos-pitch dy) (* sin-pitch z)))
         (ahead (- (+ (* sin-pitch dy) (* cos-pitch z)))))
    (and (< (- r) ahead)
         (< (- (abs x) (* ahead tan-x)) (* r (sqrt (+ 1 (* tan-x tan-x)))))
         (< (- (abs y) (* ahead tan-y)) (* r (sqrt (+ 1 (* tan-y tan-y))))))))

(defun sort-lit-lamps (camera)
  "Fill *LIT-LAMPS* with the lamps that can light something CAMERA sees closer than the
fog's far end for lamp light, nearest first. A lamp further than that plus its radius
only lights fogged-out surfaces, and one whose light lies wholly outside the view
lights nothing on screen. Insertion sort: the order barely changes from frame to frame."
  (let* ((lit *lit-lamps*)
         (eye (location camera))
         (reach (float (max *fog-end* *lamp-fog-end*) 0f0))
         (frustum (typep camera 'fps-camera))
         (pitch (if frustum (vx (rotation camera)) 0f0))
         (yaw (if frustum (vy (rotation camera)) 0f0))
         (context (context +main+))
         (tan-y (float (tan (* (/ pi 360) (if frustum (fov camera) 180))) 0f0))
         (tan-x (* tan-y (/ (float (max 1 (width context)) 0f0) (max 1 (height context))))))
    (declare (type single-float reach pitch yaw tan-y tan-x))
    (setf (fill-pointer lit) 0)
    (loop with cos-yaw = (cos yaw) and sin-yaw = (sin yaw)
          and cos-pitch = (cos pitch) and sin-pitch = (sin pitch)
          for lamp across *lamps*
          for at = (location lamp)
          for dx = (- (vx at) (vx eye))
          for dy = (- (vy at) (vy eye))
          for dz = (- (vz at) (vz eye))
          for d = (sqrt (+ (* dx dx) (* dy dy) (* dz dz)))
          do (setf (camera-distance lamp) d)
             (when (and (< d (+ reach (radius lamp)))
                        (or (not frustum)
                            (sphere-in-view-p dx dy dz (float (radius lamp) 0f0) cos-yaw sin-yaw cos-pitch sin-pitch tan-x tan-y)))
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
LAMP-BLOCK, BLOCK, sending those rooms and portals too. NIL, and nothing worth keeping
written, if LAMP stands in a room but the rooms sent this frame are full: a mask of 0
would light everything, through every wall."
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
    (when (and (= mask 0) (or (room-a lamp) (room-b lamp)))
      (return-from put-lamp-rooms NIL))
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
    (setf (cffi:mem-ref memory :uint (slot-offset light 'room-mask)) mask)
    T))

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
the rooms and portals they light. A lamp whose room no longer fits is left out."
  (update-lamps)
  (clear-sent-rooms)
  (let ((buffer (// 'hexmaw 'lamp-block))
        (camera (camera (scene +main+))))
    (when (allocated-p buffer)
      (let ((lit (sort-lit-lamps camera))
            (count 0))
        (declare (type fixnum count))
        (with-buffer-tx (block buffer)
          ;; Fields are written straight into the buffer's memory: setting them through
          ;; SLOT-VALUE allocates, which a per-frame function mustn't.
          (let ((memory (memory-region-pointer (storage block)))
                (lights (slot-value block 'lights))
                (color *light-color*))
            (put-floats memory (slot-offset block 'ambient-light) *ambient-color*)
            (put-floats memory (slot-offset block 'camera-position) (location camera))
            (setf (cffi:mem-ref memory :float (slot-offset block 'light-falloff)) (float *light-falloff* 0f0))
            (loop for lamp across lit
                  while (< count *max-lights*)
                  do (let ((light (aref lights count)))
                       (when (put-lamp-rooms block light lamp)
                         (let ((offset (slot-offset light 'sphere)))
                           (put-floats memory offset (location lamp))
                           (setf (cffi:mem-ref memory :float (+ offset 12)) (radius lamp)))
                         (v<- color (color lamp))
                         (nv* color (lamp-brightness lamp))
                         (put-floats memory (slot-offset light 'color) color)
                         (incf count))))
            (setf (cffi:mem-ref memory :int (slot-offset block 'light-count)) count)
            (put-rooms block)))))))

