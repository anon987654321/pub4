# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "kernel/lifecycle_journal"
require_relative "kernel/lifecycle"

module Master
  module Fix
    # Owns the hash-chained /fix coordinator lifecycle and keeps the replay
    # reader public for `bin/master replay <seq>`. It does not apply repairs;
    # FixLoop, RepairAdapter and Transaction retain the mutation responsibilities.
    # A broken chain is refused rather than returned as partial history.
    class Kernel
      include Lifecycle

      GENESIS = "0" * 64
      LOG_RELATIVE_PATH = ".master/log.jsonl"

      class LedgerCorruption < StandardError; end

      # Serializes /fix across independent Kernel instances and OS processes.
      # The per-instance mutex prevents local re-entry; flock is the authority
      # shared by every process operating on the same repository checkout.
      class ExecutionLock
        RELATIVE_PATH = ".master/fix-execution.lock"

        attr_reader :path

        def initialize(root:)
          workspace = File.expand_path(root)
          @directory = File.join(workspace, ".master")
          @path = File.join(workspace, RELATIVE_PATH)
          @mutex = Mutex.new
        end

        def synchronize
          @mutex.synchronize do
            raise IOError, "refusing symlinked .master directory" if File.symlink?(@directory)

            FileUtils.mkdir_p(@directory, mode: 0o700)
            directory_stat = File.lstat(@directory)
            unless directory_stat.directory? && !directory_stat.symlink?
              raise IOError, "refusing non-directory or symlinked .master path"
            end
            if (directory_stat.mode & 0o022).positive?
              raise IOError, "refusing group/world-writable .master directory"
            end
            raise IOError, "refusing symlinked execution lock" if File.symlink?(@path)

            flags = File::RDWR | File::CREAT
            flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
            File.open(@path, flags, 0o600) do |file|
              validate_lock_identity!(file, directory_stat)
              mode = file.stat.mode & 0o777
              unless (mode & 0o077).zero?
                raise IOError, "execution lock permissions must be private (0600 or stricter)"
              end
              raise IOError, "could not acquire /fix execution lock" unless file.flock(File::LOCK_EX)

              begin
                # A path or parent directory can be swapped while this process
                # waits for flock. Never enter /fix on an orphaned inode that no
                # longer serializes callers using the canonical lock pathname.
                validate_lock_identity!(file, directory_stat)
                mode = file.stat.mode & 0o777
                unless (mode & 0o077).zero?
                  raise IOError, "execution lock permissions changed while waiting"
                end
                current_directory = File.lstat(@directory)
                if (current_directory.mode & 0o022).positive?
                  raise IOError, "refusing group/world-writable .master directory"
                end
                yield
              ensure
                file.flock(File::LOCK_UN)
              end
            end
          end
        end
        private

        def validate_lock_identity!(file, original_directory_stat)
          current_directory = File.lstat(@directory)
          unless current_directory.directory? && !current_directory.symlink? &&
                 current_directory.dev == original_directory_stat.dev &&
                 current_directory.ino == original_directory_stat.ino
            raise IOError, "refusing changed .master directory during execution-lock acquisition"
          end

          opened = file.stat
          unless opened.file? && opened.nlink == 1
            raise IOError, "execution lock must be a singly linked regular file"
          end
          current = File.lstat(@path)
          unless current.file? && !current.symlink? &&
                 current.dev == opened.dev && current.ino == opened.ino
            raise IOError, "execution lock path changed while opening or waiting"
          end
        rescue SystemCallError => e
          raise IOError, "execution lock path changed while opening or waiting: #{e.message}"
        end

      end

      # The Kernel owns coordinator receipts only. FixLoop/RepairLoop and
      # Transaction remain the sole repository-mutation path.
      def initialize(root:, actor: "fix", bus: nil, log_path: nil, lifecycle_journal: nil)
        @root = File.expand_path(root)
        @workspace_root = self.class.send(:locate_workspace, @root)
        @actor = actor.to_s
        @bus = bus
        @log_path = File.expand_path(log_path || File.join(@workspace_root, LOG_RELATIVE_PATH))
        @log_head = nil
        @lifecycle_journal = lifecycle_journal
        @lifecycle_mutex = Mutex.new
        @execution_mutex = ExecutionLock.new(root: @workspace_root)
        @append_mutex = Mutex.new
      end

      attr_reader :root, :workspace_root, :actor, :log_path, :execution_mutex

      def verify_log!
        self.class.read_log(@log_path)
      end

      def append_event(kind, payload, run_id: nil)
        @append_mutex.synchronize do
          directory = File.dirname(@log_path)
          raise LedgerCorruption, "ledger directory is a symlink" if File.symlink?(directory)

          FileUtils.mkdir_p(directory, mode: 0o700)
          directory_stat = File.lstat(directory)
          unless directory_stat.directory? && !directory_stat.symlink?
            raise LedgerCorruption, "ledger directory is not a real directory"
          end
          raise LedgerCorruption, "ledger directory is group/world writable" if
            (directory_stat.mode & 0o022).positive?
          raise LedgerCorruption, "ledger path is a symlink" if File.symlink?(@log_path)

          if File.exist?(@log_path)
            path_stat = File.lstat(@log_path)
            raise LedgerCorruption, "ledger path is not a regular file" unless
              path_stat.file? && !path_stat.symlink?
            raise LedgerCorruption, "ledger permissions are not private" unless
              (path_stat.mode & 0o077).zero?
          end

          flags = File::RDWR | File::CREAT
          flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
          File.open(@log_path, flags, 0o600) do |file|
            opened_stat = file.stat
            raise LedgerCorruption, "ledger handle is not a regular file" unless opened_stat.file?
            raise LedgerCorruption, "ledger permissions are not private" unless
              (opened_stat.mode & 0o077).zero?
            current_stat = File.lstat(@log_path)
            unless current_stat.file? && !current_stat.symlink? &&
                   current_stat.dev == opened_stat.dev && current_stat.ino == opened_stat.ino
              raise LedgerCorruption, "ledger path changed while opening"
            end

            raise IOError, "could not acquire ledger append lock" unless file.flock(File::LOCK_EX)
            current_stat = File.lstat(@log_path)
            unless current_stat.file? && !current_stat.symlink? &&
                   current_stat.dev == opened_stat.dev && current_stat.ino == opened_stat.ino
              raise LedgerCorruption, "ledger path changed while waiting for its lock"
            end
            head = append_head(file)
            body = {
              "seq" => head.fetch(:seq) + 1, "at" => Time.now.utc.iso8601(6),
              "run_id" => run_id, "kind" => kind.to_s, "payload" => payload,
              "prev" => head.fetch(:hash)
            }
            row = body.merge("hash" => Digest::SHA256.hexdigest(JSON.generate(body)))
            line = JSON.generate(row) + "\n"
            file.seek(0, IO::SEEK_END)
            written = file.write(line)
            raise IOError, "ledger append wrote #{written || 0} of #{line.bytesize} bytes" unless
              written == line.bytesize

            file.flush
            file.fsync
            cache_log_head(file, row.fetch("seq"), row.fetch("hash"))
            row
          ensure
            file.flock(File::LOCK_UN) rescue nil
          end
        end
      end

      def append_head(file)
        stat = file.stat
        cached = @log_head
        if cached
          unless stat.dev == cached.fetch(:dev) && stat.ino == cached.fetch(:ino) &&
                 stat.size >= cached.fetch(:size)
            raise LedgerCorruption, "ledger identity changed or ledger was truncated"
          end
          if stat.size > cached.fetch(:size)
            # A different writer may have appended, but suffix-only validation
            # trusts the cached prefix without proving that its bytes survived.
            # Re-validate the complete chain before adopting the new head.
            events = self.class.read_log_io(file)
            last = events.last
            return cache_log_head(file, last ? last.fetch("seq") : 0,
                                  last ? last.fetch("hash") : GENESIS)
          end
          return cached if stat.mtime == cached.fetch(:mtime) && stat.ctime == cached.fetch(:ctime)
        end

        events = self.class.read_log_io(file)
        last = events.last
        cache_log_head(file, last ? last.fetch("seq") : 0, last ? last.fetch("hash") : GENESIS)
      end

      def cache_log_head(file, seq, hash)
        stat = file.stat
        @log_head = {
          dev: stat.dev, ino: stat.ino, size: stat.size,
          mtime: stat.mtime, ctime: stat.ctime, seq:, hash:
        }
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
        directory = File.dirname(File.expand_path(path))
        raise LedgerCorruption, "ledger directory is a symlink" if File.symlink?(directory)
        return [] unless File.exist?(path) || File.symlink?(path)

        path_stat = File.lstat(path)
        raise LedgerCorruption, "ledger path is not a regular file" unless
          path_stat.file? && !path_stat.symlink?
        raise LedgerCorruption, "ledger permissions are not private" unless
          (path_stat.mode & 0o077).zero?

        File.open(path, "rb") do |file|
          opened_stat = file.stat
          unless opened_stat.file? && opened_stat.dev == path_stat.dev && opened_stat.ino == path_stat.ino
            raise LedgerCorruption, "ledger path changed while opening"
          end
          read_log_io(file)
        end
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
