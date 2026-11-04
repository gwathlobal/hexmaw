(in-package #:hexmaw)

;;; The automap screen, Daggerfall style: M freezes the world (*GAME-STATE* :MAP) and
;;; swaps the scene's camera for a MAP-CAMERA orbiting the level. Trial draws what the
;;; active camera's IN-VIEW-P accepts, so under the map camera only what MAP-DRAWN-P
;;; accepts is drawn: the map pieces of revealed blocks (automap.lisp), the player's
;;; arrow and the map's own HUD; and the player's camera never draws a map piece. The
;;; map cuts every storey open *MAP-CUT-HEIGHT* above its floor, leaves out the storeys
;;; above the shown one and darkens those below. With the debug minimap (MAP-DEBUG-P) every block shows, with a
;;; marker on each creature and each block's name.
;;;
;;; Controls: left drag rotates, right drag pans, the wheel zooms; WASD pan, Q and E
;;; turn, R and F tilt, + and - zoom, Page Up and Page Down (or Shift and the wheel) change
;;; the storey within those explored, Space centres on the player, M or Esc (menu.lisp)
;;; closes. The storey above the shown one is a stippled ghost (automap.lisp).

(defparameter *map-background* (vec 0.035 0.04 0.06) "The map screen's clear colour.")
(defparameter *map-arrow-color* (vec4 1.0 0.85 0.2 1))
(defparameter *map-live-color* (vec4 0.9 0.15 0.12 1))
(defparameter *map-dead-color* (vec4 0.35 0.32 0.30 1))
(defparameter *map-start-pitch* 0.95 "Radians the map looks down when first opened.")
(defparameter *map-start-distance* 28.0 "Metres from the camera to the point it orbits, when first opened.")
(defparameter *map-min-distance* 3.0)
(defparameter *map-max-distance* 400.0)
(defparameter *map-min-pitch* 0.1)
(defparameter *map-max-pitch* 1.5)
(defparameter *map-drag-turn* 0.008 "Radians a pixel of left drag turns or tilts the map.")
(defparameter *map-zoom-step* 1.15 "How much one wheel notch zooms.")
(defparameter *map-key-pan* 0.8 "Map panned per second with WASD, in multiples of the camera's distance.")
(defparameter *map-key-turn* 1.6 "Radians per second Q, E, R and F turn or tilt the map.")
(defparameter *map-key-zoom* 2.0 "Zoom factor per second with + and -.")

;;; Visibility.

(defgeneric map-drawn-p (object)
  (:documentation "Whether OBJECT draws on the map screen.")
  (:method (object) NIL))

(defmethod map-drawn-p ((piece map-piece))
  (let ((block (map-block piece)))
    (or (null block) (revealed block) (map-debug-p))))

(define-shader-entity map-overlay ()
  ()
  (:documentation "Drawn on the map screen in front of the level, whatever the draw order."))

(defmethod map-drawn-p ((overlay map-overlay)) T)

(defmethod render :around ((overlay map-overlay) (program shader-program))
  (gl:disable :cull-face)
  (unwind-protect (call-next-method)
    (gl:enable :cull-face)))

(define-class-shader (map-overlay :vertex-shader)
  "void main(){
  maybe_call_next_method();
  // On the near plane, so the level drawn before or after never covers it.
  gl_Position.z = -0.999 * gl_Position.w;
}")

;;; The camera.

(defclass map-camera (3d-camera)
  ((name :initform :map-camera)
   (fov :initform 50.0)
   (map-target :initform (vec 0 0 0) :reader map-target :documentation "The point it orbits.")
   (map-yaw :initform 0.0 :accessor map-yaw :documentation "In the player's convention: 0 has north up the screen.")
   (map-pitch :initform *map-start-pitch* :accessor map-pitch)
   (map-distance :initform *map-start-distance* :accessor map-distance)
   (map-eye :initform (vec 0 0 0) :reader map-eye)
   (view-projection :initform (meye 4) :reader view-projection
                    :documentation "Its last projection times view, for placing labels."))
  (:default-initargs :near-plane 0.1 :far-plane 2000.0))

(defmethod project-view ((camera map-camera))
  (let* ((target (map-target camera)) (eye (map-eye camera))
         (yaw (map-yaw camera)) (pitch (map-pitch camera)) (d (map-distance camera))
         (across (* d (cos pitch))))
    ;; Behind the way the yaw faces, so that way is up the screen.
    (vsetf eye (- (vx target) (* across (sin yaw)))
               (+ (vy target) (* d (sin pitch)))
               (+ (vz target) (* across (cos yaw))))
    (look-at eye target +vy+)
    (v<- *map-eye* eye)
    (!m* (view-projection camera) (projection-matrix) (view-matrix))))

(defmethod in-view-p :around (object (camera map-camera))
  (map-drawn-p object))

(defmethod in-view-p :around ((piece map-piece) (camera player))
  NIL)

(defmethod in-view-p :around ((overlay map-overlay) (camera player))
  NIL)

(defun pan-map (camera forward right)
  "Move CAMERA's orbit point FORWARD metres up the screen and RIGHT metres right."
  (let ((target (map-target camera)) (yaw (map-yaw camera)))
    (incf (vx target) (+ (* forward (sin yaw)) (* right (cos yaw))))
    (incf (vz target) (+ (* forward (- (cos yaw))) (* right (sin yaw))))))

(defun zoom-map (camera factor)
  (setf (map-distance camera) (float (clamp *map-min-distance* (* (map-distance camera) factor) *map-max-distance*) 0f0)))

(defun turn-map (camera yaw pitch)
  (setf (map-yaw camera) (mod (+ (map-yaw camera) yaw) #.(float (* 2 pi) 0f0))
        (map-pitch camera) (clamp *map-min-pitch* (+ (map-pitch camera) pitch) *map-max-pitch*)))

;;; The player's arrow, flat on the floor, pointing the way the player faces.

(define-asset (hexmaw map-arrow) mesh
    ;; A chevron one metre long, pointing -Z, its middle at the origin.
    (with-mesh-construction (v :attributes (location))
      (v 0 0 -0.6) (v -0.45 0 0.45) (v 0 0 0.15)
      (v 0 0 -0.6) (v 0 0 0.15) (v 0.45 0 0.45)
      (finalize-data)))

(define-shader-entity map-arrow (map-overlay vertex-entity colored-entity transformed-entity)
  ((vertex-array :initform (// 'hexmaw 'map-arrow))
   (color :initform *map-arrow-color*)))

(defun update-map-arrow (arrow camera)
  (let ((feet (feet *player*)) (loc (location arrow))
        (size (max 1.0 (* 0.045 (map-distance camera)))))
    (vsetf loc (vx feet) (+ (vy feet) 0.05) (vz feet))
    (vsetf (scaling arrow) size size size)
    (!qfrom-angle (orientation arrow) +vy+ (- (vy (rotation *player*))))))

;;; Creature markers (debug): a block on every creature, drawn by one entity.

(define-shader-entity map-markers (map-overlay vertex-entity colored-entity transformed-entity)
  ((vertex-array :initform (// 'trial 'unit-cube))
   (marker-matrix :initform (meye 4) :reader marker-matrix)
   (marker-size :initform (vec 1 1 1) :reader marker-size)
   (marker-size-scale :initform 1.0 :accessor marker-size-scale)))

(defmethod map-drawn-p ((markers map-markers))
  (map-debug-p))

(defmethod render ((markers map-markers) (program shader-program))
  (let* ((m (marker-matrix markers))
         (s (marker-size-scale markers))
         (size (vsetf (marker-size markers) s s s)))
    (setf (uniform program "view_matrix") (view-matrix))
    (setf (uniform program "projection_matrix") (projection-matrix))
    (loop for creature across *creatures*
          for at = (location creature)
          ;; Not those on storeys the map has cut away.
          unless (or (gibbed creature) (< *map-focus-storey* (storey-at (vy at))))
            do (!meye m)
               (nmtranslate m (vsetf (marker-size markers) (vx at) (+ (vy at) (* 0.5 s)) (vz at)))
               (nmscale m (vsetf size s s s))
               (setf (uniform program "model_matrix") m)
               (setf (uniform program "objectcolor") (if (dead creature) *map-dead-color* *map-live-color*))
               (render (vertex-array markers) program))))

;;; Text: the controls and storey, and (debug) every block's name.

(define-shader-entity map-text (map-overlay hud-text) ())

(define-shader-entity map-label (map-text)
  ((labelled :initarg :block :reader label-block)))

(defmethod map-drawn-p ((label map-label))
  (map-debug-p))

(defparameter *exit-label-color* (vec4 1.0 0.42 0.2 1)
  "Not the other labels' colour: over a wall's cut face, that one can't be read.")

(define-shader-entity exit-label (map-label) ()
  (:documentation "Says where the way down is, once the player has seen its block."))

(defmethod map-drawn-p ((label exit-label))
  (or (revealed (label-block label)) (map-debug-p)))

(defparameter *map-hint*
  "Storey ~d~a    Drag: turn  Right drag: pan  Wheel: zoom  PgUp/PgDn/Shift+wheel: storey  Space: centre  M: close")

(defun map-hint-text (storey above below)
  (format NIL *map-hint* storey
          (cond ((and above below) ", more above and below")
                (above ", more above")
                (below ", more below")
                (T ""))))

(defun place-map-label (label camera clip)
  "Put LABEL over its block's floor on the shown storey, or off screen when its block
isn't on that storey or is behind the camera. CLIP is a scratch vec4."
  (let* ((block (label-block label))
         (low (map-block-low block)) (high (map-block-high block))
         (floor (* *map-focus-storey* hexmaw.blueprint:*storey-height*))
         (y (max (+ (vy low) 0.5) floor)))
    (vsetf clip (* 0.5 (+ (vx low) (vx high))) y (* 0.5 (+ (vz low) (vz high))) 1.0)
    (n*m (view-projection camera) clip)
    (if (and (< (vy low) (+ floor *map-cut-height*)) (< floor (vy high)) (< 0.1 (vw clip)))
        (let ((x (* (+ 0.5 (* 0.5 (/ (vx clip) (vw clip)))) (width *context*)))
              (y (* (+ 0.5 (* 0.5 (/ (vy clip) (vw clip)))) (height *context*))))
          (place label (round (- x (* 4.5 (length (text label))))) (round (- y (/ +glyph-height+ 2)))))
        (place label -10000 -10000))))

;;; The controller: opening and closing, controls, revealing blocks as the player walks.

(defclass map-view (entity listener)
  ((name :initform :map-view)
   (map-camera :initform (make-instance 'map-camera) :reader map-camera)
   (arrow :initform (make-instance 'map-arrow) :reader map-arrow)
   (markers :initform (make-instance 'map-markers) :reader map-markers)
   (hint :initform (make-hud-text "" 'map-text) :reader map-hint)
   (shown-hint :initform NIL :accessor shown-hint :documentation "The storey and what's past it, as the hint shows them.")
   (block-labels :initform () :accessor map-labels)
   (exit-labels :initform () :accessor map-exit-labels)
   (clip :initform (vec4 0 0 0 1) :reader map-clip)))

(defvar *map-view* NIL "The current scene's MAP-VIEW.")

(defun add-map-view (container)
  "Enter the map screen's camera, overlays and controller into CONTAINER. After the
level is built: there is a label per block."
  (let ((view (make-instance 'map-view)))
    (flet ((label (class block text color)
             (make-instance class :block block :text text
                                  :font-size (float +glyph-height+ 0f0)
                                  :foreground color :background (vec4 0 0 0 0))))
      (setf (map-labels view)
            (loop for block across *map-blocks*
                  collect (label 'map-label block (map-block-name block) *hud-text-color*))
            (map-exit-labels view)
            (loop for (nil . block) across *level-exits*
                  collect (label 'exit-label block "Stairs down" *exit-label-color*))))
    (dolist (entity (list* (map-camera view) (map-arrow view) (map-markers view) (map-hint view)
                           (append (map-labels view) (map-exit-labels view))))
      (enter entity container))
    (enter view container)
    (setf *map-view* view)))

(defun centre-map (view)
  "Orbit the player, the way they face up the screen, their storey cut open."
  (let ((camera (map-camera view)))
    (v<- (map-target camera) (feet *player*))
    (setf (map-yaw camera) (vy (rotation *player*))
          *map-focus-storey* (storey-at (vy (feet *player*))))))

(defun step-map-storey (step)
  "Show the storey STEP above (below, if negative) the shown one, within the storeys the map
shows and the player's own."
  (let ((storey (+ *map-focus-storey* step)))
    (multiple-value-bind (low high) (map-storey-range)
      (when low
        (let ((own (storey-at (vy (feet *player*)))))
          (setf storey (clamp (min low own) storey (max high own))))))
    (unless (= storey *map-focus-storey*)
      (play-sound :map-storey))
    (setf *map-focus-storey* storey)))

(defun open-map ()
  (when (and (eq *game-state* :playing) *player* *map-view*)
    (play-sound :map-open)
    (setf *game-state* :map)
    (release-mouse *player*)
    (centre-map *map-view*)))

(defun close-map ()
  (when (eq *game-state* :map)
    (play-sound :map-close)
    (setf *game-state* :playing)
    (when *player* (capture-mouse *player*))))

(define-handler (map-view key-press) (key)
  (case *game-state*
    (:playing (when (eq key :m) (open-map)))
    (:map (case key
            (:m (close-map))
            (:page-up (step-map-storey 1))
            (:page-down (step-map-storey -1))
            (:space (centre-map map-view))))))

(define-handler (map-view mouse-scroll) (delta)
  (when (and (eq *game-state* :map) (/= 0 delta))
    (if (or (retained :left-shift) (retained :right-shift))
        ;; Shift: up a notch is up a storey.
        (step-map-storey (if (< 0 delta) 1 -1))
        (zoom-map (map-camera map-view) (expt *map-zoom-step* (- (signum delta)))))))

(define-handler (map-view mouse-move) (old-pos pos)
  (when (eq *game-state* :map)
    (let ((camera (map-camera map-view))
          (dx (- (vx pos) (vx old-pos)))
          ;; Mouse Y grows upward.
          (dy (- (vy pos) (vy old-pos))))
      (cond ((retained :left)
             (turn-map camera (* *map-drag-turn* dx) (- (* *map-drag-turn* dy))))
            ((retained :right)
             ;; The ground under the cursor follows it, near enough.
             (let ((per-pixel (/ (* 2 (map-distance camera) (tan (* 0.5 (float (deg->rad (fov camera)) 0f0))))
                                 (max 1 (height *context*)))))
               (pan-map camera (- (* dy per-pixel (/ (sin (map-pitch camera))))) (- (* dx per-pixel)))))))))

(defun steer-map (camera dt)
  "Move CAMERA by the keys held, over DT seconds."
  (flet ((axis (plus minus) (- (if (retained plus) 1.0 0.0) (if (retained minus) 1.0 0.0))))
    (let ((pan (* *map-key-pan* (map-distance camera) dt)))
      (pan-map camera (* pan (axis :w :s)) (* pan (axis :d :a))))
    (turn-map camera (* *map-key-turn* dt (axis :q :e)) (* *map-key-turn* dt (axis :r :f)))
    (let ((zoom (+ (axis :minus :equal) (axis :kp-subtract :kp-add))))
      (unless (= 0 zoom)
        (zoom-map camera (expt *map-key-zoom* (* zoom dt)))))))

(define-handler (map-view tick) (dt)
  (let ((scene (scene +main+))
        (camera (map-camera map-view)))
    ;; Standing in a block reveals it.
    (when (and *player* (eq *game-state* :playing))
      (reveal-map-at (feet *player*)))
    ;; The map camera while the map is up, else the player's: also after a scene reset.
    (let ((wanted (if (eq *game-state* :map) camera *player*)))
      (when (and wanted (not (eq wanted (camera scene))))
        (setf (camera scene) wanted)))
    (when (and (eq *game-state* :map) *player*)
      (steer-map camera dt)
      (update-map-arrow (map-arrow map-view) camera)
      (setf (marker-size-scale (map-markers map-view)) (max 0.5 (* 0.015 (map-distance camera))))
      ;; Depth precision: the near plane moves out as the map zooms out.
      (let ((near (max 0.1 (/ (map-distance camera) 50.0))))
        (when (< 0.01 (abs (- near (near-plane camera))))
          (setf (near-plane camera) near)))
      (multiple-value-bind (low high) (map-storey-range)
        (let* ((storey *map-focus-storey*)
               (above (and high (< storey high)))
               (below (and low (< low storey)))
               (key (+ (* 4 storey) (if above 1 0) (if below 2 0))))
          ;; Re-uploading text costs a buffer update, so only when it changes.
          (unless (eql key (shown-hint map-view))
            (setf (shown-hint map-view) key
                  (text (map-hint map-view)) (map-hint-text storey above below)))))
      (place (map-hint map-view) *hud-margin* *hud-margin*)
      (dolist (label (map-exit-labels map-view))
        (place-map-label label camera (map-clip map-view)))
      (when (map-debug-p)
        (dolist (label (map-labels map-view))
          (place-map-label label camera (map-clip map-view)))))))
