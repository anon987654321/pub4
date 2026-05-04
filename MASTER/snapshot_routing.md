# MASTER Snapshot — lib/master/routing/
Generated: 2026-05-04T10:21:42Z

## lib/master/routing/continuity_index.rb
```ruby
# frozen_string_literal: true


module Master
  module Routing
    class ContinuityIndex
      def initialize(root: Master::ROOT)
        @root       = root
        @data_cache = nil
        @data_mtime = nil
      end

      def fallback_models
        return [] unless enabled?

        [openrouter_latest, ferrum_latest].flatten.compact.uniq
      end

      private

      def enabled?
        data.dig("continuity", "enabled") != false
      end

      def openrouter_latest
        data.dig("openrouter", "free_latest").to_a
      end


      def ferrum_latest
        data.dig("ferrum_web_chat", "free_latest").to_a
      end

      def data
        path = File.join(@root, "data", "models.yml")
        current_mtime = File.exist?(path) ? File.mtime(path) : nil

        if @data_cache.nil? || current_mtime != @data_mtime
          @data_cache = begin
            Master.load_yaml(path) || {}
          rescue StandardError => _e
            {}
          end
          @data_mtime = current_mtime
        end

        @data_cache
      end
    end
  end
end

```

## lib/master/routing/model_router.rb
```ruby
# frozen_string_literal: true

module Master
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

      def initialize(config:, root: Master::ROOT, continuity_index: nil)
        @config = config
        @root = root
        @rules = load_rules
        @continuity_index = continuity_index || ContinuityIndex.new(root: @root)
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
        continuity = @continuity_index.fallback_models
        ([pref] + all + continuity + [@config.model]).uniq
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
        return nil unless escalate?(response)

        strong_model = stronger_model(task_type:)
        return nil if current_model == strong_model

        strong_model
      end

      def tier_for_model(model_id)
        @rules.fetch("models", {}).each do |tier, models|
          return tier if models.is_a?(Array) && models.any? { |m| m["id"] == model_id }
        end
        "cheap"
      end

      def next_escalation_tier(current_tier)
        tier_index = ESCALATION_CHAIN.index(current_tier.to_s)
        return nil unless tier_index

        ESCALATION_CHAIN[tier_index + 1]
      end

      def confidence_threshold(task_type: :exploration)
        route = @rules.dig("routes", task_type.to_s)
        return DEFAULT_THRESHOLD unless route.is_a?(Hash)

        route.fetch("confidence_threshold", DEFAULT_THRESHOLD).to_f
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
        DecisionEngine.score(
          impact:     score.fetch("quality", 0.5).to_f * qw,
          confidence: [score.fetch("speed", 1.0).to_f * sw, 0.01].max,
          cost:       1.0 / [score.fetch("cost", 0.5).to_f * cw, 0.001].max
        )
      end

      def load_rules
        path = File.join(@root, "data", "models.yml")
        Master.load_yaml(path) || {}
      rescue StandardError => _e
        {}
      end
    end
  end
end

```
