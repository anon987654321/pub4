# frozen_string_literal: true

enable_integrity!

pin "application"
pin_all_from "app/javascript/controllers", under: "controllers"

# The verticals' controllers, pinned by absolute engine root.
#
# pin_all_from resolves a relative path against Rails.root, so the line above
# covers brgen/app/javascript/controllers and nothing else. Each engine pushes
# its own app/javascript onto config.assets.paths, which makes the file
# *servable* — but importmap needs a *pin* for the module specifier to exist,
# and eagerLoadControllersFrom("controllers") only walks what the importmap
# declares. So every vertical's Stimulus controller was reachable over HTTP and
# registered nowhere.
#
# Measured on the booted app before this: 92 pins, 20 under controllers/, not
# one of them from an engine. Dead in production as a result: the playlist audio
# player (playlist/playlists/_player), the TV video player on all three watch
# pages, and dating's intro/discover toggle on its landing page.
%w[Dating Marketplace Playlist Takeaway Tv BrgenMessenger Maps].each do |vertical|
  next unless Object.const_defined?("#{vertical}::Engine")

  dir = Object.const_get("#{vertical}::Engine").root.join("app/javascript/controllers")
  pin_all_from dir.to_s, under: "controllers" if dir.exist?
end

eval(File.read(Shared::Engine.root.join("config/importmap_baseline.rb")), binding)

# stimulus_boot_social.js (shared with amber, not bsdports) and
# stimulus_boot_brgen.js (brgen only). Pinned per app rather than in
# importmap_baseline.rb, which bsdports also evals — bsdports imports
# neither, so its importmap carries no pin for them.
pin "pub4/stimulus_boot_social", to: "stimulus_boot_social.js"
pin "pub4/stimulus_boot_brgen", to: "stimulus_boot_brgen.js"

pin "radio_brgen_tunnel", to: "radio_brgen_tunnel.js"
pin "radio_brgen_audio", to: "radio_brgen_audio.js"
pin "radio_brgen_visual", to: "radio_brgen_visual.js"
pin "radio_brgen_modes", to: "radio_brgen_modes.js"

# css-doodle 0.60.0 (MIT, css-doodle.com), vendored from npm: the animated
# heart on dating's first screen. Not preloaded: dating_splash_controller
# imports it on that one screen, and only when motion is welcome.
pin "css-doodle", to: "css-doodle.js", preload: false

# anime.js 3.2.1 (MIT, animejs.com), its ES build vendored from npm: the
# marketplace logo's timelines and the parallax ad. It was imported from
# esm.sh at runtime, a third-party host on the page's critical path.
pin "animejs", to: "animejs.js", preload: false
# No tiptap pin here. It is pinned once in shared/config/importmap_baseline.rb,
# vendored to shared/vendor/javascript/tiptap.js rather than fetched from a CDN.
