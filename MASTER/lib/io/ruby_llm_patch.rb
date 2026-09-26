# frozen_string_literal: true

# MASTER only supplies the OpenRouter unknown-model fallback. RubyLLM 2 owns
# registry loading, UTF-8 decoding and the Tool/parameter DSL, so no compatibility
# aliases or registry-reader overrides belong here.
module RubyLLM
  class Models
    private

    def find_without_provider(model_id)
      exact_matches = all.select { |m| m.id == model_id }
      return preferred_match(exact_matches) if exact_matches.any?

      resolved_id = Aliases.resolve(model_id)
      alias_matches = all.select { |m| m.id == resolved_id }
      return preferred_match(alias_matches) if alias_matches.any?

      RubyLLM::Model.default(model_id.to_s, "openrouter")
    end
  end
end
