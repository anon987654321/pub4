# frozen_string_literal: true

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
