# frozen_string_literal: true

# Where brgen's vertical engines live under RAILS/. They moved out of brgen/engines/ into sibling
# brgen_* directories, so a test that walks every engine takes its glob from here and not from a
# literal that goes stale the next time one moves.
module EngineRoots
  GLOB = "{brgen_*,brgen_radio/*,brgen_marketplace/engines/*}"

  # Each vertical's directory under RAILS/, by the name its tests use.
  PATHS = {
    "marketplace" => "brgen_marketplace",
    "dating" => "brgen_dating",
    "maps" => "brgen_maps",

    "tv" => "brgen_radio/tv",
    "playlist" => "brgen_radio/playlist",
    "takeaway" => "brgen_marketplace/engines/takeaway",
  }.freeze
end
