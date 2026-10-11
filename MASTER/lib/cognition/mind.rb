# frozen_string_literal: true

require "fileutils"
require_relative "../io/atomic_write"
require_relative "state"
require_relative "outcome_model"
require_relative "fix_outcome"
require_relative "prediction"
require_relative "self_model"

module Master
  module Cognition
    # A bounded observer over the event bus. Observations update prediction,
    # attention, affect and self-model state in memory; tick! persists it atomically.
    # The subscription uses ** because event topics are namespaced. Metrics are
    # named for the behaviour they measure and do not imply subjective experience.
    class Mind
      include ::Master::Io::AtomicWrite
      include FixOutcome
      STATE_PATH = State::PATH
      TICK_EVERY_S = 60
      TICK_EVERY_OBSERVATIONS = 256
      WORKSPACE_HALF_LIFE_S = 900.0
      REFLECT_EVERY = 16

      attr_reader :state

      def initialize(root:, bus:, memory: nil)
        @root = root
        @repo_root = File.expand_path(root) == Master::ROOT ? Master::REPO_ROOT : File.expand_path(root)
        @bus = bus
        @memory = memory
        @path = File.join(root, STATE_PATH)
        @mutex = Mutex.new
        @state = State.load(@path)
        @state.metrics["restore_completeness"] = @state.restore_completeness
        @attention = Attention.new
        @affect = Affect.new
        @self_model = SelfModel.new
        @prediction = Prediction.new
        @outcome_model = OutcomeModel.new
        @since_tick = 0
        # From construction, not from the loaded state's `last_tick_at`: that one
        # is wall-clock from a previous process and is days stale after a restart,
        # which would make the first observation of every boot due.
        @ticked_at = Time.now.to_i
        @dirty = false
        subscribe!
      end

      def observe(event:, payload: {})
        event = event.to_s
        return if event.start_with?("cognition:")

        @mutex.synchronize do
          error = @prediction.observe!(@state.predictions, event:, context: prediction_context(payload))
          salience = @attention.score(event:, payload:, prediction_error: error, affect: @state.affect)
          @affect.update!(@state.affect, prediction_error: error, salience:, **outcome(payload))
          @self_model.update!(@state.self_model, event:, payload:, salience:)
          @state.remember_workspace(
            "key" => "#{event}:#{Time.now.to_i}", "event" => event, "salience" => salience.round(4),
            "prediction_error" => error.round(4), "at" => Time.now.to_i
          )
          update_metrics!(salience:, error:)
          @since_tick += 1
          @dirty = true
        end
        # Outside the lock on purpose: tick! takes the same mutex, and a
        # non-reentrant Mutex deadlocks the publishing thread rather than
        # recursing. The bus itself is a Monitor and calls handlers unlocked, so
        # the tick's own publish from inside this one is safe.
        # A terminal repair outcome feeds the next run's review strategy, so it
        # must survive even when the process goes idle or restarts immediately.
        tick! if event == "fix_loop:terminal" || tick_due?
      rescue StandardError => e
        Ground::Swallow.log(e, context: "cognition.observe", event_bus: @bus)
      end

      # The only writer, and the only publisher. Perception stays silent because
      # publishing per observation doubles every event on a bus this subscribes
      # to all of.
      def tick!
        @mutex.synchronize do
          decay_workspace!
          @state.tick!
          @since_tick = 0
          @ticked_at = Time.now.to_i
          persist!
        end
        @bus&.publish(
          "cognition:tick",
          metrics: @state.metrics.dup,
          restoration: { status: @state.load_status, completeness: @state.restore_completeness },
          workspace: @state.workspace.size,
        )
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

      # Predict from verified task history. Sparse history stays explicitly
      # insufficient; a prior is not presented as learned knowledge.
      def predict_outcome(context:, action:)
        @mutex.synchronize { @outcome_model.predict(@state.outcomes, context:, action:) }
      end

      # The write path for outcome learning. Evidence must identify an artifact
      # and its SHA-256; raw event payloads are not accepted as verified outcomes.
      def record_task_result(context:, action:, outcome:, evidence:, predicted_probability: nil)
        receipt = OutcomeModel.validate_evidence!(evidence, root: @repo_root)
        @mutex.synchronize do
          prediction = @outcome_model.observe!(
            @state.outcomes, context:, action:, outcome:, evidence: receipt, predicted_probability:
          )
          @dirty = true
          persist!
          prediction
        end
      end

      def snapshot = @mutex.synchronize { State.deep_dup(@state.data) }

      private

      def subscribe!
        @bus&.subscribe("**") do |payload|
          event = payload[:event] || payload["event"] || "event"
          observe(event:, payload:)
          capture_fix_outcome(payload) if event == "fix_loop:terminal"
        end
      end

      def tick_due?
        return false if @since_tick.zero?

        @since_tick >= TICK_EVERY_OBSERVATIONS || Time.now.to_i - @ticked_at >= TICK_EVERY_S
      end

      # Prefer task-scoped streams when events carry an explicit correlation
      # identifier. Unscoped events remain supported but are only temporal
      # adjacency evidence; their order must not be interpreted as causation.
      def prediction_context(payload)
        return unless payload.is_a?(Hash)

        %i[task_id run_id mission_id].each do |key|
          value = payload[key] || payload[key.to_s]
          next if value.nil? || value.to_s.strip.empty?

          # Run/task/mission identifiers describe one work stream even when
          # publishers use different field names for the same identifier.
          return "work:#{value.to_s.strip[0, 128]}"
        end
        nil
      end

      def outcome(payload)
        return {} unless payload.is_a?(Hash)

        success = payload.key?(:ok) ? payload[:ok] : payload["ok"]
        success == true || success == false ? { success: } : {}
      end

      def update_metrics!(salience:, error:)
        @state.metrics["prediction_error"] = @state.metrics.fetch("prediction_error", 0.0).to_f * 0.9 + error * 0.1
        @state.metrics["attention"] = salience
        @state.metrics["workspace_activity"] = workspace_activity
        @state.metrics["restore_completeness"] = @state.restore_completeness
      end

      # A bounded activity/diversity proxy for the working set. It is not a
      # measure of integrated information, selfhood, or subjective experience.
      def workspace_activity
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

      def persist!
        # Never replace unreadable state with defaulted state automatically. Keep
        # the source intact for diagnosis; the restoration event exposes the fault.
        return if @state.load_status == "invalid"
        return unless @dirty || @state.ticks.to_i.positive?

        FileUtils.mkdir_p(File.dirname(@path))
        write_atomic(@path, @state.data.to_yaml, mode: 0o600)
        @dirty = false
      end
    end
  end
end
