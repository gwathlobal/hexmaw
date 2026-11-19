(in-package #:hexmaw)

;;; Skins: something laid over the level's floors and walls in play for a while, drawn on them in
;;; world space. A rime hag's ice (hag.lisp) is one: it is ice underfoot, so walks slide, lunges
;;; overshoot and blows send bodies skating into walls, and it freezes what stands on it as it
;;; forms. A skin has a kind (*SKIN-KINDS*: the texture it is drawn with, its rim's colours, the
;;; footing it is underfoot or NIL for a look only), covers the nav grid's 0.5 m cells within its
;;; radius whose floors are within *PATCH-CLIMB* of the floor it was laid on (SKIN-FLOOR-CELLS, so
;;; it follows steps, pits and ledges, and never lies on a liquid), and may cover the wall faces
;;; round it too (SKIN-WALL-CELLS), as a look only. Each kind's SKIN-FLOOR draws every skin of
;;; that kind in one call.
;;;
;;; What a skin is to the rest of the game is an entry in *SKIN-PATCHES* (greybox.lisp), which
;;; SKIN-FOOTING reads. Elements reach skins through STRIKE-SKINS (a fire burst, nova, projectile,
;;; beam or firestorm: spells.lisp, acolyte.lisp), which asks SKIN-STRUCK of each: fire melts
;;; rime. A save keeps them (:SKINS, SKIN-RECORD and RESTORE-SKIN).
;;;
;;; Ported from the frost patch of the spell-secondary branch (its FROST-PATCH-CELLS, FREEZE and
;;; ice floor), made general for other kinds of skin.

(defparameter *patch-renew-reach* 1.0
  "Metres within which a caster's new patch renews its old one instead of laying another.")
(defparameter *patch-climb* 1.0
  "Metres above or below the floor where it was laid that a skin still spreads over: steps and a
ledge, not the storey above.")
(defparameter *patch-reach* 2.0 "Metres above the floor a point may be and still lay a skin on it.")
(defparameter *freeze-max* 1.0 "Most seconds a frost patch freezes anything.")
(defparameter *freeze-guard* 2.0 "Seconds after a freeze before the creature can be frozen again.")
(defparameter *skin-wall-height* 2.5 "Metres above its floor that a skin climbs the walls round it.")
(defparameter *skin-grit* 24 "Frost grit thrown as a frost patch forms.")

(defvar *skins* () "The skins in the level (CLEAR-LEVEL empties it).")

;;; Kinds.

(defvar *skin-kinds* ()
  "(NAME :TEXTURE asset :RIM (r g b) :INNER (r g b) :FOOTING key :EDGE mode): what each kind of
skin is drawn with, the colour its rim is frosted, the one just inside it, the footing it is
underfoot (a key of *FOOTINGS*, or NIL for a look only), and how its edge is found (:CIRCLE or
:COVER). DEFINE-SKIN-KIND adds one.")

(defmacro define-skin-kind (name &key texture (rim ''(0.78 0.89 0.96)) (inner ''(0.59 0.77 0.9)) footing
                                      (edge :circle))
  "Define skin kind NAME (a keyword): drawn with the hexmaw pool's image TEXTURE (an asset name,
laid at 64 texels a metre; texels under half alpha are see-through), its rim RIM and just inside
it INNER (linear RGB lists), underfoot FOOTING. EDGE :CIRCLE cuts it at the skin's circle (entry
index 3, the radius drawn now) in jagged texel steps; :COVER at its cells' own outline, for a skin
that grows cell by cell (roots): each floor cell's corner carries the share of the four cells
round it that are laid, on its floor (SKIN-CORNER-COVER), and the shader cuts where that share
plus hashed noise falls under a half, so a lone cell shows nothing and a carpet's edge runs ragged
half a cell inside its outer cells; wall cells are whole. ADD-SKIN-FLOORS gives each kind its own
drawer, so a kind defined after the scene was set up shows from the next one."
  `(progn
     (setf *skin-kinds* (remove ,name *skin-kinds* :key #'first))
     (setf *skin-kinds* (append *skin-kinds* (list (list ,name :texture ',texture :rim ,rim :inner ,inner
                                                          :footing ,footing :edge ,edge))))
     ,name))

(defun skin-kind-property (kind property)
  (getf (rest (assoc kind *skin-kinds*)) property))

(define-skin-kind :ice :texture ice :footing :ice)

;;; The cells a skin covers.

(defun patch-floor-under (x y z)
  "The floor height under the point X Y Z a skin may lie on, or NIL if there is none within
*PATCH-REACH*."
  (let ((floor (and *nav-grid* (nav-floor-at x (+ y 0.1) z))))
    (and floor (< (- y floor) *patch-reach*) floor)))

(defun skin-floor-cells (x floor z radius)
  "The floor a skin covers round X FLOOR Z out to RADIUS: values the X and Z of its grid's corner,
its columns a side, a cell's size, and each cell's floor height (most-negative-single-float for
none), row by row. A cell under a liquid is left out: no rime on lava or water."
  (let* ((grid *nav-grid*)
         (c (nav-cell-size grid))
         (n (1+ (ceiling (* 2 radius) c)))
         (i0 (- (floor (- x (nav-x0 grid)) c) (floor n 2)))
         (j0 (- (floor (- z (nav-z0 grid)) c) (floor n 2)))
         (heights (make-array (* n n) :element-type 'single-float :initial-element most-negative-single-float)))
    (dotimes (a n)
      (dotimes (b n)
        (let ((i (+ i0 a)) (j (+ j0 b))
              (cx (+ (nav-x0 grid) (* (+ i0 a 0.5) c)))
              (cz (+ (nav-z0 grid) (* (+ j0 b 0.5) c))))
          (when (and (< -1 i (nav-width grid)) (< -1 j (nav-depth grid))
                     (< (+ (expt (- cx x) 2) (expt (- cz z) 2)) (expt (+ radius (* 0.71 c)) 2)))
            (let ((k (nav-layer i j (+ floor *patch-climb*) grid)))
              (when k
                (let ((h (nav-floor i j k grid)))
                  (when (and (< (abs (- h floor)) *patch-climb*)
                             (not (liquid-at cx (+ h 0.05) cz)))
                    (setf (aref heights (+ a (* b n))) (float h 0f0))))))))))
    (values (float (+ (nav-x0 grid) (* i0 c)) 0f0) (float (+ (nav-z0 grid) (* j0 c)) 0f0) n
            (float c 0f0) heights)))

(defparameter *skin-wall-cell* 0.5 "Metres a side of a wall cell, on the world's grid.")

(defun skin-wall-cells (x floor z radius &key (height *skin-wall-height*))
  "The wall faces a skin round X FLOOR Z out to RADIUS covers, from FLOOR up to HEIGHT above it:
a single-float array, 7 floats a cell, its quad's low corner X Y Z, its high corner X Y Z, and
its face's normal (1 or -1 along X, 2 or -2 along Z). Only square boxes' upright faces turned
toward the middle, where open air is in front of them (not between two solids) and a line from
the middle a metre up reaches them; a wedge's diagonal is left bare, as blood leaves it."
  (let ((cells (make-array 64 :element-type 'single-float :adjustable T :fill-pointer 0))
        (seen (make-hash-table :test 'eq))
        (step *skin-wall-cell*)
        (top (+ floor height))
        (eye (vec x (+ floor 1.0) z))
        (x0 (float (- x radius) 0f0)) (z0 (float (- z radius) 0f0))
        (x1 (float (+ x radius) 0f0)) (z1 (float (+ z radius) 0f0)))
    (labels ((push-cell (ax ay az bx by bz normal)
               (dolist (v (list ax ay az bx by bz normal))
                 (vector-push-extend (float v 0f0) cells)))
             (face (s axis high)
               ;; AXIS 0 is a face across X (at x = const), 2 across Z.
               (let* ((at (aref s (if high (+ axis 3) axis)))
                      (normal (* (if (= axis 0) 1 2) (if high 1 -1)))
                      (out (if high 0.02 -0.02))
                      (along (if (= axis 0) 2 0))
                      (lo (aref s along)) (hi (aref s (+ along 3)))
                      (y0 (max floor (aref s 1))) (y1 (min top (aref s 4))))
                 ;; Turned toward the middle, and within its reach across.
                 (when (and (< y0 y1)
                            (if (= axis 0)
                                (if high (< at x) (< x at))
                                (if high (< at z) (< z at)))
                            (< (abs (- at (if (= axis 0) x z))) radius))
                   (loop for u from (* step (floor lo step)) below hi by step
                         for ua = (max lo u) and ub = (min hi (+ u step))
                         when (< (+ ua 0.01) ub)
                           do (loop for v from (* step (floor y0 step)) below y1 by step
                                    for va = (max y0 v) and vb = (min y1 (+ v step))
                                    when (< (+ va 0.01) vb)
                                      do (let* ((mu (* 0.5 (+ ua ub))) (mv (* 0.5 (+ va vb)))
                                                (px (if (= axis 0) (+ at out) mu))
                                                (pz (if (= axis 0) mu (+ at out))))
                                           (when (and (< (+ (expt (- px x) 2) (expt (- pz z) 2)) (* radius radius))
                                                      (not (solid-at px mv pz))
                                                      (clear-line-p eye (vec px mv pz)))
                                             (if (= axis 0)
                                                 (push-cell at va ua at vb ub normal)
                                                 (push-cell ua va at ub vb at normal))))))))))
      (do-solids-near (s x0 z0 x1 z1)
        ;; Nor a window's pane (glass.lisp): it may break.
        (unless (or (gethash s seen) (< 0 (solid-cut s)) (eq :glass (solid-strike s)))
          (setf (gethash s seen) T)
          (when (and (< (aref s 1) top) (< floor (aref s 4)))
            (face s 0 NIL) (face s 0 T) (face s 2 NIL) (face s 2 T)))))
    (coerce cells '(simple-array single-float (*)))))

;;; The skin.

(defclass skin (entity listener)
  ((location :initarg :location :accessor location :documentation "Its middle, on its floor.")
   (kind :initarg :kind :initform :ice :reader skin-kind)
   (caster :initarg :caster :initform NIL :reader caster)
   (ground :initarg :ground :initform 0.0 :reader skin-ground :documentation "Its floor's height.")
   (radius :initarg :radius :initform 1.5 :accessor skin-radius)
   (time :initarg :time :initform 6.0 :accessor skin-time :documentation "Seconds it lasts in all.")
   (left :initarg :left :initform NIL :accessor skin-left :documentation "Seconds it has left.")
   (strength :initarg :strength :initform 0 :accessor skin-strength
             :documentation "How hard what laid it struck, for its kind to make of.")
   (floor-p :initarg :floor-p :initform T :reader skin-floor-p :documentation "True if it covers floor cells.")
   (walls-p :initarg :walls-p :initform T :reader skin-walls-p :documentation "True if it climbs the walls too.")
   (wall-base :initarg :wall-base :initform NIL :reader skin-wall-base
              :documentation "Where its wall cells start from, if not its floor: a wall struck high over a drop.")
   (entry :initform NIL :accessor skin-entry :documentation "Its vector in *SKIN-PATCHES*.")))

(defmethod initialize-instance :after ((skin skin) &key)
  (unless (skin-left skin)
    (setf (skin-left skin) (skin-time skin)))
  (compute-skin-cells skin))

(defun compute-skin-cells (skin)
  "Work out SKIN's cells for its radius now, into its entry."
  (let* ((at (location skin))
         (ground (float (skin-ground skin) 0f0))
         (radius (float (skin-radius skin) 0f0))
         (entry (or (skin-entry skin)
                    (setf (skin-entry skin) (make-array 12 :initial-element NIL)))))
    (multiple-value-bind (ox oz n c heights)
        (if (and *nav-grid* (skin-floor-p skin))
            (skin-floor-cells (vx at) ground (vz at) radius)
            (values 0f0 0f0 0 1f0 (make-array 0 :element-type 'single-float)))
      (setf (aref entry 0) (float (vx at) 0f0) (aref entry 1) ground (aref entry 2) (float (vz at) 0f0)
            (aref entry 3) (* radius (min 1.0 (skin-left skin)))
            (aref entry 4) ox (aref entry 5) oz (aref entry 6) n (aref entry 7) c (aref entry 8) heights
            (aref entry 9) (skin-kind-property (skin-kind skin) :footing)
            (aref entry 10) (if (and (skin-walls-p skin) (< 0 (length *solids*)))
                                (skin-wall-cells (vx at) (float (or (skin-wall-base skin) ground) 0f0) (vz at) radius)
                                (make-array 0 :element-type 'single-float))
            (aref entry 11) (skin-kind skin)))
    entry))

;; Not ENTER :AFTER: preloading enters things into the staging area.
(defgeneric start-skin (skin container)
  (:documentation "SKIN, just laid in CONTAINER, takes effect: it lies on the floor and walls (a
frost patch freezes what stands on it).")
  (:method :before ((skin skin) container)
    (declare (ignore container))
    (push skin *skins*))
  (:method ((skin skin) container)
    (declare (ignore container))
    (vector-push-extend (skin-entry skin) *skin-patches*)))

(defmethod leave :after ((skin skin) container)
  (setf *skins* (delete skin *skins*))
  (let ((at (position (skin-entry skin) *skin-patches*)))
    (when at
      (setf (aref *skin-patches* at) (aref *skin-patches* (1- (fill-pointer *skin-patches*))))
      (decf (fill-pointer *skin-patches*)))))

(defun lay-skin (skin container)
  "Put SKIN, made with MAKE-INSTANCE, into CONTAINER and start it. Returns it."
  (enter skin container)
  (start-skin skin container)
  skin)

(defgeneric renew-skin (skin strength radius)
  (:documentation "SKIN was laid again where it lies, by a blow of STRENGTH: it lasts its whole time
anew, widened to RADIUS.")
  (:method ((skin skin) strength radius)
    (setf (skin-left skin) (skin-time skin)
          (skin-strength skin) (max (skin-strength skin) strength))
    (when (< (skin-radius skin) radius)
      (setf (skin-radius skin) radius)
      (compute-skin-cells skin))))

(defgeneric skin-tick (skin dt)
  (:documentation "Run SKIN for DT seconds of play: by default it counts down and shrinks away over
its last second, as a look and as footing.")
  (:method ((skin skin) dt)
    (decf (skin-left skin) dt)
    (if (<= (skin-left skin) 0.0)
        (despawn skin)
        (setf (aref (skin-entry skin) 3)
              (float (* (skin-radius skin) (min 1.0 (skin-left skin))) 0f0)))))

(define-handler (skin tick) (dt)
  (unless (frozen-p)
    (skin-tick skin dt)))

(defgeneric skin-struck (skin element point radius caster)
  (:documentation "The ball RADIUS metres round POINT of ELEMENT's damage, from CASTER, reached SKIN
(STRIKE-SKINS): what it does to the skin. By default, nothing.")
  (:method ((skin skin) element point radius caster)
    (declare (ignore element point radius caster))
    NIL))

(defun skin-reached-p (skin point radius)
  "True if the ball RADIUS metres round POINT reaches SKIN's circle, at about its floor's height."
  (let ((at (location skin)))
    (and (< (abs (- (vy point) (skin-ground skin))) (+ radius *patch-climb* 1.0))
         (< (+ (expt (- (vx point) (vx at)) 2) (expt (- (vz point) (vz at)) 2))
            (expt (+ radius (skin-radius skin)) 2)))))

(defun strike-skins (element point radius caster)
  "ELEMENT struck the ball RADIUS metres round POINT, for CASTER: every skin it reaches hears of it
(SKIN-STRUCK), and a bloodroot's roots there burn or are held by frost (TOUCH-ROOTS, bloodroot.lisp)."
  (when element
    (touch-roots point radius element))
  (when (and element *skins*)
    (dolist (skin (copy-list *skins*))
      (when (and (container skin) (skin-reached-p skin point radius))
        (skin-struck skin element point radius caster)))))

(defun clear-skins ()
  "Take every skin away (RESET-RUN)."
  (dolist (skin (copy-list *skins*))
    (if (container skin)
        (despawn skin)
        (setf *skins* (delete skin *skins*))))
  (setf (fill-pointer *skin-patches*) 0))

(defun in-skin-p (skin creature)
  "True if CREATURE stands on SKIN: on its floor's storey and within its radius."
  (let ((loc (location creature))
        (at (location skin)))
    (and (< (abs (- (vy loc) (skin-ground skin))) *patch-climb*)
         (< (+ (expt (- (vx loc) (vx at)) 2) (expt (- (vz loc) (vz at)) 2))
            (expt (+ (skin-radius skin) (* 0.5 (body-radius creature))) 2)))))

;;; Saving: a skin's record is its class and the initargs that lay it again, its cells worked out
;;; afresh from the nav grid.

(defgeneric skin-record (skin)
  (:documentation "SKIN as a save keeps it: a plist with :CLASS and what RESTORE-SKIN needs.")
  (:method ((skin skin))
    (list :class (type-of skin) :kind (skin-kind skin) :location (encode-value (location skin))
          :ground (skin-ground skin) :radius (skin-radius skin) :time (skin-time skin)
          :left (skin-left skin) :strength (skin-strength skin)
          :floor-p (skin-floor-p skin) :walls-p (skin-walls-p skin) :wall-base (skin-wall-base skin)
          :caster (encode-value (caster skin)))))

(defgeneric restore-skin (class record container)
  (:documentation "Lay again in CONTAINER the skin of CLASS a save's RECORD (SKIN-RECORD) holds.")
  (:method (class record container)
    (let ((skin (make-instance class :kind (getf record :kind)
                                     :location (decode-value (getf record :location) NIL)
                                     :ground (getf record :ground) :radius (getf record :radius)
                                     :time (getf record :time) :left (getf record :left)
                                     :strength (getf record :strength)
                                     :floor-p (getf record :floor-p) :walls-p (getf record :walls-p)
                                     :wall-base (getf record :wall-base)
                                     :caster (decode-value (getf record :caster) NIL))))
      (enter skin container)
      ;; Its effect was had when it was laid: only its place underfoot again.
      (call-next-start-skin skin container)
      skin)))

(defun call-next-start-skin (skin container)
  "Start SKIN as a plain skin, without what its kind does as it forms (a freeze)."
  (declare (ignore container))
  (push skin *skins*)
  (vector-push-extend (skin-entry skin) *skin-patches*))

;;; The frost patch: rime over the floor, ice underfoot. As it forms it freezes the creatures
;;; standing on it that its caster is hostile to, its own side spared (FREEZE-PATCH); fire melts it.

(defclass frost-patch (skin)
  ((freeze-time :initarg :freeze-time :initform 0.0 :accessor freeze-time
                :documentation "Seconds it freezes what stands on it as it forms, at most *FREEZE-MAX*."))
  (:default-initargs :kind :ice))

(defmethod start-skin :after ((patch frost-patch) container)
  (declare (ignore container))
  (freeze-patch patch (freeze-time patch))
  (spray-sparks (vec (vx (location patch)) (+ (skin-ground patch) 0.1) (vz (location patch)))
                NIL *skin-grit* :kind :grit :ramp :frost :speed '(1.5 4.0)))

(defmethod renew-skin :after ((patch frost-patch) strength radius)
  (declare (ignore strength radius))
  (freeze-patch patch (freeze-time patch)))

(defmethod skin-struck ((patch frost-patch) (element (eql :fire)) point radius caster)
  (declare (ignore point radius caster))
  ;; Fire melts rime: it shrinks away over what would have been its last second.
  (setf (skin-left patch) (min (skin-left patch) 1.0)))

(defun freeze (creature seconds)
  "Freeze CREATURE for SECONDS (half for a boss), unless it thawed too lately: it stops what it was
doing and does nothing until it thaws (the creature's tick)."
  (when (and (< 0 seconds) (not (dead creature)) (not (dormant-p creature)) (<= (thaw creature) 0.0))
    (let ((seconds (float (if (typep creature 'boss) (* 0.5 seconds) seconds) 0f0)))
      (afflict creature :freeze 1 seconds)
      (setf (thaw creature) (+ seconds *freeze-guard*))
      (stop-walking creature seconds))))

(defun freeze-patch (patch seconds)
  "Freeze for SECONDS everything standing on PATCH that its caster is hostile to: never the caster
or its side."
  (let ((caster (caster patch))
        (seconds (min *freeze-max* seconds)))
    (when (< 0 seconds)
      (loop for c across *creatures*
            when (and (not (dead c)) (not (eq c caster)) (not (calm-p c))
                      (or (null caster) (hostile-p caster c))
                      (in-skin-p patch c) (<= (thaw c) 0.0))
              do (freeze c seconds)))
    (play-sound :freeze (location patch))))

(defun lay-frost-patch (at container &key (radius 1.5) (time 6.0) (strength 0) (freeze 0.0) caster
                                          (walls T) wall-base)
  "Lay a frost patch round point AT for CASTER, RADIUS metres for TIME seconds, freezing what it
forms under for FREEZE seconds; or renew the one CASTER has there. With no floor within
*PATCH-REACH* under AT, only the walls round it ice over (from WALL-BASE, by default 1.25 m under
AT). Returns the patch, or NIL."
  (when container
    (let ((floor (patch-floor-under (vx at) (vy at) (vz at))))
      (when (or floor walls)
        (let ((old (and floor
                        (find-if (lambda (p) (and (typep p 'frost-patch) (eq (caster p) caster) (container p)
                                                  (< (abs (- (skin-ground p) floor)) *patch-climb*)
                                                  (< (+ (expt (- (vx (location p)) (vx at)) 2)
                                                        (expt (- (vz (location p)) (vz at)) 2))
                                                     (expt *patch-renew-reach* 2))))
                                 *skins*))))
          (if old
              (progn (renew-skin old strength radius) old)
              (lay-skin (make-instance 'frost-patch
                                       :location (vec (vx at) (or floor (vy at)) (vz at))
                                       :ground (or floor (vy at)) :radius radius :time time
                                       :strength strength :freeze-time freeze :caster caster
                                       :floor-p (and floor T) :walls-p walls
                                       :wall-base (or wall-base (and (not floor) (- (vy at) 1.25))))
                        container)))))))

(defmethod skin-record ((patch frost-patch))
  (list* :freeze-time (freeze-time patch) (call-next-method)))

;;; The drawing: each kind's skins in one call, quads on their floors and walls a hair off them,
;;; written each frame into a stream buffer as the blood pool is (gore.lisp). The kind's texture is
;;; laid in world space at 64 texels a metre, lit as the face it lies on; its edge is the skin's
;;; circle, broken into jagged steps of whole texels and frosted in the kind's rim colours, and on
;;; walls a jagged top.

(defparameter *max-skin-cells* 2400 "Cells each kind's drawer draws at most, floors and walls together.")
(defparameter *skin-lift* 0.012 "Metres off its floor or wall a skin is drawn.")
(defparameter *skin-vertex-floats* 13
  "Per vertex: position, the skin's centre X Z and radius, the face's normal, the texture's two
world coordinates on the face, the top of a wall cell's skin (far up for a floor), and the
corner's cover (1 but for a :COVER kind's floor, SKIN-CORNER-COVER).")

(defun skin-corner-cover (heights n a b)
  "The share of the four cells round corner A B (0 to N each way) of a skin's grid of N by N
cells, HEIGHTS row by row, that are laid, on about the floor of the first laid one found."
  (declare (type (simple-array single-float (*)) heights) (type fixnum n a b))
  (let ((laid 0) (floor most-negative-single-float))
    (declare (type fixnum laid) (type single-float floor))
    (loop for (i j) in '((-1 -1) (0 -1) (-1 0) (0 0))
          for ci = (+ a i) and cj = (+ b j)
          do (when (and (< -1 ci n) (< -1 cj n))
               (let ((h (aref heights (+ ci (* cj n)))))
                 (when (< most-negative-single-float h)
                   (when (= floor most-negative-single-float) (setf floor h))
                   (when (< (abs (- h floor)) 0.3) (incf laid))))))
    (* 0.25 laid)))

(defvar *skin-floors* () "Each kind's drawer in the current scene.")

(define-shader-entity skin-floor (lit-entity renderable listener)
  ((kind :initarg :kind :reader skin-kind)
   (data :reader skin-data)
   (vbo :reader skin-vbo)
   (vao :reader skin-vao)))

(defmethod initialize-instance :after ((floor skin-floor) &key)
  (let* ((data (make-array (* *max-skin-cells* 6 *skin-vertex-floats*) :element-type 'single-float
                                                                        :initial-element 0f0))
         (vbo (make-instance 'vertex-buffer :buffer-data data :data-usage :stream-draw))
         (stride (* 4 *skin-vertex-floats*)))
    (setf (slot-value floor 'data) data
          (slot-value floor 'vbo) vbo
          (slot-value floor 'vao) (make-instance 'vertex-array
                                                 :vertex-form :triangles
                                                 :bindings `((,vbo :size 3 :offset 0 :stride ,stride :index 0)
                                                             (,vbo :size 3 :offset 12 :stride ,stride :index 1)
                                                             (,vbo :size 3 :offset 24 :stride ,stride :index 2)
                                                             (,vbo :size 3 :offset 36 :stride ,stride :index 3)
                                                             (,vbo :size 1 :offset 48 :stride ,stride :index 4))))))

(defun skin-texture (floor)
  (// 'hexmaw (skin-kind-property (skin-kind floor) :texture)))

(defmethod stage :after ((floor skin-floor) (area staging-area))
  (stage (skin-vao floor) area)
  (stage (skin-texture floor) area))

(defmethod bind-textures :after ((floor skin-floor))
  (bind (skin-texture floor) :texture0))

(defun add-skin-floors (scene)
  "A drawer for each kind of skin, in SCENE (SETUP-SCENE)."
  (setf *skin-floors*
        (loop for (kind) in *skin-kinds*
              collect (let ((floor (make-instance 'skin-floor :kind kind)))
                        (enter floor scene)
                        floor))))

(defun write-skin-vertices (floor)
  "Write every skin of FLOOR's kind into its data; how many vertices."
  (let ((data (skin-data floor))
        (kind (skin-kind floor))
        (k 0)
        (most (* *max-skin-cells* 6 *skin-vertex-floats*))
        (lift *skin-lift*)
        (cover-p (eq :cover (skin-kind-property (skin-kind floor) :edge)))
        (q 1f0))
    (declare (type (simple-array single-float (*)) data) (type fixnum k most) (type single-float q))
    ;; Q is the cover PUT writes: set before each corner.
    (flet ((put (x y z cx cz r nx ny nz u v top)
             (setf (aref data k) x (aref data (+ k 1)) y (aref data (+ k 2)) z
                   (aref data (+ k 3)) cx (aref data (+ k 4)) cz (aref data (+ k 5)) r
                   (aref data (+ k 6)) nx (aref data (+ k 7)) ny (aref data (+ k 8)) nz
                   (aref data (+ k 9)) u (aref data (+ k 10)) v (aref data (+ k 11)) top
                   (aref data (+ k 12)) q)
             (incf k 13)))
      (loop for entry across *skin-patches*
            when (eq kind (aref entry 11))
              do (let* ((cx (aref entry 0)) (cz (aref entry 2)) (r (aref entry 3))
                        (ox (aref entry 4)) (oz (aref entry 5)) (n (aref entry 6)) (c (aref entry 7))
                        (heights (aref entry 8))
                        (walls (aref entry 10))
                        (far 1f6))
                   (declare (type (simple-array single-float (*)) heights walls))
                   (dotimes (b n)
                     (dotimes (a n)
                       (let ((h (aref heights (+ a (* b n)))))
                         (when (and (< most-negative-single-float h) (<= (+ k (* 6 *skin-vertex-floats*)) most))
                           (let* ((x0 (float (+ ox (* a c)) 0f0)) (z0 (float (+ oz (* b c)) 0f0))
                                  (x1 (float (+ x0 c) 0f0)) (z1 (float (+ z0 c) 0f0))
                                  (y (float (+ h lift) 0f0)))
                             ;; Unless the whole cell lies outside its circle (a circle kind's).
                             (when (or cover-p
                                       (< (+ (expt (- (+ x0 (* 0.5 c)) cx) 2) (expt (- (+ z0 (* 0.5 c)) cz) 2))
                                          (expt (+ r (* 0.71 c)) 2)))
                               (flet ((corner (x z i j)
                                        (setf q (if cover-p (float (skin-corner-cover heights n (+ a i) (+ b j)) 0f0) 1f0))
                                        (put x y z cx cz r 0f0 1f0 0f0 x z far)))
                                 (corner x0 z0 0 0) (corner x1 z1 1 1) (corner x1 z0 1 0)
                                 (corner x0 z0 0 0) (corner x0 z1 0 1) (corner x1 z1 1 1))))))))
                   (setf q 1f0)
                   ;; Its wall cells, a hair out from their faces.
                   (let ((top (float (+ (aref entry 1) *skin-wall-height*) 0f0)))
                     (loop for w from 0 below (length walls) by 7
                           while (<= (+ k (* 6 *skin-vertex-floats*)) most)
                           do (let* ((normal (round (aref walls (+ w 6))))
                                     (s (float (signum normal) 0f0))
                                     (ax (aref walls w)) (ay (aref walls (+ w 1))) (az (aref walls (+ w 2)))
                                     (bx (aref walls (+ w 3))) (by (aref walls (+ w 4))) (bz (aref walls (+ w 5))))
                                (if (= 1 (abs normal))
                                    (let ((x (+ ax (* s lift))))
                                      (put x ay az cx cz r s 0f0 0f0 az ay top) (put x by bz cx cz r s 0f0 0f0 bz by top)
                                      (put x ay bz cx cz r s 0f0 0f0 bz ay top)
                                      (put x ay az cx cz r s 0f0 0f0 az ay top) (put x by az cx cz r s 0f0 0f0 az by top)
                                      (put x by bz cx cz r s 0f0 0f0 bz by top))
                                    (let ((z (+ az (* s lift))))
                                      (put ax ay z cx cz r 0f0 0f0 s ax ay top) (put bx by z cx cz r 0f0 0f0 s bx by top)
                                      (put bx ay z cx cz r 0f0 0f0 s bx ay top)
                                      (put ax ay z cx cz r 0f0 0f0 s ax ay top) (put ax by z cx cz r 0f0 0f0 s ax by top)
                                      (put bx by z cx cz r 0f0 0f0 s bx by top)))))))))
    (floor k *skin-vertex-floats*)))

(defmethod render ((floor skin-floor) (program shader-program))
  (when (< 0 (fill-pointer *skin-patches*))
    (let ((count (write-skin-vertices floor)))
      (when (< 0 count)
        (update-buffer-data (skin-vbo floor) (skin-data floor) :count (* count *skin-vertex-floats* 4))
        (setf (uniform program "view_matrix") (view-matrix))
        (setf (uniform program "projection_matrix") (projection-matrix))
        (set-fog-uniforms program)
        (setf (uniform program "texels_per_metre") *texels-per-metre*)
        ;; Smooth light, as the floors' (*WALL-LIGHT-SNAP*, lights.lisp, is 0).
        (setf (uniform program "light_snap") 0.0)
        (setf (uniform program "light_bands") 0.0)
        (destructuring-bind (r g b) (skin-kind-property (skin-kind floor) :rim)
          (setf (uniform program "rim_color") (vec r g b)))
        (destructuring-bind (r g b) (skin-kind-property (skin-kind floor) :inner)
          (setf (uniform program "inner_color") (vec r g b)))
        (setf (uniform program "cover_edge") (if (eq :cover (skin-kind-property (skin-kind floor) :edge)) 1.0 0.0))
        (render-array (skin-vao floor) :vertex-count count)))))

(define-class-shader (skin-floor :vertex-shader)
  "layout (location = 0) in vec3 position;
layout (location = 1) in vec3 in_patch;
layout (location = 2) in vec3 in_normal;
layout (location = 3) in vec3 in_face;
layout (location = 4) in float in_cover;
uniform mat4 view_matrix;
uniform mat4 projection_matrix;
out vec3 v_world_position;
out vec3 v_view_position;
out vec3 v_patch;
out vec3 v_normal;
out vec3 v_face;
out float v_cover;

void main(){
  vec4 view_position = view_matrix * vec4(position, 1.0);
  gl_Position = projection_matrix * view_position;
  v_world_position = position;
  v_view_position = view_position.xyz;
  v_patch = in_patch;
  v_normal = in_normal;
  v_face = in_face;
  v_cover = in_cover;
}")

(define-class-shader (skin-floor :fragment-shader)
  "in vec3 v_world_position;
in vec3 v_view_position;
in vec3 v_patch;
in vec3 v_normal;
in vec3 v_face;
in float v_cover;
uniform sampler2D texture_image;
uniform float texels_per_metre;
uniform vec3 rim_color;
uniform vec3 inner_color;
uniform float cover_edge;
out vec4 color;

float hash(float n){ return fract(sin(n * 127.1) * 43758.5453); }

void main(){
  // Whole texels of the world's grid on the face, as the level's faces are.
  vec2 texel = floor(v_face.xy * texels_per_metre) + 0.5;
  // Where it is across the level, to the nearest texel, for its circle.
  vec2 p = (floor(v_world_position.xz * texels_per_metre) + 0.5) / texels_per_metre - v_patch.xy;
  float r = v_patch.z;
  // Its edge: the circle, pulled in by up to 5 texels in jagged steps round it.
  float a = atan(p.y, p.x) / 6.2831853 + 0.5;
  float edge = r - floor(hash(floor(a * 48.0)) * 6.0) / texels_per_metre;
  float d = length(p);
  float in_rim;
  if(cover_edge > 0.5){
    // Its cells' own outline: the corners' cover, ragged by noise in blocks of 3 texels.
    vec2 block = floor(v_world_position.xz * texels_per_metre / 3.0);
    float value = v_cover + (hash(block.x * 7.13 + block.y * 157.31) - 0.5) * 0.4;
    if(value < 0.5) discard;
    in_rim = (value - 0.5) * 32.0;
  }else{
    if(d > edge) discard;
    in_rim = (edge - d) * texels_per_metre;
  }
  // On a wall, a jagged top as well.
  float top = v_face.z - floor(hash(floor(texel.x / 4.0) + 17.0) * 8.0) / texels_per_metre;
  float y = (floor(v_world_position.y * texels_per_metre) + 0.5) / texels_per_metre;
  if(y > top) discard;
  in_rim = min(in_rim, (top - y) * texels_per_metre);
  vec4 tex = texture(texture_image, texel / vec2(textureSize(texture_image, 0)));
  if(tex.a < 0.5) discard;
  // Frosted at the rim, paler just inside it.
  vec3 surface = in_rim < 3.0 ? rim_color : (in_rim < 7.0 ? mix(tex.rgb, inner_color, 0.5) : tex.rgb);
  vec3 normal = normalize(v_normal);
  vec3 light = band_light(light_at(snap_position(v_world_position), normal, 1.0, v_world_position + normal * 0.05));
  vec3 lamp = lamp_part(light);
  color = vec4(fog_lit(surface * (light - lamp), surface * lamp, length(v_view_position)), 1.0);
}")
