# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module Master
  module CLI
    module Routing
    # ProviderQuarantine — extends ProviderHealth with automatic quarantine
    # and recovery.
    #
    # Quarantine removes a provider from routing until its quarantine
    # expires or an operator clears it. We append all decisions to NDJSON so
    # the quarantine state is replayable from the event log.
      class ProviderQuarantine
        QUARANTINE_PATH = File.join(Master::ROOT, "runtime", "telemetry", "quarantine.ndjson").freeze
        # 5 minutes initial quarantine
        DEFAULT_DURATION = 300
        # 1 hour ceiling
        MAX_DURATION = 3600
        # score at or below this triggers quarantine
        QUARANTINE_THRESHOLD = 0.10

        QuarantineEntry = Data.define(:model, :reason, :quarantined_at, :expires_at, :duration)

        def initialize(health: ProviderHealth.new, path: QUARANTINE_PATH, now: -> { Time.now.utc }, event_bus: nil)
          @health = health
          @path = path
          @now = now
          @bus = event_bus
        end

        def quarantined?(model)
          entry = active_quarantine(model.to_s)
          return false unless entry
          Time.parse(entry["expires_at"]) > @now.call
        rescue ArgumentError => e
          Master::Ground::Swallow.log(e, context: "ProviderQuarantine.quarantined?")
          false
        end

        # Called after a provider outcome — auto-quarantines if score crosses threshold
        def record_and_assess(model:, status:, latency_ms: nil, error: nil)
          @health.record(model:, status:, latency_ms:, error:)
          score = @health.score(model)
          quarantine(model:, reason: "score #{format('%.2f', score)} at or below threshold") if score <= QUARANTINE_THRESHOLD
          score
        end

        def quarantine(model:, reason:, duration: nil)
          return if quarantined?(model)
          now = @now.call
          exp_duration = duration || exponential_duration(model)
          expires_at = now + exp_duration
          entry = { model: model.to_s, reason:, quarantined_at: now.iso8601,
                         expires_at: expires_at.iso8601, duration: exp_duration }
          append(entry)
          @bus&.publish("provider:quarantined", model:, reason:, expires_at: expires_at.iso8601, duration: exp_duration)
          entry
        end

        def clear(model)
          entry = { model: model.to_s, cleared_at: @now.call.iso8601, action: "clear" }
          append(entry)
          @bus&.publish("provider:quarantine_cleared", model:)
        end

        def rank(models)
          available = models.reject { |m| quarantined?(m) }
          available.empty? ? @health.rank(models) : @health.rank(available)
        end

        def status
          models_seen = all_entries.map { |e| e["model"] }.uniq
          models_seen.map do |model|
            { model:, quarantined: quarantined?(model), score: @health.score(model) }
          end
        end

        private

        def exponential_duration(model)
          past = all_entries.count { |e| e["model"] == model.to_s && e["expires_at"] && !e["action"] }
          [DEFAULT_DURATION * (2**past), MAX_DURATION].min
        end

        def active_quarantine(model_id)
          latest = all_entries
            .select { |entry| entry["model"] == model_id }
            .max_by { |entry| entry_time(entry) }

          # Clear records are events in the same append-only log. Excluding them
          # before choosing the latest event makes an operator clear ineffective:
          # the earlier quarantine row wins until expiry. A later quarantine row
          # naturally becomes active again.
          return unless latest && latest["action"] != "clear" && latest["expires_at"]

          latest
        end

        def entry_time(entry)
          value = entry["cleared_at"] || entry["quarantined_at"]
          Time.iso8601(value.to_s)
        rescue ArgumentError, TypeError
          Time.at(0).utc
        end

        def all_entries
          return [] unless File.file?(@path)
          File.readlines(@path, chomp: true).filter_map do |line|
            next if line.strip.empty?
            JSON.parse(line)
          rescue JSON::ParserError => e
            Master::Ground::Swallow.log(e, context: "ProviderQuarantine.all_entries")
            nil
          end
        end

        def append(entry)
          FileUtils.mkdir_p(File.dirname(@path))
          File.open(@path, "a") { |f| f.puts(JSON.generate(entry)) }
        end
      end
    end
  end
end
