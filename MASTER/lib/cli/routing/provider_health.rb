# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Master
  module CLI
    module Routing
      class ProviderHealth
        DEFAULT_PATH = File.join(Master::ROOT, "runtime", "telemetry", "provider_health.ndjson").freeze
        FAILURE_PENALTY = 0.25
        SUCCESS_BONUS = 0.03
        MIN_SCORE = 0.05
        MAX_SCORE = 1.25

        attr_reader :path

        def initialize(path: DEFAULT_PATH, now: -> { Time.now.utc })
          @path = path
          @now = now
        end

        # Health and quarantine share one append primitive so independent
        # runtime instances and processes never interleave NDJSON records.
        def self.append_json_line(path, value)
          directory = File.dirname(path)
          raise ArgumentError, "provider telemetry directory is a symlink" if File.symlink?(directory)

          FileUtils.mkdir_p(directory, mode: 0o700)
          directory_stat = File.lstat(directory)
          raise ArgumentError, "provider telemetry directory is not a real directory" unless
            directory_stat.directory? && !directory_stat.symlink?
          File.chmod(0o700, directory)

          raise ArgumentError, "provider telemetry log is a symlink" if File.symlink?(path)
          if File.exist?(path)
            log_stat = File.lstat(path)
            raise ArgumentError, "provider telemetry log is not a regular file" unless log_stat.file? && !log_stat.symlink?

            File.chmod(0o600, path)
          end

          File.open(path, File::RDWR | File::CREAT, 0o600) do |file|
            file.flock(File::LOCK_EX)
            file.seek(0, IO::SEEK_END)
            file.write(JSON.generate(value) + "\n")
            file.flush
            file.fsync
          ensure
            file.flock(File::LOCK_UN) if file
          end
        end

        def record(model:, status:, latency_ms: nil, error: nil, at: @now.call)
          event = {
            ts: at.iso8601,
            model: model.to_s,
            status: status.to_s,
            latency_ms:,
            error: error&.to_s,
          }.compact
          self.class.append_json_line(path, event)
          event
        end

        def score(model)
          events_for(model.to_s).reduce(1.0) do |score, event|
            case event["status"].to_s
            when "success"
              [score + SUCCESS_BONUS, MAX_SCORE].min
            when "failure", "timeout", "rate_limit", "provider_error", "quota_exceeded", "canary_validation_failure", "canary_failure"
              [score - FAILURE_PENALTY, MIN_SCORE].max
            else
              score
            end
          end
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

        def latest_event(model)
          events_for(model.to_s).max_by { |event| event_time(event).to_f }
        end

        def rank(models)
          Array(models).sort_by { |model| -score(model) }
        end

        private

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

        def all_events
          stat = File.stat(path) if File.file?(path)
          stamp = stat && [stat.ino, stat.size, stat.mtime.to_r]
          return @events if @events && @events_stamp == stamp

          @events_stamp = stamp
          @events = load_events
        end

        def load_events
          return [] unless File.file?(path)
          File.readlines(path, chomp: true).filter_map do |line|
            next if line.strip.empty?
            JSON.parse(line)
          rescue JSON::ParserError => e
            Master::Ground::Swallow.log(e, context: "ProviderHealth.events_for")
            nil
          end
        end
      end
    end
  end
end
