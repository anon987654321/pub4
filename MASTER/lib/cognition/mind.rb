# frozen_string_literal: true

require "fileutils"
require "time"

module Master
  module Cognition
    # MASTER's persistent cognitive layer.
    #
    # This is an engineering implementation of several research-inspired
    # ingredients: recurrent perception, salience/attention, a global working
    # set, affect/homeostasis, autobiographical self-modeling, prediction error,
    # memory consolidation, and reflective thought. It intentionally calls its
    # consciousness-related numbers proxies; no software test can establish
    # phenomenal consciousness.
    class Mind
      STATE_PATH = ".master/cognition/state.yml"
      SAVE_EVERY = 8
      DECAY_S = 300

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
        @recent_events = {}
        @pending_since_save = 0
        subscribe!
      end

      def observe(event:, payload: {})
        event = event.to_s
        return if event.start_with?("cognition:")

        @mutex.synchronize do
          error = prediction_error(event)
          salience = @attention.score(event:, payload:, prediction_error: error, affect: @state.affect)
          success = payload[:ok] if payload.respond_to?(:key?)
          success = payload["ok"] if success.nil? && payload.is_a?(Hash)

          @affect.update!(@state.affect, prediction_error: error, salience:, success: success unless success.nil?)
          @self_model.update!(@state.self_model, event:, payload:, salience:)
          @state.remember_workspace(
            "key" => "#{event}:#{Time.now.to_i}",
            "event" => event,
            "salience" => salience.round(4),
            "prediction_error" => error.round(4),
            "at" => Time.now.to_i,
            "payload" => compact_payload(payload)
          )
          update_metrics!(error:, salience:)
          @recent_events[event] = Time.now.to_f
          @pending_since_save += 1
          persist! if @pending_since_save >= SAVE_EVERY || salience >= 0.9
        end

        publish_state(event:, salience:)
      rescue StandardError => e
        Ground::Swallow.log(e, context: "cognition.observe", event_bus: @bus)
      end

      def tick!
        @mutex.synchronize do
          decay_workspace!
          update_continuity!
          @state.tick!
          @pending_since_save += 1
          persist!
        end
        @bus&.publish("cognition:tick", metrics: @state.metrics.dup)
        reflection!
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
        @mutex.synchronize { Marshal.load(Marshal.dump(@state.data)) }
      end

      private

      def subscribe!
        return unless @bus

        @bus.subscribe("*") do |payload|
          event = payload[:event] || payload["event"] || payload[:type] || payload["type"]
          observe(event: event || "event", payload: payload)
        rescue StandardError => e
          Ground::Swallow.log(e, context: "cognition.event_subscription", event_bus: @bus)
        end
      end

      def prediction_error(event)
        now = Time.now.to_f
        last = @recent_events[event]
        return 1.0 unless last

        recurrence = now - last
        # Repetition quickly becomes predictable; long gaps become novel again.
        (recurrence / DECAY_S).clamp(0.05, 1.0)
      end

      def update_metrics!(error:, salience:)
        previous = @state.metrics.fetch("prediction_error", 0.0).to_f
        @state.metrics["prediction_error"] = previous * 0.9 + error * 0.1

        active = @state.workspace.sum { |item| item["salience"].to_f }
        diversity = @state.workspace.map { |item| item["event"].to_s }.uniq.length
        integration = ((active / [State::MAX_WORKSPACE, 1].max) * 0.55 +
          (diversity.to_f / [State::MAX_WORKSPACE, 1].max) * 0.45).clamp(0.0, 1.0)
        @state.metrics["integration"] = integration
        @state.metrics["attention"] = salience
      end

      def decay_workspace!
        now = Time.now.to_i
        @state.workspace.each do |item|
          age = [now - item["at"].to_i, 0].max
          item["salience"] = (item["salience"].to_f * Math.exp(-age / 900.0)).round(4)
        end
        @state.data["workspace"] = @state.workspace.reject { |item| item["salience"].to_f < 0.03 }
      end

      def update_continuity!
        previous = @state.metrics.fetch("continuity", 1.0).to_f
        gap = @state.last_tick_at.to_i.zero? ? 0 : Time.now.to_i - @state.last_tick_at.to_i
        continuity = gap.zero? ? previous : (previous * 0.995 + 0.005).clamp(0.0, 1.0)
        @state.metrics["continuity"] = continuity
        @state.identity["continuity"] = continuity
      end

      def reflection!
        return unless @state.ticks.to_i % 16 == 0

        reflect!
      end

      def compact_payload(payload)
        payload.to_h.each_with_object({}) do |(key, value), out|
          next if value.is_a?(Hash) && value.size > 12
          next if value.is_a?(Array) && value.size > 12

          out[key.to_s] = value.is_a?(String) ? value[0, 180] : value
        end
      end

      def publish_state(event:, salience:)
        @bus&.publish(
          "cognition:state",
          event: event,
          salience: salience,
          affect: @state.affect.dup,
          metrics: @state.metrics.dup,
          workspace_size: @state.workspace.size
        )
      end

      def persist!
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, @state.data.to_yaml, encoding: "UTF-8")
        @pending_since_save = 0
      end
    end
  end
end
