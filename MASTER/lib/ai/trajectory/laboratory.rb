# frozen_string_literal: true

require "json"

module Master
  module AI
    module Trajectory
      module Laboratory
        module_function

        def summarize(input:)
          rows = read(input)
          grouped = rows.group_by { |row| row["model"].to_s.empty? ? "unknown" : row["model"].to_s }
          grouped.transform_values { |records| summarize_model(records) }
        end

        def render(input:)
          return "model0: no trajectory file #{input}" unless File.file?(input)

          rows = summarize(input:)
          return "model0: no valid trajectories in #{input}" if rows.empty?

          width = rows.keys.map(&:length).max.to_i
          rows.sort_by { |_model, stat| [-stat[:verified_rate], -stat[:benchmark_ratio], stat[:model]] }.map do |model, stat|
            format(
              "model0: %-#{width}s calls=%d verified=%d verified_rate=%d%% benchmark=%d%% latency=%s outcome=%s",
              model,
              stat[:calls],
              stat[:verified],
              (stat[:verified_rate] * 100).round,
              (stat[:benchmark_ratio] * 100).round,
              stat[:latency_ms] ? "#{stat[:latency_ms].round}ms" : "unmeasured",
              stat[:outcomes].map { |key, value| "#{key}=#{value}" }.join(","),
            )
          end.join("\n")
        end

        def read(path)
          File.foreach(path).filter_map do |line|
            next if line.strip.empty?
            JSON.parse(line)
          rescue JSON::ParserError
            nil
          end
        end

        def summarize_model(records)
          scores = records.map { |record| Benchmark.score(record) }
          latencies = records.filter_map { |record| value_ms(record["latency_ms"] || record.dig("metrics", "latency_ms")) }
          outcomes = records.group_by { |record| record["outcome"].to_s.empty? ? "unknown" : record["outcome"].to_s }
          verified = records.count { |record| record["verified"] == true }
          {
            model: records.first["model"].to_s,
            calls: records.size,
            verified: verified,
            verified_rate: verified.fdiv(records.size),
            benchmark_ratio: scores.sum { |score| score["ratio"].to_f }.fdiv(scores.size),
            latency_ms: latencies.empty? ? nil : latencies.sum.fdiv(latencies.size),
            outcomes: outcomes.transform_values(&:size).sort.to_h,
          }
        end

        def value_ms(value)
          number = Float(value)
          number if number.finite? && number >= 0
        rescue ArgumentError, TypeError
          nil
        end
      end
    end
  end
end
