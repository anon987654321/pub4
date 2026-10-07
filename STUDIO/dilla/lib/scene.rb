# frozen_string_literal: true

# The album/world layer: scenes are not audio presets. They are a small set of
# relationships consumed by sound, architecture and motion design.
module DillaScene
  MATERIALS = %w[graphite brass concrete glass tape].freeze
  WORLD_EVENTS = %w[debris flash void fracture bloom pulse].freeze
  FAMILIES = %w[city night machine dream gravity].freeze

  module_function

  def profile(name, index: 0, tension: nil, energy: nil)
    t = tension.nil? ? 0.5 : tension.to_f.clamp(0.0, 1.0)
    e = energy.nil? ? (0.28 + ((index % 7) * 0.08)).clamp(0.0, 0.95) : energy.to_f.clamp(0.0, 1.0)
    {
      scene: name.to_s,
      family: FAMILIES[index % FAMILIES.length],
      material: MATERIALS[(index + (t * 3).round) % MATERIALS.length],
      world_event: WORLD_EVENTS[(index + (t * 5).round) % WORLD_EVENTS.length],
      tension: t.round(3),
      energy: e.round(3),
      fracture: (0.12 + (t * 0.58) + (e * 0.18)).clamp(0.0, 1.0).round(3),
      density: (0.28 + (t * 0.44) + (e * 0.18)).clamp(0.0, 1.0).round(3),
      contrast: (0.4 + ((t - 0.5).abs * 0.85)).clamp(0.0, 1.0).round(3)
    }
  end

  def journey(index, size)
    return :intro if index.zero?
    return :outro if index >= size - 1
    ratio = index.to_f / [size - 1, 1].max
    return :breakdown if ratio.between?(0.58, 0.68)
    return :hook if ratio.between?(0.28, 0.46)
    :verse
  end
end
