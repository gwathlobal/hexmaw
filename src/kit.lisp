(in-package #:hexmaw)

;;; The kit: every level block in data/blocks/, and a gallery level (*LEVEL* :GALLERY)
;;; that lays them all out to walk through and look at. Corridor and stair pieces stand
;;; in one row, rooms in a row behind it, each turned so that one of its doorways on
;;; storey 0 faces south, toward the spawn. That doorway is open and every other one is
;;; plugged, so the plugs can be looked at too.

(defparameter *gallery-gap* 4.0 "Metres between blocks in the gallery.")
(defparameter *gallery-rows* '(-4.0 -20.0)
  "Where the south faces of the gallery's two rows (corridors, then rooms) stand, in Z.")

(defun kit-blocks ()
  "The name of every block in data/blocks/, sorted."
  (sort (mapcar #'pathname-name (directory (data-path "blocks/*.glb")))
        #'string<))

(defun block-tags (name) (getf (find-block name) :tags))
(defun block-weight (name) (getf (find-block name) :weight))

(defvar *gallery* (make-hash-table :test 'equalp)
  "Each gallery block's open doorway, by block name: where it is, on its floor.")

(defun build-kit-gallery (container)
  (clrhash *gallery*)
  ;; Blueprints that have no block yet are built first.
  (dolist (name (hexmaw.blueprint:blueprint-names))
    (hexmaw.blueprint:ensure-block name))
  (let* ((names (kit-blocks))
         (rooms (remove-if-not (lambda (n) (member :room (block-tags n))) names))
         (pieces (set-difference names rooms :test #'string=))
         (west -4.0) (east west) (footprints ()))
    (loop for row in (list (sort pieces #'string<) (sort rooms #'string<))
          for south in *gallery-rows*
          do (let ((x west))
               (dolist (name row)
                 (let* ((door (or (find 0 (getf (find-block name) :connectors) :key (lambda (c) (getf c :storey)))
                                  (first (getf (find-block name) :connectors))))
                        (turns (turns-between (getf door :direction) :south)))
                   (multiple-value-bind (low high) (block-world-bounds name (vec 0 0 0) turns)
                     (let ((at (vec (- x (vx low)) 0 (- south (vz high)))))
                       (push (list (+ (vx at) (vx low)) (+ (vz at) (vz low)) (+ (vx at) (vx high)) (+ (vz at) (vz high)))
                             footprints)
                       (dolist (c (place-block name container :at at :turns turns))
                         (if (string-equal (connector-name c) (getf door :name))
                             (setf (gethash name *gallery*) (connector-location c))
                             (seal-connector container c)))
                       (setf x (+ x (- (vx high) (vx low)) *gallery-gap*))))))
               (setf east (max east x))))
    ;; Ground between the blocks, just below their floors so it doesn't fight with them
    ;; where they meet. Not under them: it would fill a lava pit (liquids.lisp).
    (add-ground container (- west *gallery-gap*) (- (car (last *gallery-rows*)) 30) east 12 footprints)))

(defun add-ground (container x0 z0 x1 z1 holes)
  "Floor the rectangle X0 Z0 to X1 Z1 at just below 0, except under HOLES, each a
rectangle (X0 Z0 X1 Z1), in as few boxes as it takes."
  (let* ((xs (sort (remove-duplicates (list* x0 x1 (loop for (a nil b) in holes collect a collect b))) #'<))
         (zs (sort (remove-duplicates (list* z0 z1 (loop for (nil a nil b) in holes collect a collect b))) #'<))
         (grid (make-array (list (1- (length zs)) (1- (length xs))) :initial-element NIL)))
    (loop for (za zb) on zs while zb for r from 0
          do (loop for (xa xb) on xs while xb for c from 0
                   for mx = (/ (+ xa xb) 2) for mz = (/ (+ za zb) 2)
                   do (setf (aref grid r c)
                            (and (< x0 mx x1) (< z0 mz z1)
                                 (notany (lambda (h) (destructuring-bind (hx0 hz0 hx1 hz1) h
                                                       (and (< hx0 mx hx1) (< hz0 mz hz1))))
                                         holes)))))
    (loop for (r0 c0 r1 c1) in (hexmaw.blueprint::merge-rectangles grid)
          do (add-box container (nth c0 xs) -0.55 (nth r0 zs) (nth (1+ c1) xs) -0.05 (nth (1+ r1) zs)
                      :surface :floor))))

(defun kit-goto (name)
  "Stand the player outside gallery block NAME's open doorway, facing in. Run it in GAME."
  (let ((door (or (gethash (string name) *gallery*)
                  (error "No ~a in the gallery; it has ~{~a~^, ~}." name
                         (loop for k being the hash-keys of *gallery* collect k)))))
    (setf (vx (feet *player*)) (vx door) (vy (feet *player*)) 0.0 (vz (feet *player*)) (+ (vz door) 2.5)
          (vx (rotation *player*)) 0.05 (vy (rotation *player*)) 0.0)
    door))

;;; Reachability: every doorway of every placed block must be walkable to from the
;;; spawn point, and so back (steps go both ways; drops don't count). BUILD-LEVEL checks
;;; after the nav grid is built and warns about each one that isn't. A stream is lava wall
;;; to wall, so the way may lead through lava: the level's checks wade.

(defun doorway-inside (connector)
  "A point 1 m inside CONNECTOR's block from its doorway, just above its floor: in front
of the plug, if it is plugged."
  (first (doorway-probes connector)))

(defun flooded-kind-p (kind)
  "True if a doorway of KIND is lava wall to wall, no banks: a stream's."
  (let ((spec (assoc kind hexmaw.blueprint:*connector-kinds* :test #'string-equal)))
    (and (fourth spec) (<= (second spec) (fourth spec)))))

(defun doorway-probes (connector)
  "Where to stand 1 m inside CONNECTOR's doorway, just above its floor: its middle, or for
a river's (lava down the middle) the middle of each bank. A stream's has no banks: its
middle, in the lava."
  (let ((p (connector-location connector))
        (spec (assoc (connector-kind connector) hexmaw.blueprint:*connector-kinds* :test #'string-equal)))
    (multiple-value-bind (dx dz)
        (ecase (connector-direction connector)
          (:north (values 0 -1)) (:south (values 0 1)) (:west (values -1 0)) (:east (values 1 0)))
      (let ((x (- (vx p) dx)) (y (+ (vy p) 0.1)) (z (- (vz p) dz)))
        (if (and (fourth spec) (not (flooded-kind-p (first spec))))
            ;; Along the doorway, halfway across each bank.
            (let ((off (/ (+ (second spec) (fourth spec)) 4)))
              (list (vec (+ x (* off (abs dz))) y (+ z (* off (abs dx))))
                    (vec (- x (* off (abs dz))) y (- z (* off (abs dx))))))
            (list (vec x y z)))))))

(defun unreachable-doorways (&key (from *spawn-point*) (doorways *level-doorways*))
  "The DOORWAYS a player can't walk to from FROM, on the nav grid, wading through lava if
need be: it burns, but it is a way."
  (let ((r *player-radius*) (h *player-height*) (step *step-height*) (*nav-hazards* :wade))
    (multiple-value-bind (si sj sk) (and *nav-grid* (nav-nearest-fitting from r h))
      (if (null si)
          doorways
          (let ((seen (nav-reached si sj sk r h step)))
            (remove-if (lambda (c)
                         ;; A body can't stand right against a plug, and inside a stair's
                         ;; doorway the floor climbs, so look a little around and above. A
                         ;; river's doorway counts only if both its banks do.
                         (every (lambda (probe)
                                  (multiple-value-bind (i j k) (nav-nearest-fitting probe r h :search 2 :reach 1.5)
                                    (and i (= 1 (sbit seen (nav-index i j k))))))
                                (doorway-probes c)))
                       doorways))))))

(defun stranded-creatures (&key (from *spawn-point*))
  "The creatures that can't walk to FROM from where they live, each on the nav grid at
its own size and step. A creature whose own cell is too tight for it can't plan a walk
at all, so that counts too. Walks go both ways, so one search from FROM per size does. A
chase wades when there is no dry way (CHASE-PATH), so these walks may too."
  (let ((searches (make-hash-table :test 'equal)) (stranded ()) (*nav-hazards* :wade))
    (when *nav-grid*
      (loop for creature across *creatures*
            for r = (float (body-radius creature) 0f0)
            for h = (float (sprite-height creature) 0f0)
            for step = (float (step-height creature) 0f0)
            for seen = (let ((key (list r h step)))
                         (multiple-value-bind (si sj sk) (nav-nearest-fitting from r h)
                           (and si (or (gethash key searches)
                                       (setf (gethash key searches) (nav-reached si sj sk r h step))))))
            ;; Spawn points often sit on the line between cells, so any of the cells
            ;; touching it will do.
            do (unless (and seen
                            (loop for (dx dz) in '((-0.1 -0.1) (-0.1 0.1) (0.1 -0.1) (0.1 0.1))
                                  thereis (let ((p (v+ (home creature) (vec dx 0 dz))))
                                            (multiple-value-bind (i j k) (nav-nearest-fitting p r h :search 0 :reach 1.0)
                                              (and i (= 1 (sbit seen (nav-index i j k))))))))
                 (push creature stranded))))
    (nreverse stranded)))

(defun check-reachable ()
  "Warn about every doorway of the level the player can't walk to, and every creature
that can't walk to the player. Returns both."
  (let ((lost (unreachable-doorways))
        (stranded (stranded-creatures)))
    (dolist (c lost)
      (v:warn :hexmaw "Can't walk to ~a at ~a from the spawn point." c (connector-location c)))
    (dolist (c stranded)
      (v:warn :hexmaw "~a at ~a can't walk to the spawn point." (type-of c) (home c)))
    (values lost stranded)))

;;; Checking one block: *LEVEL* :BLOCK is *CHECK-BLOCK* alone, every doorway open. Each
;;; doorway has its probes (a river's, one per bank), and what joins what on the nav grid
;;; at the player's size decides it is sound:
;;;
;;; - its ordinary doorways reach each other;
;;; - every probe reaches another doorway's: no bank or corner leads nowhere;
;;; - a river end (tag RIVER-END) joins all of them: a river's two banks meet only at its
;;;   ends and crossings, so with an end at each end both banks of every piece stay walkable;
;;; - a block with a stream's doorway (lava wall to wall) is checked wading, the rest dry, so
;;;   a wide river's banks must still walk dry to its doorways;
;;; - every monster reaches the first doorway;
;;; - in a high block (tag HIGH), every doorway reaches every other at *HIGH-BODY*'s size,
;;;   walking: the ogre's leaps are shortcuts there, never its only way.

(defvar *check-block* NIL "The block *LEVEL* :BLOCK builds.")

(defparameter *high-body* '(1.0 2.7 0.45)
  "The radius, height and step a high block must let walk between all its doorways: the ogre,
without its leaps.")

(defun build-check-block (container)
  (let ((doors (place-block *check-block* container :at (vec 0 0 0) :turns 0)))
    (when doors
      (v<- *spawn-point* (doorway-inside (first doors))))))

(defun block-problems (name)
  "What is wrong with block NAME, built alone as *LEVEL* :BLOCK, as a list of strings."
  (let* ((r *player-radius*) (h *player-height*) (step *step-height*)
         (*nav-hazards* (if (some (lambda (c) (flooded-kind-p (connector-kind c))) *level-doorways*)
                            :wade
                            :avoid))
         (probes (loop for c in *level-doorways*
                       append (loop for p in (doorway-probes c)
                                    collect (list c p (multiple-value-list
                                                       (nav-nearest-fitting p r h :search 2 :reach 1.5))))))
         (problems ()))
    (flet ((ordinary-p (c) (not (fourth (assoc (connector-kind c) hexmaw.blueprint:*connector-kinds*
                                               :test #'string-equal))))
           (label (probe) (format NIL "~a~:[~; (a bank)~]" (connector-name (first probe))
                                  (rest (doorway-probes (first probe))))))
      (let ((reach (loop for probe in probes
                         collect (destructuring-bind (i j k) (third probe)
                                   (and i (nav-reached i j k r h step))))))
        (flet ((joined (a b)
                 (let ((seen (nth (position a probes) reach)))
                   (destructuring-bind (i j k) (third b)
                     (and seen i (= 1 (sbit seen (nav-index i j k))))))))
          (loop for a in probes
                do (cond ((null (first (third a)))
                          (push (format NIL "~a: no floor to stand on" (label a)) problems))
                         ((and (< 1 (length *level-doorways*))
                               (notany (lambda (b) (and (not (eq (first a) (first b))) (joined a b))) probes))
                          (push (format NIL "~a leads to no other doorway" (label a)) problems))))
          (let ((ordinary (remove-if-not (lambda (p) (ordinary-p (first p))) probes))
                (all-joined (member :river-end (block-tags name))))
            (loop for a in (if all-joined probes ordinary)
                  do (loop for b in (if all-joined probes ordinary)
                           when (and (not (eq (first a) (first b))) (not (joined a b)))
                             do (push (format NIL "~a doesn't reach ~a" (label a) (label b)) problems))))))
      (dolist (c (stranded-creatures))
        (push (format NIL "~a at ~a can't reach ~a" (type-of c) (home c) (connector-name (first *level-doorways*)))
              problems))
      (when (member :high (block-tags name))
        (destructuring-bind (r h step) *high-body*
          (let ((cells (loop for c in *level-doorways*
                             collect (cons c (multiple-value-list
                                              (nav-nearest-fitting (first (doorway-probes c)) r h :search 2 :reach 1.5))))))
            (loop for (a . (i j k)) in cells
                  for seen = (and i (nav-reached i j k r h step))
                  do (if (null i)
                         (push (format NIL "~a: no floor for the ogre" (connector-name a)) problems)
                         (loop for (b . (bi bj bk)) in cells
                               unless (or (eq a b) (and bi (= 1 (sbit seen (nav-index bi bj bk)))))
                                 do (push (format NIL "the ogre can't walk from ~a to ~a" (connector-name a) (connector-name b))
                                          problems))))))))
    (remove-duplicates (nreverse problems) :test #'string=)))

(defun check-kit (&optional names)
  "Build every block in NAMES (or the kit) alone and check it (BLOCK-PROBLEMS). Returns
a list of (name problem...) for those with any; NIL is a clean kit. Rebuilds the scene
for each, then puts the level back. Call it from the eval server, not inside GAME."
  (let ((level *level*) (problems ()))
    (unwind-protect
         (dolist (name (or names (kit-blocks)))
           (setf *check-block* name *level* :block)
           (reload-scene)
           (let ((found (block-problems name)))
             (when found (push (cons name found) problems))))
      (setf *level* level)
      (reload-scene))
    (nreverse problems)))
