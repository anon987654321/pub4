# frozen_string_literal: true

require "fileutils"
require "json"
# MasterPaths::ROOT rather than Master::ROOT, which is defined in lib/master.rb
# and therefore only exists after a full runtime boot. lib/io/replicate_client.rb
# is deliberately standalone-loadable -- STUDIO/repligen and STUDIO/lora both
# require it and nothing else -- and it calls Swallow.log in three rescue paths,
# so on the first Replicate training for a new subject (model_exists? raises,
# the rescue fires) the swallow raised NameError instead of logging. Same value,
# no boot order.
require_relative "../boot/paths"

module Master
  module Ground
    # Error swallowing with structured telemetry. Never truly silent —
    # every swallowed error publishes to the event bus and writes
    # to a structured log for post-mortem analysis.
    module Swallow
      LOG_PATH = File.join(MasterPaths::ROOT, ".master", "swallowed_errors.jsonl").freeze

      # Every swallow this session looked identical from outside -- the
      # extract_code NameError (defeated the primary LLM fix strategy every
      # single call) and a genuinely cosmetic glob-found-nothing were both
      # another line in the same undifferentiated stream. severity:
      # is opt-in and defaults to :cosmetic (never claims something is
      # load-bearing without a caller actually saying so); it exists so a
      # caller who *has* done that judgment call once can tag it, and the
      # next diagnostic hunt can filter for :load_bearing instead of reading
      # every line.
      SEVERITIES = %i[load_bearing cosmetic].freeze

      class << self
        def event_bus=(bus)
          @event_bus = bus
        end

        def log(error, context:, event_bus: nil, severity: :cosmetic, **meta)
          payload = build_payload(error, context, severity, meta)
          bus = event_bus || @event_bus
          bus&.publish("error:swallowed", payload)
          write_structured_log(payload)
        rescue StandardError => e
          # Last resort: stderr if even the logger fails
          warn "[SWALLOW-CRITICAL] #{e.class}: #{e.message} (while logging #{error.class})"
        end

        # Query swallowed errors from structured log. Returns array of hashes.
        def recent(limit: 100, context: nil, since: nil, severity: nil)
          return [] unless File.exist?(LOG_PATH)

          lines = File.readlines(LOG_PATH, chomp: true).last(limit)
          records = lines.filter_map { |line| JSON.parse(line) rescue nil }
          records = records.select { |r| r["context"] == context.to_s } if context
          records = records.select { |r| Time.parse(r["at"]) >= since } if since
          records = records.select { |r| r["severity"] == severity.to_s } if severity
          records
        end

        # Rotate log if it exceeds size threshold (default 10MB).
        def rotate!(max_bytes: 10_485_760)
          return unless File.exist?(LOG_PATH) && File.size(LOG_PATH) > max_bytes

          backup = "#{LOG_PATH}.#{Time.now.utc.strftime("%Y%m%d%H%M%S")}"
          File.rename(LOG_PATH, backup)
          # Keep only last 5 backups
          Dir.glob("#{LOG_PATH}.*").sort.reverse.drop(5).each { |f| File.delete(f) } # scan: intentional — log rotation, drop(5) keeps the five newest
        end

        private

        def build_payload(error, context, severity, meta)
          {
            at: Time.now.utc.iso8601,
            context: context.to_s,
            severity: (SEVERITIES.include?(severity&.to_sym) ? severity : :cosmetic).to_s,
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

      def self.safe_call(context:, event_bus: nil, severity: :cosmetic, **meta)
        yield
      rescue StandardError => e
        log(e, context:, event_bus:, severity:, **meta)
        nil
      end
    end
  end
end
