(in-package #:hexmaw)

;;; Level generator (*LEVEL* :GENERATED): grows a level from the kit's blocks on the
;;; 4 m grid. It starts from a block tagged :START, keeps a frontier of open doorways,
;;; and at each step picks one, picks a block that fits it (rooms lead into corridors
;;; and stairs, corridors run on or open into rooms), and tries each of that block's
;;; doorways of the same kind against it, turned to face it, until one fits in free
;;; cells. A new doorway that meets an open one face to face joins it, which makes
;;; loops; one that runs into another block's wall is plugged. Growth stops when the rooms
;;; in and the corridors still open add up to the rooms wanted. Then each open corridor gets
;;; a room, or a plug only if no room fits, and every doorway still open is plugged.
;;;
;;; Networks: blocks joined through their own kind of doorway, which ordinary blocks don't
;;; have (*NETWORKS*): rivers, through river doorways (lava down the middle, between banks)
;;; and stream doorways (lava wall to wall, waded), and high quarters, through high doorways
;;; (two storeys of room, for the ogre's leaps), and flooded runs, through underwater
;;; doorways (passages full of water, swum on one breath, a cistern at each end, whose
;;; ledges go on into the dungeon), and canals, through canal doorways (a river's, deep
;;; water in place of lava). The first block of one comes in like any
;;; corridor or room, through an ordinary doorway, and starts a network with a target length
;;; in blocks. Its open network doorways are tried before any other, with pieces until the
;;; network has its length and ends from then on, so each arm ends in an end block (whose
;;; other doorways go on into the dungeon), in a join with another of its doorways, or, if
;;; nothing fits, in a plug.
;;;
;;; Ice: the ice caves' doorways are all of kind ice, so they join only each other and the
;;; ice gates, blocks half rock and half ice with one ordinary doorway and one ice. A gate's
;;; rock side joins only a cave without lava (GATE-ALLOWED-P), so the ice is a frozen wing
;;; of the caves.

(defparameter *generator-rooms* 16
  "How many rooms GENERATE-LEVEL aims for, the start included. A run's levels say their own (*RUN-LEVELS*).")
(defparameter *generator-attempts* 300 "How many frontier doorways the generator tries before it stops.")
(defparameter *corridor-run* 0.55
  "From a corridor, the chance of another corridor piece, to the power of the run so far.")
(defparameter *generator-storeys* '(-2 2) "The lowest and highest storey a level may reach.")
(defparameter *river-length* '(5 9) "The fewest and most blocks a river runs to before it ends.")
(defparameter *max-rivers* 1 "How many rivers a level may start.")
(defparameter *high-length* '(3 6) "The fewest and most blocks a high quarter runs to before it ends.")
(defparameter *max-high-networks* 1 "How many high quarters a level may start.")
(defparameter *flooded-length* '(2 4)
  "The fewest and most blocks a flooded run has before its ends, its first cistern included:
short, so it is swum on one breath.")
(defparameter *max-flooded-networks* 1 "How many flooded runs a level may start.")
(defparameter *canal-length* '(3 6) "The fewest and most blocks a canal runs to before it ends.")
(defparameter *max-canals* 1 "How many canals a level may start.")
(defparameter *networks*
  '((:river ("river" "stream") :river :river-end *river-length* *max-rivers*)
    (:high ("high") :high :high-end *high-length* *max-high-networks*)
    (:flooded ("underwater") :flooded :cistern *flooded-length* *max-flooded-networks*)
    (:canal ("canal") :canal :canal-end *canal-length* *max-canals*))
  "The networks the generator grows: each family, the doorway kinds that join its blocks,
the tags of its pieces and of its ends, and the variables that hold its length in blocks and
how many a level may start.")
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

(defparameter *altar-block* "shrine-altar" "The block a generated level's spellforge altar stands in (forge.lisp).")

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

(defun kind-network (kind)
  "The family of network a doorway of KIND joins (*NETWORKS*), or NIL for an ordinary one."
  (first (find-if (lambda (spec) (member kind (second spec) :test #'string-equal)) *networks*)))

(defun block-network (name)
  "The family of network block NAME is a piece or an end of, by its tags, or NIL."
  (first (find-if (lambda (spec) (intersection (list (third spec) (fourth spec)) (block-tags name))) *networks*)))

(defun network-end-p (name family)
  (member (fourth (assoc family *networks*)) (block-tags name)))

(defclass network ()
  ((family :initarg :family :reader network-family :documentation "Its entry in *NETWORKS*: :RIVER, :HIGH, :FLOODED or :CANAL.")
   (target :initarg :target :reader network-target :documentation "How many blocks it runs to.")
   (pieces :initform 0 :accessor network-pieces :documentation "How many blocks it has.")
   (ends :initform () :accessor network-ends :documentation "How each arm ended: :END, :JOIN or :PLUG."))
  (:documentation "A network being grown: its blocks, joined by its own kind of doorway."))

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
   (depth :initarg :depth :initform 0 :reader door-depth
          :documentation "How many blocks lie between it and the start.")
   (network :initarg :network :initform NIL :reader door-network
            :documentation "The NETWORK a network's doorway belongs to.")))

(defvar *level-networks* () "The last generated level's networks: its rivers and high quarters.")

(defun generate-level (container &key (seed (or *level-seed* (random most-positive-fixnum (make-random-state T))))
                                      (rooms *generator-rooms*) exit altar-chance)
  "Grow a level from SEED, aiming for ROOMS rooms. EXIT names a block to put on the open
doorway furthest from the start once it has grown, or is a list of them, tried in order.
After it, with ALTAR-CHANCE (0 to 1, or NIL), the spellforge's altar room goes on a doorway
part way in (*ALTAR-BLOCK*). Returns the seed and whether EXIT went in."
  (setf *last-level-seed* seed)
  (let* ((*generator-random* (sb-ext:seed-random-state seed))
         (*block-random* *generator-random*)
         (*spawn-clearance* NIL)
         (kit (or *generator-blocks* (remove-if-not #'block-tags (kit-blocks))))
         (cells (setf *level-cells* (make-hash-table :test 'equal)))
         (frontier ()) (shut ()) (doors ()) (placed-rooms 0) (networks ()) (exit-placed NIL))
    (labels ((full-p (family)
               ;; True once the level has as many networks of FAMILY as it may.
               (<= (symbol-value (sixth (assoc family *networks*))) (count family networks :key #'network-family)))
             (tagged (&rest tags)
               ;; Once the level has a family's networks, no ordinary doorway starts another.
               (remove-if (lambda (n) (let ((family (block-network n))) (and family (full-p family))))
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
               (when (door-network door) (push :plug (network-ends (door-network door)))))
             (place (name at turns run &key (spawns T) joined network (depth 0))
               (dolist (cell (block-cells name at turns)) (setf (gethash cell cells) name))
               (when (member :room (block-tags name)) (incf placed-rooms))
               (let ((run (if (member :room (block-tags name)) 0 (1+ run)))
                     (connectors (place-block name container :at at :turns turns :spawns spawns)))
                 ;; A network's block joins the network it was reached by, or starts one.
                 (let ((family (some (lambda (c) (kind-network (connector-kind c))) connectors)))
                   (when family
                     (unless (and network (eq family (network-family network)))
                       (destructuring-bind (low high) (symbol-value (fifth (assoc family *networks*)))
                         (setf network (make-instance 'network :family family
                                                               :target (+ low (generator-roll (1+ (- high low))))))
                         (push network networks)))
                     (incf (network-pieces network))
                     (when (network-end-p name family) (push :end (network-ends network)))))
                 (dolist (c connectors)
                   (push c doors)
                   (let ((other (find-if (lambda (d) (let ((o (door-connector d)))
                                                       (and (facing-p c o)
                                                            (gate-allowed-p name (connector-block o) (connector-kind c)))))
                                         frontier))
                         (network (and (kind-network (connector-kind c)) network)))
                     ;; A doorway that meets another shares its portal.
                     (cond ((and joined (facing-p c joined)) (drop-portal c))
                           (other (drop-portal c) (setf frontier (remove other frontier))
                                  (when network (push :join (network-ends network))))
                           (T (push (make-instance 'open-door :connector c :run run :depth (1+ depth) :network network)
                                    frontier))))))
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
                         (place name at turns (door-run door) :joined c :network (door-network door)
                                                              :depth (door-depth door))
                         (return-from attach T)))))))
             (ends (door)
               ;; The blocks that may end DOOR's arm: its end blocks, heavier first, then any
               ;; other room with its doorway, for when no end block fits.
               (let ((family (network-family (door-network door)))
                     (fitting (with-doorway (connector-kind (door-connector door)))))
                 (append (weighted-order (remove-if-not (lambda (n) (network-end-p n family)) fitting))
                         (weighted-order (remove-if-not (lambda (n) (and (member :room (block-tags n))
                                                                         (not (network-end-p n family))))
                                                        fitting)))))
             (network-choices (door)
               ;; Pieces until the network has its length, ends from then on; before it, an
               ;; end is still tried when no piece fits, ahead of a plug.
               (let* ((network (door-network door))
                      (pieces (weighted-order (remove-if (lambda (n) (network-end-p n (network-family network)))
                                                         (with-doorway (connector-kind (door-connector door)))))))
                 (if (< (network-pieces network) (network-target network))
                     (append pieces (ends door))
                     (ends door))))
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
               (if (door-network door)
                   (attach door (network-choices door))
                   (let* ((from-room (= 0 (door-run door)))
                          (corridor (or from-room (< (generator-roll 1.0) (expt *corridor-run* (door-run door)))))
                          (first (weighted-order (if corridor (tagged :corridor :stair) (tagged :room))))
                          ;; A corridor tries both before it ends in a plug. So does an ice
                          ;; doorway, since few blocks have one.
                          (then (when (or (not from-room)
                                          (string-equal (connector-kind (door-connector door)) "ice"))
                                  (weighted-order (if corridor (tagged :room) (tagged :corridor :stair))))))
                     (attach door (allowed door (append first then))))))
             (corridor-door-p (door)
               ;; True if DOOR leads on from a corridor or stair, so a plug there is a stub.
               (not (member :room (block-tags (connector-block (door-connector door))))))
             (finish (door)
               ;; End DOOR's corridor in a room. Few rooms take a narrow doorway, and a stair has
               ;; to arrive somewhere, so when none fits those take one more corridor piece,
               ;; which is finished in turn. Nothing here starts a network: its arms would be
               ;; plugged.
               (let ((c (door-connector door)))
                 (or (attach door (allowed door (weighted-order (remove-if #'block-network (tagged :room)))))
                     (when (or (string-equal (connector-kind c) "narrow")
                               (member :stair (block-tags (connector-block c))))
                       (attach door (allowed door (weighted-order (remove-if #'block-network (tagged :corridor)))))))))
             (next-door ()
               ;; A network's doorways come first, so it is finished early.
               (let ((open (remove-if-not #'door-network frontier)))
                 (if open
                     (nth (generator-roll (length open)) open)
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
      ;; Grow, then finish what is open. A corridor that no room fits leaves the level short
      ;; of its rooms, so growth goes on from the rooms' doorways until it has them.
      (let ((attempts *generator-attempts*) (tried ()))
        (loop
          ;; Each corridor still open will end in a room, so it counts as one already.
          (loop while (and frontier (< 0 attempts)
                           (< (+ placed-rooms (count-if #'corridor-door-p frontier)) rooms))
                do (decf attempts)
                   (let ((door (next-door)))
                     (unless (try door)
                       (setf frontier (remove door frontier))
                       (shut door))))
          ;; The room quota doesn't cut a network short: each open arm still gets its end.
          (dolist (d frontier)
            (when (and (member d frontier) (door-network d) (not (member d tried)))
              (push d tried)
              (attach d (ends d))))
          ;; No corridor ends in a plug while a room fits, an ice gate's included: ice on its
          ;; ice side, a cave on its rock side.
          (loop for d = (find-if (lambda (d) (and (corridor-door-p d) (not (door-network d)) (not (member d tried))))
                                 frontier)
                while d
                do (push d tried)
                   (finish d))
          ;; Whatever corridor or arm no room took is plugged now.
          (dolist (d frontier)
            (when (corridor-door-p d)
              (setf frontier (remove d frontier))
              (shut d)))
          (unless (and frontier (< 0 attempts) (< placed-rooms rooms))
            (return))))
      ;; The way off the level, as far from the start as a doorway is still open.
      (when exit
        (setf exit-placed (loop for d in (stable-sort (copy-list frontier) #'> :key #'door-depth)
                                thereis (attach d (allowed d (uiop:ensure-list exit))))))
      ;; Last, so the rest of the level is the same whether it rolls one or not.
      (when (and altar-chance (< (generator-roll 1.0) altar-chance))
        (let* ((deepest (reduce #'max frontier :key #'door-depth :initial-value 0))
               (middle (remove-if-not (lambda (d) (<= (* 0.3 deepest) (door-depth d) (* 0.7 deepest))) frontier))
               (placed (loop for d in (append (shuffle middle) (shuffle (set-difference frontier middle)))
                             thereis (attach d (allowed d (list *altar-block*))))))
          (v:info :hexmaw "Generated level ~d: ~:[no room for the altar~;an altar~]." seed placed)))
      (dolist (d frontier) (shut d))
      (dolist (c shut) (seal-connector container c))
      ;; Every doorway left open should meet another.
      (dolist (c doors)
        (unless (or (member c shut) (find-if (lambda (o) (facing-p c o)) doors))
          (v:warn :hexmaw "Generated level ~d: ~a opens onto nothing." seed c)))
      (setf *level-networks* (reverse networks))
      (v:info :hexmaw "Generated level ~d: ~d rooms, ~d cells~{, a ~(~a~) network of ~d block~:p (target ~d) ending ~{~(~a~)~^, ~}~}."
              seed placed-rooms (hash-table-count cells)
              (loop for n in *level-networks*
                    append (list (network-family n) (network-pieces n) (network-target n) (reverse (network-ends n)))))
      (values seed exit-placed))))

(defun level-map (&optional (stream *standard-output*))
  "Print the generated level's cells, a storey at a time, north up: each cell is the first
letter of its block's name, upper case for rooms, ~ for a river's blocks, ^ for a high
quarter's, = for a flooded run's and - for a canal's."
  (let ((keys (loop for k being the hash-keys of *level-cells* collect k)))
    (when keys
      (loop for k from (reduce #'min keys :key #'third) to (reduce #'max keys :key #'third)
            do (format stream "~&storey ~d~%" k)
               (loop for j from (reduce #'min keys :key #'second) to (reduce #'max keys :key #'second)
                     do (loop for i from (reduce #'min keys :key #'first) to (reduce #'max keys :key #'first)
                              for name = (gethash (list i j k) *level-cells*)
                              do (write-char (cond ((null name) #\.)
                                                   ((eq (block-network name) :river) #\~)
                                                   ((eq (block-network name) :high) #\^)
                                                   ((eq (block-network name) :flooded) #\=)
                                                   ((eq (block-network name) :canal) #\-)
                                                   ((member :room (block-tags name)) (char-upcase (char name 0)))
                                                   (T (char-downcase (char name 0))))
                                             stream))
                        (terpri stream))))))
