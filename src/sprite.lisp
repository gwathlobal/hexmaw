(in-package #:hexmaw)

;;; Doom-style billboard sprites. A billboard turns to face the camera plane and
;;; picks one of five views (front, front-quarter, side, back-quarter, back) from
;;; the angle between the way it faces and the direction to the camera. Atlases
;;; come from tools/slice_turnaround.py, whose turned views all face image-left;
;;; they are mirrored when the camera is on the sprite's other side.

(define-pool hexmaw :path #p"../data/")

;; A unit quad standing on its bottom edge, so a billboard's location is its feet.
(define-asset (hexmaw billboard-quad) mesh
    (make-rectangle-mesh 1 1 :y 0.5))

(define-asset (hexmaw imp-turnaround) image
    #p"sprites/imp/turnaround.png"
  :min-filter :nearest :mag-filter :nearest)

(defun read-atlas (file)
  "Read an atlas index written by tools/slice_turnaround.py: a plist."
  (with-open-file (in (merge-pathnames file (root)))
    (let ((*read-eval* NIL))
      (read in))))

;;; Frame animations: a strip of frames from tools/slice_frames.py, played by effect
;;; sprites (fx.lisp) and by creatures as they die.

(defclass fx-animation ()
  ((texture :initarg :texture :reader animation-texture)
   (atlas :initarg :atlas :reader animation-atlas)
   (fps :initarg :fps :reader animation-fps)
   (loop-p :initarg :loop :reader animation-loop-p
           :documentation "Loop forever; otherwise the sprite leaves after the last frame.")
   (size :initarg :size :reader animation-size :documentation "Frame height in metres.")))

(defvar *fx-animations* (make-hash-table :test 'eq))

(defun find-fx-animation (name)
  (or (gethash name *fx-animations*) (error "No effect animation named ~s." name)))

(defmacro define-fx-animation (name strip &key (fps 12) loop (size 1.0))
  "Define effect animation NAME from STRIP, a path under data/ without extension:
the STRIP.png and STRIP.lisp that tools/slice_frames.py writes."
  `(progn
     (define-asset (hexmaw ,name) image
         ,(pathname (format NIL "~a.png" strip))
       :min-filter :nearest :mag-filter :nearest)
     (setf (gethash ',name *fx-animations*)
           (make-instance 'fx-animation :texture (// 'hexmaw ',name)
                                        :atlas (read-atlas ,(format NIL "data/~a.lisp" strip))
                                        :fps ,fps :loop ,loop :size ,size))))

(define-shader-entity billboard (lit-entity vertex-entity textured-entity transformed-entity listener)
  ((vertex-array :initform (// 'hexmaw 'billboard-quad))
   (atlas :initarg :atlas :accessor atlas)
   (facing :initarg :facing :initform 0.0 :accessor facing
           :documentation "Yaw the sprite faces, as for the player: 0 faces -Z, pi/2 faces +X.")
   (sprite-height :initarg :sprite-height :initform 1.5 :accessor sprite-height)
   (view-index :initform 0 :accessor view-index)
   (mirrored :initform NIL :accessor mirrored)
   (frame-uv :initform (vec4 0 0 1 1) :reader frame-uv)
   (tint :initform (vec4 0 0 0 0) :reader tint
         :documentation "RGB mixed over the sprite by A, for hit flashes and the like.")))

(defmethod initialize-instance :after ((sprite billboard) &key)
  (let ((atlas (atlas sprite))
        (h (float (sprite-height sprite) 0f0)))
    (setf (scaling sprite) (vec (* h (/ (getf atlas :cell-width) (getf atlas :cell-height))) h 1))))

(defun billboard-view (sprite camera-location)
  "The view index (0 front .. 4 back) for a camera at CAMERA-LOCATION, and whether
the camera is on the side that needs the mirrored view."
  (let* ((loc (location sprite))
         (dx (- (vx camera-location) (vx loc)))
         (dz (- (vz camera-location) (vz loc)))
         (fx (sin (facing sprite)))
         (fz (- (cos (facing sprite))))
         ;; Signed angle from the facing direction to the camera, around +Y.
         (angle (atan (- (* fz dx) (* fx dz)) (+ (* fx dx) (* fz dz)))))
    (values (min 4 (round (abs angle) #.(float (/ pi 4) 0f0)))
            (< angle 0))))

(defun strip-uv (uv atlas index count &optional mirrored)
  "Point UV (u, v, du, dv) at cell INDEX of ATLAS, a strip of COUNT cells side by
side; negative du mirrors."
  (let* ((cell (getf atlas :cell-width))
         (gap (getf atlas :gap))
         (width (float (+ (* count cell) (* (1- count) gap)) 0f0))
         (u0 (/ (* index (+ cell gap)) width))
         (du (/ cell width)))
    (if mirrored
        (setf (vx uv) (+ u0 du) (vz uv) (- du))
        (setf (vx uv) u0 (vz uv) du))
    (setf (vy uv) 0.0 (vw uv) 1.0)
    uv))

(defun update-frame-uv (sprite)
  "Point FRAME-UV at the current view's atlas cell."
  (let ((atlas (atlas sprite)))
    (strip-uv (frame-uv sprite) atlas (view-index sprite) (length (getf atlas :views)) (mirrored sprite))))

(define-handler (billboard tick) ()
  (let ((camera (camera (scene +main+))))
    (when (typep camera 'fps-camera)
      (multiple-value-bind (index mirrored) (billboard-view billboard (location camera))
        (setf (view-index billboard) index
              ;; Front and back are symmetric; mirroring them would only make them flicker.
              (mirrored billboard) (and mirrored (< 0 index 4))))
      ;; Face the camera plane rather than the camera position, as Doom does.
      (!qfrom-angle (orientation billboard) +vy+ (- (vy (rotation camera))))))
  (update-frame-uv billboard))

(defmethod render :before ((sprite billboard) (program shader-program))
  (set-fog-uniforms program)
  (setf (uniform program "light_snap") (float *sprite-light-snap* 0f0))
  (setf (uniform program "light_bands") (float *sprite-light-bands* 0f0))
  (setf (uniform program "frame_uv") (frame-uv sprite))
  (setf (uniform program "tint") (tint sprite)))

(define-class-shader (billboard :vertex-shader)
  "layout (location = TRIAL_V_UV) in vec2 in_uv;
out vec2 uv;
uniform vec4 frame_uv;

void main(){
  maybe_call_next_method();
  uv = frame_uv.xy + in_uv * frame_uv.zw;
}")

(define-class-shader (billboard :fragment-shader)
  "in vec3 v_view_position;
in vec3 v_world_position;
uniform vec3 fog_color;
uniform float fog_start;
uniform float fog_end;
uniform vec4 tint;
out vec4 color;

void main(){
  maybe_call_next_method();
  if(color.a < 0.5) discard;
  color.rgb *= band_light(light_at(snap_position(v_world_position), vec3(0), 0.0));
  color.rgb = mix(color.rgb, tint.rgb, tint.a);
  float fog = clamp((length(v_view_position) - fog_start) / (fog_end - fog_start), 0.0, 1.0);
  color.rgb = mix(color.rgb, fog_color, fog);
}")
