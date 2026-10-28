# frozen_string_literal: true

require "digest"
require "json"

module Master
  module Fix
    # Reads the hash-chained audit log at `<workspace>/.master/log.jsonl` for
    # `bin/master replay <seq>`. Nothing in the runtime appends to the log; the
    # reader stays so an existing log can still be verified and replayed, and it
    # refuses a broken chain rather than returning a partial history.
    class Kernel
      GENESIS = "0" * 64
      LOG_RELATIVE_PATH = ".master/log.jsonl"

      class LedgerCorruption < StandardError; end

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
        expanded = File.expand_path(path)
        directory = File.dirname(expanded)

        unless File.exist?(directory) || File.symlink?(directory)
          return [] unless File.exist?(expanded) || File.symlink?(expanded)

          raise LedgerCorruption, "audit log exists without its parent directory"
        end
        directory_stat = File.lstat(directory)
        unless directory_stat.directory? && !directory_stat.symlink?
          raise LedgerCorruption, "refusing non-directory or symlinked audit log directory"
        end
        if (directory_stat.mode & 0o022).positive?
          raise LedgerCorruption, "audit log directory is group/world writable"
        end
        return [] unless File.exist?(expanded) || File.symlink?(expanded)

        path_stat = File.lstat(expanded)
        unless path_stat.file? && !path_stat.symlink? && path_stat.nlink == 1
          raise LedgerCorruption, "refusing symlinked, hard-linked or non-regular audit log"
        end
        if (path_stat.mode & 0o077).positive?
          raise LedgerCorruption, "audit log permissions must be private (0600 or stricter)"
        end

        flags = File::RDONLY
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        File.open(expanded, flags) do |file|
          opened = file.stat
          current = File.lstat(expanded)
          unless current.file? && !current.symlink? && current.nlink == 1 &&
                 current.dev == opened.dev && current.ino == opened.ino
            raise LedgerCorruption, "audit log path changed while opening"
          end

          events = read_log_io(file)
          after = File.lstat(expanded)
          unless after.file? && !after.symlink? && after.nlink == 1 &&
                 after.dev == opened.dev && after.ino == opened.ino &&
                 after.size == opened.size && after.mtime == opened.mtime && after.ctime == opened.ctime
            raise LedgerCorruption, "audit log changed while reading"
          end
          events
        end
      rescue SystemCallError => error
        raise LedgerCorruption, "audit log cannot be opened safely: #{error.class}: #{error.message}"
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
