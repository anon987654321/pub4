# frozen_string_literal: true

module Master
  module Voice
    # Paralinguistic tags for Chatterbox-Turbo / OmniVoice-style engines.
    module Enrich
      module_function

      def apply(text, emotion)
        t = text.to_s
        return t if t.strip.empty?

        primary = emotion[:primary]
        scores = emotion.fetch(:scores, {})
        out = t.dup

        case primary
        when :humor
          out = maybe_insert(out, "[chuckle]", 0.35 + scores[:humor].to_f * 0.2)
        when :triumph
          out = maybe_insert(out, "[laugh]", 0.18 + scores[:triumph].to_f * 0.15)
        when :comfort
          out = maybe_insert(out, "[sigh]", 0.22) if scores[:comfort].to_f > 0.35
        when :wonder
          out = maybe_insert(out, "[chuckle]", 0.12)
        end
        out
      end

      def maybe_insert(text, tag, chance)
        return text if chance <= 0 || rand >= chance

        parts = text.split(/(?<=[.!?])\s+/)
        return text if parts.length < 2

        idx = rand(1...[parts.length, 3].max)
        parts[idx] = "#{tag} #{parts[idx]}"
        parts.join(" ")
      end
      private_class_method :maybe_insert
    end
  end
end
