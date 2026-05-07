# frozen_string_literal: true

require "sqlite3"
require "json"

module Master
  module Persistence
    # SQLite-backed findings store. Replaces .master/findings.jsonl when present;
    # otherwise no-op so existing JSONL flow continues unaltered. Exposes time-series
    # queries the JSONL stream cannot answer (rule frequency over time, by directory).
    class SqliteFindings
      DEFAULT_PATH = ".master/findings.sqlite3"

      def initialize(root:)
        path = File.join(root, DEFAULT_PATH)
        FileUtils.mkdir_p(File.dirname(path))
        @db = SQLite3::Database.new(path)
        @db.execute "PRAGMA journal_mode = WAL"
        ensure_schema
      end

      def record(rule:, message:, line:, severity:, path:, tags: [])
        @db.execute(<<~SQL, [Time.now.to_i, rule.to_s, message.to_s, line.to_i, severity.to_s, path.to_s, tags.to_json])
          INSERT INTO findings (ts, rule, message, line, severity, path, tags) VALUES (?, ?, ?, ?, ?, ?, ?)
        SQL
      end

      def top_rules(since_days: 30, limit: 10)
        cutoff = Time.now.to_i - since_days * 86_400
        @db.execute(<<~SQL, [cutoff, limit])
          SELECT rule, COUNT(*) AS n FROM findings WHERE ts >= ?
          GROUP BY rule ORDER BY n DESC LIMIT ?
        SQL
      end

      def by_directory(since_days: 30)
        cutoff = Time.now.to_i - since_days * 86_400
        @db.execute(<<~SQL, [cutoff])
          SELECT substr(path, 1, instr(path || '/', '/lib/') + 4) AS dir,
                 COUNT(*) AS n FROM findings WHERE ts >= ?
          GROUP BY dir ORDER BY n DESC
        SQL
      end

      def close
        @db&.close
      end

      private

      def ensure_schema
        @db.execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS findings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            rule TEXT NOT NULL,
            message TEXT NOT NULL,
            line INTEGER,
            severity TEXT,
            path TEXT,
            tags TEXT
          );
          CREATE INDEX IF NOT EXISTS idx_findings_ts ON findings(ts);
          CREATE INDEX IF NOT EXISTS idx_findings_rule ON findings(rule);
          CREATE INDEX IF NOT EXISTS idx_findings_path ON findings(path);
        SQL
      end
    end
  end
end
