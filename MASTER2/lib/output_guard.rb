# frozen_string_literal: true

require_relative "mode"

module MASTER
  # Guards LLM output against category errors.
  # In ops mode, narrative output is illegal.
  class OutputGuard
    NARRATIVE_MARKERS = [
      /^\s*Chapter\s+\d+/i,
      /^\s*Part\s+\d+/i,
      /\bTo be continued\b/i,
    ].freeze

    def self.check(mode:, candidate_text:, **)
      return Result.ok(candidate_text) unless candidate_text.is_a?(String)

      if mode == Mode::OPS && NARRATIVE_MARKERS.any? { |p| candidate_text.match?(p) }
        return Result.err("OutputGuard: narrative output forbidden in ops mode.", category: :mode)
      end

      Result.ok(candidate_text)
    end
  end
end
