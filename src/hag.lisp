(in-package #:hexmaw)

;;; The rime hag: a stooped crone of the ice caves, the first monster whose element is frost and
;;; the first caster that punishes a player who closes in. She throws rime shards (frost, a chill);
;;; from level 2 of a run she throws a ball of rime at the floor ahead of where her target is going,
;;; which bursts into a rime patch (skins.lisp: ice underfoot, and on the walls round it); and when
;;; her target comes within *HAG-NOVA-TRIGGER* she gathers the cold for a second, hunched, rime
;;; crawling up her, a cold lamp swelling and frost drawn in, then bursts a frost nova round her
;;; that leaves a patch round her feet. A run, a bash or the earthshake in the gather beats it. She
;;; walks her own ice without slipping (SLIPS-ON-RIME-P), takes a quarter of frost and half again of
;;; fire (*ELEMENT-RESISTANCES*), and killed by a player who doesn't know frost drops its glyph
;;; (TAUGHT-EFFECT). Fire melts her rime.

(defparameter *hag-height* 1.7 "Rime hag height in metres, hood to feet, stooped.")
(defparameter *hag-nova-trigger* 3.0 "Metres from her that her target sets off the frost nova.")
(defparameter *hag-nova-cooldown* 9.0)
(defparameter *rime-patch-radius* 3.5 "Metres round where her rime lands that the floor and walls ice over.")
(defparameter *rime-patch-time* 10.0 "Seconds her rime lasts; it shrinks away over its last second.")
(defparameter *rime-freeze* 1.0 "Seconds her rime freezes her foes as it forms.")
(defparameter *rime-field-cooldown* 12.0)
(defparameter *rime-field-first* 4.0 "Seconds of cooldown the rime field starts with, so a fight opens with shards.")
(defparameter *rime-field-lead* 1.5 "Metres at most ahead of where her target moves that the rime field is aimed.")
(defparameter *rime-field-lead-time* 0.5 "Seconds of the target's movement the rime field leads it by.")
(defparameter *rime-field-range* 11.0 "Metres from her her target may be for a rime field.")
(defparameter *hag-wary-time* 10.0
  "Seconds after the player's Absorb swallows one of her shards, or she sees it held at her, that she
throws none and comes in for the nova instead, icing the floor short of them where she may.")
(defparameter *hag-wary-reach* 2.5 "Metres from a target she shuns that she comes in to and waits at.")
(defparameter *rime-field-short* 1.3
  "Metres short of a target holding Absorb that she drops the rime field, so it lands on the floor
and not on them, where Absorb would swallow it.")
(defparameter *blizzard-radius* 6.0 "Metres round her the blizzard reaches across; a boss's *BLIZZARD-BOSS-SCALE* times it.")
(defparameter *blizzard-boss-scale* 1.25)
(defparameter *blizzard-height* 3.5 "Metres over her feet it reaches.")
(defparameter *blizzard-time* 10.0 "Seconds it blows, once raised.")
(defparameter *blizzard-cooldown* 18.0 "Seconds from raising one to the next: it is down for the rest.")
(defparameter *blizzard-first* 1.0 "Seconds of cooldown it starts with.")
(defparameter *blizzard-form* 0.6 "Seconds it takes to rise to full strength.")
(defparameter *blizzard-fade* 0.8 "Seconds it takes to die down at its end or her death.")
(defparameter *blizzard-turn* 1.2
  "Radians a second its wind turns a projectile flying through it (WIND-TURN), times its GUST: the
Fire Bolt from 3 m always strikes her, from 4 m a third of the time, and from 5 m or its rim (6 m) it
goes 0.5 to 1.4 m wide. Not her own.")
(defparameter *blizzard-slow* 0.6 "Fraction of their speed it leaves her foes inside it.")
(defparameter *blizzard-flakes* 500.0 "Flakes a second it throws up round her, at full strength.")
(defparameter *blizzard-flake-life* '(0.5 1.3) "Least and most seconds a flake lasts.")
(defparameter *blizzard-flake-speed* 7.5 "M/s the wind carries a flake round her, times the flake's own speed.")
(defparameter *blizzard-flake-speeds* '(0.6 1.4) "Least and most of that a flake goes at.")
(defparameter *blizzard-flake-spread* 0.7
  "How the flakes thin out toward its edge: a flake starts RADIUS × u^SPREAD out, u even in 0..1,
so under 1 crowds them to the middle; some start past the edge (*BLIZZARD-FLAKE-REACH*).")
(defparameter *blizzard-flake-reach* 1.2 "Times its radius that its wind still carries flakes, and that they start within.")
(defparameter *blizzard-flake-chips* 0.0
  "Share of flakes that are 2 × 2 specks rather than streaks: the pool shades a chip as grit, so they read as dust.")
(defparameter *blizzard-volume* 0.7 "How loud its roar is at full strength.")
(defparameter *hag-gather-pain-bonus* 20 "Percent added to her pain chance while she gathers the nova.")
(defparameter *hag-gather-light* (vec 0.6 1.3 2.2) "Her lamp's colour at the gather's height.")
(defparameter *hag-gather-light-radius* 6.0)
(defparameter *hag-gather-motes* 40.0 "Frost motes a second drawn in toward her through the gather.")
(defparameter *hag-gather-ring* '(1.2 2.2) "Least and most metres from her they start.")

;; Sliced at 109 px tall, so her art pixels are the monsters' 64 a metre.
(define-asset (hexmaw hag-turnaround) image
    #p"sprites/hag/turnaround.png"
  :min-filter :nearest :mag-filter :nearest)

;; A stooped hobble on the staff, four frames per view.
(define-fx-animation hag-walk "sprites/hag/walk" :loop T :size (* *hag-height* 112/109))
;; The staff swung forward, a shard forming at its lantern: wind-up, raised, release, recover.
;; The shards and the rime field.
(define-fx-animation hag-cast "sprites/hag/cast" :size (* *hag-height* 124/109))
;; The nova: the gather (hunched, rime crawling up her: what the tell holds), deeper, the burst,
;; recover.
(define-fx-animation hag-nova "sprites/hag/nova" :size (* *hag-height* 114/109))
;; The flinch: jolt, then stagger, two frames per view over *STAGGER-TIME*.
(define-fx-animation hag-hurt "sprites/hag/hurt" :size (* *hag-height* 110/109))
;; Her icicle mantle cracks and she sinks into a heap of frosted fur: the corpse. Front only.
(define-fx-animation hag-death "sprites/hag/death" :fps 9 :size (* *hag-height* 109/109))

;;; Her spells. The shard flies on the player's frost look; the rime field is a slower ball that
;;; lays its patch where it bursts (SPELL-IMPACT); the nova reaches 5 m, a boss's 7.

(define-spell rime-shard (:delivery :projectile :projectile-speed 10.0 :title "Rime Shard"
                          :projectile-animation 'frost-flight :impact-animation 'frost-burst
                          :light-color (vec 0.45 1.0 1.8) :light-radius 3.0)
  (:damage :magnitude '(4 6) :element :frost))

(define-spell rime-field (:delivery :projectile :projectile-speed 9.0 :title "Rime Field"
                          :projectile-animation 'frost-flight :impact-animation 'frost-burst
                          :light-color (vec 0.5 1.1 2.0) :light-radius 3.5)
  (:damage :magnitude '(2 4) :area 1.5 :element :frost))

(define-spell hag-nova (:delivery :nova :nova-radius 5.0 :title "Frost Nova")
  (:damage :magnitude '(8 12) :element :frost)
  (:slow :magnitude '(35 35) :duration 3)
  (:knockback :magnitude '(4 4)))

(define-spell hag-nova-boss (:delivery :nova :nova-radius 7.0 :title "Frost Nova")
  (:damage :magnitude '(8 12) :element :frost)
  (:slow :magnitude '(35 35) :duration 3)
  (:knockback :magnitude '(4 4)))

(defmethod spell-impact ((name (eql 'rime-field)) spell at caster container victim)
  (declare (ignore spell))
  ;; On a body, round its feet; on a floor or wall, where it burst.
  (let ((at (if victim (body-feet victim) at)))
    (lay-frost-patch at container :radius *rime-patch-radius* :time *rime-patch-time*
                                  :freeze *rime-freeze* :caster caster)))

(defun hag-abilities ()
  (list (make-instance 'ability :name :shard :spell 'rime-shard :animation 'hag-cast
                                :frame-times '(0.3 0.2 0.25 0.3) :hit-frame 2 :pause 1.0)
        (make-instance 'ability :name :rime-field :spell 'rime-field :animation 'hag-cast
                                :frame-times '(0.35 0.35 0.25 0.3) :hit-frame 2 :pause 1.0
                                :cooldown *rime-field-cooldown*)
        ;; From level 3: the staff raised, and the storm rises round her.
        (make-instance 'ability :name :blizzard :animation 'hag-cast
                                :frame-times '(0.3 0.45 0.25 0.3) :hit-frame 2 :pause 0.4
                                :cooldown *blizzard-cooldown*)
        ;; The gather is the tell: 1.0 s to the burst.
        (make-instance 'ability :name :frost-nova :spell 'hag-nova :animation 'hag-nova
                                :frame-times '(0.3 0.7 0.25 0.4) :hit-frame 2 :pause 1.2
                                :cooldown *hag-nova-cooldown*)))

(define-shader-entity rime-hag (ability-user creature)
  ((texture :initform (// 'hexmaw 'hag-turnaround))
   (atlas :initform (read-atlas "sprites/hag/turnaround.lisp"))
   (sprite-height :initform *hag-height*)
   ;; What a boss's powers show (POWER-ANIMATION, boss.lisp); the abilities answer otherwise.
   (attack-animation :initform 'hag-cast)
   (walk-animation :initform 'hag-walk)
   (hurt-animation :initform 'hag-hurt)
   (death-animation :initform 'hag-death)
   (gibs :initform '((:flesh 0 0 1 2 4 5 6 7)))
   (abilities :initform (hag-abilities))
   (cooldowns :initform (list :frost-nova 0.0 :rime-field *rime-field-first* :blizzard *blizzard-first*))
   (attack-range :initform 12.0)
   (keep-away :initform 3.5)
   (cast-offset :initform 0.3)
   (walk-speed :initform 1.0)
   (chase-speed :initform 1.7)
   (wander-radius :initform 2.0)
   (pain-chance :initform 30)
   (max-health :initform 30)
   (gather-lamp :initform NIL :accessor gather-lamp :documentation "Her lamp, lit through the nova's gather.")
   (mote-timer :initform 0.0 :accessor mote-timer)
   (wary :initform 0.0 :accessor wary
         :documentation "Seconds left that she feeds the player's Absorb no shards (*HAG-WARY-TIME*).")
   (blizzard :initform 0.0 :accessor blizzard
             :documentation "Seconds left of her blizzard, 0 with none (*BLIZZARD-TIME*).")
   (blizzard-centre :initform (vec 0 0 0) :reader blizzard-centre :documentation "Her feet, while it blows.")
   (blizzard-sound :initform NIL :accessor blizzard-sound)
   (flake-debt :initform 0.0 :accessor flake-debt :documentation "Flakes owed to the pool, a fraction carried over.")))

(define-creature-sounds rime-hag
  :alert :hag-alert :pain :hag-pain :death :hag-death :step :step-light)

;; The nova's gather draws a breath in; the shard and the field crack the staff's ice.
(defmethod creature-sound ((hag rime-hag) (event (eql :windup)))
  (if (eq :frost-nova (ability-name (current-ability hag))) :hag-gather :hag-cast))

(defmethod slips-on-rime-p ((hag rime-hag)) NIL)

;; Absorb turns her shards into the player's mana, as it did the acolyte's cinders: once it has
;; swallowed one, or she sees it held at her, she throws no more for a while and comes for them.
(defmethod note-absorbed ((hag rime-hag) projectile)
  (declare (ignore projectile))
  (setf (wary hag) *hag-wary-time*))

(defun shuns-target-p (hag target)
  "True if HAG feeds TARGET no shards now: it holds Absorb at her, or swallowed one lately."
  (when (absorbing-at-p hag target)
    (setf (wary hag) (max (wary hag) *hag-wary-time*)))
  (< 0.0 (wary hag)))
(defmethod taught-effect ((hag rime-hag)) :frost)

(defun gathering-nova-p (hag)
  "True while HAG gathers the cold for her nova: its tell, before the burst."
  (and (not (dead hag)) (ability-p hag :frost-nova) (winding-up-p hag)))

;; Gathering, she is easier to break.
(defmethod pain-chance :around ((hag rime-hag))
  (if (gathering-nova-p hag)
      (+ (call-next-method) *hag-gather-pain-bonus*)
      (call-next-method)))

(defun on-a-floor-p (target)
  "True if TARGET stands on a floor of the nav grid, neither swimming nor whirled."
  (and *nav-grid*
       (not (target-swimming-p target))
       (not (whirl target))
       (let ((feet (body-feet target)))
         (nav-floor-at (vx feet) (vy feet) (vz feet)))))

(defun hag-nova-ready-p (hag target distance)
  (and (< distance *hag-nova-trigger*)
       (ready-p hag :frost-nova)
       (on-a-floor-p target)))

(defun rime-field-ready-p (hag target distance)
  (and (level-ability-p :rime-field)
       (< distance *rime-field-range*)
       (ready-p hag :rime-field)
       (on-a-floor-p target)))

(defun blizzard-ready-p (hag distance)
  (and (level-ability-p :blizzard)
       (<= (blizzard hag) 0.0)
       (<= *hag-nova-trigger* distance)
       (ready-p hag :blizzard)))

(defmethod hunt-from-range ((hag rime-hag))
  "Burst a frost nova at a target come too close, if it is ready. Raise a blizzard at one further
off, if she may and it is ready; and while it blows, with the nova ready, walk in on a target it
holds back instead of backing off. If it holds Absorb at her or
swallowed a shard lately (SHUNS-TARGET-P), throw it no shard: a rime field short of it if she may,
else close in to *HAG-WARY-REACH* for the nova. Else back off from one too close, and with one in
range and sight throw a rime field ahead of it if she may, else a shard; or close in."
  (let* ((distance (target-distance hag))
         (target (hunt-target hag))
         (seen (and (< distance (attack-range hag))
                    (clear-path-p (location hag) (body-feet target) (cast-height hag)))))
    (cond ((and seen (hag-nova-ready-p hag target distance))
           (start-ability hag :frost-nova))
          ((and seen (blizzard-ready-p hag distance))
           (start-ability hag :blizzard))
          ;; Her wind holds it back: come in for the nova.
          ((and (< 0.0 (blizzard hag)) (ready-p hag :frost-nova) (on-a-floor-p target)
                (< (wind-slow hag target) 1.0))
           (chase hag))
          ((shuns-target-p hag target)
           ;; Ice the floor short of them, then come in for the nova, and wait close for it.
           (cond ((and seen (rime-field-ready-p hag target distance))
                  (start-ability hag :rime-field))
                 ((< *hag-wary-reach* distance) (chase hag))
                 (T (face-target hag) (stop-walking hag 0.3))))
          ((and (< distance (keep-away hag)) (retreat hag)))
          ((and seen (rime-field-ready-p hag target distance))
           (start-ability hag :rime-field))
          (seen (start-ability hag :shard))
          (T (chase hag)))))

;; The nova is cast round her, so she turns after nothing in its gather; the throws turn after
;; the target as a caster's do.

(defun cast-origin (creature)
  "Where CREATURE's casting hand is: in front of it and to its CAST-OFFSET side, at CAST-HEIGHT."
  (let* ((loc (location creature))
         (out (+ (body-radius creature) 0.15))
         (side (cast-offset creature))
         (yaw (facing creature)))
    (vec (+ (vx loc) (* out (sin yaw)) (* side (cos yaw)))
         (+ (vy loc) (cast-height creature))
         (+ (vz loc) (- (* out (cos yaw))) (* side (sin yaw))))))

(defun rime-field-point (target)
  "The floor ahead of where TARGET moves, *RIME-FIELD-LEAD-TIME* of its movement and at most
*RIME-FIELD-LEAD* metres on, under its feet if it stands still."
  (let* ((feet (body-feet target))
         (velocity (if (typep target 'player) (velocity target) (momentum target)))
         (dx (* *rime-field-lead-time* (vx velocity)))
         (dz (* *rime-field-lead-time* (vz velocity)))
         (d (sqrt (+ (* dx dx) (* dz dz))))
         (k (if (< *rime-field-lead* d) (/ *rime-field-lead* d) 1.0))
         (point (vec (+ (vx feet) (* k dx)) (+ (vy feet) 0.3) (+ (vz feet) (* k dz)))))
    ;; Ahead only where there is floor to ice; else at its feet.
    (if (and *nav-grid* (nav-floor-at (vx point) (vy point) (vz point)) (clear-line-p feet point))
        (floor-under point)
        (floor-under feet))))

(defun rime-field-short-point (hag target)
  "The floor *RIME-FIELD-SHORT* metres short of TARGET toward HAG, or NIL if there is none there."
  (let* ((feet (body-feet target))
         (loc (location hag))
         (dx (- (vx loc) (vx feet)))
         (dz (- (vz loc) (vz feet)))
         (d (sqrt (+ (* dx dx) (* dz dz)))))
    (when (and *nav-grid* (< *rime-field-short* d))
      (let ((point (vec (+ (vx feet) (* *rime-field-short* (/ dx d))) (+ (vy feet) 0.3)
                        (+ (vz feet) (* *rime-field-short* (/ dz d))))))
        (when (and (nav-floor-at (vx point) (vy point) (vz point)) (clear-line-p feet point))
          (floor-under point))))))

(defun throw-rime-field (hag)
  (let* ((origin (cast-origin hag))
         (target (hunt-target hag))
         (aim (v- (or (and (< 0.0 (wary hag)) (rime-field-short-point hag target))
                      (rime-field-point target))
                  origin)))
    (when (< 1f-4 (vlength aim))
      (let ((spell (find-spell 'rime-field)))
        (play-sound (spell-sound spell :cast) origin)
        (cast-spell spell origin (nvunit aim) (container hag) :caster hag)))))

(defun burst-hag-nova (hag)
  (let* ((loc (location hag))
         (spell (find-spell (if (typep hag 'boss) 'hag-nova-boss 'hag-nova)))
         (chest (vec (vx loc) (+ (vy loc) (* 0.55 (sprite-height hag))) (vz loc))))
    (cast-spell spell chest (vec 0 0 -1) (container hag) :caster hag)
    ;; It leaves her rime round her feet.
    (lay-frost-patch (vcopy loc) (container hag) :radius *rime-patch-radius* :time *rime-patch-time*
                                                 :caster hag)))

(defmethod release-attack ((hag rime-hag))
  (let ((ability (current-ability hag)))
    (case (ability-name ability)
      ;; Absorb raised at her in her wind-up: she keeps the shard.
      (:shard (unless (shuns-target-p hag (hunt-target hag)) (release-attack-spell hag)))
      (:rime-field (throw-rime-field hag))
      (:frost-nova (burst-hag-nova hag))
      (:blizzard (raise-blizzard hag)))
    (when (< 0 (ability-cooldown ability))
      (setf (getf (cooldowns hag) (ability-name ability))
            (* (ability-cooldown ability) (depth-scale :cooldown))))))

;;; The gather's tell: a cold lamp swelling, frost motes drawn in toward her chest.

(defun update-gather (hag dt)
  (let* ((gathering (gathering-nova-p hag))
         (k (if gathering (min 1.0 (/ (attack-time hag) (attack-hit-time hag))) 0.0))
         (lamp (gather-lamp hag)))
    (when (and gathering (null lamp))
      (setf lamp (setf (gather-lamp hag) (attach-glow hag (vec 0 0 0) *hag-gather-light-radius*))))
    (when lamp
      (let ((color (color lamp)))
        (setf (vx color) (* k (vx *hag-gather-light*))
              (vy color) (* k (vy *hag-gather-light*))
              (vz color) (* k (vz *hag-gather-light*)))))
    (when gathering
      (decf (mote-timer hag) dt)
      (loop while (<= (mote-timer hag) 0.0)
            do (incf (mote-timer hag) (/ 1.0 *hag-gather-motes*))
               (let* ((loc (location hag))
                      (a (random (* 2 pi)))
                      (r (+ (first *hag-gather-ring*)
                            (random (- (second *hag-gather-ring*) (first *hag-gather-ring*)))))
                      (from (vec (+ (vx loc) (* r (cos a))) (+ (vy loc) 0.2 (random 1.4)) (+ (vz loc) (* r (sin a)))))
                      (chest (vec (vx loc) (+ (vy loc) (* 0.6 (sprite-height hag))) (vz loc))))
                 (spray-sparks from (v- chest from) 1 :ramp :frost :speed '(3.0 4.0) :spread 0.05))))))

(define-handler (rime-hag tick :after) (dt)
  (unless (frozen-p)
    (run-cooldowns rime-hag dt)
    (setf (wary rime-hag) (max 0.0 (- (wary rime-hag) dt)))
    (update-gather rime-hag dt))
  (update-blizzard rime-hag dt))

(defmethod leave :after ((hag rime-hag) container)
  (declare (ignore container))
  (douse-blizzard hag)
  (when (gather-lamp hag)
    (remove-lamp (gather-lamp hag))
    (setf (gather-lamp hag) NIL)))

;;; The blizzard (from level 3 of a run, `:blizzard' in its abilities): a storm of snow round her,
;;; *BLIZZARD-RADIUS* across, for *BLIZZARD-TIME*. Its wind bends every projectile but hers flying
;;; through it (WIND-TURN, spells.lisp), so one from across it goes wide and one from close in
;;; strikes, and it holds back her foes inside it (WIND-SLOW): close in to hit her and she walks in
;;; on you with the nova. It goes with her, and dies down with her. All that shows of it is snow:
;;; hundreds of flakes in the spark pool (sparks.lisp) carried round her by its wind (WIND-CARRY),
;;; streaks as long as their speed and a few specks, thinning out toward its edge so it has none.

(defun blizzard-radius (hag)
  (if (typep hag 'boss) (* *blizzard-radius* *blizzard-boss-scale*) *blizzard-radius*))

(defun blizzard-strength (hag)
  "0 (none) to 1 (full): rising over *BLIZZARD-FORM*, dying down over its last *BLIZZARD-FADE*."
  (let ((left (blizzard hag)))
    (if (<= left 0.0)
        0.0
        (max 0.0 (min 1.0
                      (/ (- *blizzard-time* left) *blizzard-form*)
                      (/ left *blizzard-fade*))))))

(defun in-blizzard-p (hag point)
  "True if POINT is inside HAG's blizzard."
  (let* ((c (blizzard-centre hag))
         (h (- (vy point) (vy c))))
    (and (< -0.5 h *blizzard-height*)
         (let ((dx (- (vx point) (vx c)))
               (dz (- (vz point) (vz c)))
               (r (blizzard-radius hag)))
           (< (+ (* dx dx) (* dz dz)) (* r r))))))

(defmethod wind-turn ((hag rime-hag) projectile)
  (let ((k (blizzard-strength hag)))
    (if (and (< 0.0 k)
             (not (eq hag (caster projectile)))
             (in-blizzard-p hag (location projectile)))
        (* k *blizzard-turn*)
        0.0)))

(defmethod wind-slow ((hag rime-hag) actor)
  (if (and (< 0.5 (blizzard-strength hag))
           (not (eq hag actor))
           (hostile-p hag actor)
           (in-blizzard-p hag (body-feet actor)))
      *blizzard-slow*
      1.0))

(defmethod wind-carry ((hag rime-hag) x y z speed dt)
  (let ((k (blizzard-strength hag)))
    (when (< 0.0 k)
      (let* ((c (blizzard-centre hag))
             (rx (- x (vx c)))
             (rz (- z (vz c)))
             (h (- y (vy c)))
             (r2 (+ (* rx rx) (* rz rz)))
             (reach (* *blizzard-flake-reach* (blizzard-radius hag))))
        (when (and (< -0.5 h (+ 0.5 *blizzard-height*)) (< r2 (* reach reach)))
          ;; Round her the way it turns projectiles, at the flake's speed: an exact turn about her
          ;; feet, so the flakes keep their circles.
          (let* ((r (max 0.4 (sqrt r2)))
                 (a (/ (* k *blizzard-flake-speed* speed dt) r))
                 (ca (cos a)) (sa (sin a)))
            (values (- (- (* ca rx) (* sa rz)) rx)
                    (- (+ (* sa rx) (* ca rz)) rz)
                    T)))))))

(defun raise-blizzard (hag)
  (setf (blizzard hag) *blizzard-time*)
  (play-sound :gust-cast (location hag)))

(defun blizzard-up-p (hag)
  "True while HAG's blizzard's wind blows and its roar sounds."
  (and (find hag *winds*) T))

(defun light-blizzard (hag)
  "Set HAG's blizzard's wind blowing and its roar sounding (again after a load)."
  (setf (blizzard-sound hag) (start-loop :tornado (blizzard-centre hag) 0.0))
  (add-wind hag))

(defun douse-blizzard (hag)
  "Still HAG's blizzard's wind and roar; its flakes fall out of it."
  (remove-wind hag)
  (setf (blizzard-sound hag) (stop-loop (blizzard-sound hag))))

(defun blow-snow (hag dt)
  "Throw up the flakes HAG's blizzard owes the pool for DT seconds, as many as it is strong, round
her, thinning out toward its edge."
  (when *spark-pool*
    (let* ((c (blizzard-centre hag))
           (radius (* *blizzard-flake-reach* (blizzard-radius hag)))
           (ramp (spark-ramp-index :snow))
           (rises (pool-rises *spark-pool*)))
      (incf (flake-debt hag) (* dt *blizzard-flakes* (blizzard-strength hag)))
      (loop while (<= 1.0 (flake-debt hag))
            do (decf (flake-debt hag))
               (let* ((r (* radius (expt (random 1.0) *blizzard-flake-spread*)))
                      (a (random (float (* 2 pi) 0f0)))
                      (x (+ (vx c) (* r (cos a))))
                      (y (+ (vy c) 0.1 (random *blizzard-height*)))
                      (z (+ (vz c) (* r (sin a)))))
                 (unless (solid-at x y z)
                   (let ((i (spawn-spark 7 ramp x y z 0.0 0.0 0.0 (range-random *blizzard-flake-life*)
                                         :chip (if (< (random 1.0) *blizzard-flake-chips*) 2 1)
                                         :ambient T)))
                     (when i
                       (setf (aref rises i) (range-random *blizzard-flake-speeds*))))))))))

(defun update-blizzard (hag dt)
  "Run DT seconds of HAG's blizzard: count it down (down to its fade at her death), keep it on her
feet, its curtains as tall and bright as it is strong, and its snow blowing."
  (let ((frozen (frozen-p)))
    (when (and (dead hag) (< *blizzard-fade* (blizzard hag)))
      (setf (blizzard hag) *blizzard-fade*))
    (unless frozen
      (setf (blizzard hag) (max 0.0 (- (blizzard hag) dt))))
    (cond ((and (< 0.0 (blizzard hag)) (container hag))
           (let ((feet (body-feet hag))
                 (c (blizzard-centre hag)))
             (setf (vx c) (vx feet) (vy c) (vy feet) (vz c) (vz feet))
             (unless (blizzard-up-p hag)
               (light-blizzard hag))
             (move-loop (blizzard-sound hag) c (* (blizzard-strength hag) *blizzard-volume*))
             (unless frozen
               (blow-snow hag dt))))
          ((blizzard-up-p hag)
           (douse-blizzard hag)))))

(defun preload-hag (scene)
  "Load what a rime hag throws mid-game: the frost look's flight and burst."
  (preload (make-instance 'fx-sprite :animation (find-fx-animation 'frost-flight)) scene)
  (preload (make-instance 'fx-sprite :animation (find-fx-animation 'frost-burst)) scene))

;;; As a boss (boss.lisp): the Winter Crone, her nova reaching 7 m. Its powers' attacks show her
;;; cast. And as an elite (elite.lisp).

(define-shader-entity hag-boss (boss rime-hag) ())
(define-shader-entity elite-hag (elite rime-hag) ())

(defmethod power-animation ((boss hag-boss)) 'hag-cast)
