(in-package #:hexmaw)

;;; Music, through Harmony (trial-harmony, set up by MAIN). In play the MUSIC-DIRECTOR,
;;; entered by setup-scene, plays the *MUSIC-PLAYLIST* at random, one track at a time,
;;; crossfading to another every *MUSIC-TRACK-TIME* of play (never the one playing); the
;;; main menu, the death screen and the victory screen have tracks of their own
;;; (*SCREEN-MUSIC*), which start from the top whenever their screen comes up. MUSIC-WANTED
;;; says which track the game state wants and MUSIC-TARGET how loud: full in play, the
;;; automap, the inventory and the screens, ducked under the pause menu, silent on the
;;; loading screen. A playlist track faded out pauses, and picks up where it paused when it
;;; comes round again. (Music that followed the fighting, combat while a monster hunted the
;;; player, swapped every few seconds, since monsters notice and lose the player that often.)
;;;
;;; Every track is started once, when its voice first appears, and from then on only
;;; paused and unpaused (HARMONY:PAUSED-P, a flag on the voice's unpacker that the mixing
;;; thread reads: paused, its source stops decoding and it outputs silence). Never
;;; HARMONY:STOP and PLAY again: PLAY only queues the voice's connection for the mixing
;;; thread, while STOP decides on the game thread, from whether it is connected yet, to do
;;; nothing. A stop right after a start (a scene rebuilt into a fight, picking a fresh
;;; track and then switching at once) left a voice connected that the director believed
;;; stopped, and its next start left it silent for good. Each track is a seamless loop, cut
;;; from a longer generated piece (audio/music/, tools/gen_music.py and tools/make_loop.py)
;;; or composed as notes and rendered through a GM soundfont (tools/compose_explore.py,
;;; explore-2; tools/compose_combat.py, combat-5; tools/compose_title.py, the main menu's),
;;; encoded to Ogg Vorbis in data/music/. The Settings sliders set *MUSIC-VOLUME* and
;;; *SOUND-VOLUME*, which the director applies to Harmony's mixers.

(defvar *music-volume* 0.5 "Volume of the music mixer, 0 to 1 (Settings).")
(defvar *sound-volume* 1.0 "Volume of the sound effect and speech mixers, 0 to 1 (Settings).")

(defparameter *music-pause-volume* 0.35 "Share of the music's volume under the pause menu.")
(defparameter *music-fade-time* 2.0 "Seconds a fade between silence and full takes.")
(defparameter *music-track-time* 180.0
  "Seconds of play before the music moves on to another track of the playlist.")

(define-asset (hexmaw music-explore-1) org.shirakumo.fraf.trial.harmony:sound #p"music/explore-1.ogg" :repeat T :mixer :music)
(define-asset (hexmaw music-explore-2) org.shirakumo.fraf.trial.harmony:sound #p"music/explore-2.ogg" :repeat T :mixer :music)
(define-asset (hexmaw music-explore-3) org.shirakumo.fraf.trial.harmony:sound #p"music/explore-3.ogg" :repeat T :mixer :music)
(define-asset (hexmaw music-combat-1) org.shirakumo.fraf.trial.harmony:sound #p"music/combat-1.ogg" :repeat T :mixer :music)
(define-asset (hexmaw music-combat-2) org.shirakumo.fraf.trial.harmony:sound #p"music/combat-2.ogg" :repeat T :mixer :music)
(define-asset (hexmaw music-combat-3) org.shirakumo.fraf.trial.harmony:sound #p"music/combat-3.ogg" :repeat T :mixer :music)
(define-asset (hexmaw music-combat-4) org.shirakumo.fraf.trial.harmony:sound #p"music/combat-4.ogg" :repeat T :mixer :music)
(define-asset (hexmaw music-combat-5) org.shirakumo.fraf.trial.harmony:sound #p"music/combat-5.ogg" :repeat T :mixer :music)
(define-asset (hexmaw music-title) org.shirakumo.fraf.trial.harmony:sound #p"music/title.ogg" :repeat T :mixer :music)
(define-asset (hexmaw music-death) org.shirakumo.fraf.trial.harmony:sound #p"music/death.ogg" :repeat T :mixer :music)

(defparameter *music-playlist*
  '(music-explore-1 music-explore-2 music-explore-3
    music-combat-1 music-combat-2 music-combat-3 music-combat-4 music-combat-5)
  "The tracks (asset names) play draws from at random.")

(defparameter *screen-music*
  '(:title music-title :dead music-death :victory music-combat-4)
  "The track each screen plays, by *GAME-STATE*: the main menu's, the death screen's (the
first explore-2, too much drone to explore to) and the victory screen's.")

(defvar *music-random* (make-random-state T)
  "The music's own random state, so picking tracks leaves the game's rolls alone.")

(defun music-tracks ()
  "Every track, the playlist's and the screens'."
  (remove-duplicates (append *music-playlist* (loop for (nil track) on *screen-music* by #'cddr collect track))))

(defun music-voice (track)
  (// 'hexmaw track))

(defun music-target ()
  "How loud the music should be now, 0 to 1 of the music mixer."
  (case *game-state*
    (:paused *music-pause-volume*)
    (:loading 0.0)
    (T 1.0)))

(defclass music-director (entity listener)
  ((name :initform :music-director)
   (levels :initform NIL :accessor levels
           :documentation "Each track's fade, 0 to 1, as a plist by asset name. NIL until the
first tick, which takes them from the voices, so a scene rebuild doesn't dip a track that
plays on.")
   (current :initform NIL :accessor current
            :documentation "The playlist track play plays, picked on the first tick.")
   (track-time :initform 0.0 :accessor track-time
               :documentation "Seconds of play the current track has had.")
   (wanted :initform NIL :accessor wanted
           :documentation "The track wanted last tick, to see a screen track come up.")
   (applied :initform (cons -1.0 -1.0) :accessor applied
            :documentation "The music and sound volumes last set on the mixers.")))

(defun pick-track (&optional other-than)
  (let ((choices (or (remove other-than *music-playlist*) *music-playlist*)))
    (nth (random (length choices) *music-random*) choices)))

(defun music-wanted (director)
  "The track the game state wants: its screen's, or in play (and on the pause menu, the
automap and the inventory) the playlist's current one; NIL on the loading screen."
  (case *game-state*
    (:loading NIL)
    ((:title :dead :victory) (getf *screen-music* *game-state*))
    (T (or (current director) (setf (current director) (pick-track))))))

(defun apply-volumes (director)
  (let ((applied (applied director)))
    (unless (and (= (car applied) *music-volume*) (= (cdr applied) *sound-volume*))
      (setf (car applied) *music-volume* (cdr applied) *sound-volume*)
      (flet ((set-mixer (name volume)
               (let ((mixer (harmony:segment name harmony:*server* NIL)))
                 (when mixer (setf (mixed:volume mixer) (float volume 0f0))))))
        (set-mixer :music *music-volume*)
        (set-mixer :effect *sound-volume*)
        (set-mixer :speech *sound-volume*)))))

(defun update-playlist (director dt)
  "Move on to another playlist track every *MUSIC-TRACK-TIME* of play."
  (when (and (member *game-state* '(:playing :map :inventory :talk))
             (< *music-track-time* (incf (track-time director) dt)))
    (setf (current director) (pick-track (current director))
          (track-time director) 0.0)))

(defun restart-track (resource)
  "Send RESOURCE's track back to its start, in the mixing thread, which reads its decoder."
  (let ((source (harmony:source (org.shirakumo.fraf.trial.harmony:voice resource))))
    (harmony:with-server (harmony:*server* :synchronize NIL)
      (mixed:seek source 0))))

(defvar *connected-voices* ()
  "The Harmony voices (inside the tracks' Trial resources) started once, paused, and only
paused and unpaused since. It outlives scene rebuilds, so a rebuild's new director never
starts one twice; a voice Trial reallocates (an asset reload) is a new object, started anew.")

(defun connected-voice (resource)
  "RESOURCE's Harmony voice, started paused and silent the first time it is asked for."
  (let ((voice (org.shirakumo.fraf.trial.harmony:voice resource)))
    (unless (member voice *connected-voices*)
      (setf *connected-voices*
            (cons voice (loop for track in (music-tracks)
                              for other = (music-voice track)
                              when (and (allocated-p other)
                                        (member (org.shirakumo.fraf.trial.harmony:voice other) *connected-voices*))
                              collect (org.shirakumo.fraf.trial.harmony:voice other))))
      (setf (harmony:paused-p voice) T
            (mixed:volume resource) 0.0)
      (harmony:play resource))
    voice))

(define-handler (music-director tick) (dt)
  (when harmony:*server*
    (apply-volumes music-director)
    (update-playlist music-director dt)
    (let ((wanted (music-wanted music-director))
          (target (music-target))
          (step (/ dt *music-fade-time*)))
      (dolist (track (music-tracks))
        (let ((resource (music-voice track)))
          (when (allocated-p resource)
            (let* ((voice (connected-voice resource))
                   (old (or (getf (levels music-director) track)
                            (if (harmony:paused-p voice) 0.0 (min 1.0 (mixed:volume resource)))))
                   (goal (if (eq track wanted) target 0.0))
                   (new (if (< old goal) (min goal (+ old step)) (max goal (- old step))))
                   (pause (= new 0.0)))
              ;; A screen's track coming up from silence starts from the top, even one the
              ;; playlist has too (the victory screen's).
              (when (and (eq track wanted) (not (eq wanted (wanted music-director))) (= old 0.0)
                         (getf *screen-music* *game-state*))
                (restart-track resource))
              (setf (getf (levels music-director) track) new)
              (when (/= new old)
                (setf (mixed:volume resource) new))
              (unless (eq pause (not (not (harmony:paused-p voice))))
                (setf (harmony:paused-p voice) pause))))))
      (setf (wanted music-director) wanted))))

(defun add-music (scene)
  (dolist (track (music-tracks))
    ;; The voice, not the asset: staging an asset only loads it, while staging its resource
    ;; loads the asset and allocates the voice.
    (preload (music-voice track) scene))
  (enter (make-instance 'music-director) scene))
