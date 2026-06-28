# frozen_string_literal: true

module Master
  module Ground
    module KnowledgeSchema
      STATEMENTS = [
        <<~SQL,
          CREATE TABLE IF NOT EXISTS fix_outcomes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            rule TEXT NOT NULL,
            file_type TEXT NOT NULL,
            outcome TEXT NOT NULL CHECK (outcome IN ('fixed', 'stuck'))
          );
          CREATE INDEX IF NOT EXISTS idx_fix_rule ON fix_outcomes(rule);
          CREATE INDEX IF NOT EXISTS idx_fix_ts ON fix_outcomes(ts);
        SQL
        <<~SQL,
          CREATE TABLE IF NOT EXISTS strategy_outcomes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            trigger TEXT NOT NULL,
            strategy TEXT NOT NULL,
            outcome TEXT NOT NULL,
            confidence REAL NOT NULL DEFAULT 0.5,
            reuse_count INTEGER NOT NULL DEFAULT 0,
            UNIQUE(trigger, strategy)
          );
          CREATE INDEX IF NOT EXISTS idx_strat_trigger ON strategy_outcomes(trigger);
        SQL
        <<~SQL,
          CREATE TABLE IF NOT EXISTS feedback_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            event_type TEXT NOT NULL,
            dimension TEXT NOT NULL,
            value TEXT,
            metadata TEXT
          );
          CREATE INDEX IF NOT EXISTS idx_fb_ts ON feedback_events(ts);
          CREATE INDEX IF NOT EXISTS idx_fb_dimension ON feedback_events(dimension);
        SQL
      ].freeze
    end
  end
end
