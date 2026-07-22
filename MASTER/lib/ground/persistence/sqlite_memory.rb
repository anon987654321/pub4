# frozen_string_literal: true

require "sqlite3"

module Master
  module Ground
    module Persistence
      # SQLite-backed memory with FTS5 full-text search. Replaces flat-file memory
      # once entries cross a few dozen. Each record carries a kind (user/feedback/
      # project/reference), a name, and body; FTS5 indexes name+body for /recall.
      class SqliteMemory
        include SqliteStore
        DEFAULT_PATH = ".master/memory.sqlite3"

        def initialize(root:)
          @db = open_sqlite(root, DEFAULT_PATH)
          ensure_schema
        end

        def upsert(name:, kind:, body:, description: "")
          @db.execute(<<~SQL, [name.to_s, kind.to_s, description.to_s, body.to_s, Time.now.to_i, name.to_s])
          INSERT INTO memories (name, kind, description, body, updated_at) VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(name) DO UPDATE SET kind=excluded.kind, description=excluded.description,
                                          body=excluded.body, updated_at=excluded.updated_at
          WHERE name = ?
        SQL
          rebuild_fts_for(name.to_s)
        end

        def recall(query, limit: 10)
          @db.execute(<<~SQL, [query.to_s, limit])
          SELECT m.name, m.kind, m.description, snippet(memories_fts, 1, '[', ']', '…', 12) AS hit
          FROM memories_fts JOIN memories m ON m.rowid = memories_fts.rowid
          WHERE memories_fts MATCH ? ORDER BY rank LIMIT ?
        SQL
        end

        def all
          @db.execute("SELECT name, kind, description, updated_at FROM memories ORDER BY updated_at DESC")
        end

        def delete(name)
          @db.execute("DELETE FROM memories WHERE name = ?", [name.to_s])
          @db.execute("DELETE FROM memories_fts WHERE name = ?", [name.to_s])
        end

        def close
          @db&.close
        end

        private

        def ensure_schema
          @db.execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            kind TEXT NOT NULL,
            description TEXT,
            body TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          );
          CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
            name, body, content='memories', content_rowid='id'
          );
          CREATE INDEX IF NOT EXISTS idx_memories_kind ON memories(kind);
        SQL
        end

        def rebuild_fts_for(_name)
          @db.execute("INSERT INTO memories_fts(memories_fts) VALUES('rebuild')")
        end
      end
    end
  end
end
