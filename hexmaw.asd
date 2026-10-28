(asdf:defsystem hexmaw
  :description "First-person real-time roguelike POC."
  :serial T
  :pathname "src/"
  :components ((:file "package")
               (:file "dev")
               (:file "greybox")
               (:file "sprite")
               (:file "creature")
               (:file "blocks")
               (:file "fx")
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
