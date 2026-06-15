# frozen_string_literal: true

module Master
  module Voice
    # Detects and strips banned phrases from LLM output (CA06).
    class SoulDriftDetector
      STRUNK_PATH = Master.data_path("rules.yml")

      PATTERNS = [
        /\A(?:In summary|Consequently|Therefore|Notably|Importantly),?\s+/i,
        /\b(?:I think that|I believe|I'd be happy to|I'm sorry but I cannot|as an AI)\b/i,
        /\b(?:Great question|Let me explain|Certainly!|Absolutely!)\b/i,
        /^#+\s+/m,
        /^[-*]\s*$/m
      ].freeze

      class << self
        def clean(text, event_bus: nil)
          original = text.to_s
          cleaned = original.dup
          hits = 0
          loop do
            before = cleaned
            PATTERNS.each { |rx| cleaned = cleaned.gsub(rx, "") }
            strunk_rules.each { |phrase| cleaned = cleaned.gsub(/#{Regexp.escape(phrase)}/i, "") }
            hits += 1 if cleaned != before
            break if cleaned == before
          end
          cleaned = cleaned.gsub(/\n{3,}/, "\n\n").strip
          if hits.positive? && cleaned != original.strip
            event_bus&.publish("soul_drift:stripped", count: hits, bytes: original.bytesize - cleaned.bytesize)
          end
          cleaned
        end

        def drift?(text)
          probe = text.to_s
          PATTERNS.any? { |rx| probe.match?(rx) } ||
            strunk_rules.any? { |phrase| probe.match?(/#{Regexp.escape(phrase)}/i) }
        end

        private

        def strunk_rules
          @strunk_rules ||= begin
            data = Master.load_yaml(STRUNK_PATH) || {}
            voice = data["voice"] || {}
            strunk = voice["strunk"] || {}
            Array(strunk["preambles"]) + Array(strunk["hedges"]) + Array(strunk["endings"])
          rescue StandardError
            []
          end
        end
      end
    end
  end
end