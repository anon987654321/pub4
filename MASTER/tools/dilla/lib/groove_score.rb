# frozen_string_literal: true

# Transient-aware pocket scoring — velocity spread, ghost density, timing bias.
module DillaGrooveScore
  module_function

  def analyze(events, meta: nil)
    return { score: 70, breakdown: {} } unless events.is_a?(Hash)

    kicks_n = events[:kick]&.length || 0
    snares = events[:snare] || []
    ghosts = events[:ghost] || []
    hats_n = events[:hat]&.length || 0
    meta ||= events[:_groove_meta] || {}

    ghost_vels = ghosts.map { |e| e[1].to_f }
    ghost_var = variance(ghost_vels)
    ghost_density = ghosts.length.to_f / [kicks_n, 1].max

    snare_vels = snares.map { |e| e[1].to_f }
    backbeat_ratio = snares.empty? ? 0.0 : snare_vels.count { |v| v >= 0.5 } / snares.length.to_f

    hat_ratio = hats_n.to_f / [kicks_n, 1].max

    snare_early = Array(meta[:snare_early_ms])
    snare_early_avg = snare_early.empty? ? 0.0 : snare_early.sum / snare_early.length
    hat_late = Array(meta[:hat_late_ms])
    hat_late_avg = hat_late.empty? ? 0.0 : hat_late.sum / hat_late.length

    density_pts = [kicks_n * 0.5, 20].min + [ghosts.length * 0.3, 15].min
    score = 60.0 + density_pts
    score += [ghost_var * 100, 10].min
    score += 6 if ghost_density.between?(0.2, 0.85)
    score += 5 if backbeat_ratio >= 0.55
    score += [snare_early_avg.abs * 0.35, 10].min if snare_early_avg.negative?
    score += [hat_late_avg * 0.25, 8].min if hat_late_avg.positive?
    score -= 4 if hat_ratio > 14
    score += 3 if hat_ratio.between?(2.5, 10.0)

    breakdown = {
      kicks: kicks_n, ghosts: ghosts.length, hats: hats_n,
      ghost_var: ghost_var.round(3), ghost_density: ghost_density.round(3),
      backbeat_ratio: backbeat_ratio.round(3),
      snare_early_avg_ms: snare_early_avg.round(2),
      hat_late_avg_ms: hat_late_avg.round(2)
    }

    { score: score.round.clamp(40, 98), breakdown: breakdown }
  end

  def variance(values)
    return 0.0 if values.length < 2
    mean = values.sum / values.length
    values.sum { |v| (v - mean)**2 } / values.length
  end
end