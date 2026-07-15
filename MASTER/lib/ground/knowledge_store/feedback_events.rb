# frozen_string_literal: true

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
