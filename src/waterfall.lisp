(in-package #:hexmaw)

;;; Waterfalls: where a creek drops a storey (a blueprint's FALLS action), a sheet of water
;;; hangs from the lip to the pool below, its streaks pouring down, with churning foam where
;;; it lands. Both are WATER-SURFACE's kin: lit, see-through, drawn late. The water itself is
;;; only the two pools' liquids: the sheet is a picture, and swimming over the lip drops into
;;; the pool below. Its roar is an ambient loop at the foot (*FALLS-POINTS*, liquids.lisp).

(defparameter *falls-speed* 3.0 "Metres a second the sheet's streaks pour down.")
(defparameter *falls-alpha* 0.8 "How much of what lies behind the sheet it hides.")
(defparameter *foam-reach* 1.6 "Metres out from the sheet's foot that its foam spreads.")
(defparameter *spill-reach* 2.5 "How far beside a waterfall ADD-WATERFALL looks for the pool it pours from.")

(define-shader-entity waterfall (liquid-sheet)
  ((axis :initarg :axis :initform (vec2 1 0) :reader falls-axis
         :documentation "The sheet's direction across, in XZ.")
   (bottom :initarg :bottom :initform 0.0 :reader falls-bottom))
  (:documentation "A waterfall's sheet: a quad standing across the drop."))

(defmethod late-rank ((sheet waterfall)) 0.2)

(defmethod render :around ((sheet waterfall) (program shader-program))
  (gl:disable :cull-face)
  (gl:depth-mask NIL)
  (call-next-method)
  (gl:depth-mask T)
  (gl:enable :cull-face))

;;; Not under FIRST-THIS-FRAME-P: LIQUID-SHEET's method, which runs after this one, asks it.
(defmethod render :before ((sheet waterfall) (program shader-program))
  (setf (uniform program "falls_speed") (float *falls-speed* 0f0)
        (uniform program "falls_alpha") (float *falls-alpha* 0f0)
        (uniform program "falls_axis") (falls-axis sheet)
        (uniform program "falls_bottom") (float (falls-bottom sheet) 0f0)))

(define-class-shader (waterfall :fragment-shader)
  "in vec3 v_world_position;
in vec3 v_view_position;
uniform sampler2D surface_texture;
uniform float texels_per_metre;
uniform float time;
uniform float falls_speed;
uniform float falls_alpha;
uniform vec2 falls_axis;
uniform float falls_bottom;
out vec4 color;

vec3 falls_layer(float u, float v, float speed, float shift){
  // The water's own texture, twice as long down its length, pouring down at SPEED and
  // rippling across as the surface does.
  vec2 st = vec2(u + shift + 0.05 * sin(v * 2.3 + time * 1.7), (v + time * speed) * 0.5);
  return texture(surface_texture, st * texels_per_metre / vec2(textureSize(surface_texture, 0))).rgb;
}

void main(){
  float u = dot(v_world_position.xz, falls_axis);
  float v = v_world_position.y;
  // Two layers falling at different speeds, so the pattern never repeats as one sheet.
  vec3 a = falls_layer(u, v, falls_speed, 0.0);
  vec3 b = falls_layer(u, v, falls_speed * 1.37, 1.7);
  vec3 c = (a + b) * 0.62;
  // White water: the texture's own brightest texels whitened, more of them toward the foot,
  // so the foam keeps the pixel shapes of the water around it.
  float foot = smoothstep(falls_bottom + 1.5, falls_bottom, v);
  float bright = max(dot(a, vec3(0.3333)), dot(b, vec3(0.3333)));
  float foam = smoothstep(0.24 - 0.08 * foot, 0.36 - 0.08 * foot, bright);
  c = mix(c, vec3(0.74, 0.8, 0.83), (0.35 + 0.35 * foot) * foam);
  // Lit on the side it is seen from.
  vec3 n = vec3(-falls_axis.y, 0.0, falls_axis.x);
  if(dot(n, camera_position - v_world_position) < 0.0) n = -n;
  vec3 light = band_light(light_at(snap_position(v_world_position), n, 1.0, v_world_position + n * 0.05));
  vec3 lamp = lamp_part(light);
  color = vec4(fog_lit(c * (light - lamp), c * lamp, length(v_view_position)), falls_alpha);
}")

(define-shader-entity falls-foam (liquid-sheet)
  ((axis :initarg :axis :initform (vec2 1 0) :reader falls-axis)
   (middle :initarg :middle :initform (vec2 0 0) :reader foam-middle
           :documentation "A point on the line in XZ where the sheet meets the pool."))
  (:documentation "Foam churning on the pool where a waterfall lands."))

(defmethod late-rank ((foam falls-foam)) 0.1)

(defmethod render :around ((foam falls-foam) (program shader-program))
  (gl:disable :cull-face)
  (gl:depth-mask NIL)
  (call-next-method)
  (gl:depth-mask T)
  (gl:enable :cull-face))

(defmethod render :before ((foam falls-foam) (program shader-program))
  (setf (uniform program "foam_reach") (float *foam-reach* 0f0)
        (uniform program "falls_axis") (falls-axis foam)
        (uniform program "foam_middle") (foam-middle foam)))

(define-class-shader (falls-foam :fragment-shader)
  "in vec3 v_world_position;
in vec3 v_view_position;
uniform float time;
uniform vec2 falls_axis;
uniform vec2 foam_middle;
uniform float foam_reach;
out vec4 color;

float foam_hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float foam_noise(vec2 p){
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(foam_hash(i), foam_hash(i + vec2(1, 0)), f.x),
             mix(foam_hash(i + vec2(0, 1)), foam_hash(i + vec2(1, 1)), f.x), f.y);
}

void main(){
  vec2 p = v_world_position.xz;
  vec2 across = vec2(-falls_axis.y, falls_axis.x);
  float out_from = abs(dot(p - foam_middle, across));
  // Two layers of blobs boiling outward from the line the water lands on.
  vec2 q = vec2(dot(p, falls_axis), out_from);
  float churn = foam_noise(q * 3.0 + vec2(0.0, -time * 1.4)) * 0.6 + foam_noise(q * 7.0 + vec2(time * 0.5, -time * 2.3)) * 0.4;
  float fade = 1.0 - smoothstep(0.0, foam_reach, out_from);
  float a = step(0.45 + 0.4 * (1.0 - fade), churn) * fade;
  if(a <= 0.0) discard;
  vec3 c = vec3(0.82, 0.88, 0.9);
  vec3 light = band_light(light_at(snap_position(v_world_position), vec3(0.0, 1.0, 0.0), 1.0, v_world_position + vec3(0.0, 0.05, 0.0)));
  vec3 lamp = lamp_part(light);
  color = vec4(fog_lit(c * (light - lamp), c * lamp, length(v_view_position)), 0.85 * a);
}")

(defun add-waterfall (container low high)
  "Add a waterfall pouring through the box from LOW to HIGH: its sheet across the box's longer
side, from HIGH's height down to LOW's (the pool's surface), and foam where it lands. With the
upper pool found on one side (within *SPILL-REACH* of the box), the sheet stands at the box's far
edge from it, and a SPILL of water at the pool's height runs from the pool over the lip to the
sheet's top, so nothing open shows between them."
  (let* ((w (- (vx high) (vx low))) (d (- (vz high) (vz low)))
         (along-x (<= d w))
         (width (max w d)) (depth (min w d))
         (cx (/ (+ (vx low) (vx high)) 2)) (cz (/ (+ (vz low) (vz high)) 2))
         (y0 (vy low)) (y1 (vy high))
         (axis (if along-x (vec2 1 0) (vec2 0 1)))
         ;; Across the drop, the unit step; and how far out from the box the upper pool starts
         ;; on each side, if it does.
         (nx (if along-x 0.0 1.0)) (nz (if along-x 1.0 0.0)))
    (flet ((pool-gap (side)
             (loop for out from 0.05 to *spill-reach* by 0.05
                   for reach = (+ (/ depth 2) out)
                   when (swim-liquid-at (+ cx (* side nx reach)) (- y1 0.05) (+ cz (* side nz reach)))
                     return out)))
      (let* ((up (cond ((pool-gap 1) 1) ((pool-gap -1) -1)))
             (gap (and up (pool-gap up))))
        (when up
          ;; The sheet at the downstream edge, the spill from it to the pool's edge.
          (let ((length (+ depth gap)))
            (enter (make-instance 'water-surface :surface-texture (// 'hexmaw 'water-ripple)
                                                 :location (vec (+ cx (* up nx (/ gap 2))) y1 (+ cz (* up nz (/ gap 2))))
                                                 :scaling (if along-x (vec width length 1) (vec length width 1))
                                                 :orientation (qfrom-angle +vx+ (float (- (/ pi 2)) 0f0)))
                   container))
          (setf cx (- cx (* up nx (- (/ depth 2) 0.02)))
                cz (- cz (* up nz (- (/ depth 2) 0.02)))))))
    (enter (make-instance 'waterfall :surface-texture (// 'hexmaw 'water-ripple)
                                     :axis axis :bottom y0
                                     :location (vec cx (/ (+ y0 y1) 2) cz)
                                     :scaling (vec width (- y1 y0) 1)
                                     :orientation (if along-x (quat) (qfrom-angle +vy+ (float (/ pi 2) 0f0))))
           container)
    (enter (make-instance 'falls-foam :surface-texture (// 'hexmaw 'water-ripple)
                                      :axis axis :middle (vec2 cx cz)
                                      :location (vec cx (+ y0 0.01) cz)
                                      :scaling (if along-x
                                                   (vec (+ width 1.0) (* 2 *foam-reach*) 1)
                                                   (vec (* 2 *foam-reach*) (+ width 1.0) 1))
                                      :orientation (qfrom-angle +vx+ (float (- (/ pi 2)) 0f0)))
           container)
    (vector-push-extend (vec cx (+ y0 0.5) cz) *falls-points*)))
