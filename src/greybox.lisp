(in-package #:hexmaw)

;;; Level geometry. Faces are shaded by which axis they face (Doom/Quake style), lit by
;;; the lights in lights.lisp, and distance fog hides the far end. A box with a surface
;;; is textured; one without is flat colour with a 1 m grid to show scale. Every
;;; parameter here is a DEFPARAMETER so it can be tuned live.

;; The project's assets (data/). Defined here, in the first file that defines an asset.
(define-pool hexmaw :path #p"../data/")
;; Blocks are built from their blueprints before a standalone build (tools/build-dist).
(define-as-unused hexmaw #p"blueprints/")

(defparameter *fog-color* (vec 0.06 0.05 0.07))
(defparameter *fog-start* 3.0)
(defparameter *fog-end* 12.0)
;; The light lamps add fades into the fog further out than ambient light does, so a lit
;; room shows in the dark distance while the unlit stretch before it stays dark.
(defparameter *lamp-fog-start* 6.0)
(defparameter *lamp-fog-end* 36.0)
(defparameter *grid-strength* 0.25)
;; Under water the fog closes in and turns the water's colour; lamps still show a little further.
(defparameter *underwater-fog-color* (vec 0.02 0.08 0.16))
(defparameter *underwater-fog-start* 0.5)
(defparameter *underwater-fog-end* 8.0)
(defparameter *underwater-lamp-fog-start* 1.0)
(defparameter *underwater-lamp-fog-end* 14.0)
(defvar *eye-underwater* NIL
  "True while the camera is under water (the player's PLACE-CAMERA sets it): the fog is the water's.")

(defun fog-color ()
  "The colour everything fades into, and the screen is cleared to: the water's under water."
  (if *eye-underwater* *underwater-fog-color* *fog-color*))

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
(define-asset (hexmaw rock) image #p"textures/rock.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)
(define-asset (hexmaw cave-floor) image #p"textures/cave-floor.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)
(define-asset (hexmaw ice) image #p"textures/ice.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)
(define-asset (hexmaw ice-rock) image #p"textures/ice-rock.png"
  :min-filter :nearest :mag-filter :nearest :wrapping :repeat)
(define-asset (hexmaw snow) image #p"textures/snow.png"
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
    (:sarcophagus sarcophagus-side sarcophagus-lid sarcophagus-side)
    ;; Caves: natural rock, and a floor of rubble and packed earth.
    (:rock rock rock rock)
    (:cave-floor rock cave-floor rock)
    ;; Ice: slippery (*FOOTINGS*); a raised block of it is ice all round.
    (:ice ice ice ceiling-stone)
    ;; Ice caves: walls of glacier ice, and a floor of packed snow that grips (its drifts and
    ;; the banks of frozen ponds are snow on their sides too).
    (:ice-rock ice-rock ice-rock ice-rock)
    (:snow snow snow ice-rock)))

;; A footing is how a surface holds what stands on it. A solid drawn with a surface named
;; here carries its footing (MAKE-SOLID), and whatever stands on it moves as Hexen's ice
;; (footing.lisp): its speed decays by :FRICTION per second, its push reaches :TOP-SPEED
;; times its usual speed, and below :STOP-SPEED it stops once nothing pushes it.
(defparameter *footings*
  '((:ice :friction 0.97 :top-speed 1.7 :stop-speed 0.1))
  "Per surface name, its footing: Hexen's ice is 0.973 of the speed kept per 1/35 s tic
against 0.906 on other floors, with half the push, so 0.97 per second and 1.7 times as fast.")

(defun footing-property (footing key)
  (getf (rest (or (assoc footing *footings*) (error "No footing ~s." footing))) key))

(defun surface-footing (name)
  "The footing code of surface NAME (a keyword or a material's name) for MAKE-SOLID:
its place in *FOOTINGS* from 1, or 0 for an ordinary floor."
  (let ((n (and name (position name *footings* :key #'first :test #'string-equal))))
    (if n (1+ n) 0)))

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
;;; opening. No shadows within a room. FOG_LIT fogs a lit colour: its ambient-lit part
;;; fades out between FOG_START and FOG_END, the part lamps lit carries on to LAMP_FOG_END.

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
uniform vec3 fog_color;
uniform float fog_start;
uniform float fog_end;
uniform float lamp_fog_start;
uniform float lamp_fog_end;

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
}

// The part of LIGHT (from LIGHT_AT) that lamps add above the ambient light.
vec3 lamp_part(vec3 light){
  return max(light - ambient_light, vec3(0.0));
}

// A surface seen DIST metres away, COLOR being what ambient light shows of it and GLOW
// what lamps add, fogged: the ambient part fades into the fog colour by FOG_END, the
// lamps' part only by LAMP_FOG_END.
vec3 fog_lit(vec3 color, vec3 glow, float dist){
  float fog = clamp((dist - fog_start) / (fog_end - fog_start), 0.0, 1.0);
  float lamp_fog = clamp((dist - lamp_fog_start) / (lamp_fog_end - lamp_fog_start), 0.0, 1.0);
  return mix(color, fog_color, fog) + glow * (1.0 - lamp_fog);
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

;; A program keeps its uniforms between draws, so what is the same for every entity
;; drawn with it is set once a frame, by the first: every GL call costs.
(defvar *render-frame* 0 "Frames drawn so far; MAIN's render counts them.")
(defvar *programs-this-frame* (make-hash-table :test 'eq)
  "Program -> the last *RENDER-FRAME* it was set up in.")

(defun first-this-frame-p (program)
  "True the first time it is asked about PROGRAM in a frame."
  (unless (eql (gethash program *programs-this-frame*) *render-frame*)
    (setf (gethash program *programs-this-frame*) *render-frame*)))

(defun set-fog-uniforms (program)
  "Set the fog uniforms FOG_LIT reads (lit-entity), shared by every shader that fogs."
  (let ((under *eye-underwater*))
    (setf (uniform program "fog_color") (fog-color))
    (setf (uniform program "fog_start") (float (if under *underwater-fog-start* *fog-start*) 0f0))
    (setf (uniform program "fog_end") (float (if under *underwater-fog-end* *fog-end*) 0f0))
    (setf (uniform program "lamp_fog_start") (float (if under *underwater-lamp-fog-start* *lamp-fog-start*) 0f0))
    (setf (uniform program "lamp_fog_end") (float (if under *underwater-lamp-fog-end* *lamp-fog-end*) 0f0))))

(defmethod render :before ((box greybox) (program shader-program))
  (when (first-this-frame-p program)
    (set-fog-uniforms program)
    (setf (uniform program "light_snap") (float *wall-light-snap* 0f0))
    (setf (uniform program "light_bands") (float *wall-light-bands* 0f0))
    (setf (uniform program "grid_strength") (float *grid-strength* 0f0))
    (setf (uniform program "side_texture") 0)
    (setf (uniform program "top_texture") 1)
    (setf (uniform program "bottom_texture") 2)
    (setf (uniform program "texels_per_metre") (float *texels-per-metre* 0f0)))
  (setf (uniform program "textured") (if (face-textures box) 1 0)))

(define-class-shader (greybox :fragment-shader)
  "in vec3 v_world_position;
in vec3 v_view_position;
uniform float grid_strength;
uniform int textured;
uniform sampler2D side_texture;
uniform sampler2D top_texture;
uniform sampler2D bottom_texture;
uniform float texels_per_metre;
out vec4 color;

// TEX laid flat on a face with normal N at world position P: floors and ceilings by
// (x, z), walls by the distance along the wall and y. Along the wall runs the way of its
// horizontal tangent that leans to +x and +z, so an X face reads z and a Z face x, and a
// 45° wall its diagonal; that choice is made where it can't flicker. Walls run only at
// 0° and 45°, so the direction is snapped to the nearest 45°: N comes from screen-space
// derivatives, and its slight noise, times a world position 100 m out, would scatter the
// texture by texels from one pixel to the next.
vec3 face_texel(sampler2D tex, vec3 p, vec3 n){
  vec2 st;
  if(abs(n.y) > 0.5){
    st = p.xz;
  }else{
    float eighth = 0.78539816;
    float a = round(atan(n.z, n.x) / eighth) * eighth;
    vec2 h = vec2(cos(a), sin(a));
    vec2 t = vec2(h.y, -h.x);
    float lean = t.x + t.y;
    if(lean < -0.5 || (abs(lean) <= 0.5 && t.x < 0.0)) t = -t;
    st = vec2(dot(p.xz, t), p.y);
  }
  return texture(tex, st * texels_per_metre / vec2(textureSize(tex, 0))).rgb;
}

void main(){
  maybe_call_next_method();
  // Flat face normal from screen-space derivatives; no mesh normals needed.
  // Turned toward the camera, since the visible side is the one being lit.
  vec3 face = normalize(cross(dFdx(v_world_position), dFdy(v_world_position)));
  if(dot(face, camera_position - v_world_position) < 0.0) face = -face;
  vec3 n = abs(face);
  // Weighted by the squares, so a 45° wall falls between an X face and a Z face.
  float shade = n.y * n.y * 1.0 + n.x * n.x * 0.75 + n.z * n.z * 0.6;
  // 1 m grid on the two axes that lie in the face.
  vec3 g = abs(fract(v_world_position + 0.5) - 0.5);
  vec3 tangent = step(n, vec3(0.5));
  float d = min(min(mix(1.0, g.x, tangent.x), mix(1.0, g.y, tangent.y)), mix(1.0, g.z, tangent.z));
  float line = 1.0 - smoothstep(0.0, 0.02, d);
  if(textured != 0){
    color.rgb *= (n.y <= 0.5) ? face_texel(side_texture, v_world_position, face)
               : (face.y > 0.0) ? face_texel(top_texture, v_world_position, face)
               : face_texel(bottom_texture, v_world_position, face);
    line = 0.0;
  }
  vec3 surface = color.rgb * shade * (1.0 - grid_strength * line);
  vec3 light = band_light(light_at(snap_position(v_world_position), face, 1.0, v_world_position + face * 0.05));
  vec3 lamp = lamp_part(light);
  color.rgb = fog_lit(surface * (light - lamp), surface * lamp, length(v_view_position));
}")

;;; Solids are axis-aligned boxes stored as #(min-x min-y min-z max-x max-y max-z).
;;; The level rebuilds this list; the player collides against it.

(defvar *solids* (make-array 0 :adjustable T :fill-pointer T))

;;; A wedge is a solid box with one vertical corner cut away along the diagonal between
;;; the two corners beside it: a 45° wall when the box is square. Its 7th value names the
;;; corner cut, seen from above: 1 north-east (max x, min z), 2 north-west, 3 south-west,
;;; 4 south-east; a box has none, or 0. Top and bottom stay flat, so heights read as a
;;; box's, over its solid half.

(defun corner-cut (east south)
  "The cut that takes away the corner on the EAST (else west) and SOUTH (else north) side."
  (+ 1 (if east 0 1) (if south (if east 3 1) 0)))

(defun make-solid (x0 y0 z0 x1 y1 z1 &optional (cut 0) (footing 0))
  "A solid: its corners, then for a wedge its CUT, then for one with a FOOTING (a code from
SURFACE-FOOTING) that, after a cut of 0 if it is a box."
  (let ((box (make-array (cond ((/= 0 footing) 8) ((/= 0 cut) 7) (T 6)) :element-type 'single-float)))
    (setf (aref box 0) (float (min x0 x1) 0f0) (aref box 1) (float (min y0 y1) 0f0) (aref box 2) (float (min z0 z1) 0f0)
          (aref box 3) (float (max x0 x1) 0f0) (aref box 4) (float (max y0 y1) 0f0) (aref box 5) (float (max z0 z1) 0f0))
    (when (< 6 (length box)) (setf (aref box 6) (float cut 0f0)))
    (when (< 7 (length box)) (setf (aref box 7) (float footing 0f0)))
    box))

(defun solid-footing (s)
  "The footing (a key of *FOOTINGS*) of what stands on solid S, or NIL for an ordinary floor."
  (declare (type (simple-array single-float (*)) s))
  (when (< 7 (length s))
    (first (nth (1- (truncate (aref s 7))) *footings*))))

(declaim (inline solid-cut))
(defun solid-cut (s)
  "The corner wedge S has cut away (1 to 4), or 0 for a box."
  (declare (type (simple-array single-float (*)) s))
  (if (< 6 (length s)) (truncate (aref s 6)) 0))

(declaim (inline cut-sides))
(defun cut-sides (cut)
  "1 if CUT's corner is on the +X (east) side, else 0; and 1 if on the +Z (south) side."
  (declare (type (integer 1 4) cut))
  (values (if (member cut '(1 4)) 1 0) (if (member cut '(3 4)) 1 0)))

(declaim (inline %wedge-depth))
(defun %wedge-depth (s x0 z0 x1 z1)
  "How far the XZ rectangle X0..X1 by Z0..Z1 reaches past wedge S's diagonal into its solid
half, as a fraction of the box (0 just touching, below 0 clear of it); 1 for a box."
  (declare (type (simple-array single-float (*)) s)
           (type single-float x0 z0 x1 z1)
           (optimize speed))
  (let ((cut (solid-cut s)))
    (if (= 0 cut)
        1f0
        (multiple-value-bind (cu cv) (cut-sides cut)
          ;; Across the box, f = ±u ± v grows toward the cut corner; the solid half is
          ;; where f is at most its value at the other two corners, CU + CV - 1.
          (let* ((u (/ (- (if (= cu 1) x0 x1) (aref s 0)) (- (aref s 3) (aref s 0))))
                 (v (/ (- (if (= cv 1) z0 z1) (aref s 2)) (- (aref s 5) (aref s 2))))
                 (f (+ (if (= cu 1) u (- u)) (if (= cv 1) v (- v)))))
            (- (float (+ cu cv -1) 0f0) f))))))

(defun solid-covers-p (s x z)
  "True if solid S stands over the point X Z (its edges included)."
  (let ((x (float x 0f0)) (z (float z 0f0)))
    (and (<= (aref s 0) x (aref s 3)) (<= (aref s 2) z (aref s 5))
         (<= -1f-5 (%wedge-depth s x z x z)))))

(declaim (inline %box-overlaps-p))
(defun %box-overlaps-p (s x y z half-width height)
  (declare (type (simple-array single-float (*)) s)
           (type single-float x y z half-width height)
           (optimize speed))
  (let ((eps 1f-4))
    (and (< (- x half-width) (- (aref s 3) eps)) (> (+ x half-width) (+ (aref s 0) eps))
         (< y (- (aref s 4) eps)) (> (+ y height) (+ (aref s 1) eps))
         (< (- z half-width) (- (aref s 5) eps)) (> (+ z half-width) (+ (aref s 2) eps))
         (< 1f-5 (%wedge-depth s (- x half-width) (- z half-width) (+ x half-width) (+ z half-width))))))

(defun solid-flush (s axis delta x z radius)
  "Where an upright body RADIUS out from its centre line at X Z, having moved DELTA along
AXIS (0 for X, 2 for Z) into solid S, stands flush against it: its centre's coordinate on
AXIS. True as the second value if it was a wedge's diagonal that stopped it."
  (let* ((lo (aref s axis)) (hi (aref s (+ axis 3)))
         (edge (if (< 0 delta) (- lo radius) (+ hi radius)))
         (cut (solid-cut s)))
    (if (= 0 cut)
        edge
        (multiple-value-bind (cu cv) (cut-sides cut)
          (let* ((along (if (= axis 0) cu cv))
                 (across (if (= axis 0) cv cu))
                 (clo (aref s (if (= axis 0) 2 0)))
                 (clen (- (aref s (if (= axis 0) 5 3)) clo))
                 (c (if (= axis 0) z x))
                 ;; The across axis's part of f, for the body's extent there.
                 (cterm (if (= across 1)
                            (/ (- (- c radius) clo) clen)
                            (- (/ (- (+ c radius) clo) clen))))
                 (limit (float (+ cu cv -1) 0f0))
                 (flush (if (= along 1)
                            (+ lo radius (* (- hi lo) (- limit cterm)))
                            (+ (- lo radius) (* (- hi lo) (- cterm limit))))))
            ;; Backing off only clears the diagonal if it was moving toward the cut side.
            (if (< (* (if (= along 1) 1 -1) delta) 0)
                (if (< 0 delta)
                    (if (< edge flush) (values flush T) edge)
                    (if (< flush edge) (values flush T) edge))
                edge))))))

(defun slide-along (s axis blocked)
  "The move along wedge S's diagonal that takes the place of BLOCKED metres along AXIS
(0 X, 2 Z) it stopped: the X and Z of the part of BLOCKED that runs along the wall."
  (multiple-value-bind (cu cv) (cut-sides (solid-cut s))
    ;; The diagonal's outward normal is (SU, SV)/sqrt 2: project the blocked move onto
    ;; the wall, which leaves half of it on its own axis and half on the other.
    (let ((sign (* (if (= cu 1) 1 -1) (if (= cv 1) 1 -1) -0.5)))
      (if (= axis 0)
          (values (* 0.5 blocked) (* sign blocked))
          (values (* sign blocked) (* 0.5 blocked))))))

(defun box-overlaps-p (s x y z half-width height)
  "True if box S overlaps an upright box standing at X Y Z, HALF-WIDTH out from its
centre line on X and Z and HEIGHT tall. Touching faces don't count."
  (%box-overlaps-p s (float x 0f0) (float y 0f0) (float z 0f0) (float half-width 0f0) (float height 0f0)))

;;; Finding solids fast. Collision, sight lines, projectiles and blood all ask "what
;;; solid is here?", many times a frame (a sight line asks every 0.1 m), so once a level
;;; is built INDEX-SOLIDS files every solid under the 4 m columns it reaches into, and a
;;; question looks only in the columns it touches. *SOLIDS* stays the list of record:
;;; when it isn't the vector indexed, or has grown since (a box added from the REPL), or
;;; is rebound (the nav grid binds it to the solids near a tile), questions walk it whole.

(defparameter *solid-column* 4.0 "Metres across the columns INDEX-SOLIDS files solids under.")
(defvar *solid-columns* NIL "INDEX-SOLIDS's 2D array of simple-vectors of solids, or NIL.")
(defvar *solid-columns-of* NIL "The *SOLIDS* vector *SOLID-COLUMNS* was made from.")
(defvar *solid-columns-count* 0 "How many solids it had then.")
(defvar *solid-columns-x0* 0f0)
(defvar *solid-columns-z0* 0f0)

(defun index-solids ()
  "File every solid of *SOLIDS* under the columns it reaches into, for DO-SOLIDS-NEAR."
  (let ((n (length *solids*)))
    (if (= 0 n)
        (setf *solid-columns* NIL)
        (let* ((size *solid-column*)
               (x0 (loop for s across *solids* minimize (aref s 0)))
               (z0 (loop for s across *solids* minimize (aref s 2)))
               (x1 (loop for s across *solids* maximize (aref s 3)))
               (z1 (loop for s across *solids* maximize (aref s 5)))
               (columns (make-array (list (1+ (floor (- x1 x0) size)) (1+ (floor (- z1 z0) size)))
                                    :initial-element ())))
          (loop for s across *solids*
                do (loop for i from (floor (- (aref s 0) x0) size) to (floor (- (aref s 3) x0) size)
                         do (loop for k from (floor (- (aref s 2) z0) size) to (floor (- (aref s 5) z0) size)
                                  do (push s (aref columns i k)))))
          (dotimes (i (array-total-size columns))
            (setf (row-major-aref columns i) (coerce (nreverse (row-major-aref columns i)) 'simple-vector)))
          (setf *solid-columns* columns *solid-columns-of* *solids* *solid-columns-count* n
                *solid-columns-x0* (float x0 0f0) *solid-columns-z0* (float z0 0f0))))))

(defun solid-columns-current-p ()
  (and *solid-columns* (eq *solid-columns-of* *solids*) (= *solid-columns-count* (length *solids*))))

(defmacro do-solids-near ((s x0 z0 x1 z1) &body body)
  "Run BODY with S bound to every solid that may reach into the XZ rectangle X0 Z0 X1 Z1
(single-floats): those filed under the columns it touches, or every solid when *SOLIDS*
isn't indexed. A solid in two of those columns comes up twice."
  (let ((columns (gensym "COLUMNS")) (i (gensym "I")) (k (gensym "K")) (size (gensym "SIZE")))
    `(flet ((visit (,s)
              (declare (type (simple-array single-float (*)) ,s))
              ,@body))
       (declare (inline visit))
       (if (solid-columns-current-p)
           (let ((,columns *solid-columns*) (,size *solid-column*))
             (declare (type (simple-array T (* *)) ,columns))
             (loop for ,i from (max 0 (floor (- ,x0 *solid-columns-x0*) ,size))
                     to (min (1- (array-dimension ,columns 0)) (floor (- ,x1 *solid-columns-x0*) ,size))
                   do (loop for ,k from (max 0 (floor (- ,z0 *solid-columns-z0*) ,size))
                              to (min (1- (array-dimension ,columns 1)) (floor (- ,z1 *solid-columns-z0*) ,size))
                            do (loop for ,s across (the simple-vector (aref ,columns ,i ,k))
                                     do (visit ,s)))))
           (loop for ,s across *solids* do (visit ,s))))))

(defun solid-overlapping (x y z half-width height)
  "The first solid overlapped by an upright box standing at X Y Z, HALF-WIDTH out from
its centre line on X and Z and HEIGHT tall, or NIL. Touching faces don't count."
  (let ((x (float x 0f0)) (y (float y 0f0)) (z (float z 0f0))
        (r (float half-width 0f0)) (h (float height 0f0)))
    (do-solids-near (s (- x r) (- z r) (+ x r) (+ z r))
      (when (%box-overlaps-p s x y z r h)
        (return-from solid-overlapping s)))
    NIL))

(defun floor-footing (x y z &optional (radius 0.0))
  "The footing of the floor whose top is at Y under the point X Z, as SOLID-FOOTING, or NIL.
As in Hexen, the point decides; but a body RADIUS out from it standing on a ledge's edge,
with nothing at Y under its centre, stands on that ledge's."
  (let ((x (float x 0f0)) (y (float y 0f0)) (z (float z 0f0)) (r (float radius 0f0))
        (edge NIL))
    (do-solids-near (s (- x r) (- z r) (+ x r) (+ z r))
      (when (< (abs (- (aref s 4) y)) 0.02)
        (cond ((solid-covers-p s x z)
               (return-from floor-footing (solid-footing s)))
              ((and (not edge) (< 0 r) (%box-overlaps-p s x (- y 0.05) z r 0.1))
               (setf edge s)))))
    (and edge (solid-footing edge))))

(defun add-box (container x0 y0 z0 x1 y1 z1
                &key surface (color (if surface (vec 1 1 1) (vec 0.6 0.6 0.6))) (solid T))
  "Add a box spanning the two corners, in metres, to CONTAINER. SURFACE (a name in
*SURFACES*) textures it, tinted by COLOR; without one it is flat COLOR. A surface with a
footing (*FOOTINGS*) gives the solid that footing."
  (let ((box (make-solid x0 y0 z0 x1 y1 z1 0 (surface-footing surface)))
        (textures (and surface (or (surface-textures surface) (error "No surface called ~s." surface)))))
    (when solid (vector-push-extend box *solids*))
    (let ((location (vec (/ (+ (aref box 0) (aref box 3)) 2)
                         (/ (+ (aref box 1) (aref box 4)) 2)
                         (/ (+ (aref box 2) (aref box 5)) 2)))
          (scaling (vec (- (aref box 3) (aref box 0))
                        (- (aref box 4) (aref box 1))
                        (- (aref box 5) (aref box 2)))))
      ;; Its twin on the automap (automap.lisp).
      (add-map-piece container (// 'trial 'unit-cube) location (quat) scaling
                     (vec (aref box 0) (aref box 1) (aref box 2)) (vec (aref box 3) (aref box 4) (aref box 5))
                     :surface surface :color color)
      (enter (make-instance 'greybox
                            :color (vec4 (vx color) (vy color) (vz color) 1)
                            :face-textures textures
                            :location location
                            :scaling scaling)
             container))))
