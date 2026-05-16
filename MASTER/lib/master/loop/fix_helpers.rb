# frozen_string_literal: true

module Master
  module Loop
  # Shared helpers for fix loops — extract_code, converged?.
  # Included by AutoLoop and RuleLoop to eliminate duplication.
  module FixHelpers
    CONVERGE_THRESHOLD = 0.05

    # Extract code from LLM response. Handles multi-language fenced blocks.
    # ext: file extension (.rb, .js, ...) or nil for generic extraction.
    def extract_code(text, ext = nil)
      return nil if text.nil? || text.strip.empty? || text.strip == "UNCHANGED"
      return nil if text.match?(/\b(?:error|exception|rate.?limit|i cannot|as an ai)\b/i)
      lang     = ext ? (Master::Judge::Scan::Rule::EXT_LANG.fetch(ext.downcase, "text") rescue "text") : "text"
      langs_re = Regexp.union(lang, "text", "")
      return m[1].strip if (m = text.match(/```(?:#{langs_re})?\n(.*?)```/m))
      return text.strip if ext == ".rb" && text.match?(/frozen_string_literal|module |class /)
      text.strip.empty? ? nil : text.strip
    end

    # True when improvement from prev to current is below threshold — fix loop has stalled.
    def converged?(prev, current, threshold: CONVERGE_THRESHOLD)
      return false unless prev
      ((prev - current).to_f / [prev, 1].max) < threshold
    end
  end
  end
end
