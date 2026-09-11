# frozen_string_literal: true

# Two changes to ruby_llm's model registry, both for OpenRouter.
#
# Upstream already rescues JSON::ParserError here and already answers an
# unknown id through `Models.resolve(id, provider:, assume_exists: true)`.
# Neither of those reaches MASTER: the registry file is read once at boot
# under whatever locale the host has, and every call site says
# `RubyLLM.chat(model: id)` with no provider, which routes to
# `find_without_provider` and raises ModelNotFoundError on any id the
# shipped registry does not carry.
module RubyLLM
  class Models
    class << self
      # `encoding:` is the whole reason this override exists. The registry is
      # the gem's own models.json, whose model descriptions carry non-ASCII
      # punctuation. Read with no locale set — vm23's cron and rc.d
      # environments both — the default external encoding is US-ASCII, the
      # string comes back invalid, and JSON.parse raises
      # Encoding::InvalidByteSequenceError. Upstream rescues JSON::ParserError
      # only, so that one escapes the gem and takes the whole boot with it.
      # The rescue below is upstream's and is kept for a corrupt registry;
      # the encoding argument is what stops the locale case.
      def read_from_json(file = RubyLLM.config.model_registry_file)
        data = File.exist?(file) ? File.read(file, encoding: "UTF-8") : "[]"
        JSON.parse(data, symbolize_names: true).map { |model| Model::Info.new(model) }
      rescue JSON::ParserError => e
        Master::Ground::Swallow.log(e, context: "Models.read_from_json")
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

      fallback_model_info(model_id)
    end

    # Only the keys Model::Info#initialize reads. It stores `:pricing` and
    # `:max_output_tokens`; `input_price_per_million`, `output_price_per_million`
    # and `max_tokens` are reader methods over those, and `type` is derived
    # from modalities. Passing any of those four as a constructor key sets
    # nothing, so they are not passed.
    def fallback_model_info(model_id)
      Model::Info.new({
        id: model_id.to_s,
        name: model_id.to_s,
        provider: "openrouter",
        family: model_id.to_s.split("/").first,
        context_window: 128_000,
        modalities: { input: ["text"], output: ["text"] },
        metadata: {},
      })
    end
  end
end
