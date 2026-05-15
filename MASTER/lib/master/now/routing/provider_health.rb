# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Master
  module Now
    module Routing
      # ProviderHealth tracks append-only model/provider outcomes and turns them into
      # small routing penalties. It deliberately accepts NDJSON so the runtime can
      # keep cheap, replayable telemetry without a database dependency.
      class ProviderHealth
        DEFAULT_PATH = File.join(Master::ROOT, "runtime", "telemetry", "provider_health.ndjson").freeze
        DEFAULT_FAILURE_PENALTY = 0.25
        DEFAULT_SUCCESS_BONUS = 0.03
        MIN_SCORE = 0.05
        MAX_SCORE = 1.25

        attr_reader :path

        def initialize(path: DEFAULT_PATH, now: -> { Time.now.utc })
          @path = path
          @now = now
        end

        def record(model:, status:, latency_ms: nil, error: nil, at: @now.call)
          event = {
            ts: at.iso8601,
            model: model.to_s,
            status: status.to_s,
            latency_ms: latency_ms,
            error: error&.to_s
          }.compact
          FileUtils.mkdir_p(File.dirname(path))
          File.open(path, "a") { |f| f.puts(JSON.generate(event)) }
          event
        end

        def score(model)
          model_id = model.to_s
          events_for(model_id).reduce(1.0) do |score, event|
            case event["status"].to_s
            when "success"
              [score + DEFAULT_SUCCESS_BONUS, MAX_SCORE].min
            when "failure", "timeout", "rate_limit", "provider_error", "quota_exceeded"
              [score - DEFAULT_FAILURE_PENALTY, MIN_SCORE].max
            else
              score
            end
          end
        end

        def unhealthy?(model)
          score(model) <= MIN_SCORE
        end

        def rank(models)
          Array(models).sort_by { |model| -score(model) }
        end

        private

        def events_for(model_id)
          return [] unless File.file?(path)

          File.readlines(path, chomp: true).filter_map do |line|
            next if line.strip.empty?

            JSON.parse(line)
          rescue JSON::ParserError
            nil
          end.select { |event| event["model"].to_s == model_id }
        end
      end
    end
  end
end
