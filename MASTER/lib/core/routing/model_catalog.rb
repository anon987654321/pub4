# frozen_string_literal: true

module Master
  module Core
    module Routing
      # One resolver for every place a model name enters MASTER.
      #
      # `/model qwen`, `agent.model = "ollama:qwen..."`, routing, and the
      # dispatcher must not maintain separate vocabularies. Exact ids win;
      # aliases are accepted only when they resolve to one unambiguous id.
      module ModelCatalog

        module_function

        LOCAL_ALIASES = %w[local ollama].freeze

        def models(root: Master::ROOT)
          path = File.join(root, "data", "models.yml")
          data = Master.load_yaml(path) || {}
          rows = []
          (data["models"] || {}).each_value do |tier|
            Array(tier).each do |row|
              id = row["id"].to_s.strip
              rows << id unless id.empty?
            end
          end
          (data["model_defs"] || {}).each_value do |row|
            id = row.is_a?(Hash) ? row["id"].to_s.strip : ""
            rows << id unless id.empty?
          end
          rows.uniq
        rescue StandardError
          []
        end

        def resolve(name, root: Master::ROOT, local_models: nil)
          raw = name.to_s.strip
          raise ArgumentError, "model name is empty" if raw.empty?

          local = Array(local_models).map(&:to_s).reject(&:empty?)
          return local.first if LOCAL_ALIASES.include?(raw.downcase) && local.one?
          if LOCAL_ALIASES.include?(raw.downcase)
            raise ArgumentError, "no local model available; run `ollama list` or `/models`"
          end

          ids = models(root:)
          exact = ids.select { |id| id.casecmp?(raw) }
          return exact.first if exact.one?
          return raw if exact.empty? && canonical_provider_id?(raw)

          aliases = ids.select { |id| alias_match?(id, raw) }
          return aliases.first if aliases.one?

          if aliases.empty?
            raise ArgumentError, "unknown model #{raw.inspect}; use `/model list`"
          end

          raise ArgumentError, "ambiguous model #{raw.inspect}: #{aliases.join(', ')}"
        end

        def alias_match?(id, query)
          normalized_id = id.downcase
          normalized_query = query.downcase
          normalized_id == normalized_query ||
            normalized_id.split(/[:\/]/).last == normalized_query ||
            normalized_id.include?("/#{normalized_query}") ||
            normalized_id.include?(":#{normalized_query}")
        end

        def canonical_provider_id?(name)
          name.match?(%r{\A(?:ollama|openrouter|agy|web-chat|claude-cli):[^[:space:]]+\z}) ||
            name.match?(%r{\A[^[:space:]/]+/[^[:space:]]+\z})
        end
      end
    end
  end
end
