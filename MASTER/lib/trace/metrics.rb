# frozen_string_literal: true

require "json"

module Master
  module Trace
    # What the runtime measures about its own model calls: how many, how many
    # failed, how many escalated, per model.
    #
    # It measured three more things until nothing turned out to call them.
    # record_latency, record_diff and record_undo were public, had no caller
    # anywhere in the tree, and were reachable only through the bus — which
    # subscribes one event, llm:response. So the counters they maintained never
    # moved, and `summary` reported avg_latency_ms 0, avg_diff_lines 0 and
    # rollback_rate 0.0 on every run of a system doing all three things. A
    # metric that always reads zero is worse than an absent one: it answers the
    # question, and the answer is that everything is fine.
    #
    # Deleted rather than wired, because wiring them is a decision about what
    # the runtime should watch, not a repair of what it claimed to. The three
    # thresholds and the sampling window went with them; they existed only to
    # judge those counters.
    class Metrics
      def initialize(root:, event_bus: nil)
        @path = File.join(root, ".master", "metrics.jsonl")
        @bus = event_bus
        @mutex = Mutex.new
        @model_stats = Hash.new { |h, k| h[k] = { calls: 0, failures: 0, escalations: 0 } }
        subscribe_to_bus(event_bus) if event_bus
      end

      def record_llm_response(model:, success:, tokens_approx: 0, escalated: false)
        @mutex.synchronize do
          stats = @model_stats[model.to_s]
          stats[:calls] += 1
          stats[:failures] += 1 unless success
          stats[:escalations] += 1 if escalated
        end
        append(llm_response: { model: model.to_s, success:, tokens_approx:, escalated: })
      end

      def summary
        calls = @model_stats.values.sum { |s| s[:calls] }
        {
          llm_calls: calls,
          llm_failures: @model_stats.values.sum { |s| s[:failures] },
          llm_escalations: @model_stats.values.sum { |s| s[:escalations] },
          models: @model_stats.size,
        }
      end

      def model_quality
        @model_stats.transform_values do |s|
          fail_rate = s[:calls] > 0 ? (s[:failures].to_f / s[:calls]).round(3) : 0.0
          s.merge(fail_rate:)
        end.sort_by { |_, v| -v[:fail_rate] }.to_h
      end

      private

      def subscribe_to_bus(bus)
        bus.subscribe("llm:response") do |ev|
          record_llm_response(
            model: ev[:model].to_s,
            success: ev[:success] != false,
            tokens_approx: ev[:tokens_approx].to_i,
            escalated: ev[:escalated] == true,
          )
        rescue StandardError => e
          @bus&.publish("metrics:record_error", error: e.message)
        end
      end

      def append(entry)
        entry[:ts] = Time.now.to_i
        Master::Trace::Telemetry.span("metrics.append", keys: entry.keys.join(",")) do
          File.open(@path, "a") { |f| f.puts(JSON.generate(entry)) }
        end
      rescue StandardError => e
        @bus&.publish("metrics:append_error", error: e.message)
      end
    end
  end
end
