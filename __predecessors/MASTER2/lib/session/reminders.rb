# frozen_string_literal: true

module MASTER
  class Session
    # Reminders — re-inject constitutional constraints mid-conversation
    # Prevents axiom drift in long sessions.
    # Pattern: Anthropic's Claude Sonnet 4.5 reminder mechanism (gistfile10 §3)
    module Reminders
      module_function

      REMINDER_INTERVAL = 8 # inject a reminder every N messages
      CRITICAL_AXIOMS = %w[
        FAIL_VISIBLY
        ONE_SOURCE
        SELF_APPLY
        PRESERVE_THEN_IMPROVE_NEVER_BREAK
        GUARD_EXPENSIVE
      ].freeze

      # Should a reminder be injected at this message count?
      def inject_reminder?(message_count)
        message_count > 0 && (message_count % REMINDER_INTERVAL).zero?
      end

      # Build the reminder text to prepend to the next system message.
      # @param context [Hash] keys: :count, :recent_violations, :budget_remaining
      def build_reminder(context = {})
        violations = context[:recent_violations] || []
        active_axioms = if violations.any?
                          violations.map { |v| v[:axiom] }.uniq.first(5)
                        else
                          CRITICAL_AXIOMS
                        end

        axiom_text = active_axioms.map { |a| "- #{a}" }.join("\n")
        budget_note = context[:budget_remaining] ? "Session budget remaining: #{context[:budget_remaining]}" : nil

        lines = [
          "[SYSTEM REMINDER — message #{context[:count]}]",
          "Active constitutional constraints:",
          axiom_text,
          "Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK",
        ]
        lines << budget_note if budget_note
        lines.join("\n")
      end
    end
  end
end
