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

      def initialize(config:, root: Master::ROOT)
        @config = config
        @root = root
        @rules = load_rules
      end

      def preferred(task_type: :exploration)
        return @config.model unless enabled?

        tier = @rules.dig("routes", task_type.to_s) || @rules.dig("routes", "fallback_default") || "cheap"
        candidates = @rules.dig("models", tier).to_a
        return @config.model if candidates.empty?

        best = candidates.max_by { |m| weighted_score(m["score"] || {}) }
        best["id"] || @config.model
      end

      def fallback_chain(task_type: :exploration)
        return [@config.model] unless enabled?

        pref = preferred(task_type:)
        all = @rules.fetch("models", {}).values.flat_map { |tier| tier.filter_map { |m| m["id"] } }
        ([pref] + all + continuity_models + [@config.model]).uniq
      end

      def continuity_models
        return [] if @rules.dig("continuity", "enabled") == false
        latest = [
          @rules.dig("openrouter", "free_latest"),
          @rules.dig("ferrum_web_chat", "free_latest")
        ]
        flat = latest.flatten.compact
        flat.uniq
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

        candidates.max_by { |m| weighted_score(m["score"] || {}) }&.dig("id") || preferred(task_type:)
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
        qualified = candidates.select { |m| m.dig("score", "quality").to_f >= min_quality }
        return preferred if qualified.empty?

        qualified.max_by { |m| weighted_score(m["score"] || {}) }&.dig("id") || preferred
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
        sw = [weights.fetch("speed",   1.0).to_f, 0.01].max
        cw = [weights.fetch("cost",    1.0).to_f, 0.01].max
        candidates.map { |m|
          s = m["score"] || {}
          q = s.fetch("quality", 0.5).to_f * qw
          sp = [s.fetch("speed", 1.0).to_f * sw, 0.01].max
          co = [s.fetch("cost",  0.5).to_f * cw, 0.001].max
          { id: m["id"], q:, s: sp, c: co, total: q * sp * co }
        }.sort_by { |x| -x[:total] }
      end

INTENT_PATTERNS = {
  code_generation: /\b(implement|build|add|create|write|make|generate|scaffold|port|wire)\b/i,
  refactoring:     /\b(refactor|rename|clean ?up|simplify|extract|inline|dedup|consolidate|tidy)\b/i,
  architecture:    /\b(design|architect|structure|plan|approach|module|boundary|layer|topology)\b/i,
  review:          /\b(review|critique|audit|check|council|tribunal|inspect|evaluate|judge)\b/i,
  explanation:     /\b(explain|what is|how does|why does|describe|clarify|walk me through)\b/i
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

      private

      def enabled?
        @rules.dig("routing", "enabled") != false
      end

      def weighted_score(score)
        weights = @rules.fetch("weights", {})
        qw = [weights.fetch("quality", 1.0).to_f, 0.01].max
        sw = [weights.fetch("speed",   1.0).to_f, 0.01].max
        cw = [weights.fetch("cost",    1.0).to_f, 0.01].max
        q = score.fetch("quality", 0.5).to_f * qw
        s = [score.fetch("speed", 1.0).to_f * sw, 0.01].max
        c = [score.fetch("cost",  0.5).to_f * cw, 0.001].max
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
