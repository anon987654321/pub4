# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"

module Master
  module Trace
    module Log
      # Append-only tool invocation log; subscribes to tool:before on EventBus.
      class Audit
        LOG_PATH = ".master/audit.ndjson".freeze
        MAX_VAL = 120
        MAX_BYTES = 5 * 1024 * 1024

        def initialize(root:, event_bus:)
          @path = File.join(root, LOG_PATH)
          @mutex = Mutex.new
          FileUtils.mkdir_p(File.dirname(@path))
          event_bus.subscribe("tool:before") { |event_data| append(event_data) }
        end

        private

        def append(event_data)
          record = { ts: Time.now.utc.iso8601, tool: event_data[:tool] }
                    .merge(event_data.except(:tool).transform_values { |v| v.to_s[0, MAX_VAL] })
          Master::Trace::Telemetry.span("audit.append", tool: event_data[:tool].to_s) do
            @mutex.synchronize do
              rotate! if File.exist?(@path) && File.size(@path) > MAX_BYTES
              File.open(@path, "a") { |f| f.puts(JSON.generate(record)) }
            end
          end
        end

        def rotate!
          File.rename(@path, "#{@path}.1")
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "audit_log.rotate", path: @path)
        end
      end

      class Event
        DEFAULT_STREAM = "activity"
        STREAM_PATTERN = /\A[a-z0-9_\-]+\z/
        # Append-only with no cap previously ran unbounded -- activity.jsonl
        # reached 1.2GB and filled the disk, crashing an in-progress /fix
        # round with no warning beyond a swallowed ENOSPC on every event.
        # Rotate (rename to .1, start fresh) rather than truncate-in-place --
        # avoids ever reading a multi-GB file into memory to keep a tail.
        MAX_BYTES = 25 * 1024 * 1024

        def initialize(root: Master::ROOT, stream: DEFAULT_STREAM)
          @root = root
          @stream = normalize_stream(stream)
          @path = File.join(@root, "runtime", "events", "#{@stream}.jsonl")
        end

        def append(event, payload = {})
          record = build_record(event, payload)
          FileUtils.mkdir_p(File.dirname(@path))
          rotate_if_oversized!
          File.open(@path, "a") { |io| io.write(JSON.generate(record), "\n") }
          record
        rescue SystemCallError, JSON::GeneratorError => e
          # Stderr is last resort — cannot route through bus without risking recursion.
          ::Kernel.warn("event_log: append to #{@path} failed — #{e.class}: #{e.message}")
          nil
        end

        def recent(limit, pattern: nil)
          return [] unless File.exist?(@path)

          matcher = pattern && !pattern.empty? ? Regexp.new(pattern) : nil
          File.foreach(@path).to_a.last(limit).filter_map do |line|
            record = parse_line(line)
            next unless record
            next if matcher && !record["event"].to_s.match?(matcher)

            record
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Log::Event.recent")
          []
        end

        def tail(limit, pattern: nil)
          recent(limit, pattern:)
        rescue RegexpError => e
          Master::Ground::Swallow.log(e, context: "Log::Event.tail")
          []
        end

        private

        def build_record(event, payload)
          now = Time.now.utc
          {
            id: SecureRandom.uuid,
            timestamp: now.iso8601(6),
            event: event.to_s,
            payload: payload || {},
          }
        end

        def rotate_if_oversized!
          return unless File.exist?(@path) && File.size(@path) > MAX_BYTES

          File.rename(@path, "#{@path}.1")
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Log::Event.rotate_if_oversized")
        end

        def normalize_stream(stream)
          candidate = stream.to_s
          candidate.match?(STREAM_PATTERN) ? candidate : DEFAULT_STREAM
        end

        def parse_line(line)
          JSON.parse(line)
        rescue JSON::ParserError => e
          Master::Ground::Swallow.log(e, context: "Log::Event.parse_line")
          nil
        end
      end

      class Evidence
        OPERATIONAL = /\A(?:ops:|pipeline:rollback|fix_loop:commit|resync:|deploy:)/

        def initialize(root: Master::ROOT)
          @log = Event.new(root:, stream: "evidence")
        end

        def operational?(event) = event.to_s.match?(OPERATIONAL)

        def append(event, payload = {}) = @log.append(event, payload)

        def recent(limit, pattern: nil) = @log.recent(limit, pattern:)
      end
    end
  end
end
