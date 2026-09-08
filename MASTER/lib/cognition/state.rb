# frozen_string_literal: true

module Master
  module Cognition
    # Durable internal state. This is a computational self-model, not evidence
    # that MASTER is phenomenally conscious.
    class State
      DEFAULT = {
        "identity" => { "name" => "MASTER", "continuity" => 1.0, "agency" => 0.5, "coherence" => 1.0 },
        "affect" => { "valence" => 0.0, "arousal" => 0.25, "novelty" => 0.0, "uncertainty" => 0.5 },
        "drives" => { "safety" => 1.0, "coherence" => 0.8, "curiosity" => 0.6, "agency" => 0.5, "affiliation" => 0.4 },
        "workspace" => [],
        "predictions" => {},
        "self_model" => {},
        "thoughts" => [],
        "metrics" => { "integration" => 0.0, "prediction_error" => 0.0, "continuity" => 1.0, "attention" => 0.0 },
        "last_tick_at" => 0,
        "ticks" => 0,
      }.freeze

      MAX_WORKSPACE = 12
      MAX_THOUGHTS = 20

      def self.load(path)
        raw = File.file?(path) ? Master.load_yaml(path) : {}
        new(deep_merge(deep_dup(DEFAULT), raw.is_a?(Hash) ? raw : {}))
      rescue StandardError
        new(deep_dup(DEFAULT))
      end

      def self.deep_dup(value)
        case value
        when Hash then value.each_with_object({}) { |(k, v), out| out[k] = deep_dup(v) }
        when Array then value.map { |item| deep_dup(item) }
        else value
        end
      end

      def self.deep_merge(left, right)
        left.merge(right) do |_key, a, b|
          a.is_a?(Hash) && b.is_a?(Hash) ? deep_merge(a, b) : b
        end
      end

      attr_reader :data

      def initialize(data)
        @data = self.class.deep_merge(self.class.deep_dup(DEFAULT), data)
      end

      def affect = @data.fetch("affect")
      def drives = @data.fetch("drives")
      def identity = @data.fetch("identity")
      def workspace = @data.fetch("workspace")
      def predictions = @data.fetch("predictions")
      def self_model = @data.fetch("self_model")
      def thoughts = @data.fetch("thoughts")
      def metrics = @data.fetch("metrics")
      def last_tick_at = @data.fetch("last_tick_at", 0)
      def ticks = @data.fetch("ticks", 0)

      def remember_workspace(item)
        @data["workspace"] = ([item] + workspace).uniq { |x| x["key"] }.first(MAX_WORKSPACE)
      end

      def think(text, kind: "reflection")
        @data["thoughts"] = ([{"text" => text.to_s, "kind" => kind.to_s, "at" => Time.now.to_i}] + thoughts).first(MAX_THOUGHTS)
      end

      def tick!
        @data["ticks"] = ticks.to_i + 1
        @data["last_tick_at"] = Time.now.to_i
      end
    end
  end
end
