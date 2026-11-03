(asdf:defsystem hexmaw
  :description "First-person real-time roguelike POC."
  ;; asdf:make builds the standalone executable into dist/ (tools/build-dist, src/dist.lisp).
  ;; Deploy puts the build pathname under bin/, hence the ../.
  :defsystem-depends-on (:deploy)
  :build-operation "deploy-op"
  :build-pathname "../dist/hexmaw"
  :entry-point "hexmaw::dist-main"
  :serial T
  :pathname "src/"
  :components ((:file "package")
               (:file "dev")
               (:file "greybox")
               (:file "automap")
               (:file "rooms")
               (:file "nav")
               (:file "footing")
               (:file "sprite")
               (:file "creature")
               (:file "sound")
               (:file "flyer")
               (:file "necromancer")
               (:file "ogre")
               (:file "blocks")
               (:file "run")
               (:file "fx")
               (:file "lights")
               (:file "liquids")
               (:file "gore")
               (:file "spells")
               (:file "player")
               (:file "vortex")
               (:file "wraith")
               (:file "boss")
               (:file "elite")
               (:file "riftwalker")
               (:file "pickups")
               (:file "hud")
               (:file "hands")
               (:file "sword")
               (:file "spear")
               (:file "inventory")
               (:file "menu")
               (:file "music")
               (:file "map-view")
               (:file "level")
               (:file "kit")
               (:file "generate")
               (:file "save")
               (:file "main")
               (:file "dist"))
  :depends-on (:hexmaw-blueprints
               :trial
               :trial-glfw
               :trial-png
               :trial-gltf
               :trial-alloy
               :trial-harmony
               :cl-mixed-vorbis
               :sb-bsd-sockets))
