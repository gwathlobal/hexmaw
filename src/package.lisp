(defpackage #:hexmaw
  (:use #:cl+trial)
  (:shadow #:main #:launch)
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
