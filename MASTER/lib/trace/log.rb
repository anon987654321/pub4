# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"

module Master
  module Trace
    module Log
      # The conversation that wrote a line. Several sessions share one checkout
      # and one log, so a line without it cannot be attributed. A web
      # conversation id is the cookie that selects a transcript, so the line
      # carries a digest of it rather than the bearer; a CLI process has no id
      # and is named by its pid, as Trace::Hooks already names it. Twelve hex
      # characters tell sessions apart and stay short of the 32 that Redactor
      # blanks as a key.
      SESSION_DIGEST_CHARS = 12

      def self.session
        conversation = Fiber[:master_conversation]
        return "local-#{Process.pid}" unless conversation

        Digest::SHA256.hexdigest(conversation.to_s)[0, SESSION_DIGEST_CHARS]
      end

      # Renames a log past max_bytes to .1 and starts it fresh. Renaming, not
      # truncating, means no multi-gigabyte read to keep a tail.
      def self.rotate(path, max_bytes)
        return unless File.exist?(path) && File.size(path) > max_bytes

        File.rename(path, "#{path}.1")
      rescue SystemCallError => e
        Master::Ground::Swallow.log(e, context: "Trace::Log.rotate", path:)
      end

      # A failing log says so once per path and error. On a full disk every
      # event fails the same way, and a line per event lands mid-prompt.
      def self.warn_once(key, message)
        @warned ||= {}
        return if @warned[key]

        @warned[key] = true
        ::Kernel.warn(message)
      end

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

        # The bus stamps its own `ts` (milliseconds since boot) and the raw
        # conversation id; neither belongs in a log read across processes, so
        # the wall clock and the session digest take their places.
        def append(event_data)
          fields = event_data.except(:tool, :ts, :conversation).transform_values { |v| v.to_s[0, MAX_VAL] }
          record = { ts: Time.now.utc.iso8601, session: Log.session, tool: event_data[:tool] }.merge(fields)
          Master::Trace::Telemetry.span("audit.append", tool: event_data[:tool].to_s) do
            @mutex.synchronize do
              Log.rotate(@path, MAX_BYTES)
              File.open(@path, "a") { |f| f.puts(JSON.generate(record)) }
            end
          end
        end
      end

      class Event
        DEFAULT_STREAM = "activity"
        STREAM_PATTERN = /\A[a-z0-9_\-]+\z/
        # Uncapped, activity.jsonl once reached 1.2GB and filled the disk.
        MAX_BYTES = 25 * 1024 * 1024

        def initialize(root: Master::ROOT, stream: DEFAULT_STREAM)
          @root = root
          @stream = normalize_stream(stream)
          @path = File.join(@root, "runtime", "events", "#{@stream}.jsonl")
        end

        def append(event, payload = {})
          record = build_record(event, payload)
          FileUtils.mkdir_p(File.dirname(@path))
          Log.rotate(@path, MAX_BYTES)
          File.open(@path, "a") { |io| io.write(JSON.generate(record), "\n") }
          record
        rescue SystemCallError, JSON::GeneratorError => e
          # Stderr is last resort — cannot route through bus without risking recursion.
          Log.warn_once([@path, e.class], "event_log: #{@path}: #{e.message}")
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
            session: Log.session,
            event: event.to_s,
            payload: payload || {},
          }
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
