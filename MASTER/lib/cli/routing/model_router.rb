# frozen_string_literal: true

require_relative "model_router/provider_availability"
require_relative "model_router/escalation"
require_relative "model_router/intent_classification"
require_relative "model_router/failover_config"
require_relative "model_router/diagnostics"
require_relative "model_router/pool"
require_relative "model_router/hosted_endpoints"
require_relative "compute_pool"

module Master
  module CLI
    module Routing
      class ModelRouter
        include ProviderAvailability
        include Escalation
        include IntentClassification
        include FailoverConfig
        include Diagnostics
        include Pool
        include HostedEndpoints

        UNCERTAINTY_PHRASES = [
          "i'm not sure", "i don't know", "cannot determine",
          "unclear", "uncertain", "migh#{?t} be", "possibly",
          "probably not", "limited information", "i cannot",
          "i am unable", "i lack the", "not enough information",
          "i need more"
        ].freeze

        ESCALATION_CHAIN = %w[cheap default strong].freeze
        DEFAULT_THRESHOLD = 0.3

        def initialize(config:, root: Master::ROOT, provider_health: nil)
          @config = config
          @root = root
          @provider_health = provider_health
          @rules = load_rules
          @capability_map = Master::CLI::Routing::CapabilityMap.new(path: File.join(@root, "runtime", "telemetry", "model_capabilities.json"),
                                                                    write: Object.new.extend(Io::AtomicWrite).method(:write_atomic))
          @compute_pool = ComputePool.new(router: self, root: @root)
          start_pool_probes
        end

        def compute_pool
          @compute_pool
        end

        def api_provider_for(model_id)
          api_provider(model_id)
        end

        def capability_score(model_id, task_type: :exploration)
          @capability_map.score_for(model_id, task_type)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "model_router.capability_score", model: model_id)
          0.5
        end

        # ComputePool asks the router whether a model supports tool calls;
        # the same TOOL_CAPABLE_RE the dispatcher already builds from
        # data/models.yml#tool_capable_prefixes, not a second copy of it.
        def tool_capable?(model_id) = Review::LLMDispatcher::TOOL_CAPABLE_RE.match?(model_id.to_s.downcase)

        def record_provider_outcome(model:, status:, latency_ms: nil, error: nil)
          @compute_pool&.record(model:, status:, latency_ms:, error:)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "model_router.record_provider_outcome")
        end

        def preferred(task_type: :exploration)
          return @config.model unless enabled?

          empirical_best = @capability_map.best_model_for(task_type)
          candidates = reachable_candidates(task_type)
          return @config.model if candidates.empty?

          ids = healthy(candidates).filter_map { |model| model["id"] }
          ids = candidates.filter_map { |model| model["id"] } if ids.empty?
          @compute_pool.select(ids, task_type:, empirical_best:) || @config.model
        end

        # Only models the pool can reach. Free cloud lanes follow the tiers and
        # paid Replicate follows those. A discovered local model may join the
        # same live chain; local availability is not an offline contract.
        def fallback_chain(task_type: :exploration)
          return [@config.model] unless enabled?

          chain = chain_for(task_type).uniq.select { |id| reachable?(id) }
          chain = Io::ModelSkipCache.filter(chain)
          ranked = @provider_health ? @provider_health.rank(chain) : chain
          ranked = @compute_pool.rank(ranked, task_type:)
          Io::ModelSkipCache.filter(chitchat_head(ranked, task_type))
        end

        # Greetings are explicitly routed to the free tier. A locally installed
        # subscription CLI used to jump ahead of `pref`, contradicting the route
        # table and spending the strongest lane on “hello”. Keep it available as
        # fallback, but let the task-specific preference lead.
        def chain_for(task_type)
          lanes = { pref: [preferred(task_type:)], tiers: tier_ids.reject { |id| ollama_model?(id) },
                    free: continuity_models + ollama_cloud_models + local_server_models + hosted_models,
                    subscription: agy_catalog_models + Ground::AuthProfileLane.models_for_router(self) + primary_models + cli_lane_models }
          order = task_type.to_sym == :chitchat ? %i[pref tiers free subscription] : %i[subscription pref tiers free]
          order.flat_map { |lane| lanes.fetch(lane) } + replicate_models + local_models + [@config.model]
        end

        def constrained_for(operation:)
          constraint = @rules.dig("operation_constraints", operation.to_s)
          return preferred unless constraint

          min_quality = constraint.fetch("min_quality", 0.0).to_f
          preferred_tier = constraint.fetch("preferred_tier", "strong")
          candidates = @rules.dig("models", preferred_tier).to_a
          qualified = healthy(candidates).select { |m| m.dig("score", "quality").to_f >= min_quality }
          return preferred if qualified.empty?

          ids = qualified.filter_map { |m| m["id"] }
          @compute_pool.select(ids, task_type: operation) || preferred
        end

        INTENT_PATTERNS = {
          code_generation: /\b(implement|build|add|create|write|make|generate|scaffold|port|wire)\b/i,
          refactoring: /\b(refactor|rename|clean ?up|simplify|extract|inline|dedup|consolidate|tidy)\b/i,
          architecture: /\b(design|architect|structure|plan|approach|module|boundary|layer|topology)\b/i,
          review: /\b(review|critique|audit|check|council|tribunal|inspect|evaluate|judge)\b/i,
          explanation: /\b(explain|what is|how does|why does|describe|clarify|walk me through)\b/i,
        }.freeze
        CHITCHAT_GREETING_RE = /\A(?:hi|hello|hey|yo|sup|howdy|good (?:morning|afternoon|evening))[!?.…\s]*\z/i.freeze
        CHITCHAT_CASUAL_RE = /\b(?:how are you|what'?s up|thanks|thank you|nice to meet|good night)\b/i.freeze
        MEDIA_PLAY_RE = /\b(?:play|start|put on|spin|queue|open)\s+(?:some\s+)?(?:(?:j\s*)?dilla|radio(?:\s+bergen)?|warp\s+tunnel)\b/i.freeze
        MEDIA_ARTIST_RE = /\b(?:j\s*dilla|dilla\s+beats?|radio\s+bergen|flying\s+lotus|madlib)\b/i.freeze
        CHITCHAT_CASUAL_MAX_LENGTH = 120
        CHITCHAT_MAX_LENGTH = 80

        private

        # The pool ranks the whole chain by measured utility, and on a machine
        # with a subscription CLI that put the strongest lane ahead of the free
        # tier for "hello", which chain_for exists to prevent. For chitchat the
        # free and keyless lanes stay in front, in the pool's order.
        def chitchat_head(chain, task_type)
          return chain unless task_type.to_sym == :chitchat

          head = Array(@rules.dig("models", "free")).filter_map { |row| row["id"] } +
                 Array(@rules.dig("ferrum_web_chat", "free_latest"))
          chain.partition { |id| head.include?(id) }.flatten
        end

        def enabled?
          @rules.dig("routing", "enabled") != false
        end

        def reachable_candidates(task_type)
          tier = @rules.dig("routes", task_type.to_s) || @rules.dig("routes", "fallback_default") || "cheap"
          @rules.dig("models", tier).to_a.select { |model| reachable?(model["id"]) }
        end

        def healthy(models)
          models.reject { |m| unhealthy?(m["id"]) || !reachable?(m["id"]) }
        end

        def effective_score(model)
          weighted_score(model["score"] || {}) * health_score(model["id"])
        end

        def health_score(model_id)
          @provider_health ? @provider_health.score(model_id) : 1.0
        rescue StandardError
          1.0
        end

        def unhealthy?(model_id)
          return true if Io::ModelQuota.over_quota?(model_id)
          # llm_dispatcher.rb writes every failed call here regardless of which
          # path selected the model, but constrained_for (scan_semantic,
          # council, code_generation, ...) only ever consulted @provider_health,
          # which nothing in this codebase constructs — it is always nil. A
          # model that just failed kept winning the same weighted comparison on
          # the very next file, forever, since it never saw its own failure.
          return true if Io::ModelSkipCache.skipped?(model_id)
          @provider_health&.unhealthy?(model_id)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "ModelRouter.unhealthy?")
          false
        end

        def weighted_score(score)
          weights = @rules.fetch("weights", {})
          qw = [weights.fetch("quality", 1.0).to_f, 0.01].max
          sw = [weights.fetch("speed", 1.0).to_f, 0.01].max
          cw = [weights.fetch("cost", 1.0).to_f, 0.01].max
          q = score.fetch("quality", 0.5).to_f * qw
          s = [score.fetch("speed", 1.0).to_f * sw, 0.01].max
          c = [score.fetch("cost", 0.5).to_f * cw, 0.001].max
          q * s * c
        end

        def load_rules
          path = File.join(@root, "data", "models.yml")
          Master.load_yaml(path) || {}
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "model_router.load_rules", path:)
          {}
        end
      end
    end
  end
end
