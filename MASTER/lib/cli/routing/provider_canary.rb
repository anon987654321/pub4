# frozen_string_literal: true

require_relative "provider_health"

module Master
  module CLI
    module Routing
      # A canary is a real dispatch with a unique prompt. That prevents the
      # semantic cache from turning yesterday's success into today's evidence.
      class ProviderCanary
        DEFAULT_MAX_PROVIDERS = 3
        PROMPT_PREFIX = "MASTER_CANARY".freeze

        def initialize(agent:, router:, event_bus: nil, max_providers: DEFAULT_MAX_PROVIDERS,
                       health: nil)
          @agent = agent
          @router = router
          @bus = event_bus
          @max_providers = [max_providers.to_i, 1].max
          @health = health || ProviderHealth.new
        end

        def run
          return "no agent" unless @agent
          return "no router" unless @router

          results = candidates.first(@max_providers).map { |model| probe(model) }
          passed = results.count { |result| result[:ok] }
          publish_summary(results)
          "#{passed}/#{results.size} canaries passed"
        end

        def candidates
          models = @router.respond_to?(:pool) ? Array(@router.pool(wait: false)) : []
          models.uniq { |model| provider_domain(model) }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "provider_canary.candidates", event_bus: @bus)
          []
        end

        def provider_domain(model)
          id = model.to_s
          return "claude-cli" if id.start_with?("claude-cli:")
          return "agy" if id.start_with?("agy:")
          return "web-chat" if id.start_with?("web-chat:")
          return "ollama" if id.start_with?("ollama:")
          return "local-server" if id.start_with?("local:")
          return "replicate" if id.start_with?("replicate:")

          provider = @router.api_provider_for(id) if @router.respond_to?(:api_provider_for)
          provider.to_s.empty? ? id.split(/[:\\/]/, 2).first : provider.to_s
        rescue StandardError
          id.split(/[:\\/]/, 2).first
        end

        private

        def probe(model)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          token = "#{PROMPT_PREFIX}_#{Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)}_#{model.hash.abs}"
          @bus&.publish("provider:canary_start", model:, domain: provider_domain(model))
          response = @agent.ask_once(
            "Reply with #{token} and nothing else.",
            system: "You are a health canary. Return the requested token exactly.",
            law: false,
            model:,
            temperature: 0,
            failover: false,
          )
          latency_ms = elapsed_ms(started)
          ok = response.to_s.include?(token)
          status = ok ? :success : :canary_validation_failure
          error = ok ? nil : "canary response did not contain its token"
          record(model:, status:, latency_ms:, error:)
          { model:, domain: provider_domain(model), ok:, latency_ms:, error: }
        rescue StandardError => e
          latency_ms = elapsed_ms(started)
          record(model:, status: :canary_failure, latency_ms:, error: e.message)
          { model:, domain: provider_domain(model), ok: false, latency_ms:, error: e.message }
        end

        def record(model:, status:, latency_ms:, error:)
          @health.record(model:, status:, latency_ms:, error:) if status == :canary_validation_failure
          @bus&.publish("provider:canary", model:, domain: provider_domain(model), status:, latency_ms:, error:)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "provider_canary.record", event_bus: @bus)
        end

        def publish_summary(results)
          @bus&.publish(
            "provider:canary_summary",
            passed: results.count { |result| result[:ok] },
            total: results.size,
            domains: results.map { |result| result[:domain] }.uniq,
          )
        end

        def elapsed_ms(started)
          ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        end
      end
    end
  end
end
