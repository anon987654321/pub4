# frozen_string_literal: true

module Master
  module Voice
    class Narrator

      # The bard's idle register: when nothing has happened for a while, a short dry freestyle to lift the
      # listener. It is poetry, not report, so it may not claim an outcome or a number; it speaks of the
      # listener and the work in general. Everything it says or asks lives in data/bard.yml under `cheer:`.
      # A model reply that breaks a rule, or no model at all, falls to the written lines, rotated so a
      # line is not repeated until all have been said.
      class Cheer
        CLAIM = /\d|\b(?:complete[d]?|passed|fixed|verified|deployed|succeeded|done|finished|resolved)\b/i

        def initialize(config)
          @config = config.is_a?(Hash) ? config : {}
          @said = []
        end

        def enabled? = @config["enabled"] == true

        def due?(now, since) = enabled? && now - since >= @config.fetch("after_s")

        # writer is nil when no model is usable; the written lines then speak.
        def sentences(writer:, script:, story:)
          model = ask(writer, story)
          clean = accept(model, script)
          clean.empty? ? written : remember(clean)
        end

        def prompt(story) = format(@config.fetch("prompt"), story: story.empty? ? "(nothing yet)" : story.join(" "))

        private

        def ask(writer, story)
          return unless writer

          writer.call(system: @config.fetch("system"), prompt: prompt(story),
                      max_tokens: @config.fetch("max_tokens", 120))
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Voice::Narrator::Cheer.ask")
          nil
        end

        def accept(text, script)
          return [] if text.to_s.strip.empty?

          clean = Master::Voice::StrunkPass.call(Sanitizer.clean(text, script))
          return [] if clean.empty? || clean.match?(REFUSAL) || clean.match?(CLAIM)

          sentences = clean.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:empty?)
          sentences = sentences.first(@config.fetch("max_sentences"))
          sentences.any? { |line| line.split.size > @config.fetch("max_words") } ? [] : sentences
        end

        def written
          lines = Array(@config["lines"])
          @said.clear if lines.all? { |line| @said.include?(line) }
          pick = lines.find { |line| !@said.include?(line) }
          pick ? remember([pick]) : []
        end

        def remember(sentences)
          @said.concat(sentences)
          sentences
        end
      end
    end
  end
end
