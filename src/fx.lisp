(in-package #:hexmaw)

;;; Animated effect sprites: projectiles, impact bursts. An animation is a strip
;;; of frames from tools/slice_frames.py, shown on a quad that always faces the
;;; camera. Fire is its own light, so effects skip fog and stay bright in the dark.

;; A unit quad centred on its origin, so an effect's location is its middle.
(define-asset (hexmaw centered-quad) mesh
    (make-rectangle-mesh 1 1))

(define-shader-entity fx-sprite (vertex-entity textured-entity transformed-entity listener)
  ((vertex-array :initform (// 'hexmaw 'centered-quad))
   (animation :initarg :animation :reader sprite-animation)
   (age :initform 0.0 :accessor age)
   (frame-uv :initform (vec4 0 0 1 1) :reader frame-uv)))

(defmethod initialize-instance :after ((sprite fx-sprite) &key)
  (let* ((animation (sprite-animation sprite))
         (atlas (animation-atlas animation))
         (h (float (animation-size animation) 0f0)))
    (setf (texture sprite) (animation-texture animation)
          (scaling sprite) (vec (* h (/ (getf atlas :cell-width) (getf atlas :cell-height))) h 1))))

(defun spawn-fx (name location container)
  "Play effect animation NAME once at LOCATION. Returns the effect sprite."
  (let ((sprite (make-instance 'fx-sprite :animation (find-fx-animation name) :location (vcopy location))))
    (enter sprite container)
    sprite))

(defun despawn (entity)
  (when (container entity)
    (leave entity (container entity))))

(defvar *pitch-quat* (quat))

(defun face-camera (entity camera)
  "Turn ENTITY parallel to the view plane of fps-camera CAMERA."
  (let ((rotation (rotation camera)))
    (!qfrom-angle (orientation entity) +vy+ (- (vy rotation)))
    (!qfrom-angle *pitch-quat* +vx+ (- (vx rotation)))
    (nq* (orientation entity) *pitch-quat*)))

(define-handler (fx-sprite tick) (dt)
  (unless (frozen-p)
    (incf (age fx-sprite) dt))
  (let* ((animation (sprite-animation fx-sprite))
         (atlas (animation-atlas animation))
         (count (getf atlas :frames))
         (frame (floor (* (age fx-sprite) (animation-fps animation))))
         (camera (camera (scene +main+))))
    (cond ((animation-loop-p animation)
           (setf frame (mod frame count)))
          ((<= count frame)
           (despawn fx-sprite)
           (setf frame (1- count))))
    (strip-uv (frame-uv fx-sprite) atlas frame count)
    (when (typep camera 'fps-camera)
      (face-camera fx-sprite camera))))

(defmethod render :before ((sprite fx-sprite) (program shader-program))
  (setf (uniform program "frame_uv") (frame-uv sprite)))

(define-class-shader (fx-sprite :vertex-shader)
  "layout (location = TRIAL_V_UV) in vec2 in_uv;
out vec2 uv;
uniform vec4 frame_uv;

void main(){
  maybe_call_next_method();
  uv = frame_uv.xy + in_uv * frame_uv.zw;
}")

(define-class-shader (fx-sprite :fragment-shader)
  "out vec4 color;

void main(){
  maybe_call_next_method();
  if(color.a < 0.5) discard;
}")
