# frozen_string_literal: true

module Postpro
  # Minimal, reviewable proposals; this module never edits pixels itself.
  module CorrectionProposer
    def self.propose(report, constraints: {})
      exposure = report.fetch(:exposure)
      tonal = report.fetch(:tonal)
      contrast = report.fetch(:contrast)
      max_stops = Float(constraints.fetch(:max_exposure_stops, 1.0)).abs.clamp(0.0, 2.0)
      proposals = {}

      bias = Float(exposure.fetch(:exposure_bias_stops))
      proposals[:exposure_bias_stops] = bias.clamp(-max_stops, max_stops) if bias.abs > 0.15

      curve = {}
      shadow = Float(tonal.fetch(:shadow_detail_ratio))
      highlight = Float(tonal.fetch(:highlight_detail_ratio))
      curve[:shadow_lift] = (0.35 - shadow).clamp(0.0, 0.25) if shadow < 0.35
      curve[:highlight_rolloff] = (0.35 - highlight).clamp(0.0, 0.25) if highlight < 0.35
      proposals[:tone_curve] = curve unless curve.empty?

      if Float(contrast.fetch(:rms_contrast)) < 0.18 &&
         Float(exposure.fetch(:clipped_highlights_pct)) < 0.5 &&
         Float(exposure.fetch(:clipped_shadows_pct)) < 0.5
        proposals[:s_curve_strength] = ((0.18 - contrast[:rms_contrast]) / 0.18).clamp(0.0, 0.5)
      end

      proposals[:not_addressed] = report.fetch(:not_assessed, %i[composition focus_quality subject_expression])
      proposals[:requires_operator_review] = true
      proposals
    end
  end
end
