# frozen_string_literal: true

require "sqlite3"
require "json"

module Master
  module Ground
  # WAL-mode SQLite ledger for fix quality, strategy outcomes, and RSI feedback events.
    class KnowledgeStore
      include Master::Ground::Persistence::SqliteStore
      DEFAULT_PATH = ".master/knowledge.sqlite3"
      QUALITY_WINDOW_DAYS = 30
      RSI_WINDOW_DAYS = 7
      RSI_FAIL_THRESHOLD = 0.20
      RSI_CORRECTION_MIN = 3
      RSI_PROVIDER_MIN = 3

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

      def fix_quality(rule:, file_type: nil)
        cutoff = Time.now.to_i - QUALITY_WINDOW_DAYS * 86_400
        rows = fix_quality_rows(rule, file_type, cutoff)
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
        KnowledgeSchema::STATEMENTS.each { |statement| @db.execute_batch(statement) }
      end
    end
  end
end
