# frozen_string_literal: true

require "json"

module Master
  class Metrics
    METRICS_PREFIX = "metrics0".freeze
    DECISION_LATENCY_MS_THRESHOLD = 5_000
    MAX_DIFF_SIZE_LINES = 200
    ROLLBACK_RATE_THRESHOLD = 0.15

    def initialize(root:, event_bus: nil)
      @path   = File.join(root, ".master", "metrics.jsonl")
      @bus    = event_bus
      @writes = 0
      @undos  = 0
      @latencies   = []
      @diff_sizes  = []
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

    def summary
      {
        avg_latency_ms:  average(@latencies).round,
        avg_diff_lines:  average(@diff_sizes).round,
        rollback_rate:   (@writes > 0 ? @undos.to_f / @writes : 0.0).round(3),
        writes:          @writes,
        undos:           @undos
      }
    end

    private

    def check_threshold(metric, value)
      threshold =
        case metric
        when :decision_latency_ms then DECISION_LATENCY_MS_THRESHOLD
        when :diff_size_lines then MAX_DIFF_SIZE_LINES
        when :rollback_rate then ROLLBACK_RATE_THRESHOLD
        else
          return
        end
      return unless value > threshold
      msg = "#{METRICS_PREFIX}: #{metric} #{value} exceeds #{threshold} — governance overhead detected"
      @bus&.publish("metrics:threshold_exceeded", metric:, value:)
      warn msg
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