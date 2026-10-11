# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require_relative "../io/atomic_write"
require_relative "outcome_model"

module Master
  module Cognition
    # MASTER's persistent cognitive layer: recurrent perception, salience, a
    # bounded working set, affect, self-modelling, prediction error, reflection
    # and evidence-backed task learning over one YAML file under .master/.
    # Cognitive metrics are operational proxies, not consciousness tests.
    #
    # Three things here are load-bearing and were each wrong once.
    #
    # The subscription is `**`, not `*`. EventBus compiles `*` to `[^:]*` and
    # `**` to `.*`, so `*` matches only colon-free event names, and every row in
    # Attention's weight table carries a colon. Under `*` the layer sees none of
    # the events it weighs and still looks wired.
    #
    # And nothing writes to disk from `observe`. A bus handler runs inside every
    # publish, a scan publishes thousands of events, and a YAML dump of the whole
    # state per eight of them is a scan that spends its time serialising a mood.
    # Perception marks the state dirty; `tick!` is what persists. The cost is
    # bounded: a crash loses the events since the last tick, which are in the
    # workspace and nowhere else by design.
    #
    # The third thing was worse than either, and invisible for the same reason
    # both of those were: perception ran and the loop did not. `tick!` had one
    # caller in the tree — boot/master_boot.rb:40, once, at startup — so the
    # workspace never decayed, continuity never moved, nothing after the boot
    # snapshot was ever written, and `REFLECT_EVERY` could not fire because
    # `ticks` stopped at 1 and `1 % 16` is not zero. MASTER perceived for the
    # life of the process and thought once, before anything had happened.
    #
    # So the cadence lives here rather than in a caller. The heartbeat was the
    # obvious home and is the wrong one: it is off by default, off in
    # boot/runtime.rb's guard list, and commented out in master.env.sample, so
    # hanging the loop there would have been the same defect wearing a schedule.
    # Perception is the one path every turn, scan, tool and daemon already
    # reaches — it subscribes to `**` — so the layer paces itself from what it
    # sees: a tick once a minute of activity, or every 256 observations,
    # whichever comes first. Idle costs nothing, because an idle bus makes no
    # observations to be due for.
    class Mind
      include ::Master::Io::AtomicWrite
      STATE_PATH = ".master/cognition/state.yml"
      TICK_EVERY_S = 60
      TICK_EVERY_OBSERVATIONS = 256
      WORKSPACE_HALF_LIFE_S = 900.0
      REFLECT_EVERY = 16

      attr_reader :state

      def initialize(root:, bus:, memory: nil)
        @root = File.expand_path(root)
        @repo_root = @root == Master::ROOT ? Master::REPO_ROOT : @root
        @bus = bus
        @memory = memory
        @path = File.join(@root, STATE_PATH)
        @mutex = Mutex.new
        @state = State.load(@path)
        unless @state.checkpoint_valid
          @state.metrics["continuity"] = 0.0
          @state.metrics["checkpoint_continuity"] = 0.0
          @state.identity["continuity"] = 0.0
        end
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
          error = @prediction.observe!(@state.predictions, event:)
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
        tick! if tick_due?
      rescue StandardError => e
        Ground::Swallow.log(e, context: "cognition.observe", event_bus: @bus)
      end

      # The only writer, and the only publisher. Perception stays silent because
      # publishing per observation doubles every event on a bus this subscribes
      # to all of.
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

      # Predict from verified task history. Sparse history remains explicitly
      # insufficient; a prior is not presented as learned knowledge.
      def predict_outcome(context:, action:)
        @mutex.synchronize { @outcome_model.predict(@state.outcomes, context:, action:) }
      end

      # Canonical write path for outcome learning and capability calibration.
      # Evidence must identify an artifact and its SHA-256; raw event payloads
      # are deliberately not accepted as verified outcomes.
      def record_task_result(context:, action:, outcome:, evidence:, task_type: nil,
                             confidence: nil, predicted_probability: nil)
        receipt = OutcomeModel.validate_evidence!(evidence, root: @repo_root)
        if task_type && %w[success failure].include?(outcome.to_s)
          raise ArgumentError, "task type is required" if task_type.to_s.strip.empty?
          probability = confidence.nil? ? predicted_probability : confidence
          unless probability.nil?
            probability = Float(probability)
            raise ArgumentError, "confidence must be between 0 and 1" unless probability.between?(0.0, 1.0)
          end
        end
        @mutex.synchronize do
          duplicate = @outcome_model.duplicate?(
            @state.outcomes, context:, action:, outcome:, evidence: receipt
          )
          prediction = @outcome_model.observe!(
            @state.outcomes, context:, action:, outcome:, evidence: receipt,
            predicted_probability:
          )
          if !duplicate && task_type && %w[success failure].include?(outcome.to_s)
            @self_model.record_assessment!(
              @state.self_model, task_type:, success: outcome.to_s == "success",
              confidence: confidence.nil? ? predicted_probability : confidence,
              source: receipt.fetch("source"), evidence_sha256: receipt.fetch("sha256"),
            )
          end
          @dirty = true
          persist!
          { prediction:, capabilities: @self_model.assessment_summary(@state.self_model) }
        end
      end

      def capability_report
        @mutex.synchronize { @self_model.assessment_summary(State.deep_dup(@state.self_model)) }
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

      # Learn from /fix only when the terminal event points to a durable receipt
      # whose bytes and declared run/state match. Provider prose and ordinary bus
      # events never qualify as task outcomes.
      def capture_fix_outcome(payload)
        envelope = payload[:outcome_receipt] || payload["outcome_receipt"]
        return unless envelope.is_a?(Hash)

        source = (envelope[:source] || envelope["source"]).to_s
        digest = (envelope[:sha256] || envelope["sha256"]).to_s
        receipt = OutcomeModel.validate_evidence!({ source:, sha256: digest }, root: @repo_root)
        body = receipt.fetch("content")
        data = JSON.parse(body.dup.force_encoding(Encoding::UTF_8))
        details = data["details"].is_a?(Hash) ? data["details"] : {}
        state = (payload[:state] || payload["state"]).to_s
        run_id = (payload[:run_id] || payload["run_id"]).to_s
        event_target = (payload[:target] || payload["target"]).to_s
        return unless data["command"] == "/fix" && data["state"].to_s == state
        return unless details["run_id"].to_s == run_id

        target = details["target"].to_s
        return if target.empty? || event_target != target
        prior = details["outcome_prior"]
        predicted_probability = if prior.is_a?(Hash) &&
                                   prior["context"].to_s == "target=#{target}" &&
                                   prior["action"].to_s == "/fix" &&
                                   prior["success_probability"].is_a?(Numeric) &&
                                   prior["success_probability"].between?(0.0, 1.0)
                                  prior["success_probability"].to_f
                                end

        tree = target.split("/").first
        tree = %w[MASTER RAILS OPENBSD STUDIO].include?(tree) ? tree.downcase : "other"
        outcome = case state
                  when "done" then "success"
                  when "failed", "crash", "validation_failed", "delivery_failed" then "failure"
                  else "inconclusive"
                  end
        record_task_result(
          context: "target=#{target}",
          action: "/fix",
          outcome:,
          evidence: receipt,
          task_type: "fix/#{tree}",
          predicted_probability:,
        )
      rescue StandardError => e
        Ground::Swallow.log(e, context: "cognition.fix_outcome", event_bus: @bus)
        nil
      end

      def tick_due?
        return false if @since_tick.zero?

        @since_tick >= TICK_EVERY_OBSERVATIONS || Time.now.to_i - @ticked_at >= TICK_EVERY_S
      end

      # The bus merges symbol keys, so only a symbol lookup can hit. The first
      # draft also read payload["ok"], which nothing could ever set.
      def outcome(payload)
        success = payload[:ok] if payload.is_a?(Hash)
        success.nil? ? {} : { success: }
      end

      def update_metrics!(salience:, error:)
        @state.metrics["prediction_error"] = @state.metrics.fetch("prediction_error", 0.0).to_f * 0.9 + error * 0.1
        @state.metrics["attention"] = salience
        @state.metrics["integration"] = integration
      end

      # How much of the working set is active, and how many distinct kinds of
      # thing are in it. Both halves matter: twelve copies of one event is a
      # busy workspace and an undifferentiated one.
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

      # This is checkpoint continuity, not a consciousness or identity score.
      # It is true only when a valid prior state loaded or the current state saved.
      def update_continuity!
        continuity = @state.checkpoint_valid ? 1.0 : 0.0
        @state.metrics["continuity"] = continuity
        @state.metrics["checkpoint_continuity"] = continuity
        @state.identity["continuity"] = continuity
      end

      def persist!
        return unless @dirty || @state.ticks.to_i.positive?

        FileUtils.mkdir_p(File.dirname(@path))
        write_atomic(@path, @state.data.to_yaml, mode: 0o600)
        @state.mark_checkpoint_valid!
        unless @state.metrics.fetch("checkpoint_continuity", 0.0).to_f == 1.0
          @state.metrics["continuity"] = 1.0
          @state.metrics["checkpoint_continuity"] = 1.0
          @state.identity["continuity"] = 1.0
          write_atomic(@path, @state.data.to_yaml, mode: 0o600)
        end
        @dirty = false
      end
    end
  end
end
