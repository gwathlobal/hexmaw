(in-package #:hexmaw)

;;; Level sweeps without a window. BUILD-LEVEL needs no context, GL or sound: what it enters
;;; into its container are objects that only load onto the GPU when a scene is staged. So a
;;; plain process (tools/levelcheck) builds level after level into a bare scene, the same
;;; levels a game builds for those seeds, and reports what each holds and what its checks
;;; found. The level's state is global (*SOLIDS*, *CREATURES*, *NAV-GRID* ...), so never
;;; here in a running game: a build would replace the level being played.

(defclass log-collector ()
  ((warnings :initform () :accessor collected-warnings)
   (notes :initform () :accessor collected-notes))
  (:documentation "Stands in for verbose's controller in a sweep: keeps the game's warnings and
infos as strings, newest first, in the thread that logs them."))

(defmethod piping:pass ((collector log-collector) message)
  (when (member :hexmaw (v:categories message))
    (let ((text (let ((content (v:content message)))
                  (if (functionp content) (funcall content) (princ-to-string content)))))
      (case (v:level message)
        ((:warn :error :severe :fatal) (push text (collected-warnings collector)))
        (:info (push text (collected-notes collector))))))
  NIL)

(defun build-level-alone (&key (level :generated) run-seed (depth 1) block)
  "Build a level into a scene of its own, for a sweep: level DEPTH of run RUN-SEED, or, with
BLOCK, that block alone as CHECK-KIT checks it. Returns the scene. Not in a running game."
  (when (and +main+ (scene +main+))
    (error "A game is running here: building a level alone would replace its level. Use RELOAD-SCENE."))
  (setf *pending-load* NIL)
  (if block
      (setf *level* :block *check-block* block)
      (setf *level* level *run-seed* run-seed *run-depth* depth))
  (let ((scene (make-instance 'scene)))
    (build-level scene)
    scene))

(defun json-object (&rest keys-and-values)
  "A hash table jzon writes as an object, from alternating keys (strings) and values."
  (let ((table (make-hash-table :test 'equal)))
    (loop for (key value) on keys-and-values by #'cddr
          do (setf (gethash key table) value))
    table))

(defun counted (items key)
  "An object of how many of ITEMS there are of each KEY, a string."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (item items table)
      (incf (gethash (funcall key item) table 0)))))

(defun class-label (object) (string-downcase (symbol-name (type-of object))))

(defun layout-digest ()
  "A number that changes when the level's cells or the blocks in them do (LEVEL-LAYOUT), the
same in any process and thread."
  (sxhash (with-standard-io-syntax
            (let ((*package* (find-package '#:hexmaw)))
              (prin1-to-string (level-layout))))))

(defun pickup-amount (pickup)
  "What PICKUP gives: its pile for a counted kind, else its kind's :AMOUNT (1 for a glyph or loot)."
  (let ((kind (pickup-kind pickup)))
    (if (pickup-property kind :count)
        (pickup-count pickup)
        (or (pickup-property kind :amount) 1))))

(defun pickup-report ()
  "Each kind of pickup on the level: how many, and what they give in all."
  (let ((table (make-hash-table :test 'equal)))
    (loop for pickup across *pickups*
          for entry = (or (gethash (string-downcase (pickup-kind pickup)) table)
                          (setf (gethash (string-downcase (pickup-kind pickup)) table)
                                (json-object "n" 0 "amount" 0)))
          do (incf (gethash "n" entry))
             (incf (gethash "amount" entry) (pickup-amount pickup)))
    table))

(defun resource-totals ()
  "What the level's pickups restore or give, by resource: health, mana, gold, dust."
  (let ((table (make-hash-table :test 'equal)))
    (loop for pickup across *pickups*
          for resource = (pickup-property (pickup-kind pickup) :resource)
          when resource
            do (incf (gethash (string-downcase resource) table 0) (pickup-amount pickup)))
    table))

(defun level-report (run-seed depth seconds collector)
  "What the generated level just built holds and what its checks found, as a JSON object."
  (let* ((checks *last-level-checks*)
         (monsters (remove-if-not #'monster-p *creatures*))
         (boss (and *arena* (arena-boss *arena*))))
    (json-object
     "run" run-seed "depth" depth "seed" *last-level-seed*
     "attempts" (getf checks :attempts)
     "problem" (or (getf checks :problem) 'null)
     "settlement" (if *settlement*
                      (json-object "name" (settlement-name *settlement*)
                                   "faction" (string-downcase (settlement-faction *settlement*))
                                   "condition" (string-downcase (built-condition *settlement*)))
                      'null)
     "layout" (layout-digest)
     "cells" (hash-table-count *level-cells*)
     "blocks" (length *map-blocks*)
     "rooms" (count-if (lambda (b) (room-block-p (map-block-name b))) *map-blocks*)
     "solids" (length *solids*)
     "networks" (coerce (loop for n in *level-networks*
                              collect (json-object "family" (string-downcase (network-family n))
                                                   "pieces" (network-pieces n)
                                                   "target" (network-target n)
                                                   "ends" (coerce (mapcar #'string-downcase (reverse (network-ends n)))
                                                                  'vector)))
                        'vector)
     "monsters" (length monsters)
     "monster_kinds" (counted (coerce monsters 'list) #'class-label)
     "elites" (count-if (lambda (c) (typep c 'elite)) monsters)
     "townsfolk" (count-if (lambda (c) (typep c 'townsfolk)) *creatures*)
     "creature_order" (sxhash (format NIL "~{~a~^ ~}" (map 'list #'class-label *creatures*)))
     "boss" (if boss (boss-kind boss) 'null)
     "pickups" (length *pickups*)
     "pickup_kinds" (pickup-report)
     "pickup_order" (sxhash (format NIL "~{~a~^ ~}" (map 'list (lambda (p) (string (pickup-kind p))) *pickups*)))
     "resources" (resource-totals)
     "exits" (length *level-exits*)
     "altars" (length *level-altars*)
     "unreachable" (length (getf checks :unreachable))
     "stranded" (coerce (mapcar #'class-label (getf checks :stranded)) 'vector)
     "ice_joins" (length (getf checks :ice-joins))
     "seconds" seconds
     "warnings" (coerce (reverse (collected-warnings collector)) 'vector)
     "notes" (coerce (reverse (collected-notes collector)) 'vector))))

(defmacro with-collected-log ((collector) &body body)
  "Run BODY with the game's log going into a fresh LOG-COLLECTOR, bound to COLLECTOR."
  `(let ((,collector (make-instance 'log-collector))
         (previous v:*global-controller*))
     (setf v:*global-controller* ,collector)
     (unwind-protect (progn ,@body)
       (setf v:*global-controller* previous))))

(defun seconds-since (start)
  (/ (round (* 1000 (- (get-internal-real-time) start)) internal-time-units-per-second) 1000.0))

(defun failure-report (fields error)
  (apply #'json-object "error" (remove #\Newline (princ-to-string error)) fields))

(defun sweep-level (run-seed depth)
  "Build level DEPTH of run RUN-SEED alone and report on it (LEVEL-REPORT); a level whose build
signals an error reports the error instead."
  (with-collected-log (log)
    (let ((start (get-internal-real-time)))
      (handler-case (progn (build-level-alone :run-seed run-seed :depth depth)
                           (level-report run-seed depth (seconds-since start) log))
        (error (e) (failure-report (list "run" run-seed "depth" depth) e))))))

(defun sweep-levels (&key (runs '(1)) depths)
  "Report on every level of each run in RUNS (seeds), at DEPTHS (default all of a run's): a list
of JSON objects (hash tables), as SWEEP-LEVEL makes them."
  (loop for run in runs
        nconc (progn
                ;; The run's levels (RUN-LEVELS) depend on its seed: where the settlement falls.
                (setf *run-seed* run)
                (loop for depth in (or depths (loop for d from 1 to (run-length) collect d))
                      when (<= 1 depth (run-length))
                        collect (sweep-level run depth)))))

(defun sweep-block (name)
  "Build block NAME alone and check it as CHECK-KIT does (BLOCK-PROBLEMS)."
  (with-collected-log (log)
    (let ((start (get-internal-real-time)))
      (handler-case (progn (build-level-alone :block name)
                           (json-object "block" name
                                        "problems" (coerce (block-problems name) 'vector)
                                        "seconds" (seconds-since start)
                                        "warnings" (coerce (reverse (collected-warnings log)) 'vector)))
        (error (e) (failure-report (list "block" name) e))))))

(defun kit-report (&optional names)
  "Check every block in NAMES (or the kit) alone: a list of JSON objects, as SWEEP-BLOCK makes them."
  (mapcar #'sweep-block (or names (kit-blocks))))

(defun levelcheck-worker (&key runs depths kit blocks (build-blocks NIL))
  "tools/levelcheck's worker: a JSON object a line on standard output for each level of RUNS at
DEPTHS, and with KIT for each of BLOCKS (or the kit). Blocks aren't rebuilt from their
blueprints unless BUILD-BLOCKS: the driver has done that, and workers side by side would write
the same files."
  (let ((hexmaw.blueprint:*build-blocks* build-blocks))
    (flet ((emit (object)
             (write-line (com.inuoe.jzon:stringify object) *standard-output*)
             (finish-output *standard-output*)))
      ;; Loaded, and so compiled: the driver may start the other workers.
      (emit (json-object "ready" T))
      (when kit
        (dolist (name (or blocks (kit-blocks)))
          (emit (sweep-block name))))
      (dolist (run runs)
        (setf *run-seed* run)
        (loop for depth in (or depths (loop for d from 1 to (run-length) collect d))
              when (<= 1 depth (run-length))
                do (emit (sweep-level run depth)))))))
