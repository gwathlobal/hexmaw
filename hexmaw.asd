(asdf:defsystem hexmaw
  :long-name "Hexmaw"
  ;; The game's version: the release tag must agree with it ("Releases" in CLAUDE.md).
  :version "0.1.1"
  :description "First-person real-time roguelike POC."
  :author "Vadim Murin"
  :license "zlib (code); assets: see ASSETS-LICENSE.md"
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
               (:file "input")
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
               (:file "imp")
               (:file "blocks")
               (:file "run")
               (:file "fx")
               (:file "lights")
               (:file "liquids")
               (:file "waterfall")
               (:file "gore")
               (:file "sparks")
               (:file "spells")
               (:file "player")
               (:file "magic")
               (:file "skins")
               (:file "vortex")
               (:file "wraith")
               (:file "acolyte")
               (:file "knight")
               (:file "boss")
               (:file "elite")
               (:file "riftwalker")
               (:file "hag")
               (:file "votary")
               (:file "bloodroot")
               (:file "settlement")
               (:file "townsfolk")
               (:file "pickups")
               (:file "hud")
               (:file "hands")
               (:file "sword")
               (:file "spear")
               (:file "maul")
               (:file "inventory")
               (:file "status-icons")
               (:file "menu")
               (:file "dialogue")
               (:file "forge")
               (:file "settings")
               (:file "loot")
               (:file "music")
               (:file "map-view")
               (:file "level")
               (:file "kit")
               (:file "generate")
               (:file "save")
               (:file "levelcheck")
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
