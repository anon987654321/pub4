# frozen_string_literal: true

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
%w[Dating Marketplace Playlist Takeaway Tv].each do |vertical|
  next unless Object.const_defined?("#{vertical}::Engine")

  dir = Object.const_get("#{vertical}::Engine").root.join("app/javascript/controllers")
  pin_all_from dir.to_s, under: "controllers" if dir.exist?
end

eval(File.read(Shared::Engine.root.join("config/importmap_baseline.rb")), binding)

pin "radio_brgen_tunnel", to: "radio_brgen_tunnel.js"

# Tiptap is pinned in shared/config/importmap_baseline.rb, vendored to
# shared/vendor/javascript/tiptap.js. It used to be two esm.sh pins here.
