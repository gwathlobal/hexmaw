(in-package #:hexmaw)

;;; Level blocks: pieces of dungeon in glTF, placed by the level and the generator. Most
;;; are built from text blueprints (data/blueprints/, src/blueprint.lisp); any Blender
;;; export that keeps the conventions works too. Authoring conventions, also in CLAUDE.md:
;;;
;;;  - Metres, +Y up, the block's origin at its centre on the floor. On the grid, a block
;;;    is whole 4 m cells across and whole 5 m storeys tall.
;;;  - Every mesh object is drawn and its bounding box is a solid, unless its name
;;;    starts with "deco_" (drawn, no collision), "plug_" (see below), or "lava_" or
;;;    "water_" (not drawn: a liquid's volume, liquids.lisp). One named
;;;    "wedge_<n>_..." is that box with a vertical corner cut away along the diagonal
;;;    (n: 1 north-east, 2 north-west, 3 south-west, 4 south-east, as the block lies),
;;;    a 45° wall when the box is square; the mesh must be that shape.
;;;  - Empties named "connector_<rest>" mark doorways, on the block's outer face. A
;;;    connector faces out through the face it lies on. <rest> starting with a kind and
;;;    "_" (connector_narrow_north) gives its kind, else it's a door.
;;;  - Meshes named "plug_<rest>" fill the doorway of connector_<rest>. They're left out
;;;    when the block is placed, and SEAL-CONNECTOR puts them in to shut it.
;;;  - Empties named "spawn_<monster>" place a monster facing the empty's -Z, and empties
;;;    named "torch_<anything>" a torch whose flame stands there (ADD-TORCH).
;;;  - A material named after a surface in *SURFACES* (wall, floor, ceiling, ...) draws
;;;    that surface's textures; any other material is flat in its base colour. The
;;;    textures come from the game, laid on in world space; a .glb's own aren't read.
;;;  - The scene's extras may give "tags" and a "weight", for the generator.
;;;  - Blender's duplicate suffix (".001") is ignored in every name.
;;;
;;; Blocks turn in quarter turns only, so solids stay axis-aligned boxes.

(defun gltf-mesh-data (mesh)
  "Trial mesh data for each primitive of glTF MESH, in primitive order."
  (org.shirakumo.fraf.trial.gltf::load-mesh mesh))

(defun gltf-node-transform (node)
  "NODE's transform within its file, parents included."
  (org.shirakumo.fraf.trial.gltf::gltf-node-transform* node))

(defun wedge-name-cut (name)
  "The corner a piece named wedge_<n>_... has cut away (1 to 4), or 0."
  (if (and (< 7 (length name)) (string-equal "wedge_" name :end2 6) (digit-char-p (char name 6)))
      (digit-char-p (char name 6))
      0))

(defun prefixp (prefix string)
  (and (<= (length prefix) (length string))
       (string-equal prefix string :end2 (length prefix))))

(defun liquid-name-kind (name)
  "The liquid kind a piece named NAME is the volume of, or NIL."
  (cond ((prefixp "lava_" name) :lava)
        ((prefixp "water_" name) :water)))

(defun base-name (name)
  "NAME without a Blender duplicate's suffix, \".001\"."
  (subseq name 0 (position #\. name)))

;;; Directions and quarter turns. Turning counter-clockwise seen from above takes
;;; north to west to south to east.

(defparameter *directions* '(:north :west :south :east))

(defun snap-direction (position)
  (if (< (abs (vz position)) (abs (vx position)))
      (if (< 0 (vx position)) :east :west)
      (if (< 0 (vz position)) :south :north)))

(defun turn-direction (direction turns)
  (nth (mod (+ (position direction *directions*) turns) 4) *directions*))

(defun opposite-direction (direction)
  (turn-direction direction 2))

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

;;; Connector kinds, shared with the blueprint builder.

(defun connector-size (kind)
  "The width and height of a doorway of KIND."
  (let ((spec (or (assoc kind hexmaw.blueprint:*connector-kinds* :test #'string-equal)
                  (error "No connector kind ~s." kind))))
    (values (second spec) (third spec))))

(defun connector-name-kind (rest)
  "The kind a connector named connector_REST has."
  (or (loop for (kind) in hexmaw.blueprint:*connector-kinds*
            when (and (string-not-equal kind "door") (prefixp (format NIL "~a_" kind) rest))
            return (string-downcase kind))
      "door"))

;;; Reading blocks.

(defun primitive-color (primitive)
  (let* ((material (org.shirakumo.fraf.gltf:material primitive))
         (pbr (and material (org.shirakumo.fraf.gltf:pbr material)))
         (c (and pbr (org.shirakumo.fraf.gltf:albedo-factor pbr))))
    (if c
        (vec4 (aref c 0) (aref c 1) (aref c 2) 1)
        (vec4 0.6 0.6 0.6 1))))

(defun primitive-material-name (primitive)
  (let ((material (org.shirakumo.fraf.gltf:material primitive)))
    (and material (org.shirakumo.fraf.gltf:name material))))

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

(defun face-direction (position low high)
  "The direction out of the face of the box LOW HIGH that POSITION lies on, or nearest."
  (let ((faces (list (cons (abs (- (vz position) (vz low))) :north)
                     (cons (abs (- (vz position) (vz high))) :south)
                     (cons (abs (- (vx position) (vx low))) :west)
                     (cons (abs (- (vx position) (vx high))) :east))))
    (cdr (first (sort faces #'< :key #'car)))))

(defun read-block (path)
  "Read the block at PATH into a plist of :PIECES, :CONNECTORS, :SPAWNS, :TORCHES, :LIQUIDS
(each :KIND and :BOUNDS), :BOUNDS
(min and max corners of its pieces), :TAGS and :WEIGHT. A connector is a plist of :NAME
:KIND :POSITION :DIRECTION :STOREY and :PLUGS, the pieces that shut it."
  (let ((pieces ()) (plugs ()) (connectors ()) (spawns ()) (torches ()) (liquids ()) (tags ()) (weight 1.0)
        (low (vec most-positive-single-float most-positive-single-float most-positive-single-float))
        (high (vec most-negative-single-float most-negative-single-float most-negative-single-float)))
    (org.shirakumo.fraf.gltf:with-gltf (gltf path)
      (loop for node across (org.shirakumo.fraf.gltf:nodes gltf)
            for name = (base-name (or (org.shirakumo.fraf.gltf:name node) ""))
            for transform = (gltf-node-transform node)
            for mesh = (org.shirakumo.fraf.gltf:mesh node)
            do (cond (mesh
                      (loop for primitive across (org.shirakumo.fraf.gltf:primitives mesh)
                            for data in (gltf-mesh-data mesh)
                            for bounds = (primitive-bounds primitive transform)
                            for piece = (list :name name
                                              :mesh data
                                              :vertex-array (make-vertex-array data NIL)
                                              :color (primitive-color primitive)
                                              :material (primitive-material-name primitive)
                                              :transform transform
                                              :bounds bounds
                                              :solid (not (or (prefixp "deco_" name) (liquid-name-kind name)))
                                              :cut (wedge-name-cut name))
                            do (setf low (vmin low (first bounds)) high (vmax high (second bounds)))
                               (cond ((prefixp "plug_" name)
                                      (push (cons (subseq name (length "plug_")) piece) plugs))
                                     ;; A liquid's mesh is only its volume; LIQUID-SURFACE draws it.
                                     ((liquid-name-kind name)
                                      (push (list :kind (liquid-name-kind name) :bounds bounds) liquids))
                                     (T
                                      (push piece pieces)))))
                     ((prefixp "connector_" name)
                      (let ((rest (subseq name (length "connector_"))))
                        (push (list :name name :rest rest :kind (connector-name-kind rest)
                                    :position (vcopy (tlocation transform)))
                              connectors)))
                     ((prefixp "spawn_" name)
                      (push (list :kind (subseq name (length "spawn_"))
                                  :position (vcopy (tlocation transform))
                                  :yaw (rotation-yaw (trotation transform)))
                            spawns))
                     ((prefixp "torch_" name)
                      (push (vcopy (tlocation transform)) torches))))
      (let* ((scenes (org.shirakumo.fraf.gltf:scenes gltf))
             (extras (and (plusp (length scenes)) (org.shirakumo.fraf.gltf:extras (aref scenes 0)))))
        (when (hash-table-p extras)
          (setf tags (map 'list (lambda (tag) (intern (string-upcase tag) :keyword)) (gethash "tags" extras #()))
                weight (float (gethash "weight" extras 1.0) 0f0)))))
    (setf connectors
          (loop for c in connectors
                for position = (getf c :position)
                collect (list* :direction (face-direction position low high)
                               :storey (round (vy position) hexmaw.blueprint:*storey-height*)
                               :plugs (loop for (rest . piece) in plugs
                                            when (string-equal rest (getf c :rest)) collect piece)
                               c)))
    (loop for (rest) in plugs
          unless (find rest connectors :key (lambda (c) (getf c :rest)) :test #'string-equal)
          do (v:warn :hexmaw "~a: plug_~a has no connector_~:*~a." (file-namestring path) rest))
    (list :pieces (nreverse pieces) :connectors (nreverse connectors) :spawns (nreverse spawns)
          :torches (nreverse torches) :liquids (nreverse liquids) :bounds (list low high) :tags tags :weight weight)))

(defvar *blocks* (make-hash-table :test 'equal)
  "Read blocks by file name: (file-date . definition).")

(defun block-path (name)
  (data-path (format NIL "blocks/~(~a~).glb" name)))

(defvar *block-memo* NIL
  "While a level is built (BUILD-LEVEL), a table of the definitions FIND-BLOCK has given, by
name. The generator asks for every block's tags and weight thousands of times a level, and
each FIND-BLOCK looks at the files: half a millisecond.")

(defun find-block (name)
  "The definition of block NAME (data/blocks/<name>.glb), re-read when the file changes.
A block with a blueprint is built from it first if the blueprint is newer."
  (let ((key (and *block-memo* (string-downcase (string name)))))
    (or (and key (gethash key *block-memo*))
        (let ((def (progn
                     (hexmaw.blueprint:ensure-block name)
                     (let* ((path (block-path name))
                            (date (file-write-date path))
                            (cached (gethash (namestring path) *blocks*)))
                       (if (and cached (eql date (car cached)))
                           (cdr cached)
                           (cdr (setf (gethash (namestring path) *blocks*) (cons date (read-block path)))))))))
          (when key (setf (gethash key *block-memo*) def))
          def))))

;;; Where a block goes, before placing it.

(defun block-world-bounds (name at turns)
  "The min and max corners of block NAME placed at AT, turned TURNS quarter turns."
  (destructuring-bind (lo hi) (getf (find-block name) :bounds)
    (let ((a (nv+ (turn-point lo turns) at)) (b (nv+ (turn-point hi turns) at)))
      (values (vmin a b) (vmax a b)))))

(defun block-cells (name at turns)
  "The grid cells (i j k) that block NAME fills placed at AT, turned TURNS: cell i j
spans x 4i..4i+4 and z 4j..4j+4, storey k from 5k - 0.5."
  (multiple-value-bind (low high) (block-world-bounds name at turns)
    (let ((size hexmaw.blueprint:*cell-size*)
          (storey hexmaw.blueprint:*storey-height*))
      (loop for i from (round (vx low) size) below (round (vx high) size)
            nconc (loop for j from (round (vz low) size) below (round (vz high) size)
                        nconc (loop for k from (round (+ (vy low) 0.5) storey)
                                      below (ceiling (- (+ (vy high) 0.5) 1e-3) storey)
                                    collect (list i j k)))))))

(defun attach-placement (name connector at facing)
  "Where block NAME goes so its connector named CONNECTOR sits at AT, facing FACING:
its origin and its quarter turns."
  (let* ((def (find-block name))
         (c (or (find connector (getf def :connectors) :key (lambda (c) (getf c :name)) :test #'string-equal)
                (error "Block ~a has no connector ~s; it has ~{~a~^, ~}." name connector
                       (mapcar (lambda (c) (getf c :name)) (getf def :connectors)))))
         (turns (turns-between (getf c :direction) facing)))
    (values (v- at (turn-point (getf c :position) turns)) turns)))

;;; Placing blocks.

(define-shader-entity block-piece (greybox) ()
  (:documentation "A mesh from a block, drawn like the greybox geometry."))

(defclass connector ()
  ((name :initarg :name :reader connector-name)
   (location :initarg :location :reader connector-location :documentation "On the doorway's floor, in world space.")
   (direction :initarg :direction :reader connector-direction :documentation "The way it opens, out of the block.")
   (kind :initarg :kind :reader connector-kind)
   (storey :initarg :storey :reader connector-storey :documentation "The block's storey it is on.")
   (block-name :initarg :block-name :reader connector-block)
   (plug :initarg :plug :initform NIL :reader connector-plug
         :documentation "A function of a container that enters the plug, or NIL.")
   (portal :initarg :portal :initform NIL :reader connector-portal
           :documentation "The portal in its doorway, which sealing it removes."))
  (:documentation "A placed block's doorway, as PLACE-BLOCK returns them."))

(defmethod print-object ((c connector) stream)
  (print-unreadable-object (c stream :type T)
    (format stream "~a ~a ~(~a~)" (connector-block c) (connector-name c) (connector-direction c))))

(defvar *level-doorways* ()
  "Every doorway of the blocks placed in the level, plugged or not. BUILD-LEVEL empties it,
and CHECK-REACHABLE walks to each.")

;;; Batching. Every entity costs about 20 GL calls a frame whatever its size, and a
;;; jagged block is dozens of boxes, so while a level is built (WITH-BLOCK-BATCHES) the
;;; pieces don't become entities: their triangles are gathered in world space, one batch
;;; per look (textures and colour), and each batch is drawn as one BLOCK-PIECE. The
;;; greybox shader works in world space, so nothing shows the difference.

(defvar *block-batches* NIL
  "While a level is built, the batches ENTER-PIECE adds to: (textures colour) -> a list
of (vertex-data faces), newest first. NIL enters each piece on its own.")

(defmacro with-block-batches ((container) &body body)
  "Run BODY with the block pieces it places batched, then enter the batches into CONTAINER."
  `(let ((*block-batches* (make-hash-table :test 'equal)))
     (multiple-value-prog1 (progn ,@body)
       (flush-block-batches ,container))))

(defun batch-piece (piece textures color world rotation)
  "Add PIECE's triangles, placed by WORLD and turned by ROTATION, to their batch."
  (let* ((tf (getf piece :transform))
         (mesh (getf piece :mesh))
         (placed (transform (funcall world (tlocation tf)) (vcopy (tscaling tf)) (q* rotation (trotation tf))))
         (attributes (vertex-attributes mesh))
         (stride (vertex-attribute-stride mesh))
         (location (vertex-attribute-offset 'location mesh))
         (normal (and (member 'normal attributes) (vertex-attribute-offset 'normal mesh)))
         (data (copy-seq (vertex-data mesh)))
         (point (vec3)))
    (loop for i from 0 below (length data) by stride
          do (flet ((turn (offset place)
                      (setf (vx point) (aref data (+ i offset))
                            (vy point) (aref data (+ i offset 1))
                            (vz point) (aref data (+ i offset 2)))
                      (let ((p (if place (t*p placed point) (q* (trotation placed) point))))
                        (setf (aref data (+ i offset)) (vx p)
                              (aref data (+ i offset 1)) (vy p)
                              (aref data (+ i offset 2)) (vz p)))))
               (turn location T)
               (when normal (turn normal NIL))))
    (push (list data (faces mesh) attributes)
          (gethash (list textures (list (vx color) (vy color) (vz color) (vw color))) *block-batches*))))

(defun flush-block-batches (container)
  "Enter each batch of *BLOCK-BATCHES* into CONTAINER as one BLOCK-PIECE, and empty it."
  (maphash (lambda (key parts)
             (destructuring-bind (textures (r g b a)) key
               (let* ((parts (reverse parts))
                      (attributes (third (first parts)))
                      (stride (loop for a in attributes sum (vertex-attribute-size a)))
                      (data (make-array (reduce #'+ parts :key (lambda (p) (length (first p))))
                                        :element-type 'single-float))
                      (faces (make-array (reduce #'+ parts :key (lambda (p) (length (second p))))
                                         :element-type '(unsigned-byte 32)))
                      (d 0) (f 0))
                 (loop for (part-data part-faces) in parts
                       for base = (floor d stride)
                       do (replace data part-data :start1 d)
                          (loop for index across part-faces
                                do (setf (aref faces f) (+ base index)) (incf f))
                          (incf d (length part-data)))
                 (enter (make-instance 'block-piece
                                       :vertex-array (make-vertex-array
                                                      (make-instance 'mesh-data :vertex-data data :faces faces
                                                                                :vertex-form :triangles
                                                                                :vertex-attributes attributes)
                                                      NIL)
                                       :color (vec4 r g b a)
                                       :face-textures textures)
                        container))))
           *block-batches*)
  (clrhash *block-batches*))

(defun enter-piece (piece container world rotation)
  "Enter PIECE of a block, its points placed by WORLD and turned by ROTATION, into
CONTAINER (or its batch, while a level is built), and add its solid to *SOLIDS*."
  (let* ((tf (getf piece :transform))
         (textures (surface-textures (getf piece :material)))
         (color (if textures (vec4 1 1 1 1) (getf piece :color)))
         (cut (or (getf piece :cut) 0)))
    ;; Its twin on the automap, in the block being placed (automap.lisp). Never batched:
    ;; the map shows a block's pieces only once it's revealed.
    (add-map-piece container (getf piece :vertex-array)
                   (funcall world (tlocation tf)) (q* rotation (trotation tf)) (vcopy (tscaling tf))
                   (funcall world (first (getf piece :bounds))) (funcall world (second (getf piece :bounds)))
                   :surface (getf piece :material) :color (getf piece :color)
                   :cut (if (= 0 cut) 0 (turn-cut cut (q* rotation (trotation tf)))))
    ;; A block read before batching existed (*BLOCKS* outlives reloads) has no :MESH.
    (if (and *block-batches* (getf piece :mesh))
        (batch-piece piece textures color world rotation)
        (enter (make-instance 'block-piece :vertex-array (getf piece :vertex-array)
                                           :color color
                                           :face-textures textures
                                           :location (funcall world (tlocation tf))
                                           :orientation (q* rotation (trotation tf))
                                           :scaling (vcopy (tscaling tf)))
               container))
    (when (getf piece :solid)
      (destructuring-bind (lo hi) (getf piece :bounds)
        (let* ((a (funcall world lo)) (b (funcall world hi))
               (min (vmin a b)) (max (vmax a b))
               (cut (or (getf piece :cut) 0)))
          (vector-push-extend (make-solid (vx min) (vy min) (vz min) (vx max) (vy max) (vz max)
                                          (if (= 0 cut) 0 (turn-cut cut (q* rotation (trotation tf))))
                                          (surface-footing (getf piece :material)))
                              *solids*))))))

(defun turn-cut (cut rotation)
  "Wedge corner CUT (1 to 4) as it lies once turned by ROTATION, a quarter turn about Y."
  (multiple-value-bind (east south) (case cut (1 (values 1 -1)) (2 (values -1 -1)) (3 (values -1 1)) (4 (values 1 1)))
    (let ((d (q* rotation (vec east 0 south))))
      (corner-cut (< 0 (vx d)) (< 0 (vz d))))))

(defparameter *spawn-pool* '(("imp" 3) ("acolyte" 1) ("knight" 1) ("harpy" 1) ("necromancer" 1) ("ogre" 1))
  "What a block's spawn_any picks from, each monster with its weight.")

(defvar *spawn-clearance* NIL
  "(point . metres) while a level is generated: no block spawns a monster that close to
the point, the player's start.")

(defvar *block-random* (make-random-state T)
  "Picks among a spawn's choices. The generator binds it to its own, seeded, state.")

(defun spawn-choice (kind)
  "The monster a spawn of KIND places: KIND itself, one of \"a|b|c\" (alike), for
\"any\" one of *SPAWN-POOL* by weight, or for \"any-a|b\" one of the pool but those (a
block too tight for them)."
  (let* ((choices (cond ((string-equal kind "any") *spawn-pool*)
                        ((and (< 4 (length kind)) (string-equal kind "any-" :end1 4))
                         (let ((left-out (uiop:split-string (subseq kind 4) :separator "|")))
                           (remove-if (lambda (choice) (member (first choice) left-out :test #'string-equal))
                                      *spawn-pool*)))
                        (T (mapcar (lambda (k) (list k 1)) (uiop:split-string kind :separator "|")))))
         (pick (and choices (random (reduce #'+ choices :key #'second) *block-random*))))
    (loop for (name weight) in choices
          do (decf pick weight)
          when (< pick 0) return name
          ;; NIL when every choice was left out.
          finally (return (first (car (last choices)))))))

(defun place-block (name container &key (at (vec 0 0 0)) (turns 0) (spawns T))
  "Place block NAME with its origin at AT, turned TURNS quarter turns counter-clockwise
seen from above. Enters its pieces into CONTAINER, adds its solids to *SOLIDS*, its room
and doorway portals, its torches, and spawns its monsters unless SPAWNS is NIL. Its
doorways stay open: returns them as CONNECTORs, for the next block or SEAL-CONNECTOR."
  (let* ((def (find-block name))
         (rotation (qfrom-angle +vy+ (* turns (float (/ pi 2) 0f0))))
         (*map-block* (multiple-value-call #'add-map-block name (block-world-bounds name at turns)))
         (map-block *map-block*))
    (flet ((world (point) (nv+ (turn-point point turns) at)))
      ;; The whole block is one room, walls and all, and its doorways are portals.
      (multiple-value-bind (low high) (block-world-bounds name at turns)
        (add-room (vx low) (vy low) (vz low) (vx high) (vy high) (vz high)))
      (let ((portals (loop for c in (getf def :connectors)
                           collect (add-doorway-portal (world (getf c :position))
                                                       (turn-direction (getf c :direction) turns)
                                                       (getf c :kind)))))
        (dolist (piece (getf def :pieces))
          (enter-piece piece container #'world rotation))
        (dolist (liquid (getf def :liquids))
          (destructuring-bind (lo hi) (getf liquid :bounds)
            (let ((a (world lo)) (b (world hi)))
              (add-liquid container (getf liquid :kind)
                          (vx a) (vy a) (vz a) (vx b) (vy b) (vz b)))))
        ;; After the solids, so ADD-TORCH finds the walls.
        (dolist (p (getf def :torches))
          (let ((w (world p)))
            (add-torch container (vx w) (vy w) (vz w))))
        (dolist (spawn (and spawns (getf def :spawns)))
          ;; The choice is made even for a spawn left out, so a seed builds the same level.
          (let* ((kind (spawn-choice (getf spawn :kind)))
                 (class (and kind (find-symbol (string-upcase kind) '#:hexmaw)))
                 (at (world (getf spawn :position))))
            (cond
              ((null kind))
              ((and *spawn-clearance* (< (vdistance at (car *spawn-clearance*)) (cdr *spawn-clearance*))))
              ((and class (find-class class NIL) (subtypep class 'creature))
                (spawn-creature (make-instance class :location at
                                                     :facing (- (getf spawn :yaw) (* turns (float (/ pi 2) 0f0))))
                                container))
              (T (v:warn :hexmaw "Block ~a: no creature called ~s; spawn ignored." name kind)))))
        (loop for c in (getf def :connectors)
              for portal in portals
              collect (let ((plugs (getf c :plugs)))
                        (first
                         (push (make-instance 'connector
                                              :name (getf c :name) :block-name name
                                              :location (world (getf c :position))
                                              :direction (turn-direction (getf c :direction) turns)
                                              :kind (getf c :kind) :storey (getf c :storey) :portal portal
                                              :plug (when plugs
                                                      (lambda (container)
                                                        ;; Sealed later, but still part of this block's map.
                                                        (let ((*map-block* map-block))
                                                          (dolist (piece plugs)
                                                            (enter-piece piece container #'world rotation))))))
                               *level-doorways*))))))))

(defun add-doorway-portal (position direction &optional (kind "door"))
  "A flat portal filling the doorway of a connector at POSITION facing DIRECTION. If
nothing is attached there, LINK-ROOMS finds no room beyond and drops it."
  (multiple-value-bind (width height) (connector-size kind)
    (let ((x (vx position)) (y (vy position)) (z (vz position))
          (half (/ width 2)))
      (if (member direction '(:north :south))
          (add-portal (- x half) y z (+ x half) (+ y height) z)
          (add-portal x y (- z half) x (+ y height) (+ z half))))))

(defun drop-portal (connector)
  "Take CONNECTOR's portal out of *PORTALS*: its doorway is shut, or another doorway's
portal already fills it."
  (let ((at (position (connector-portal connector) *portals*)))
    (when at
      (setf (aref *portals* at) (aref *portals* (1- (fill-pointer *portals*))))
      (decf (fill-pointer *portals*)))))

(defun seal-connector (container connector &key (surface :wall))
  "Shut CONNECTOR's doorway with the block's plug, and take away its portal so no light
goes through. A block without a plug gets a wall outside it instead, which sticks into
the next grid cell."
  (drop-portal connector)
  (if (connector-plug connector)
      (funcall (connector-plug connector) container)
      (multiple-value-bind (width height) (connector-size (connector-kind connector))
        (v:warn :hexmaw "~a has no plug; walling it off outside the block." connector)
        (let* ((position (connector-location connector))
               (x (vx position)) (y (vy position)) (z (vz position))
               (half (/ width 2)) (top (+ y height)) (thick 0.5))
          (ecase (connector-direction connector)
            (:north (add-box container (- x half) y (- z thick) (+ x half) top z :surface surface))
            (:south (add-box container (- x half) y z (+ x half) top (+ z thick) :surface surface))
            (:west (add-box container (- x thick) y (- z half) x top (+ z half) :surface surface))
            (:east (add-box container x y (- z half) (+ x thick) top (+ z half) :surface surface)))))))

(defun attach-block (name container connector &key at facing)
  "Place block NAME so that its connector named CONNECTOR sits at AT, facing FACING:
the direction the doorway opens toward, back at whatever it attaches to.
Returns the placed block's connectors, as PLACE-BLOCK does."
  (multiple-value-bind (origin turns) (attach-placement name connector at facing)
    (place-block name container :at origin :turns turns)))
