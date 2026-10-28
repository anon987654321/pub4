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

          # A local OpenAI-compatible gateway is optional and deliberately opt-in.
          # Set MASTER_LLM_GATEWAY_URL to its /v1 base; the endpoint is then
          # discovered and routed through the same health/fallback chain as the
          # catalogued providers. No extra Ruby routing gem is required.
          def hosted_endpoints
            configured = @rules.fetch("openai_compatible", {}) || {}
            base = ENV["MASTER_LLM_GATEWAY_URL"].to_s.strip
            return configured if base.empty?

            configured.merge("gateway" => gateway_spec(base))
          rescue URI::Error, ArgumentError => e
            Master::Ground::Swallow.log(e, context: "model_router.gateway_config")
            configured || {}
          end

          def gateway_spec(base)
            uri = URI.parse(base)
            unless uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
              raise ArgumentError, "MASTER_LLM_GATEWAY_URL must be an absolute HTTP(S) URL"
            end
            if uri.userinfo || uri.query || uri.fragment
              raise ArgumentError, "MASTER_LLM_GATEWAY_URL must not include credentials, query or fragment"
            end
            if uri.scheme == "http" && !loopback_gateway_host?(uri.host)
              raise ArgumentError, "unencrypted remote gateway refused; use loopback HTTP or HTTPS"
            end

            {
              "base" => base.chomp("/"),
              "key_env" => %w[MASTER_LLM_GATEWAY_KEY FREELLMPOOL_PROXY_KEY],
              "keyless" => {},
            }
          end

          def loopback_gateway_host?(host)
            %w[localhost 127.0.0.1 ::1 [::1]].include?(host.to_s.downcase)
          end

          def hosted_index
            return {} if ENV["MASTER_NO_POOL_PROBES"] == "1"

            @hosted_index ||= hosted_endpoints.each_with_object({}) do |(name, spec), index|
              key = hosted_key(spec)
              # An endpoint with no keyless rule answers nothing without a key,
              # so it is not asked until one is set.
              next if key.nil? && !spec.key?("keyless")

              endpoint = {
                base: spec["base"],
                key:,
                quota_bucket: (spec["quota_bucket"] || name).to_s,
              }
              concurrency_key = if key.nil? && spec.key?("keyless_max_concurrency")
                                   "keyless_max_concurrency"
                                 else
                                   "max_concurrency"
                                 end
              if spec.key?(concurrency_key)
                endpoint[:max_concurrency] = Integer(spec.fetch(concurrency_key))
                raise ArgumentError, "openai_compatible.#{name}.#{concurrency_key} must be positive" unless endpoint[:max_concurrency].positive?
                endpoint[:concurrency_wait_seconds] = Float(spec.fetch("concurrency_wait_seconds", 15))
                raise ArgumentError, "openai_compatible.#{name}.concurrency_wait_seconds cannot be negative" if endpoint[:concurrency_wait_seconds].negative?
              end
              hosted_ids(spec, key).each { |id| index["#{name}:#{id}"] ||= endpoint }
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
