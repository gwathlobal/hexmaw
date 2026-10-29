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
               (:file "blocks")
               (:file "fx")
               (:file "lights")
               (:file "gore")
               (:file "spells")
               (:file "player")
               (:file "hud")
               (:file "hands")
               (:file "sword")
               (:file "menu")
               (:file "level")
               (:file "main"))
  :depends-on (:trial
               :trial-glfw
               :trial-png
               :trial-gltf
               :trial-alloy
               :sb-bsd-sockets))
