(in-package #:hexmaw)

;;; Untextured level geometry. Faces are shaded by which axis they face
;;; (Doom/Quake style), lit by the lights in lights.lisp, a 1 m grid shows scale,
;;; and distance fog hides the far end. Every parameter here is a DEFPARAMETER so
;;; it can be tuned live.

(defparameter *fog-color* (vec 0.06 0.05 0.07))
(defparameter *fog-start* 3.0)
(defparameter *fog-end* 12.0)
(defparameter *grid-strength* 0.25)

;;; Lighting shared by every lit shader (the level, billboards): LIGHT_AT gives the
;;; light falling on a world position, ambient plus the lights in the LAMP-BLOCK uniform
;;; buffer, which GATHER-LIGHTS (lights.lisp) fills once a frame for every lit shader. A light is down to half at LIGHT_FALLOFF metres and fades smoothly to
;;; nothing at its radius. Callers may snap the position (SNAP_POSITION) or step the
;;; result into bands (BAND_LIGHT) for a retro look. No shadows: light goes through walls.

;; Up to 128 lights, the nearest first. The 128 must match *MAX-LIGHTS* (lights.lisp).
(define-gl-struct lamp-light
  (sphere :vec4)
  (color :vec3))

(define-gl-struct lamp-block
  (ambient-light :vec3)
  (camera-position :vec3)
  (light-falloff :float)
  (light-count :int)
  (lights (:array (:struct lamp-light) 128)))

(define-asset (hexmaw lamp-block) uniform-block
    'lamp-block
  :binding NIL)

(define-shader-entity lit-entity () ()
  (:buffers (hexmaw lamp-block)))

(define-class-shader (lit-entity :fragment-shader)
  "uniform float light_snap;
uniform float light_bands;

// FACING 1 lights a surface with normal N by the angle to each light; 0 ignores the
// angle, for sprites, which are flat cards standing in for round bodies.
vec3 light_at(vec3 p, vec3 n, float facing){
  vec3 total = ambient_light;
  for(int i = 0; i < light_count; ++i){
    vec3 d = lights[i].sphere.xyz - p;
    float dist = length(d);
    // Most lights reach only part of the view; skip them everywhere else.
    if(dist >= lights[i].sphere.w) continue;
    float edge = dist / lights[i].sphere.w;
    // Inverse-square-like near the light, windowed to reach zero at the radius.
    float window = clamp(1.0 - edge * edge * edge * edge, 0.0, 1.0);
    float k = window * window / (1.0 + (dist * dist) / (light_falloff * light_falloff));
    float angle = mix(1.0, max(dot(n, d / max(dist, 0.001)), 0.0), facing);
    total += lights[i].color * k * angle;
  }
  return total;
}

// P snapped to the centre of its cell in a LIGHT_SNAP world grid; P itself when it's 0.
vec3 snap_position(vec3 p){
  return (light_snap <= 0.0) ? p : (floor(p / light_snap) + 0.5) * light_snap;
}

// LIGHT with its brightness stepped into LIGHT_BANDS steps per unit; unchanged when 0.
vec3 band_light(vec3 light){
  if(light_bands <= 0.0) return light;
  float level = max(light.r, max(light.g, light.b));
  float banded = ceil(level * light_bands) / light_bands;
  return light * (banded / max(level, 0.0001));
}")

(define-shader-entity greybox (lit-entity vertex-entity colored-entity transformed-entity)
  ((vertex-array :initform (// 'trial 'unit-cube))))

(defun set-fog-uniforms (program)
  "Set fog_color, fog_start and fog_end, shared by every shader that fogs."
  (setf (uniform program "fog_color") *fog-color*)
  (setf (uniform program "fog_start") (float *fog-start* 0f0))
  (setf (uniform program "fog_end") (float *fog-end* 0f0)))

(defmethod render :before ((box greybox) (program shader-program))
  (set-fog-uniforms program)
  (setf (uniform program "light_snap") (float *wall-light-snap* 0f0))
  (setf (uniform program "light_bands") (float *wall-light-bands* 0f0))
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
  // Turned toward the camera, since the visible side is the one being lit.
  vec3 face = normalize(cross(dFdx(v_world_position), dFdy(v_world_position)));
  if(dot(face, camera_position - v_world_position) < 0.0) face = -face;
  vec3 n = abs(face);
  float shade = n.y * 1.0 + n.x * 0.75 + n.z * 0.6;
  // 1 m grid on the two axes that lie in the face.
  vec3 g = abs(fract(v_world_position + 0.5) - 0.5);
  vec3 tangent = step(n, vec3(0.5));
  float d = min(min(mix(1.0, g.x, tangent.x), mix(1.0, g.y, tangent.y)), mix(1.0, g.z, tangent.z));
  float line = 1.0 - smoothstep(0.0, 0.02, d);
  color.rgb *= shade * (1.0 - grid_strength * line) * band_light(light_at(snap_position(v_world_position), face, 1.0));
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

(defun box-overlaps-p (s x y z half-width height)
  "True if box S overlaps an upright box standing at X Y Z, HALF-WIDTH out from its
centre line on X and Z and HEIGHT tall. Touching faces don't count."
  (let ((eps 1f-4))
    (and (< (- x half-width) (- (aref s 3) eps)) (> (+ x half-width) (+ (aref s 0) eps))
         (< y (- (aref s 4) eps)) (> (+ y height) (+ (aref s 1) eps))
         (< (- z half-width) (- (aref s 5) eps)) (> (+ z half-width) (+ (aref s 2) eps)))))

(defun solid-overlapping (x y z half-width height)
  "The first solid overlapped by an upright box standing at X Y Z, HALF-WIDTH out from
its centre line on X and Z and HEIGHT tall, or NIL. Touching faces don't count."
  (loop for s across *solids*
        when (box-overlaps-p s x y z half-width height)
          return s))

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
