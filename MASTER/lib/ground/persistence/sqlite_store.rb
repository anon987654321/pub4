# frozen_string_literal: true

require "sqlite3"
require "fileutils"

module Master
  module Ground
    module Persistence
      # Opens a SQLite DB with WAL → DELETE → :memory: fallback so a read-only
      # filesystem or locked WAL never crashes the store.
      module SqliteStore
        @sqlite_warned = false

        def open_sqlite(root, relative_path)
          path = File.join(root, relative_path)
          dir = File.dirname(path)
          FileUtils.mkdir_p(dir, mode: 0o700)
          FileUtils.chmod(0o700, dir) if File.directory?(dir)
          FileUtils.touch(path) unless File.exist?(path)
          db = SQLite3::Database.new(path)
          journal_ok = set_journal_mode(db, path, "WAL") || set_journal_mode(db, path, "DELETE")
          unless journal_ok
            db.close rescue SQLite3::Exception
            sqlite_warn_once("file DB unavailable at #{path} — using :memory:")
            db = SQLite3::Database.new(":memory:")
          end
          db
        rescue SQLite3::Exception => e
          sqlite_warn_once("#{e.message} — using :memory:")
          SQLite3::Database.new(":memory:")
        end

        def set_journal_mode(db, path, mode)
          db.execute("PRAGMA journal_mode = #{mode}")
          true
        rescue SQLite3::IOException
          clear_wal_sidecars(path)
          db.execute("PRAGMA journal_mode = #{mode}")
          true
        rescue SQLite3::Exception
          false
        end

        def clear_wal_sidecars(path)
          %w[-wal -shm -journal].each do |suffix|
            sidecar = "#{path}#{suffix}"
            File.delete(sidecar) if File.exist?(sidecar)
          end
        rescue StandardError
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
end
