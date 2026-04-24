# frozen_string_literal: true

# Monkey-patch RubyLLM for OpenBSD/OpenRouter compatibility:
# 1. Fix UTF-8 encoding in model catalog JSON parsing
# 2. Pass through unknown models (OpenRouter :free variants) instead of raising

module RubyLLM
  class Models
    class << self
      def read_from_json(file = RubyLLM.config.model_registry_file)
        data = File.exist?(file) ? File.read(file, encoding: "utf-8") : "[]"
        JSON.parse(data, symbolize_names: true).map { |model| Model::Info.new(model) }
      rescue JSON::ParserError
        []
      end
    end

    private

    def find_without_provider(model_id)
      exact_matches = all.select { |m| m.id == model_id }
      return preferred_match(exact_matches) if exact_matches.any?

      resolved_id = Aliases.resolve(model_id)
      alias_matches = all.select { |m| m.id == resolved_id }
      return preferred_match(alias_matches) if alias_matches.any?

      # Pass through unknown models (e.g. OpenRouter :free variants)
      # instead of raising ModelNotFoundError
      Model::Info.new({
        id: model_id.to_s,
        name: model_id.to_s,
        provider: "openrouter",
        type: "chat",
        family: model_id.to_s.split("/").first,
        context_window: 128_000,
        max_tokens: 4096,
        input_price_per_million: 0.0,
        output_price_per_million: 0.0,
        modalities: { input: ["text"], output: ["text"] },
        metadata: {}
      })
    end
  end
end
