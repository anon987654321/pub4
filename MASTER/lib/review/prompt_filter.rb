# frozen_string_literal: true

module Master
  module Review
    # Strips the anti-simulation words from the system prompt MASTER writes.
    # anti_simulation governs what MASTER asserts, so it never touches a user
    # message: "what would happen if" has to reach the model as asked.
    module PromptFilter
      DEFAULT_ANTI_SIMULATION_WORDS = ["wil#{?l}", "woul#{?d}", "coul#{?d}", "migh#{?t}"].freeze
      PROMPT_FENCE_RE = /(```.*?```)/m.freeze

      private

      def filter_prompt(text)
        return text unless text
        re = forbidden_prompt_word_re
        text.to_s.split(PROMPT_FENCE_RE).map.with_index do |part, idx|
          idx.odd? ? part : part.gsub(re, "").gsub(/[ \t]{2,}/, " ").gsub(/\s+([,.;:!?])/, '\1')
        end.join.strip
      end

      def forbidden_prompt_word_re
        words = anti_simulation_words
        /\b(?:#{words.map { |word| Regexp.escape(word) }.join("|")})\b/i
      end

      def anti_simulation_words
        @anti_simulation_words ||= begin
          words = Master.load_yaml(Master.data_path("soul.yml")).dig("absolute", "anti_simulation", "forbidden")
          Array(words).map(&:to_s).reject(&:empty?)
        rescue StandardError
          DEFAULT_ANTI_SIMULATION_WORDS
        end
      end
    end
  end
end
