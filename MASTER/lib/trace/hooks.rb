# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Master
  module Trace
    class Hooks
      DEFAULT_VIOLATIONS_PATH = ".constitutional_violations.jsonl"
      COST_EVENT = "on_cost_threshold"

      def initialize(root:, event_bus:, config: nil, budget_max: nil)
        @root = root
        @bus = event_bus
        @hooks = Array(config || load_hooks)
        @budget_max = budget_max.to_f
        @cost_total = 0.0
        @cost_threshold_fired = false
      end

      def attach
        subscribe_scan_complete
        subscribe_fix_applied
        subscribe_cost
        subscribe_phase
        subscribe_convergence
        publish_hook("on_session_start", {})
        at_exit { publish_hook("on_session_end", {}) }
        self
      end

      private

      attr_reader :root, :bus, :hooks, :budget_max

      def subscribe_scan_complete
        bus.subscribe("scan:complete") do |payload|
          next unless payload[:count].to_i.positive?

          publish_hook("on_violation_found", payload)
        end
      end

      def subscribe_fix_applied
        bus.subscribe("rule_loop:fix_applied") { |payload| publish_hook("on_fix_applied", payload) }
      end

      def subscribe_cost
        bus.subscribe("llm:cost") do |payload|
          @cost_total += payload[:cost].to_f
          next unless cost_threshold_crossed?

          publish_hook(COST_EVENT, payload.merge(total_cost: @cost_total, max_per_session: budget_max))
        end
      end

      def subscribe_phase
        bus.subscribe("phase:advanced") { |payload| publish_hook("on_phase_transition", payload) }
      end

      def subscribe_convergence
        bus.subscribe("fix_loop:clean") { |payload| publish_hook("on_convergence", payload) }
      end

      def cost_threshold_crossed?
        return false if @cost_threshold_fired || budget_max <= 0

        threshold = hook_for(COST_EVENT).dig("params", "warn_at").to_f
        threshold = 0.5 if threshold <= 0
        crossed = @cost_total >= (budget_max * threshold)
        @cost_threshold_fired = true if crossed
        crossed
      end

      def publish_hook(name, payload)
        matching_hooks(name).each { |hook| run_hook(hook, payload) }
        bus.publish("hook:#{name}", payload)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "hooks.publish", event_bus: bus, hook: name)
      end

      def run_hook(hook, payload)
        case hook["action"].to_s
        when "append_constitutional_violation" then append_violation(payload, hook["params"] || {})
        when "warn_cost_threshold" then warn_cost(payload)
        when "publish" then bus.publish(hook.dig("params", "event").to_s, payload)
        end
      end

      def append_violation(payload, params)
        path = File.join(root, params.fetch("path", DEFAULT_VIOLATIONS_PATH))
        record = {
          timestamp: Time.now.utc.iso8601,
          session: Process.pid,
          file: payload[:path].to_s,
          count: payload[:count].to_i,
          top_rules: payload[:top_rules] || {}
        }
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "#{JSON.generate(record)}\n", mode: "a")
      end

      def warn_cost(payload)
        bus.publish(
          "hook:warning",
          type: COST_EVENT,
          message: "session cost crossed #{format('$%.2f', payload[:total_cost].to_f)}",
          total_cost: payload[:total_cost],
          max_per_session: payload[:max_per_session]
        )
      end

      def matching_hooks(name)
        hooks.select { |hook| hook["event"].to_s == name }
      end

      def hook_for(name)
        matching_hooks(name).first || {}
      end

      def load_hooks
        soul = Master.load_yaml(Master.data_path("soul.yml"))
        soul["hooks"] || []
      rescue StandardError => e
        []
      end
    end
  end
end
