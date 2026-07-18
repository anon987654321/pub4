# frozen_string_literal: true

# Tier-B ML stubs — heuristic fallbacks until `tools/dilla-ml/` ships.
module DillaMl
  MOOD_CLUSTERS = %w[dusty bright dark warm crisp].freeze

  module_function

  def groove_synced_vinyl(ghost_count, kick_count, base: 0.06)
    base = base.to_f
    return 0.0 if base <= 0.0
    DillaMaster.groove_vinyl_level(ghost_count, kick_count) if defined?(DillaMaster)
    g = ghost_count.to_f / [kick_count, 1].max
    # Honor low bases (e.g. VINYL=10 → ~0.018); do not force a 0.04 floor of hiss.
    lo = [base * 0.85, 0.008].max
    (base + g * 0.012).clamp(lo, 0.12).round(3)
  end

  def predict_sub_hz(kick_hz, spectrum = nil)
    low = spectrum&.dig(:low) || -20.0
    offset = low < -22 ? 2.0 : 0.0
    (kick_hz * 0.5 - offset).clamp(30.0, 80.0).round(2)
  end

  def mood_cluster_for(path_or_features)
    return MOOD_CLUSTERS.sample if path_or_features.nil?
    if path_or_features.is_a?(Hash)
      high = path_or_features[:high].to_f
      return :bright if high > -18
      return :dark if high < -28
    end
    MOOD_CLUSTERS[path_or_features.to_s.hash.abs % MOOD_CLUSTERS.length]
  end

  def ddsp_stub_note
    "DDSP sidecar not installed — using heuristic spectral regen. Set DILLA_ML=1 when tools/dilla-ml ships."
  end

  def rave_stub_note
    "RAVE latent DJ requires offline embedding — use stream + evolution for infinite variation."
  end
end