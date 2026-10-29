(in-package #:hexmaw)

;;; Level generator (*LEVEL* :GENERATED): grows a level from the kit's blocks on the
;;; 4 m grid. It starts from a block tagged :START, keeps a frontier of open doorways,
;;; and at each step picks one, picks a block that fits it (rooms lead into corridors
;;; and stairs, corridors run on or open into rooms), and tries each of that block's
;;; doorways of the same kind against it, turned to face it, until one fits in free
;;; cells. A new doorway that meets an open one face to face joins it, which makes
;;; loops; one that runs into another block's wall is plugged. When enough rooms are
;;; in, or nothing more fits, every doorway still open is plugged.

(defparameter *level-seed* NIL "The generator's seed, or NIL for a new one every build.")
(defvar *last-level-seed* NIL "The seed of the last generated level, to build it again.")
(defparameter *generator-rooms* 8 "How many rooms a generated level has, the start included.")
(defparameter *generator-attempts* 300 "How many frontier doorways the generator tries before it stops.")
(defparameter *corridor-run* 0.55
  "From a corridor, the chance of another corridor piece, to the power of the run so far.")
(defparameter *generator-storeys* '(-2 2) "The lowest and highest storey a level may reach.")
(defvar *level-cells* (make-hash-table :test 'equal)
  "The generated level's grid cells (i j k), each the name of the block that fills it.")
(defparameter *generator-blocks* NIL
  "The blocks the generator chooses from, or NIL for every block with tags (KIT-BLOCKS).")

(defvar *generator-random* (make-random-state T)
  "The generator's own random state: placing a block spawns monsters, whose own use of
RANDOM depends on the old level, so the seed alone would not decide the level.")

(defun generator-roll (limit) (random limit *generator-random*))

(defun weighted-order (names)
  "NAMES in a random order, the heavier (BLOCK-WEIGHT) more likely first."
  (let ((left (copy-list names)) (out ()))
    (loop while left
          do (let ((pick (generator-roll (reduce #'+ left :key #'block-weight))))
               (let ((name (loop for n in left
                                 do (decf pick (block-weight n))
                                 when (< pick 0) return n
                                 finally (return (car (last left))))))
                 (push name out)
                 (setf left (remove name left :test #'string=)))))
    (nreverse out)))

(defun shuffle (list)
  (let ((v (coerce list 'vector)))
    (loop for i from (1- (length v)) downto 1
          do (rotatef (aref v i) (aref v (generator-roll (1+ i)))))
    (coerce v 'list)))

(defun outside-cell (connector)
  "The grid cell just outside CONNECTOR's doorway."
  (let* ((p (connector-location connector))
         (d (ecase (connector-direction connector)
              (:north '(0 -1)) (:south '(0 1)) (:west '(-1 0)) (:east '(1 0))))
         (size hexmaw.blueprint:*cell-size*))
    (list (floor (+ (vx p) (* 2 (first d))) size)
          (floor (+ (vz p) (* 2 (second d))) size)
          (round (vy p) hexmaw.blueprint:*storey-height*))))

(defun facing-p (a b)
  "True if doorways A and B meet face to face: one place, opposite ways, one kind."
  (and (< (vdistance (connector-location a) (connector-location b)) 0.1)
       (eq (connector-direction a) (opposite-direction (connector-direction b)))
       (string-equal (connector-kind a) (connector-kind b))))

(defclass open-door ()
  ((connector :initarg :connector :reader door-connector)
   (run :initarg :run :initform 0 :reader door-run
        :documentation "How many corridor pieces lead to it since the last room.")))

(defun generate-level (container &key (seed (or *level-seed* (random most-positive-fixnum (make-random-state T))))
                                      (rooms *generator-rooms*))
  (setf *last-level-seed* seed)
  (let* ((*generator-random* (sb-ext:seed-random-state seed))
         (*block-random* *generator-random*)
         (kit (or *generator-blocks* (remove-if-not #'block-tags (kit-blocks))))
         (cells (setf *level-cells* (make-hash-table :test 'equal)))
         (frontier ()) (shut ()) (doors ()) (placed-rooms 0))
    (labels ((tagged (&rest tags) (remove-if-not (lambda (n) (intersection tags (block-tags n))) kit))
             (free-p (list)
               (destructuring-bind (lowest highest) *generator-storeys*
                 (loop for cell in list
                       always (and (<= lowest (third cell) highest) (not (gethash cell cells))))))
             (shut (door) (push (door-connector door) shut))
             (place (name at turns run &key (spawns T) joined)
               (dolist (cell (block-cells name at turns)) (setf (gethash cell cells) name))
               (when (member :room (block-tags name)) (incf placed-rooms))
               (let ((run (if (member :room (block-tags name)) 0 (1+ run))))
                 (dolist (c (place-block name container :at at :turns turns :spawns spawns))
                   (push c doors)
                   (let ((other (find-if (lambda (d) (facing-p c (door-connector d))) frontier)))
                     ;; A doorway that meets another shares its portal.
                     (cond ((and joined (facing-p c joined)) (drop-portal c))
                           (other (drop-portal c) (setf frontier (remove other frontier)))
                           (T (push (make-instance 'open-door :connector c :run run) frontier))))))
               ;; Doorways that now open into a block's wall get plugged.
               (dolist (d frontier)
                 (let ((c (door-connector d)))
                   (when (gethash (outside-cell c) cells)
                     (setf frontier (remove d frontier))
                     (shut d)))))
             (try (door)
               (let* ((c (door-connector door))
                      (from-room (= 0 (door-run door)))
                      (corridor (or from-room (< (generator-roll 1.0) (expt *corridor-run* (door-run door)))))
                      (choices (weighted-order (if corridor (tagged :corridor :stair) (tagged :room)))))
                 (dolist (name choices NIL)
                   (dolist (mine (shuffle (remove-if-not (lambda (m) (string-equal (getf m :kind) (connector-kind c)))
                                                         (getf (find-block name) :connectors))))
                     (multiple-value-bind (at turns)
                         (attach-placement name (getf mine :name) (connector-location c)
                                           (opposite-direction (connector-direction c)))
                       (when (free-p (block-cells name at turns))
                         (setf frontier (remove door frontier))
                         (place name at turns (door-run door) :joined c)
                         (return-from try T))))))))
      ;; The start, lined up so its walls fall on the grid.
      (let* ((start (or (first (weighted-order (tagged :start))) (error "No block is tagged start.")))
             (low (block-world-bounds start (vec 0 0 0) 0))
             (at (vec (mod (- (vx low)) hexmaw.blueprint:*cell-size*) 0
                      (mod (- (vz low)) hexmaw.blueprint:*cell-size*))))
        (place start at 0 0 :spawns NIL)
        (v<- *spawn-point* at)
        (when *player* (v<- (feet *player*) at)))
      (loop repeat *generator-attempts*
            while (and frontier (< placed-rooms rooms))
            do (let ((door (nth (generator-roll (length frontier)) frontier)))
                 (unless (try door)
                   (setf frontier (remove door frontier))
                   (shut door))))
      ;; A stair that ends in a plug leads nowhere: give each still open one more piece.
      (dolist (d frontier)
        (when (and (member d frontier)
                   (member :stair (block-tags (connector-block (door-connector d)))))
          (try d)))
      (dolist (d frontier) (shut d))
      (dolist (c shut) (seal-connector container c))
      ;; Every doorway left open should meet another.
      (dolist (c doors)
        (unless (or (member c shut) (find-if (lambda (o) (facing-p c o)) doors))
          (v:warn :hexmaw "Generated level ~d: ~a opens onto nothing." seed c)))
      (v:info :hexmaw "Generated level ~d: ~d rooms, ~d cells." seed placed-rooms (hash-table-count cells))
      seed)))

(defun level-map (&optional (stream *standard-output*))
  "Print the generated level's cells, a storey at a time, north up: each cell is the first
letter of its block's name, upper case for rooms, and @ is the start."
  (let ((keys (loop for k being the hash-keys of *level-cells* collect k)))
    (when keys
      (loop for k from (reduce #'min keys :key #'third) to (reduce #'max keys :key #'third)
            do (format stream "~&storey ~d~%" k)
               (loop for j from (reduce #'min keys :key #'second) to (reduce #'max keys :key #'second)
                     do (loop for i from (reduce #'min keys :key #'first) to (reduce #'max keys :key #'first)
                              for name = (gethash (list i j k) *level-cells*)
                              do (write-char (cond ((null name) #\.)
                                                   ((member :room (block-tags name)) (char-upcase (char name 0)))
                                                   (T (char-downcase (char name 0))))
                                             stream))
                        (terpri stream))))))
