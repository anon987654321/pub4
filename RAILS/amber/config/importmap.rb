# frozen_string_literal: true

pin "application"
pin_all_from "app/javascript/controllers", under: "controllers"
eval(File.read(Shared::Engine.root.join("config/importmap_baseline.rb")), binding)

# stimulus_boot_social.js (shared with brgen, not bsdports) and
# stimulus_boot_amber.js (amber only). Pinned per app rather than in
# importmap_baseline.rb, which bsdports also evals — bsdports imports
# neither, so its importmap carries no pin for them.
pin "pub4/stimulus_boot_social", to: "stimulus_boot_social.js"
pin "pub4/stimulus_boot_amber", to: "stimulus_boot_amber.js"
