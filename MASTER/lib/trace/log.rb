# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "event_privacy"

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
      # An appender rotates early to leave room for its next line, but the rotated
      # generation keeps its whole cap (keep_bytes); compacting it to the early
      # threshold would drop every record larger than half the cap.
      def self.rotate(path, max_bytes, keep_bytes: max_bytes)
        return unless File.exist?(path) && File.size(path) > max_bytes

        rotated = "#{path}.1"
        File.rename(path, rotated)
        compact_rotated(rotated, keep_bytes)
      rescue SystemCallError => e
        Master::Ground::Swallow.log(e, context: "Trace::Log.rotate", path:)
      end

      # One bounded, private, process-safe JSONL append path for local telemetry.
      # The sidecar lock covers both rotate and append because locking the data
      # inode is not enough once rotation renames it.
      def self.append_jsonl(path, value, max_bytes: Event::MAX_BYTES, mode: 0o600, directory_mode: nil, sync: true)
        limit = Integer(max_bytes)
        raise ArgumentError, "JSONL byte limit must be positive" unless limit.positive?

        line = JSON.generate(value) + "\n"
        raise ArgumentError, "JSONL record exceeds #{limit}-byte cap" if line.bytesize > limit

        directory = File.dirname(path)
        raise ArgumentError, "JSONL directory is a symlink" if File.symlink?(directory)
        FileUtils.mkdir_p(directory, mode: directory_mode || 0o700)
        directory_stat = File.lstat(directory)
        raise ArgumentError, "JSONL directory is not a real directory" unless
          directory_stat.directory? && !directory_stat.symlink?
        File.chmod(directory_mode, directory) if directory_mode

        lock_path = "#{path}.lock"
        raise ArgumentError, "JSONL lock is a symlink" if File.symlink?(lock_path)
        File.open(lock_path, File::RDWR | File::CREAT, mode) do |lock|
          File.chmod(mode, lock_path)
          lock.flock(File::LOCK_EX)

          raise ArgumentError, "JSONL destination is a symlink" if File.symlink?(path)
          if File.exist?(path)
            path_stat = File.lstat(path)
            raise ArgumentError, "JSONL destination is not a regular file" unless path_stat.file? && !path_stat.symlink?

            File.chmod(mode, path)
          end

          attempts = 0
          line_bytes = line.bytesize
          loop do
            rotate(path, [limit - line_bytes, 0].max, keep_bytes: limit)
            size = File.file?(path) ? File.size(path) : 0
            if size + line_bytes > limit
              unless attempts.zero? && reclaim(path)
                raise IOError, "JSONL rotation failed to honor #{limit}-byte cap"
              end

              attempts += 1
              next
            end

            begin
              File.open(path, File::WRONLY | File::CREAT | File::APPEND, mode) do |io|
                offset = 0
                while offset < line_bytes
                  written = io.write(line.byteslice(offset..))
                  raise IOError, "JSONL append wrote no bytes" unless written&.positive?

                  offset += written
                end
                io.flush
                io.fsync if sync
              end
              break
            rescue Errno::ENOSPC
              raise unless attempts.zero? && reclaim(path)

              attempts += 1
            end
          end
        ensure
          lock.flock(File::LOCK_UN) if lock
        end
      end

      # Release oversized rotated JSONL logs while preserving the newest complete
      # records within max_bytes. The tail is read before truncating; the old
      # allocation is freed before the bounded bytes are written back, so recovery
      # still works on a full disk. A partial first record is discarded.
      def self.compact_rotated(path, max_bytes)
        return unless File.file?(path)

        size = File.size(path)
        return size if size <= max_bytes

        tail = File.open(path, "rb") do |file|
          file.seek(-max_bytes, IO::SEEK_END)
          start = file.pos
          bytes = file.read(max_bytes)
          if start.positive?
            file.seek(start - 1, IO::SEEK_SET)
            unless file.read(1) == "\n"
              first_newline = bytes.index("\n")
              bytes = first_newline ? bytes.byteslice(first_newline + 1..) : +"".b
            end
          end
          bytes || +"".b
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
        @warn_mutex ||= Mutex.new
        emit = @warn_mutex.synchronize do
          @warned ||= {}
          next false if @warned[key]

          @warned[key] = true
          true
        end
        ::Kernel.warn(message) if emit
      rescue StandardError
        nil
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
      # It records tool identity and argument digests, never raw argument values.
      class Audit
        LOG_PATH = ".master/audit.ndjson".freeze
        MAX_BYTES = 5 * 1024 * 1024

        def initialize(root:, event_bus:)
          @path = File.join(root, LOG_PATH)
          @mutex = Mutex.new
          FileUtils.mkdir_p(File.dirname(@path))
          event_bus.subscribe("tool:before") { |event_data| append(event_data) }
        end

        private

        # The bus sends raw payloads to trusted in-process subscribers. This
        # private file is still durable storage, so it uses the same privacy
        # transform as the activity log rather than persisting arguments.
        def append(event_data)
          safe = EventPrivacy.persisted("tool:before", event_data)
          fields = safe.except(:tool, :ts, :conversation)
          tool = safe[:tool] || "unknown"
          record = { ts: Time.now.utc.iso8601, session: Log.session, tool: tool }.merge(fields)
          Master::Trace::Telemetry.span("audit.append", tool: event_data[:tool].to_s) do
            @mutex.synchronize do
              Log.append_jsonl(@path, record, max_bytes: MAX_BYTES, mode: 0o600, directory_mode: 0o700)
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
          append!(event, payload)
        rescue SystemCallError, JSON::GeneratorError, ArgumentError, IOError => e
          # Stderr is last resort — cannot route through bus without risking recursion.
          Log.warn_once([@path, e.class], "event_log: #{@path}: #{e.message}")
          nil
        end

        # Strict variant for lifecycle events whose persistence is a safety
        # precondition. Best-effort telemetry continues to use #append.
        def append!(event, payload = {})
          record = build_record(event, payload)
          Log.append_jsonl(@path, record, max_bytes: MAX_BYTES, mode: 0o600, directory_mode: 0o700)
          record
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
        OPERATIONAL = /\A(?:core:effect:|tool:execution:|worker:|fix:transaction_|fix:(?:journal_|start\z|resume\z|interrupted\z|plan_bound\z|assessment_receipt_persisted\z|assessment_reports_pruned\z)|mission:(?:start|queued|resume|deferred|block|finish|interrupt|artifact|wake|requeued|checkpoint)\z|ops:|pipeline:rollback|fix_loop:commit|resync:|deploy:)/

        def initialize(root: Master::ROOT)
          @log = Event.new(root:, stream: "evidence")
        end

        def operational?(event) = event.to_s.match?(OPERATIONAL)

        def append(event, payload = {}) = @log.append(event, payload)

        def append!(event, payload = {}) = @log.append!(event, payload)

        def recent(limit, pattern: nil) = @log.recent(limit, pattern:)
      end
    end
  end
end
