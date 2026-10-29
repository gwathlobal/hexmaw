(in-package #:hexmaw)

;;; Liquids: lava now, water later. A liquid is a box of volume, never a solid: it
;;; lies in a sunken pit whose floor is an ordinary solid, so walking in and out is a
;;; step down and up, and everything else asks LIQUID-AT whether a point is in one.
;;; Its kind (*LIQUID-KINDS*) says what being in it does. The surface is drawn by a
;;; LIQUID-SURFACE quad at the top, fullbright and warped like Quake's, and a liquid
;;; that glows lights the pit with lamps over it.

(define-asset (hexmaw lava-flow) image #p"textures/lava-flow.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)

(defparameter *liquid-kinds*
  '((:lava :damage 12.0 :speed 0.8 :texture lava-flow
     :glow (2.4 1.0 0.3) :glow-radius 7.0 :glow-spacing 4.0 :glow-flicker 0.08))
  "Per kind: :DAMAGE health per second to what stands in it, :SPEED the factor on walking
speed, :TEXTURE its surface, and :GLOW the colour of the lamps over it (NIL for none),
:GLOW-RADIUS their reach, one per :GLOW-SPACING metres of the pool's length.")
(defparameter *lava-tick* 0.4 "Seconds between the burns of something standing in lava.")
(defparameter *glow-height* 0.8 "Metres above a liquid's surface that its lamps hang.")

(defun liquid-property (kind key)
  (getf (rest (or (assoc kind *liquid-kinds*) (error "No liquid kind ~s." kind))) key))

(defclass liquid ()
  ((kind :initarg :kind :reader liquid-kind)
   (bounds :initarg :bounds :reader liquid-bounds
           :documentation "#(min-x min-y min-z max-x max-y max-z) as a solid's; max-y is the surface.")))

(defvar *liquids* (make-array 0 :adjustable T :fill-pointer T)
  "Every liquid in the level. BUILD-LEVEL empties it.")

(defun liquid-at (x y z)
  "The liquid the point X Y Z is in, or NIL."
  (loop for liquid across *liquids*
        for s = (liquid-bounds liquid)
        when (and (<= (aref s 0) x (aref s 3)) (<= (aref s 1) y (aref s 4)) (<= (aref s 2) z (aref s 5)))
          return liquid))

(defun hazard-at (x y z)
  "Health per second that standing at X Y Z costs: the damage of the liquid there, or 0."
  (let ((liquid (liquid-at x y z)))
    (if liquid (liquid-property (liquid-kind liquid) :damage) 0.0)))

(defun burn-due (timer dt damage)
  "Advance a burn TIMER, in seconds, by DT while standing in something that does DAMAGE per
second. Returns the timer's new value and the damage due now, a whole number, or 0. Out of
it (DAMAGE 0) the timer starts over, so a burn comes *LAVA-TICK* after stepping in."
  (if (<= damage 0)
      (values 0.0 0)
      (let ((timer (+ timer dt)))
        (if (<= *lava-tick* timer)
            (values (- timer *lava-tick*) (max 1 (round (* damage *lava-tick*))))
            (values timer 0)))))

(define-shader-entity liquid-surface (lit-entity vertex-entity transformed-entity listener)
  ((vertex-array :initform (// 'hexmaw 'centered-quad))
   (surface-texture :initarg :surface-texture :reader surface-texture)
   (clock :initform 0.0 :accessor liquid-clock)))

(defmethod stage :after ((surface liquid-surface) (area staging-area))
  (stage (surface-texture surface) area))

(defmethod bind-textures :after ((surface liquid-surface))
  (bind (surface-texture surface) :texture0))

(define-handler (liquid-surface tick) (dt)
  (unless (frozen-p)
    ;; Wrapped, so it stays a small single-float; the shader's waves repeat by then.
    (setf (liquid-clock liquid-surface) (mod (+ (liquid-clock liquid-surface) dt) 1000.0))))

(defmethod render :before ((surface liquid-surface) (program shader-program))
  (set-fog-uniforms program)
  (setf (uniform program "surface_texture") 0)
  (setf (uniform program "texels_per_metre") (float *texels-per-metre* 0f0))
  (setf (uniform program "time") (float (liquid-clock surface) 0f0)))

(define-class-shader (liquid-surface :fragment-shader)
  "in vec3 v_world_position;
in vec3 v_view_position;
uniform sampler2D surface_texture;
uniform float texels_per_metre;
uniform float time;
out vec4 color;

void main(){
  // Laid flat in world XZ like a floor, swirled by crossed waves and drifting slowly.
  vec2 p = v_world_position.xz;
  vec2 st = p + 0.18 * sin(p.yx * 1.7 + time * vec2(0.9, 1.1)) + time * vec2(0.05, 0.03);
  vec3 c = texture(surface_texture, st * texels_per_metre / vec2(textureSize(surface_texture, 0))).rgb;
  // A slow throb that rolls across the pool.
  c *= 1.0 + 0.12 * sin(time * 1.7 + p.x * 0.8 + p.y * 0.6);
  // Its own light: it fogs as lamp light does, so it glows from far off.
  color = vec4(fog_lit(vec3(0.0), c, length(v_view_position)), 1.0);
}")

(defun add-liquid (container kind x0 y0 z0 x1 y1 z1)
  "Add a liquid of KIND filling the box between the two corners, its surface the top, to
CONTAINER: the volume, its surface and, if it glows, the lamps over it."
  (let* ((s (make-solid x0 y0 z0 x1 y1 z1))
         (w (- (aref s 3) (aref s 0))) (d (- (aref s 5) (aref s 2)))
         (top (aref s 4)))
    (vector-push-extend (make-instance 'liquid :kind kind :bounds s) *liquids*)
    (enter (make-instance 'liquid-surface
                          :surface-texture (// 'hexmaw (liquid-property kind :texture))
                          :location (vec (/ (+ (aref s 0) (aref s 3)) 2) top (/ (+ (aref s 2) (aref s 5)) 2))
                          :scaling (vec w d 1)
                          :orientation (qfrom-angle +vx+ (float (- (/ pi 2)) 0f0)))
           container)
    (let ((glow (liquid-property kind :glow)))
      (when glow
        ;; Lamps spaced along the pool's longer side, down its middle.
        (let* ((along-x (<= d w))
               (len (if along-x w d))
               (n (max 1 (ceiling len (liquid-property kind :glow-spacing)))))
          (dotimes (i n)
            (let ((f (/ (+ i 0.5) n)))
              (add-lamp (if along-x
                            (vec (+ (aref s 0) (* f w)) (+ top *glow-height*) (/ (+ (aref s 2) (aref s 5)) 2))
                            (vec (/ (+ (aref s 0) (aref s 3)) 2) (+ top *glow-height*) (+ (aref s 2) (* f d))))
                        (apply #'vec glow) (liquid-property kind :glow-radius)
                        :flicker (liquid-property kind :glow-flicker)))))))))

(defun add-lava (container x0 z0 x1 z1 &key (floor 0.0)
                                            (depth hexmaw.blueprint:*lava-depth*)
                                            (surface hexmaw.blueprint:*lava-surface*))
  "Dig a lava pit from X0 Z0 to X1 Z1 into a floor at height FLOOR, whose slab is 0.5 m
thick: the pit's floor DEPTH below, the lava's surface SURFACE below, as a blueprint's
lava. Leave the hole in the floor around it."
  (add-box container x0 (- floor 0.5) z0 x1 (- floor depth) z1 :surface :floor)
  (add-liquid container :lava x0 (- floor depth) z0 x1 (- floor surface) z1))
