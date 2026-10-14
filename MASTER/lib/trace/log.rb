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

      # A full log is renamed, then compacted in place to its newest bounded tail.
      # Renaming alone does not free disk blocks when an old multi-GB log exists.
      def self.rotate(path, max_bytes)
        return unless File.exist?(path) && File.size(path) > max_bytes

        rotated = "#{path}.1"
        File.rename(path, rotated)
        compact_rotated(rotated, max_bytes)
      rescue SystemCallError => e
        Master::Ground::Swallow.log(e, context: "Trace::Log.rotate", path:)
      end

      # Release oversized rotated logs while preserving the newest max_bytes.
      # The tail is read before truncating; the old allocation is freed before the
      # bounded bytes are written back, so recovery still works on a full disk.
      def self.compact_rotated(path, max_bytes)
        return unless File.file?(path)

        size = File.size(path)
        return size if size <= max_bytes

        tail = File.open(path, "rb") do |file|
          file.seek(-max_bytes, IO::SEEK_END)
          file.read(max_bytes)
        end
        File.open(path, "r+b") do |file|
          file.truncate(0)
          file.write(tail)
          file.flush
          file.fsync
        end
        File.size(path)
      rescue SystemCallError => e
        Master::Ground::Swallow.log(e, context: "Trace::Log.compact_rotated", path:)
        nil
      end

      # A failing log says so once per path and error. On a full disk every
      # event fails the same way, and a line per event lands mid-prompt.
      def self.warn_once(key, message)
        @warned ||= {}
        return if @warned[key]

        @warned[key] = true
        if defined?(Master::Trace::Dmesg)
          Master::Trace::Dmesg.once("event0", message.sub(/\A[^:]+:\s*/, ""))
        else
          ::Kernel.warn(message)
        end
      end

      # Last resort after ENOSPC: discard one rotated generation first, or
      # compact the active log to a recent tail. This frees blocks before another
      # write is attempted, instead of silently losing every subsequent event.
      def self.reclaim(path, keep_bytes: 1024 * 1024)
        rotated = "#{path}.1"
        if File.file?(rotated)
          File.delete(rotated)
          return true
        end

        return false unless File.file?(path) && File.size(path) > keep_bytes

        !compact_rotated(path, keep_bytes).nil?
      rescue Errno::ENOENT
        false
      rescue SystemCallError => e
        Master::Ground::Swallow.log(e, context: "Trace::Log.reclaim", path:)
        false
      end

      # Append-only tool invocation log; subscribes to tool:before on EventBus.
      # Under .master/ because it records tool arguments, which stay out of the served event stream.
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
          2.times do |attempt|
            begin
              Log.rotate(@path, MAX_BYTES)
              File.open(@path, "a") { |io| io.write(JSON.generate(record), "\n") }
              return record
            rescue Errno::ENOSPC
              # One bounded recovery attempt only; a persistently full disk must
              # not turn logging into a retry loop of its own.
              raise unless attempt.zero? && Log.reclaim(@path)
            end
          end
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
