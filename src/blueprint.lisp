;;;; Level-block blueprints: a block drawn as text (data/blueprints/<name>.txt), built
;;;; into the .glb that blocks.lisp loads (data/blocks/<name>.glb). Its own small system,
;;;; hexmaw-blueprints, so tools/blueprint runs without Trial; the game builds a
;;;; stale block itself when it loads it (ENSURE-BLOCK). The format is in CLAUDE.md
;;;; ("Blueprints"); in short:
;;;;
;;;;   ; comment
;;;;   cells 3 3          footprint in 4 m cells, west-east then north-south
;;;;   storeys 1          5 m each
;;;;   ceiling 4          inside height of the top storey
;;;;   tags room start    for the generator, with WEIGHT
;;;;   material dais 0.58 0.47 0.30
;;;;   remap wall rock    draw what would be wall (border, lintels, plugs) in rock
;;;;   legend             one indented line per character: char action[, action...]
;;;;     % box 0 0.8 dais
;;;;   plan 0             storey 0, north up, to the next blank line
;;;;   #########nnnnnn#########
;;;;
;;;; A column is 0.5 m wide; a row is 1 m deep, except the first and last, the 0.5 m walls.

(defpackage #:hexmaw.blueprint
  (:use #:cl)
  (:export #:*cell-size* #:*storey-height* #:*connector-kinds* #:*lava-depth* #:*lava-surface* #:*water-surface*
           #:blueprint-error #:read-blueprint #:blueprint-names #:blueprint-path
           #:build-blueprint #:build-blueprints #:*build-blocks* #:ensure-block #:main))

(in-package #:hexmaw.blueprint)

(defparameter *cell-size* 4.0 "Blocks are whole cells this many metres across.")
(defparameter *storey-height* 5.0 "Storey K's floor is K times this many metres up.")
(defparameter *border* 0.5 "How thick the border walls and the floor and ceiling slabs are.")
(defparameter *max-riser* 0.45 "The most a stair step rises: the player's *STEP-HEIGHT*.")
(defparameter *connector-kinds* '(("door" 3.0 3.0) ("narrow" 2.0 2.5) ("river" 7.0 3.5 3.0) ("stream" 3.0 3.5 3.0)
                                   ("high" 7.0 9.0) ("ice" 3.0 3.0) ("underwater" 3.0 3.0)
                                   ("canal" 7.0 3.5 3.0))
  "Each kind of doorway: its name, width and height in metres, and for a river the width of
lava down its middle, between two banks; a stream's lava fills it wall to wall, no banks.
Each kind joins only itself. One wider than a cell spans two and is centred on the boundary
between them. A high doorway joins the high blocks, two storeys tall: at 9 m it is as tall
as they are inside, so it runs on up through the storey above (^ in that plan). An ice
cave's ice doorways join only ice caves and the ice gates that lead into them. An underwater doorway, full of water, joins a flooded passage
to the cisterns at either end of it. A canal's doorway is a river's with deep water in
place of lava: open down its middle to the water filling the storey below, which runs on
through the wall under it.")
(defparameter *default-ceiling* 4.0)
(defparameter *torch-height* 2.4 "Where T puts a torch's flame, above the storey's floor.")
(defparameter *torch-inset* 0.3
  "How far into the room a torch drawn on a border wall goes; ADD-TORCH stands it off the wall.")
(defparameter *lava-depth* 0.4 "Metres a lava pit's floor lies below the storey's floor: less than a step.")
(defparameter *lava-surface* 0.1 "Metres the lava's surface lies below the storey's floor.")
(defparameter *water-surface* 0.3
  "Metres deep water's surface lies below the floor of the storey above it: the ledge round a
pool stands this far out of the water, within a step.")
(defparameter *materials*
  '(("floor" 0.45 0.42 0.38) ("wall" 0.62 0.6 0.56) ("ceiling" 0.32 0.31 0.3) ("stair" 0.4 0.46 0.56)
    ("lava" 1.0 0.45 0.1) ("water" 0.2 0.36 0.45) ("ice" 0.72 0.86 0.95)
    ("ice-rock" 0.55 0.68 0.78) ("snow" 0.78 0.82 0.86))
  "The colours every blueprint has; its MATERIAL lines add to them or replace them.")

(defun root () (asdf:system-source-directory :hexmaw-blueprints))

(defun blueprint-path (name)
  (merge-pathnames (format NIL "data/blueprints/~(~a~).txt" name) (root)))

(defun block-output-path (name)
  (merge-pathnames (format NIL "data/blocks/~(~a~).glb" name) (root)))

(defun blueprint-names ()
  "Every blueprint's name, sorted."
  (sort (mapcar #'pathname-name (directory (merge-pathnames "data/blueprints/*.txt" (root))))
        #'string<))

;;; Errors point at the file, line and column.

(define-condition blueprint-error (error)
  ((file :initarg :file :initform NIL :reader error-file)
   (line :initarg :line :initform NIL :reader error-line)
   (column :initarg :column :initform NIL :reader error-column)
   (message :initarg :message :reader error-message))
  (:report (lambda (c s)
             (format s "~@[~a:~]~@[~d:~]~@[~d:~] ~a"
                     (and (error-file c) (file-namestring (error-file c)))
                     (error-line c) (error-column c) (error-message c)))))

(defvar *file* NIL "The blueprint being read, for errors.")

(defun fail (line column control &rest args)
  (error 'blueprint-error :file *file* :line line :column column
                          :message (apply #'format NIL control args)))

;;; Reading.

(defclass blueprint ()
  ((name :initarg :name :accessor name)
   (path :initarg :path :initform NIL :accessor path)
   (cells :initform NIL :accessor cells :documentation "(WIDTH DEPTH) in cells.")
   (storeys :initform 1 :accessor storeys)
   (ceiling-height :initform *default-ceiling* :accessor ceiling-height)
   (tags :initform () :accessor tags)
   (weight :initform 1 :accessor weight)
   (grid-free :initform NIL :accessor grid-free :documentation "True to skip the grid checks.")
   (mirror :initform NIL :accessor mirror :documentation "True to also build <name>-mirror.")
   (materials :initform (copy-tree *materials*) :accessor materials)
   (remaps :initform () :accessor remaps
           :documentation "(FROM . TO) material names: the block draws TO wherever it would draw FROM.")
   (legend :initform (make-hash-table) :accessor legend
           :documentation "Character -> (line . actions), for the characters this file defines.")
   (plans :initform () :accessor plans :documentation "One plan per storey, storey 0 first.")))

(defclass plan ()
  ((storey :initarg :storey :reader storey)
   (rows :initarg :rows :reader rows :documentation "A vector of strings, north first.")
   (line :initarg :line :reader line :documentation "The line its first row is on.")))

(defun blank-p (string)
  (every (lambda (c) (member c '(#\Space #\Tab))) string))

(defun words (string)
  (loop with start = 0
        for space = (position-if (lambda (c) (member c '(#\Space #\Tab))) string :start start)
        for word = (subseq string start space)
        unless (string= word "") collect word
        while space do (setf start (1+ space))))

(defun strip-comment (string)
  (subseq string 0 (position #\; string)))

(defun parse-number (word line)
  (unless (and word (plusp (length word))
               (every (lambda (c) (find c "0123456789.-+")) word)
               (some #'digit-char-p word))
    (fail line NIL "Expected a number, got ~s." word))
  (let ((value (let ((*read-default-float-format* 'single-float)
                     (*read-eval* NIL))
                 (read-from-string word))))
    (unless (realp value) (fail line NIL "Expected a number, got ~s." word))
    (float value 1f0)))

(defun parse-count (word line)
  (let ((n (parse-number word line)))
    (unless (and (= n (round n)) (plusp n)) (fail line NIL "Expected a whole number, got ~s." word))
    (round n)))

(defun parse-direction (word line)
  (or (cdr (assoc word '(("north" . :north) ("east" . :east) ("south" . :south) ("west" . :west))
                  :test #'string-equal))
      (fail line NIL "Expected north, east, south or west, got ~s." word)))

(defun parse-height (word line)
  "A height above the storey's floor, or :TOP for the storey's top."
  (if (string-equal word "top") :top (parse-number word line)))

(defparameter *npc-conditions* '("thriving" "besieged" "sacked")
  "The conditions a settlement may be in, which an npc or spawn may be limited to.")

(defun parse-conditions (words line)
  "WORDS as a list of (CONDITION PERCENT): \"sacked:50\" is there half the time when sacked."
  (loop for word in words
        collect (let* ((colon (position #\: word))
                       (name (string-downcase (subseq word 0 colon)))
                       (percent (if colon (parse-number (subseq word (1+ colon)) line) 100)))
                  (unless (member name *npc-conditions* :test #'string=)
                    (fail line NIL "No settlement condition ~s; there are ~{~a~^, ~}." name *npc-conditions*))
                  (unless (<= 0 percent 100)
                    (fail line NIL "A condition's chance is a percent, 0 to 100, not ~a." percent))
                  (list name (round percent)))))

(defun conditions-name (conditions)
  "CONDITIONS as they stand in an empty's name: thriving+sacked50, or all for none."
  (if conditions
      (format NIL "~{~a~^+~}" (loop for (name percent) in conditions
                                     collect (if (= percent 100) name (format NIL "~a~d" name percent))))
      "all"))

(defun parse-action (words line)
  (destructuring-bind (op &rest args) words
    (flet ((arg (n) (or (nth n args) (fail line NIL "~a needs more arguments." op))))
      (cond ((string-equal op "wall") (list :wall (or (first args) "wall")))
            ((string-equal op "floor") (list :floor (or (first args) "floor")))
            ((string-equal op "open") (list :open))
            ((or (string-equal op "box") (string-equal op "deco"))
             (list (if (string-equal op "box") :box :deco)
                   (parse-height (arg 0) line) (parse-height (arg 1) line) (or (third args) "wall")))
            ((string-equal op "door")
             (let ((kind (or (first args) "door")))
               (unless (assoc kind *connector-kinds* :test #'string-equal)
                 (fail line NIL "No doorway kind ~s; there are ~{~a~^, ~}." kind (mapcar #'first *connector-kinds*)))
               (list :door (string-downcase kind))))
            ((string-equal op "stairs")
             (list :stairs (parse-direction (arg 0) line) (parse-number (arg 1) line)
                   (parse-number (arg 2) line) (or (fourth args) "stair")))
            ((string-equal op "lava")
             (list :lava (if args (parse-number (first args) line) *lava-depth*)
                   (if (second args) (parse-number (second args) line) *lava-surface*)))
            ((string-equal op "water")
             ;; water [Y]: to Y above the storey's floor, TOP, or by default *WATER-SURFACE*
             ;; under the next storey's floor.
             (list :water (and args (parse-height (first args) line))))
            ((string-equal op "diagonal")
             ;; diagonal DIR [material] [Y0 Y1] [SIDE], in any order after DIR.
             (let ((dir (arg 0)) (material "wall") (heights ()) (side NIL))
               (unless (member dir '("/" "\\") :test #'string=)
                 (fail line NIL "diagonal takes / or \\, got ~s." dir))
               (dolist (word (rest args))
                 (cond ((member word '("ne" "nw" "se" "sw") :test #'string-equal)
                        (setf side (intern (string-upcase word) :keyword)))
                       ((or (string-equal word "top") (find-if #'digit-char-p word))
                        (push (parse-height word line) heights))
                       (T (setf material word))))
               (unless (member (length heights) '(0 2))
                 (fail line NIL "diagonal takes both heights, Y0 and Y1, or neither."))
               (when (and side (not (member side (if (string= dir "/") '(:nw :se) '(:ne :sw)))))
                 (fail line NIL "A ~a diagonal is solid on its ~a side or its ~a side, not ~(~a~)." dir
                       (if (string= dir "/") "nw" "ne") (if (string= dir "/") "se" "sw") side))
               (setf heights (nreverse heights))
               (list :diagonal material (char dir 0) (first heights) (second heights) side)))
            ((string-equal op "pit")
             (let ((depth (if args (parse-number (first args) line) *lava-depth*)))
               ;; The pit's floor is what is left of the slab.
               (unless (< 0 depth *border*)
                 (fail line NIL "A pit is more than 0 and less than ~a m deep, the floor slab." *border*))
               (list :pit depth)))
            ((string-equal op "torch")
             (list :torch (if args (parse-number (first args) line) *torch-height*)))
            ((string-equal op "spawn")
             ;; spawn MONSTER [FACING] [SKIP] [when:COND|COND]
             (let* ((when (find-if (lambda (w) (and (< 5 (length w)) (string-equal "when:" w :end2 5))) args))
                    (args (remove when args))
                    (skip (if (third args) (parse-number (third args) line) 0)))
               (unless (<= 0 skip 100)
                 (fail line NIL "A spawn's chance of no monster is a percent, 0 to 100, not ~a." skip))
               (list :spawn (string-downcase (arg 0))
                     (if (second args) (parse-direction (second args) line) :south)
                     (round skip)
                     (when when (parse-conditions (uiop:split-string (subseq when 5) :separator "|") line)))))
            ((string-equal op "npc")
             ;; npc ROLE [FACING] [COND[:PCT] ...]: a townsperson (townsfolk.lisp), only under
             ;; those conditions of the settlement, each with a percent chance of being there.
             (let ((facing (if (second args) (parse-direction (second args) line) :south)))
               (list :npc (string-downcase (arg 0)) facing (parse-conditions (cddr args) line))))
            ((string-equal op "zone") (list :zone (string-downcase (arg 0))))
            ((string-equal op "arrive") (list :arrive))
            ((string-equal op "pickup")
             (let ((tier (or (first args) "floor")))
               (unless (member tier '("floor" "reward") :test #'string-equal)
                 (fail line NIL "A pickup spot is floor or reward, not ~s." tier))
               (list :pickup (string-downcase tier))))
            ((string-equal op "exit") (list :exit))
            ((string-equal op "altar") (list :altar))
            (T (fail line NIL "Unknown action ~s." op))))))

(defun parse-legend-line (blueprint string line)
  (let* ((trimmed (string-left-trim '(#\Space #\Tab) string))
         (char (char trimmed 0))
         (rest (strip-comment (subseq trimmed 1))))
    (unless (or (= 1 (length trimmed)) (member (char trimmed 1) '(#\Space #\Tab)))
      (fail line NIL "A legend line is one character, a space, then its actions."))
    (let ((actions (loop for part in (let ((parts ()) (start 0))
                                       (loop for comma = (position #\, rest :start start)
                                             do (push (subseq rest start comma) parts)
                                             while comma do (setf start (1+ comma)))
                                       (nreverse parts))
                         for ws = (words part)
                         when ws collect (parse-action ws line))))
      (unless actions (fail line NIL "~s has no actions." (string char)))
      (setf (gethash char (legend blueprint)) (cons line actions)))))

(defun parse-header (blueprint key args line)
  (flet ((need (n) (unless (= n (length args)) (fail line NIL "~a takes ~d argument~:p." key n))))
    (cond ((string-equal key "cells") (need 2)
           (setf (cells blueprint) (mapcar (lambda (w) (parse-count w line)) args)))
          ((string-equal key "storeys") (need 1) (setf (storeys blueprint) (parse-count (first args) line)))
          ((string-equal key "ceiling") (need 1) (setf (ceiling-height blueprint) (parse-number (first args) line)))
          ((string-equal key "tags") (setf (tags blueprint) (mapcar #'string-downcase args)))
          ((string-equal key "weight") (need 1) (setf (weight blueprint) (parse-number (first args) line)))
          ((string-equal key "material") (need 4)
           (let ((name (string-downcase (first args))))
             (setf (materials blueprint)
                   (cons (cons name (mapcar (lambda (w) (parse-number w line)) (rest args)))
                         (remove name (materials blueprint) :key #'first :test #'string=)))))
          ((string-equal key "remap") (need 2)
           (let ((from (string-downcase (first args))))
             (when (member from '("lava" "water") :test #'string=)
               (fail line NIL "~a can't be remapped: its boxes are the liquid." from))
             (setf (remaps blueprint)
                   (acons from (string-downcase (second args)) (remove from (remaps blueprint) :key #'car :test #'string=)))))
          ((string-equal key "grid") (need 1) (setf (grid-free blueprint) (string-equal (first args) "free")))
          ((string-equal key "mirror") (need 1) (setf (mirror blueprint) (string-equal (first args) "yes")))
          (T (fail line NIL "Unknown keyword ~s." key)))))

(defun read-lines (path)
  (with-open-file (s path :external-format :utf-8)
    (coerce (loop for l = (read-line s NIL) while l
                  collect (string-right-trim '(#\Space #\Tab #\Return) l))
            'vector)))

(defun read-blueprint (path)
  "Read and check the blueprint at PATH."
  (let* ((*file* path)
         (blueprint (make-instance 'blueprint :name (pathname-name path) :path path))
         (lines (read-lines path))
         (n (length lines))
         (i 0))
    (flet ((indented-p (l) (and (plusp (length l)) (member (char l 0) '(#\Space #\Tab)))))
      (loop while (< i n)
            do (let ((raw (aref lines i)) (line (1+ i)))
                 (incf i)
                 (cond ((or (blank-p raw) (char= #\; (char (string-left-trim '(#\Space #\Tab) raw) 0))))
                       ((indented-p raw) (fail line 1 "An indented line outside a legend."))
                       (T
                        (destructuring-bind (key &rest args) (words (strip-comment raw))
                          (cond ((string-equal key "legend")
                                 (loop while (and (< i n) (indented-p (aref lines i)))
                                       do (let ((l (aref lines i)))
                                            (unless (or (blank-p l) (char= #\; (char (string-left-trim '(#\Space #\Tab) l) 0)))
                                              (parse-legend-line blueprint l (1+ i))))
                                          (incf i)))
                                ((string-equal key "plan")
                                 (unless (= 1 (length args)) (fail line NIL "plan takes the storey's number."))
                                 (let ((storey (round (parse-number (first args) line)))
                                       (start (1+ i)))
                                   (when (find storey (plans blueprint) :key #'storey)
                                     (fail line NIL "A second plan for storey ~d." storey))
                                   (let ((rows (loop while (and (< i n) (not (blank-p (aref lines i))))
                                                     collect (aref lines i) do (incf i))))
                                     (when (null rows) (fail line NIL "plan ~d has no rows." storey))
                                     (push (make-instance 'plan :storey storey :line start :rows (coerce rows 'vector))
                                           (plans blueprint)))))
                                (T (parse-header blueprint key args line)))))))))
    (setf (plans blueprint) (sort (plans blueprint) #'< :key #'storey))
    (check-blueprint blueprint)
    blueprint))

;;; Characters.

(defun char-actions (blueprint char)
  "CHAR's actions: from the legend, else built in, else NIL."
  (let ((entry (gethash char (legend blueprint))))
    (if entry
        (cdr entry)
        (case char
          (#\# '((:wall "wall")))
          (#\. '((:floor "floor")))
          (#\Space '((:open)))
          ((#\n #\e #\s #\w) '((:door "door")))
          (#\^ '((:over-door)))
          (#\T `((:torch ,*torch-height*)))
          (#\/ '((:diagonal "wall" #\/ NIL NIL NIL)))
          (#\\ '((:diagonal "wall" #\\ NIL NIL NIL)))))))

(defun side-letter (char)
  (case char (#\n :north) (#\e :east) (#\s :south) (#\w :west)))

(defun action (kind actions) (find kind actions :key #'first))

(defun remapped (blueprint material)
  "The material BLUEPRINT draws in place of MATERIAL."
  (or (cdr (assoc material (remaps blueprint) :test #'string-equal)) material))

(defun wall-like-p (actions)
  (or (action :wall actions) (action :torch actions)))

(defun connector-kind (name)
  (or (assoc name *connector-kinds* :test #'string-equal) (error "No doorway kind ~s." name)))

;;; Layout: where each row and column is, in metres from the block's origin, the
;;; centre of its floor.

(defun plan-size (blueprint)
  (let ((rows (rows (first (plans blueprint)))))
    (values (length rows) (length (aref rows 0)))))

(defun block-width (blueprint)
  (multiple-value-bind (nr nc) (plan-size blueprint) (declare (ignore nr)) (* nc 0.5)))

(defun block-depth (blueprint)
  (multiple-value-bind (nr nc) (plan-size blueprint) (declare (ignore nc)) (float (1- nr) 1f0)))

(defun col-span (blueprint c)
  (let ((x (+ (/ (block-width blueprint) -2) (* c 0.5))))
    (values x (+ x 0.5))))

(defun row-span (blueprint r)
  (let* ((nr (plan-size blueprint))
         (z (/ (block-depth blueprint) -2)))
    (cond ((= r 0) (values z (+ z *border*)))
          ((= r (1- nr)) (values (- (- z) *border*) (- z)))
          (T (let ((z0 (+ z *border* (- r 1)))) (values z0 (+ z0 1)))))))

(defun storey-base (k) (* k *storey-height*))

(defun under-canal-channel-p (blueprint k r c)
  "True if cell R C of storey K lies under the open channel of a canal's doorway."
  (let ((above (find (1+ k) (plans blueprint) :key #'storey)))
    (and above
         (let* ((actions (char-actions blueprint (char (aref (rows above) r) c)))
                (door (action :door actions)))
           (and (action :open actions) door (string= (second door) "canal"))))))

(defun storey-top (blueprint k)
  "How high storey K's walls go: the next storey's floor, or the ceiling for the top one."
  (if (= k (1- (storeys blueprint)))
      (+ (storey-base k) (ceiling-height blueprint))
      (storey-base (1+ k))))

(defun door-top-under (blueprint k r c)
  "How high above storey K's floor the doorway under cell R C reaches, going down through
the ^ cells between; NIL if there is no doorway under it."
  (loop for j from (1- k) downto 0
        for actions = (char-actions blueprint (char (aref (rows (find j (plans blueprint) :key #'storey)) r) c))
        for door = (action :door actions)
        do (cond (door (return (- (+ (storey-base j) (third (connector-kind (second door)))) (storey-base k))))
                 ((not (action :over-door actions)) (return NIL)))))

;;; Checks.

(defun check-blueprint (blueprint)
  (let ((plans (plans blueprint)))
    (when (null plans) (fail NIL NIL "No plans."))
    (unless (equal (mapcar #'storey plans) (loop for k below (storeys blueprint) collect k))
      (fail NIL NIL "storeys is ~d, so it needs plans 0 to ~:*~d, one each; it has ~{~d~^, ~}."
            (storeys blueprint) (1- (storeys blueprint)) (mapcar #'storey plans)))
    (unless (or (cells blueprint) (grid-free blueprint))
      (fail NIL NIL "No cells line (or grid free)."))
    (let ((nr (length (rows (first plans))))
          (nc (length (aref (rows (first plans)) 0))))
      (dolist (plan plans)
        (unless (= nr (length (rows plan)))
          (fail (line plan) NIL "plan ~d has ~d rows; plan ~d has ~d." (storey plan) (length (rows plan))
                (storey (first plans)) nr))
        (loop for row across (rows plan) for line from (line plan)
              do (unless (= nc (length row))
                   (fail line (1+ (min nc (length row))) "This row is ~d long; the plan's first is ~d." (length row) nc))))
      (when (or (< nr 3) (< nc 3)) (fail (line (first plans)) NIL "A plan needs at least 3 rows and 3 columns."))
      (unless (grid-free blueprint)
        (destructuring-bind (w d) (cells blueprint)
          (unless (and (= nc (* w 8)) (= nr (1+ (* d 4))))
            (fail (line (first plans)) NIL "cells ~d ~d needs plans ~d wide and ~d rows tall; this one is ~d by ~d."
                  w d (* w 8) (1+ (* d 4)) nc nr))))
      ;; Materials named in the legend.
      (maphash (lambda (char entry)
                 (declare (ignore char))
                 (dolist (a (cdr entry))
                   (let ((material (case (first a) ((:box :deco) (fourth a)) (:stairs (fifth a)) ((:wall :diagonal :floor) (second a)))))
                     (when (and material (not (assoc material (materials blueprint) :test #'string-equal)))
                       (fail (car entry) NIL "No material ~s; add a material line." material)))))
               (legend blueprint))
      (loop for (from . to) in (remaps blueprint)
            unless (assoc to (materials blueprint) :test #'string-equal)
              do (fail NIL NIL "remap ~a ~a: no material ~s; add a material line." from to to))
      (dolist (plan plans)
        (loop for row across (rows plan) for r from 0 for line from (line plan)
              do (loop for char across row for c from 0
                       for actions = (char-actions blueprint char)
                       for border = (or (= r 0) (= c 0) (= r (1- nr)) (= c (1- nc)))
                       for corner = (and (or (= r 0) (= r (1- nr))) (or (= c 0) (= c (1- nc))))
                       do (cond ((null actions) (fail line (1+ c) "Unknown character ~s; give it a legend line." (string char)))
                                ((and corner (not (wall-like-p actions)) )
                                 (fail line (1+ c) "A corner must be wall."))
                                ((and corner (action :torch actions))
                                 (fail line (1+ c) "A torch can't stand in a corner."))
                                ;; Under a canal's doorway its water runs on through the wall.
                                ((and border (action :water actions) (under-canal-channel-p blueprint (storey plan) r c)))
                                ((and border (not (or (wall-like-p actions) (action :door actions) (action :over-door actions))))
                                 (fail line (1+ c) "The border must be wall, torch or doorway, not ~s." (string char)))
                                ((and (not border) (action :door actions))
                                 (fail line (1+ c) "A doorway must be on the border.")))
                          ;; A doorway taller than its storey runs on up through the plans above.
                          (when (action :over-door actions)
                            (unless (< 1e-3 (or (door-top-under blueprint (storey plan) r c) 0))
                              (fail line (1+ c) "^ goes on up a doorway, but none reaches this storey from below.")))
                          (let ((door (action :door actions)))
                            (when door
                              (let ((top (+ (storey-base (storey plan)) (third (connector-kind (second door))))))
                                (when (< (+ (storey-top blueprint (1- (storeys blueprint))) 1e-3) top)
                                  (fail line (1+ c) "A ~a doorway reaches ~,1f m, over this block's ceiling." (second door) top))
                                (dolist (above plans)
                                  (when (and (< (storey plan) (storey above))
                                             (< (+ (storey-base (storey above)) 1e-3) top)
                                             (not (action :over-door (char-actions blueprint (char (aref (rows above) r) c)))))
                                    (fail (+ (line above) r) (1+ c) "A ~a doorway reaches ~,1f m: draw ^ here, over it." (second door) top))))))))))))

;;; Geometry. A box is (name material solid x0 y0 z0 x1 y1 z1); an empty is
;;; (name (x y z) rotation), the rotation a quaternion (x y z w) or NIL.

(defun merge-rectangles (grid)
  "The rectangles (r0 c0 r1 c1) that cover GRID's true cells, greedily. Clears GRID."
  (let ((nr (array-dimension grid 0)) (nc (array-dimension grid 1)) (out ()))
    (dotimes (r nr (nreverse out))
      (dotimes (c nc)
        (when (aref grid r c)
          (let ((c1 c) (r1 r))
            (loop while (and (< (1+ c1) nc) (aref grid r (1+ c1))) do (incf c1))
            (loop while (and (< (1+ r1) nr) (loop for cc from c to c1 always (aref grid (1+ r1) cc)))
                  do (incf r1))
            (loop for rr from r to r1 do (loop for cc from c to c1 do (setf (aref grid rr cc) NIL)))
            (push (list r c r1 c1) out)))))))

(defun region (rows r c)
  "The cells (r c) joined to R C by the same character, side by side."
  (let ((char (char (aref rows r) c)) (seen (make-hash-table :test 'equal)) (todo (list (list r c))) (out ()))
    (loop while todo
          do (destructuring-bind (rr cc) (pop todo)
               (when (and (< -1 rr (length rows)) (< -1 cc (length (aref rows rr)))
                          (char= char (char (aref rows rr) cc))
                          (not (gethash (list rr cc) seen)))
                 (setf (gethash (list rr cc) seen) T)
                 (push (list rr cc) out)
                 (push (list (1+ rr) cc) todo) (push (list (1- rr) cc) todo)
                 (push (list rr (1+ cc)) todo) (push (list rr (1- cc)) todo))))
    out))

(defun region-bounds (cells)
  (values (reduce #'min cells :key #'first) (reduce #'min cells :key #'second)
          (reduce #'max cells :key #'first) (reduce #'max cells :key #'second)))

(defun facing-rotation (facing)
  "The quaternion that turns -Z to FACING about +Y."
  (let ((h (sqrt 0.5)))
    (ecase facing
      (:north NIL)
      (:south (list 0.0 1.0 0.0 0.0))
      (:east (list 0.0 (- h) 0.0 h))
      (:west (list 0.0 h 0.0 h)))))

(defun door-runs (blueprint plan)
  "Each doorway on PLAN's border, as a plist: :side :char :kind :start :end (cells)."
  (let* ((rows (rows plan)) (nr (length rows)) (nc (length (aref rows 0))) (runs ()))
    (flet ((scan (side cells)
             (let ((current NIL))
               (dolist (rc (append cells (list NIL)))
                 (let* ((char (and rc (char (aref rows (first rc)) (second rc))))
                        (door (and char (action :door (char-actions blueprint char)))))
                   ;; A doorway is the cells of one kind side by side, whatever their
                   ;; characters: a river's lava cells and bank cells make one.
                   (if (and current door (string-equal (second door) (getf current :kind)))
                       (setf (getf current :end) rc)
                       (progn (when current (push current runs))
                              (setf current (and door (list :side side :char char :kind (second door)
                                                            :start rc :end rc))))))))))
      (scan :north (loop for c from 1 below (1- nc) collect (list 0 c)))
      (scan :south (loop for c from 1 below (1- nc) collect (list (1- nr) c)))
      (scan :west (loop for r from 1 below (1- nr) collect (list r 0)))
      (scan :east (loop for r from 1 below (1- nr) collect (list r (1- nc)))))
    (nreverse runs)))

(defun near (a b) (< (abs (- a b)) 1e-3))

(defun border-wall (blueprint rows r c)
  "The material of the border wall nearest the doorway cell R C, along its side: what its
lintel and plug are drawn in, so an ice doorway in ice-rock is shut with ice-rock."
  (let* ((nr (length rows)) (nc (length (aref rows 0)))
         (ns (or (= r 0) (= r (1- nr)))))
    (loop for d from 1 below (max nr nc)
          do (dolist (s '(-1 1))
               (let ((rr (if ns r (+ r (* s d)))) (cc (if ns (+ c (* s d)) c)))
                 (when (and (< -1 rr nr) (< -1 cc nc))
                   (let ((wall (action :wall (char-actions blueprint (char (aref rows rr) cc)))))
                     (when wall (return-from border-wall (second wall))))))))
    "wall"))

(defun slab-cell-p (blueprint k r c)
  "True if cell R C of storey K has a floor slab: everything but open cells and walls."
  (let ((plan (find k (plans blueprint) :key #'storey)))
    (when plan
      (let* ((rows (rows plan))
             (actions (char-actions blueprint (char (aref rows r) c)))
             (border (or (= r 0) (= c 0) (= r (1- (length rows))) (= c (1- (length (aref rows 0)))))))
        (not (or (action :open actions) (action :wall actions) (action :over-door actions)
                 (and border (action :torch actions))))))))

(defun diagonal-extent (blueprint k actions)
  "The heights above storey K's floor that the diagonal in ACTIONS runs between: its own,
or from the cell's floor (a pit's, lava's, or an open cell's slab bottom) to the top."
  (let ((diagonal (action :diagonal actions))
        (pit (or (action :lava actions) (action :pit actions)))
        (top (- (storey-top blueprint k) (storey-base k))))
    (flet ((height (h) (if (eq h :top) top h)))
      (if (fourth diagonal)
          (values (height (fourth diagonal)) (height (fifth diagonal)))
          (values (cond (pit (- (second pit))) ((action :open actions) (- *border*)) (T 0.0))
                  top)))))

(defun cell-covers-p (blueprint k r c y0 y1)
  "True if cell R C of storey K is solid all the way from Y0 to Y1 above the storey's floor:
its wall, floor slab, boxes and door lintel together. A diagonal doesn't count."
  (let* ((plan (find k (plans blueprint) :key #'storey))
         (rows (rows plan))
         (actions (char-actions blueprint (char (aref rows r) c)))
         (border (or (= r 0) (= c 0) (= r (1- (length rows))) (= c (1- (length (aref rows 0))))))
         (top (- (storey-top blueprint k) (storey-base k)))
         (spans ()))
    (flet ((height (h) (if (eq h :top) top h)))
      (when (or (action :wall actions) (and border (action :torch actions)))
        (push (cons (- *border*) top) spans))
      (when (slab-cell-p blueprint k r c)
        (let ((pit (or (action :lava actions) (action :pit actions))))
          (push (cons (- *border*) (if pit (- (second pit)) 0.0)) spans)))
      (dolist (a actions)
        (case (first a)
          (:box (push (cons (height (second a)) (height (third a))) spans))
          (:door (push (cons (third (connector-kind (second a))) top) spans))
          (:over-door (push (cons (door-top-under blueprint k r c) top) spans)))))
    ;; Covered if the spans, end to end, leave no gap from Y0 to Y1.
    (let ((reach y0))
      (dolist (span (sort spans #'< :key #'car))
        (when (<= (car span) (+ reach 1e-3))
          (setf reach (max reach (cdr span)))))
      (<= (- y1 1e-3) reach))))

(defun blueprint-geometry (blueprint)
  "The boxes, empties and scene extras of BLUEPRINT's block."
  (let* ((*file* (path blueprint))
         (boxes ()) (empties ()) (doors ()) (counts (make-hash-table :test 'equal))
         (w (block-width blueprint)) (d (block-depth blueprint)))
    (multiple-value-bind (nr nc) (plan-size blueprint)
      (labels ((box (prefix material solid x0 y0 z0 x1 y1 z1)
                 (let* ((material (remapped blueprint material))
                        (name (format NIL "~a~a_~d" prefix material (incf (gethash (list prefix material) counts 0)))))
                   (push (list name material solid x0 y0 z0 x1 y1 z1) boxes)))
               (wedge (material cut x0 y0 z0 x1 y1 z1)
                 ;; A wedge is a box with a corner cut: wedge_<cut>_..., its cut the
                 ;; corner's number (1 north-east, 2 north-west, 3 south-west, 4 south-east).
                 (let ((name (format NIL "wedge_~d_~a_~d" cut material (incf (gethash (list "wedge" material) counts 0)))))
                   (push (list name material T x0 y0 z0 x1 y1 z1 cut) boxes)))
               (cell-centre (r c)
                 (multiple-value-bind (x0 x1) (col-span blueprint c)
                   (multiple-value-bind (z0 z1) (row-span blueprint r)
                     (values (/ (+ x0 x1) 2) (/ (+ z0 z1) 2))))))
        (dolist (plan (plans blueprint))
          (let* ((k (storey plan)) (base (storey-base k)) (top (storey-top blueprint k))
                 (rows (rows plan))
                 (spans (make-hash-table :test 'equal))) ; (y0 y1 material solid) -> grid
            (flet ((span (r c y0 y1 material solid)
                     (when (< (+ y0 1e-4) y1)
                       (let ((grid (or (gethash (list y0 y1 material solid) spans)
                                       (setf (gethash (list y0 y1 material solid) spans)
                                             (make-array (list nr nc) :initial-element NIL)))))
                         (setf (aref grid r c) T))))
                   (height (h) (if (eq h :top) top (+ base h))))
              ;; Columns: what stands on each cell.
              (dotimes (r nr)
                (dotimes (c nc)
                  (let* ((actions (char-actions blueprint (char (aref rows r) c)))
                         (border (or (= r 0) (= c 0) (= r (1- nr)) (= c (1- nc))))
                         ;; A wall stands on the wall below it, or on storey 0 reaches
                         ;; down through the floor slab: a slab under it would put a
                         ;; face in the wall's plane, and the two would flicker.
                         (wall-bottom (if (= k 0) (- base *border*) base))
                         ;; Under a floor slab in the storey above, whatever reaches the
                         ;; top stops below the slab, so the floor shows its own colour
                         ;; and no two top faces share a plane.
                         (cap (if (slab-cell-p blueprint (1+ k) r c) (- top *border*) top)))
                    (when (slab-cell-p blueprint k r c)
                      ;; In a pit the slab is the pit's floor, and lava may fill it.
                      (let* ((lava (action :lava actions))
                             (pit (or lava (action :pit actions))))
                        (span r c (- base *border*) (if pit (- base (second pit)) base)
                              (or (second (action :floor actions)) "floor") T)
                        (when lava
                          (span r c (- base (second lava)) (- base (third lava)) "lava" :liquid))))
                    ;; Deep water stands on the cell's floor, up to its height, and never
                    ;; above the slab over it or a doorway's lintel: a flooded cell.
                    (let ((water (action :water actions)) (door (action :door actions)))
                      (when water
                        (span r c base
                              (min cap
                                   (if door (+ base (third (connector-kind (second door)))) top)
                                   (case (second water)
                                     ((NIL) (- top *water-surface*))
                                     (:top top)
                                     (T (+ base (second water)))))
                              "water" :liquid)))
                    (dolist (a actions)
                      (case (first a)
                        (:wall (span r c wall-bottom cap (second a) T))
                        (:box (span r c (height (second a)) (min cap (height (third a))) (fourth a) T))
                        (:deco (span r c (height (second a)) (height (third a)) (fourth a) NIL))
                        (:door (span r c (+ base (third (connector-kind (second a)))) cap
                                     (border-wall blueprint rows r c) T))
                        (:over-door (span r c (+ base (door-top-under blueprint k r c)) cap
                                          (border-wall blueprint rows r c) T))))
                    (when (and border (action :torch actions) (not (action :wall actions)))
                      (span r c wall-bottom cap "wall" T)))))
              (maphash (lambda (key grid)
                         (destructuring-bind (y0 y1 material solid) key
                           (loop for (r0 c0 r1 c1) in (merge-rectangles grid)
                                 do (box (if solid "" "deco_") material (eq solid T)
                                         (col-span blueprint c0) y0 (row-span blueprint r0)
                                         (nth-value 1 (col-span blueprint c1)) y1
                                         (nth-value 1 (row-span blueprint r1))))))
                       spans)
              ;; Stairs, spawns, pickup spots, exits, altars and torches, one per region or cell.
              (let ((done (make-hash-table :test 'equal)))
                (dotimes (r nr)
                  (dotimes (c nc)
                    (let* ((char (char (aref rows r) c))
                           (actions (char-actions blueprint char))
                           (stairs (action :stairs actions))
                           (spawn (action :spawn actions))
                           (pickup (action :pickup actions))
                           (exit (action :exit actions))
                           (npc (action :npc actions))
                           (zone (action :zone actions))
                           (arrive (action :arrive actions))
                           (altar (action :altar actions))
                           (torch (action :torch actions)))
                      (when (and (or stairs spawn pickup exit npc zone arrive altar) (not (gethash (list r c) done)))
                        (let ((cells (region rows r c)))
                          (dolist (cell cells) (setf (gethash cell done) T))
                          (multiple-value-bind (r0 c0 r1 c1) (region-bounds cells)
                            (let ((x0 (col-span blueprint c0)) (x1 (nth-value 1 (col-span blueprint c1)))
                                  (z0 (row-span blueprint r0)) (z1 (nth-value 1 (row-span blueprint r1))))
                              (when stairs
                                (unless (= (length cells) (* (1+ (- r1 r0)) (1+ (- c1 c0))))
                                  (fail (+ (line plan) r) (1+ c) "The stairs drawn with ~s aren't a rectangle." (string char)))
                                (when (or (= r0 0) (= c0 0) (= r1 (1- nr)) (= c1 (1- nc)))
                                  (fail (+ (line plan) r) (1+ c) "Stairs can't be on the border."))
                                (destructuring-bind (dir from to material) (rest stairs)
                                  (let* ((n (max 1 (ceiling (- (abs (- to from)) 1e-4) *max-riser*)))
                                         (length (if (member dir '(:north :south)) (- z1 z0) (- x1 x0)))
                                         (tread (/ length n)))
                                    (loop for i from 1 to n
                                          for h = (+ base from (* (- to from) (/ i n)))
                                          do (ecase dir
                                               (:north (box "" material T x0 base (- z1 (* i tread)) x1 h (- z1 (* (1- i) tread))))
                                               (:south (box "" material T x0 base (+ z0 (* (1- i) tread)) x1 h (+ z0 (* i tread))))
                                               (:east (box "" material T (+ x0 (* (1- i) tread)) base z0 (+ x0 (* i tread)) h z1))
                                               (:west (box "" material T (- x1 (* i tread)) base z0 (- x1 (* (1- i) tread)) h z1)))))))
                              (when spawn
                                (let ((y (reduce #'max (remove :box actions :key #'first :test-not #'eq)
                                                 :key (lambda (a) (height (third a))) :initial-value base)))
                                  (push (list (format NIL "spawn_~:[~*~;when-~a_~]~:[~*~;skip~d_~]~a"
                                                      (fifth spawn) (conditions-name (fifth spawn))
                                                      (plusp (fourth spawn)) (fourth spawn)
                                                      (second spawn))
                                              (list (/ (+ x0 x1) 2) y (/ (+ z0 z1) 2))
                                              (facing-rotation (third spawn)))
                                        empties)))
                              (when pickup
                                ;; On top of any box in the cell, or down in its pit.
                                (let* ((pit (action :pit actions))
                                       (y (reduce #'max (remove :box actions :key #'first :test-not #'eq)
                                                  :key (lambda (a) (height (third a)))
                                                  :initial-value (if pit (- base (second pit)) base))))
                                  (push (list (format NIL "pickup_~a_~d" (second pickup) (incf (gethash "pickup" counts 0)))
                                              (list (/ (+ x0 x1) 2) y (/ (+ z0 z1) 2)) NIL)
                                        empties)))
                              (when exit
                                (push (list (format NIL "exit_~d" (incf (gethash "exit" counts 0)))
                                            (list (/ (+ x0 x1) 2) base (/ (+ z0 z1) 2)) NIL)
                                      empties))
                              (when arrive
                                (push (list (format NIL "arrive_~d" (incf (gethash "arrive" counts 0)))
                                            (list (/ (+ x0 x1) 2) base (/ (+ z0 z1) 2)) NIL)
                                      empties))
                              (when npc
                                ;; Standing on any box in the cell, as a spawn does.
                                (let ((y (reduce #'max (remove :box actions :key #'first :test-not #'eq)
                                                 :key (lambda (a) (height (third a))) :initial-value base)))
                                  (push (list (format NIL "npc_~a_~a" (conditions-name (fourth npc)) (second npc))
                                              (list (/ (+ x0 x1) 2) y (/ (+ z0 z1) 2))
                                              (facing-rotation (third npc)))
                                        empties)))
                              (when zone
                                ;; The region's bounding box, the storey's height, as two corners.
                                (let ((n (incf (gethash "zone" counts 0))))
                                  (push (list (format NIL "zone_~a_~d_lo" (second zone) n) (list x0 base z0) NIL) empties)
                                  (push (list (format NIL "zone_~a_~d_hi" (second zone) n)
                                              (list x1 (+ base *storey-height*) z1) NIL)
                                        empties)))
                              (when altar
                                ;; On top of the box it stands on, if any: the spellforge's (forge.lisp).
                                (let ((y (reduce #'max (remove :box actions :key #'first :test-not #'eq)
                                                 :key (lambda (a) (height (third a))) :initial-value base)))
                                  (push (list (format NIL "altar_~d" (incf (gethash "altar" counts 0)))
                                              (list (/ (+ x0 x1) 2) y (/ (+ z0 z1) 2)) NIL)
                                        empties)))))))
                      (when torch
                        (multiple-value-bind (x z) (cell-centre r c)
                          (cond ((= r 0) (setf z (+ (nth-value 1 (row-span blueprint 0)) *torch-inset*)))
                                ((= r (1- nr)) (setf z (- (row-span blueprint r) *torch-inset*)))
                                ((= c 0) (setf x (+ (nth-value 1 (col-span blueprint 0)) *torch-inset*)))
                                ((= c (1- nc)) (setf x (- (col-span blueprint c) *torch-inset*))))
                          (push (list (format NIL "torch_~d" (incf (gethash "torch" counts 0)))
                                      (list x (+ base (second torch)) z) NIL)
                                empties))))))))
            ;; Diagonals: each pair of / or \ (or a diagonal action) is a 1 m square cut
            ;; along the diagonal it draws, solid on one side over its heights: rock to the
            ;; top, a pit's dry edge, a shelf's. The solid side is its SIDE, or the side
            ;; whose neighbours are solid over the same heights.
            (dotimes (r nr)
              (let ((c 0))
                (loop while (< c nc)
                      do (let* ((char (char (aref rows r) c))
                                (actions (char-actions blueprint char))
                                (diagonal (action :diagonal actions)))
                           (if (not diagonal)
                               (incf c)
                               (let ((line (+ (line plan) r)))
                                 (unless (and (< (1+ c) nc) (char= char (char (aref rows r) (1+ c))))
                                   (fail line (1+ c) "~s draws a 1 m square, two columns wide: write it as a pair." (string char)))
                                 (multiple-value-bind (y0 y1) (diagonal-extent blueprint k actions)
                                   (flet ((solid-at (rr cc)
                                            (if (and (< -1 rr nr) (< -1 cc nc))
                                                (if (cell-covers-p blueprint k rr cc y0 y1) 1 0)
                                                1)))
                                     (let* ((dir (third diagonal))
                                            (north (+ (solid-at (1- r) c) (solid-at (1- r) (1+ c))))
                                            (south (+ (solid-at (1+ r) c) (solid-at (1+ r) (1+ c))))
                                            (west (solid-at r (1- c)))
                                            (east (solid-at r (+ c 2)))
                                            ;; / runs south-west to north-east, \ north-west to south-east.
                                            (a (if (char= dir #\/) (+ north west) (+ north east)))
                                            (b (if (char= dir #\/) (+ south east) (+ south west)))
                                            ;; The cut corner is on the side away from the solid half.
                                            (cut (case (sixth diagonal)
                                                   (:ne 3) (:nw 4) (:se 2) (:sw 1)
                                                   (T (cond ((= a b)
                                                             (fail line (1+ c) "Can't tell which side of ~s is solid: put solid beside one side only, or give it a side." (string char)))
                                                            ((char= dir #\/) (if (< b a) 4 2))
                                                            (T (if (< b a) 3 1)))))))
                                       (multiple-value-bind (x0) (col-span blueprint c)
                                         (multiple-value-bind (z0 z1) (row-span blueprint r)
                                           (let ((x1 (nth-value 1 (col-span blueprint (1+ c))))
                                                 (cap (if (slab-cell-p blueprint (1+ k) r c) (- top *border*) top)))
                                             (wedge (remapped blueprint (second diagonal)) cut
                                                    x0 (+ base y0) z0 x1 (min cap (+ base y1)) z1)))))))
                                 (incf c 2)))))))
            ;; Doorways: a connector on the outer face and a plug filling the hole.
            (dolist (run (door-runs blueprint plan))
              (destructuring-bind (&key side char kind start end) run
                (let* ((line (+ (line plan) (first start))) (column (1+ (second start)))
                       (letter (side-letter char))
                       (spec (connector-kind kind))
                       (ns (member side '(:north :south)))
                       (lo (if ns (col-span blueprint (second start)) (row-span blueprint (first start))))
                       (hi (if ns (nth-value 1 (col-span blueprint (second end))) (nth-value 1 (row-span blueprint (first end)))))
                       (centre (/ (+ lo hi) 2))
                       (half (/ (second spec) 2)))
                  (when (and letter (not (eq letter side)))
                    (fail line column "~s is a ~(~a~) doorway, but it is on the ~(~a~) wall." (string char) letter side))
                  (unless (near (- hi lo) (second spec))
                    (fail line column "A ~a doorway is ~,1f m wide (~d ~a); this one is ~,1f m." kind (second spec)
                          (if ns (round (second spec) 0.5) (round (second spec))) (if ns "columns" "rows") (- hi lo)))
                  ;; One cell wide, it is centred on a cell's middle; two, on the boundary.
                  (unless (or (grid-free blueprint)
                              (let ((off (mod (+ centre (/ (if ns w d) 2)) *cell-size*)))
                                (if (oddp (round (+ (second spec) 1) *cell-size*))
                                    (near off (/ *cell-size* 2))
                                    (or (near off 0) (near off *cell-size*)))))
                    (fail line column "This doorway isn't centred on a cell's edge~:[~; (a ~a doorway spans two cells: centre it on the boundary between them)~]."
                          (< *cell-size* (second spec)) kind))
                  ;; A river's lava runs down its middle, LAVA wide, the rest is bank (none
                  ;; when it is the doorway's width), so every doorway of a kind meets every other.
                  ;; A canal's middle is open, down to its water in the storey below.
                  (when (fourth spec)
                    (loop for i from (if ns (second start) (first start)) to (if ns (second end) (first end))
                          for rc = (if ns (list (first start) i) (list i (second start)))
                          for mid = (/ (+ (if ns (col-span blueprint i) (row-span blueprint i))
                                          (nth-value 1 (if ns (col-span blueprint i) (row-span blueprint i))))
                                       2)
                          for actions = (char-actions blueprint (char (aref rows (first rc)) (second rc)))
                          for lava = (or (action :lava actions) (action :open actions))
                          for what = (if (string= kind "canal") "open channel" "lava")
                          do (unless (eq (not lava) (not (< (abs (- mid centre)) (/ (fourth spec) 2))))
                               (fail (+ (line plan) (first rc)) (1+ (second rc))
                                     "~:[A ~a doorway has ~a m of ~a down its middle and bank on each side~;A ~a doorway is all ~*~a~]; this cell should be ~:[bank~;~a~]."
                                     (<= (second spec) (fourth spec)) kind (fourth spec) what (not lava) what))))
                  (push (list :storey k :side side :kind kind :along centre
                              :wall (border-wall blueprint rows (first start) (second start))
                              :position (ecase side
                                          (:north (list centre base (/ d -2)))
                                          (:south (list centre base (/ d 2)))
                                          (:west (list (/ w -2) base centre))
                                          (:east (list (/ w 2) base centre)))
                              :plug (let ((y1 (+ base (third spec))))
                                      (ecase side
                                        (:north (list (- centre half) base (/ d -2) (+ centre half) y1 (+ (/ d -2) *border*)))
                                        (:south (list (- centre half) base (- (/ d 2) *border*) (+ centre half) y1 (/ d 2)))
                                        (:west (list (/ w -2) base (- centre half) (+ (/ w -2) *border*) y1 (+ centre half)))
                                        (:east (list (- (/ w 2) *border*) base (- centre half) (/ w 2) y1 (+ centre half)))))
                              ;; Under a river's lava the floor is sunk, so its plug goes down
                              ;; to the pit's floor there, or the lava shows beneath it. Under a
                              ;; canal's open channel, down a storey to the water's bottom.
                              :lava-plug (when (fourth spec)
                                           (let* ((depth (if (string= kind "canal")
                                                             *storey-height*
                                                             (or (loop for i from (if ns (second start) (first start))
                                                                         to (if ns (second end) (first end))
                                                                       for ch = (if ns (char (aref rows (first start)) i) (char (aref rows i) (second start)))
                                                                       thereis (second (action :lava (char-actions blueprint ch))))
                                                                 *lava-depth*)))
                                                  (y0 (- base depth)) (lh (/ (fourth spec) 2)))
                                             (ecase side
                                               (:north (list (- centre lh) y0 (/ d -2) (+ centre lh) base (+ (/ d -2) *border*)))
                                               (:south (list (- centre lh) y0 (- (/ d 2) *border*) (+ centre lh) base (/ d 2)))
                                               (:west (list (/ w -2) y0 (- centre lh) (+ (/ w -2) *border*) base (+ centre lh)))
                                               (:east (list (- (/ w 2) *border*) y0 (- centre lh) (/ w 2) base (+ centre lh)))))))
                        doors))))))
        ;; The ceiling over the whole block.
        (let ((top (storey-top blueprint (1- (storeys blueprint)))))
          (box "" "ceiling" T (/ w -2) top (/ d -2) (/ w 2) (+ top *border*) (/ d 2)))
        ;; Name the doorways: connector_[kind_]side, numbered from the second on a side.
        (let ((seen (make-hash-table :test 'equal)))
          (dolist (door (sort (nreverse doors) (lambda (a b) (or (< (getf a :storey) (getf b :storey))
                                                                  (and (= (getf a :storey) (getf b :storey))
                                                                       (< (getf a :along) (getf b :along)))))))
            (let* ((stem (format NIL "~:[~a_~;~*~]~(~a~)" (string= (getf door :kind) "door") (getf door :kind) (getf door :side)))
                   (n (incf (gethash stem seen 0)))
                   (suffix (if (= n 1) stem (format NIL "~a_~d" stem n))))
              (push (list (format NIL "connector_~a" suffix) (getf door :position) NIL) empties)
              (push (list* (format NIL "plug_~a" suffix) (remapped blueprint (getf door :wall)) T (getf door :plug)) boxes)
              ;; A second piece of the same plug (blocks.lisp drops the ".001").
              (when (getf door :lava-plug)
                (push (list* (format NIL "plug_~a.001" suffix) (remapped blueprint (getf door :wall)) T (getf door :lava-plug)) boxes)))))
        (values (nreverse boxes) (nreverse empties)
                (let ((extras (make-hash-table :test 'equal)))
                  (setf (gethash "tags" extras) (coerce (tags blueprint) 'vector)
                        (gethash "weight" extras) (weight blueprint)
                        (gethash "storeys" extras) (storeys blueprint))
                  (when (cells blueprint)
                    (setf (gethash "cells" extras) (coerce (cells blueprint) 'vector)))
                  extras))))))

;;; Mirroring west to east, for pieces a quarter turn can't make.

(defun mirror-char (c) (case c (#\e #\w) (#\w #\e) (#\/ #\\) (#\\ #\/) (T c)))
(defun mirror-direction (d) (case d (:east :west) (:west :east) (T d)))
(defun mirror-action (a)
  (case (first a)
    (:stairs (list* :stairs (mirror-direction (second a)) (cddr a)))
    (:spawn (list :spawn (second a) (mirror-direction (third a)) (fourth a) (fifth a)))
    (:npc (list :npc (second a) (mirror-direction (third a)) (fourth a)))
    (:diagonal (list :diagonal (second a) (if (char= (third a) #\/) #\\ #\/) (fourth a) (fifth a)
                     (case (sixth a) (:ne :nw) (:nw :ne) (:se :sw) (:sw :se))))
    (T a)))

(defun mirrored (blueprint)
  (let ((m (make-instance 'blueprint :name (format NIL "~a-mirror" (name blueprint)) :path (path blueprint))))
    (dolist (slot '(cells storeys ceiling-height tags weight grid-free materials remaps))
      (setf (slot-value m slot) (slot-value blueprint slot)))
    (maphash (lambda (char entry)
               (setf (gethash (mirror-char char) (legend m))
                     (cons (car entry) (mapcar #'mirror-action (cdr entry)))))
             (legend blueprint))
    (setf (plans m)
          (loop for plan in (plans blueprint)
                collect (make-instance 'plan :storey (storey plan) :line (line plan)
                                             :rows (map 'vector (lambda (row) (map 'string #'mirror-char (reverse row)))
                                                        (rows plan)))))
    m))

;;; Writing glTF: one box mesh per box (24 vertices, so each face has its own normal),
;;; centred on its node, which is at the box's centre; one material per colour.

(defun obj (&rest pairs)
  (let ((table (make-hash-table :test 'equal)))
    (loop for (k v) on pairs by #'cddr do (setf (gethash k table) v))
    table))

(defun octets () (make-array 0 :element-type '(unsigned-byte 8) :adjustable T :fill-pointer 0))

(defun put-u32 (v n) (dotimes (k 4) (vector-push-extend (ldb (byte 8 (* 8 k)) n) v)))
(defun put-u16 (v n) (dotimes (k 2) (vector-push-extend (ldb (byte 8 (* 8 k)) n) v)))
(defun put-f32 (v x) (put-u32 v (ldb (byte 32 0) (sb-kernel:single-float-bits (float x 1f0)))))
(defun pad4 (v &optional (byte 0)) (loop until (zerop (mod (length v) 4)) do (vector-push-extend byte v)))

(defun box-faces (sx sy sz)
  "Each face of a box with half-sizes SX SY SZ: its normal and 4 corners, counter-clockwise outside."
  `(((1 0 0) ((,sx ,(- sy) ,sz) (,sx ,(- sy) ,(- sz)) (,sx ,sy ,(- sz)) (,sx ,sy ,sz)))
    ((-1 0 0) ((,(- sx) ,(- sy) ,(- sz)) (,(- sx) ,(- sy) ,sz) (,(- sx) ,sy ,sz) (,(- sx) ,sy ,(- sz))))
    ((0 1 0) ((,(- sx) ,sy ,sz) (,sx ,sy ,sz) (,sx ,sy ,(- sz)) (,(- sx) ,sy ,(- sz))))
    ((0 -1 0) ((,(- sx) ,(- sy) ,(- sz)) (,sx ,(- sy) ,(- sz)) (,sx ,(- sy) ,sz) (,(- sx) ,(- sy) ,sz)))
    ((0 0 1) ((,(- sx) ,(- sy) ,sz) (,sx ,(- sy) ,sz) (,sx ,sy ,sz) (,(- sx) ,sy ,sz)))
    ((0 0 -1) ((,sx ,(- sy) ,(- sz)) (,(- sx) ,(- sy) ,(- sz)) (,(- sx) ,sy ,(- sz)) (,sx ,sy ,(- sz))))))

(defun wedge-faces (sx sy sz cut)
  "Each face of a box with half-sizes SX SY SZ and corner CUT cut away (1 north-east, 2
north-west, 3 south-west, 4 south-east): its normal and corners, counter-clockwise outside."
  (let* ((ring (list (list (- sx) sz 3) (list sx sz 4) (list sx (- sz) 1) (list (- sx) (- sz) 2)))
         (tri (remove cut ring :key #'third))
         (cx (/ (reduce #'+ tri :key #'first) 3)) (cz (/ (reduce #'+ tri :key #'second) 3))
         (faces (list (list '(0 1 0) (loop for (x z) in tri collect (list x sy z)))
                      (list '(0 -1 0) (loop for (x z) in (reverse tri) collect (list x (- sy) z))))))
    (loop for (p q) on (append tri (list (first tri)))
          while q
          do (destructuring-bind (px pz qx qz) (list (first p) (second p) (first q) (second q))
               ;; Outward is (-dz, dx) along P to Q, if that points away from the middle.
               (when (< (+ (* (- (- qz pz)) (- (/ (+ px qx) 2) cx)) (* (- qx px) (- (/ (+ pz qz) 2) cz))) 0)
                 (rotatef px qx) (rotatef pz qz))
               (let* ((nx (- (- qz pz))) (nz (- qx px)) (len (sqrt (+ (* nx nx) (* nz nz)))))
                 (push (list (list (/ nx len) 0 (/ nz len))
                             (list (list px (- sy) pz) (list qx (- sy) qz) (list qx sy qz) (list px sy pz)))
                       faces))))
    faces))

(defun write-glb (path blueprint boxes empties extras)
  (let ((blob (octets))
        (views ()) (accessors ()) (meshes ()) (nodes ())
        (material-names (remove-duplicates (mapcar #'second boxes) :test #'string= :from-end T)))
    (labels ((view (bytes target)
               (pad4 blob)
               (push (obj "buffer" 0 "byteOffset" (length blob) "byteLength" (length bytes) "target" target) views)
               (loop for b across bytes do (vector-push-extend b blob))
               (1- (length views)))
             (accessor (view component count type &rest more)
               (push (apply #'obj "bufferView" view "componentType" component "count" count "type" type more) accessors)
               (1- (length accessors))))
      (dolist (b boxes)
        (destructuring-bind (name material solid x0 y0 z0 x1 y1 z1 &optional cut) b
          (declare (ignore solid))
          (let ((sx (/ (- x1 x0) 2)) (sy (/ (- y1 y0) 2)) (sz (/ (- z1 z0) 2))
                (positions (octets)) (normals (octets)) (indices (octets))
                (vertices 0) (index-count 0))
            (loop for (normal corners) in (if cut (wedge-faces sx sy sz cut) (box-faces sx sy sz))
                  for n = (length corners)
                  do (dolist (p corners) (dolist (x p) (put-f32 positions x)))
                     (dotimes (k n) (dolist (x normal) (put-f32 normals x)))
                     (dolist (i (if (= n 4) '(0 1 2 0 2 3) '(0 1 2)))
                       (put-u16 indices (+ vertices i))
                       (incf index-count))
                     (incf vertices n))
            (let ((pos (accessor (view positions 34962) 5126 vertices "VEC3"
                                 "min" (vector (- sx) (- sy) (- sz)) "max" (vector sx sy sz)))
                  (nrm (accessor (view normals 34962) 5126 vertices "VEC3"))
                  (idx (accessor (view indices 34963) 5123 index-count "SCALAR")))
              (push (obj "name" name
                         "primitives" (vector (obj "attributes" (obj "POSITION" pos "NORMAL" nrm)
                                                   "indices" idx
                                                   "material" (position material material-names :test #'string=))))
                    meshes)
              (push (obj "name" name "mesh" (1- (length meshes))
                         "translation" (vector (/ (+ x0 x1) 2) (/ (+ y0 y1) 2) (/ (+ z0 z1) 2)))
                    nodes)))))
      (dolist (e empties)
        (destructuring-bind (name position rotation) e
          (let ((node (obj "name" name "translation" (coerce position 'vector))))
            (when rotation (setf (gethash "rotation" node) (coerce rotation 'vector)))
            (push node nodes))))
      (pad4 blob)
      (let* ((json (com.inuoe.jzon:stringify
                    (obj "asset" (obj "version" "2.0" "generator" "hexmaw src/blueprint.lisp")
                         "scene" 0
                         "scenes" (vector (obj "name" (name blueprint) "nodes" (coerce (loop for i below (length nodes) collect i) 'vector)
                                               "extras" extras))
                         "nodes" (coerce (reverse nodes) 'vector)
                         "meshes" (coerce (reverse meshes) 'vector)
                         "accessors" (coerce (reverse accessors) 'vector)
                         "bufferViews" (coerce (reverse views) 'vector)
                         "buffers" (vector (obj "byteLength" (length blob)))
                         "materials" (coerce (loop for m in material-names
                                                   for (r g b) = (rest (assoc m (materials blueprint) :test #'string-equal))
                                                   collect (obj "name" m "pbrMetallicRoughness"
                                                                (obj "baseColorFactor" (vector r g b 1.0)
                                                                     "metallicFactor" 0.0 "roughnessFactor" 1.0)))
                                             'vector))))
             (json-bytes (let ((v (octets)))
                           (loop for b across (sb-ext:string-to-octets json :external-format :utf-8)
                                 do (vector-push-extend b v))
                           (pad4 v 32)
                           v)))
        (ensure-directories-exist path)
        (with-open-file (s path :direction :output :element-type '(unsigned-byte 8) :if-exists :supersede)
          (let ((header (octets)))
            (put-u32 header #x46546C67) (put-u32 header 2)
            (put-u32 header (+ 12 8 (length json-bytes) 8 (length blob)))
            (put-u32 header (length json-bytes)) (put-u32 header #x4E4F534A)
            (write-sequence header s)
            (write-sequence json-bytes s)
            (let ((bin (octets)))
              (put-u32 bin (length blob)) (put-u32 bin #x004E4942)
              (write-sequence bin s))
            (write-sequence blob s)))
        path))))

;;; Building.

(defun build-one (blueprint &key (write T))
  "Build BLUEPRINT's block, writing it unless WRITE is NIL. Returns a one-line summary."
  (multiple-value-bind (boxes empties extras) (blueprint-geometry blueprint)
    (let ((path (block-output-path (name blueprint))))
      (when write (write-glb path blueprint boxes empties extras))
      (flet ((named (prefix) (loop for e in empties when (eql 0 (search prefix (first e))) collect (first e))))
        (format NIL "~a: ~:[~*free grid~;~{~d×~d~} cells~], ~d storey~:p, ~d boxes, ~d doorway~:p (~{~a~^ ~}), ~d spawn~:p, ~d pickup spot~:p, ~d torch~:*~[es~;~:;es~]~@[ -> ~a~]"
                (name blueprint) (cells blueprint) (cells blueprint) (storeys blueprint)
                (count-if-not (lambda (b) (eql 0 (search "plug_" (first b)))) boxes)
                (length (named "connector_"))
                (mapcar (lambda (n) (subseq n (length "connector_"))) (named "connector_"))
                (length (named "spawn_")) (length (named "pickup_")) (length (named "torch_"))
                (and write (enough-namestring path (root))))))))

(defun build-blueprint (name &key (write T))
  "Read blueprint NAME and build its block (and its mirror, if it asks for one).
Returns the summaries."
  (let ((blueprint (read-blueprint (blueprint-path name))))
    (cons (build-one blueprint :write write)
          (when (mirror blueprint) (list (build-one (mirrored blueprint) :write write))))))

(defun build-blueprints (&key (names (blueprint-names)) (write T))
  "Build every blueprint in NAMES, carrying on past errors. Returns the summaries and the errors."
  (let ((summaries ()) (errors ()))
    (dolist (name names)
      (handler-case (setf summaries (append summaries (build-blueprint name :write write)))
        (blueprint-error (e) (push e errors))))
    (values summaries (nreverse errors))))

(defun blueprint-for-block (name)
  "The blueprint block NAME is built from, or NIL: NAME's own, or for <base>-mirror, <base>'s."
  (let ((name (string-downcase name)))
    (cond ((probe-file (blueprint-path name)) name)
          ((and (< 7 (length name)) (string= "-mirror" name :start2 (- (length name) 7))
                (probe-file (blueprint-path (subseq name 0 (- (length name) 7)))))
           (subseq name 0 (- (length name) 7))))))

(defvar *build-blocks* T
  "Whether ENSURE-BLOCK builds anything. A standalone build turns it off: it ships its
blocks built, and has no blueprints to build them from.")

(defun ensure-block (name)
  "Build block NAME from its blueprint if the .glb is missing or older. True if it was built."
  (let ((source (and *build-blocks* (blueprint-for-block name))))
    (when source
      (let ((glb (probe-file (block-output-path name))))
        (when (or (null glb) (< (file-write-date glb) (file-write-date (blueprint-path source))))
          (build-blueprint source)
          T)))))

(defun main (args)
  "tools/blueprint: build the named blueprints, or all; --check only checks. Returns the exit code."
  (let* ((check (member "--check" args :test #'string=))
         (names (or (remove "--check" args :test #'string=) (blueprint-names))))
    (multiple-value-bind (summaries errors) (build-blueprints :names names :write (not check))
      (dolist (s summaries) (format T "~a~%" s))
      (dolist (e errors) (format *error-output* "~a~%" e))
      (if errors 1 0))))
