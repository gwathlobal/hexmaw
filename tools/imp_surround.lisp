;;;; How well a pack of imps surrounds the player: loaded into a running game by
;;;; tools/imp_surround.sh, on the debug level with only its hall imps
;;;; (*DEBUG-LEVEL-MONSTERS* '(IMP), *DEBUG-HALL-MONSTERS* T).
;;;;
;;;; Each trial stands the player in the hall facing north, a pack of *SURROUND-PACK* imps
;;;; 6 m in front hunting them, and has the player strafe (A to *SURROUND-STRAFE* metres left of
;;;; the middle, then D to as far right, and on; W or S if shoved off the line) for
;;;; *SURROUND-SECONDS*, health topped up. Or, in :TRACK mode, the player turns to face the
;;;; nearest imp at *SURROUND-TURN* radians a second, as a player keeping the pack in front does,
;;;; and backs off for 2 s in every 4 while within *SURROUND-ROOM* of where they started. It records how long
;;;; imps stand in reach in front of the player, at their flank and at their back; the claws
;;;; that reach them by the same sides and whether the shield took them; the flank leaps
;;;; started, cut short and knocked down; touches between imps; and when an imp first stood
;;;; at the flank or back. RUN-SURROUND runs a list of configurations a number of trials each.

(in-package #:hexmaw)

(defparameter *surround-pack* 3)
(defparameter *surround-seconds* 20.0)
(defparameter *surround-strafe* 2.5 "Metres either side of the middle the player strafes to before turning back.")
(defparameter *surround-player* (vec 0 0 1))
(defparameter *surround-turn* 3.0 "Radians a second the player turns to face the nearest imp in :TRACK mode.")
(defparameter *surround-room* 6.0 "Metres from where they started the player backs off to at most.")

(defvar *surround* NIL "The trial being recorded, a plist, or NIL.")
(defvar *surround-queue* () "The trials still to run: (leaps shield mode) each, MODE :STRAFE or :TRACK.")
(defvar *surround-results* () "Finished trials, newest first.")

(defun surround-side (yaw)
  "Which side of the player YAW (a bearing from them) is: :FRONT, :FLANK or :BACK."
  (let ((a (angle-between yaw (target-facing *player*))))
    (cond ((< a (/ pi 4)) :front)
          ((< a (* 3/4 pi)) :flank)
          (T :back))))

(defun surround-imps ()
  (remove-if-not (lambda (c) (and (typep c 'imp) (not (dead c)) (< (vy (location c)) 2.0)
                                  (< (abs (vx (location c))) 10) (< (abs (vz (location c))) 10)))
                 (coerce *creatures* 'list)))

(defun stage-surround (leaps shield &optional (mode :strafe))
  "Stand the player and a fresh pack for a trial."
  (setf *imp-flank-leaps* leaps)
  (let ((imps (surround-imps)))
    (loop while (< (length imps) *surround-pack*)
          do (spawn-creature (make-instance 'imp :location (vec 0 0 -5)) (scene +main+))
             (setf imps (surround-imps)))
    (v<- (feet *player*) *surround-player*)
    (setf (vy (rotation *player*)) 0.0
          (health *player*) (max-health *player*)
          (stamina *player*) (max-stamina *player*)
          (block-held *player*) shield)
    (loop for imp in imps
          for k from 0
          for x = (* 1.2 (- k (/ (1- (length imps)) 2)))
          do (v<- (location imp) (vec x 0 (+ -5 (* -0.3 (abs x)))))
             (setf (vx (momentum imp)) 0.0 (vz (momentum imp)) 0.0
                   (health imp) (max-health imp)
                   (brain imp) :idle (path imp) ()
                   (idle-timer imp) (random 0.3)
                   (slot-yaw imp) NIL (slot-bans imp) ()
                   (flanking imp) NIL (flank-timer imp) 0.0
                   (leap-cooldown imp) 0.0 (flank-leaping imp) NIL
                   (airborne imp) NIL (falling imp) NIL (recover imp) 0.0 (attack-kind imp) :slam
                   (downed imp) 0.0 (knocked imp) NIL (shrieked imp) NIL (fleeing imp) 0.0)
             (set-target imp *player*)
             (face-target imp)
             (setf (alert imp) 30.0))
    (setf *surround* (list :leaps leaps :shield shield :mode mode :time 0.0
                           :front 0.0 :flank 0.0 :back 0.0
                           :claw-front 0 :claw-flank 0 :claw-back 0 :blocked 0
                           :leaps-started 0 :cut-short 0 :knocked 0 :contacts 0
                           :first-side NIL :left T :landings () :was-landed ()
                           :was-leaping () :was-falling () :touching ()))))

(defun finish-surround ()
  (dolist (key '(:a :d :w :s)) (setf (input-held key) NIL))
  (setf (block-held *player*) NIL)
  (let ((trial *surround*))
    (dolist (key '(:was-leaping :was-falling :touching :left :was-landed)) (remf trial key))
    (push trial *surround-results*))
  (setf *surround* NIL)
  (if *surround-queue*
      (apply #'stage-surround (pop *surround-queue*))
      (setf *imp-flank-leaps* T)))

(defun strafe-line (s)
  "Facing north, strafe across the line through where the player started."
  (setf (vy (rotation *player*)) 0.0)
  (let ((x (vx (feet *player*)))
        (z (vz (feet *player*))))
    (cond ((< x (- (vx *surround-player*) *surround-strafe*)) (setf (getf s :left) NIL))
          ((< (+ (vx *surround-player*) *surround-strafe*) x) (setf (getf s :left) T)))
    (setf (input-held :a) (getf s :left)
          (input-held :d) (not (getf s :left))
          (input-held :w) (< (+ (vz *surround-player*) 0.5) z)
          (input-held :s) (< z (- (vz *surround-player*) 0.5)))))

(defun track-pack (dt time)
  "Turn toward the nearest imp, and back off from it for 2 s in every 4 while there is room."
  (let ((nearest NIL) (best 0.0))
    (dolist (imp (surround-imps))
      (let ((d (target-distance imp *player*)))
        (when (or (null nearest) (< d best))
          (setf nearest imp best d))))
    (when nearest
      (let* ((now (vy (rotation *player*)))
             (want (target-bearing *player* (location nearest)))
             (diff (- (mod (+ (- want now) pi) (* 2 pi)) pi))
             (most (* *surround-turn* dt)))
        (setf (vy (rotation *player*)) (float (+ now (max (- most) (min most diff))) 0f0))))
    (setf (input-held :s) (and (evenp (floor time 2.0))
                               (< (vdistance (feet *player*) *surround-player*) *surround-room*))
          (input-held :a) NIL (input-held :d) NIL (input-held :w) NIL)))

(defun note-surround (dt)
  (let ((s *surround*))
    (incf (getf s :time) dt)
    (setf (health *player*) (max-health *player*)
          (stamina *player*) (max-stamina *player*)
          (block-held *player*) (getf s :shield))
    (if (eq (getf s :mode) :track)
        (track-pack dt (getf s :time))
        (strafe-line s))
    (let ((imps (surround-imps)))
      (dolist (imp imps)
        (when (target-within-p imp (+ (attack-reach imp) 0.3) *player*)
          (let ((side (surround-side (target-bearing *player* (location imp)))))
            (incf (getf s side) dt)
            (when (and (not (eq side :front)) (null (getf s :first-side)))
              (setf (getf s :first-side) (getf s :time)))))
        (let ((leaping (realp (flank-leaping imp)))
              (cut (and (falling imp) (realp (flank-leaping imp)) (not (knocked imp)) (not (impaled imp)))))
          (when (and leaping (not (member imp (getf s :was-leaping))))
            (incf (getf s :leaps-started)))
          (when (and (eq (flank-leaping imp) :landed) (not (member imp (getf s :was-landed))))
            (push (list (surround-side (target-bearing *player* (location imp)))
                        (target-distance imp *player*))
                  (getf s :landings)))
          (setf (getf s :was-landed) (if (eq (flank-leaping imp) :landed)
                                         (adjoin imp (getf s :was-landed))
                                         (remove imp (getf s :was-landed))))
          (when (and cut (not (member imp (getf s :was-falling))))
            (incf (getf s :cut-short)))
          (when (and (knocked imp) (realp (flank-leaping imp)) (not (member imp (getf s :was-falling))))
            (incf (getf s :knocked)))
          (setf (getf s :was-leaping) (if leaping (adjoin imp (getf s :was-leaping)) (remove imp (getf s :was-leaping)))
                (getf s :was-falling) (if (falling imp) (adjoin imp (getf s :was-falling)) (remove imp (getf s :was-falling))))))
      ;; Touches between imps: a pair counts each time it comes into contact.
      (let ((touching ()))
        (loop for (a . rest) on imps
              do (dolist (b rest)
                   (when (< (vdistance (location a) (location b)) (+ (body-radius a) (body-radius b) 0.05))
                     (let ((pair (cons a b)))
                       (push pair touching)
                       (unless (find pair (getf s :touching) :test #'equal)
                         (incf (getf s :contacts)))))))
        (setf (getf s :touching) touching)))
    (setf *surround* s)
    (when (<= *surround-seconds* (getf s :time))
      (finish-surround))))

(defclass surround-recorder (entity listener)
  ((name :initform :surround-recorder)))

(define-handler (surround-recorder tick) (dt)
  (when (and *surround* (not (frozen-p)) (<= *hit-stop* 0))
    (note-surround dt)))

(defmethod strike-target :around ((player player) amount from &rest args &key by &allow-other-keys)
  (declare (ignore args amount))
  (let ((blocked (call-next-method)))
    (when (and *surround* (typep by 'imp))
      (let ((side (surround-side (target-bearing player from))))
        (incf (getf *surround* (ecase side (:front :claw-front) (:flank :claw-flank) (:back :claw-back))))
        (when blocked (incf (getf *surround* :blocked)))))
    blocked))

(defun run-surround (configs trials)
  "Run TRIALS trials of each of CONFIGS, (leaps shield mode) each, one after another."
  (unless (node :surround-recorder (scene +main+))
    (enter (make-instance 'surround-recorder) (scene +main+)))
  (setf *surround-results* ()
        *surround-queue* (loop for config in configs
                               append (loop repeat trials collect config)))
  (apply #'stage-surround (pop *surround-queue*))
  (length *surround-queue*))

(defun surround-done-p () (and (null *surround*) (null *surround-queue*)))

(defun surround-report ()
  "The finished trials' means per configuration, as lines."
  (let ((groups ()))
    (dolist (trial (reverse *surround-results*))
      (let* ((key (list (getf trial :leaps) (getf trial :shield) (getf trial :mode)))
             (group (assoc key groups :test #'equal)))
        (if group (push trial (cdr group)) (setf groups (append groups (list (list key trial)))))))
    (with-output-to-string (out)
      (format out "~&mode   leaps shield n | in reach: front flank back (s, share flank+back) | claws: front flank back blocked | leaps cut knocked | imp contacts | first side contact (s)~%")
      (loop for ((leaps shield mode) . trials) in groups
            for n = (length trials)
            do (flet ((mean (key) (/ (reduce #'+ trials :key (lambda (s) (or (getf s key) 0))) n)))
                 (let ((reach (+ (mean :front) (mean :flank) (mean :back)))
                       (firsts (remove NIL (mapcar (lambda (s) (getf s :first-side)) trials))))
                   (format out "~(~6a~) ~5a ~6a ~a | ~5,1f ~5,1f ~5,1f (~3d%) | ~4,1f ~4,1f ~4,1f ~4,1f | ~4,1f ~4,1f ~4,1f | ~5,1f | ~a of ~a, mean ~,1f~%"
                           mode (if leaps "on" "off") (if shield "up" "down") n
                           (mean :front) (mean :flank) (mean :back)
                           (if (< 0 reach) (round (* 100 (/ (+ (mean :flank) (mean :back)) reach))) 0)
                           (mean :claw-front) (mean :claw-flank) (mean :claw-back) (mean :blocked)
                           (mean :leaps-started) (mean :cut-short) (mean :knocked)
                           (mean :contacts)
                           (length firsts) n (if firsts (/ (reduce #'+ firsts) (length firsts)) 0))))))))
