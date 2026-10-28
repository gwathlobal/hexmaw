(in-package #:hexmaw)

;;; Point lights for the lit shaders (LIT-ENTITY in greybox.lisp): the level and
;;; billboards. Effects and the HUD stay unlit; fire is its own light. A light is a
;;; LAMP in *LAMPS*, which the level rebuilds. Each frame GATHER-LIGHTS picks the
;;; *MAX-LIGHTS* nearest the camera, and UPLOAD-LIGHTS sends them to each lit shader
;;; program once. A lamp fades linearly-squared to nothing at its radius.

(defparameter *ambient-color* (vec 0.65 0.63 0.67)
  "Light on every surface, from no direction. It multiplies the face shading, so 0.65 keeps
the hall about as bright as with Trial's renderer at 0.5.")
(defparameter *light-snap* 0.0625 "World grid, in metres, the light is worked out on: blocky pools.")
(defparameter *light-bands* 6.0 "Brightness steps per unit of light.")
(defparameter *torch-color* (vec 1.3 0.8 0.4))
(defparameter *torch-radius* 7.0)
(defparameter *torch-flicker* 0.12 "How far a torch's brightness wavers, as a fraction.")
(defparameter *torch-flame-size* 0.35 "Height of the flame drawn at a torch, in metres.")
(defparameter *bolt-light-color* (vec 1.5 0.8 0.3))
(defparameter *bolt-light-radius* 4.0)

;; Must match MAX_LIGHTS in the LIT-ENTITY shader. The arrays below are sized from it
;; when first loaded, so a change needs a restart.
(defparameter *max-lights* 16)

(defclass lamp ()
  ((location :initarg :location :accessor location)
   (color :initarg :color :accessor color)
   (radius :initarg :radius :accessor radius)
   (flicker :initarg :flicker :initform 0.0 :accessor flicker
            :documentation "How far the brightness wavers, as a fraction; 0 for steady.")
   (flicker-phase :initform (random 100.0) :reader flicker-phase)
   (source :initarg :source :initform NIL :reader source
           :documentation "Entity the lamp follows; it goes out when the entity leaves the scene.")))

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

;;; Each frame: follow sources, drop lamps whose source has gone, pick the nearest.

(defvar *light-count* 0)
(defvar *light-spheres* (coerce (loop repeat *max-lights* collect (vec4)) 'simple-vector)
  "Position and radius of each light sent this frame.")
(defvar *light-colors* (coerce (loop repeat *max-lights* collect (vec3)) 'simple-vector))
(defvar *light-picked* (make-array *max-lights* :initial-element NIL))
(defvar *light-frame* 0 "Counts frames, so each program gets the lights once per frame.")
(defvar *light-uploads* (make-hash-table :test 'eq) "Shader program -> frame it last got the lights.")
(defvar *light-uniform-names*
  (coerce (loop for i below *max-lights*
                collect (cons (format NIL "light_sphere[~d]" i) (format NIL "light_color[~d]" i)))
          'simple-vector))

(defun update-lamps ()
  "Move lamps with a source onto it, and remove those whose source left the scene."
  (let ((j 0))
    (loop for lamp across *lamps*
          for source = (source lamp)
          do (cond ((null source)
                    (setf (aref *lamps* j) lamp) (incf j))
                   ((container source)
                    (v<- (location lamp) (location source))
                    (setf (aref *lamps* j) lamp) (incf j))))
    (setf (fill-pointer *lamps*) j)))

(defun lamp-distance (lamp camera)
  (let ((a (location lamp)))
    (+ (expt (- (vx a) (vx camera)) 2) (expt (- (vy a) (vy camera)) 2) (expt (- (vz a) (vz camera)) 2))))

(defun gather-lights ()
  "Pick up to +MAX-LIGHTS+ lamps nearest the camera into the arrays UPLOAD-LIGHTS sends."
  (update-lamps)
  (let ((camera (location (camera (scene +main+))))
        (time (float (current-time) 0f0))
        (count (min *max-lights* (length *lamps*))))
    (fill *light-picked* NIL)
    (dotimes (i count)
      ;; Selection: the nearest lamp not yet picked. Few lamps, so this is cheap.
      (let ((best NIL) (best-d 0.0))
        (loop for lamp across *lamps*
              for d = (lamp-distance lamp camera)
              do (when (and (or (null best) (< d best-d)) (not (find lamp *light-picked* :end i)))
                   (setf best lamp best-d d)))
        (setf (aref *light-picked* i) best)
        (let* ((sphere (aref *light-spheres* i))
               (color (aref *light-colors* i))
               (p (flicker-phase best))
               (k (+ 1.0 (* (flicker best) (+ (* 0.6 (sin (+ (* time 9.0) p))) (* 0.4 (sin (+ (* time 23.0) (* 2 p)))))))))
          (let ((at (location best)))
            (setf (vx sphere) (vx at) (vy sphere) (vy at) (vz sphere) (vz at) (vw sphere) (radius best)))
          (v<- color (color best))
          (nv* color k))))
    (setf *light-count* count)
    (incf *light-frame*)))

(defun upload-lights (program)
  "Send this frame's lights to PROGRAM, unless it already has them."
  (unless (eql *light-frame* (gethash program *light-uploads*))
    (setf (gethash program *light-uploads*) *light-frame*)
    (setf (uniform program "ambient_light") *ambient-color*)
    (setf (uniform program "camera_position") (location (camera (scene +main+))))
    (setf (uniform program "light_snap") (float *light-snap* 0f0))
    (setf (uniform program "light_bands") (float *light-bands* 0f0))
    (setf (uniform program "light_count") *light-count*)
    (dotimes (i *light-count*)
      (let ((names (aref *light-uniform-names* i)))
        (setf (uniform program (car names)) (aref *light-spheres* i))
        (setf (uniform program (cdr names)) (aref *light-colors* i))))))
