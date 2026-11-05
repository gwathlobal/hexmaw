(asdf:defsystem hexmaw-blueprints
  :description "Builds hexmaw's level blocks from their text blueprints, without Trial."
  :author "Vadim Murin"
  :license "zlib"
  :pathname "src/"
  :components ((:file "blueprint"))
  :depends-on (:com.inuoe.jzon))
