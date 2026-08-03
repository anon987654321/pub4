# frozen_string_literal: true

pin "application"
pin_all_from "app/javascript/controllers", under: "controllers"
eval(File.read(Shared::Engine.root.join("config/importmap_baseline.rb")), binding)

pin "radio_brgen_tunnel", to: "radio_brgen_tunnel.js"

# Tiptap minimal rich-text editor (compose box). esm.sh serves the ProseMirror
# tree self-resolved; the tiptap_editor controller degrades to a plain textarea
# if these fail to load, so the compose never depends on them.
#
# preload: false is load-bearing, not tidiness. `pin` defaults to preload: true,
# so importmap-rails emitted <link rel="modulepreload"> for both of these on
# every page -- which fetches them eagerly no matter what the controller does,
# and made tiptap_editor_controller's dynamic import() decorative. The controller
# now mounts on first focus (see its comment); this is the other half.
pin "@tiptap/core", to: "https://esm.sh/@tiptap/core@2.11.5", preload: false
pin "@tiptap/starter-kit", to: "https://esm.sh/@tiptap/starter-kit@2.11.5", preload: false
