(in-package #:hexmaw)

;;; Nav grid: where creatures can stand and how they get from one place to another,
;;; built from *SOLIDS*. It is the grid cousin of a navmesh: the level is cut into
;;; square cells, and each cell records how much room it has rather than whether one
;;; particular body fits, so creatures of every size share one grid:
;;;
;;;  - floor: the height of the surface to stand on (one per cell, the lowest one
;;;    with room above it, so a hall's roof never counts);
;;;  - headroom: from the floor up to the lowest solid above it;
;;;  - clearance: the widest body (half-width, as for collision boxes) that fits
;;;    standing there. Solids lower than *NAV-WALL-ABOVE* above the floor don't count,
;;;    so steps and low ledges aren't walls.
;;;
;;; A body of radius R, height H fits a cell when clearance >= R and headroom >= H. It
;;; can move to a neighbouring cell (diagonals too, without cutting corners) when the
;;; floors differ by no more than its step height. Every query takes those three.
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

(defvar *nav-grid* NIL "The current level's nav grid. BUILD-LEVEL rebuilds it.")

(defclass nav-grid ()
  ((x0 :initarg :x0 :reader nav-x0 :documentation "World X of the grid's west edge.")
   (z0 :initarg :z0 :reader nav-z0 :documentation "World Z of the grid's north edge.")
   (cell :initarg :cell :reader nav-cell-size)
   (width :initarg :width :reader nav-width :documentation "Cells along X.")
   (depth :initarg :depth :reader nav-depth :documentation "Cells along Z.")
   (floors :initarg :floors :reader nav-floors
           :documentation "Floor height per cell, or MOST-NEGATIVE-SINGLE-FLOAT for none.")
   (headroom :initarg :headroom :reader nav-headroom)
   (clearance :initarg :clearance :reader nav-clearance)))

;;; Geometry questions.

(defun floor-candidates (x z)
  "Heights of the solid tops under the point X Z, lowest first."
  (sort (loop for s across *solids*
              when (and (<= (aref s 0) x (aref s 3)) (<= (aref s 2) z (aref s 5)))
                collect (aref s 4))
        #'<))

(defun ceiling-above (x y z)
  "Height of the lowest solid bottom at or above Y over the point X Z, or NIL."
  (let ((lowest NIL))
    (loop for s across *solids*
          when (and (<= (aref s 0) x (aref s 3)) (<= (aref s 2) z (aref s 5))
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
           (floors (make-array (list width depth) :element-type 'single-float
                                                  :initial-element most-negative-single-float))
           (headroom (make-array (list width depth) :element-type 'single-float :initial-element 0f0))
           (clearance (make-array (list width depth) :element-type 'single-float :initial-element 0f0)))
      (dotimes (i width)
        (dotimes (j depth)
          (let* ((x (+ x0 (* (+ i 0.5) cell)))
                 (z (+ z0 (* (+ j 0.5) cell)))
                 (y (find-if (lambda (y) (fits-at-p x y z 0.0 *nav-min-height*))
                             (floor-candidates x z))))
            (when y
              (let ((room (let ((top (ceiling-above x y z)))
                            (if top (- top y) *nav-open-headroom*))))
                (setf (aref floors i j) y
                      (aref headroom i j) (float room 0f0)
                      (aref clearance i j) (measure-clearance x y z room)))))))
      (setf *nav-grid* (make-instance 'nav-grid :x0 x0 :z0 z0 :cell cell :width width :depth depth
                                                :floors floors :headroom headroom :clearance clearance)))))

;;; Cells.

(defun nav-cell (x z &optional (grid *nav-grid*))
  "The cell I J containing the world point X Z, or NIL outside the grid."
  (let ((i (floor (- x (nav-x0 grid)) (nav-cell-size grid)))
        (j (floor (- z (nav-z0 grid)) (nav-cell-size grid))))
    (when (and (< -1 i (nav-width grid)) (< -1 j (nav-depth grid)))
      (values i j))))

(defun nav-floor (i j &optional (grid *nav-grid*))
  "Floor height of cell I J, or NIL if it has none."
  (let ((y (aref (nav-floors grid) i j)))
    (when (< most-negative-single-float y) y)))

(defun nav-fits-p (i j radius height &optional (grid *nav-grid*))
  "True if a body RADIUS out from its centre and HEIGHT tall can stand in cell I J."
  (and (< -1 i (nav-width grid)) (< -1 j (nav-depth grid))
       (nav-floor i j grid)
       (<= radius (aref (nav-clearance grid) i j))
       (<= height (aref (nav-headroom grid) i j))))

(defun nav-point (i j &optional (grid *nav-grid*))
  "A new vector at the centre of cell I J, on its floor."
  (let ((cell (nav-cell-size grid)))
    (vec (+ (nav-x0 grid) (* (+ i 0.5) cell))
         (nav-floor i j grid)
         (+ (nav-z0 grid) (* (+ j 0.5) cell)))))

(defun nav-floor-at (x z &optional (grid *nav-grid*))
  "Floor height under the world point X Z, or NIL."
  (multiple-value-bind (i j) (nav-cell x z grid)
    (when i (nav-floor i j grid))))

(defun nav-nearest-fitting (point radius height &key (search 2) (reach 1.0) (grid *nav-grid*))
  "The cell I J under POINT if the body fits there, else the nearest cell within SEARCH
cells that it fits, or NIL. Knockback can push a creature into a cell too tight for it.
Only floors within REACH metres of POINT's height count: a pillar's cells have the roof
above it for a floor."
  (flet ((ok (i j)
           (and (nav-fits-p i j radius height grid)
                (<= (abs (- (nav-floor i j grid) (vy point))) reach))))
    (multiple-value-bind (ci cj) (nav-cell (vx point) (vz point) grid)
      (when ci
        (if (ok ci cj)
            (values ci cj)
            (let ((best NIL) (bi 0) (bj 0))
              (loop for i from (- ci search) to (+ ci search)
                    do (loop for j from (- cj search) to (+ cj search)
                             for d = (+ (expt (- i ci) 2) (expt (- j cj) 2))
                             when (and (ok i j) (or (null best) (< d best)))
                               do (setf best d bi i bj j)))
              (when best (values bi bj))))))))

(defun nav-step-p (i j ni nj radius height step &optional (grid *nav-grid*))
  "True if a body can move from cell I J to the neighbouring cell NI NJ."
  (and (nav-fits-p ni nj radius height grid)
       (<= (abs (- (nav-floor ni nj grid) (nav-floor i j grid))) step)
       ;; A diagonal step needs both cells beside it, so it never cuts a corner.
       (or (= i ni) (= j nj)
           (and (nav-fits-p ni j radius height grid)
                (nav-fits-p i nj radius height grid)))))

;;; Searching.

(defun nav-flood (si sj max-distance radius height step &optional (grid *nav-grid*))
  "Shortest path lengths from cell SI SJ to every cell within MAX-DISTANCE metres of
walking. Returns two arrays indexed by I + J * WIDTH: distances (infinity where not
reached) and each cell's previous cell on its path (-1 for none)."
  (let* ((w (nav-width grid))
         (n (* w (nav-depth grid)))
         (cell (nav-cell-size grid))
         (dist (make-array n :element-type 'single-float :initial-element most-positive-single-float))
         (parent (make-array n :element-type 'fixnum :initial-element -1))
         (done (make-array n :element-type 'bit :initial-element 0))
         (open (make-array 64 :adjustable T :fill-pointer 0)))
    (setf (aref dist (+ si (* sj w))) 0.0)
    (vector-push-extend (+ si (* sj w)) open)
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
                 (multiple-value-bind (j i) (floor c w)
                   (loop for di from -1 to 1
                         do (loop for dj from -1 to 1
                                  for ni = (+ i di) for nj = (+ j dj)
                                  for nc = (+ ni (* nj w))
                                  for d = (+ (aref dist c) (* cell (if (or (= di 0) (= dj 0)) 1.0 1.4142135)))
                                  when (and (not (and (= di 0) (= dj 0)))
                                            (<= d max-distance)
                                            (nav-step-p i j ni nj radius height step grid)
                                            (< d (aref dist nc)))
                                    do (setf (aref dist nc) d
                                             (aref parent nc) c)
                                       (vector-push-extend nc open)))))))
    (values dist parent)))

(defun nav-line-clear-p (a b radius height step &optional (grid *nav-grid*))
  "True if a body can walk the straight line from point A to point B: it fits every
cell along it, and no floor change between them is more than STEP."
  (let* ((dx (- (vx b) (vx a))) (dz (- (vz b) (vz a)))
         (samples (max 1 (ceiling (sqrt (+ (* dx dx) (* dz dz))) (/ (nav-cell-size grid) 4))))
         (floor NIL))
    (loop for k from 0 to samples
          for f = (/ k samples)
          do (multiple-value-bind (i j) (nav-cell (+ (vx a) (* f dx)) (+ (vz a) (* f dz)) grid)
               (unless (and i (nav-fits-p i j radius height grid))
                 (return NIL))
               (let ((y (nav-floor i j grid)))
                 (when (and floor (< step (abs (- y floor))))
                   (return NIL))
                 (setf floor y)))
          finally (return T))))

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

(defun nav-reachable-spot (from radius height step &key (around from) (within 4.0) (max-walk (* 2 within))
                                                   (min-distance 1.0) (grid *nav-grid*))
  "A path to a random spot that a body standing at point FROM can walk to: within
WITHIN metres of point AROUND, at least MIN-DISTANCE and at most MAX-WALK metres of
walking away. A list of points ending at the spot, smoothed; NIL if there is none."
  (when grid
    (multiple-value-bind (si sj) (nav-nearest-fitting from radius height :grid grid)
      (when si
        (multiple-value-bind (dist parent) (nav-flood si sj max-walk radius height step grid)
          (let* ((w (nav-width grid))
                 (cell (nav-cell-size grid))
                 (spots (loop for c from 0 below (length dist)
                              when (and (<= min-distance (aref dist c) max-walk)
                                        (multiple-value-bind (j i) (floor c w)
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
                (nav-smooth-path from
                                 (loop for c in (rest cells)
                                       collect (multiple-value-bind (j i) (floor c w) (nav-point i j grid)))
                                 radius height step grid)))))))))

(defun nav-path-to (from to radius height step &key (max-walk 15.0) (grid *nav-grid*))
  "A path for a body standing at point FROM to point TO, walking at most MAX-WALK
metres: a list of points ending at TO, smoothed; NIL if TO's cell (or the nearest one
the body fits) can't be reached."
  (when grid
    (multiple-value-bind (si sj) (nav-nearest-fitting from radius height :grid grid)
      (multiple-value-bind (gi gj) (nav-nearest-fitting to radius height :grid grid)
        (when (and si gi)
          (multiple-value-bind (dist parent) (nav-flood si sj max-walk radius height step grid)
            (let* ((w (nav-width grid))
                   (goal (+ gi (* gj w))))
              (when (< (aref dist goal) most-positive-single-float)
                (let ((cells ()))
                  (loop for c = goal then (aref parent c)
                        until (= c -1)
                        do (push c cells))
                  (nav-smooth-path from
                                   (append (loop for c in (rest cells)
                                                 collect (multiple-value-bind (j i) (floor c w) (nav-point i j grid)))
                                           (list (vcopy to)))
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
RADIUS wide and HEIGHT tall fits. Run in GAME. HIDE-NAV, or a scene reset, removes them."
  (hide-nav)
  (let ((feet (feet *player*))
        (half (* 0.4 (nav-cell-size grid)))
        (scene (scene +main+)))
    (dotimes (i (nav-width grid))
      (dotimes (j (nav-depth grid))
        (when (nav-fits-p i j radius height grid)
          (let ((p (nav-point i j grid)))
            (when (< (+ (expt (- (vx p) (vx feet)) 2) (expt (- (vz p) (vz feet)) 2)) (* within within))
              (push (add-box scene (- (vx p) half) (vy p) (- (vz p) half)
                             (+ (vx p) half) (+ (vy p) 0.03) (+ (vz p) half)
                             :color (vec 0.2 0.8 0.3) :solid NIL)
                    *nav-tiles*))))))
    (length *nav-tiles*)))
