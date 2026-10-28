# frozen_string_literal: true

require "json"
require "fileutils"
require "digest"
require_relative "event_privacy"
require_relative "../boot/paths"

module Master
  module Trace
  # Trace — captures all bus events for the current turn into a JSONL log
  # at .master/traces/YYYY-MM-DD.jsonl (local state, never data/ — a runtime
  # write target inside the law tree read as config). One turn record per line.
  # /why formats the last turn.
    class Recorder
      EVENT_PATTERNS = %w[gateway:* pipeline:* tool:after route:* council:* memo:* lint:* governor:*].freeze
      MAX_EVENTS_PER_TURN = 200
      KEEP_DAYS = 14

      def initialize(root:, event_bus:)
        @dir = File.join(root, ".master", "traces")
        @bus = event_bus
        @mutex = Mutex.new
        @current = nil
        @last = nil
        prepare_storage_directory!
        subscribe
      end

      def last_turn = @last

      def pretty_last
        turn = @last || load_last_from_disk
        return "no trace recorded yet" unless turn

        lines = ["turn #{turn[:id]}  ts=#{turn[:start_ts]}  channel=#{turn[:channel]}"]
        message = turn.fetch(:message, "")
        shown = message.is_a?(Hash) ? "#{message[:bytes]} bytes, kept as a digest" : message.to_s[0, 100]
        lines << "  message: #{shown}"
        turn[:events].each do |ev|
          ms = ev[:ts_ms]
          name = ev[:event]
          detail = ev.except(:ts_ms, :event).reject { |_, v| v.nil? }
          lines << "  +#{ms.to_s.rjust(5)}ms  #{name}  #{detail.empty? ? "" : detail.inspect}"
        end
        lines.join("\n")
      end

      private

      def subscribe
        EVENT_PATTERNS.each { |pat| @bus.subscribe(pat) { |ev| record(ev) } }
      end

      def record(event)
        @mutex.synchronize do
          if event[:event] == "gateway:turn_start"
            @current = { id: event[:turn_id], start_ts: Time.now.to_i, channel: event[:channel],
                         message: event[:message], events: [], t0: event[:ts] }
            next
          end
          if @current && event[:event] == "gateway:turn_done"
            @current[:events] << relative(event)
            finalize(@current)
            @last = @current
            @current = nil
            next
          end
          next unless @current
          next if @current[:events].size >= MAX_EVENTS_PER_TURN
          @current[:events] << relative(event)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "recorder.ingest")
      end

      def relative(ev)
        ts0 = @current.fetch(:t0, 0)
        ev.merge(ts_ms: (ev.fetch(:ts, 0)) - ts0).except(:ts)
      end

      # Disk gets what the event log gets: the same EventPrivacy transform, the message as a
      # digest and length, owner-only, two weeks kept. Subscribers see raw payloads, and this
      # wrote them as they came: chat text, tool URLs and queries, in 0644 daily files.
      # /why keeps the full turn in memory for the process that recorded it.
      def finalize(turn)
        path = File.join(@dir, "#{Time.now.strftime("%Y-%m-%d")}.jsonl")
        append_private_line(path, JSON.generate(persisted(turn)) + "\n")
        prune
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "recorder.finalize", path:)
      end

      def prepare_storage_directory!
        state_directory = File.dirname(@dir)
        ensure_private_directory!(state_directory, shared_state: true)
        ensure_private_directory!(@dir)
      end

      def ensure_private_directory!(path, shared_state: false)
        raise IOError, "refusing symlinked trace directory" if File.symlink?(path)

        FileUtils.mkdir_p(path, mode: 0o700)
        stat = File.lstat(path)
        unless stat.directory? && !stat.symlink?
          raise IOError, "trace storage path is not a real directory"
        end

        # The checkout's .master directory is deliberately shared with the
        # service group on vm23. Apply its existing canonical permission policy
        # instead of breaking the Rails service by forcing 0700; the per-trace
        # directory and files remain owner-private.
        expected_mode = shared_state ? MasterPaths.private_dir_mode(path, 0o700) : 0o700
        File.chmod(expected_mode, path) if (stat.mode & 0o7777) != expected_mode
        current = File.lstat(path)
        unsafe_mask = shared_state ? 0o0007 : 0o0077
        raise IOError, "trace storage directory permissions must be private" unless
          (current.mode & unsafe_mask).zero?
      end

      def append_private_line(path, line)
        prepare_storage_directory!
        raise IOError, "refusing symlinked trace file" if File.symlink?(path)

        flags = File::RDWR | File::APPEND | File::CREAT
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        File.open(path, flags, 0o600) do |file|
          validate_trace_file!(file, path)
          raise IOError, "could not acquire trace file lock" unless file.flock(File::LOCK_EX)

          begin
            validate_trace_file!(file, path)
            # Existing files keep their old mode when opened with CREAT. Repair it
            # before writing any new trace bytes, never after the sensitive append.
            file.chmod(0o600)
            validate_trace_file!(file, path)
            raise IOError, "trace file permissions are not private" unless
              (file.stat.mode & 0o077).zero?

            if file.stat.size.positive?
              file.seek(-1, IO::SEEK_END)
              unless file.read(1) == "\n"
                raise IOError, "refusing to append after an incomplete trace record"
              end
            end

            offset = 0
            while offset < line.bytesize
              written = file.write(line.byteslice(offset..))
              raise IOError, "trace append wrote no bytes" unless written&.positive?

              offset += written
            end
            file.flush
            file.fsync
          ensure
            file.flock(File::LOCK_UN)
          end
        end
      end

      def validate_trace_file!(file, path)
        prepare_storage_directory!
        opened = file.stat
        unless opened.file? && opened.nlink == 1
          raise IOError, "trace file must be a singly linked regular file"
        end
        current = File.lstat(path)
        unless current.file? && !current.symlink? &&
               current.dev == opened.dev && current.ino == opened.ino
          raise IOError, "trace file path changed while opening"
        end
      end

      def persisted(turn)
        message = turn[:message].to_s
        events = turn[:events].map do |event|
          EventPrivacy.persisted(event[:event].to_s, event.except(:event)).merge(event: event[:event])
        end
        turn.merge(message: { sha256: Digest::SHA256.hexdigest(message), bytes: message.bytesize }, events:)
      end

      def prune
        prepare_storage_directory!
        cutoff = Time.now - (KEEP_DAYS * 86_400)
        Dir.children(@dir).each do |name|
          next unless /\A\d{4}-\d{2}-\d{2}\.jsonl\z/.match?(name)

          path = File.join(@dir, name)
          stat = File.lstat(path)
          next unless stat.file? && !stat.symlink? && stat.nlink == 1
          next unless stat.mtime < cutoff

          File.unlink(path)
        end
      end

      def load_last_from_disk
        prepare_storage_directory!
        files = Dir.children(@dir).filter_map do |name|
          next unless /\A\d{4}-\d{2}-\d{2}\.jsonl\z/.match?(name)

          path = File.join(@dir, name)
          stat = File.lstat(path)
          path if stat.file? && !stat.symlink? && stat.nlink == 1
        end.sort
        return if files.empty?

        # Streamed rather than read whole: a day of turns can be a large file.
        path = files.last
        flags = File::RDONLY
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        File.open(path, flags) do |file|
          validate_trace_file!(file, path)
          file.chmod(0o600)
          last_line = file.each_line.inject(nil) { |_, line| line }
          validate_trace_file!(file, path)
          last_line ? JSON.parse(last_line, symbolize_names: true) : nil
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "recorder.load_last_from_disk")
        nil
      end
    end
  end
end
