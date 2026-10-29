(in-package #:hexmaw)

;;; Greybox test level: a 20 x 20 m hall with pillars, a jumpable platform, a
;;; two-storey annex east and a corridor north that runs into the fog. Units are metres, +Y is up, the
;;; player spawns facing -Z (north). Rebuilt on every scene reload.

(defun build-annex (container)
  "A two-storey annex east of the hall: a lower room through the hall's east doorway, an
upper room right above it, and a stair shaft along their east side that climbs from the
lower room's south-east corner to the upper room's north-east doorway. An imp lives
upstairs."
  (let ((x0 10.5) (x1 18.5) (z0 1) (z1 9) (w 0.5)
        (upper 3.5) (top 6.5) (shaft 21) (rise 0.35) (tread 0.6)
        (hall 4.0))                     ; where the hall's east wall ends
    ;; Floor under the doorway from the hall, the lower room and the stair shaft. Without
    ;; the doorway's strip the nav grid has no floor there, and creatures can't path through.
    (add-box container (- x0 w) -0.5 (- z0 w)  (+ shaft w) 0 (+ z1 w) :surface :floor)
    ;; Lower room: 3 m tall, with a doorway at the south end of its east wall into the shaft.
    (add-box container x0 0 (- z0 w)  (+ x1 w) 3 z0 :surface :wall)
    (add-box container x0 0 z1  (+ x1 w) 3 (+ z1 w) :surface :wall)
    (add-box container x1 0 z0  (+ x1 w) 3 (- z1 2) :surface :wall)
    ;; Its ceiling is the upper room's floor.
    (add-box container x0 3 (- z0 w)  (+ x1 w) upper (+ z1 w) :surface :floor)
    ;; Upper room, with a doorway at the north end of its east wall onto the stair landing.
    ;; Its west wall stands on the hall's east wall.
    (add-box container (- x0 w) hall (- z0 w)  x0 top (+ z1 w) :surface :wall)
    (add-box container x0 upper (- z0 w)  (+ x1 w) top z0 :surface :wall)
    (add-box container x0 upper z1  (+ x1 w) top (+ z1 w) :surface :wall)
    (add-box container x1 upper (+ z0 2)  (+ x1 w) top z1 :surface :wall)
    (add-box container (- x0 w) top (- z0 w)  (+ x1 w) (+ top w) (+ z1 w) :surface :ceiling)
    ;; Stair shaft, open from the floor to its own ceiling.
    (let ((x (+ x1 w)) (roof (+ top w)))
      (add-box container shaft 0 (- z0 w)  (+ shaft w) roof (+ z1 w) :surface :wall)
      (add-box container x 0 (- z0 w)  shaft roof z0 :surface :wall)
      (add-box container x 0 z1  shaft roof (+ z1 w) :surface :wall)
      (add-box container x roof (- z0 w)  (+ shaft w) (+ roof w) (+ z1 w) :surface :ceiling)
      ;; Ten steps climbing north from the lower doorway; the last is the landing.
      (let ((steps (round upper rise)))
        (loop for k from 1 to steps
              for south = (- z1 1 (* tread (1- k)))
              for north = (if (= k steps) z0 (- south tread))
              do (add-box container x 0 north  shaft (* rise k) south :surface :platform))))
    ;; Rooms, so the torches don't light through floors and walls, and the doorways
    ;; between them: hall to lower room, lower room to shaft, shaft to upper room.
    (add-room x0 0 z0  x1 3 z1)
    (add-room x0 upper z0  x1 top z1)
    (add-room (+ x1 w) 0 z0  shaft (+ top w) z1)
    (add-portal 10 0 3.5  x0 3 6.5)
    (add-portal x1 0 (- z1 2)  (+ x1 w) 3 z1)
    (add-portal x1 upper z0  (+ x1 w) top (+ z0 2))
    (add-torch container (- x1 0.5) 2.2 4)
    (add-torch container (+ x0 0.5) (+ upper 2.0) 5)
    (add-torch container (- shaft 0.5) 4.5 6)
    (spawn-creature (make-instance 'imp :location (vec 14.5 upper 5) :facing (/ pi 2)) container)))

(defun build-level (container)
  (setf (fill-pointer *solids*) 0
        (fill-pointer *creatures*) 0
        (fill-pointer *lamps*) 0
        (fill-pointer *rooms*) 0
        (fill-pointer *portals*) 0
        *level-doorways* ())
  (setf (vx *spawn-point*) 0.0 (vy *spawn-point*) 0.0 (vz *spawn-point*) 5.0)
  (ecase *level*
    (:test (build-test-level container))
    (:gallery (build-kit-gallery container))
    (:generated (generate-level container)))
  ;; Last, once every solid, room and portal is in.
  (link-rooms)
  (build-nav-grid)
  (check-reachable))

(defun build-test-level (container)
  (let ((h 4.0) (w 0.5))
    (add-room -10 0 -10  10 h 10)
    (add-portal -1.5 0 (- -10 w)  1.5 3 -10)
    ;; Hall: floor, ceiling, east/west/south walls, north wall with a doorway.
    (add-box container -10 -0.5 -10  10 0 10 :surface :floor)
    (add-box container -10 h -10  10 (+ h 0.5) 10 :surface :ceiling)
    (add-box container (- -10 w) 0 -10  -10 h 10 :surface :wall)
    ;; East wall, with a doorway into the annex.
    (add-box container 10 0 -10  (+ 10 w) h 3.5 :surface :wall)
    (add-box container 10 0 6.5  (+ 10 w) h 10 :surface :wall)
    (add-box container 10 3 3.5  (+ 10 w) h 6.5 :surface :wall)
    (add-box container -10 0 10  10 h (+ 10 w) :surface :wall)
    (add-box container -10 0 (- -10 w)  -1.5 h -10 :surface :wall)
    (add-box container 1.5 0 (- -10 w)  10 h -10 :surface :wall)
    (add-box container -1.5 3 (- -10 w)  1.5 h -10 :surface :wall)
    ;; Pillars.
    (loop for (x z) in '((-4 -4) (4 -4) (-4 4) (4 4))
          do (add-box container (- x 0.5) 0 (- z 0.5) (+ x 0.5) h (+ z 0.5) :surface :pillar))
    ;; Platform in the north-east corner with two steps up to it.
    (add-box container 5 0 -9.5  9.5 1.2 -5 :surface :platform)
    (add-box container 5 0 -5  6.5 0.8 -3.5 :surface :platform)
    (add-box container 6.5 0 -5  8 0.4 -3.5 :surface :platform)
    ;; Torches on the hall walls, two of them flanking the doorway.
    (loop for (x z) in '((-9.5 0) (9.5 0) (0 9.5) (-5 -9.5) (5 -9.5))
          do (add-torch container x 2.4 z))
    ;; An imp in the middle of the hall, facing the spawn point.
    (spawn-creature (make-instance 'imp :location (vec 0 0 -3) :facing pi) container)
    ;; An acolyte up on the platform, facing the spawn point.
    (spawn-creature (make-instance 'acolyte :location (vec 7.5 1.2 -7.5) :facing -2.6) container)
    ;; A knight by the west pillars, its shield toward the spawn point.
    (spawn-creature (make-instance 'knight :location (vec -6 0 0) :facing pi) container)
    ;; A harpy in the south-east of the hall; it rises to its hover from the floor.
    (spawn-creature (make-instance 'harpy :location (vec 6 0 7) :facing (- (/ pi 2))) container)
    (build-annex container)
    ;; Corridor north, 3 m wide, 3 m tall, 14 m long.
    (let ((z0 (- -10 w)) (z1 -25))
      (add-room -1.5 0 z1  1.5 3 z0)
      ;; The floor runs under the doorway too, for the nav grid.
      (add-box container -1.5 -0.5 z1  1.5 0 -10 :surface :floor)
      (add-box container -1.5 3 z1  1.5 3.5 z0 :surface :ceiling)
      (add-box container (- -1.5 w) 0 z1  -1.5 3 z0 :surface :wall)
      (add-box container 1.5 0 z1  (+ 1.5 w) 3 z0 :surface :wall)
      (add-torch container -1.0 2.2 -18)
      ;; The shrine block (data/blueprints/shrine.txt) at the corridor's end, attached by
      ;; its south doorway. Its other doorways are plugged.
      (dolist (c (attach-block 'shrine container "connector_south" :at (vec 0 0 z1) :facing :south))
        (unless (string-equal (connector-name c) "connector_south")
          (seal-connector container c))))))
