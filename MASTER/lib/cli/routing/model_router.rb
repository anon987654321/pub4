# frozen_string_literal: true

require_relative "model_router/provider_availability"
require_relative "model_router/escalation"
require_relative "model_router/intent_classification"
require_relative "model_router/failover_config"
require_relative "model_router/diagnostics"

module Master
  module CLI
    module Routing
      class ModelRouter
        include ProviderAvailability
        include Escalation
        include IntentClassification
        include FailoverConfig
        include Diagnostics

        UNCERTAINTY_PHRASES = [
          "i'm not sure", "i don't know", "cannot determine",
          "unclear", "uncertain", "migh#{?t} be", "possibly",
          "probably not", "limited information", "i cannot",
          "i am unable", "i lack the", "not enough information",
          "i need more",
        ].freeze

        ESCALATION_CHAIN = %w[cheap default strong].freeze
        DEFAULT_THRESHOLD = 0.3

        def initialize(config:, root: Master::ROOT, provider_health: nil)
          @config = config
          @root = root
          @provider_health = provider_health
          @rules = load_rules
        end

        def preferred(task_type: :exploration)
          return @config.model unless enabled?

          tier = @rules.dig("routes", task_type.to_s) || @rules.dig("routes", "fallback_default") || "cheap"
          candidates = @rules.dig("models", tier).to_a
          return @config.model if candidates.empty?

          best = healthy(candidates).max_by { |m| effective_score(m) }
          best ||= candidates.max_by { |m| effective_score(m) }
          best["id"] || @config.model
        end

        def fallback_chain(task_type: :exploration)
          return [@config.model] unless enabled?

          pref = preferred(task_type:)
          all = @rules.fetch("models", {}).values.flat_map { |tier| tier.filter_map { |m| m["id"] } }
          all = all.reject { |id| web_chat_model?(id) } unless web_chat_enabled?
          paid_or_subscription = Ground::AuthProfileLane.models_for_router(self) + primary_models
          # Greetings are explicitly routed to the free tier. A locally installed
          # subscription CLI used to jump ahead of `pref`, contradicting the route
          # table and spending the strongest lane on “hello”. Keep it available as
          # fallback, but let the task-specific preference lead.
          chain = if task_type.to_sym == :chitchat
                    ([pref] + all + continuity_models + paid_or_subscription + [@config.model]).uniq
                  else
                    (paid_or_subscription + [pref] + all + continuity_models + [@config.model]).uniq
                  end
          chain = chain.reject { |id| unreachable_agy?(id) }
          chain = Ground::ModelSkipCache.filter(chain)
          ranked = @provider_health ? @provider_health.rank(chain) : chain
          Ground::ModelSkipCache.filter(ranked)
        end

        def constrained_for(operation:)
          constraint = @rules.dig("operation_constraints", operation.to_s)
          return preferred unless constraint

          min_quality = constraint.fetch("min_quality", 0.0).to_f
          preferred_tier = constraint.fetch("preferred_tier", "strong")
          candidates = @rules.dig("models", preferred_tier).to_a
          qualified = healthy(candidates).select { |m| m.dig("score", "quality").to_f >= min_quality }
          return preferred if qualified.empty?

          qualified.max_by { |m| effective_score(m) }&.dig("id") || preferred
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

        def enabled?
          @rules.dig("routing", "enabled") != false
        end

        def healthy(models)
          models.reject { |m| unhealthy?(m["id"]) }
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
          return true if Ground::ModelQuota.over_quota?(model_id)
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
