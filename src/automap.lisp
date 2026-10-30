(in-package #:hexmaw)

;;; The automap's model, Daggerfall style: the level's own geometry, drawn again by a
;;; map shader. Every box the level draws (ADD-BOX, a block's pieces, a liquid's surface)
;;; gets a MAP-PIECE twin sharing its vertex array and transform, which only the map
;;; camera sees (map-view.lisp). A placed block is a MAP-BLOCK: its pieces show once the
;;; player has stood inside it. Pieces of no block (the test level's boxes, the gallery's
;;; ground) always show.

(defvar *map-debug* NIL
  "The debug minimap (a Settings checkbox in a debug version): every block revealed,
creature markers and block labels.")

(defun map-debug-p ()
  (and *debug-version* *map-debug*))

(defclass map-block ()
  ((name :initarg :name :reader map-block-name)
   (low :initarg :low :reader map-block-low :documentation "Min corner of its bounds, walls and all.")
   (high :initarg :high :reader map-block-high)
   (revealed :initform NIL :accessor revealed)))

(defmethod print-object ((block map-block) stream)
  (print-unreadable-object (block stream :type T)
    (format stream "~a~:[~; revealed~]" (map-block-name block) (revealed block))))

(defvar *map-blocks* (make-array 0 :adjustable T :fill-pointer T)
  "Every placed block, in placement order (fixed by a generated level's seed, so a save
names them by index). BUILD-LEVEL empties it.")

(defvar *map-block* NIL "The block whose pieces are being entered, or NIL for none.")

(defun add-map-block (name low high)
  (let ((block (make-instance 'map-block :name (string-downcase name) :low (vcopy low) :high (vcopy high))))
    (vector-push-extend block *map-blocks*)
    block))

(defun map-block-at (x y z)
  "The placed block whose bounds hold X Y Z, or NIL."
  (loop for block across *map-blocks*
        for low = (map-block-low block)
        for high = (map-block-high block)
        when (and (<= (vx low) x (vx high)) (<= (vy low) y (vy high)) (<= (vz low) z (vz high)))
          return block))

(defun reveal-map-at (point)
  "Reveal the block POINT stands in, if any."
  (let ((block (map-block-at (vx point) (+ (vy point) 0.1) (vz point))))
    (when (and block (not (revealed block)))
      (setf (revealed block) T))))

(defun clear-map-reveals ()
  (loop for block across *map-blocks* do (setf (revealed block) NIL)))

(defun revealed-block-indices ()
  (loop for block across *map-blocks*
        for i from 0
        when (revealed block) collect i))

(defun storey-at (y)
  "The storey whose floor is under height Y: storey k's floor is at 5k, on a slab from 5k - 0.5."
  (floor (+ y 0.5) hexmaw.blueprint:*storey-height*))

(defun map-storey-range ()
  "The lowest and highest storey of the blocks the map shows, or NIL if it shows none. A
block's bounds start under its floor slab and end on its ceiling slab."
  (let ((low NIL) (high NIL))
    (loop for block across *map-blocks*
          when (or (revealed block) (map-debug-p))
            do (let ((a (storey-at (vy (map-block-low block))))
                     (b (storey-at (- (vy (map-block-high block)) 1.0))))
                 (setf low (if low (min low a) a)
                       high (if high (max high b) b))))
    (values low high)))

(defun reveal-block-indices (indices)
  (dolist (i indices)
    (when (< -1 i (length *map-blocks*))
      (setf (revealed (aref *map-blocks* i)) T))))

;;; Pieces.

(defparameter *map-colors*
  '((:wall 0.46 0.41 0.36) (:pillar 0.46 0.41 0.36) (:stone 0.50 0.46 0.40) (:beam 0.48 0.36 0.24)
    (:sarcophagus 0.52 0.48 0.42)
    (:floor 0.64 0.60 0.52) (:ceiling 0.64 0.60 0.52) (:dais 0.70 0.64 0.52) (:platform 0.62 0.50 0.34)
    (:stair 0.76 0.60 0.34)
    (:lava 1.00 0.42 0.08))
  "Map colours by surface (or liquid kind). Anything else keeps its own colour.")
(defparameter *map-cut-height* 2.0 "Metres above each storey's floor where the map cuts the level open.")
(defparameter *map-cut-color* (vec 0.88 0.82 0.66) "The cut faces of walls.")
(defparameter *map-depth-fade* 0.5 "How much each storey below the shown one keeps of its brightness.")
(defparameter *map-grid-strength* 0.18 "Darkness of the 1 m grid on floors, when zoomed in enough to see it.")
(defparameter *map-ghost-color* (vec 0.50 0.58 0.75) "The storey above the shown one, drawn as a ghost.")
(defparameter *map-ghost-stipple* 4 "The ghost keeps 1 pixel in this many.")
(defvar *map-eye* (vec 0 0 0) "Where the map camera is (map-view.lisp), for the caps.")

(defun map-color (surface color)
  (let ((entry (and surface (assoc surface *map-colors* :test #'string-equal))))
    (if entry
        (vec4 (second entry) (third entry) (fourth entry) 1)
        (vec4 (vx color) (vy color) (vz color) 1))))

(define-shader-entity map-piece (vertex-entity colored-entity transformed-entity)
  ((map-block :initarg :map-block :initform NIL :reader map-block)
   (low :initarg :low :initform (vec 0 0 0) :reader piece-low :documentation "Min corner of its box, in world space.")
   (high :initarg :high :initform (vec 0 0 0) :reader piece-high)
   (cut :initarg :cut :initform (vec 0 0 0) :reader piece-cut
        :documentation "A wedge's cut-away corner as (east south 1), 0 or 1 each; all 0 for a box."))
  (:documentation "A box of the level as the automap draws it."))

(defun add-map-piece (container vertex-array location orientation scaling low high
                      &key surface (color (vec 0.6 0.6 0.6)) (cut 0))
  "Enter a map twin of a piece of level geometry into CONTAINER, belonging to *MAP-BLOCK*.
LOW and HIGH are the corners of its box in world space; CUT is the corner a wedge has cut
away as it lies (1 to 4, see MAKE-SOLID), or 0 for a box. SURFACE (a surface or liquid
name) picks its colour from *MAP-COLORS*, else COLOR."
  (enter (make-instance 'map-piece :vertex-array vertex-array
                                   :map-block *map-block*
                                   :low (vmin low high) :high (vmax low high)
                                   :cut (if (= 0 cut)
                                            (vec 0 0 0)
                                            (multiple-value-bind (east south) (cut-sides cut)
                                              (vec east south 1)))
                                   :color (map-color surface color)
                                   :location (vcopy location)
                                   :orientation (qcopy orientation)
                                   :scaling (vcopy scaling))
         container))

(defvar *map-focus-storey* 0 "The storey the map shows cut open; those below are darkened.")

(defmethod render :around ((piece map-piece) (program shader-program))
  ;; A cut box shows its inside, which the shader caps; that needs its back faces.
  (gl:disable :cull-face)
  (unwind-protect (call-next-method)
    (gl:enable :cull-face)))

(defmethod render :before ((piece map-piece) (program shader-program))
  (let ((storey hexmaw.blueprint:*storey-height*))
    (setf (uniform program "focus_storey") (float *map-focus-storey* 0f0))
    (setf (uniform program "cut_height") (float *map-cut-height* 0f0))
    (setf (uniform program "storey_height") (float storey 0f0))
    (setf (uniform program "depth_fade") (float *map-depth-fade* 0f0))
    (setf (uniform program "grid_strength") (float *map-grid-strength* 0f0))
    (setf (uniform program "cut_color") *map-cut-color*)
    (setf (uniform program "ghost_color") *map-ghost-color*)
    (setf (uniform program "ghost_stipple") (max 1 (round *map-ghost-stipple*)))
    (setf (uniform program "map_eye") *map-eye*)
    (setf (uniform program "piece_low") (piece-low piece))
    (setf (uniform program "piece_high") (piece-high piece))
    (setf (uniform program "piece_cut") (piece-cut piece))))

(define-class-shader (map-piece :fragment-shader)
  "in vec3 v_world_position;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;
uniform vec3 map_eye;
uniform vec3 piece_low;
uniform vec3 piece_high;
uniform vec3 piece_cut;
uniform vec3 ghost_color;
uniform int ghost_stipple;
uniform float focus_storey;
uniform float cut_height;
uniform float storey_height;
uniform float depth_fade;
uniform float grid_strength;
uniform vec3 cut_color;
out vec4 color;

void main(){
  maybe_call_next_method();
  vec3 p = v_world_position;
  // A storey starts with its floor slab, half a metre under its floor. The top of a wall
  // standing under the slab above is still its own storey's, and nothing is below the storey
  // its piece starts in: a wall on storey 0 reaches down through the slab to -0.5.
  float storey = max(floor((p.y + 0.49) / storey_height), floor((piece_low.y + 0.51) / storey_height));
  float cut = storey * storey_height + cut_height;
  // Every storey is cut open at the same height over its floor, so the ones below show
  // as floor plans, not roofs. The one above the shown one is a ghost; the rest are gone.
  bool ghost = storey == focus_storey + 1.0;
  if(storey > focus_storey + 1.0 || cut < p.y) discard;
  // The ghost: its outside only, on a sparse pattern of pixels, which needs no draw order.
  if(ghost && (!gl_FrontFacing || (int(gl_FragCoord.x) + 2 * int(gl_FragCoord.y)) % ghost_stipple != 0)) discard;
  gl_FragDepth = gl_FragCoord.z;
  float fade = pow(depth_fade, max(focus_storey - storey, 0.0));
  // Through the cut, the inside of a box: draw it as the cut face, and at the cut plane it
  // is seen through rather than where it lies, so nothing inside the box (the floor a
  // pillar stands on) can lie level with it and flicker. Only where the line of sight
  // crosses the plane over the piece's own top (a box's, or a wedge's but the corner it has
  // cut away): elsewhere the inside is seen through a side, which hides it. A piece under the
  // cut has no inside to see, and seen from under the plane there's no cut face.
  if(!gl_FrontFacing){
    if(cut < piece_high.y && cut < map_eye.y){
      vec3 q = map_eye + (p - map_eye) * ((cut - map_eye.y) / (p.y - map_eye.y));
      vec2 uv = (q.xz - piece_low.xz) / max(piece_high.xz - piece_low.xz, vec2(0.0001));
      bool on_top = all(greaterThanEqual(uv, vec2(-0.001))) && all(lessThanEqual(uv, vec2(1.001)))
                    && (piece_cut.z == 0.0 || 0.999 <= abs(uv.x - piece_cut.x) + abs(uv.y - piece_cut.y));
      if(on_top){
        vec4 clip = projection_matrix * view_matrix * vec4(q, 1.0);
        gl_FragDepth = clamp(clip.z / clip.w * 0.5 + 0.5, 0.0, 1.0);
      }
    }
    color = vec4(cut_color * fade, 1.0);
    return;
  }
  vec3 n = abs(normalize(cross(dFdx(p), dFdy(p))));
  float shade = n.y * 1.0 + n.x * 0.75 + n.z * 0.6;
  if(ghost){
    color = vec4(ghost_color * shade, 1.0);
    return;
  }
  if(n.y > 0.5){
    // A 1 m grid on floors, gone once a metre is under a few pixels.
    vec2 w = max(fwidth(p.xz), vec2(0.0001));
    vec2 g = abs(fract(p.xz + 0.5) - 0.5) / w;
    float line = 1.0 - min(min(g.x, g.y), 1.0);
    shade *= 1.0 - grid_strength * line * clamp(1.0 - 4.0 * max(w.x, w.y), 0.0, 1.0);
  }
  color = vec4(color.rgb * shade * fade, 1.0);
}")
