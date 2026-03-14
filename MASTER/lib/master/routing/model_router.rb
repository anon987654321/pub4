# frozen_string_literal: true

require "yaml"

module Master
  module Routing
    class ModelRouter
      # Phrases that indicate the model is uncertain — trigger escalation.
      UNCERTAINTY_PHRASES = %w[
        i'm\ not\ sure i\ don't\ know cannot\ determine unclear uncertain
        might\ be possibly probably\ not limited\ information i\ cannot i\ am\ unable
        i\ lack\ the not\ enough\ information i\ would\ need\ more
      ].freeze

      def initialize(config:, root: Master::ROOT, continuity_index: nil)
        @config = config
        @root = root
        @rules = load_rules
        @continuity_index = continuity_index || ContinuityIndex.new(root: @root)
      end

      def primary(task_type: :exploration)
        return @config.model unless enabled?

        tier = @rules.dig("routes", task_type.to_s) || @rules.dig("routes", "fallback_default") || "cheap"
        candidates = @rules.dig("models", tier).to_a
        return @config.model if candidates.empty?

        best = candidates.max_by { |m| weighted_score(m["score"] || {}) }
        best["id"] || @config.model
      end

      def fallback_chain(task_type: :exploration)
        return [@config.model] unless enabled?

        preferred = primary(task_type:)
        all = @rules.fetch("models", {}).values.flatten.map { |m| m["id"] }.compact
        continuity = @continuity_index.fallback_models
        ([preferred] + all + continuity + [@config.model]).uniq
      end

      # Returns true if the response text suggests insufficient confidence.
      # Used by Execute stage to decide whether to retry with a stronger model.
      def escalate?(response, threshold: 0.3)
        return false unless @rules.dig("routing", "escalation_enabled")
        text = response.to_s.downcase
        hits = UNCERTAINTY_PHRASES.count { |p| text.include?(p) }
        hits.to_f / UNCERTAINTY_PHRASES.size >= threshold
      end

      # Return the best model from the escalation tier (default: "strong").
      def escalated_model(task_type: :exploration)
        tier = @rules.dig("routing", "escalation_tier") || "strong"
        candidates = @rules.dig("models", tier).to_a
        return primary(task_type:) if candidates.empty?
        candidates.max_by { |m| weighted_score(m["score"] || {}) }&.dig("id") || primary(task_type:)
      end

      private

      def enabled?
        @rules.dig("routing", "enabled") != false
      end

      def weighted_score(score)
        w = @rules.fetch("weights", {})
        quality_w = w.fetch("quality", 0.0).to_f
        speed_w   = w.fetch("speed",   0.0).to_f
        cost_w    = w.fetch("cost",    0.0).to_f

        (score.fetch("quality", 0.0).to_f * quality_w) +
          (score.fetch("speed", 0.0).to_f * speed_w) +
          (score.fetch("cost",  0.0).to_f * cost_w)
      end

      def load_rules
        path = File.join(@root, "data", "models.yml")
        YAML.safe_load_file(path) || {}
      rescue StandardError
        {}
      end
    end
  end
end
