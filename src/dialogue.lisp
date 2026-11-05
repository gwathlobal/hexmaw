(in-package #:hexmaw)

;;; Talking to the townsfolk (townsfolk.lisp): E opens a DIALOGUE-PANEL, a menu over the frozen
;;; world (*GAME-STATE* :TALK), with the townsperson's name, what they say, and a button for
;;; each thing they offer. What that is comes from their role and the settlement (settlement.lisp):
;;; the shopkeeper sells and buys potions and sells the glyphs the player doesn't know, the priest
;;; heals, restores mana and blesses, the trainer raises the player's maxima, the quest-giver offers
;;; a quest into the wing, and a guard takes fines and, for the Free Company, bribes. A click acts
;;; and re-shows the panel (*MENU-REFRESH*), since an Alloy panel lays itself out once.

(defvar *talk-page* :main
  "Which page of the talk is up: :MAIN, or :GLYPHS for the shopkeeper's glyphs.")
(defvar *talk-note* NIL "A line under the greeting after something was tried: \"You can't afford that.\"")

(defparameter *training-steps* '(:health 10 :mana 10 :stamina 15) "What one step of training adds to each maximum.")
(defparameter *training-limit* 3 "Steps of each the trainer gives.")
(defparameter *training-step-cost* 0.6 "How much dearer each step is than the one before, as a share of the first.")

(defun start-talk (townsfolk &optional (page :main))
  "Open the talk with TOWNSFOLK, who turns to the player."
  (when (and (eq *game-state* :playing) *player*)
    (unless (dead townsfolk)
      (face-player townsfolk))
    (setf *talk-target* townsfolk
          *talk-page* page
          *talk-note* NIL
          *game-state* :talk
          ;; Another townsperson's panel may still be up.
          *menu-refresh* T)
    (release-mouse *player*)))

(defun end-talk ()
  (when (eq *game-state* :talk)
    (setf *game-state* :playing
          *talk-target* NIL)
    (when *player* (capture-mouse *player*))))

(defun talk-note (format-control &rest args)
  "Say FORMAT-CONTROL with ARGS under the greeting, and show the panel again."
  (setf *talk-note* (apply #'format NIL format-control args)
        *menu-refresh* T))

(defun spend (amount)
  "Take AMOUNT gold from the player, or say they can't afford it. True if it was paid."
  (cond ((<= amount (gold *player*))
         (decf (gold *player*) amount)
         (setf *menu-refresh* T)
         T)
        (T (talk-note "You can't afford that: ~d gold." amount)
           NIL)))

;;; Services.

(defun refusing-p ()
  "True if the townsfolk offer the player nothing: the watch hunts them, or they sacked the town."
  (and *settlement* (or (settlement-hostile *settlement*) (eq (sacked-by *settlement*) :player))))

(defun buy-item (kind)
  (let ((stock (settlement-stock *settlement*)))
    (cond ((<= (getf stock kind 0) 0) (talk-note "Sold out."))
          ((zerop (give-item *player* kind)) (talk-note "You've no room for it."))
          ((not (spend (price kind))) (take-item *player* kind 1))
          (T (decf (getf (settlement-stock *settlement*) kind))
             (talk-note "Bought a ~(~a~)." (item-property kind :name))))))

(defun sell-item (kind)
  (when (take-item *player* kind 1)
    (let ((paid (max 1 (round (* *sell-share* (price kind))))))
      (incf (gold *player*) paid)
      (incf (getf (settlement-stock *settlement*) kind 0))
      (talk-note "Sold a ~(~a~) for ~d gold." (item-property kind :name) paid))))

(defun shop-glyphs (player)
  "The glyphs the shop has for PLAYER: every one teaching an effect they don't know yet."
  (remove-if (lambda (kind) (member (pickup-property kind :teaches) (known-effects player)))
             (glyph-kinds)))

(defun glyph-price () (price :glyph))

(defun buy-glyph (kind)
  "Teach the player glyph KIND for its price: knowledge, so it takes no room in the bag."
  (when (spend (glyph-price))
    (learn-glyph *player* kind)
    (talk-note "You learn the glyph of ~a. Forge it at an altar." (pickup-property kind :name))))

(defun show-talk-page (page)
  (setf *talk-page* page
        *talk-note* NIL
        *menu-refresh* T))

(defun loot-item (kind)
  "Take one from a dead shopkeeper's stall."
  (let ((stock (settlement-stock *settlement*)))
    (cond ((<= (getf stock kind 0) 0) (talk-note "There's none left."))
          ((zerop (give-item *player* kind)) (talk-note "You've no room for it."))
          (T (decf (getf (settlement-stock *settlement*) kind))
             (talk-note "Took a ~(~a~)." (item-property kind :name))))))

(defun heal-price () (price :heal :base (* (getf *base-prices* :heal) (- (max-health *player*) (health *player*)))))
(defun mana-price () (price :mana :base (* (getf *base-prices* :mana) (- (max-mana *player*) (mana *player*)))))

(defun priest-heal ()
  (when (spend (heal-price))
    (setf (health *player*) (max-health *player*))
    (flash-resource *player* :health)
    (talk-note "Your wounds close.")))

(defun priest-restore-mana ()
  (when (spend (mana-price))
    (setf (mana *player*) (max-mana *player*))
    (flash-resource *player* :mana)
    (talk-note "Your mind clears.")))

(defun priest-bless ()
  (when (spend (price :bless))
    (setf (blessed *player*) *bless-time*)
    (talk-note "Blessed: every blow does ~d% less to you for ~d minutes of play, down the stairs too."
               (round (* 100 (- 1 *bless-scale*))) (round *bless-time* 60))))

(defun blessing-scale (player)
  "What a blow does to PLAYER, as a share of its damage: less while blessed."
  (if (< 0 (blessed player)) *bless-scale* 1.0))

(defun training-price (stat)
  (let ((steps (getf (settlement-trained *settlement*) stat 0)))
    (price :training :base (* (getf *base-prices* :training) (+ 1 (* *training-step-cost* steps))))))

(defun train (stat)
  (let ((steps (getf (settlement-trained *settlement*) stat 0))
        (amount (getf *training-steps* stat)))
    (cond ((<= *training-limit* steps) (talk-note "That's all I can teach you of that."))
          ((spend (training-price stat))
           (incf (getf (settlement-trained *settlement*) stat 0))
           (ecase stat
             (:health (incf (max-health *player*) amount) (incf (health *player*) amount))
             (:mana (incf (max-mana *player*) amount) (incf (mana *player*) amount))
             (:stamina (incf (max-stamina *player*) amount) (incf (stamina *player*) amount)))
           (talk-note "Your ~(~a~) rises by ~d." stat amount)))))

(defun pay-fine ()
  (when (spend (settlement-fine *settlement*))
    (calm-watch)
    (talk-note "Paid. Mind yourself.")))

(defun refuse-fine ()
  (end-talk)
  (watch-turns-hostile "Then you'll pay in blood!"))

(defun asking-fine-p (&optional (who *talk-target*))
  "True while WHO, the one talked to, is a guard asking the fine: there, leaving is refusing."
  (and who (typep who 'guard) (not (dead who)) *settlement* (settlement-fine *settlement*)))

(defun escape-talk ()
  "Esc while talking: walk off, which refuses a fine being asked."
  (if (asking-fine-p) (refuse-fine) (end-talk)))

(defun bribe-price ()
  (max 1 (round (* *bribe-share* (or (settlement-fine *settlement*) (fine-amount))))))

(defun pay-bribe ()
  (when (spend (bribe-price))
    (calm-watch)
    (talk-note "Never saw a thing.")))

;;; The panel.

(defclass dialogue-panel (menu-panel) ())

(defparameter *title-char-width* 23
  "UI units a character of a panel's title takes, about, in the menu font (Jersey 15 at 32).")

(defmethod panel-width ((panel dialogue-panel))
  ;; Wide enough for the title: "Corwin the Lamp, the quest giver" ran past 640.
  (max 640 (+ 24 (* *title-char-width* (length (panel-title panel))))))

(defmethod panel-title ((panel dialogue-panel))
  (let ((who *talk-target*))
    (cond ((null who) "")
          ((dead who) "An abandoned stall")
          (T (let ((title (copy-seq (townsfolk-title who))))
               (when (plusp (length title)) (setf (char title 0) (char-upcase (char title 0))))
               title)))))

(defun talk-greeting (who)
  (cond ((dead who) "The stall's goods lie where they were left.")
        ((and (typep who 'guard) (settlement-fine *settlement*))
         (format NIL "That's ~d gold for your trouble." (settlement-fine *settlement*)))
        ((and (typep who 'guard) (settlement-hostile *settlement*)) "You've a nerve.")
        ((eq (sacked-by *settlement*) :player) "Murderer. Get away from me.")
        ((settlement-hostile *settlement*) "Not while the watch wants you.")
        ((eq (settlement-condition *settlement*) :sacked)
         (if (typep who 'commoner) "They came up out of the undercroft. Few of us got away." "Few of us left. I'll sell what's left, if you've coin."))
        ((and (eq (settlement-condition *settlement*) :besieged) (typep who '(or guard commoner)))
         "The undercroft keeps coming at the gates. Watch yourself.")
        ((typep who 'guard) (format NIL (greeting who) (faction-property :name)))
        ((and (typep who 'shopkeeper) (eq *talk-page* :glyphs))
         (if (shop-glyphs *player*)
             "Glyphs, carved by the deep folk. Learn one, and the spellforge works its effect for you."
             "You know every glyph I've ever had."))
        (T (greeting who))))

(defparameter *dialogue-wrap* 45
  "Most characters on one row of the dialogue's text: a row holds about 48 of the menu font's
(Jersey 15) at the panel's width, and the font isn't fixed-width.")

(defun prose-lines (text &optional label)
  "TEXT, after LABEL and a colon, as stat rows of text alone, left-aligned and wrapped at
*DIALOGUE-WRAP* (WRAP-TEXT, hud.lisp); no rows for no text."
  (let ((text (if label (format NIL "~a: ~a" label text) text)))
    (unless (string= text "")
      (loop for row in (wrap-text text *dialogue-wrap*)
            collect (list row "")))))

(defmethod panel-lines ((panel dialogue-panel))
  (let ((who *talk-target*))
    (when who
      (append (prose-lines (talk-greeting who))
              (when (and (typep who 'guard) (not (dead who)))
                (prose-lines (faction-property :rule-text) "The rule"))
              (when (and (typep who 'quest-giver) (settlement-quest *settlement*))
                (prose-lines (quest-summary (settlement-quest *settlement*)) "Quest"))
              (when *talk-note* (prose-lines *talk-note*))
              (list (list "Your gold" (princ-to-string (gold *player*)))
                    (list "Standing" (standing-word (faction-reputation *player* (settlement-faction *settlement*)))))))))

(defun standing-word (reputation)
  (cond ((<= 50 reputation) "honoured")
        ((<= 15 reputation) "trusted")
        ((< -15 reputation) "a stranger")
        ((< -50 reputation) "distrusted")
        (T "hated")))

(defun row (label action &rest args)
  "A button: LABEL, formatted with ARGS, that calls ACTION, a function name or closure."
  (list (apply #'format NIL label args) action))

(defmethod panel-buttons ((panel dialogue-panel))
  (let ((who *talk-target*) (s *settlement*))
    (append
     (cond
       ((null who) ())
       ((dead who)
        (loop for kind in *shop-goods*
              collect (row "Take a ~(~a~) (~d left)" (lambda () (loot-item kind)) (item-property kind :name)
                           (getf (settlement-stock s) kind 0))))
       ((typep who 'guard)
        (cond ((settlement-fine s)
               (append (list (row "Pay the fine (~d gold)" 'pay-fine (settlement-fine s)))
                       (when (faction-property :bribable)
                         (list (row "Slip them something instead (~d gold)" 'pay-bribe (bribe-price))))
                       (list (row "Refuse" 'refuse-fine))))
              ((bribable-p who) (list (row "Buy them off (~d gold)" 'pay-bribe (bribe-price))))))
       ((refusing-p) ())
       ((and (typep who 'shopkeeper) (eq *talk-page* :glyphs))
        (append (loop for kind in (shop-glyphs *player*)
                      collect (let ((kind kind))
                                (row "Glyph of ~a, ~a: ~d gold" (lambda () (buy-glyph kind))
                                     (pickup-property kind :name) (pickup-property kind :about) (glyph-price))))
                (list (row "Back" (lambda () (show-talk-page :main))))))
       ((typep who 'shopkeeper)
        (append (let ((glyphs (shop-glyphs *player*)))
                  (when glyphs
                    (list (row "Glyphs for the spellforge (~d you don't know)" (lambda () (show-talk-page :glyphs))
                               (length glyphs)))))
                (loop for kind in *shop-goods*
                      collect (row "Buy a ~(~a~): ~d gold (~d left)" (lambda () (buy-item kind)) (item-property kind :name)
                                   (price kind) (getf (settlement-stock s) kind 0)))
                (loop for kind in *shop-goods*
                      when (< 0 (kind-total *player* kind))
                        collect (row "Sell a ~(~a~): ~d gold" (lambda () (sell-item kind)) (item-property kind :name)
                                     (max 1 (round (* *sell-share* (price kind))))))))
       ((typep who 'priest)
        (append (when (< (health *player*) (max-health *player*))
                  (list (row "Heal my wounds: ~d gold" 'priest-heal (heal-price))))
                (when (< (mana *player*) (max-mana *player*))
                  (list (row "Restore my mana: ~d gold" 'priest-restore-mana (mana-price))))
                (list (row "~:[Bless me~;Renew my blessing~] (~d% less harm, ~d min): ~d gold" 'priest-bless
                           (plusp (blessed *player*)) (round (* 100 (- 1 *bless-scale*))) (round *bless-time* 60)
                           (price :bless)))))
       ((typep who 'trainer)
        (loop for (stat amount) on *training-steps* by #'cddr
              collect (let ((stat stat))
                        (if (<= *training-limit* (getf (settlement-trained s) stat 0))
                            (row "~:(~a~): fully trained" (lambda () (train stat)) stat)
                            (row "Train ~(~a~) (+~d): ~d gold" (lambda () (train stat)) stat amount (training-price stat))))))
       ((typep who 'quest-giver) (quest-buttons s)))
     ;; A guard asking a fine has Refuse instead, and Esc refuses (ESCAPE-TALK).
     (unless (asking-fine-p who)
       (list (row "Leave" 'end-talk))))))

;;; Quests: the quest-giver's one quest, into the settlement's own wing, claimed back in town.
;;; It is drawn the first time they are asked (ENSURE-QUEST), from the settlement's seed and the
;;; level as built, and kept on the settlement as a plist: :KIND, :STATE (:OFFERED, :ACTIVE,
;;; :CLAIMED), :REWARD and what its kind needs. A relic waits, hidden, on a spot deep in the wing
;;; (QUEST-PICKUP, pickups.lisp) until the quest is taken; a bounty counts the dead of one kind; holding
;;; the gate counts raids beaten off (townsfolk.lisp).

(defparameter *quest-rewards* '(:relic 110 :bounty 30 :hold-gate 140)
  "Gold a quest pays at the first depth: the relic and holding the gate all told, a bounty per head.")
(defparameter *quest-reputation* 15 "Standing a quest done earns with the settlement's faction.")
(defparameter *bounty-most* 3 "Most heads a bounty asks for.")
(defparameter *gate-raids* 2 "Raids the gate must be held through.")

(defun quest-relic ()
  "The relic waiting in the wing, or NIL if there was no spot for one."
  (find-if (lambda (p) (typep p 'quest-pickup)) *pickups*))

(defun bounty-target ()
  "The kind of monster the wing has most of alive, and how many: a bounty's quarry."
  (let ((counts ()))
    (loop for c across *creatures*
          when (and (monster-p c) (not (dead c)) (not (in-settlement-p (location c))))
            do (incf (getf counts (type-of c) 0)))
    (loop with best = NIL and most = 0
          for (kind n) on counts by #'cddr
          when (< most n) do (setf best kind most n)
          finally (return (values best most)))))

(defun dead-count (kind)
  (count-if (lambda (c) (and (typep c kind) (monster-p c) (dead c))) *creatures*))

(defun ensure-quest (settlement)
  "The settlement's quest, drawn now if it has none yet."
  (or (settlement-quest settlement)
      (setf (settlement-quest settlement)
            (let* ((random (sb-ext:seed-random-state (logxor (settlement-seed settlement) #x9E57)))
                   (scale (gold-scale (settlement-depth-of settlement)))
                   (kinds (append (when (quest-relic) '(:relic))
                                  (when (bounty-target) '(:bounty))
                                  (when (eq (built-condition settlement) :besieged) '(:hold-gate)))))
              (when kinds
                (let ((kind (nth (random (length kinds) random) kinds)))
                  (ecase kind
                    (:relic (list :kind :relic :state :offered :reward (round (* scale (getf *quest-rewards* :relic)))))
                    (:bounty (multiple-value-bind (target n) (bounty-target)
                               (let ((n (min n *bounty-most*)))
                                 (list :kind :bounty :state :offered :target target :count n
                                       :reward (round (* scale n (getf *quest-rewards* :bounty)))))))
                    (:hold-gate (list :kind :hold-gate :state :offered :count *gate-raids*
                                      :reward (round (* scale (getf *quest-rewards* :hold-gate))))))))))))

(defun quest-progress (quest)
  "How far QUEST has got, and how far it must."
  (ecase (getf quest :kind)
    (:relic (values (min 1 (kind-total *player* :relic)) 1))
    (:bounty (values (min (getf quest :count) (- (dead-count (getf quest :target)) (getf quest :baseline 0)))
                     (getf quest :count)))
    (:hold-gate (values (min (getf quest :count) (- (raids-held *settlement*) (getf quest :baseline 0)))
                        (getf quest :count)))))

(defun quest-done-p (quest)
  (multiple-value-bind (now goal) (quest-progress quest) (<= goal now)))

(defun quest-summary (quest)
  (let ((what (ecase (getf quest :kind)
                (:relic "Bring back the reliquary lost in the undercroft")
                (:bounty (format NIL "Kill ~d ~(~a~)~p in the undercroft" (getf quest :count)
                                 (substitute #\Space #\- (string (getf quest :target))) (getf quest :count)))
                (:hold-gate (format NIL "Hold the gates through ~d raids" (getf quest :count))))))
    (case (getf quest :state)
      (:offered (format NIL "~a. ~d gold." what (getf quest :reward)))
      (:active (multiple-value-bind (now goal) (quest-progress quest)
                 (format NIL "~a: ~d of ~d." what now goal)))
      (T (format NIL "~a: done." what)))))

(defun accept-quest ()
  (let ((quest (settlement-quest *settlement*)))
    (setf (getf quest :state) :active)
    (case (getf quest :kind)
      (:bounty (setf (getf quest :baseline) (dead-count (getf quest :target))))
      (:hold-gate (setf (getf quest :baseline) (raids-held *settlement*))))
    (setf (settlement-quest *settlement*) quest)
    (talk-note "Good. Come back when it's done.")))

(defun claim-quest ()
  (let ((quest (settlement-quest *settlement*)))
    (when (eq :relic (getf quest :kind))
      (take-item *player* :relic 1))
    (setf (getf quest :state) :claimed
          (settlement-quest *settlement*) quest)
    (incf (gold *player*) (getf quest :reward))
    (adjust-reputation *player* (settlement-faction *settlement*) *quest-reputation*)
    (talk-note "As promised: ~d gold." (getf quest :reward))))

(defun quest-buttons (settlement)
  (let ((quest (ensure-quest settlement)))
    (case (and quest (getf quest :state))
      ((NIL) (setf *talk-note* (or *talk-note* "Nothing for you today.")) ())
      (:offered (list (row "Take the job" 'accept-quest)))
      (:active (if (quest-done-p quest)
                   (list (row "It's done (~d gold)" 'claim-quest (getf quest :reward)))
                   ()))
      (T ()))))
