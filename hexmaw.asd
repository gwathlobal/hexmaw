(asdf:defsystem hexmaw
  :description "First-person real-time roguelike POC."
  :serial T
  :pathname "src/"
  :components ((:file "package")
               (:file "dev")
               (:file "greybox")
               (:file "rooms")
               (:file "nav")
               (:file "sprite")
               (:file "creature")
               (:file "flyer")
               (:file "necromancer")
               (:file "blocks")
               (:file "fx")
               (:file "lights")
               (:file "liquids")
               (:file "gore")
               (:file "spells")
               (:file "player")
               (:file "hud")
               (:file "hands")
               (:file "sword")
               (:file "menu")
               (:file "level")
               (:file "kit")
               (:file "generate")
               (:file "save")
               (:file "main"))
  :depends-on (:hexmaw-blueprints
               :trial
               :trial-glfw
               :trial-png
               :trial-gltf
               :trial-alloy
               :sb-bsd-sockets))
