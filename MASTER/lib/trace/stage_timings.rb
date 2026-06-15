# frozen_string_literal: true

require "json"
require "sqlite3"

module Master
  module Trace
    # CD03: persist _timings per stage to SQLite for latency analysis.
    class StageTimings
      def initialize(root:)
        @db_path = File.join(root, ".master", "knowledge.sqlite3")
        ensure_schema!
      end

      def record(stage:, ms:, session_id: nil, meta: {})
        db.execute(
          "INSERT INTO stage_timings(stage, ms, session_id, meta, recorded_at) VALUES(?,?,?,?,?)",
          [stage.to_s, ms.to_f, session_id, JSON.generate(meta), Time.now.utc.iso8601]
        )
      end

      def recent(limit: 50)
        db.execute("SELECT stage, ms, session_id, recorded_at FROM stage_timings ORDER BY id DESC LIMIT ?", [limit])
      end

      private

      def db
        @db ||= SQLite3::Database.new(@db_path)
      end

      def ensure_schema!
        db.execute <<~SQL
          CREATE TABLE IF NOT EXISTS stage_timings (
            id INTEGER PRIMARY KEY,
            stage TEXT NOT NULL,
            ms REAL NOT NULL,
            session_id TEXT,
            meta TEXT,
            recorded_at TEXT NOT NULL
          );
        SQL
      end
    end
  end
end