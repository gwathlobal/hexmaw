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
  (sort (mapcar #'pathname-name (directory (merge-pathnames "data/blocks/*.glb" (root))))
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
         (west -4.0) (east west))
    (loop for row in (list (sort pieces #'string<) (sort rooms #'string<))
          for south in *gallery-rows*
          do (let ((x west))
               (dolist (name row)
                 (let* ((door (or (find 0 (getf (find-block name) :connectors) :key (lambda (c) (getf c :storey)))
                                  (first (getf (find-block name) :connectors))))
                        (turns (turns-between (getf door :direction) :south)))
                   (multiple-value-bind (low high) (block-world-bounds name (vec 0 0 0) turns)
                     (let ((at (vec (- x (vx low)) 0 (- south (vz high)))))
                       (dolist (c (place-block name container :at at :turns turns))
                         (if (string-equal (connector-name c) (getf door :name))
                             (setf (gethash name *gallery*) (connector-location c))
                             (seal-connector container c)))
                       (setf x (+ x (- (vx high) (vx low)) *gallery-gap*))))))
               (setf east (max east x))))
    ;; Ground between and under the blocks, just below their floors so it doesn't
    ;; fight with them.
    (add-box container (- west *gallery-gap*) -0.55 (- (car (last *gallery-rows*)) 30)
             east -0.05 12 :color *floor-color*)))

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
;;; after the nav grid is built and warns about each one that isn't.

(defun doorway-inside (connector)
  "A point 1 m inside CONNECTOR's block from its doorway, just above its floor: in front
of the plug, if it is plugged."
  (let ((p (connector-location connector)))
    (multiple-value-bind (dx dz)
        (ecase (connector-direction connector)
          (:north (values 0 -1)) (:south (values 0 1)) (:west (values -1 0)) (:east (values 1 0)))
      (vec (- (vx p) dx) (+ (vy p) 0.1) (- (vz p) dz)))))

(defun unreachable-doorways (&key (from *spawn-point*) (doorways *level-doorways*))
  "The DOORWAYS a player can't walk to from FROM, on the nav grid."
  (let ((r *player-radius*) (h *player-height*) (step *step-height*))
    (multiple-value-bind (si sj sk) (and *nav-grid* (nav-nearest-fitting from r h))
      (if (null si)
          doorways
          (let ((seen (nav-reached si sj sk r h step)))
            (remove-if (lambda (c)
                         ;; A body can't stand right against a plug, and inside a stair's
                         ;; doorway the floor climbs, so look a little around and above.
                         (multiple-value-bind (i j k) (nav-nearest-fitting (doorway-inside c) r h :search 2 :reach 1.5)
                           (and i (= 1 (sbit seen (nav-index i j k))))))
                       doorways))))))

(defun stranded-creatures (&key (from *spawn-point*))
  "The creatures that can't walk to FROM from where they live, each on the nav grid at
its own size and step. A creature whose own cell is too tight for it can't plan a walk
at all, so that counts too. Walks go both ways, so one search from FROM per size does."
  (let ((searches (make-hash-table :test 'equal)) (stranded ()))
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
