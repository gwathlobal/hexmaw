(in-package #:hexmaw)

;;; Greybox test level: a 20 x 20 m hall with pillars, a jumpable platform and a
;;; corridor north that runs into the fog. Units are metres, +Y is up, the
;;; player spawns facing -Z (north). Rebuilt on every scene reload.

(defparameter *floor-color* (vec 0.45 0.42 0.38))
(defparameter *wall-color* (vec 0.62 0.6 0.56))
(defparameter *ceiling-color* (vec 0.32 0.31 0.3))
(defparameter *pillar-color* (vec 0.62 0.36 0.3))
(defparameter *platform-color* (vec 0.4 0.46 0.56))

(defun build-level (container)
  (setf (fill-pointer *solids*) 0)
  (let ((h 4.0) (w 0.5))
    ;; Hall: floor, ceiling, east/west/south walls, north wall with a doorway.
    (add-box container -10 -0.5 -10  10 0 10 :color *floor-color*)
    (add-box container -10 h -10  10 (+ h 0.5) 10 :color *ceiling-color*)
    (add-box container (- -10 w) 0 -10  -10 h 10 :color *wall-color*)
    (add-box container 10 0 -10  (+ 10 w) h 10 :color *wall-color*)
    (add-box container -10 0 10  10 h (+ 10 w) :color *wall-color*)
    (add-box container -10 0 (- -10 w)  -1.5 h -10 :color *wall-color*)
    (add-box container 1.5 0 (- -10 w)  10 h -10 :color *wall-color*)
    (add-box container -1.5 3 (- -10 w)  1.5 h -10 :color *wall-color*)
    ;; Pillars.
    (loop for (x z) in '((-4 -4) (4 -4) (-4 4) (4 4))
          do (add-box container (- x 0.5) 0 (- z 0.5) (+ x 0.5) h (+ z 0.5) :color *pillar-color*))
    ;; Platform in the north-east corner with two steps up to it.
    (add-box container 5 0 -9.5  9.5 1.2 -5 :color *platform-color*)
    (add-box container 5 0 -5  6.5 0.8 -3.5 :color *platform-color*)
    (add-box container 6.5 0 -5  8 0.4 -3.5 :color *platform-color*)
    ;; Corridor north, 3 m wide, 3 m tall, 14 m long, dead end.
    (let ((z0 (- -10 w)) (z1 -25))
      (add-box container -1.5 -0.5 z1  1.5 0 z0 :color *floor-color*)
      (add-box container -1.5 3 z1  1.5 3.5 z0 :color *ceiling-color*)
      (add-box container (- -1.5 w) 0 z1  -1.5 3 z0 :color *wall-color*)
      (add-box container 1.5 0 z1  (+ 1.5 w) 3 z0 :color *wall-color*)
      (add-box container -1.5 0 (- z1 w)  1.5 3 z1 :color *wall-color*))))
