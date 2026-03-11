# frozen_string_literal: true

require "yaml"

module Master3
  module Routing
    class ModelRouter
      def initialize(config:, root: Master3::ROOT, continuity_index: nil)
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

      private

      def enabled?
        @rules.dig("routing", "enabled") != false
      end

      def weighted_score(score)
        w = @rules.fetch("weights", {})
        (score.fetch("quality", 0.0) * w.fetch("quality", 0.0)) +
          (score.fetch("speed", 0.0) * w.fetch("speed", 0.0)) +
          (score.fetch("cost", 0.0) * w.fetch("cost", 0.0))
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
