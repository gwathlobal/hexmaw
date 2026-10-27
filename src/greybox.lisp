(in-package #:hexmaw)

;;; Untextured level geometry. Faces are shaded by which axis they face
;;; (Doom/Quake style), a 1 m grid shows scale, and distance fog hides the far
;;; end. Every parameter here is a DEFPARAMETER so it can be tuned live.

(defparameter *fog-color* (vec 0.06 0.05 0.07))
(defparameter *fog-start* 3.0)
(defparameter *fog-end* 12.0)
(defparameter *grid-strength* 0.25)

(define-shader-entity greybox (vertex-entity colored-entity transformed-entity)
  ((vertex-array :initform (// 'trial 'unit-cube))))

(defun set-fog-uniforms (program)
  "Set fog_color, fog_start and fog_end, shared by every shader that fogs."
  (setf (uniform program "fog_color") *fog-color*)
  (setf (uniform program "fog_start") (float *fog-start* 0f0))
  (setf (uniform program "fog_end") (float *fog-end* 0f0)))

(defmethod render :before ((box greybox) (program shader-program))
  (set-fog-uniforms program)
  (setf (uniform program "grid_strength") (float *grid-strength* 0f0)))

(define-class-shader (greybox :fragment-shader)
  "in vec3 v_world_position;
in vec3 v_view_position;
uniform vec3 fog_color;
uniform float fog_start;
uniform float fog_end;
uniform float grid_strength;
out vec4 color;

void main(){
  maybe_call_next_method();
  // Flat face normal from screen-space derivatives; no mesh normals needed.
  vec3 n = abs(normalize(cross(dFdx(v_world_position), dFdy(v_world_position))));
  float shade = n.y * 1.0 + n.x * 0.75 + n.z * 0.6;
  // 1 m grid on the two axes that lie in the face.
  vec3 g = abs(fract(v_world_position + 0.5) - 0.5);
  vec3 tangent = step(n, vec3(0.5));
  float d = min(min(mix(1.0, g.x, tangent.x), mix(1.0, g.y, tangent.y)), mix(1.0, g.z, tangent.z));
  float line = 1.0 - smoothstep(0.0, 0.02, d);
  color.rgb *= shade * (1.0 - grid_strength * line);
  float fog = clamp((length(v_view_position) - fog_start) / (fog_end - fog_start), 0.0, 1.0);
  color.rgb = mix(color.rgb, fog_color, fog);
}")

;;; Solids are axis-aligned boxes stored as #(min-x min-y min-z max-x max-y max-z).
;;; The level rebuilds this list; the player collides against it.

(defvar *solids* (make-array 0 :adjustable T :fill-pointer T))

(defun make-solid (x0 y0 z0 x1 y1 z1)
  (let ((box (make-array 6 :element-type 'single-float)))
    (setf (aref box 0) (float (min x0 x1) 0f0) (aref box 1) (float (min y0 y1) 0f0) (aref box 2) (float (min z0 z1) 0f0)
          (aref box 3) (float (max x0 x1) 0f0) (aref box 4) (float (max y0 y1) 0f0) (aref box 5) (float (max z0 z1) 0f0))
    box))

(defun add-box (container x0 y0 z0 x1 y1 z1 &key (color (vec 0.6 0.6 0.6)) (solid T))
  "Add a box spanning the two corners, in metres, to CONTAINER."
  (let ((box (make-solid x0 y0 z0 x1 y1 z1)))
    (when solid (vector-push-extend box *solids*))
    (enter (make-instance 'greybox
                          :color (vec4 (vx color) (vy color) (vz color) 1)
                          :location (vec (/ (+ (aref box 0) (aref box 3)) 2)
                                         (/ (+ (aref box 1) (aref box 4)) 2)
                                         (/ (+ (aref box 2) (aref box 5)) 2))
                          :scaling (vec (- (aref box 3) (aref box 0))
                                        (- (aref box 4) (aref box 1))
                                        (- (aref box 5) (aref box 2))))
           container)))
