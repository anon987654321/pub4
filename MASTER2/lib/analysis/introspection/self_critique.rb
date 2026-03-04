# frozen_string_literal: true

module Analysis
  module Introspection
    class SelfCritique
      DEFAULT_LIMIT = 50
      SCORE_THRESHOLD = 0.75

      UI_TITLE = "Self‑Critique"
      UI_EMPTY_STATE = "Nothing to review… yet."
      UI_ERROR = "We couldn’t load your self‑critique — please try again."

      def initialize(scope: nil, limit: DEFAULT_LIMIT)
        @scope = scope
        @limit = limit
      end

      def call(user:)
        return empty_result if user.nil?

        load_entries(user)
          .then { |entries| summarize(entries) }
          .then { |summary| format_result(summary) }
      rescue ActiveRecord::StatementInvalid => e
        error_result(e)
      end

      def eligible?(entry)
        return false if entry.nil?

        score = entry.score.to_f
        score >= SCORE_THRESHOLD && entry.active?
      end

      def title
        UI_TITLE
      end

      private

      attr_reader :scope, :limit

      def load_entries(user)
        base = scope || user.self_critique_entries

        base
          .includes(:analysis_result) # prevent N+1
          .order(created_at: :desc)
          .limit(limit)
          .to_a
      end

      def summarize(entries)
        eligible = entries.select { |e| eligible?(e) }

        {
          total: entries.size,
          eligible: eligible.size,
          recent: entries.first
        }
      end

      def format_result(summary)
        if summary[:total].zero?
          return {
            title: title,
            message: UI_EMPTY_STATE,
            summary: summary
          }
        end

        {
          title: title,
          message: "Review ready — you have #{summary[:eligible]} eligible item(s)…",
          summary: summary
        }
      end

      def empty_result
        {
          title: title,
          message: UI_EMPTY_STATE,
          summary: { total: 0, eligible: 0, recent: nil }
        }
      end

      def error_result(_error)
        {
          title: title,
          message: UI_ERROR,
          summary: { total: 0, eligible: 0, recent: nil }
        }
      end
    end
  end
end