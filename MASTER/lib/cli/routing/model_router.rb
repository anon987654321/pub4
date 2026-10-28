# frozen_string_literal: true

require_relative "model_router/provider_availability"
require_relative "model_router/route_policy"
require_relative "model_router/selection"
require_relative "availability_policy"
require_relative "provider_health"
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
        include Selection

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
          @availability = AvailabilityPolicy.new(root: @root)
          @provider_health = provider_health || ProviderHealth.new(
            path: File.join(@root, "runtime", "telemetry", "provider_health.ndjson"),
          )
          @rules = load_laws
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
          # Diagnostics records the health event first. This method shadows the included
          # module method, so the explicit super keeps that recording wired.
          super
          @compute_pool&.record(model:, status:, latency_ms:, error:)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "model_router.record_provider_outcome")
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

        def load_laws
          path = File.join(@root, "data", "models.yml")
          Master.load_yaml(path) || {}
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "model_router.load_laws", path:)
          {}
        end
      end
    end
  end
end
