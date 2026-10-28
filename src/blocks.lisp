(in-package #:hexmaw)

;;; Level blocks: hand-authored pieces of dungeon in glTF (Blender exports, or
;;; tools/make_test_block.py), placed by the level and later by the generator.
;;; Authoring conventions, also in CLAUDE.md:
;;;
;;;  - Metres, +Y up, the block's origin at its centre on the floor.
;;;  - Every mesh object is drawn and its bounding box is a solid, unless its name
;;;    starts with "deco_" (drawn, no collision).
;;;  - Empties named "connector_<anything>" mark doorways. A connector faces the
;;;    direction from the origin to it, snapped to north/east/south/west.
;;;  - Empties named "spawn_<monster>" place a monster facing the empty's -Z.
;;;  - A material's base colour is the piece's colour (no textures yet).
;;;
;;; Blocks turn in quarter turns only, so solids stay axis-aligned boxes.

(defun gltf-mesh-data (mesh)
  "Trial mesh data for each primitive of glTF MESH, in primitive order."
  (org.shirakumo.fraf.trial.gltf::load-mesh mesh))

(defun gltf-node-transform (node)
  "NODE's transform within its file, parents included."
  (org.shirakumo.fraf.trial.gltf::gltf-node-transform* node))

(defun prefixp (prefix string)
  (and (<= (length prefix) (length string))
       (string-equal prefix string :end2 (length prefix))))

;;; Directions and quarter turns. Turning counter-clockwise seen from above takes
;;; north to west to south to east.

(defparameter *directions* '(:north :west :south :east))

(defun snap-direction (position)
  (if (< (abs (vz position)) (abs (vx position)))
      (if (< 0 (vx position)) :east :west)
      (if (< 0 (vz position)) :south :north)))

(defun turn-direction (direction turns)
  (nth (mod (+ (position direction *directions*) turns) 4) *directions*))

(defun turns-between (from to)
  "Quarter turns counter-clockwise that take direction FROM to direction TO."
  (mod (- (position to *directions*) (position from *directions*)) 4))

(defun turn-point (point turns)
  "A new vector: POINT turned TURNS quarter turns counter-clockwise about the Y axis."
  (let ((x (vx point)) (y (vy point)) (z (vz point)))
    (ecase (mod turns 4)
      (0 (vec x y z))
      (1 (vec z y (- x)))
      (2 (vec (- x) y (- z)))
      (3 (vec (- z) y x)))))

(defun rotation-yaw (rotation)
  "Yaw, in the player's convention (0 faces -Z), of the -Z axis turned by ROTATION."
  (let ((forward (q* rotation (vec 0 0 -1))))
    (float (atan (vx forward) (- (vz forward))) 0f0)))

;;; Reading blocks.

(defun primitive-color (primitive)
  (let* ((material (org.shirakumo.fraf.gltf:material primitive))
         (pbr (and material (org.shirakumo.fraf.gltf:pbr material)))
         (c (and pbr (org.shirakumo.fraf.gltf:albedo-factor pbr))))
    (if c
        (vec4 (aref c 0) (aref c 1) (aref c 2) 1)
        (vec4 0.6 0.6 0.6 1))))

(defun primitive-bounds (primitive transform)
  "(MIN MAX) of PRIMITIVE's positions after TRANSFORM, as vectors."
  (let* ((positions (gethash :position (org.shirakumo.fraf.gltf:attributes primitive)))
         (lo (org.shirakumo.fraf.gltf:minimum positions))
         (hi (org.shirakumo.fraf.gltf:maximum positions))
         (min (vec most-positive-single-float most-positive-single-float most-positive-single-float))
         (max (vec most-negative-single-float most-negative-single-float most-negative-single-float)))
    (dolist (x (list (aref lo 0) (aref hi 0)))
      (dolist (y (list (aref lo 1) (aref hi 1)))
        (dolist (z (list (aref lo 2) (aref hi 2)))
          (let ((p (t*p transform (vec x y z))))
            (setf min (vmin min p) max (vmax max p))))))
    (list min max)))

(defun read-block (path)
  "Read the block at PATH into a plist of :PIECES, :CONNECTORS and :SPAWNS."
  (let ((pieces ()) (connectors ()) (spawns ()))
    (org.shirakumo.fraf.gltf:with-gltf (gltf path)
      (loop for node across (org.shirakumo.fraf.gltf:nodes gltf)
            for name = (or (org.shirakumo.fraf.gltf:name node) "")
            for transform = (gltf-node-transform node)
            for mesh = (org.shirakumo.fraf.gltf:mesh node)
            do (cond (mesh
                      (loop for primitive across (org.shirakumo.fraf.gltf:primitives mesh)
                            for data in (gltf-mesh-data mesh)
                            do (push (list :name name
                                           :vertex-array (make-vertex-array data NIL)
                                           :color (primitive-color primitive)
                                           :transform transform
                                           :bounds (primitive-bounds primitive transform)
                                           :solid (not (prefixp "deco_" name)))
                                     pieces)))
                     ((prefixp "connector_" name)
                      (push (list :name name
                                  :position (vcopy (tlocation transform))
                                  :direction (snap-direction (tlocation transform)))
                            connectors))
                     ((prefixp "spawn_" name)
                      (push (list :kind (subseq name (length "spawn_"))
                                  :position (vcopy (tlocation transform))
                                  :yaw (rotation-yaw (trotation transform)))
                            spawns)))))
    (list :pieces (nreverse pieces) :connectors (nreverse connectors) :spawns (nreverse spawns))))

(defvar *blocks* (make-hash-table :test 'equal)
  "Read blocks by file name: (file-date . definition).")

(defun block-path (name)
  (merge-pathnames (format NIL "data/blocks/~(~a~).glb" name) (root)))

(defun find-block (name)
  "The definition of block NAME (data/blocks/<name>.glb), re-read when the file changes."
  (let* ((path (block-path name))
         (date (file-write-date path))
         (cached (gethash (namestring path) *blocks*)))
    (if (and cached (eql date (car cached)))
        (cdr cached)
        (cdr (setf (gethash (namestring path) *blocks*) (cons date (read-block path)))))))

;;; Placing blocks.

(define-shader-entity block-piece (greybox) ()
  (:documentation "A mesh from a block, drawn like the greybox geometry."))

(defun place-block (name container &key (at (vec 0 0 0)) (turns 0))
  "Place block NAME with its origin at AT, turned TURNS quarter turns counter-clockwise
seen from above. Enters its pieces into CONTAINER, adds its solids to *SOLIDS* and spawns
its monsters. Returns its connectors in world space: a list of (NAME POSITION DIRECTION)."
  (let ((def (find-block name))
        (rotation (qfrom-angle +vy+ (* turns (float (/ pi 2) 0f0))))
        (low (vec most-positive-single-float most-positive-single-float most-positive-single-float))
        (high (vec most-negative-single-float most-negative-single-float most-negative-single-float)))
    (flet ((world (point) (nv+ (turn-point point turns) at)))
      ;; The whole block is one room, walls and all, and its doorways are portals.
      (dolist (piece (getf def :pieces))
        (dolist (corner (getf piece :bounds))
          (let ((p (world corner)))
            (setf low (vmin low p) high (vmax high p)))))
      (add-room (vx low) (vy low) (vz low) (vx high) (vy high) (vz high))
      (dolist (c (getf def :connectors))
        (add-doorway-portal (world (getf c :position)) (turn-direction (getf c :direction) turns)))
      (dolist (piece (getf def :pieces))
        (let ((tf (getf piece :transform)))
          (enter (make-instance 'block-piece :vertex-array (getf piece :vertex-array)
                                             :color (getf piece :color)
                                             :location (world (tlocation tf))
                                             :orientation (q* rotation (trotation tf))
                                             :scaling (vcopy (tscaling tf)))
                 container))
        (when (getf piece :solid)
          (destructuring-bind (lo hi) (getf piece :bounds)
            (let ((a (world lo)) (b (world hi)))
              (vector-push-extend (make-solid (vx a) (vy a) (vz a) (vx b) (vy b) (vz b)) *solids*)))))
      (dolist (spawn (getf def :spawns))
        (let ((class (find-symbol (string-upcase (getf spawn :kind)) '#:hexmaw)))
          (if (and class (find-class class NIL) (subtypep class 'creature))
              (spawn-creature (make-instance class :location (world (getf spawn :position))
                                                   :facing (- (getf spawn :yaw) (* turns (float (/ pi 2) 0f0))))
                              container)
              (v:warn :hexmaw "Block ~a: no creature called ~s; spawn ignored." name (getf spawn :kind)))))
      (loop for c in (getf def :connectors)
            collect (list (getf c :name) (world (getf c :position)) (turn-direction (getf c :direction) turns))))))

(defparameter *doorway-width* 3.0 "Doorways are this wide and *DOORWAY-HEIGHT* tall in every block.")
(defparameter *doorway-height* 3.0)

(defun add-doorway-portal (position direction)
  "A flat portal filling the doorway of a connector at POSITION facing DIRECTION. If
nothing is attached there, LINK-ROOMS finds no room beyond and drops it."
  (let ((x (vx position)) (y (vy position)) (z (vz position))
        (half (/ *doorway-width* 2)))
    (if (member direction '(:north :south))
        (add-portal (- x half) y z (+ x half) (+ y *doorway-height*) z)
        (add-portal x y (- z half) x (+ y *doorway-height*) (+ z half)))))

(defun seal-connector (container position direction &key (color *wall-color*))
  "Wall off the doorway of a connector at POSITION facing DIRECTION, outside the block."
  (let* ((x (vx position)) (y (vy position)) (z (vz position))
         (half (/ *doorway-width* 2)) (top (+ y *doorway-height*)) (thick 0.5))
    (ecase direction
      (:north (add-box container (- x half) y (- z thick) (+ x half) top z :color color))
      (:south (add-box container (- x half) y z (+ x half) top (+ z thick) :color color))
      (:west (add-box container (- x thick) y (- z half) x top (+ z half) :color color))
      (:east (add-box container x y (- z half) (+ x thick) top (+ z half) :color color)))))

(defun attach-block (name container connector &key at facing)
  "Place block NAME so that its connector named CONNECTOR sits at AT, facing FACING:
the direction the doorway opens toward, back at whatever it attaches to.
Returns the placed block's connectors, as PLACE-BLOCK does."
  (let* ((def (find-block name))
         (c (or (find connector (getf def :connectors) :key (lambda (c) (getf c :name)) :test #'string-equal)
                (error "Block ~a has no connector ~s; it has ~{~a~^, ~}." name connector
                       (mapcar (lambda (c) (getf c :name)) (getf def :connectors)))))
         (turns (turns-between (getf c :direction) facing)))
    (place-block name container :at (v- at (turn-point (getf c :position) turns)) :turns turns)))
