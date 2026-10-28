# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "socket"
require "time"
require_relative "kernel/lifecycle_journal"
require_relative "kernel/lifecycle"

module Master
  module Fix
    # Reads the hash-chained audit log at `<workspace>/.master/log.jsonl` for
    # `bin/master replay <seq>`. Nothing in the runtime appends to the log; the
    # reader stays so an existing log can still be verified and replayed, and it
    # refuses a broken chain rather than returning a partial history.
    class Kernel
      include Lifecycle

      GENESIS = "0" * 64
      LOG_RELATIVE_PATH = ".master/log.jsonl"

      class LedgerCorruption < StandardError; end

      # Kernel coordinates /fix and owns its hash-chained run receipts. The
      # legacy replay API below remains the same; lifecycle metadata lives in
      # the separate, schema-preserving RunJournal adapter.
      def initialize(root:, actor: "master", bus: nil, log_path: nil, lifecycle_journal: nil)
        @root = File.expand_path(root)
        @workspace_root = self.class.send(:locate_workspace, @root)
        @actor = actor.to_s
        @bus = bus
        @log_path = File.expand_path(log_path || File.join(@workspace_root, LOG_RELATIVE_PATH))
        @lifecycle_journal = lifecycle_journal
        @lifecycle_mutex = Mutex.new
        @execution_mutex = Mutex.new
        @current_run_id = nil
      end

      attr_reader :root, :workspace_root, :actor, :log_path, :execution_mutex

      def verify_log!
        self.class.read_log(@log_path)
      end

      # Append under an exclusive file lock and verify the prior chain before
      # assigning the next sequence. A torn or edited prefix is a hard refusal.
      def append_event(kind, payload, run_id: nil)
        FileUtils.mkdir_p(File.dirname(@log_path), mode: 0o700)
        File.open(@log_path, File::RDWR | File::CREAT, 0o600) do |file|
          file.flock(File::LOCK_EX)
          previous = self.class.read_log_io(file).last
          body = {
            "seq" => previous ? previous.fetch("seq") + 1 : 1,
            "at" => Time.now.utc.iso8601(6),
            "run_id" => run_id,
            "kind" => kind.to_s,
            "payload" => payload,
            "prev" => previous ? previous.fetch("hash") : GENESIS
          }
          row = body.merge("hash" => Digest::SHA256.hexdigest(JSON.generate(body)))
          line = JSON.generate(row) + "\n"
          file.seek(0, IO::SEEK_END)
          written = file.write(line)
          raise IOError, "ledger append wrote #{written || 0} of #{line.bytesize} bytes" unless written == line.bytesize

          file.flush
          file.fsync
          row
        ensure
          file.flock(File::LOCK_UN) rescue nil
        end
      end

      def self.replay_events(root:, seq:)
        number = Integer(seq)
        raise ArgumentError, "sequence must be a positive integer" unless number.positive?

        path = File.join(locate_workspace(File.expand_path(root)), LOG_RELATIVE_PATH)
        events = read_log(path)
        selected = events.find { |row| row.fetch("seq") == number }
        return nil unless selected

        run_id = selected["run_id"]
        run_events = run_id ? events.select { |row| row["run_id"] == run_id } : [selected]
        { "sequence" => number, "run_id" => run_id, "events" => run_events }
      end

      def self.replay_cli(root:, seq:)
        unless seq && seq.match?(/\A[1-9][0-9]*\z/)
          warn "master0: usage master replay sequence"
          return 64
        end

        result = replay_events(root:, seq:)
        unless result
          warn "master0: replay sequence not found"
          return 1
        end

        puts JSON.pretty_generate(result)
        0
      rescue LedgerCorruption => error
        warn "master0: audit log corrupt, #{error.message}"
        1
      rescue StandardError => error
        warn "master0: replay failed, #{error.class}: #{error.message}"
        1
      end

      def self.read_log(path)
        return [] unless File.file?(path)

        File.open(path, "rb") { |file| read_log_io(file) }
      end

      # Every record must carry the next sequence number, the previous
      # record's hash and its own body hash; any gap, edit or torn final line
      # is corruption.
      def self.read_log_io(file)
        previous = GENESIS
        expected_seq = 1
        events = []

        file.rewind
        file.each_line.with_index(1) do |line, line_number|
          begin
            raise LedgerCorruption, "line #{line_number}: incomplete final record" unless line.end_with?("\n")
            next if line.strip.empty?

            row = JSON.parse(line)
            body = row.reject { |key, _| key == "hash" }

            raise LedgerCorruption, "line #{line_number}: sequence gap" unless row.fetch("seq") == expected_seq
            raise LedgerCorruption, "line #{line_number}: previous hash mismatch" unless row.fetch("prev") == previous
            actual = Digest::SHA256.hexdigest(JSON.generate(body))
            raise LedgerCorruption, "line #{line_number}: event hash mismatch" unless actual == row.fetch("hash")

            events << row
            previous = row.fetch("hash")
            expected_seq += 1
          rescue JSON::ParserError, KeyError, TypeError, NoMethodError => error
            raise LedgerCorruption, "line #{line_number}: #{error.message}"
          end
        end
        events
      end

      def self.locate_workspace(path)
        cursor = path
        loop do
          return cursor if File.exist?(File.join(cursor, ".git"))

          parent = File.dirname(cursor)
          return path if parent == cursor

          cursor = parent
        end
      end

      private_class_method :locate_workspace
    end
  end
end
