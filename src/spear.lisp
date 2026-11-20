(in-package #:hexmaw)

;;; The spear, held in both hands, so no shield. Against the sword it reaches further
;;; and staggers more often, but its thrust is slower and its arc narrow, so it hits
;;; only what the player is looking at. It is swung like the sword (SWING-TIME,
;;; sword.lisp), its blow landing at full extension.
;;;
;;; Its sprite is the sword's, drawn from its own strip (data/sprites/spear): a 4-frame
;;; idle loop followed by an 8-frame thrust: rest, drawing back, drawn back, the thrust,
;;; full extension, pulling back, recovery, rest.

(define-fx-animation spear "sprites/spear/spear" :fps 5 :loop T)

;;; A thrust that lands on a creature charging at the player through the air (CHARGING-P,
;;; creature.lisp: a leap or pounce, a harpy's dive) is a counter: the charge runs onto the
;;; point. It hits harder, always flinches (a boss only rolls with the thrust's COUNTER-PAIN-BONUS),
;;; shows the jolt and does its kind's reaction (IMPALE: a leaper drops out of the air with no
;;; quake). A knight's shield takes it as any thrust. The right button (the shield's action, :BLOCK)
;;; sweeps with the haft: the bash's rules (a stagger only in a wind-up, poise), but every creature
;;; in a wide arc, to clear space, and no enchantment.
;;;
;;; Its strip: the 4 idle frames, the thrust's 8 (rest, drawing back, drawn back, the thrust, full
;;; extension, pulling back, recovery, rest), the jolt of a counter, then the sweep's 4. It is placed
;;; by its aim, the spearhead's point at full extension (art/spear/extend-1.png's tip, placed by
;;; art/spear/spear-frames.txt), which goes on the screen's middle: held in both hands, the spear
;;; points where the player looks.
(define-weapon :spear
  :title "Spear" :icon 2 :strip spear :frames (:idle 4 :swing 4 :jolt 12 :alternate 13) :aim 187
  :loot T :loot-strip loot-spear :forge-noun "Point"
  :sounds (:draw :draw-spear)
  ;; Further than the sword and staggering more often, but slower and in a narrow arc: it hits
  ;; only what the player looks at. It lands on frame 4, full extension.
  :swing (thrust :name :spear :frame-times (0.05 0.08 0.06 0.05 0.12 0.10 0.12 0.10) :hit-frame 4
                 :reach 3.5 :arc 0.3 :damage (8 14) :knockback 2.5 :pain-bonus 35
                 :sound :spear-thrust :verb "thrust"
                 :counter-damage (18 26) :counter-sparks 12 :counter-knockback 5.0
                 :counter-pain-bonus 100 :jolt-time 0.25 :brace-recoil 2.5 :brace-hit-stop 0.08
                 :wall (:sparks 8 :grit 3 :speed (3.0 7.5) :spread 0.5
                        :sound :blade-hit-stone :wood-sound :blade-hit-wood)
                 ;; The point at full extension, strip frame 8.
                 :tip (:spear 165 18))
  ;; The haft's sweep: wound up to the right, the sweep (where it lands), the follow-through,
  ;; back. A flanker's side is in its arc too.
  :alternate (sweep :name :haft :frame-times (0.1 0.08 0.12 0.12) :hit-frame 1
                    :reach 1.8 :arc 1.4 :damage (2 4) :knockback 6.0 :stamina 15.0 :sound :haft-sweep
                    :wall (:sparks 0 :grit 5 :speed (1.5 4.0) :spread 1.0
                           :sound :bone-hit :wood-sound :bone-hit)
                    ;; The spearhead leading the sweep, strip frame 14, its rightmost pixel.
                    :tip (:spear 337 102)))

;; A thrust's blow is a counter on a creature charging at the player; from the front, where its
;; shield covers it, it stops a knight's shield charge instead (BRACE-AGAINST-CHARGE).
(defmethod swing-strike (player (blow thrust) target)
  (cond ((and (charging-p target) (not (shielded-p target (feet player))))
         (spear-counter player blow target))
        ((and (shield-charging-p target) (shielded-p target (feet player)))
         (brace-against-charge player blow target))
        (T (call-next-method))))

(defun brace-against-charge (player thrust knight)
  "PLAYER's THRUST met KNIGHT's shield charge head-on: the point takes the shield, and the charge
stops dead, the knight reeling with its guard down (knight.lisp). No harm to it."
  (setf (weapon-jolt player) (blow-jolt-time thrust))
  (play-sound :bash-glance (location knight))
  (play-sound :maul-guard-break (location knight))
  (shield-sparks knight 16)
  (reel-from-charge knight :spear)
  (shove-player player (location knight) (blow-brace-recoil thrust))
  (hit-stop (blow-brace-hit-stop thrust)))

(defun spear-counter (player thrust target)
  "TARGET charged onto PLAYER's THRUST: skewered, flinching whatever the roll, and its charge
broken (IMPALE)."
  (let ((feet (feet player)))
    (setf (weapon-jolt player) (blow-jolt-time thrust))
    (play-sound :spear-impale (location target))
    (strike-sparks target feet (blow-counter-sparks thrust))
    (impale target)
    (hurt target (roll (blow-counter-damage thrust)) :from feet :by player
                                                     :pain-bonus (blow-counter-pain-bonus thrust)
                                                     :force-pain (not (typep target 'boss)))
    (push-creature target (v- (location target) feet) (float (blow-counter-knockback thrust) 0f0))
    (enchant-strike player (weapon player) target)))

(defmethod start-blow ((blow sweep) player)
  (start-alternate player blow))

(defmethod bash-strike (player (blow sweep))
  (sweep-hit player blow))

(defun sweep-hit (player sweep)
  "Sweep the haft (the blow SWEEP) through every creature in its arc: each shoved, staggered only
in the wind-up of an attack and not poised (BASH-HIT's rules). One a shield covers glances off it,
and the player reels back once. With no one in it, it strikes the wall."
  (let ((feet (feet player))
        (glanced NIL)
        (struck NIL))
    (loop for c across *creatures*
          when (and (not (dead c)) (blow-reaches-p player c (blow-reach sweep) (blow-arc sweep)))
            do (setf struck T)
               (if (shielded-p c feet)
                   (progn
                     (play-sound :bash-glance (location c))
                     (block-hit c)
                     (setf glanced c))
                   (let* ((poised (< 0.0 (bash-poise c)))
                          (bonus (if (and (not poised) (winding-up-p c)) *bash-pain-bonus* -100)))
                     (setf (bash-poise c) *bash-poise-time*)
                     (play-sound :bash-hit (location c))
                     (hurt c (roll (blow-damage sweep)) :from feet :pain-bonus bonus :by player)
                     (push-creature c (v- (location c) feet)
                                    (float (* (blow-knockback sweep) (if poised *poised-bash-knockback* 1.0)) 0f0)))))
    (when glanced
      (shove-player player (location glanced) *bash-recoil*)
      (break-guard player *bash-recoil-guard*))
    ;; With no one in its arc, the haft strikes the wall the crosshair meets (WALL-STRIKE, sword.lisp).
    (unless struck
      (wall-strike player sweep))))

(defmethod blow-lines ((blow thrust))
  (append (call-next-method) (list "A thrust counters a leap or dive")))

(defmethod second-blow-lines ((blow sweep))
  (list "Right button: sweep, shove all near"))
