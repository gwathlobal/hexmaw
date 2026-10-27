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

(define-shader-entity billboard (vertex-entity textured-entity transformed-entity listener)
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

(defun update-frame-uv (sprite)
  "Point FRAME-UV (u, v, du, dv) at the current view's atlas cell; negative du mirrors."
  (let* ((atlas (atlas sprite))
         (cell (getf atlas :cell-width))
         (gap (getf atlas :gap))
         (n (length (getf atlas :views)))
         (width (float (+ (* n cell) (* (1- n) gap)) 0f0))
         (u0 (/ (* (view-index sprite) (+ cell gap)) width))
         (du (/ cell width))
         (uv (frame-uv sprite)))
    (if (mirrored sprite)
        (setf (vx uv) (+ u0 du) (vz uv) (- du))
        (setf (vx uv) u0 (vz uv) du))
    (setf (vy uv) 0.0 (vw uv) 1.0)))

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
uniform vec3 fog_color;
uniform float fog_start;
uniform float fog_end;
uniform vec4 tint;
out vec4 color;

void main(){
  maybe_call_next_method();
  if(color.a < 0.5) discard;
  color.rgb = mix(color.rgb, tint.rgb, tint.a);
  float fog = clamp((length(v_view_position) - fog_start) / (fog_end - fog_start), 0.0, 1.0);
  color.rgb = mix(color.rgb, fog_color, fog);
}")
