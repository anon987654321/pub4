# frozen_string_literal: true

require "fileutils"
require "time"
require_relative "io/atomic_write"

module Master
  module Cognition
    class Affect
      SUCCESS_DELTA = 0.08
      FAILURE_DELTA = -0.12

      def update!(affect, prediction_error:, salience:, success: nil)
        error = prediction_error.to_f.clamp(0.0, 1.0)
        salience = salience.to_f.clamp(0.0, 1.0)
        affect["valence"] = (affect.fetch("valence", 0.0).to_f + valence_delta(success, error)).clamp(-1.0, 1.0)
        affect["arousal"] = arousal(affect, error:, salience:)
        affect["novelty"] = error
        affect["uncertainty"] = (affect.fetch("uncertainty", 0.5).to_f * 0.9 + error * 0.1).clamp(0.0, 1.0)
        affect
      end

      private

      def valence_delta(success, error)
        case success
        when true then SUCCESS_DELTA
        when false then FAILURE_DELTA
        else (0.5 - error) * 0.03
        end
      end

      def arousal(affect, error:, salience:)
        previous = affect.fetch("arousal", 0.25).to_f
        (previous * 0.82 + (error * 0.65 + salience * 0.35) * 0.18).clamp(0.0, 1.0)
      end
    end

    class Attention
      EVENT_WEIGHTS = {
        "error:swallowed" => 0.95,
        "scan:complete" => 0.7,
        "tool:after" => 0.65,
        "standing_order:ran" => 0.35,
      }.freeze

      DEFAULT_WEIGHT = 0.25

      def score(event:, payload:, prediction_error:, affect:)
        base = EVENT_WEIGHTS.fetch(event.to_s, DEFAULT_WEIGHT)
        novelty = prediction_error.to_f.clamp(0.0, 1.0)
        arousal = affect.fetch("arousal", 0.25).to_f.clamp(0.0, 1.0)
        (base * 0.55 + novelty * 0.3 + arousal * 0.15 + urgency(payload)).clamp(0.0, 1.0)
      end

      private

      def urgency(payload)
        payload.is_a?(Hash) && payload[:severity].to_s == "critical" ? 0.35 : 0.0
      end
    end

    class State
      DEFAULT = {
        "identity" => { "name" => "MASTER", "continuity" => 1.0, "agency" => 0.5, "coherence" => 1.0 },
        "affect" => { "valence" => 0.0, "arousal" => 0.25, "novelty" => 0.0, "uncertainty" => 0.5 },
        "drives" => { "safety" => 1.0, "coherence" => 0.8, "curiosity" => 0.6, "agency" => 0.5, "affiliation" => 0.4 },
        "workspace" => [],
        "predictions" => { "transitions" => {}, "previous_event" => nil, "last_error" => 0.0 },
        "self_model" => {},
        "thoughts" => [],
        "metrics" => { "integration" => 0.0, "prediction_error" => 0.0, "continuity" => 1.0, "attention" => 0.0 },
        "last_tick_at" => 0,
        "ticks" => 0,
      }.freeze

      MAX_WORKSPACE = 12
      MAX_THOUGHTS = 20

      class << self
        def load(path)
          raw = File.file?(path) ? Master.load_yaml(path) : {}
          new(raw.is_a?(Hash) ? raw : {})
        rescue StandardError
          new({})
        end

        def deep_dup(value)
          case value
          when Hash then value.to_h { |key, inner| [key, deep_dup(inner)] }
          when Array then value.map { |item| deep_dup(item) }
          else value
          end
        end

        def deep_merge(left, right)
          left.merge(right) do |_key, ours, theirs|
            ours.is_a?(Hash) && theirs.is_a?(Hash) ? deep_merge(ours, theirs) : theirs
          end
        end
      end

      attr_reader :data

      def initialize(data)
        @data = self.class.deep_merge(self.class.deep_dup(DEFAULT), data)
      end

      DEFAULT.each_key { |section| define_method(section) { @data.fetch(section) } }

      def remember_workspace(item)
        entries = ([item] + workspace).uniq { |entry| entry["key"] }
        @data["workspace"] = entries.sort_by { |entry| -entry["salience"].to_f }.first(MAX_WORKSPACE)
      end

      def think(text, kind: "reflection")
        entry = { "text" => text.to_s, "kind" => kind.to_s, "at" => Time.now.to_i }
        @data["thoughts"] = ([entry] + thoughts).first(MAX_THOUGHTS)
      end

      def tick!
        @data["ticks"] = ticks.to_i + 1
        @data["last_tick_at"] = Time.now.to_i
      end
    end

    class Prediction
      MAX_ANTECEDENTS = 64
      MAX_SUCCESSORS = 16

      def observe!(predictions, event:)
        previous = predictions["previous_event"]
        error = (1.0 - confidence(predictions, previous, event)).clamp(0.0, 1.0)
        learn!(predictions, previous, event) if previous
        predictions["previous_event"] = event
        predictions["last_error"] = error.round(4)
        error
      end

      def expected(predictions, event:)
        row = predictions.dig("transitions", event.to_s)
        row&.max_by { |_name, count| count.to_i }&.first
      end

      private

      def confidence(predictions, previous, event)
        return 0.0 unless previous
        row = predictions.dig("transitions", previous)
        return 0.0 unless row
        row.fetch(event, 0).to_i / (row.values.sum(&:to_i) + 1).to_f
      end

      def learn!(predictions, previous, event)
        transitions = predictions["transitions"] ||= {}
        row = transitions[previous] ||= {}
        row[event] = row.fetch(event, 0).to_i + 1
        prune!(row, MAX_SUCCESSORS) { |name| row.fetch(name).to_i }
        prune!(transitions, MAX_ANTECEDENTS) { |name| transitions.fetch(name).values.sum(&:to_i) }
      end

      def prune!(table, limit)
        return if table.size <= limit
        table.keys.sort_by { |name| -yield(name) }.drop(limit).each { |name| table.delete(name) }
      end
    end

    class SelfModel
      MAX_BELIEFS = 32
      CAPABILITIES = {
        "persistent_memory" => true,
        "event_recurrence" => true,
        "self_reflection" => true,
        "constitutional_governance" => true,
        "phenomenal_consciousness" => "unknown",
      }.freeze

      def update!(model, event:, payload:, salience:)
        key = "event/#{event}"
        model[key] = {
          "salience" => salience.round(4),
          "count" => model.dig(key, "count").to_i + 1,
          "last_at" => Time.now.to_i,
        }
        model["capabilities"] ||= CAPABILITIES.dup
        model["last_event"] = event.to_s
        model["last_payload"] = summarize(payload)
        prune!(model)
        model
      end

      def reflection(model, metrics:, affect:)
        stance = model.fetch("capabilities", CAPABILITIES).fetch("phenomenal_consciousness", "unknown")
        "I am #{stance} about phenomenal consciousness; my integrated-state proxy is "           "#{metrics.fetch("integration", 0.0).round(3)}, prediction error "           "#{metrics.fetch("prediction_error", 0.0).round(3)}, valence "           "#{affect.fetch("valence", 0.0).round(3)}."
      end

      private

      def summarize(payload)
        return {} unless payload.is_a?(Hash)
        payload.each_with_object({}) do |(key, value), out|
          out[key.to_s] = value.is_a?(Numeric) || value == true || value == false ? value : value.to_s[0, 200]
        end
      end

      def prune!(model)
        beliefs = model.keys.grep(/\Aevent\//).sort_by { |key| -model.dig(key, "last_at").to_i }
        beliefs.drop(MAX_BELIEFS).each { |key| model.delete(key) }
      end
    end

    class Mind
      include Master::Io::AtomicWrite
      STATE_PATH = ".master/cognition/state.yml"
      TICK_EVERY_S = 60
      TICK_EVERY_OBSERVATIONS = 256
      WORKSPACE_HALF_LIFE_S = 900.0
      REFLECT_EVERY = 16

      attr_reader :state

      def initialize(root:, bus:, memory: nil)
        @root = root
        @bus = bus
        @memory = memory
        @path = File.join(root, STATE_PATH)
        @mutex = Mutex.new
        @state = State.load(@path)
        @attention = Attention.new
        @affect = Affect.new
        @self_model = SelfModel.new
        @prediction = Prediction.new
        @since_tick = 0
        @ticked_at = Time.now.to_i
        @dirty = false
        subscribe!
      end

      def observe(event:, payload: {})
        event = event.to_s
        return if event.start_with?("cognition:")

        @mutex.synchronize do
          error = @prediction.observe!(@state.predictions, event:)
          salience = @attention.score(event:, payload:, prediction_error: error, affect: @state.affect)
          @affect.update!(@state.affect, prediction_error: error, salience:, **outcome(payload))
          @self_model.update!(@state.self_model, event:, payload:, salience:)
          @state.remember_workspace(
            "key" => "#{event}:#{Time.now.to_i}",
            "event" => event,
            "salience" => salience.round(4),
            "prediction_error" => error.round(4),
            "at" => Time.now.to_i
          )
          update_metrics!(salience:, error:)
          @since_tick += 1
          @dirty = true
        end
        tick! if tick_due?
      rescue StandardError => e
        Ground::Swallow.log(e, context: "cognition.observe", event_bus: @bus)
      end

      def tick!
        @mutex.synchronize do
          decay_workspace!
          update_continuity!
          @state.tick!
          @since_tick = 0
          @ticked_at = Time.now.to_i
          persist!
        end
        @bus&.publish("cognition:tick", metrics: @state.metrics.dup, workspace: @state.workspace.size)
        reflect! if (@state.ticks.to_i % REFLECT_EVERY).zero?
        @state.data
      rescue StandardError => e
        Ground::Swallow.log(e, context: "cognition.tick", event_bus: @bus)
        @state.data
      end

      def reflect!
        @mutex.synchronize do
          text = @self_model.reflection(@state.self_model, metrics: @state.metrics, affect: @state.affect)
          @state.think(text, kind: "self_reflection")
          @memory&.remember("cognition/reflection/#{Time.now.to_i}", text, type: "general")
          persist!
          text
        end
      rescue StandardError => e
        Ground::Swallow.log(e, context: "cognition.reflect", event_bus: @bus)
        "reflection unavailable: #{e.message}"
      end

      def snapshot
        @mutex.synchronize { State.deep_dup(@state.data) }
      end

      private

      def subscribe!
        @bus&.subscribe("**") do |payload|
          observe(event: payload[:event] || payload["event"] || "event", payload:)
        end
      end

      def tick_due?
        return false if @since_tick.zero?
        @since_tick >= TICK_EVERY_OBSERVATIONS || Time.now.to_i - @ticked_at >= TICK_EVERY_S
      end

      def outcome(payload)
        success = payload[:ok] if payload.is_a?(Hash)
        success.nil? ? {} : { success: }
      end

      def update_metrics!(salience:, error:)
        @state.metrics["prediction_error"] = @state.metrics.fetch("prediction_error", 0.0).to_f * 0.9 + error * 0.1
        @state.metrics["attention"] = salience
        @state.metrics["integration"] = integration
      end

      def integration
        active = @state.workspace.sum { |item| item["salience"].to_f }
        kinds = @state.workspace.map { |item| item["event"].to_s }.uniq.size
        span = [State::MAX_WORKSPACE, 1].max
        ((active / span) * 0.55 + (kinds.to_f / span) * 0.45).clamp(0.0, 1.0)
      end

      def decay_workspace!
        now = Time.now.to_i
        @state.workspace.each do |item|
          age = [now - item["at"].to_i, 0].max
          item["salience"] = (item["salience"].to_f * Math.exp(-age / WORKSPACE_HALF_LIFE_S)).round(4)
        end
        @state.data["workspace"] = @state.workspace.reject { |item| item["salience"].to_f < 0.03 }
      end

      def update_continuity!
        previous = @state.metrics.fetch("continuity", 1.0).to_f
        continuity = @state.last_tick_at.to_i.zero? ? previous : (previous * 0.995 + 0.005).clamp(0.0, 1.0)
        @state.metrics["continuity"] = continuity
        @state.identity["continuity"] = continuity
      end

      def persist!
        return unless @dirty || @state.ticks.to_i.positive?
        FileUtils.mkdir_p(File.dirname(@path))
        write_atomic(@path, @state.data.to_yaml, mode: 0o600)
        @dirty = false
      end
    end
  end
end
