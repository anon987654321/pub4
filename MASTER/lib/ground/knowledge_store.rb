# frozen_string_literal: true

require "sqlite3"
require "json"

module Master
  module Ground
    class KnowledgeStore
      # Feedback-event storage and RSI opportunity detection — separate from
      # KnowledgeStore's fix-outcome and strategy-reuse concerns.
      module FeedbackEvents
        def record_event(event_type:, dimension:, value: nil, metadata: nil)
          @db.execute(
            "INSERT INTO feedback_events (ts, event_type, dimension, value, metadata) VALUES (?, ?, ?, ?, ?)",
            [Time.now.to_i, event_type.to_s, dimension.to_s, value&.to_s, encoded_metadata(metadata)],
          )
        rescue SQLite3::Exception => e
          warn "knowledge_store: #{e.message}"
        end

        def provider_errors(model: nil, limit: 20)
          where, args = provider_errors_query(model, limit)
          @db.execute(<<~SQL, args).map { |row| provider_error_row(row) }
            SELECT ts, dimension, value, metadata
            FROM feedback_events
            WHERE #{where.join(" AND ")}
            ORDER BY ts DESC, id DESC
            LIMIT ?
          SQL
        end

        def opportunities
          cutoff = Time.now.to_i - RSI_WINDOW_DAYS * 86_400
          recent = @db.execute("SELECT event_type, dimension FROM feedback_events WHERE ts >= ?", [cutoff])
          tool_failure_opportunities(recent) +
            event_count_opportunities(recent, "user_correction", :repeated_correction, RSI_CORRECTION_MIN) +
            event_count_opportunities(recent, "provider_error", :provider_errors, RSI_PROVIDER_MIN)
        end
      end
    end
  end
end
module Master
  module Ground
    class KnowledgeStore
      # Strategy-reuse tracking (trigger -> strategy -> outcome/confidence) —
      # separate from KnowledgeStore's fix-outcome and feedback-event concerns.
      module StrategyOutcomes
        def record_strategy(trigger:, strategy:, outcome:)
          ts = Time.now.to_i
          existing = existing_strategy(trigger, strategy)
          existing ? update_strategy(existing, outcome, ts) : insert_strategy(trigger, strategy, outcome, ts)
        rescue SQLite3::Exception => e
          warn "knowledge_store: #{e.message}"
        end

        def search(trigger_fragment, limit: 3)
          fragment = "%#{trigger_fragment.to_s.downcase}%"
          @db.execute(<<~SQL, [fragment, limit])
          SELECT trigger, strategy, outcome, confidence
          FROM strategy_outcomes
          WHERE LOWER(trigger) LIKE ? AND outcome != 'failed'
          ORDER BY confidence DESC LIMIT ?
        SQL
        end
      end
    end
  end
end

module Master
  module Ground
  # WAL-mode SQLite ledger for fix quality, strategy outcomes, and RSI feedback events.
    class KnowledgeStore
      include Master::Ground::SqliteStore
      include StrategyOutcomes
      include FeedbackEvents

      DEFAULT_PATH = ".master/knowledge.sqlite3"
      QUALITY_WINDOW_DAYS = 30
      RSI_WINDOW_DAYS = 7
      RSI_FAIL_THRESHOLD = 0.20
      RSI_CORRECTION_MIN = 3
      RSI_PROVIDER_MIN = 3

      # The three tables this store owns, in `ensure_schema` order. The first
      # entry is also replayed on its own by the fix_outcomes rebuild below,
      # so keep fix_outcomes first.
      SCHEMA_STATEMENTS = [
        <<~SQL,
          CREATE TABLE IF NOT EXISTS fix_outcomes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            rule TEXT NOT NULL,
            file_type TEXT NOT NULL,
            outcome TEXT NOT NULL CHECK (outcome IN ('fixed', 'stuck', 'skipped'))
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
      private_constant :SCHEMA_STATEMENTS

      def initialize(root:)
        @db = open_db(root)
        @db.results_as_hash = true
        ensure_schema
      end

      def record(trigger: nil, strategy: nil, rule: nil, file_type: nil, outcome:)
        if rule
          record_fix(rule:, file_type:, outcome:)
        elsif trigger
          record_strategy(trigger:, strategy: strategy || "unknown", outcome:)
        end
      end

      def record_fix(rule:, file_type:, outcome:)
        @db.execute(
          "INSERT INTO fix_outcomes (ts, rule, file_type, outcome) VALUES (?, ?, ?, ?)",
          [Time.now.to_i, rule.to_s, file_type.to_s, outcome.to_s],
        )
      rescue SQLite3::Exception => e
        warn "knowledge_store: #{e.message}"
      end

      # A violation the rule never actually attempted (confidence gate,
      # stale fingerprint) is recorded as 'skipped' and excluded here --
      # only genuine attempt outcomes ('fixed'/'stuck') count toward
      # quality. See fix_batch's comment in rule_loop.rb for why: counting
      # policy skips as failures deprioritizes a rule further every time
      # it's skipped, without it ever having actually failed a fix.
      def fix_quality(rule:, file_type: nil)
        cutoff = Time.now.to_i - QUALITY_WINDOW_DAYS * 86_400
        rows = fix_quality_rows(rule, file_type, cutoff)
        tally = rows.each_with_object(Hash.new(0)) { |r, h| h[r["outcome"]] = r["n"].to_i }
        total = tally["fixed"] + tally["stuck"]
        return 0.5 if total.zero?

        tally["fixed"].to_f / total
      end

      def top_rules(limit: 20, min_attempts: 3)
        cutoff = Time.now.to_i - QUALITY_WINDOW_DAYS * 86_400
        @db.execute(<<~SQL, [cutoff, min_attempts, limit])
        SELECT rule,
               SUM(CASE WHEN outcome = 'fixed' THEN 1 ELSE 0 END) AS fixed,
               SUM(CASE WHEN outcome IN ('fixed', 'stuck') THEN 1 ELSE 0 END) AS total,
               CAST(SUM(CASE WHEN outcome = 'fixed' THEN 1 ELSE 0 END) AS REAL)
                 / NULLIF(SUM(CASE WHEN outcome IN ('fixed', 'stuck') THEN 1 ELSE 0 END), 0) AS quality
        FROM fix_outcomes WHERE ts >= ?
        GROUP BY rule HAVING total >= ?
        ORDER BY quality DESC LIMIT ?
      SQL
      end

      def close
        @db&.close
      end

      private

      def provider_errors_query(model, limit)
        args = ["provider_error"]
        where = ["event_type = ?"]
        if model
          where << "dimension = ?"
          args << model.to_s
        end
        args << limit
        [where, args]
      end

      def provider_error_row(row)
        {
          ts: row["ts"].to_i,
          model: row["dimension"],
          status: row["value"],
          metadata: decoded_metadata(row["metadata"]),
        }
      end

      def fix_quality_rows(rule, file_type, cutoff)
        if file_type
          sql = "SELECT outcome, COUNT(*) AS n FROM fix_outcomes " \
                "WHERE rule = ? AND file_type = ? AND ts >= ? GROUP BY outcome"
          return @db.execute(sql, [rule.to_s, file_type.to_s, cutoff])
        end

        sql = "SELECT outcome, COUNT(*) AS n FROM fix_outcomes WHERE rule = ? AND ts >= ? GROUP BY outcome"
        @db.execute(sql, [rule.to_s, cutoff])
      end

      def existing_strategy(trigger, strategy)
        sql = "SELECT id, reuse_count, confidence FROM strategy_outcomes WHERE trigger = ? AND strategy = ?"
        @db.execute(sql, [trigger.to_s, strategy.to_s]).first
      end

      def update_strategy(existing, outcome, timestamp)
        confidence = [existing["confidence"].to_f + 0.05, 1.0].min
        sql = "UPDATE strategy_outcomes SET reuse_count = reuse_count + 1, " \
              "confidence = ?, outcome = ?, ts = ? WHERE id = ?"
        @db.execute(sql, [confidence, outcome.to_s, timestamp, existing["id"]])
      end

      def insert_strategy(trigger, strategy, outcome, timestamp)
        confidence = outcome.to_s == "fixed" ? 0.7 : 0.4
        sql = "INSERT INTO strategy_outcomes " \
              "(ts, trigger, strategy, outcome, confidence, reuse_count) VALUES (?, ?, ?, ?, ?, 0)"
        @db.execute(sql, [timestamp, trigger.to_s, strategy.to_s, outcome.to_s, confidence])
      end

      def tool_failure_opportunities(events)
        grouped_events(events, %w[tool_success tool_failure]).filter_map do |tool, rows|
          total = rows.size
          failures = rows.count { |row| row["event_type"] == "tool_failure" }
          rate = total.zero? ? 0.0 : failures.to_f / total
          next unless rate >= RSI_FAIL_THRESHOLD && total >= 3

          { category: :high_failure, dimension: tool, fail_rate: rate.round(3), total: }
        end
      end

      def event_count_opportunities(events, type, category, minimum)
        grouped_events(events, [type]).filter_map do |dimension, rows|
          { category:, dimension:, count: rows.size } if rows.size >= minimum
        end
      end

      def grouped_events(events, types)
        events.select { |row| types.include?(row["event_type"]) }.group_by { |row| row["dimension"] }
      end

      def open_db(root)
        open_sqlite(root, DEFAULT_PATH)
      end

      def encoded_metadata(metadata)
        return if metadata.nil?
        return metadata if metadata.is_a?(String)

        metadata.to_json
      end

      def decoded_metadata(raw)
        return {} if raw.to_s.empty?

        decoded = JSON.parse(raw)
        decoded.is_a?(String) ? JSON.parse(decoded) : decoded
      rescue JSON::ParserError
        { "raw" => raw.to_s }
      end

      def ensure_schema
        migrate_fix_outcomes_skipped_value!
        SCHEMA_STATEMENTS.each { |statement| @db.execute_batch(statement) }
      end

      # fix_outcomes' CHECK constraint originally only allowed ('fixed',
      # 'stuck') -- SQLite can't ALTER a CHECK constraint in place, so an
      # existing DB from before 'skipped' was added needs its table rebuilt.
      # CREATE TABLE IF NOT EXISTS alone would silently leave old databases
      # on the old constraint forever, rejecting every 'skipped' insert.
      def migrate_fix_outcomes_skipped_value!
        row = @db.execute(
          "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'fix_outcomes'",
        ).first
        return unless row
        return if row["sql"].to_s.include?("skipped")

        @db.execute_batch(<<~SQL)
          ALTER TABLE fix_outcomes RENAME TO fix_outcomes_pre_skipped;
        SQL
        SCHEMA_STATEMENTS.first.then { |statement| @db.execute_batch(statement) }
        @db.execute_batch(<<~SQL)
          INSERT INTO fix_outcomes (id, ts, rule, file_type, outcome)
            SELECT id, ts, rule, file_type, outcome FROM fix_outcomes_pre_skipped;
          DROP TABLE fix_outcomes_pre_skipped;
        SQL
      rescue SQLite3::Exception => e
        warn "knowledge_store: fix_outcomes migration failed — #{e.message}"
      end
    end
  end
end
