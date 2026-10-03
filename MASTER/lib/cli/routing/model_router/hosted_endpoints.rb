# frozen_string_literal: true

require "json"

module Master
  module CLI
    module Routing
      class ModelRouter
        # Hosted OpenAI-compatible endpoints, models.yml `openai_compatible`:
        # each lists its models at <base>/models, and they become
        # "<name>:<model>" lanes. With none of its key_env set, an endpoint
        # offers only the models its `keyless` rule selects: LLM7 answers
        # GLM-5.3-Flash without a key and refuses gpt-5.5 with a 401, and the
        # listing says which is which.
        module HostedEndpoints
          HOSTED_TIMEOUT_S = 5

          def hosted_models = hosted_index.keys

          # { base:, key: } for a hosted lane id; nil when no endpoint lists it.
          def hosted_endpoint_for(model_id) = hosted_index[model_id.to_s]

          def hosted_model?(model_id) = hosted_endpoints.key?(model_id.to_s.split(":", 2).first)

          private

          def hosted_endpoints = @rules.fetch("openai_compatible", nil) || {}

          def hosted_index
            return {} if ENV["MASTER_NO_POOL_PROBES"] == "1"

            @hosted_index ||= hosted_endpoints.each_with_object({}) do |(name, spec), index|
              key = hosted_key(spec)
              # An endpoint with no keyless rule answers nothing without a key,
              # so it is not asked until one is set.
              next if key.nil? && !spec.key?("keyless")

              hosted_ids(spec, key).each { |id| index["#{name}:#{id}"] ||= { base: spec["base"], key: } }
            end
          end

          def hosted_key(spec)
            Array(spec["key_env"]).map { |env| ENV[env].to_s }.find { |value| !value.empty? }
          end

          def hosted_ids(spec, key)
            headers = key ? { "Authorization" => "Bearer #{key}" } : {}
            body = get_json("#{spec["base"].chomp("/")}/models", headers:, timeout: HOSTED_TIMEOUT_S)
            rows = Array(JSON.parse(body.to_s)["data"]).select { |row| row.fetch("model_type", "chat") == "chat" }
            rows = rows.select { |row| Hash(spec["keyless"]).all? { |field, want| row[field] == want } } unless key
            rows.filter_map { |row| row["id"] }
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "model_router.hosted", endpoint: spec["base"])
            []
          end
        end
      end
    end
  end
end
