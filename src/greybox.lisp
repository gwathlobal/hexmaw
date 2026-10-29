(in-package #:hexmaw)

;;; Level geometry. Faces are shaded by which axis they face (Doom/Quake style), lit by
;;; the lights in lights.lisp, and distance fog hides the far end. A box with a surface
;;; is textured; one without is flat colour with a 1 m grid to show scale. Every
;;; parameter here is a DEFPARAMETER so it can be tuned live.

;; The project's assets (data/). Defined here, in the first file that defines an asset.
(define-pool hexmaw :path #p"../data/")

(defparameter *fog-color* (vec 0.06 0.05 0.07))
(defparameter *fog-start* 3.0)
(defparameter *fog-end* 12.0)
(defparameter *grid-strength* 0.25)

;;; Level textures: tiling pixel art made by tools/make_texture.py, laid on the faces in
;;; world space at *TEXELS-PER-METRE*, the monsters' density, so a 256 px texture covers
;;; 4 m and walls line up across boxes. Faces are axis-aligned, so no UVs are needed.

(defparameter *texels-per-metre* 64.0)

(define-asset (hexmaw wall-stone) image #p"textures/wall-stone.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)
(define-asset (hexmaw floor-flags) image #p"textures/floor-flags.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)
(define-asset (hexmaw ceiling-stone) image #p"textures/ceiling-stone.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)
(define-asset (hexmaw pillar-stone) image #p"textures/pillar-stone.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)
(define-asset (hexmaw planks) image #p"textures/planks.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)
(define-asset (hexmaw stair-side) image #p"textures/stair-side.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)
(define-asset (hexmaw stair-tread) image #p"textures/stair-tread.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)
(define-asset (hexmaw dressed-stone) image #p"textures/dressed-stone.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)
(define-asset (hexmaw timber) image #p"textures/timber.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)
(define-asset (hexmaw sarcophagus-side) image #p"textures/sarcophagus-side.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)
(define-asset (hexmaw sarcophagus-lid) image #p"textures/sarcophagus-lid.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)

;; A surface is the textures of a box's sides, its top and its underside, as floors and
;; ceilings are flats in Doom. A block's material picks the surface of its name, so
;; :FLOOR and :CEILING are the same slab under the names blocks use.
(defparameter *surfaces*
  '((:wall wall-stone wall-stone wall-stone)
    (:floor wall-stone floor-flags ceiling-stone)
    (:ceiling wall-stone floor-flags ceiling-stone)
    (:pillar pillar-stone pillar-stone pillar-stone)
    (:platform planks planks planks)
    (:dais pillar-stone floor-flags pillar-stone)
    (:stair stair-side stair-tread stair-side)
    (:stone dressed-stone dressed-stone dressed-stone)
    (:beam timber timber timber)
    ;; Its side is a 0.8 m strip on a 1 m texture: a box 0.8 m tall standing on a floor.
    (:sarcophagus sarcophagus-side sarcophagus-lid sarcophagus-side)))

(defun surface-textures (name)
  "The textures of surface NAME (a keyword, or a material's name) as a list (SIDE TOP
BOTTOM), or NIL if there is no such surface."
  (let ((entry (assoc name *surfaces* :test #'string-equal)))
    (when entry
      (mapcar (lambda (asset) (// 'hexmaw asset)) (rest entry)))))

;;; Lighting shared by every lit shader (the level, billboards): LIGHT_AT gives the
;;; light falling on a world position, ambient plus the lights in the LAMP-BLOCK uniform
;;; buffer, which GATHER-LIGHTS (lights.lisp) fills once a frame for every lit shader. A light is down to half at LIGHT_FALLOFF metres and fades smoothly to
;;; nothing at its radius. Callers may snap the position (SNAP_POSITION) or step the
;;; result into bands (BAND_LIGHT) for a retro look. Rooms (rooms.lisp) keep light in: a
;;; light reaches its own rooms, and the rooms beyond their portals only through the
;;; opening. No shadows within a room.

;; Up to 128 lights, the nearest first. The 128 must match *MAX-LIGHTS* (lights.lisp).
;; ROOM-MASK has a bit per room that the light stands in, 0 for none (it then lights
;; everything); PORTAL-IDS are the portals it shines through, -1 for none.
(define-gl-struct lamp-light
  (sphere :vec4)
  (color :vec3)
  (room-mask :uint)
  (portal-ids :ivec4))

;; Rooms and portals are boxes, their corners in ROOM-LOWS and ROOM-HIGHS and so on, in
;; plain arrays rather than arrays of structs: Trial declares only the last struct type
;; a block uses in the shader. A portal's low W is the axis light crosses it along (0 to
;; 2 for X to Z), and PORTAL-MASKS has the bits of the two rooms it joins. The 32s must
;; match *MAX-ROOMS* and *MAX-PORTALS* (rooms.lisp).
(define-gl-struct lamp-block
  (ambient-light :vec3)
  (camera-position :vec3)
  (light-falloff :float)
  (light-count :int)
  (room-count :int)
  (portal-count :int)
  (room-lows (:array :vec4 32))
  (room-highs (:array :vec4 32))
  (portal-lows (:array :vec4 32))
  (portal-highs (:array :vec4 32))
  (portal-masks (:array :uint 32))
  (lights (:array (:struct lamp-light) 128)))

(define-asset (hexmaw lamp-block) uniform-block
    'lamp-block
  :binding NIL)

(define-shader-entity lit-entity () ()
  (:buffers (hexmaw lamp-block)))

(define-class-shader (lit-entity :fragment-shader)
  "uniform float light_snap;
uniform float light_bands;

bool in_box(vec3 p, vec3 low, vec3 high){
  return all(greaterThanEqual(p, low)) && all(lessThanEqual(p, high));
}

// Bits of the rooms Q is in: its room's, or both rooms' of the portal it is in.
uint rooms_at(vec3 q){
  uint mask = 0u;
  for(int i = 0; i < room_count; ++i)
    if(in_box(q, room_lows[i].xyz, room_highs[i].xyz)) mask |= 1u << uint(i);
  for(int i = 0; i < portal_count; ++i)
    if(in_box(q, portal_lows[i].xyz, portal_highs[i].xyz)) mask |= portal_masks[i];
  return mask;
}

// True if the segment from A to B passes through portal I: wherever it is within the
// portal's thickness, it is inside the opening, so it doesn't clip a wall beside it.
bool through_portal(vec3 a, vec3 b, int i){
  vec3 d = b - a;
  d = mix(d, vec3(0.000001), lessThan(abs(d), vec3(0.000001)));
  vec3 t0 = (portal_lows[i].xyz - a) / d;
  vec3 t1 = (portal_highs[i].xyz - a) / d;
  vec3 enter = min(t0, t1);
  vec3 leave = max(t0, t1);
  int k = int(portal_lows[i].w);
  float from = max(enter[k], 0.0);
  float to = min(leave[k], 1.0);
  if(from > to) return false;
  for(int j = 0; j < 3; ++j)
    if(j != k && (enter[j] > from + 0.0001 || leave[j] < to - 0.0001)) return false;
  return true;
}

// FACING 1 lights a surface with normal N by the angle to each light; 0 ignores the
// angle, for sprites, which are flat cards standing in for round bodies. Q is the
// point whose room decides which lights reach it: just off a wall on the side it is
// seen from, or the middle of a sprite's body, so the whole sprite is lit alike.
vec3 light_at(vec3 p, vec3 n, float facing, vec3 q){
  vec3 total = ambient_light;
  uint here = rooms_at(q);
  for(int i = 0; i < light_count; ++i){
    vec3 d = lights[i].sphere.xyz - p;
    float dist = length(d);
    // Most lights reach only part of the view; skip them everywhere else.
    if(dist >= lights[i].sphere.w) continue;
    uint mask = lights[i].room_mask;
    if(mask != 0u && (mask & here) == 0u){
      // Another room: only through a portal into this one. HERE has none of MASK's bits,
      // so a portal with one of HERE's bits leads here from the light's side.
      bool seen = false;
      for(int k = 0; k < 4 && !seen; ++k){
        int j = lights[i].portal_ids[k];
        if(j < 0) break;
        seen = (portal_masks[j] & here) != 0u
            && through_portal(q, lights[i].sphere.xyz, j);
      }
      if(!seen) continue;
    }
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
  ((vertex-array :initform (// 'trial 'unit-cube))
   (face-textures :initform NIL :initarg :face-textures :accessor face-textures
                  :documentation "(SIDE TOP BOTTOM) textures from SURFACE-TEXTURES, or NIL for flat colour.")))

(defmethod stage :after ((box greybox) (area staging-area))
  (dolist (texture (face-textures box))
    (stage texture area)))

(defmethod bind-textures :after ((box greybox))
  (loop for texture in (face-textures box)
        for unit in '(:texture0 :texture1 :texture2)
        do (bind texture unit)))

(defun set-fog-uniforms (program)
  "Set fog_color, fog_start and fog_end, shared by every shader that fogs."
  (setf (uniform program "fog_color") *fog-color*)
  (setf (uniform program "fog_start") (float *fog-start* 0f0))
  (setf (uniform program "fog_end") (float *fog-end* 0f0)))

(defmethod render :before ((box greybox) (program shader-program))
  (set-fog-uniforms program)
  (setf (uniform program "light_snap") (float *wall-light-snap* 0f0))
  (setf (uniform program "light_bands") (float *wall-light-bands* 0f0))
  (setf (uniform program "grid_strength") (float *grid-strength* 0f0))
  (setf (uniform program "textured") (if (face-textures box) 1 0))
  (setf (uniform program "side_texture") 0)
  (setf (uniform program "top_texture") 1)
  (setf (uniform program "bottom_texture") 2)
  (setf (uniform program "texels_per_metre") (float *texels-per-metre* 0f0)))

(define-class-shader (greybox :fragment-shader)
  "in vec3 v_world_position;
in vec3 v_view_position;
uniform vec3 fog_color;
uniform float fog_start;
uniform float fog_end;
uniform float grid_strength;
uniform int textured;
uniform sampler2D side_texture;
uniform sampler2D top_texture;
uniform sampler2D bottom_texture;
uniform float texels_per_metre;
out vec4 color;

// TEX laid flat on an axis-aligned face with normal N (its absolute value) at world
// position P: X faces by (z, y), Z faces by (x, y), floors and ceilings by (x, z).
vec3 face_texel(sampler2D tex, vec3 p, vec3 n){
  vec2 st = (n.y > 0.5) ? p.xz : (n.x > n.z) ? p.zy : p.xy;
  return texture(tex, st * texels_per_metre / vec2(textureSize(tex, 0))).rgb;
}

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
  if(textured != 0){
    color.rgb *= (n.y <= 0.5) ? face_texel(side_texture, v_world_position, n)
               : (face.y > 0.0) ? face_texel(top_texture, v_world_position, n)
               : face_texel(bottom_texture, v_world_position, n);
    line = 0.0;
  }
  color.rgb *= shade * (1.0 - grid_strength * line) * band_light(light_at(snap_position(v_world_position), face, 1.0, v_world_position + face * 0.05));
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

(defun add-box (container x0 y0 z0 x1 y1 z1
                &key surface (color (if surface (vec 1 1 1) (vec 0.6 0.6 0.6))) (solid T))
  "Add a box spanning the two corners, in metres, to CONTAINER. SURFACE (a name in
*SURFACES*) textures it, tinted by COLOR; without one it is flat COLOR."
  (let ((box (make-solid x0 y0 z0 x1 y1 z1))
        (textures (and surface (or (surface-textures surface) (error "No surface called ~s." surface)))))
    (when solid (vector-push-extend box *solids*))
    (enter (make-instance 'greybox
                          :color (vec4 (vx color) (vy color) (vz color) 1)
                          :face-textures textures
                          :location (vec (/ (+ (aref box 0) (aref box 3)) 2)
                                         (/ (+ (aref box 1) (aref box 4)) 2)
                                         (/ (+ (aref box 2) (aref box 5)) 2))
                          :scaling (vec (- (aref box 3) (aref box 0))
                                        (- (aref box 4) (aref box 1))
                                        (- (aref box 5) (aref box 2))))
           container)))
