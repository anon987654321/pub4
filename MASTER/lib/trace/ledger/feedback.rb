# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../../ground/swallow"

module Master
  module Trace
    module Ledger
      # Feedback mirrors high-signal execution feedback into the SQLite
      # knowledge store so RSI can inspect tool results, corrections, and provider failures.
      class Feedback
        def initialize(event_bus:, learnings:, rollback: nil)
          @bus = event_bus
          @learnings = learnings
          @rollback = rollback
        end

        def attach
          @bus&.subscribe("tool:after") { |payload| record_tool(payload) }
          @bus&.subscribe("llm:call_complete") { |payload| record_llm(payload) }
          @bus&.subscribe("llm:provider_outcome") { |payload| record_provider(payload) }
          @bus&.subscribe("user_correction") { |payload| record_user_correction(payload) }
          @bus&.subscribe("fix_loop:soul_proposal") { |payload| record_improvement(payload) }
          @bus&.subscribe("fix_loop:oscillation") { |_payload| trigger_rollback("fix loop oscillation") }
          @bus&.subscribe("fix_loop:cycle_detected") { |_payload| trigger_rollback("fix loop cycle detected") }
          self
        end

        private

        def record_tool(payload)
          dim = payload[:tool] || payload["tool"] || "unknown"
          value = payload[:exit_code] || payload["exit_code"]
          event_type = value.to_i.zero? ? "tool_success" : "tool_failure"
          record(event_type:, dimension: dim, value:, metadata: payload)
        end

        def record_llm(payload)
          model = payload[:model] || payload["model"] || "unknown"
          record(event_type: "tool_success", dimension: "llm:#{model}", value: payload[:tokens_out] || payload["tokens_out"], metadata: payload)
        end

        def record_provider(payload)
          status = (payload[:status] || payload["status"]).to_s
          model = payload[:model] || payload["model"] || "unknown"
          event_type = status == "success" ? "tool_success" : "provider_error"
          record(event_type:, dimension: model, value: status, metadata: payload)
        end

        def record_user_correction(payload)
          action = payload[:action] || payload["action"] || "unknown"
          record(event_type: "user_correction", dimension: action, metadata: payload)
        end

        def record(event_type:, dimension:, value: nil, metadata: nil)
          return unless @learnings&.respond_to?(:record_event)

          @learnings.record_event(
            event_type:,
            dimension:,
            value:,
            metadata: metadata && JSON.generate(metadata),
          )
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Ledger::Feedback.record", event_bus: @bus)
        end

        def record_improvement(payload)
          root = payload[:root] || payload["root"] || Master::ROOT
          rule_id = payload[:rule] || payload["rule"] || "unknown"
          files = Array(payload[:sample] || payload["sample"]).map { |row| row[:file] || row["file"] }.compact.uniq
          line = "#{Time.now.utc.strftime("%Y-%m-%d %H:%M")} #{rule_id}: recurring in #{files.join(", ")}\n"
          path = File.join(root, "runtime", "rsi_improvements.md")
          FileUtils.mkdir_p(File.dirname(path))
          File.open(path, "a") { |file| file.write(line) }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Ledger::Feedback.record_improvement", event_bus: @bus)
        end

        def trigger_rollback(message)
          return unless @rollback

          error = Struct.new(:category, :message) do
            def err?
              true
            end
          end.new(:policy, message)
          @rollback.call(error)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Ledger::Feedback.trigger_rollback", event_bus: @bus)
        end
      end
    end
  end
end
