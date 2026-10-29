(in-package #:hexmaw)

;;; Nav grid: where creatures can stand and how they get from one place to another,
;;; built from *SOLIDS*. It is the grid cousin of a navmesh: the level is cut into
;;; square columns, and each column holds one cell per floor in it (its layers: a room
;;; and the room above it, or a hall and its roof), lowest first. Each cell records how
;;; much room it has rather than whether one particular body fits, so creatures of every
;;; size share one grid:
;;;
;;;  - floor: the height of the surface to stand on (any solid top with room above it);
;;;  - headroom: from the floor up to the lowest solid above it;
;;;  - clearance: the widest body (half-width, as for collision boxes) that fits
;;;    standing there. Solids lower than *NAV-WALL-ABOVE* above the floor don't count,
;;;    so steps and low ledges aren't walls.
;;;
;;; A cell is I J K: column I J, layer K. A body of radius R, height H fits a cell when
;;; clearance >= R and headroom >= H. It can move to a cell in a neighbouring column
;;; (diagonals too, without cutting corners) when the floors differ by no more than its
;;; step height, so stairs join the layers. Every query takes those three. A point in
;;; the world is in the layer under it: the highest floor no more than *NAV-LAYER-ABOVE*
;;; above it (NAV-LAYER).
;;;
;;; The geometry questions go through FLOOR-CANDIDATES, CEILING-ABOVE and FITS-AT-P,
;;; so nothing else here depends on solids being axis-aligned boxes.

(defparameter *nav-cell* 0.5 "Grid cell size in metres.")
(defparameter *nav-radius-step* 0.125 "Clearance is measured in steps of this many metres.")
(defparameter *nav-max-radius* 2.0 "Clearance is measured up to this radius.")
(defparameter *nav-min-height* 0.5 "The shortest body that walks: a floor needs this much room above it.")
(defparameter *nav-wall-above* 0.45
  "Clearance ignores solids that rise less than this above the floor: steps aren't walls.")
(defparameter *nav-clearance-height* 2.0
  "Clearance is measured up to this height above the floor, or up to the headroom if lower.")
(defparameter *nav-open-headroom* 100.0 "Headroom of a cell with nothing above it.")
(defparameter *nav-layer-above* 0.5
  "A point is on a floor up to this far above it: a body stepping up is already on the
step, and its feet may sit a little below the floor it settles onto.")

(defvar *nav-grid* NIL "The current level's nav grid. BUILD-LEVEL rebuilds it.")

(defclass nav-grid ()
  ((x0 :initarg :x0 :reader nav-x0 :documentation "World X of the grid's west edge.")
   (z0 :initarg :z0 :reader nav-z0 :documentation "World Z of the grid's north edge.")
   (cell :initarg :cell :reader nav-cell-size)
   (width :initarg :width :reader nav-width :documentation "Cells along X.")
   (depth :initarg :depth :reader nav-depth :documentation "Cells along Z.")
   (layers :initarg :layers :reader nav-layers :documentation "The most floors any column has.")
   (floors :initarg :floors :reader nav-floors
           :documentation "Floor height per cell I J K, or MOST-NEGATIVE-SINGLE-FLOAT for none.
A column's floors come first, lowest first.")
   (headroom :initarg :headroom :reader nav-headroom)
   (clearance :initarg :clearance :reader nav-clearance)
   (hazard :initarg :hazard :reader nav-hazard
           :documentation "A bit per cell I J K, set where its floor is under lava (liquids.lisp).")))

(defvar *nav-hazards* :avoid
  "How the nav questions treat cells under lava. :AVOID, the default, keeps out of them.
:WADE lets paths through them, each step there costing *NAV-WADE-COST* times as much,
but no straight walk crosses them, so a path through lava keeps to the short way across
it. :IGNORE treats them as any floor, for flyers. Creatures bind it while they think.")
(defparameter *nav-wade-cost* 3.0
  "How many times as costly a step through lava is to a path that may wade.")

;;; Geometry questions.

(defun floor-candidates (x z)
  "Heights of the solid tops under the point X Z, lowest first."
  (sort (loop for s across *solids*
              when (solid-covers-p s x z)
                collect (aref s 4))
        #'<))

(defun ceiling-above (x y z)
  "Height of the lowest solid bottom at or above Y over the point X Z, or NIL."
  (let ((lowest NIL))
    (loop for s across *solids*
          when (and (solid-covers-p s x z)
                    (<= (- y 1f-4) (aref s 1))
                    (or (null lowest) (< (aref s 1) lowest)))
            do (setf lowest (aref s 1)))
    lowest))

(defun fits-at-p (x y z radius height)
  "True if an upright body RADIUS out from X Z and HEIGHT tall fits standing at Y."
  (not (solid-overlapping x y z (float radius 0f0) (float height 0f0))))

;;; Building.

(defun solids-bounds ()
  "The XZ extent of *SOLIDS*: min-x min-z max-x max-z."
  (loop for s across *solids*
        minimize (aref s 0) into x0 minimize (aref s 2) into z0
        maximize (aref s 3) into x1 maximize (aref s 5) into z1
        finally (return (values x0 z0 x1 z1))))

(defun measure-clearance (x y z headroom)
  (let ((height (- (min headroom *nav-clearance-height*) *nav-wall-above*))
        (above (+ y *nav-wall-above*)))
    (loop for r from *nav-radius-step* to (+ *nav-max-radius* 1f-4) by *nav-radius-step*
          while (fits-at-p x above z r height)
          maximize r into widest
          finally (return (float (or widest 0.0) 0f0)))))

(defun column-floors (x z)
  "The floors over the point X Z, lowest first: every solid top with room for the
shortest body above it, once (boxes side by side share a top)."
  (let ((floors ()))
    (dolist (y (floor-candidates x z) (nreverse floors))
      (when (and (or (null floors) (< (+ (first floors) 1f-3) y))
                 (fits-at-p x y z 0.0 *nav-min-height*))
        (push y floors)))))

(defparameter *nav-tile* 8 "BUILD-NAV-GRID measures cells in tiles this many cells across.")

(defun solids-near (x0 z0 x1 z1)
  "The solids that reach into the XZ rectangle X0 Z0 X1 Z1."
  (let ((near (make-array 16 :adjustable T :fill-pointer 0)))
    (loop for s across *solids*
          do (when (and (< (aref s 0) x1) (< x0 (aref s 3)) (< (aref s 2) z1) (< z0 (aref s 5)))
               (vector-push-extend s near)))
    near))

(defmacro do-nav-tiles ((i j width depth cell x0 z0) &body body)
  "Run BODY for every cell I J of a grid WIDTH by DEPTH, a tile at a time, with *SOLIDS*
bound to the solids near the tile, so each question looks at a few boxes, not all."
  (let ((ti (gensym "TI")) (tj (gensym "TJ")) (margin (gensym "MARGIN")))
    `(let ((,margin (+ *nav-max-radius* (* 2 ,cell))))
       (loop for ,ti from 0 below ,width by *nav-tile*
             do (loop for ,tj from 0 below ,depth by *nav-tile*
                      do (let ((*solids* (solids-near (- (+ ,x0 (* ,ti ,cell)) ,margin)
                                                      (- (+ ,z0 (* ,tj ,cell)) ,margin)
                                                      (+ ,x0 (* (+ ,ti *nav-tile*) ,cell) ,margin)
                                                      (+ ,z0 (* (+ ,tj *nav-tile*) ,cell) ,margin))))
                           (loop for ,i from ,ti below (min ,width (+ ,ti *nav-tile*))
                                 do (loop for ,j from ,tj below (min ,depth (+ ,tj *nav-tile*))
                                          do (progn ,@body)))))))))

(defun build-nav-grid ()
  "Measure every cell of the level in *SOLIDS* and make the result *NAV-GRID*."
  (when (= 0 (length *solids*))
    (return-from build-nav-grid (setf *nav-grid* NIL)))
  (multiple-value-bind (bx0 bz0 bx1 bz1) (solids-bounds)
    ;; Line cells up on whole multiples of the cell size, so cell centres stay off the
    ;; edges of boxes laid out on the same grid.
    (let* ((cell (float *nav-cell* 0f0))
           (x0 (* cell (floor bx0 cell)))
           (z0 (* cell (floor bz0 cell)))
           (width (ceiling (- bx1 x0) cell))
           (depth (ceiling (- bz1 z0) cell))
           (columns (make-array (list width depth)))
           (layers 0))
      (flet ((centre-x (i) (+ x0 (* (+ i 0.5) cell)))
             (centre-z (j) (+ z0 (* (+ j 0.5) cell))))
        ;; Find every column's floors first: the deepest column sizes the layers.
        (do-nav-tiles (i j width depth cell x0 z0)
          (let ((floors (column-floors (centre-x i) (centre-z j))))
            (setf (aref columns i j) floors
                  layers (max layers (length floors)))))
        (let ((floors (make-array (list width depth layers) :element-type 'single-float
                                                            :initial-element most-negative-single-float))
              (headroom (make-array (list width depth layers) :element-type 'single-float :initial-element 0f0))
              (clearance (make-array (list width depth layers) :element-type 'single-float :initial-element 0f0))
              (hazard (make-array (list width depth layers) :element-type 'bit :initial-element 0)))
          (do-nav-tiles (i j width depth cell x0 z0)
            (let ((x (centre-x i)) (z (centre-z j)))
              (loop for y in (aref columns i j)
                    for k from 0
                    do (let ((room (let ((top (ceiling-above x y z)))
                                     (if top (- top y) *nav-open-headroom*))))
                         (setf (aref floors i j k) y
                               (aref headroom i j k) (float room 0f0)
                               (aref clearance i j k) (measure-clearance x y z room)
                               (aref hazard i j k) (if (< 0 (hazard-at x (+ y 0.05) z)) 1 0))))))
          (setf *nav-grid* (make-instance 'nav-grid :x0 x0 :z0 z0 :cell cell :width width :depth depth
                                                    :layers layers :floors floors
                                                    :headroom headroom :clearance clearance
                                                    :hazard hazard)))))))

;;; Cells.

(defun nav-cell (x z &optional (grid *nav-grid*))
  "The column I J containing the world point X Z, or NIL outside the grid."
  (let ((i (floor (- x (nav-x0 grid)) (nav-cell-size grid)))
        (j (floor (- z (nav-z0 grid)) (nav-cell-size grid))))
    (when (and (< -1 i (nav-width grid)) (< -1 j (nav-depth grid)))
      (values i j))))

(defun nav-floor (i j k &optional (grid *nav-grid*))
  "Floor height of cell I J K, or NIL if column I J has no layer K."
  (let ((y (aref (nav-floors grid) i j k)))
    (when (< most-negative-single-float y) y)))

(defun nav-layer (i j y &optional (grid *nav-grid*))
  "The layer of column I J that a point at height Y is in: the highest floor at most
*NAV-LAYER-ABOVE* above it. NIL if there is none."
  (let ((limit (+ y *nav-layer-above*)) (found NIL))
    (dotimes (k (nav-layers grid) found)
      (let ((floor (nav-floor i j k grid)))
        (if (and floor (<= floor limit))
            (setf found k)
            (return found))))))

(defun nav-fits-p (i j k radius height &optional (grid *nav-grid*))
  "True if a body RADIUS out from its centre and HEIGHT tall can stand in cell I J K."
  (and (< -1 i (nav-width grid)) (< -1 j (nav-depth grid)) (< -1 k (nav-layers grid))
       (nav-floor i j k grid)
       (<= radius (aref (nav-clearance grid) i j k))
       (<= height (aref (nav-headroom grid) i j k))))

(defun nav-layer-near (i j floor radius height step &optional (grid *nav-grid*))
  "The layer of column I J that a body standing at height FLOOR can step onto: one it
fits, whose floor is at most STEP away, the nearest if several. NIL if there is none.
Path searches ask this for every neighbour, so it reads the arrays directly."
  (when (and (< -1 i (nav-width grid)) (< -1 j (nav-depth grid)))
    (let ((floors (nav-floors grid)) (clearance (nav-clearance grid)) (headroom (nav-headroom grid))
          (hazard (nav-hazard grid)) (dry (eq *nav-hazards* :avoid))
          (best NIL) (best-d 0.0))
      (declare (type (simple-array single-float (* * *)) floors clearance headroom)
               (type (simple-array bit (* * *)) hazard))
      (dotimes (k (nav-layers grid) best)
        (let ((y (aref floors i j k)))
          ;; A column's floors come first, so the first missing one ends them.
          (when (= y most-negative-single-float)
            (return best))
          (let ((d (abs (- y floor))))
            (when (and (<= d step) (or (null best) (< d best-d))
                       (<= radius (aref clearance i j k)) (<= height (aref headroom i j k))
                       (not (and dry (= 1 (aref hazard i j k)))))
              (setf best k best-d d))))))))

(defun nav-point (i j k &optional (grid *nav-grid*))
  "A new vector at the centre of cell I J K, on its floor."
  (let ((cell (nav-cell-size grid)))
    (vec (+ (nav-x0 grid) (* (+ i 0.5) cell))
         (nav-floor i j k grid)
         (+ (nav-z0 grid) (* (+ j 0.5) cell)))))

(defun nav-floor-at (x y z &optional (grid *nav-grid*))
  "Floor height of the layer under the world point X Y Z, or NIL."
  (multiple-value-bind (i j) (nav-cell x z grid)
    (when i
      (let ((k (nav-layer i j y grid)))
        (when k (nav-floor i j k grid))))))

(defun nav-room-around (x y z reach step &optional (grid *nav-grid*))
  "The floor of the layer under X Y Z, and the lowest ceiling over it and every column
within REACH metres around it, on the layer a body on that floor could step to (STEP).
A flyer keeps under that ceiling so that it ducks under a lintel before it gets there.
NIL if there is no floor under the point. Lava is floor here: this is about ceilings."
  (multiple-value-bind (ci cj) (nav-cell x z grid)
    (let* ((*nav-hazards* :ignore)
           (ck (and ci (nav-layer ci cj y grid)))
           (floor (and ck (nav-floor ci cj ck grid))))
      (when floor
        (let ((n (ceiling reach (nav-cell-size grid)))
              (lowest (+ floor (aref (nav-headroom grid) ci cj ck))))
          (loop for i from (- ci n) to (+ ci n)
                do (loop for j from (- cj n) to (+ cj n)
                         for k = (nav-layer-near i j floor 0.0 0.0 step grid)
                         when k
                           do (setf lowest (min lowest (+ (nav-floor i j k grid)
                                                          (aref (nav-headroom grid) i j k))))))
          (values floor lowest))))))

(defun nav-nearest-fitting(point radius height &key (search 2) (reach 1.0) (grid *nav-grid*))
  "The cell I J K under POINT if the body fits there, else the nearest cell within SEARCH
columns that it fits, or NIL. Knockback can push a creature into a cell too tight for it.
Only floors within REACH metres of POINT's height count, the nearest in each column."
  (multiple-value-bind (ci cj) (nav-cell (vx point) (vz point) grid)
    (when ci
      (let ((ck (nav-layer-near ci cj (vy point) radius height reach grid)))
        (if ck
            (values ci cj ck)
            (let ((best NIL) (bi 0) (bj 0) (bk 0))
              (loop for i from (- ci search) to (+ ci search)
                    do (loop for j from (- cj search) to (+ cj search)
                             for d = (+ (expt (- i ci) 2) (expt (- j cj) 2))
                             for k = (nav-layer-near i j (vy point) radius height reach grid)
                             when (and k (or (null best) (< d best)))
                               do (setf best d bi i bj j bk k)))
              (when best (values bi bj bk))))))))

(defun nav-step (i j k ni nj radius height step &optional (grid *nav-grid*))
  "The layer of the neighbouring column NI NJ that a body in cell I J K can move to, or NIL."
  (let* ((floor (nav-floor i j k grid))
         (nk (nav-layer-near ni nj floor radius height step grid)))
    (when (and nk
               ;; A diagonal step needs both columns beside it, so it never cuts a corner.
               (or (= i ni) (= j nj)
                   (and (nav-layer-near ni j floor radius height step grid)
                        (nav-layer-near i nj floor radius height step grid))))
      nk)))

;;; Searching.

(defun nav-index (i j k &optional (grid *nav-grid*))
  "Cell I J K's index in NAV-FLOOD's arrays."
  (+ i (* (nav-width grid) (+ j (* (nav-depth grid) k)))))

(defun nav-unindex (c &optional (grid *nav-grid*))
  "The cell I J K at index C in NAV-FLOOD's arrays."
  (multiple-value-bind (jk i) (floor c (nav-width grid))
    (multiple-value-bind (k j) (floor jk (nav-depth grid))
      (values i j k))))

(defun nav-flood (si sj sk max-distance radius height step &optional (grid *nav-grid*))
  "Shortest path lengths from cell SI SJ SK to every cell within MAX-DISTANCE metres of
walking. Returns two arrays indexed by NAV-INDEX: distances (infinity where not
reached) and each cell's previous cell on its path (-1 for none). While *NAV-HAZARDS* is
:WADE, a step into lava counts *NAV-WADE-COST* times its length."
  (let* ((n (* (nav-width grid) (nav-depth grid) (nav-layers grid)))
         (cell (nav-cell-size grid))
         (dist (make-array n :element-type 'single-float :initial-element most-positive-single-float))
         (parent (make-array n :element-type 'fixnum :initial-element -1))
         (done (make-array n :element-type 'bit :initial-element 0))
         (open (make-array 64 :adjustable T :fill-pointer 0))
         (start (nav-index si sj sk grid))
         (hazard (nav-hazard grid))
         (wade-cost (if (eq *nav-hazards* :wade) (float *nav-wade-cost* 0f0) 1f0)))
    (setf (aref dist start) 0.0)
    (vector-push-extend start open)
    ;; Dijkstra with a plain list of open cells: a wander radius reaches a few hundred.
    (loop while (< 0 (fill-pointer open))
          do (let* ((best (loop with best = 0
                                for k from 1 below (fill-pointer open)
                                when (< (aref dist (aref open k)) (aref dist (aref open best)))
                                  do (setf best k)
                                finally (return best)))
                    (c (aref open best)))
               (setf (aref open best) (aref open (1- (fill-pointer open))))
               (decf (fill-pointer open))
               (unless (= 1 (aref done c))
                 (setf (aref done c) 1)
                 (multiple-value-bind (i j k) (nav-unindex c grid)
                   (loop for di from -1 to 1
                         do (loop for dj from -1 to 1
                                  for ni = (+ i di) for nj = (+ j dj)
                                  for d0 = (* cell (if (or (= di 0) (= dj 0)) 1.0 1.4142135))
                                  for nk = (unless (or (and (= di 0) (= dj 0)) (< max-distance (+ (aref dist c) d0)))
                                             (nav-step i j k ni nj radius height step grid))
                                  when nk
                                    do (let* ((nc (nav-index ni nj nk grid))
                                              (d (+ (aref dist c) (if (= 1 (aref hazard ni nj nk)) (* d0 wade-cost) d0))))
                                         (when (and (<= d max-distance) (< d (aref dist nc)))
                                           (setf (aref dist nc) d
                                                 (aref parent nc) c)
                                           (vector-push-extend nc open)))))))))
    (values dist parent)))

(defun nav-reached (si sj sk radius height step &optional (grid *nav-grid*))
  "Every cell a body can walk to from cell SI SJ SK, however far: a bit per NAV-INDEX.
Steps go up and down alike, so it can walk back from all of them too."
  (let* ((seen (make-array (* (nav-width grid) (nav-depth grid) (nav-layers grid))
                           :element-type 'bit :initial-element 0))
         (queue (make-array 256 :adjustable T :fill-pointer 0))
         (start (nav-index si sj sk grid)))
    (setf (sbit seen start) 1)
    (vector-push-extend start queue)
    (loop for head from 0
          while (< head (fill-pointer queue))
          do (multiple-value-bind (i j k) (nav-unindex (aref queue head) grid)
               (loop for di from -1 to 1
                     do (loop for dj from -1 to 1
                              for nk = (unless (and (= di 0) (= dj 0))
                                         (nav-step i j k (+ i di) (+ j dj) radius height step grid))
                              when nk
                                do (let ((nc (nav-index (+ i di) (+ j dj) nk grid)))
                                     (when (= 0 (sbit seen nc))
                                       (setf (sbit seen nc) 1)
                                       (vector-push-extend nc queue)))))))
    seen))

(defun nav-line-clear-p (a b radius height step &optional (grid *nav-grid*))
  "True if a body standing at point A can walk the straight line to point B: it fits
every cell along it, no floor change between them is more than STEP, and it arrives on
the floor B is on, not one above or below it. Unless *NAV-HAZARDS* is :IGNORE, the
line keeps out of lava, even for a path that may wade."
  (let* ((*nav-hazards* (if (eq *nav-hazards* :ignore) :ignore :avoid))
         (dx (- (vx b) (vx a))) (dz (- (vz b) (vz a)))
         (samples (max 1 (ceiling (sqrt (+ (* dx dx) (* dz dz))) (/ (nav-cell-size grid) 4))))
         (floor (nav-floor-at (vx a) (vy a) (vz a) grid)))
    (when floor
      (loop for s from 0 to samples
            for f = (/ s samples)
            do (multiple-value-bind (i j) (nav-cell (+ (vx a) (* f dx)) (+ (vz a) (* f dz)) grid)
                 (let ((k (and i (nav-layer-near i j floor radius height step grid))))
                   (unless k
                     (return NIL))
                   (setf floor (nav-floor i j k grid))))
            finally (return (eql floor (nav-floor-at (vx b) (vy b) (vz b) grid)))))))

(defun nav-smooth-path (start points radius height step &optional (grid *nav-grid*))
  "Drop waypoints from POINTS that a straight walk from the previous one can skip,
starting at START, so the path doesn't zig-zag along the grid."
  (let ((path ()) (from start) (points (coerce points 'vector)) (k 0))
    (loop while (< k (length points))
          do (let ((furthest (loop for m from (1- (length points)) downto k
                                   when (nav-line-clear-p from (aref points m) radius height step grid)
                                     return m
                                   finally (return k))))
               (push (aref points furthest) path)
               (setf from (aref points furthest)
                     k (1+ furthest))))
    (nreverse path)))

(defun nav-path-points (cells grid)
  "The points of a path through CELLS, a list of NAV-INDEX indices."
  (loop for c in cells
        collect (multiple-value-bind (i j k) (nav-unindex c grid) (nav-point i j k grid))))

(defun nav-reachable-spot (from radius height step &key (around from) (within 4.0) (max-walk (* 2 within))
                                                   (min-distance 1.0) (grid *nav-grid*))
  "A path to a random spot that a body standing at point FROM can walk to: within
WITHIN metres of point AROUND, at least MIN-DISTANCE and at most MAX-WALK metres of
walking away. A list of points ending at the spot, smoothed; NIL if there is none."
  (when grid
    (multiple-value-bind (si sj sk) (nav-nearest-fitting from radius height :grid grid)
      (when si
        (multiple-value-bind (dist parent) (nav-flood si sj sk max-walk radius height step grid)
          (let* ((cell (nav-cell-size grid))
                 (spots (loop for c from 0 below (length dist)
                              when (and (<= min-distance (aref dist c) max-walk)
                                        (multiple-value-bind (i j) (nav-unindex c grid)
                                          (< (+ (expt (- (+ (nav-x0 grid) (* (+ i 0.5) cell)) (vx around)) 2)
                                                (expt (- (+ (nav-z0 grid) (* (+ j 0.5) cell)) (vz around)) 2))
                                             (* within within))))
                                collect c)))
            (when spots
              (let ((cells ()))
                (loop for c = (nth (random (length spots)) spots) then (aref parent c)
                      until (= c -1)
                      do (push c cells))
                ;; The first cell is the one the body stands in; walk from where it is.
                (nav-smooth-path from (nav-path-points (rest cells) grid) radius height step grid)))))))))

(defun nav-path-to (from to radius height step &key (max-walk 15.0) (grid *nav-grid*))
  "A path for a body standing at point FROM to point TO, walking at most MAX-WALK
metres: a list of points ending at TO, smoothed; NIL if TO's cell (or the nearest one
the body fits) can't be reached."
  (when grid
    (multiple-value-bind (si sj sk) (nav-nearest-fitting from radius height :grid grid)
      (multiple-value-bind (gi gj gk) (nav-nearest-fitting to radius height :grid grid)
        (when (and si gi)
          (multiple-value-bind (dist parent) (nav-flood si sj sk max-walk radius height step grid)
            (let ((goal (nav-index gi gj gk grid)))
              (when (< (aref dist goal) most-positive-single-float)
                (let ((cells ()))
                  (loop for c = goal then (aref parent c)
                        until (= c -1)
                        do (push c cells))
                  (nav-smooth-path from
                                   (append (nav-path-points (rest cells) grid) (list (vcopy to)))
                                   radius height step grid))))))))))

;;; Looking at it.

(defvar *nav-tiles* () "Tiles SHOW-NAV put in the scene.")

(defun hide-nav ()
  (dolist (tile *nav-tiles*)
    (when (container tile)
      (leave tile (container tile))))
  (setf *nav-tiles* ()))

(defun show-nav (&key (within 8.0) (radius 0.35) (height 1.5) (grid *nav-grid*))
  "Lay a thin green tile on every cell within WITHIN metres of the player where a body
RADIUS wide and HEIGHT tall fits, on every floor. Run in GAME. HIDE-NAV, or a scene
reset, removes them."
  (hide-nav)
  (let ((feet (feet *player*))
        (half (* 0.4 (nav-cell-size grid)))
        (scene (scene +main+)))
    (dotimes (i (nav-width grid))
      (dotimes (j (nav-depth grid))
        (dotimes (k (nav-layers grid))
          (when (nav-fits-p i j k radius height grid)
            (let ((p (nav-point i j k grid)))
              (when (< (vsqrdistance p feet) (* within within))
                (push (add-box scene (- (vx p) half) (vy p) (- (vz p) half)
                               (+ (vx p) half) (+ (vy p) 0.03) (+ (vz p) half)
                               :color (vec 0.2 0.8 0.3) :solid NIL)
                      *nav-tiles*)))))))
    (length *nav-tiles*)))
