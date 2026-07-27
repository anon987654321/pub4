# frozen_string_literal: true

# Ableton-Live-shaped vocabulary for dilla's mix: named Tracks (stems) with a
# Volume/Pan/Sends, each carrying an ordered Device chain, plus a Scene
# concept (one named snapshot of per-role weights active for a given bar).
# Introduced to make the engine's actual signal path introspectable (`ruby
# dilla.rb tracks`) instead of only existing as scattered ENV reads and long
# inline ffmpeg filter strings.
module DillaMixer
  # One named, self-contained ffmpeg filter-graph segment (e.g. one
  # "[in]acompressor=...[out]" stage). `filter` is the exact string used at
  # render time -- Device exists to make WHICH stage a value belongs to
  # inspectable, not to change how filters are built or joined.
  Device = Struct.new(:name, :filter) do
    def to_s = filter
  end

  # Ordered list of Devices. `to_a` returns the plain filter-string array in
  # the shape callers already expect (Array<String>, one labeled segment per
  # element) -- existing call sites that `.concat`/iterate this are
  # unaffected by the Device wrapping.
  DeviceChain = Struct.new(:devices) do
    def to_a = devices.map(&:filter)
    def names = devices.map(&:name)
  end

  # A stem in the mix. `volume`/`pan` are the resolved numeric values for the
  # current config (not ENV variable names); `sends` maps bus name => send
  # amount (0.0 if the stem doesn't reach that bus); `device_chain` is a
  # DeviceChain when the stem's processing is Device-backed, or a plain
  # Array<Symbol> of stage names when it's described statically (see
  # dilla.rb's `dilla_print_tracks`).
  Track = Struct.new(:name, :volume, :pan, :sends, :device_chain, keyword_init: true)

  # One named arrangement snapshot for a given bar -- the closest existing
  # analog to an Ableton Scene (a snapshot that changes what plays across
  # every track at once). Wraps dilla.rb's existing `dilla_section`
  # resolution; does not change which section-source wins.
  Scene = Struct.new(:name, :bar, :weights, :active_roles, keyword_init: true)
end
