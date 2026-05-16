# frozen_string_literal: true

require "sqlite3"

module Master
  module Ground
  module Persistence
  # Architecture #10: SQLite-backed fix-quality ledger for reinforcement learning.
  # Records whether each rule+file_type fix attempt stuck (no regression next scan).
  # SuperLoop uses fix_quality as secondary priority sort key — high-quality rules
  # run first; rules that repeatedly fail to stick are deprioritised.
  class SqliteLearnings
    DEFAULT_PATH = ".master/learnings.sqlite3"
    QUALITY_WINDOW_DAYS = 30

    def initialize(root:)
      path = File.join(root, DEFAULT_PATH)
      FileUtils.mkdir_p(File.dirname(path))
      @db = SQLite3::Database.new(path)
      @db.results_as_hash = true
      @db.execute("PRAGMA journal_mode = WAL")
      ensure_schema
    end

    # Record a fix attempt outcome.
    # outcome: :fixed (violation gone next scan) | :stuck (violation persisted)
    def record(rule:, file_type:, outcome:)
      @db.execute(
        "INSERT INTO learnings (ts, rule, file_type, outcome) VALUES (?, ?, ?, ?)",
        [Time.now.to_i, rule.to_s, file_type.to_s, outcome.to_s]
      )
    rescue SQLite3::Exception => e
      warn "sqlite_learnings: #{e.message}"
    end

    # Fix quality score for a rule (and optionally a file type).
    # Returns float 0.0–1.0. Default 0.5 when no data.
    def fix_quality(rule:, file_type: nil)
      cutoff = Time.now.to_i - QUALITY_WINDOW_DAYS * 86_400
      rows = if file_type
        @db.execute(
          "SELECT outcome, COUNT(*) AS n FROM learnings WHERE rule = ? AND file_type = ? AND ts >= ? GROUP BY outcome",
          [rule.to_s, file_type.to_s, cutoff]
        )
      else
        @db.execute(
          "SELECT outcome, COUNT(*) AS n FROM learnings WHERE rule = ? AND ts >= ? GROUP BY outcome",
          [rule.to_s, cutoff]
        )
      end
      tally = rows.each_with_object(Hash.new(0)) { |r, h| h[r["outcome"]] = r["n"].to_i }
      total = tally.values.sum
      return 0.5 if total.zero?
      tally["fixed"].to_f / total
    end

    # Top rules by fix quality — useful for dashboard and priority bootstrapping.
    def top_rules(limit: 20, min_attempts: 3)
      cutoff = Time.now.to_i - QUALITY_WINDOW_DAYS * 86_400
      @db.execute(<<~SQL, [cutoff, min_attempts, limit])
        SELECT rule,
               SUM(CASE WHEN outcome = 'fixed' THEN 1 ELSE 0 END) AS fixed,
               COUNT(*) AS total,
               CAST(SUM(CASE WHEN outcome = 'fixed' THEN 1 ELSE 0 END) AS REAL) / COUNT(*) AS quality
        FROM learnings
        WHERE ts >= ?
        GROUP BY rule
        HAVING total >= ?
        ORDER BY quality DESC
        LIMIT ?
      SQL
    end

    def close = @db&.close

    private

    def ensure_schema
      @db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS learnings (
          id        INTEGER PRIMARY KEY AUTOINCREMENT,
          ts        INTEGER NOT NULL,
          rule      TEXT NOT NULL,
          file_type TEXT NOT NULL,
          outcome   TEXT NOT NULL CHECK (outcome IN ('fixed', 'stuck'))
        );
        CREATE INDEX IF NOT EXISTS idx_learnings_rule ON learnings(rule);
        CREATE INDEX IF NOT EXISTS idx_learnings_ts   ON learnings(ts);
      SQL
    end
  end
  end
  end
end
