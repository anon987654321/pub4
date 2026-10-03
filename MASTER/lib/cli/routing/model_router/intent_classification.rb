# frozen_string_literal: true

module Master
  module CLI
    module Routing
      class ModelRouter
        # Text -> task_type classification (code_generation/refactoring/
        # architecture/review/explanation/chitchat) — separate from
        # ModelRouter's own model-selection/escalation/failover logic.
        module IntentClassification
          def classify_intent(text)
            s = text.to_s
            return :exploration if s.strip.empty?
            return :chitchat if chitchat_intent?(s)
            INTENT_PATTERNS.each { |intent, re| return intent if re.match?(s) }
            :exploration
          end

          def chitchat_intent?(text)
            trimmed = text.to_s.strip
            return true if CHITCHAT_GREETING_RE.match?(trimmed)
            return true if CHITCHAT_CASUAL_RE.match?(trimmed) && trimmed.length <= CHITCHAT_CASUAL_MAX_LENGTH
            return false if MEDIA_PLAY_RE.match?(trimmed) || MEDIA_ARTIST_RE.match?(trimmed)
            return false if trimmed.length > CHITCHAT_MAX_LENGTH
            return false if trimmed.match?(%r{/|\b(?:implement|refactor|fix|deploy|scan|code|build)\b}i)
            return false if INTENT_PATTERNS.values.any? { |re| re.match?(trimmed) }

            trimmed.split.size <= 8
          end

          def preferred_for(text)
            preferred(task_type: classify_intent(text))
          end
        end
      end
    end
  end
end
