# frozen_string_literal: true

# Scene is the common object passed to the musical, visual and architectural
# layers. It stays small: the scene says what the world is doing, while renderers
# decide how that world is drawn or sounded.
module DillaScene
  MATERIALS = %w[graphite brass concrete glass tape].freeze
  WORLD_EVENTS = %w[debris flash void fracture bloom pulse scrape radio laser].freeze
  FAMILIES = %w[city night machine dream gravity].freeze
  VOICES = %w[bass_voice dust_voice harp_voice machine_voice ghost_percussion air_voice melodic_noise broken_keyboard sub_voice room_voice].freeze

  module_function

  def profile(name, index: 0, tension: nil, energy: nil)
    t = tension.nil? ? 0.5 : tension.to_f.clamp(0.0, 1.0)
    e = energy.nil? ? (0.28 + ((index % 7) * 0.08)).clamp(0.0, 0.95) : energy.to_f.clamp(0.0, 1.0)
    density = (0.25 + (t * 0.44) + (e * 0.18)).clamp(0.0, 1.0)
    contrast = (0.42 + ((t - 0.5).abs * 0.9) + ((e - 0.5).abs * 0.2)).clamp(0.0, 1.0)
    {
      scene: name.to_s,
      family: FAMILIES[index % FAMILIES.length],
      material: MATERIALS[(index + (t * 3).round) % MATERIALS.length],
      world_event: WORLD_EVENTS[(index + (t * 5).round) % WORLD_EVENTS.length],
      tension: t.round(3),
      energy: e.round(3),
      fracture: (0.10 + (t * 0.58) + (e * 0.18)).clamp(0.0, 1.0).round(3),
      density: density.round(3),
      contrast: contrast.round(3),
      voices: voices_for(density:, energy: e),
      dynamic: dynamic_for(tension: t, energy: e, density:),
      architecture: {
        foreground: density > 0.62 ? :active : :open,
        horizon: contrast > 0.68 ? :broken : :wide,
        motion: e > 0.62 ? :accelerate : :drift
      }
    }
  end

  def voices_for(density:, energy:)
    count = (2 + (density * 6).round + (energy * 2).round).clamp(2, VOICES.length)
    VOICES.first(count)
  end

  def dynamic_for(tension:, energy:, density:)
    {
      kick_duck: (0.18 + (energy * 0.34)).clamp(0.0, 0.65).round(3),
      texture_duck: (0.12 + (density * 0.42)).clamp(0.0, 0.62).round(3),
      room_rebound: (0.18 + ((1.0 - density) * 0.58)).clamp(0.0, 0.72).round(3),
      distortion: (tension * 0.38).clamp(0.0, 0.42).round(3)
    }
  end

  def journey(index, size)
    return :intro if index.zero?
    return :outro if index >= size - 1
    ratio = index.to_f / [size - 1, 1].max
    return :breakdown if ratio.between?(0.58, 0.68)
    return :solo if ratio.between?(0.46, 0.57)
    return :bridge if ratio.between?(0.22, 0.28)
    return :hook if ratio.between?(0.28, 0.46)
    :verse
  end
end
