# frozen_string_literal: true

require "sqlite3"
require "fileutils"

module Master
  module Ground
    module Persistence
      # Opens a SQLite DB with WAL → DELETE → :memory: fallback so a read-only
      # filesystem or locked WAL never crashes the store.
      module SqliteStore
        def open_sqlite(root, relative_path)
          path = File.join(root, relative_path)
          FileUtils.mkdir_p(File.dirname(path))
          db = SQLite3::Database.new(path)
          begin
            db.execute("PRAGMA journal_mode = WAL")
          rescue SQLite3::IOException
            begin
              db.execute("PRAGMA journal_mode = DELETE")
            rescue SQLite3::IOException
              db.close rescue nil
              warn "sqlite_store: file DB unavailable at #{path} — using :memory:"
              db = SQLite3::Database.new(":memory:")
            end
          end
          db
        rescue SQLite3::Exception => e
          warn "sqlite_store: #{e.message} — using :memory:"
          SQLite3::Database.new(":memory:")
        end
      end
    end
  end
end
