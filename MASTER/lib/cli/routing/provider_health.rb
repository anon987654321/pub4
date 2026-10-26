# frozen_string_literal: true

require "fileutils"
require_relative "../../execution/contract"
require "json"
require "time"
require_relative "../../trace/log"

module Master
  module CLI
    module Routing
      class ProviderHealth
        DEFAULT_PATH = File.join(Master::ROOT, "runtime", "telemetry", "provider_health.ndjson").freeze
        FAILURE_PENALTY = 0.25
        SUCCESS_BONUS = 0.03
        MIN_SCORE = 0.05
        MAX_SCORE = 1.25
        WINDOW_S = 900
        MAX_BYTES = Master::Trace::Log::Event::MAX_BYTES
        FAILURES = %w[failure timeout rate_limit provider_error quota_exceeded canary_validation_failure
                      canary_failure].freeze

        attr_reader :path

        def initialize(path: ENV.fetch("MASTER_PROVIDER_HEALTH_PATH", DEFAULT_PATH), now: -> { Time.now.utc })
          @path = path
          @now = now
        end

        # Compatibility name for the shared, bounded telemetry writer.
        def self.append_json_line(path, value, max_bytes: MAX_BYTES)
          Master::Trace::Log.append_jsonl(
            path, value, max_bytes:, mode: 0o600, directory_mode: 0o700
          )
        end
        def record(model:, status:, latency_ms: nil, error: nil, at: @now.call)
          event = {
            ts: at.iso8601,
            model: model.to_s,
            status: status.to_s,
            latency_ms:,
            **Master::Execution::Contract.diagnostic_fields(error)
          }.compact
          self.class.append_json_line(path, event)
          event
        end

        # Only the last WINDOW_S of outcomes count. The score used to fold every
        # event the log still held, so four net failures pinned a lane at
        # MIN_SCORE, unhealthy? dropped it from every route, and with no calls it
        # could never earn the +0.03s back. An idle lane now returns to neutral.
        def score(model)
          cutoff = @now.call.to_f - WINDOW_S
          recent = events_for(model.to_s).select { |event| event_time(event).to_f >= cutoff }
          recent.reduce(1.0) { |score, event| scored(score, event["status"].to_s) }
        end

        def unhealthy?(model) = score(model) <= MIN_SCORE

        def observed?(model)
          !events_for(model.to_s).empty?
        end

        def age_seconds(model, now: @now.call)
          event = latest_event(model)
          return unless event

          [now.to_f - event_time(event).to_f, 0.0].max
        rescue StandardError
          nil
        end

        def freshness(model, max_age_s:)
          age = age_seconds(model, now: @now.call)
          return :unknown unless age

          age <= max_age_s.to_f ? :fresh : :stale
        end

        def fresh?(model, max_age_s:)
          freshness(model, max_age_s:) == :fresh
        end

        def stale?(model, max_age_s:)
          freshness(model, max_age_s:) == :stale
        end

        # The last thing the model did was fail, and that happened within
        # max_age_s. Older evidence of either kind says nothing about now.
        def recently_failed?(model, max_age_s:)
          FAILURES.include?(latest_event(model)&.fetch("status", nil).to_s) && fresh?(model, max_age_s:)
        end

        def latest_event(model)
          events_for(model.to_s).max_by { |event| event_time(event).to_f }
        end

        def rank(models)
          Array(models).sort_by { |model| -score(model) }
        end

        private

        def scored(score, status)
          return [score + SUCCESS_BONUS, MAX_SCORE].min if status == "success"
          return [score - FAILURE_PENALTY, MIN_SCORE].max if FAILURES.include?(status)

          score
        end

        # ModelRouter#preferred and #fallback_chain both call score per
        # candidate, and a single turn's routing touches a dozen or more
        # candidates — each used to re-read and re-parse the whole ndjson
        # log from scratch. Cached here per file mtime, so a turn pays for
        # one read no matter how many models it scores.
        def events_for(model_id)
          all_events.select { |event| event["model"].to_s == model_id }
        end

        def event_time(event)
          Time.iso8601(event.fetch("ts"))
        rescue ArgumentError, KeyError, TypeError
          Time.at(0).utc
        end

        def telemetry_paths
          ["#{path}.1", path]
        end

        def all_events
          stamp = telemetry_paths.map do |candidate|
            next unless File.file?(candidate) && !File.symlink?(candidate)

            stat = File.stat(candidate)
            [candidate, stat.ino, stat.size, stat.mtime.to_r]
          end
          return @events if @events && @events_stamp == stamp

          @events_stamp = stamp
          @events = telemetry_paths.flat_map { |candidate| load_events(candidate) }
        rescue SystemCallError => e
          Master::Ground::Swallow.log(e, context: "ProviderHealth.all_events")
          @events || []
        end

        def load_events(candidate)
          return [] unless File.file?(candidate) && !File.symlink?(candidate)

          File.readlines(candidate, chomp: true).filter_map do |line|
            next if line.strip.empty?
            JSON.parse(line)
          rescue JSON::ParserError => e
            Master::Ground::Swallow.log(e, context: "ProviderHealth.events_for", path: candidate)
            nil
          end
        end
      end
    end
  end
end
