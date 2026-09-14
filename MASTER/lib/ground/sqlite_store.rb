# frozen_string_literal: true

require "sqlite3"
require "fileutils"

module Master
  module Ground
    # Opens a SQLite DB with WAL → DELETE. Ephemeral memory is opt-in because
    # silently losing persistence violates evidence and continuity guarantees.
    #
    # The fallback suits the one includer, KnowledgeStore, a rebuildable ledger under the
    # gitignored .master/. Pairing and memory are YAML, not SQLite, and never reach it.
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
           database.close rescue nil
           return ephemeral_database(path)
           end

        database
       rescue SQLite3::Exception => e
         return ephemeral_database(path) if ENV["MASTER_ALLOW_EPHEMERAL_DB"] == "1"
         raise
       end
 
       def ephemeral_database(path)
         unless ENV["MASTER_ALLOW_EPHEMERAL_DB"] == "1"
           raise SQLite3::Exception,
                 "persistent database unavailable at #{path}; set MASTER_ALLOW_EPHEMERAL_DB=1 only for disposable runs"
         end
 
         sqlite_warn_once("persistent DB unavailable at #{path} — using :memory: (explicitly allowed)")
         SQLite3::Database.new(":memory:")
       end
 
       def prepare_sqlite_path(path)

        dir = File.dirname(path)
        FileUtils.mkdir_p(dir, mode: 0o700)
        harden_sqlite_directory(dir)
        FileUtils.touch(path) unless File.exist?(path)
      end

      # Clears "other" and leaves owner and group alone, rather than clamping
      # to 0700. The store is shared on purpose where MASTER runs as its own
      # user: rc.d/master documents .master as dev:master 2775, and 0700 undid
      # that on every boot the dev CLI took, locking the daemon out of the
      # state directory it is given.
      #
      # EPERM is rescued for the same reason. chmod belongs to the owner, so
      # the daemon raised it re-hardening a directory dev owns -- and this runs
      # inside container bootstrap, where an unrescued raise leaves the whole
      # web tier serving "Starting up..." with no container and no way back.
      def harden_sqlite_directory(dir)
        mode = File.stat(dir).mode & 0o7777
        return if (mode & 0o007).zero?

        FileUtils.chmod(mode & 0o7770, dir)
      rescue Errno::ENOSYS, Errno::EOPNOTSUPP, Errno::EPERM
        SqliteStore.warn_chmod_unsupported_once(dir)
      end

      def set_journal_mode(database, path, mode)
        statement = JOURNAL_MODES.fetch(mode)
        database.execute(statement)
        true
       rescue SQLite3::IOException
         false
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
