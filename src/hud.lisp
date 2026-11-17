(in-package #:hexmaw)

;;; Heads-up display: health, mana and stamina in the lower-left corner, each a label, a
;;; bar and the numbers, breath above them while it is short, and the frame counter in the upper-left when it's on. HUD elements are ordinary scene entities drawn with a
;;; pixel-space orthographic projection at the near plane, so they stay on top
;;; whatever order the scene draws in. Text is Jersey 15, the menus' typeface, from a bitmap of it
;;; drawn at its own pixel grid (HUD-TEXT).

(defparameter *hud-margin* 16 "Pixels from the window's left and bottom edges.")
(defparameter *hud-pixel-rows* 360
  "Window rows per HUD art pixel: the bars, slots and icons are drawn in art pixels
HUD-PIXEL-SCALE screen pixels across, 2 at 720 rows and 3 at 1080, so they keep the size of
the rest of the art's pixels as the window grows (the weapons' are 3 and 5).")
(defparameter *hud-bar-width* 64 "Art pixels across a bar, its frame included.")
(defparameter *hud-bar-height* 7 "Art pixels up a bar, its frame included.")
(defparameter *hud-row-gap* 6)
(defparameter *hud-text-color* (vec4 0.87 0.81 0.67 1))
;; The bars' colours are a ramp's middle tone: the shader lights the top row and darkens the bottom.
(defparameter *health-bar-color* (vec4 0.54 0.14 0.10 1))
(defparameter *mana-bar-color* (vec4 0.20 0.28 0.56 1))
(defparameter *stamina-bar-color* (vec4 0.26 0.44 0.17 1))
(defparameter *breath-bar-color* (vec4 0.42 0.58 0.66 1))
(defparameter *hud-bar-back-color* (vec4 0.17 0.13 0.11 0.9))
(defparameter *hud-frame-color* (vec4 0.07 0.05 0.04 1) "The dark frame round bars and slots.")

(defun hud-pixel-scale ()
  "Screen pixels across a HUD art pixel at the window's size."
  (max 1 (round (height *context*) *hud-pixel-rows*)))

(defparameter *glyph-height* 23
  "Pixels a line of HUD text stands, its shadow included: the HUD font's row (data/fonts/hud-font).")

(define-shader-entity hud-element () ())

(defgeneric hud-shown-p (element)
  (:documentation "Whether ELEMENT draws this frame."))

(defmethod hud-shown-p ((element hud-element))
  ;; No HUD on the main menu; the pause menu dims it instead.
  (not (eq *game-state* :title)))

(defmethod render :around ((element hud-element) (program shader-program))
  (when (hud-shown-p element)
    (with-pushed-matrix ((view-matrix :identity)
                         (projection-matrix :identity))
      ;; Pixel coordinates with the origin at the bottom left; z 0 is the near plane.
      (orthographic-projection 0 (width *context*) 0 (height *context*) 0 10)
      (call-next-method))))

(defun place (entity x y &optional (z 0))
  "Put ENTITY at pixel X, Y. Z below 0 (down to -10) puts it behind elements nearer 0."
  (let ((loc (location entity)))
    (setf (vx loc) (float x 0f0) (vy loc) (float y 0f0) (vz loc) (float z 0f0))))

;;; Bars.

(define-asset (hexmaw hud-quad) mesh
    (make-rectangle-mesh 1 1 :align :bottomleft))

(define-shader-entity hud-bar (hud-element vertex-entity transformed-entity)
  ((vertex-array :initform (// 'hexmaw 'hud-quad))
   (fill-fraction :initform 1.0 :accessor fill-fraction)
   (fill-color :initarg :fill-color :initform (vec4 1 1 1 1) :accessor fill-color)
   (art-size :initform (vec2 *hud-bar-width* *hud-bar-height*) :reader art-size
             :documentation "Art pixels across and up, the frame included.")))

(defun size-bar (bar width height)
  "Make BAR WIDTH by HEIGHT art pixels, drawn at HUD-PIXEL-SCALE."
  (let ((k (float (hud-pixel-scale) 0f0)))
    (vsetf (art-size bar) width height)
    (setf (vx (scaling bar)) (* k width)
          (vy (scaling bar)) (* k height))))

(defmethod render :before ((bar hud-bar) (program shader-program))
  (setf (uniform program "fill_fraction") (float (fill-fraction bar) 0f0))
  (setf (uniform program "fill_color") (fill-color bar))
  (setf (uniform program "back_color") *hud-bar-back-color*)
  (setf (uniform program "frame_color") *hud-frame-color*)
  (setf (uniform program "art_size") (art-size bar)))

(define-class-shader (hud-bar :vertex-shader)
  "layout (location = TRIAL_V_UV) in vec2 in_uv;
out vec2 bar_uv;

void main(){
  maybe_call_next_method();
  bar_uv = in_uv;
}")

(define-class-shader (hud-bar :fragment-shader)
  "in vec2 bar_uv;
uniform float fill_fraction;
uniform vec4 fill_color;
uniform vec4 back_color;
uniform vec4 frame_color;
uniform vec2 art_size;
out vec4 color;

void main(){
  // Worked out per art pixel, so the bar is drawn in whole art pixels at any scale.
  vec2 px = min(floor(bar_uv * art_size), art_size - 1.0);
  bool frame = px.x < 1.0 || px.y < 1.0 || art_size.x - 1.0 <= px.x || art_size.y - 1.0 <= px.y;
  bool filled = px.x - 1.0 < floor(fill_fraction * (art_size.x - 2.0) + 0.5);
  color = filled ? fill_color : back_color;
  // Three tones of the fill's ramp, so it reads as a solid bar lit from above.
  if(filled && art_size.y - 2.0 <= px.y) color.rgb = min(color.rgb * 1.32, 1.0);
  if(filled && px.y < 2.0) color.rgb *= 0.68;
  if(frame) color = frame_color;
}")

;;; Text. Jersey 15 drawn at the size where its outlines fall on whole pixels (27 px, one
;;; screen pixel per font pixel at any window size): scaled, or at another size, its strokes came
;;; out of uneven widths. tools/make_hud_font.py draws the bitmap, its glyphs in red and their
;;; shadows in green, a row *GLYPH-HEIGHT* tall; its index gives each glyph's cell and advance.
;;; A HUD-TEXT is Trial's DEBUG-TEXT (its vertex layout, so subclasses such as the map's overlays
;;; keep working) with this font, laid out by advance instead of in 9-pixel cells.

(define-asset (hexmaw hud-font) image
    #p"fonts/hud-font.png"
  :min-filter :nearest :mag-filter :nearest)

(defvar *hud-font* NIL "The HUD font's index: (:image :height :first :glyphs), read once.")

(defun hud-font ()
  (or *hud-font* (setf *hud-font* (read-atlas "fonts/hud-font.lisp"))))

(defparameter *hud-shadow-color* (vec3 0.07 0.05 0.04) "The colour of HUD text's shadow.")

(defun glyph-metrics (char)
  "CHAR's cell in the HUD font: its x, width and advance; a character it lacks as a space."
  (let* ((font (hud-font))
         (glyphs (getf font :glyphs))
         (i (- (char-code char) (getf font :first))))
    (values-list (aref glyphs (if (< -1 i (length glyphs)) i 0)))))

(defun text-width (string)
  "Pixels STRING's longest line takes across in HUD text."
  (let ((widest 0) (x 0))
    (loop for char across string
          do (if (char= char #\Linefeed)
                 (setf widest (max widest x) x 0)
                 (incf x (nth-value 2 (glyph-metrics char)))))
    (max widest x)))

(define-shader-entity hud-text (hud-element debug-text)
  ((texture :initform (// 'hexmaw 'hud-font)))
  (:inhibit-shaders (debug-text :fragment-shader)))

(defun print-hud-text (string array)
  "Fill ARRAY (adjustable single floats) with STRING's quads, as PRINT-ASCII-TEXT lays its own:
x y z u v per vertex, two triangles a glyph, lines *GLYPH-HEIGHT* apart downward. Returns the
floats written, the width and the height."
  (adjust-array array (* 5 6 (count #\Linefeed string :test-not #'char=)))
  (let ((i 0) (x 0.0) (y 0.0) (widest 0.0)
        (h (float *glyph-height* 0f0)))
    (flet ((vertex (&rest values)
             (dolist (v values)
               (setf (aref array i) (float v 0f0))
               (incf i))))
      (loop for char across string
            do (if (char= char #\Linefeed)
                   (setf widest (max widest x) x 0.0 y (- y h))
                   (multiple-value-bind (u w advance) (glyph-metrics char)
                     (let ((x1 (+ x w)) (u1 (+ u w)))
                       (vertex x y 0 u 0  x1 y 0 u1 0  x1 (+ y h) 0 u1 h
                               x1 (+ y h) 0 u1 h  x (+ y h) 0 u h  x y 0 u 0))
                     (incf x advance)))))
    (values i (max widest x) (- y))))

(defmethod (setf text) :around (value (text hud-text))
  ;; Instead of DEBUG-TEXT's layout in its own 9 x 17 cells.
  (setf (slot-value text 'text) value)
  (let* ((vao (vertex-array text))
         (vbo (caar (bindings vao)))
         (array (buffer-data vbo)))
    (multiple-value-bind (i w h) (print-hud-text value array)
      (vsetf (size text) w h)
      (setf (size vao) (truncate i 5)))
    (when (allocated-p vao)
      (resize-buffer-data vbo (* 4 (length array)) :data array)))
  value)

(defmethod render :before ((text hud-text) (program shader-program))
  (setf (uniform program "shadow_color") *hud-shadow-color*))

(define-class-shader (hud-text :fragment-shader)
  "in vec2 uv;
out vec4 color;
uniform sampler2D texture_image;
uniform vec4 foreground;
uniform vec3 shadow_color;

void main(){
  vec4 glyph = texture(texture_image, uv, 0);
  if(0.5 < glyph.r) color = foreground;
  else if(0.5 < glyph.g) color = vec4(shadow_color, foreground.a);
  else discard;
}")

;;; Breath: a bar over the others, only while the player has less than a full breath.

(define-shader-entity breath-element () ())

(defun breath-shown-p ()
  (and *player* (< (breath *player*) *breath-time*)))

(defmethod hud-shown-p ((element breath-element))
  (and (call-next-method) (breath-shown-p)))

(define-shader-entity breath-bar (breath-element hud-bar) ())
(define-shader-entity breath-text (breath-element hud-text) ())

(defun wrap-text (text width)
  "TEXT broken at spaces into lines of at most WIDTH characters, a word longer than that on a
line of its own. Lines after the first keep the first's indent."
  (let* ((indent (or (position #\Space text :test-not #'char=) 0))
         (prefix (subseq text 0 indent))
         (words (loop with start = indent
                      for space = (position #\Space text :start start)
                      for word = (subseq text start space)
                      unless (string= word "") collect word
                      while space do (setf start (1+ space))))
         (lines ())
         (line prefix))
    (dolist (word words)
      (cond ((= (length line) (length prefix))
             (setf line (concatenate 'string line word)))
            ((<= (+ (length line) 1 (length word)) width)
             (setf line (concatenate 'string line " " word)))
            (T
             (push line lines)
             (setf line (concatenate 'string prefix word)))))
    (nreverse (cons line lines))))

(defun make-hud-text (&optional (text "") (class 'hud-text))
  (make-instance class :text text :font-size (float *glyph-height* 0f0)
                           :foreground *hud-text-color* :background (vec4 0 0 0 0)))

;;; Frame counter: frames drawn per second, in the upper-left corner, when the
;;; settings menu's Show FPS is on.

(defvar *show-fps* NIL "Show the frame counter. The settings menu (menu.lisp) toggles it.")
(defparameter *fps-interval* 0.5 "Seconds of frames the counter averages over between updates.")

(defvar *frame-timing* (make-array 3 :element-type '(unsigned-byte 62) :initial-element 0)
  "Since the counter last updated: internal time spent in ticks (MAIN's UPDATE), in rendering
(MAIN's RENDER), and the ticks run. Kept by main.lisp, shown by the frame counter, so a slow
machine shows whether the frame goes to drawing or to the fixed step catching up.")

(define-shader-entity fps-display (hud-text)
  ((frames :initform 0 :accessor frames)
   (since :initform 0 :accessor since :documentation "Internal real time the count started.")))

;; On every screen, menus included: what the menus cost to draw is worth seeing too.
(defmethod hud-shown-p ((display fps-display))
  *show-fps*)

(defmethod render :before ((display fps-display) (program shader-program))
  ;; Render runs once a frame (the tick runs at a fixed rate), so count here.
  (let* ((now (get-internal-real-time))
         (elapsed (/ (- now (since display)) (float internal-time-units-per-second))))
    (incf (frames display))
    (when (<= *fps-interval* elapsed)
      ;; A longer gap means the counter was hidden: start over rather than show it.
      (when (< elapsed (* 2 *fps-interval*))
        (let ((timing *frame-timing*)
              (frames (frames display))
              (ms (/ 1000.0 internal-time-units-per-second)))
          (setf (text display)
                (format NIL "~d FPS  tick ~,1f ms x~,1f  draw ~,1f ms"
                        (round frames elapsed)
                        (/ (* ms (aref timing 0)) frames)
                        (/ (aref timing 2) frames)
                        (/ (* ms (aref timing 1)) frames)))))
      (fill *frame-timing* 0)
      (setf (frames display) 0
            (since display) now))))

;;; Pain: the whole view flashes red when the player is hurt.

(defparameter *pain-color* (vec4 0.75 0.0 0.0 0.4) "RGB and peak opacity of the pain flash.")

(define-shader-entity pain-flash (hud-element vertex-entity transformed-entity)
  ((vertex-array :initform (// 'hexmaw 'hud-quad))
   (strength :initform 0.0 :accessor strength :documentation "0 to 1.")))

(defmethod render :around ((flash pain-flash) (program shader-program))
  ;; Writing depth would hide whatever the scene draws after it, such as projectiles.
  (when (< 0 (strength flash))
    (with-depth-mask NIL
      (call-next-method))))

(defgeneric flash-color (flash))

(defmethod flash-color ((flash pain-flash)) *pain-color*)

(defmethod render :before ((flash pain-flash) (program shader-program))
  (let ((c (flash-color flash)))
    (setf (uniform program "pain_color") (vec4 (vx c) (vy c) (vz c) (* (vw c) (strength flash))))))

(define-class-shader (pain-flash :fragment-shader)
  "uniform vec4 pain_color;
out vec4 color;

void main(){
  color = pain_color;
}")

;;; A pickup restoring something flashes the view the same way, in that resource's colour.

(defparameter *health-flash-color* (vec4 0.75 0.7 0.15 0.25) "RGB and peak opacity of a health pickup's flash.")
(defparameter *mana-flash-color* (vec4 0.15 0.35 1.0 0.25) "RGB and peak opacity of a mana pickup's flash.")
(defparameter *stolen-flash-color* (vec4 0.22 0.05 0.3 0.35)
  "RGB and peak opacity of the flash when an imp snatches an item (imp.lisp).")

(defparameter *rift-flash-color* (vec4 0.55 0.65 1.0 0.45)
  "RGB and peak opacity of the flash when a riftwalker's rift moves the player (riftwalker.lisp).")

(define-shader-entity restore-flash (pain-flash) ())

(defparameter *gold-flash-color* (vec4 0.9 0.65 0.1 0.18) "RGB and peak opacity of gold's flash.")

(defparameter *ward-flash-color* (vec4 0.7 0.5 1.0 0.25) "RGB and peak opacity of a ward's flash (magic.lisp).")
(defparameter *absorb-flash-color* (vec4 0.3 0.55 1.0 0.35)
  "RGB and peak opacity of the flash of a projectile an Absorb takes (magic.lisp).")
(defparameter *glyph-flash-color* (vec4 1.0 0.8 0.3 0.3) "RGB and peak opacity of a glyph's flash (pickups.lisp).")
(defparameter *dust-flash-color* (vec4 0.75 0.5 1.0 0.25) "RGB and peak opacity of picking up arcane dust.")

(defmethod flash-color ((flash restore-flash))
  (case (and *player* (restored *player*))
    (:mana *mana-flash-color*)
    (:stolen *stolen-flash-color*)
    (:gold *gold-flash-color*)
    (:ward *ward-flash-color*)
    (:absorb *absorb-flash-color*)
    (:glyph *glyph-flash-color*)
    (:dust *dust-flash-color*)
    (:rift *rift-flash-color*)
    (T *health-flash-color*)))

;;; Veils: a lasting effect on the player shows at the screen's edges while it lasts, faint, and
;;; flares as it acts: a ward's honeycomb along the left and right edges, flaring as it takes a
;;; blow; the priest's blessing as rays of light in the corners, flaring as it lessens one and
;;; blinking out over its last seconds; healing over time as motes rising along the bottom edge,
;;; flaring at each heal. Each is a tile of tools/draw_status_veils.py's strip repeated over its
;;; part of the edge, fading inward in steps, at the HUD's art pixel size; a whole-screen quad
;;; whose fragment shader lays it out, so it never covers the middle of the view.

(define-asset (hexmaw veils) image #p"sprites/veils/veils.png"
  :min-filter :nearest :mag-filter :nearest)

(defparameter *veil-kinds* '(:ward :bless :heal) "The veils, in the strip's order, two tiles each.")
(defparameter *veil-tile* 32 "HUD art pixels across a veil's tile.")
(defparameter *veil-gap* 2 "Pixels between the strip's tiles.")
(defparameter *veil-band* '(:ward 48 :bless 80 :heal 40)
  "HUD art pixels in from its edge or corner a veil reaches, fading in four steps.")
(defparameter *veil-alpha* 0.45 "A resting veil's opacity at the edge.")
(defparameter *veil-flare-alpha* 0.85 "A flared veil's opacity at the edge.")
(defparameter *veil-flare-time* 0.3 "Seconds a veil shows flared after its effect acts.")
(defparameter *veil-warn-time* 3.0 "Seconds of the blessing left from which its veil blinks.")
(defparameter *veil-rise* 10.0 "HUD art pixels a second healing's motes rise.")

(defvar *veil-flares* (list :ward 0.0 :bless 0.0 :heal 0.0) "Seconds each veil still shows flared.")

(defun flare-veil (kind)
  "KIND's effect just acted on the player: its veil flares."
  (setf (getf *veil-flares* kind) *veil-flare-time*))

(define-shader-entity status-veil (hud-element vertex-entity transformed-entity)
  ((vertex-array :initform (// 'hexmaw 'hud-quad))
   (kind :initarg :kind :reader veil-kind)
   (strength :initform 0.0 :accessor strength :documentation "0 to 1: how much of it shows.")
   (clock :initform 0.0 :accessor veil-clock)))

(defmethod stage :after ((veil status-veil) (area staging-area))
  (stage (// 'hexmaw 'veils) area))

(defmethod bind-textures :after ((veil status-veil))
  (bind (// 'hexmaw 'veils) :texture0))

(defmethod hud-shown-p ((veil status-veil))
  (and (call-next-method) (< 0 (strength veil)) (member *game-state* '(:playing :inventory :paused))))

(defmethod render :around ((veil status-veil) (program shader-program))
  (with-depth-mask NIL
    (call-next-method)))

(defmethod render :before ((veil status-veil) (program shader-program))
  (let ((kind (veil-kind veil)))
    (setf (uniform program "veils") 0
          (uniform program "kind") (position kind *veil-kinds*)
          (uniform program "band") (float (getf *veil-band* kind) 0f0)
          (uniform program "scale") (float (hud-pixel-scale) 0f0)
          (uniform program "screen") (vec2 (width *context*) (height *context*))
          (uniform program "tile") *veil-tile*
          (uniform program "gap") *veil-gap*
          (uniform program "rise") (float (* *veil-rise* (veil-clock veil)) 0f0)
          (uniform program "flared") (if (< 0 (getf *veil-flares* kind)) 1 0)
          (uniform program "alpha") (float (* (strength veil)
                                              (if (< 0 (getf *veil-flares* kind)) *veil-flare-alpha* *veil-alpha*))
                                           0f0))))

(define-class-shader (status-veil :fragment-shader)
  "uniform sampler2D veils;
uniform int kind;
uniform float band;
uniform float scale;
uniform vec2 screen;
uniform int tile;
uniform int gap;
uniform float rise;
uniform int flared;
uniform float alpha;
out vec4 color;

void main(){
  // Whole HUD art pixels, counted from the bottom left.
  vec2 size = floor(screen / scale);
  vec2 a = floor(gl_FragCoord.xy / scale);
  vec2 edge = min(a, size - 1.0 - a);
  float d;
  vec2 t = a;
  if(kind == 0) d = edge.x;                       // the left and right edges
  else if(kind == 1) d = length(edge);            // the corners
  else { d = a.y; t.y = a.y - floor(rise); }      // the bottom edge, rising
  if(band <= d) discard;
  float fade = 1.0 - floor(4.0 * d / band) / 4.0;
  // The texture's rows run up from the image's bottom, as the screen's do.
  ivec2 texel = ivec2(int(mod(t.x, float(tile))), int(mod(t.y, float(tile))));
  texel.x += (kind * 2 + flared) * (tile + gap);
  vec4 c = texelFetch(veils, texel, 0);
  if(c.a < 0.5) discard;
  color = vec4(c.rgb, alpha * fade);
}")

;;; Under water: the whole view, the hands with it, turned blue. The colour multiplies what
;;; is drawn, so the darks stay dark. Drawn after the water's see-through surface (LATE-RANK),
;;; behind the bars like the pain flash.

(defparameter *underwater-tint* (vec 0.45 0.68 1.0) "What the view is multiplied by under water.")

(define-shader-entity underwater-tint (hud-element vertex-entity transformed-entity)
  ((vertex-array :initform (// 'hexmaw 'hud-quad))))

(defmethod hud-shown-p ((tint underwater-tint))
  (and (call-next-method) *eye-underwater* (not (eq *game-state* :map))))

(defmethod late-rank ((tint underwater-tint)) 1)

(defmethod render :around ((tint underwater-tint) (program shader-program))
  (with-depth-mask NIL
    (gl:blend-func :dst-color :zero)
    (unwind-protect (call-next-method)
      (gl:blend-func :src-alpha :one-minus-src-alpha))))

(defmethod render :before ((tint underwater-tint) (program shader-program))
  (setf (uniform program "tint_color") *underwater-tint*))

(define-class-shader (underwater-tint :fragment-shader)
  "uniform vec3 tint_color;
out vec4 color;

void main(){
  color = vec4(tint_color, 1.0);
}")

;;; In a vortex: chunky streaks of wind and dust rush across the view, thickest at its edges
;;; so the middle stays clear to aim through, and go on, thinner, while the player is
;;; thrown. From inside, the funnel alone is too close to read as anything (vortex.lisp).

(defparameter *streak-cell* 5.0 "Screen pixels on a side of a streak's chunky cells.")
(defparameter *streak-ease* 0.4 "Seconds in a vortex until the streaks are at full strength.")
(defparameter *streak-thrown* 0.6 "Their strength while thrown.")

(define-shader-entity whirl-streaks (hud-element vertex-entity transformed-entity listener)
  ((vertex-array :initform (// 'hexmaw 'hud-quad))
   (strength :initform 0.0 :accessor strength :documentation "0 to 1.")
   (clock :initform 0.0 :accessor streak-clock)))

(defmethod hud-shown-p ((streaks whirl-streaks))
  (and (call-next-method) (< 0 (strength streaks)) (not (eq *game-state* :map))))

(defmethod late-rank ((streaks whirl-streaks)) 1)

(define-handler (whirl-streaks tick) (dt)
  (when *player*
    (unless (frozen-p)
      (setf (streak-clock whirl-streaks) (mod (+ (streak-clock whirl-streaks) dt) 1000.0)))
    (setf (strength whirl-streaks)
          (cond ((whirl *player*) (min 1.0 (/ (whirl-time *player*) *streak-ease*)))
                ((flung *player*) *streak-thrown*)
                (T 0.0)))))

(defmethod render :around ((streaks whirl-streaks) (program shader-program))
  (with-depth-mask NIL
    (gl:blend-func :one :one-minus-src-alpha)
    (unwind-protect (call-next-method)
      (gl:blend-func :src-alpha :one-minus-src-alpha))))

(defmethod render :before ((streaks whirl-streaks) (program shader-program))
  (setf (uniform program "strength") (float (strength streaks) 0f0)
        (uniform program "time") (float (streak-clock streaks) 0f0)
        (uniform program "cell_size") (float *streak-cell* 0f0)
        (uniform program "screen") (vec2 (width *context*) (height *context*))))

(define-class-shader (whirl-streaks :fragment-shader)
  "uniform float strength;
uniform float time;
uniform float cell_size;
uniform vec2 screen;
out vec4 color;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void main(){
  vec2 cell = floor(gl_FragCoord.xy / cell_size);
  vec2 at = cell * cell_size / screen - 0.5;
  // A row of the wind, slanting a little; each runs at its own speed, broken into lengths.
  float row = cell.y + floor(cell.x * 0.12);
  float speed = 60.0 + 110.0 * hash(vec2(row, 1.0));
  float x = cell.x + time * speed + 500.0 * hash(vec2(row, 2.0));
  float piece = floor(x / (18.0 + 30.0 * hash(vec2(row, 3.0))));
  float on = step(0.82, hash(vec2(row, piece)));
  float edge = smoothstep(0.18, 0.62, length(at * vec2(1.0, 1.3)));
  float alpha = on * edge * strength * (0.35 + 0.5 * hash(vec2(row, 4.0)));
  vec3 c = mix(vec3(0.35, 0.31, 0.42), vec3(0.72, 0.68, 0.82), hash(vec2(row, 5.0)));
  color = vec4(c * alpha, alpha);
}")

;;; The level banner: which level of the run this is, on arriving.

(defparameter *level-banner-time* 3.0 "Seconds of play the banner stays up on arriving at a level.")
(defvar *level-banner-left* 0.0 "Seconds of play left of the banner.")

(define-shader-entity level-banner (hud-text) ())

;;; A message across the middle of the view for a few seconds of play: what a glyph taught, kill
;;; gold the bag had no room for, what the watch warns of (SHOW-MESSAGE, or HUD-SAY to format it).

(defparameter *message-time* 3.0 "Seconds of play a message stays up.")
(defvar *message-left* 0.0 "Seconds of play left of the message.")
(defvar *message* "" "The message SHOW-MESSAGE put up last.")

(define-shader-entity message-banner (hud-text) ())

(defmethod hud-shown-p ((banner message-banner))
  (and (eq *game-state* :playing) (< 0.0 *message-left*)))

(defun show-message (text)
  (setf *message* text
        *message-left* *message-time*))

;;; What a pickup of a counted item gave (dust's pile, coins), just above the crosshair for a
;;; moment: "+25 arcane dust". Pickups of one kind in quick succession add up.

(defparameter *pickup-note-time* 1.5 "Seconds of play a pickup's note stays up.")
(defparameter *pickup-note-height* 0.56 "Where its line stands, up the screen.")
(defvar *pickup-note* "" "The note NOTE-PICKUP put up last.")
(defvar *pickup-note-left* 0.0 "Seconds of play left of it.")
(defvar *pickup-note-kind* NIL "The item kind it counts.")
(defvar *pickup-note-count* 0 "How many of it the note says.")

(define-shader-entity pickup-banner (hud-text) ())

(defmethod hud-shown-p ((banner pickup-banner))
  (and (eq *game-state* :playing) (< 0.0 *pickup-note-left*)))

(defun note-pickup (kind count)
  "Put up \"+COUNT name\" for COUNT of item KIND just picked up, added to the last note's count
if that was KIND and is still up. The name is the item's :NOTE, else its :NAME."
  (if (and (eq kind *pickup-note-kind*) (< 0.0 *pickup-note-left*))
      (incf *pickup-note-count* count)
      (setf *pickup-note-kind* kind
            *pickup-note-count* count))
  (setf *pickup-note-left* *pickup-note-time*
        *pickup-note* (format NIL "+~d ~a" *pickup-note-count*
                              (or (item-property kind :note) (string-downcase (item-property kind :name))))))

(defmethod hud-shown-p ((banner level-banner))
  (and (eq *game-state* :playing) (< 0.0 *level-banner-left*)))

(defun level-banner-text ()
  "\"Level 2 of 4\", and in the settlement its name and who holds it: \", held by the Deepwardens\"."
  (let ((s *settlement*))
    (format NIL "Level ~d of ~d~@[: ~a~]~@[, ~a~]" *run-depth* (run-length)
            (and s (settlement-name s))
            (and s (format NIL "~:[held~;once held~] by ~a"
                           (eq (settlement-condition s) :sacked) (faction-property :name s))))))

;;; HUD-SAY puts a message up from a format string, and the prompt line says what E does with
;;; what the player looks at or stands at (INTERACT-TARGET, townsfolk.lisp).

(defun hud-say (format-control &rest args)
  "Put a message on the screen (SHOW-MESSAGE): FORMAT-CONTROL and ARGS, as for FORMAT."
  (show-message (apply #'format NIL format-control args)))

;;; Arriving: the banner names the town and its faction (LEVEL-BANNER-TEXT, above), and the
;;; message line says the watch's rule, so the player knows it before they can break it.

(defparameter *arrival-message-time* 7.0 "Seconds of play the rule stays up on arriving in the settlement.")

(defun announce-settlement ()
  "On arriving at a level, put the watch's rule, or that there is no watch, on the message line
for *ARRIVAL-MESSAGE-TIME*; on any other level, clear what the level before left there."
  (let ((s *settlement*))
    (cond ((null s) (setf *message-left* 0.0))
          (T (if (eq (settlement-condition s) :sacked)
                 (hud-say "The watch of ~a is dead. The undercroft holds the streets." (faction-property :name s))
                 (hud-say "The watch of ~a: ~a" (faction-property :name s) (faction-property :rule-text s)))
             (setf *message-left* *arrival-message-time*)))))

(define-shader-entity interact-prompt (hud-text) ())

(defmethod hud-shown-p ((prompt interact-prompt))
  (and (eq *game-state* :playing) *interact-prompt* T))

;;; The boss bar: the boss's title, its health and its powers, across the top of the screen
;;; from the moment the arena's gate drops until it dies (boss.lisp). An elite the player aims at
;;; (AIMED-ELITE, elite.lisp) takes its place while aimed at and *ELITE-BAR-LINGER* after: its
;;; name over a bar half as wide, and its trait's name under it in its glow's colour.

(defparameter *boss-bar-width* 160 "Art pixels across the boss bar, its frame included.")
(defparameter *boss-bar-height* 6 "Art pixels up it.")
(defparameter *boss-bar-color* (vec4 0.62 0.10 0.06 1))
(defparameter *boss-bar-top* 28 "Pixels from the top of the screen to the top of the title.")
(defparameter *elite-bar-width* 80 "Art pixels across an aimed elite's bar: half the boss's.")
(defparameter *elite-aim-step* 0.1 "Seconds between looks for the elite under the aim.")
(defparameter *elite-bar-linger* 0.25
  "Seconds an elite's bar stays after the crosshair leaves it, so a glance off its edge doesn't
make it flicker.")

(defvar *aimed-elite* NIL "The elite whose bar is up, or NIL.")
(defvar *aimed-left* 0.0 "Seconds of play its bar stays up unless it is aimed at again.")
(defvar *aim-clock* 0.0 "Seconds of play until the next look for an aimed elite.")

(defun shown-elite ()
  "The elite whose bar is up, while it lives and is in the scene, else NIL."
  (let ((elite *aimed-elite*))
    (and elite (< 0.0 *aimed-left*) (not (dead elite)) (not (gibbed elite)) (container elite) elite)))

(defun update-aimed-elite (dt)
  "Every *ELITE-AIM-STEP* of play, the elite under the player's aim, if any, holds the bar for
*ELITE-BAR-LINGER* more."
  (when (and *player* (eq *game-state* :playing))
    (setf *aimed-left* (max 0.0 (- *aimed-left* dt)))
    (when (<= (decf *aim-clock* dt) 0.0)
      (setf *aim-clock* *elite-aim-step*)
      (let ((elite (aimed-elite *player*)))
        (when elite
          (setf *aimed-elite* elite
                *aimed-left* *elite-bar-linger*))))))

(define-shader-entity boss-element () ())

(defun shown-boss ()
  "The boss the bar is for, or NIL when the bar is down."
  (let ((boss (and *arena* (sealed *arena*) (arena-boss *arena*))))
    (and boss (not (dead boss)) boss)))

(defun shown-foe ()
  "What the bar is for: the aimed elite, else the boss; NIL when the bar is down."
  (or (shown-elite) (shown-boss)))

(defmethod hud-shown-p ((element boss-element))
  (and (member *game-state* '(:playing :paused)) (shown-foe) T))

(define-shader-entity boss-only-element (boss-element) ()
  (:documentation "A part of the bar an elite's doesn't have: the half mark."))

(defmethod hud-shown-p ((element boss-only-element))
  (and (call-next-method) (null (shown-elite))))

(define-shader-entity boss-bar (boss-element hud-bar) ())
(define-shader-entity boss-text (boss-element hud-text) ())
(define-shader-entity boss-half-mark (boss-only-element hud-bar) ())

(defun boss-powers-text (boss)
  (format NIL "~{~a~^  ~}" (mapcar (lambda (name) (power-label (find-power name))) (active-powers boss))))

;;; The HUD: owns the elements, keeps them in place and in sync with the player.

(defclass hud (entity listener)
  ((name :initform :hud)
   (level-banner :initform (make-hud-text (level-banner-text) 'level-banner) :reader level-banner)
   (message-banner :initform (make-hud-text "" 'message-banner) :reader message-banner)
   (pickup-banner :initform (make-hud-text "" 'pickup-banner) :reader pickup-banner)
   (shown-pickup-note :initform NIL :accessor shown-pickup-note)
   (shown-message :initform NIL :accessor shown-message)
   (prompt-line :initform (make-hud-text "" 'interact-prompt) :reader prompt-line)
   (health-label :initform (make-hud-text "HP") :reader health-label)
   (health-bar :initform (make-instance 'hud-bar :fill-color *health-bar-color*) :reader health-bar)
   (health-text :initform (make-hud-text) :reader health-text)
   (mana-label :initform (make-hud-text "MP") :reader mana-label)
   (mana-bar :initform (make-instance 'hud-bar :fill-color *mana-bar-color*) :reader mana-bar)
   (mana-text :initform (make-hud-text) :reader mana-text)
   (stamina-label :initform (make-hud-text "SP") :reader stamina-label)
   (stamina-bar :initform (make-instance 'hud-bar :fill-color *stamina-bar-color*) :reader stamina-bar)
   (stamina-text :initform (make-hud-text) :reader stamina-text)
   (breath-label :initform (make-hud-text "AIR" 'breath-text) :reader breath-label)
   (breath-bar :initform (make-instance 'breath-bar :fill-color *breath-bar-color*) :reader breath-bar)
   (pain-flash :initform (make-instance 'pain-flash) :reader pain-flash)
   (restore-flash :initform (make-instance 'restore-flash) :reader restore-flash)
   (underwater-tint :initform (make-instance 'underwater-tint) :reader underwater-tint)
   (veils :initform (mapcar (lambda (kind) (make-instance 'status-veil :kind kind)) *veil-kinds*) :reader veils)
   (whirl-streaks :initform (make-instance 'whirl-streaks) :reader whirl-streaks)
   (fps-display :initform (make-hud-text "" 'fps-display) :reader fps-display)
   (boss-name :initform (make-hud-text "" 'boss-text) :reader boss-name)
   (boss-bar :initform (make-instance 'boss-bar :fill-color *boss-bar-color*) :reader boss-bar)
   (boss-half :initform (make-instance 'boss-half-mark :fill-color (vec4 0 0 0 1)) :reader boss-half
              :documentation "A mark on the bar at half health, where the boss enrages.")
   (boss-powers :initform (make-hud-text "" 'boss-text) :reader boss-powers-line)
   (shown-boss-text :initform NIL :accessor shown-boss-text :documentation "The foe the bar's text is for.")
   (shown-foe-state :initform NIL :accessor shown-foe-state
                    :documentation "Whether that boss is enraged, or that elite's trait, as the text shows it.")
   (shown-health :initform NIL :accessor shown-health)
   (shown-mana :initform NIL :accessor shown-mana)
   (shown-stamina :initform NIL :accessor shown-stamina)))

(defun hud-elements (hud)
  ;; The flash first, so the bars draw over it.
  (list* (pain-flash hud) (restore-flash hud) (underwater-tint hud) (whirl-streaks hud)
         (append (veils hud) (list
        (health-label hud) (health-bar hud) (health-text hud)
        (mana-label hud) (mana-bar hud) (mana-text hud)
        (stamina-label hud) (stamina-bar hud) (stamina-text hud)
        (breath-label hud) (breath-bar hud)
        (level-banner hud) (message-banner hud) (pickup-banner hud) (prompt-line hud)
        (boss-bar hud) (boss-half hud) (boss-name hud) (boss-powers-line hud)
        (fps-display hud)))))

(defun add-hud (container)
  (setf *aimed-elite* NIL *aimed-left* 0.0)
  (let ((hud (make-instance 'hud)))
    (enter hud container)
    (dolist (element (hud-elements hud) hud)
      (enter element container))))

(defun hud-row-y (row)
  "Pixels from the bottom edge to the bottom of ROW, counted from 0 at the bottom."
  (+ *hud-margin* (* row (+ *glyph-height* *hud-row-gap*))))

(defun hud-top ()
  "Pixels from the bottom edge to the top of the bars, for what stacks above them."
  (+ (hud-row-y (if (breath-shown-p) 3 2)) *glyph-height*))

(defun layout-hud (hud)
  "Rows from the bottom: stamina, mana, health, then breath. Each row is a label, a bar and the
numbers; breath has none."
  (let* ((margin *hud-margin*)
         (k (hud-pixel-scale))
         (bar-x (+ margin (text-width "AIR") 8))
         ;; Whole pixels only: a bar on a half pixel loses an edge row.
         (bar-dy (floor (- *glyph-height* (* k *hud-bar-height*)) 2)))
    (flet ((row (y label bar value)
             (place label margin y)
             (place bar bar-x (+ y bar-dy))
             (size-bar bar *hud-bar-width* *hud-bar-height*)
             (when value
               (place value (+ bar-x (* k *hud-bar-width*) 8) y))))
      (row (hud-row-y 0) (stamina-label hud) (stamina-bar hud) (stamina-text hud))
      (row (hud-row-y 1) (mana-label hud) (mana-bar hud) (mana-text hud))
      (row (hud-row-y 2) (health-label hud) (health-bar hud) (health-text hud))
      (row (hud-row-y 3) (breath-label hud) (breath-bar hud) NIL)))
  (place (pickup-banner hud)
         (round (- (/ (width *context*) 2) (/ (text-width (text (pickup-banner hud))) 2)))
         (round (* *pickup-note-height* (height *context*))))
  (place (message-banner hud)
         (round (- (/ (width *context*) 2) (/ (text-width (text (message-banner hud))) 2)))
         (round (* 0.62 (height *context*))))
  (place (fps-display hud) *hud-margin* (- (height *context*) *hud-margin* *glyph-height*))
  (place (level-banner hud)
         (round (- (/ (width *context*) 2) (/ (text-width (text (level-banner hud))) 2)))
         (round (* 0.75 (height *context*))))
  (place (prompt-line hud)
         (round (- (/ (width *context*) 2) (/ (text-width (text (prompt-line hud))) 2)))
         (round (* 0.4 (height *context*))))
  ;; The boss bar, centred across the top: the title, the bar, the powers under it.
  (let* ((w (width *context*))
         (title-y (- (height *context*) *boss-bar-top* *glyph-height*))
         (k (hud-pixel-scale))
         (width (if (shown-elite) *elite-bar-width* *boss-bar-width*))
         (bar-w (* k width))
         (bar-h (* k *boss-bar-height*))
         (bar-y (- title-y 4 bar-h))
         (bar-x (round (- (/ w 2) (/ bar-w 2)))))
    (flet ((centre (text y)
             (place text (round (- (/ w 2) (/ (text-width (text text)) 2))) y)))
      (centre (boss-name hud) title-y)
      (centre (boss-powers-line hud) (- bar-y 4 *glyph-height*)))
    (place (boss-bar hud) bar-x bar-y -0.1)
    (size-bar (boss-bar hud) width *boss-bar-height*)
    ;; In front of the bar, at the middle: one art pixel of the frame's colour.
    (place (boss-half hud) (+ bar-x (* k (floor *boss-bar-width* 2))) bar-y)
    (vsetf (art-size (boss-half hud)) 1 *boss-bar-height*)
    (setf (vx (scaling (boss-half hud))) (float k 0f0)
          (vy (scaling (boss-half hud))) (float bar-h 0f0)))
  ;; Behind every HUD element, in front of the world: anything nearer than -0.5 would
  ;; be within the near plane's 5 cm.
  (dolist (cover (list* (pain-flash hud) (restore-flash hud) (underwater-tint hud) (whirl-streaks hud) (veils hud)))
    (place cover 0 0 -0.5)
    (setf (vx (scaling cover)) (float (width *context*) 0f0)
          (vy (scaling cover)) (float (height *context*) 0f0))))

(defun update-veils (hud dt)
  "How much of each veil shows: a ward's while it has points, fading under 10 of them; the
blessing's while it lasts, blinking over its last *VEIL-WARN-TIME*; healing over time's while it
heals."
  (dolist (veil (veils hud))
    (when (eq *game-state* :playing)
      (incf (veil-clock veil) dt))
    (setf (strength veil)
          (ecase (veil-kind veil)
            (:ward (let ((ward (status-of *player* :ward)))
                     (if ward (min 1.0 (/ (status-magnitude ward) 10.0)) 0.0)))
            (:bless (let ((left (blessed *player*)))
                      (cond ((<= left 0.0) 0.0)
                            ((< left *veil-warn-time*) (if (evenp (floor left 0.25)) 1.0 0.3))
                            (T 1.0))))
            (:heal (if (status-of *player* :heal) 1.0 0.0))))))

(define-handler (hud tick) (dt)
  (when (eq *game-state* :playing)
    (setf *level-banner-left* (max 0.0 (- *level-banner-left* dt))
          *message-left* (max 0.0 (- *message-left* dt))
          *pickup-note-left* (max 0.0 (- *pickup-note-left* dt))))
  (unless (eq *pickup-note* (shown-pickup-note hud))
    (setf (shown-pickup-note hud) *pickup-note*
          (text (pickup-banner hud)) *pickup-note*))
  (unless (eq *message* (shown-message hud))
    (setf (shown-message hud) *message*
          (text (message-banner hud)) *message*))
  ;; A new string each time it changes, so EQ tells.
  (when (and *interact-prompt* (not (eq *interact-prompt* (text (prompt-line hud)))))
    (setf (text (prompt-line hud)) *interact-prompt*))
  (update-aimed-elite dt)
  (let ((foe (shown-foe)))
    (when foe
      (setf (fill-fraction (boss-bar hud)) (/ (float (max 0 (health foe))) (max-health foe)))
      ;; Re-uploading text costs a buffer update, so only when what it says changes: another
      ;; foe, or the boss's powers (enraged) or the elite's trait. Compared without allocating.
      (let ((state (if (typep foe 'boss) (and (enraged foe) T) (elite-trait foe))))
        (unless (and (eq foe (shown-boss-text hud)) (eq state (shown-foe-state hud)))
          (setf (shown-boss-text hud) foe
                (shown-foe-state hud) state)
          (cond ((typep foe 'boss)
                 (setf (text (boss-name hud)) (boss-title foe)
                       (text (boss-powers-line hud)) (boss-powers-text foe)
                       (foreground (boss-powers-line hud)) *hud-text-color*))
                (T
                 (let ((c (getf *elite-glow-colors* (elite-trait foe))))
                   (setf (text (boss-name hud)) (elite-title foe)
                         (text (boss-powers-line hud)) (elite-trait-label foe)
                         (foreground (boss-powers-line hud)) (vec4 (vx c) (vy c) (vz c) 1)))))))))
  (when (eq *game-state* :playing)
    (loop for (kind left) on *veil-flares* by #'cddr
          do (setf (getf *veil-flares* kind) (max 0.0 (- left dt)))))
  (when *player*
    (update-veils hud dt)
    (let ((hp (max 0 (health *player*)))
          (mp (floor (mana *player*)))
          (sp (floor (stamina *player*))))
      (setf (strength (pain-flash hud)) (/ (pain *player*) *pain-time*)
            (strength (restore-flash hud)) (/ (restore-flash *player*) *restore-flash-time*)
            (fill-fraction (health-bar hud)) (/ (float hp) (max-health *player*))
            (fill-fraction (mana-bar hud)) (/ (mana *player*) (max-mana *player*))
            (fill-fraction (stamina-bar hud)) (/ (stamina *player*) (max-stamina *player*))
            (fill-fraction (breath-bar hud)) (/ (breath *player*) *breath-time*))
      ;; Re-uploading text costs a buffer update, so only when a number changes: each is
      ;; kept with its maximum (the trainer raises them) as one integer.
      (let ((max-hp (max-health *player*)) (max-mp (floor (max-mana *player*))) (max-sp (floor (max-stamina *player*))))
        (unless (eql (+ hp (* 100000 max-hp)) (shown-health hud))
          (setf (shown-health hud) (+ hp (* 100000 max-hp))
                (text (health-text hud)) (format NIL "~d/~d" hp max-hp)))
        (unless (eql (+ mp (* 100000 max-mp)) (shown-mana hud))
          (setf (shown-mana hud) (+ mp (* 100000 max-mp))
                (text (mana-text hud)) (format NIL "~d/~d" mp max-mp)))
        (unless (eql (+ sp (* 100000 max-sp)) (shown-stamina hud))
          (setf (shown-stamina hud) (+ sp (* 100000 max-sp))
                (text (stamina-text hud)) (format NIL "~d/~d" sp max-sp))))))
  (layout-hud hud))
