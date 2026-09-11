# frozen_string_literal: true

require "fileutils"

module Master
  module Cognition
    # MASTER's persistent cognitive layer: recurrent perception, salience, a
    # bounded working set, affect, self-modelling, prediction error and
    # reflection, over one YAML file under .master/.
    #
    # The consciousness-adjacent numbers are proxies and are named as such
    # everywhere they are written. COGNITION.md carries the argument.
    #
    # Three things here are load-bearing and were each wrong once.
    #
    # The subscription is `**`, not `*`. EventBus compiles `*` to `[^:]*` and
    # `**` to `.*`, so `*` matches only colon-free event names — it would have
    # seen `error` and missed `tool:after`, `chat:message`, `scan:complete` and
    # `pressure:changed`, which is five of the seven rows in Attention's own
    # weight table. The layer would have been near-inert and looked wired.
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

      def snapshot = @mutex.synchronize { State.deep_dup(@state.data) }

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

      def update_continuity!
        previous = @state.metrics.fetch("continuity", 1.0).to_f
        continuity = @state.last_tick_at.to_i.zero? ? previous : (previous * 0.995 + 0.005).clamp(0.0, 1.0)
        @state.metrics["continuity"] = continuity
        @state.identity["continuity"] = continuity
      end

      def persist!
        return unless @dirty || @state.ticks.to_i.positive?

        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, @state.data.to_yaml, encoding: "UTF-8")
        @dirty = false
      end
    end
  end
end
