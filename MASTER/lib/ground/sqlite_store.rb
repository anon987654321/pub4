# frozen_string_literal: true

require "sqlite3"
require "fileutils"

module Master
  module Ground
    # Opens a SQLite DB with WAL → DELETE → :memory: fallback so a read-only
    # filesystem or locked WAL never crashes the store.
    module SqliteStore
      @sqlite_warned = false
      @chmod_warned = false
      JOURNAL_MODES = {
        "WAL" => "PRAGMA journal_mode = WAL",
        "DELETE" => "PRAGMA journal_mode = DELETE",
      }.freeze

      class << self
        def warn_chmod_unsupported_once(path)
          return if @chmod_warned

          @chmod_warned = true
          warn "sqlite_store: chmod unsupported for #{path}; continuing with filesystem permissions"
        end
      end

      def open_sqlite(root, relative_path)
        path = File.join(root, relative_path)
        prepare_sqlite_path(path)
        database = SQLite3::Database.new(path)
        journal_ok = set_journal_mode(database, path, "WAL") || set_journal_mode(database, path, "DELETE")
        unless journal_ok
          database.close rescue SQLite3::Exception
          sqlite_warn_once("file DB unavailable at #{path} — using :memory:")
          database = SQLite3::Database.new(":memory:")
        end
        database
      rescue SQLite3::Exception => e
        sqlite_warn_once("#{e.message} — using :memory:")
        SQLite3::Database.new(":memory:")
      end

      def prepare_sqlite_path(path)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir, mode: 0o700)
        harden_sqlite_directory(dir)
        FileUtils.touch(path) unless File.exist?(path)
      end

      def harden_sqlite_directory(dir)
        FileUtils.chmod(0o700, dir)
      rescue Errno::ENOSYS, Errno::EOPNOTSUPP
        SqliteStore.warn_chmod_unsupported_once(dir)
      end

      def set_journal_mode(database, path, mode)
        statement = JOURNAL_MODES.fetch(mode)
        database.execute(statement)
        true
      rescue SQLite3::IOException
        clear_wal_sidecars(path)
        database.execute(statement)
        true
      rescue KeyError, SQLite3::Exception => e
        Master::Ground::Swallow.log(e, context: "SqliteStore.set_journal_mode")
        false
      end

      def clear_wal_sidecars(path)
        %w[-wal -shm -journal].each do |suffix|
          sidecar = "#{path}#{suffix}"
          File.delete(sidecar) if File.exist?(sidecar)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "SqliteStore.clear_wal_sidecars")
        nil
      end

      def sqlite_warn_once(message)
        return if @sqlite_warned

        @sqlite_warned = true
        warn "sqlite_store: #{message}"
      end
    end
  end
end
