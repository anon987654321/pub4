# frozen_string_literal: true

require "fileutils"
require "json"
# MasterPaths::ROOT rather than Master::ROOT, which is defined in lib/master.rb
# and therefore only exists after a full runtime boot. lib/io/replicate_client.rb
# is deliberately standalone-loadable -- MASTER/tools/preprompt and MASTER/tools/lora both
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
      # Under .master/, not runtime/events/: the record holds unredacted messages and backtraces at
      # mode 0600, beside the operator token, where nothing is served or packed. It writes with no
      # bus and no boot because STUDIO loads Swallow alone.
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
      MAX_BYTES = 10_485_760
      KEEP_BACKUPS = 5

      class << self
        def event_bus=(bus)
          @event_bus = bus
        end

        def log(error, context:, event_bus: nil, severity: :cosmetic, **meta)
          payload = build_payload(error, context, severity, meta)
          bus = event_bus || @event_bus
          reporting = Thread.current.thread_variable_get(:master_swallow_reporting)

          unless reporting
            Thread.current.thread_variable_set(:master_swallow_reporting, true)
            begin
              bus&.publish("error:swallowed", payload)
            ensure
              Thread.current.thread_variable_set(:master_swallow_reporting, false)
            end
          end

          write_structured_log(payload)
        rescue StandardError => e
          # Last resort: stderr if even the logger fails, once per cause. On a
          # full disk every swallow fails alike, and each line lands mid-prompt.
          @unrecorded ||= {}
          if defined?(Master::Trace::Dmesg)
            Master::Trace::Dmesg.once("error0", "cannot record error, #{e.class}: #{e.message}") unless @unrecorded[e.class]
          else
            warn "error0: cannot record error, #{e.class}: #{e.message}" unless @unrecorded[e.class]
          end
          @unrecorded[e.class] = true
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

        # Rotate oversized logs without preserving a giant backup. The active
        # file and every retained generation are bounded, not just the filename
        # that new writes happen to reach.
        def rotate!(path: LOG_PATH, max_bytes: MAX_BYTES, keep: KEEP_BACKUPS)
          limit = Integer(max_bytes)
          raise ArgumentError, "swallow log limit must be positive" unless limit.positive?
          return unless File.file?(path) && File.size(path) > limit

          backup = "#{path}.#{Time.now.utc.strftime("%Y%m%d%H%M%S%N")}-#{Process.pid}"
          File.rename(path, backup)
          compact_rotated!(backup, limit)
          # The sidecar lock is not a rotated generation and must never be
          # unlinked while another process could be waiting on its inode.
          prefix = "#{File.basename(path)}."
          backups = Dir.glob("#{path}.*").select do |candidate|
            File.basename(candidate).delete_prefix(prefix).match?(/\\A\\d{23}-\\d+\\z/)
          end
          backups.sort.reverse.drop([Integer(keep), 0].max).each do |old|
            File.delete(old) if File.file?(old) && !File.symlink?(old)
          end
        end

        def compact_rotated!(path, max_bytes)
          return unless File.file?(path)

          size = File.size(path)
          return size if size <= max_bytes

          tail = File.open(path, "rb") do |file|
            file.seek(-max_bytes, IO::SEEK_END)
            file.read(max_bytes)
          end
          File.open(path, "r+b") do |file|
            file.truncate(0)
            offset = 0
            while offset < tail.bytesize
              written = file.write(tail.byteslice(offset..))
              raise IOError, "swallow log compaction wrote no bytes" unless written&.positive?

              offset += written
            end
            file.flush
            file.fsync
          end
          File.size(path)
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
          directory = File.dirname(LOG_PATH)
          raise IOError, "swallow log directory is a symlink" if File.symlink?(directory)
          FileUtils.mkdir_p(directory, mode: 0o700)
          File.chmod(0o700, directory)
          line = JSON.generate(payload) + "\n"
          raise IOError, "swallow log record must be smaller than #{MAX_BYTES} bytes" if line.bytesize >= MAX_BYTES

          lock_path = "#{LOG_PATH}.lock"
          raise IOError, "swallow log lock is a symlink" if File.symlink?(lock_path)
          File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
            File.chmod(0o600, lock_path)
            lock.flock(File::LOCK_EX)

            raise IOError, "swallow log is a symlink" if File.symlink?(LOG_PATH)
            File.chmod(0o600, LOG_PATH) if File.file?(LOG_PATH)
            rotate!(max_bytes: MAX_BYTES - line.bytesize)
            File.open(LOG_PATH, File::WRONLY | File::CREAT | File::APPEND, 0o600) do |file|
              file.write(line)
              file.flush
              file.fsync
            end
          ensure
            lock.flock(File::LOCK_UN) if lock
          end
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
