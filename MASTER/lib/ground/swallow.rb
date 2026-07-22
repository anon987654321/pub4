# frozen_string_literal: true

require "fileutils"
require "json"

module Master
  module Ground
    # Error swallowing with structured telemetry. Never truly silent —
    # every swallowed error publishes to the event bus and writes
    # to a structured log for post-mortem analysis.
    module Swallow
      LOG_PATH = File.join(Master::ROOT, ".master", "swallowed_errors.jsonl").freeze

      class << self
        def event_bus=(bus)
          @event_bus = bus
        end

        def log(error, context:, event_bus: nil, **meta)
          payload = build_payload(error, context, meta)
          bus = event_bus || @event_bus
          bus&.publish("error:swallowed", payload)
          write_structured_log(payload)
        rescue StandardError => e
          # Last resort: stderr if even the logger fails
          warn "[SWALLOW-CRITICAL] #{e.class}: #{e.message} (while logging #{error.class})"
        end

        # Query swallowed errors from structured log. Returns array of hashes.
        def recent(limit: 100, context: nil, since: nil)
          return [] unless File.exist?(LOG_PATH)

          lines = File.readlines(LOG_PATH, chomp: true).last(limit)
          records = lines.filter_map { |line| JSON.parse(line) rescue nil }
          records = records.select { |r| r["context"] == context.to_s } if context
          records = records.select { |r| Time.parse(r["at"]) >= since } if since
          records
        end

        # Rotate log if it exceeds size threshold (default 10MB).
        def rotate!(max_bytes: 10_485_760)
          return unless File.exist?(LOG_PATH) && File.size(LOG_PATH) > max_bytes

          backup = "#{LOG_PATH}.#{Time.now.utc.strftime("%Y%m%d%H%M%S")}"
          File.rename(LOG_PATH, backup)
          # Keep only last 5 backups
          Dir.glob("#{LOG_PATH}.*").sort.reverse.drop(5).each { |f| File.delete(f) }
        end

        private

        def build_payload(error, context, meta)
          {
            at: Time.now.utc.iso8601,
            context: context.to_s,
            error_class: error.class.name,
            error_message: error.message,
            backtrace: error.backtrace&.first(5),
            meta:,
          }
        end

        def write_structured_log(payload)
          FileUtils.mkdir_p(File.dirname(LOG_PATH))
          File.open(LOG_PATH, "a", 0o600) do |f|
            f.puts(JSON.generate(payload))
          end
          rotate!
        end
      end

      def self.safe_call(context:, event_bus: nil, **meta)
        yield
      rescue StandardError => e
        log(e, context:, event_bus:, **meta)
        nil
      end
    end
  end
end
