(in-package #:hexmaw)

;;; Moving on a slippery footing (*FOOTINGS*, greybox.lisp): Hexen's ice. There a body keeps
;;; its momentum, losing a fixed fraction of it every second, and what it does to move only
;;; pushes that momentum, at a fraction of the usual push. So it is slow to get going, slow
;;; to stop, and in the end faster than on stone. The player (player.lisp) and creatures
;;; (creature.lisp) both move this way on ice; on other floors each keeps its own grip.
;;; These change a velocity's X and Z in place: they run every tick.

(defun footing-drag (velocity footing dt stopping)
  "Slow VELOCITY's horizontal part by FOOTING's friction over DT seconds. When STOPPING
(nothing pushes it) and it is slower than the footing's stop speed, stop it."
  (let ((keep (exp (- (* (float (footing-property footing :friction) 0f0) dt)))))
    (setf (vx velocity) (* (vx velocity) keep)
          (vz velocity) (* (vz velocity) keep))
    (when (and stopping
               (< (+ (expt (vx velocity) 2) (expt (vz velocity) 2))
                  (expt (float (footing-property footing :stop-speed) 0f0) 2)))
      (setf (vx velocity) 0f0 (vz velocity) 0f0))))

(defun footing-push (velocity wx wz speed footing dt)
  "Push VELOCITY for DT seconds along WX WZ (at most unit length) by what moves at SPEED on
other floors: against FOOTING-DRAG, it tops out at SPEED times the footing's top speed."
  (let ((a (* speed (footing-property footing :top-speed) (footing-property footing :friction) dt)))
    (setf (vx velocity) (+ (vx velocity) (float (* wx a) 0f0))
          (vz velocity) (+ (vz velocity) (float (* wz a) 0f0)))))
