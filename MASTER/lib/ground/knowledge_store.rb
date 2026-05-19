# frozen_string_literal: true

require "sqlite3"
require "json"

module Master
  module Ground
  # Unified knowledge ledger — consolidates fix quality (arch #10), strategy
  # outcomes, and RSI feedback events into one WAL-mode SQLite database.
  #
  # Replaces the split Ground::Learnings (JSONL) + Persistence::SqliteLearnings (SQLite).
  # Single-object `learnings:` kwarg serves the RuleLoop caller path:
  #   record(trigger:, strategy:, outcome:)  → strategy_outcomes table
  #   record(rule:, file_type:, outcome:)    → fix_outcomes table
  class KnowledgeStore
    include Master::Ground::Persistence::SqliteStore
    DEFAULT_PATH        = ".master/knowledge.sqlite3"
    QUALITY_WINDOW_DAYS = 30
    RSI_WINDOW_DAYS     = 7
    RSI_FAIL_THRESHOLD  = 0.20
    RSI_CORRECTION_MIN  = 3
    RSI_PROVIDER_MIN    = 3

    def initialize(root:)
      @db = open_db(root)
      @db.results_as_hash = true
      ensure_schema
    end

    # Unified dispatch — keyword args determine which table is written.
    def record(trigger: nil, strategy: nil, rule: nil, file_type: nil, outcome:)
      if rule
        record_fix(rule: rule, file_type: file_type, outcome: outcome)
      elsif trigger
        record_strategy(trigger: trigger, strategy: strategy || "unknown", outcome: outcome)
      end
    end

    # Fix quality tracking (arch #10) — outcome: :fixed | :stuck
    def record_fix(rule:, file_type:, outcome:)
      @db.execute(
        "INSERT INTO fix_outcomes (ts, rule, file_type, outcome) VALUES (?, ?, ?, ?)",
        [Time.now.to_i, rule.to_s, file_type.to_s, outcome.to_s]
      )
    rescue SQLite3::Exception => e
      warn "knowledge_store: #{e.message}"
    end

    # Fix quality score 0.0–1.0 for a rule. Default 0.5 when no data.
    def fix_quality(rule:, file_type: nil)
      cutoff = Time.now.to_i - QUALITY_WINDOW_DAYS * 86_400
      rows = if file_type
        @db.execute(
          "SELECT outcome, COUNT(*) AS n FROM fix_outcomes WHERE rule = ? AND file_type = ? AND ts >= ? GROUP BY outcome",
          [rule.to_s, file_type.to_s, cutoff]
        )
      else
        @db.execute(
          "SELECT outcome, COUNT(*) AS n FROM fix_outcomes WHERE rule = ? AND ts >= ? GROUP BY outcome",
          [rule.to_s, cutoff]
        )
      end
      tally = rows.each_with_object(Hash.new(0)) { |r, h| h[r["outcome"]] = r["n"].to_i }
      total = tally.values.sum
      return 0.5 if total.zero?
      tally["fixed"].to_f / total
    end

    def top_rules(limit: 20, min_attempts: 3)
      cutoff = Time.now.to_i - QUALITY_WINDOW_DAYS * 86_400
      @db.execute(<<~SQL, [cutoff, min_attempts, limit])
        SELECT rule,
               SUM(CASE WHEN outcome = 'fixed' THEN 1 ELSE 0 END) AS fixed,
               COUNT(*) AS total,
               CAST(SUM(CASE WHEN outcome = 'fixed' THEN 1 ELSE 0 END) AS REAL) / COUNT(*) AS quality
        FROM fix_outcomes WHERE ts >= ?
        GROUP BY rule HAVING total >= ?
        ORDER BY quality DESC LIMIT ?
      SQL
    end

    # Strategy outcome tracking — autoloop fix records
    def record_strategy(trigger:, strategy:, outcome:)
      ts = Time.now.to_i
      existing = @db.execute(
        "SELECT id, reuse_count, confidence FROM strategy_outcomes WHERE trigger = ? AND strategy = ?",
        [trigger.to_s, strategy.to_s]
      ).first
      if existing
        new_confidence = [existing["confidence"].to_f + 0.05, 1.0].min
        @db.execute(
          "UPDATE strategy_outcomes SET reuse_count = reuse_count + 1, confidence = ?, outcome = ?, ts = ? WHERE id = ?",
          [new_confidence, outcome.to_s, ts, existing["id"]]
        )
      else
        confidence = outcome.to_s == "fixed" ? 0.7 : 0.4
        @db.execute(
          "INSERT INTO strategy_outcomes (ts, trigger, strategy, outcome, confidence, reuse_count) VALUES (?, ?, ?, ?, ?, 0)",
          [ts, trigger.to_s, strategy.to_s, outcome.to_s, confidence]
        )
      end
    rescue SQLite3::Exception => e
      warn "knowledge_store: #{e.message}"
    end

    def search(trigger_fragment, limit: 3)
      fragment = "%#{trigger_fragment.to_s.downcase}%"
      @db.execute(
        "SELECT trigger, strategy, outcome, confidence FROM strategy_outcomes WHERE LOWER(trigger) LIKE ? AND outcome != 'failed' ORDER BY confidence DESC LIMIT ?",
        [fragment, limit]
      )
    end

    # RSI feedback events — dimensional statistics for opportunity detection
    def record_event(event_type:, dimension:, value: nil, metadata: nil)
      @db.execute(
        "INSERT INTO feedback_events (ts, event_type, dimension, value, metadata) VALUES (?, ?, ?, ?, ?)",
        [Time.now.to_i, event_type.to_s, dimension.to_s, value&.to_s, metadata&.to_json]
      )
    rescue SQLite3::Exception => e
      warn "knowledge_store: #{e.message}"
    end

    def opportunities
      cutoff = Time.now.to_i - RSI_WINDOW_DAYS * 86_400
      recent = @db.execute("SELECT event_type, dimension FROM feedback_events WHERE ts >= ?", [cutoff])

      tool_stats = recent.select { |r| %w[tool_success tool_failure].include?(r["event_type"]) }
                         .group_by { |r| r["dimension"] }
                         .filter_map { |tool, evs|
        success = evs.count { |e| e["event_type"] == "tool_success" }
        failure = evs.count { |e| e["event_type"] == "tool_failure" }
        total   = success + failure
        rate    = total.zero? ? 0.0 : failure.to_f / total
        { category: :high_failure, dimension: tool, fail_rate: rate.round(3), total: } if rate >= RSI_FAIL_THRESHOLD && total >= 3
      }

      corrections = recent.select { |r| r["event_type"] == "user_correction" }
                          .group_by { |r| r["dimension"] }
                          .filter_map { |dim, evs|
        { category: :repeated_correction, dimension: dim, count: evs.size } if evs.size >= RSI_CORRECTION_MIN
      }

      provider_errs = recent.select { |r| r["event_type"] == "provider_error" }
                            .group_by { |r| r["dimension"] }
                            .filter_map { |dim, evs|
        { category: :provider_errors, dimension: dim, count: evs.size } if evs.size >= RSI_PROVIDER_MIN
      }

      tool_stats + corrections + provider_errs
    end

    def close
      @db&.close
    end

    private

    def open_db(root)
      open_sqlite(root, DEFAULT_PATH)
    end

    def ensure_schema
      @db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS fix_outcomes (
          id        INTEGER PRIMARY KEY AUTOINCREMENT,
          ts        INTEGER NOT NULL,
          rule      TEXT NOT NULL,
          file_type TEXT NOT NULL,
          outcome   TEXT NOT NULL CHECK (outcome IN ('fixed', 'stuck'))
        );
        CREATE INDEX IF NOT EXISTS idx_fix_rule ON fix_outcomes(rule);
        CREATE INDEX IF NOT EXISTS idx_fix_ts   ON fix_outcomes(ts);

        CREATE TABLE IF NOT EXISTS strategy_outcomes (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          ts          INTEGER NOT NULL,
          trigger     TEXT NOT NULL,
          strategy    TEXT NOT NULL,
          outcome     TEXT NOT NULL,
          confidence  REAL NOT NULL DEFAULT 0.5,
          reuse_count INTEGER NOT NULL DEFAULT 0,
          UNIQUE(trigger, strategy)
        );
        CREATE INDEX IF NOT EXISTS idx_strat_trigger ON strategy_outcomes(trigger);

        CREATE TABLE IF NOT EXISTS feedback_events (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          ts         INTEGER NOT NULL,
          event_type TEXT NOT NULL,
          dimension  TEXT NOT NULL,
          value      TEXT,
          metadata   TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_fb_ts        ON feedback_events(ts);
        CREATE INDEX IF NOT EXISTS idx_fb_dimension ON feedback_events(dimension);
      SQL
    end
  end
  end
end
