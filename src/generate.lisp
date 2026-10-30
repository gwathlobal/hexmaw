(in-package #:hexmaw)

;;; Level generator (*LEVEL* :GENERATED): grows a level from the kit's blocks on the
;;; 4 m grid. It starts from a block tagged :START, keeps a frontier of open doorways,
;;; and at each step picks one, picks a block that fits it (rooms lead into corridors
;;; and stairs, corridors run on or open into rooms), and tries each of that block's
;;; doorways of the same kind against it, turned to face it, until one fits in free
;;; cells. A new doorway that meets an open one face to face joins it, which makes
;;; loops; one that runs into another block's wall is plugged. When enough rooms are
;;; in, or nothing more fits, every doorway still open is plugged.
;;;
;;; Rivers: blocks joined through river and stream doorways (lava down the middle). The
;;; first river block comes in like any corridor or room, through an ordinary doorway, and
;;; starts a river with a target length in blocks. Its open river doorways are tried
;;; before any other, with river pieces until the river has its length and ends from then
;;; on, so each arm ends in an end block (whose other doorways go on into the dungeon), in
;;; a join with another river doorway, or, if nothing fits, in a plug.
;;;
;;; Ice: the ice caves' doorways are all of kind ice, so they join only each other and the
;;; ice gates, blocks half rock and half ice with one ordinary doorway and one ice. A gate's
;;; rock side joins only a cave without lava (GATE-ALLOWED-P), so the ice is a frozen wing
;;; of the caves.

(defparameter *level-seed* NIL "The generator's seed, or NIL for a new one every build.")
(defvar *last-level-seed* NIL "The seed of the last generated level, to build it again.")
(defparameter *generator-rooms* 8 "How many rooms a generated level has, the start included.")
(defparameter *generator-attempts* 300 "How many frontier doorways the generator tries before it stops.")
(defparameter *corridor-run* 0.55
  "From a corridor, the chance of another corridor piece, to the power of the run so far.")
(defparameter *generator-storeys* '(-2 2) "The lowest and highest storey a level may reach.")
(defparameter *river-length* '(5 9) "The fewest and most blocks a river runs to before it ends.")
(defparameter *max-rivers* 1 "How many rivers a level may start.")
(defparameter *start-clearance* 16.0
  "Metres round the player's start where no monster spawns: the start block's neighbours
would see the player the moment the level begins.")
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

(defun outside-cells (connector)
  "The grid cells just outside CONNECTOR's doorway: one, or two for a doorway two cells wide."
  (let* ((p (connector-location connector))
         (d (ecase (connector-direction connector)
              (:north '(0 -1)) (:south '(0 1)) (:west '(-1 0)) (:east '(1 0))))
         (size hexmaw.blueprint:*cell-size*)
         (wide (< size (connector-size (connector-kind connector))))
         ;; A wide doorway is centred on a cell boundary: the cells either side of it.
         (along (if wide '(-1 1) '(0))))
    (loop for a in along
          collect (list (floor (+ (vx p) (* 2 (first d)) (* a (abs (second d)))) size)
                        (floor (+ (vz p) (* 2 (second d)) (* a (abs (first d)))) size)
                        (round (vy p) hexmaw.blueprint:*storey-height*)))))

(defun river-kind-p (kind)
  "True if a doorway of KIND carries a river: lava down its middle."
  (fourth (assoc kind hexmaw.blueprint:*connector-kinds* :test #'string-equal)))

(defclass river ()
  ((target :initarg :target :reader river-target :documentation "How many blocks it runs to.")
   (pieces :initform 0 :accessor river-pieces :documentation "How many blocks it has.")
   (ends :initform () :accessor river-ends :documentation "How each arm ended: :END, :JOIN or :PLUG."))
  (:documentation "A river being grown: its blocks, joined by river and stream doorways."))

(defun facing-p (a b)
  "True if doorways A and B meet face to face: one place, opposite ways, one kind."
  (and (< (vdistance (connector-location a) (connector-location b)) 0.1)
       (eq (connector-direction a) (opposite-direction (connector-direction b)))
       (string-equal (connector-kind a) (connector-kind b))))

(defun gate-allowed-p (a b kind)
  "True if blocks A and B may join through a doorway of KIND: an ice gate's ordinary,
rock side joins only a block tagged cave, and not one tagged lava: ice beside lava makes
no sense."
  (flet ((gate-p (n) (member :ice-gate (block-tags n)))
         (cave-p (n) (let ((tags (block-tags n))) (and (member :cave tags) (not (member :lava tags))))))
    (or (string-not-equal kind "door")
        (and (or (not (gate-p a)) (cave-p b))
             (or (not (gate-p b)) (cave-p a))))))

(defun joined-p (a b)
  "True if placed doorways A and B were joined: face to face, one portal left between them.
Sealing a doorway takes its portal away, joining takes away one of the two."
  (and (facing-p a b)
       (or (find (connector-portal a) *portals*) (find (connector-portal b) *portals*))))

(defun check-ice-joins ()
  "Warn about every pair of joined doorways that GATE-ALLOWED-P forbids: an ice gate's
rock side opening onto anything but a cave. (An ice doorway's kind keeps it to ice.)
Returns the pairs."
  (let ((bad ()))
    (loop for (a . rest) on *level-doorways*
          do (dolist (b rest)
               (when (and (joined-p a b)
                          (not (gate-allowed-p (connector-block a) (connector-block b) (connector-kind a))))
                 (push (list a b) bad)
                 (v:warn :hexmaw "Ice gate joined to something not a cave: ~a and ~a." a b))))
    bad))

(defclass open-door ()
  ((connector :initarg :connector :reader door-connector)
   (run :initarg :run :initform 0 :reader door-run
        :documentation "How many corridor pieces lead to it since the last room.")
   (river :initarg :river :initform NIL :reader door-river
          :documentation "The RIVER a river or stream doorway belongs to.")))

(defvar *level-rivers* () "The last generated level's rivers.")

(defun generate-level (container &key (seed (or *level-seed* (random most-positive-fixnum (make-random-state T))))
                                      (rooms *generator-rooms*))
  (setf *last-level-seed* seed)
  (let* ((*generator-random* (sb-ext:seed-random-state seed))
         (*block-random* *generator-random*)
         (*spawn-clearance* NIL)
         (kit (or *generator-blocks* (remove-if-not #'block-tags (kit-blocks))))
         (cells (setf *level-cells* (make-hash-table :test 'equal)))
         (frontier ()) (shut ()) (doors ()) (placed-rooms 0) (rivers ()))
    (labels ((river-block-p (n) (intersection '(:river :river-end) (block-tags n)))
             (tagged (&rest tags)
               ;; Once the level has its rivers, no ordinary doorway starts another.
               (remove-if (lambda (n) (and (<= *max-rivers* (length rivers)) (river-block-p n)))
                          (remove-if-not (lambda (n) (intersection tags (block-tags n))) kit)))
             (with-doorway (kind) (remove-if-not (lambda (n) (find kind (getf (find-block n) :connectors)
                                                                 :key (lambda (m) (getf m :kind)) :test #'string-equal))
                                                 kit))
             (free-p (list)
               (destructuring-bind (lowest highest) *generator-storeys*
                 (loop for cell in list
                       always (and (<= lowest (third cell) highest) (not (gethash cell cells))))))
             (shut (door)
               (push (door-connector door) shut)
               (when (door-river door) (push :plug (river-ends (door-river door)))))
             (place (name at turns run &key (spawns T) joined river)
               (dolist (cell (block-cells name at turns)) (setf (gethash cell cells) name))
               (when (member :room (block-tags name)) (incf placed-rooms))
               (let ((run (if (member :room (block-tags name)) 0 (1+ run)))
                     (connectors (place-block name container :at at :turns turns :spawns spawns)))
                 ;; A river block joins the river it was reached by, or starts one.
                 (when (some (lambda (c) (river-kind-p (connector-kind c))) connectors)
                   (unless river
                     (destructuring-bind (low high) *river-length*
                       (setf river (make-instance 'river :target (+ low (generator-roll (1+ (- high low)))))))
                     (push river rivers))
                   (incf (river-pieces river))
                   (when (member :river-end (block-tags name)) (push :end (river-ends river))))
                 (dolist (c connectors)
                   (push c doors)
                   (let ((other (find-if (lambda (d) (let ((o (door-connector d)))
                                                       (and (facing-p c o)
                                                            (gate-allowed-p name (connector-block o) (connector-kind c)))))
                                         frontier))
                         (river (and (river-kind-p (connector-kind c)) river)))
                     ;; A doorway that meets another shares its portal.
                     (cond ((and joined (facing-p c joined)) (drop-portal c))
                           (other (drop-portal c) (setf frontier (remove other frontier))
                                  (when river (push :join (river-ends river))))
                           (T (push (make-instance 'open-door :connector c :run run :river river) frontier))))))
               ;; Doorways that now open into a block's wall get plugged.
               (dolist (d frontier)
                 (let ((c (door-connector d)))
                   (when (some (lambda (cell) (gethash cell cells)) (outside-cells c))
                     (setf frontier (remove d frontier))
                     (shut d)))))
             (attach (door names)
               ;; Place the first of NAMES that fits DOOR, by any doorway of its kind.
               (let ((c (door-connector door)))
                 (dolist (name names NIL)
                   (dolist (mine (shuffle (remove-if-not (lambda (m) (string-equal (getf m :kind) (connector-kind c)))
                                                         (getf (find-block name) :connectors))))
                     (multiple-value-bind (at turns)
                         (attach-placement name (getf mine :name) (connector-location c)
                                           (opposite-direction (connector-direction c)))
                       (when (free-p (block-cells name at turns))
                         (setf frontier (remove door frontier))
                         (place name at turns (door-run door) :joined c :river (door-river door))
                         (return-from attach T)))))))
             (river-choices (door)
               ;; Pieces until the river has its length, ends from then on; before it, an
               ;; end is still tried when no piece fits, ahead of a plug.
               (let* ((river (door-river door))
                      (fitting (with-doorway (connector-kind (door-connector door))))
                      (ends (weighted-order (remove-if-not (lambda (n) (member :river-end (block-tags n))) fitting)))
                      (pieces (weighted-order (remove-if (lambda (n) (member :river-end (block-tags n))) fitting))))
                 (if (< (river-pieces river) (river-target river))
                     (append pieces ends)
                     ends)))
             (allowed (door names)
               ;; Only the blocks that may join DOOR's block through it: an ice gate's rock
               ;; side, and the rock side of a gate brought to it, join only caves; and a
               ;; gate's ice side leads into the ice, not straight to another gate.
               (let* ((c (door-connector door))
                      (from (connector-block c)))
                 (remove-if-not (lambda (n) (and (gate-allowed-p from n (connector-kind c))
                                                 (not (and (member :ice-gate (block-tags from))
                                                           (member :ice-gate (block-tags n))))))
                                names)))
             (try (door)
               (if (door-river door)
                   (attach door (river-choices door))
                   (let* ((from-room (= 0 (door-run door)))
                          (corridor (or from-room (< (generator-roll 1.0) (expt *corridor-run* (door-run door)))))
                          (first (weighted-order (if corridor (tagged :corridor :stair) (tagged :room))))
                          ;; Few blocks have ice doorways, so one that fits no corridor tries
                          ;; the rooms too, and the other way round, before it is plugged.
                          (then (when (string-equal (connector-kind (door-connector door)) "ice")
                                  (weighted-order (if corridor (tagged :room) (tagged :corridor :stair))))))
                     (attach door (allowed door (append first then))))))
             (next-door ()
               ;; A river's doorways come first, so it is finished early.
               (let ((rivers (remove-if-not #'door-river frontier)))
                 (if rivers
                     (nth (generator-roll (length rivers)) rivers)
                     (nth (generator-roll (length frontier)) frontier)))))
      ;; The start, lined up so its walls fall on the grid.
      (let* ((start (or (first (weighted-order (tagged :start))) (error "No block is tagged start.")))
             (low (block-world-bounds start (vec 0 0 0) 0))
             (at (vec (mod (- (vx low)) hexmaw.blueprint:*cell-size*) 0
                      (mod (- (vz low)) hexmaw.blueprint:*cell-size*))))
        (place start at 0 0 :spawns NIL)
        (setf *spawn-clearance* (cons (vcopy at) *start-clearance*))
        (v<- *spawn-point* at)
        (when *player* (v<- (feet *player*) at)))
      (loop repeat *generator-attempts*
            while (and frontier (< placed-rooms rooms))
            do (let ((door (next-door)))
                 (unless (try door)
                   (setf frontier (remove door frontier))
                   (shut door))))
      ;; The room quota doesn't cut a river short: each open arm still gets its end.
      (dolist (d frontier)
        (when (and (member d frontier) (door-river d))
          (attach d (weighted-order (remove-if-not (lambda (n) (member :river-end (block-tags n)))
                                                   (with-doorway (connector-kind (door-connector d))))))))
      ;; A stair that ends in a plug leads nowhere: give each still open one more piece.
      (dolist (d frontier)
        (when (and (member d frontier)
                   (member :stair (block-tags (connector-block (door-connector d)))))
          (try d)))
      ;; Nor does an ice gate: each still open gets a room, ice on its ice side, a cave on
      ;; its rock side.
      (dolist (d frontier)
        (when (and (member d frontier)
                   (member :ice-gate (block-tags (connector-block (door-connector d)))))
          (attach d (allowed d (weighted-order (tagged :room))))))
      (dolist (d frontier) (shut d))
      (dolist (c shut) (seal-connector container c))
      ;; Every doorway left open should meet another.
      (dolist (c doors)
        (unless (or (member c shut) (find-if (lambda (o) (facing-p c o)) doors))
          (v:warn :hexmaw "Generated level ~d: ~a opens onto nothing." seed c)))
      (setf *level-rivers* (reverse rivers))
      (v:info :hexmaw "Generated level ~d: ~d rooms, ~d cells~{, a river of ~d block~:p (target ~d) ending ~{~(~a~)~^, ~}~}."
              seed placed-rooms (hash-table-count cells)
              (loop for r in *level-rivers* append (list (river-pieces r) (river-target r) (reverse (river-ends r)))))
      seed)))

(defun level-map (&optional (stream *standard-output*))
  "Print the generated level's cells, a storey at a time, north up: each cell is the first
letter of its block's name, upper case for rooms, ~ for a river's blocks."
  (let ((keys (loop for k being the hash-keys of *level-cells* collect k)))
    (when keys
      (loop for k from (reduce #'min keys :key #'third) to (reduce #'max keys :key #'third)
            do (format stream "~&storey ~d~%" k)
               (loop for j from (reduce #'min keys :key #'second) to (reduce #'max keys :key #'second)
                     do (loop for i from (reduce #'min keys :key #'first) to (reduce #'max keys :key #'first)
                              for name = (gethash (list i j k) *level-cells*)
                              do (write-char (cond ((null name) #\.)
                                                   ((intersection '(:river :river-end) (block-tags name)) #\~)
                                                   ((member :room (block-tags name)) (char-upcase (char name 0)))
                                                   (T (char-downcase (char name 0))))
                                             stream))
                        (terpri stream))))))
