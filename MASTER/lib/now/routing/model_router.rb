# frozen_string_literal: true

module Master
  module Now
    module Routing
      class ModelRouter
        UNCERTAINTY_PHRASES = [
          "i'm not sure", "i don't know", "cannot determine",
          "unclear", "uncertain", "might be", "possibly",
          "probably not", "limited information", "i cannot",
          "i am unable", "i lack the", "not enough information",
          "i would need more"
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
          chain = (primary_models + [pref] + all + continuity_models + [@config.model]).uniq
          @provider_health ? @provider_health.rank(chain) : chain
        end

        # Opus via the local claude subscription costs no tokens, so it leads whenever the
        # binary is present. The paid Opus API stays in the flattened tiers (escalation only).
        def primary_models
          return [] unless claude_cli_available?
          Array(@rules.dig("models", "primary")).filter_map { |m| m["id"] }
                                                .select { |id| id.to_s.start_with?("claude-cli:") }
        end

        def claude_cli_available?
          return false if ENV["MASTER_NO_CLAUDE_CLI"] == "1"
          return @claude_cli_available unless @claude_cli_available.nil?
          @claude_cli_available = ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
            exe = File.join(dir, "claude")
            File.file?(exe) && File.executable?(exe)
          end
        end

        def continuity_models
          return [] if @rules.dig("continuity", "enabled") == false
          latest = [@rules.dig("openrouter", "free_latest"), live_free_models]
          latest << @rules.dig("ferrum_web_chat", "free_latest") if web_chat_enabled?
          latest.flatten.compact.uniq
        end

        def web_chat_enabled?
          gate = @rules.dig("ferrum_web_chat", "enabled_when_env").to_s
          gate.empty? ? false : ENV[gate].to_s != ""
        end

        # Live free slugs refreshed into the SQLite catalog; read-only, never creates the DB.
        def live_free_models
          return [] unless @rules.dig("openrouter", "use_live_catalog")
          require_relative "../../providers/catalog_index"
          db = Providers::CatalogIndex::DEFAULT_DB
          return [] unless File.exist?(db)
          rows = Providers::CatalogIndex.new(db_path: db).search(":free", source: "openrouter", limit: 40)
          rows.filter_map { |row| row["id"] }.select { |id| id.to_s.end_with?(":free") }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "model_router.live_free_models")
          []
        end

        def escalate?(response, threshold: DEFAULT_THRESHOLD)
          return false unless @rules.dig("routing", "escalation_enabled")

          text = response.to_s.downcase
          hits = UNCERTAINTY_PHRASES.count { |p| text.include?(p) }
          hits.to_f / UNCERTAINTY_PHRASES.size >= threshold
        end

        def stronger_model(task_type: :exploration)
          tier = @rules.dig("routing", "escalation_tier") || "strong"
          candidates = @rules.dig("models", tier).to_a
          return preferred(task_type:) if candidates.empty?

          healthy(candidates).max_by { |m| effective_score(m) }&.dig("id") || preferred(task_type:)
        end

        def escalate_if_low_confidence(response, current_model:, task_type: :exploration)
          return unless escalate?(response)

          strong_model = stronger_model(task_type:)
          return if current_model == strong_model

          strong_model
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

        def tier_for_model(model_id)
          @rules.fetch("models", {}).each do |tier, models|
            return tier if models.is_a?(Array) && models.any? { |m| m["id"] == model_id }
          end
          "cheap"
        end

        def next_escalation_tier(current_tier)
          tier_index = ESCALATION_CHAIN.index(current_tier.to_s)
          return unless tier_index

          ESCALATION_CHAIN[tier_index + 1]
        end

        def confidence_threshold(task_type: :exploration)
          route = @rules.dig("routes", task_type.to_s)
          return DEFAULT_THRESHOLD unless route.is_a?(Hash)

          route.fetch("confidence_threshold", DEFAULT_THRESHOLD).to_f
        end

        def current_tier(task_type: :exploration)
          @rules.dig("routes", task_type.to_s) || @rules.dig("routes", "fallback_default") || "cheap"
        end

        def score_breakdown(task_type: :exploration)
          return [] unless enabled?
          candidates = @rules.dig("models", current_tier(task_type:)).to_a
          weights = @rules.fetch("weights", {})
          qw = [weights.fetch("quality", 1.0).to_f, 0.01].max
          sw = [weights.fetch("speed", 1.0).to_f, 0.01].max
          cw = [weights.fetch("cost", 1.0).to_f, 0.01].max
          candidates.map { |m|
            s = m["score"] || {}
            q = s.fetch("quality", 0.5).to_f * qw
            sp = [s.fetch("speed", 1.0).to_f * sw, 0.01].max
            co = [s.fetch("cost", 0.5).to_f * cw, 0.001].max
            { id: m["id"], q:, s: sp, c: co, total: q * sp * co }
          }.sort_by { |x| -x[:total] }
        end

        def record_provider_outcome(model:, status:, latency_ms: nil, error: nil)
          @provider_health&.record(model:, status:, latency_ms:, error:)
        rescue StandardError
          nil
        end

        INTENT_PATTERNS = {
          code_generation: /\b(implement|build|add|create|write|make|generate|scaffold|port|wire)\b/i,
          refactoring: /\b(refactor|rename|clean ?up|simplify|extract|inline|dedup|consolidate|tidy)\b/i,
          architecture: /\b(design|architect|structure|plan|approach|module|boundary|layer|topology)\b/i,
          review: /\b(review|critique|audit|check|council|tribunal|inspect|evaluate|judge)\b/i,
          explanation: /\b(explain|what is|how does|why does|describe|clarify|walk me through)\b/i
        }.freeze

        def classify_intent(text)
          s = text.to_s
          return :exploration if s.strip.empty?
          INTENT_PATTERNS.each { |intent, re| return intent if re.match?(s) }
          :exploration
        end

        def preferred_for(text)
          preferred(task_type: classify_intent(text))
        end

        def runtime_choice(task: :exploration)
          Master::Ground::RuntimeRegistry.new.choose(task:)
        rescue StandardError
          { provider: :local, model: preferred, score: 0.5, quarantined: [] }
        end

        def failover_max_retries
          @rules.dig("failover", "max_retries").to_i
        end

        def failover_cooldown_seconds
          val = @rules.dig("failover", "cooldown_seconds").to_i
          val.positive? ? val : 300
        end

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
        rescue StandardError
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
