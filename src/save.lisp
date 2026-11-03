(in-package #:hexmaw)

;;; Saving and loading generated runs. A save doesn't store the level: the generator
;;; draws only from its seeded state, so the seed and the generator's settings build it
;;; again, with the same monsters in the same order in *CREATURES*. What changed in play
;;; is laid over it: the player, every creature, every effect in flight (projectiles,
;;; circles, impacts), the blood pool, hit-stop and the random state, so a load is the
;;; moment it was saved, and nothing coming at the player goes away with it.
;;;
;;; A save is one plist, printed readably and read back with *READ-EVAL* NIL. Objects are
;;; saved as alists of their SAVED-SLOTS; references between them are tagged lists
;;; (ENCODE-VALUE), so a list whose first element is :VEC, :PLAYER, :CREATURE, :SPELL,
;;; :ABILITY or :ANIMATION is a reference, not data. A new kind of state that changes in
;;; play needs its slot in SAVED-SLOTS, and a new kind of object an ENCODE-VALUE case.

(defparameter *save-directory* (uiop:xdg-data-home "hexmaw/saves/")
  "Where saves live: $XDG_DATA_HOME/hexmaw/saves/, usually ~/.local/share/.")
(defparameter *save-version* 3 "Bumped when old saves can no longer be read.")
(defparameter *saved-generator-settings*
  '(*generator-rooms* *generator-attempts* *corridor-run* *generator-storeys* *generator-blocks* *spawn-pool*
    *river-length* *max-rivers* *high-length* *max-high-networks* *flooded-length* *max-flooded-networks*
    *canal-length* *max-canals* *start-clearance*)
  "The variables besides the seed that decide a generated level.")

(defun level-settings (depth)
  "The generator's settings for level DEPTH of a run, as an alist of those variables."
  (loop for var in *saved-generator-settings*
        collect (cons var (if (eq var '*generator-rooms*)
                              (run-level-property depth :rooms)
                              (symbol-value var)))))

(defun save-path (slot)
  (merge-pathnames (if (eq slot :quick) "quick.sav" (format NIL "slot-~d.sav" slot))
                   *save-directory*))

(defun slot-name (slot)
  (if (eq slot :quick) "Quicksave" (format NIL "Slot ~d" slot)))

;;; Object state.

(defgeneric saved-slots (object)
  (:documentation "The slots of OBJECT that change in play, which a save keeps.")
  (:method-combination append :most-specific-last))

(defmethod saved-slots append ((actor whirlable))
  '(whirl-angle whirl-radius whirl-lift whirl-time whirl-hold whirl-stuck flung spat-timer))

(defmethod saved-slots append ((player player))
  '(feet rotation velocity grounded eye health pain restore-flash restored burn-timer wading swimming climbing breath drown-timer
    mana inventory quickslot stamina winded cast-timer cast-time
    pending-spell weapon wanted-weapon weapon-lower swing-time swing-pending
    block-raise bash-time bash-pending guard-broken run-time damage-taken level-records))

(defmethod saved-slots append ((creature creature))
  '(location facing home health brain alert look-timer replan-timer attack-time attack-pending
    idle-timer path stuck walk-distance momentum flight stagger flash brace burn-timer dead bleeding
    drip-timer gibbed rising stirring bash-poise flanking flank-timer
    sidestep sidestep-side sidestep-flipped slot-yaw slot-bans slot-ban-timer))

(defmethod saved-slots append ((flyer flyer))
  '(dive-direction dive-left downed landed launching landed-dead fall-speed bob-phase))

(defmethod saved-slots append ((user ability-user))
  '(ability cooldowns))

(defmethod saved-slots append ((necromancer necromancer))
  '(raise-target))

(defmethod saved-slots append ((wraith gale-wraith))
  '(tempest-point))

(defmethod saved-slots append ((riftwalker riftwalker))
  '(blink-cooldown blink-timer pounce call-target call-point))

(defmethod saved-slots append ((sign rift-sign))
  '(caster centre))

(defmethod saved-slots append ((sigil summon-sigil))
  '(caster centre burst))

(defmethod saved-slots append ((boss boss))
  '(powers dormant enraged boss-power power-cooldowns power-gap power-point roar))

(defmethod saved-slots append ((leaper leaper))
  '(attack-kind leap-from leap-to leap-apex leap-duration leap-time airborne falling fall-speed
    recover leap-cooldown))

(defmethod saved-slots append ((sprite fx-sprite))
  '(animation location age))

(defmethod saved-slots append ((projectile spell-projectile))
  '(spell caster homing projectile-velocity submerged evade-asked))

(defmethod saved-slots append ((circle spell-circle))
  '(spell caster centre struck rings-left))

;; CAUGHT isn't a slot: what it holds is noted on them, and it links them up again.
(defmethod saved-slots append ((vortex spell-vortex))
  '(spell caster centre heading route replan ceiling puff-timer caught))

(defmethod saved-slots append ((sign gale-sign))
  '(caster centre))

(defun animation-name (animation)
  (loop for name being the hash-keys of *fx-animations* using (hash-value value)
        when (eq value animation) return name
        finally (error "~s isn't a defined effect animation." animation)))

(defun encode-value (value)
  "VALUE as data that prints readably: vectors as (:VEC ...), objects as references."
  (typecase value
    ((or number symbol string character) value)
    (vec2 (list :vec (vx value) (vy value)))
    (vec3 (list :vec (vx value) (vy value) (vz value)))
    (vec4 (list :vec (vx value) (vy value) (vz value) (vw value)))
    (player (list :player))
    (creature (list :creature (or (position value *creatures*)
                                  (error "~a isn't in *CREATURES*." value))))
    (spell (list :spell (spell-name value)))
    (ability (list :ability (ability-name value)))
    (fx-animation (list :animation (animation-name value)))
    (cons (mapcar #'encode-value value))
    (T (error "Don't know how to save ~s." value))))

(defun decode-value (data owner)
  "The value DATA was encoded from. OWNER is the object whose slot it fills, for
references that are relative to it (an ability)."
  (if (consp data)
      (case (first data)
        (:vec (apply #'vec (rest data)))
        (:player *player*)
        (:creature (aref *creatures* (second data)))
        (:spell (find-spell (second data)))
        (:ability (or (find-ability owner (second data)) (error "~a has no ability ~s." owner (second data))))
        (:animation (find-fx-animation (second data)))
        (T (mapcar (lambda (d) (decode-value d owner)) data)))
      data))

;; A saved name is a slot, or where the object has no slot by that name an accessor:
;; Trial keeps an entity's LOCATION in its transform.
(defun saved-value (object name)
  (if (slot-exists-p object name)
      (and (slot-boundp object name) (slot-value object name))
      (funcall name object)))

(defun (setf saved-value) (value object name)
  (if (slot-exists-p object name)
      (setf (slot-value object name) value)
      (funcall (fdefinition (list 'setf name)) value object)))

(defun object-state (object)
  (loop for name in (saved-slots object)
        collect (cons name (encode-value (saved-value object name)))))

(defun restore-state (object state)
  "Set OBJECT's slots from STATE (OBJECT-STATE's alist), skipping those it no longer has.
A vector is written in place, since some slots have only a reader."
  (loop for (name . data) in state
        when (or (slot-exists-p object name) (fboundp name))
          do (let ((value (decode-value data object))
                   (old (saved-value object name)))
               (if (and (typep old '(or vec2 vec3 vec4)) (eq (class-of old) (class-of value)))
                   (v<- old value)
                   (setf (saved-value object name) value)))))

;; SBCL prints a random state with #., which a save can't be read with, so it keeps the
;; state's words.
(defun random-state-words (state)
  (coerce (sb-kernel::random-state-state state) 'simple-vector))

(defun (setf random-state-words) (words state)
  (replace (sb-kernel::random-state-state state) words)
  words)

;;; What a save holds.

(defun level-layout ()
  "The generated level's cells and the block in each, in a fixed order."
  (sort (loop for cell being the hash-keys of *level-cells* using (hash-value name)
              collect (cons cell name))
        (lambda (a b)
          (loop for x in (car a) for y in (car b)
                do (cond ((< x y) (return T))
                         ((> x y) (return NIL)))))))

(defun level-effects ()
  "The effects in flight: projectiles, circles, impacts and bursts; not the HUD, torches or pickups."
  (let ((effects ()))
    (when (and +main+ (scene +main+))
      (for:for ((entity over (scene +main+)))
        (when (and (typep entity 'fx-sprite) (not (typep entity '(or hud-element torch pickup)))
                   (container entity))
          (push entity effects))))
    (nreverse effects)))

(defun effect-record (effect)
  (let ((glow (find effect *lamps* :key #'source)))
    (list :class (type-of effect)
          :state (object-state effect)
          :glow (when glow (list (encode-value (color glow)) (radius glow))))))

(defun blood-record (pool)
  (flet ((v (array) (coerce array 'simple-vector)))
    (list :state (v (pool-state pool)) :frame (v (pool-frame pool)) :side (v (pool-side pool))
          :scales (v (pool-scales pool)) :positions (v (pool-positions pool))
          :velocities (v (pool-velocities pool)) :ages (v (pool-ages pool))
          :cursor (pool-cursor pool) :splat-count (splat-count pool) :gib-count (gib-count pool))))

(defun run-summary ()
  (let ((built (remove-if #'summoned *creatures*)))
    (list :slain (count-if #'dead built) :monsters (length built))))

(defun run-record ()
  (list :version *save-version*
        :saved (get-universal-time)
        :summary (run-summary)
        :seed *last-level-seed*
        :depth *run-depth*
        :run-seed (current-run-seed)
        :generator (level-settings *run-depth*)
        :layout (level-layout)
        :globals (list :hit-stop *hit-stop*
                       :light-clock *light-clock*
                       :random (random-state-words *random-state*)
                       :roll-random (random-state-words *roll-random*))
        :player (object-state *player*)
        :creatures (loop for creature across *creatures*
                         collect (list :class (type-of creature)
                                       :summoned (summoned creature)
                                       :state (object-state creature)))
        :effects (mapcar #'effect-record (level-effects))
        :blood (when *blood-pool* (blood-record *blood-pool*))
        ;; The blocks the automap shows, by placement order (map-view.lisp).
        :map (revealed-block-indices)
        ;; The seed places the pickups again; a save older than them has none taken.
        :pickups (taken-pickup-indices)
        ;; Whether the gate has dropped behind the player (boss.lisp).
        :arena (when *arena* (list :sealed (sealed *arena*)))))

;;; Files.

(defmacro with-save-syntax (&body body)
  `(with-standard-io-syntax
     (let ((*package* (find-package '#:hexmaw))
           (*read-eval* NIL))
       ,@body)))

(defun write-save (path record)
  "Write RECORD to PATH through a temporary file, so a crash leaves the old save whole."
  (let ((tmp (make-pathname :type "tmp" :defaults path)))
    (ensure-directories-exist path)
    (with-open-file (out tmp :direction :output :if-exists :supersede)
      (with-save-syntax
        (prin1 record out)
        (terpri out)))
    (uiop:rename-file-overwriting-target tmp path)))

(defun read-save (path)
  "The save at PATH, or NIL if there is none or it can't be read."
  (handler-case
      (with-open-file (in path :if-does-not-exist NIL)
        (when in
          (let ((record (with-save-syntax (read in))))
            (if (and (listp record) (eql *save-version* (getf record :version)))
                record
                (progn (v:warn :hexmaw "~a isn't a save of version ~d; ignored." path *save-version*)
                       NIL)))))
    (error (e)
      (v:warn :hexmaw "Can't read ~a: ~a" path e)
      NIL)))

(defun slot-info (slot)
  "The menu label for SLOT: its name, how far the run had got and when it was saved."
  (let ((save (read-save (save-path slot))))
    (if save
        (multiple-value-bind (s min h d mon) (decode-universal-time (getf save :saved))
          (declare (ignore s))
          (let ((summary (getf save :summary)))
            (format NIL "~a: level ~d, ~d/~d slain, ~d ~a ~2,'0d:~2,'0d"
                    (slot-name slot) (getf save :depth) (getf summary :slain) (getf summary :monsters)
                    d (aref #("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec") (1- mon))
                    h min)))
        (format NIL "~a: empty" (slot-name slot)))))

(defun slot-used-p (slot)
  (probe-file (save-path slot)))

;;; Saving.

(defun can-save-p ()
  (and (eq *level* :generated) *last-level-seed* *player*
       (member *game-state* '(:playing :paused))))

(defun save-game (slot)
  "Save the run to SLOT (1 to 3 or :QUICK). True if it was saved."
  (cond ((not (can-save-p))
         (v:warn :hexmaw "Only a generated level in play can be saved.")
         NIL)
        (T
         (handler-case
             (let ((path (save-path slot)))
               (write-save path (run-record))
               (setf *save-note* (format NIL "Saved to ~(~a~)" (slot-name slot)))
               (v:info :hexmaw "Saved to ~a." path)
               T)
           (error (e)
             (v:warn :hexmaw "Saving to ~a failed: ~a" (slot-name slot) e)
             NIL)))))

;;; Loading: LOAD-GAME starts a run as START-LEVEL does; BUILD-LEVEL builds the saved
;;; seed (GENERATE-SAVED-LEVEL), and SETUP-SCENE ends with RESTORE-RUN.

(defun load-game (slot)
  "Load the run saved in SLOT. True if there was one to load."
  (let ((save (read-save (save-path slot))))
    (cond (save
           ;; After START-LEVEL, which drops any load still pending and starts at the top.
           (start-level :generated)
           (setf *pending-load* save
                 *run-depth* (getf save :depth)
                 *run-seed* (getf save :run-seed))
           T)
          (T
           (v:warn :hexmaw "~a has no save that can be loaded." (slot-name slot))
           NIL))))

(defun generate-saved-level (container save)
  (let ((settings (getf save :generator)))
    (progv (mapcar #'car settings) (mapcar #'cdr settings)
      (generate-level container :seed (getf save :seed)
                                :exit (run-level-property (getf save :depth) :exit)))))

(defun save-matches-level-p (save)
  "True if the level just built is the one SAVE was made on."
  (let ((built (getf save :creatures)))
    (and (equal (getf save :layout) (level-layout))
         (equal (loop for c in built unless (getf c :summoned) collect (getf c :class))
                (map 'list #'type-of *creatures*)))))

(defun restore-effect (record scene)
  (let* ((state (getf record :state))
         (class (getf record :class))
         (initargs (loop for (slot initarg) in '((animation :animation) (spell :spell) (centre :centre))
                         for entry = (assoc slot state)
                         when entry append (list initarg (decode-value (cdr entry) NIL))))
         (effect (apply #'make-instance class initargs)))
    (restore-state effect state)
    (enter effect scene)
    (destructuring-bind (&optional color radius) (getf record :glow)
      (when color
        (attach-glow effect (decode-value color NIL) radius)))
    ;; A circle lights itself on its first tick until it strikes; after, it keeps the
    ;; lamp it had, and its aurora is already gone.
    (when (and (typep effect 'spell-circle) (struck effect))
      (light-circle effect)
      (drop-aurora effect))))

(defun restore-blood (pool record)
  (loop for (key array) on '(:state pool-state :frame pool-frame :side pool-side :scales pool-scales
                             :positions pool-positions :velocities pool-velocities :ages pool-ages)
          by #'cddr
        do (let* ((target (funcall array pool))
                  (type (array-element-type target)))
             (fill target (coerce 0 type))
             (map-into target (lambda (x) (coerce x type)) (getf record key))))
  (setf (pool-cursor pool) (mod (getf record :cursor) (pool-size pool))
        (splat-count pool) (getf record :splat-count)
        (gib-count pool) (getf record :gib-count)))

(defun restore-saved-objects (save scene)
  (let ((records (getf save :creatures)))
    ;; Raised skeletons first, so every creature reference has its index.
    (dolist (record records)
      (when (getf record :summoned)
        (spawn-creature (make-instance (getf record :class) :summoned T) scene)))
    (restore-state *player* (getf save :player))
    (place-camera *player*)
    (loop for record in records
          for creature across *creatures*
          do (restore-state creature (getf record :state))
             (update-creature-look creature)))
  (dolist (record (getf save :effects))
    (restore-effect record scene))
  (when (and *blood-pool* (getf save :blood))
    (restore-blood *blood-pool* (getf save :blood)))
  (reveal-block-indices (getf save :map))
  (take-pickups-at (getf save :pickups))
  (let ((globals (getf save :globals)))
    (setf *hit-stop* (getf globals :hit-stop)
          *light-clock* (getf globals :light-clock))
    ;; Last: making the effects above draws on RANDOM.
    (setf (random-state-words *random-state*) (getf globals :random)
          (random-state-words *roll-random*) (getf globals :roll-random))))

(defun restore-run (scene)
  "Lay the pending save over the level SETUP-SCENE has just built, and pause there."
  (let ((save *pending-load*))
    (setf *pending-load* NIL)
    (cond ((not (save-matches-level-p save))
           (v:warn :hexmaw "This save's level has changed since (the blocks or generator differ); starting it fresh.")
           NIL)
          (T
           (handler-case (progn (restore-saved-objects save scene)
                                (when (getf (getf save :arena) :sealed)
                                  (seal-arena :instant T)))
             (error (e)
               (v:warn :hexmaw "Restoring the save failed: ~a" e)
               (return-from restore-run NIL)))
           ;; Paused, so the player sees where they are before anything moves.
           (setf *game-state* :paused)
           (release-mouse *player*)
           T))))
