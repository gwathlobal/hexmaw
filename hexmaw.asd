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
               (:file "spells")
               (:file "player")
               (:file "hud")
               (:file "level")
               (:file "main"))
  :depends-on (:trial
               :trial-glfw
               :trial-png
               :trial-gltf
               :sb-bsd-sockets))
