# frozen_string_literal: true

require "json"

module Master
  class Metrics
    METRICS_PREFIX = "metrics0".freeze
    DIFF_SIZE_LIMIT_DEFAULT = 200
    MAX_DIFF_SIZE_LIMIT = DIFF_SIZE_LIMIT_DEFAULT
    MAX_DIFF_SIZE_LINES = MAX_DIFF_SIZE_LIMIT
    ROLLBACK_RATE_THRESHOLD = 0.15
    DECISION_LATENCY_MS_THRESHOLD = 5000

    def initialize(root:, event_bus: nil)
      @path        = File.join(root, ".master", "metrics.jsonl")
      @bus         = event_bus
      @writes      = 0
      @undos       = 0
      @latencies   = []
      @diff_sizes  = []
      @model_stats = Hash.new { |h, k| h[k] = { calls: 0, failures: 0, escalations: 0 } }
      subscribe_to_bus(event_bus) if event_bus
    end

    def record_latency(ms)
      @latencies << ms
      check_threshold(:decision_latency_ms, average(@latencies))
      append(decision_latency_ms: ms)
    end

    def record_diff(lines)
      @diff_sizes << lines
      @writes += 1
      check_threshold(:diff_size_lines, average(@diff_sizes))
      append(diff_size_lines: lines)
    end

    def record_undo
      @undos += 1
      rate = @writes > 0 ? @undos.to_f / @writes : 0.0
      check_threshold(:rollback_rate, rate)
      append(rollback_rate: rate.round(3))
    end

    # Called via llm:response EventBus subscription or directly.
    def record_llm_response(model:, success:, tokens_approx: 0, escalated: false)
      s = @model_stats[model.to_s]
      s[:calls]       += 1
      s[:failures]    += 1 unless success
      s[:escalations] += 1 if escalated
      append(llm_response: { model: model.to_s, success:, tokens_approx:, escalated: })
    end

    def summary
      {
        avg_latency_ms: average(@latencies).round,
        avg_diff_lines: average(@diff_sizes).round,
        rollback_rate:  (@writes > 0 ? @undos.to_f / @writes : 0.0).round(3),
        writes:         @writes,
        undos:          @undos
      }
    end

    # Returns per-model quality stats, sorted by failure rate desc.
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
          model:        ev[:model].to_s,
          success:      ev[:success] != false,
          tokens_approx: ev[:tokens_approx].to_i,
          escalated:    ev[:escalated] == true
        )
      rescue StandardError
        nil
      end
    end

    def check_threshold(metric, value)
      threshold =
        case metric
        when :decision_latency_ms then DECISION_LATENCY_MS_THRESHOLD
        when :diff_size_lines     then MAX_DIFF_SIZE_LINES
        when :rollback_rate       then ROLLBACK_RATE_THRESHOLD
        else return
        end
      return unless value > threshold
      @bus&.publish("metrics:threshold_exceeded", metric:, value:)
      warn "#{METRICS_PREFIX}: #{metric} #{value} exceeds #{threshold}"
    end

    def average(arr)
      return 0.0 if arr.empty?
      arr.sum.to_f / arr.size
    end

    def append(entry)
      entry[:ts] = Time.now.to_i
      File.open(@path, "a") { |f| f.puts(JSON.generate(entry)) }
    rescue StandardError
      nil
    end
  end
end
