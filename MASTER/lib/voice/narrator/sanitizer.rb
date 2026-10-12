# frozen_string_literal: true

module Master
  module Voice
    class Narrator
      # What may be spoken. Applied to every event before a model or a speaker
      # sees it, and again to the model's reply: a secret that reaches a speaker
      # has been published to the room. Patterns live in data/narration.yml.
      module Sanitizer
        ANSI = /\e\[[0-9;?]*[A-Za-z]/
        MARKUP = /[\[\]{}`*_#|<>~^\\]/
        # Applied in this order: secrets first, then shapes merely unpleasant to hear.
        STEPS = %i[secret_assignment env_file url email home_path path long_token commit ip].freeze

        module_function

        def clean(text, script)
          out = Master::Ground::Redactor.text(text.to_s.scrub.gsub(ANSI, "")).gsub("[REDACTED]", "something withheld")
          STEPS.each do |step|
            pattern = script.redact[step.to_s]
            next unless pattern

            out = step == :path ? out.gsub(pattern) { Regexp.last_match(1) } : out.gsub(pattern, script.spoken.fetch(step.to_s, "something withheld"))
          end
          out.gsub(MARKUP, " ").gsub(/[[:cntrl:]]/, " ").gsub(/\s+/, " ").strip
        end
      end
    end
  end
end
