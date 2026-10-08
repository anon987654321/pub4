# frozen_string_literal: true

require "digest"

module Master
  module Voice
    # Disciplined, deterministic paralinguistic enrichment.
    #
    # Only Chatterbox-style native tags are emitted. Placement is tied to real
    # clause boundaries and the same text always produces the same result.
    module Enrich
      TAGS = {
        humor: "[chuckle]",
        comfort: "[sigh]",
        wonder: "[gasp]",
        intimacy: "[sigh]",
        triumph: "[chuckle]",
      }.freeze

      module_function

      def apply(text, emotion, tags: false)
        source = text.to_s
        return source if source.strip.empty? || !tags

        scores = emotion.fetch(:scores, {})
        primary = emotion[:primary]
        expressiveness = scores[:expressiveness].to_f
        intimacy = scores[:intimacy].to_f
        humor = scores[:humor].to_f
        candidates = []
        candidates << [TAGS[:humor], humor * 0.45 + expressiveness * 0.10] if humor >= 0.35
        candidates << [TAGS[:comfort], scores[:comfort].to_f * 0.34 + intimacy * 0.10] if scores[:comfort].to_f >= 0.35
        candidates << [TAGS[:wonder], scores[:wonder].to_f * 0.22 + expressiveness * 0.10] if scores[:wonder].to_f >= 0.45
        candidates << [TAGS[:intimacy], intimacy * 0.16] if intimacy >= 0.72
        candidates << [TAGS[:triumph], scores[:triumph].to_f * 0.18] if primary == :triumph

        tag, strength = candidates.max_by { |candidate| [candidate[1], candidate[0]] }
        return source unless tag && strength >= 0.24

        insert_tag(source, tag, strength)
      end

      def insert_tag(text, tag, strength)
        sentences = text.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:empty?)
        return text if sentences.length < 2

        # Hard cap: one event per utterance. The threshold is deterministic so
        # repeated synthesis does not randomly change the speaker's performance.
        seed = Digest::SHA256.hexdigest(text)[0, 8].to_i(16)
        gate = (seed % 100) / 100.0
        threshold = [0.18 + strength * 0.34, 0.72].min
        return text if gate > threshold

        index = [((seed / 100) % sentences.length), sentences.length - 1].min
        return text if index.zero?

        sentences[index] = "#{tag} #{sentences[index]}"
        sentences.join(" ")
      end

      private_class_method :insert_tag
    end
  end
end
