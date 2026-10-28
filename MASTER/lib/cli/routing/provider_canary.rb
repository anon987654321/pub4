# frozen_string_literal: true

require_relative "provider_health"
require_relative "../../execution/contract"

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

          retest_dead_lanes
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
          provider.to_s.empty? ? provider_key(id) : provider.to_s
        rescue StandardError
          provider_key(id)
        end

        def provider_key(value)
          value.to_s.tr("\\", "/").split(/[:\/]/, 2).first
        end

        private

        # Timed/unknown quota deaths are revived and tested. Manual exclusions get
        # one real canary probe per run; a successful answer retires the stale
        # exclusion in the effective state, without editing operator-owned data/.
        def retest_dead_lanes
          Master::Io::LaneState.due_probes.each do |lane|
            model = Master::Io::LaneHealth.model_for_lane(lane)
            next unless model

            Master::Io::LaneQuota.revive(lane)
            probe(model)
          end

          return unless defined?(Master::Review::Agent) && @agent.is_a?(Master::Review::Agent)

          manual_models = Master::Io::LaneState.manual_dead.filter_map do |lane|
            model = Master::Io::LaneHealth.model_for_lane(lane)
            [lane, model] if model
          end.to_h
          lane = Master::Io::LaneQuota.due_manual_probes(known: manual_models.keys, limit: 1).first
          return unless lane

          result = Master::Io::LaneQuota.with_manual_probe(lane) { probe(manual_models.fetch(lane)) }
          Master::Io::LaneQuota.revive_manual(lane) if result[:ok]
        end

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
          if @router.respond_to?(:record_provider_outcome)
            # The production router records health and applies quarantine in one
            # path. Recording only in @health would rank the provider lower but
            # never create the quarantine event that removes it from the pool.
            @router.record_provider_outcome(model:, status:, latency_ms:, error:)
          else
            @health.record(model:, status:, latency_ms:, error:)
          end
          @bus&.publish(
            "provider:canary",
            model:, domain: provider_domain(model), status:, latency_ms:,
            **Master::Execution::Contract.diagnostic_fields(error)
          )
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
