(defpackage #:hexmaw
  (:use #:cl+trial)
  ;; IMPACT: a projectile's (spells.lisp), not Trial's physics generic, which our DEFUN
  ;; replaced; a build that loaded Trial's rigidbody again then failed on it.
  (:shadow #:main #:launch #:impact)
  (:local-nicknames
   (#:v #:org.shirakumo.verbose)
   (#:alloy #:org.shirakumo.alloy)
   (#:trial-alloy #:org.shirakumo.fraf.trial.alloy)
   (#:simple #:org.shirakumo.alloy.renderers.simple)
   (#:presentations #:org.shirakumo.alloy.renderers.simple.presentations)
   (#:chroma #:org.shirakumo.alloy.chroma)
   (#:harmony #:org.shirakumo.fraf.harmony)
   (#:mixed #:org.shirakumo.fraf.mixed)
   (#:command-line #:org.shirakumo.deploy.command-line))
  (:export #:main #:launch))
