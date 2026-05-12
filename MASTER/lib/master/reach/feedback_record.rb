# frozen_string_literal: true

module Master
  module Reach
    # FeedbackRecord — LLM-callable tool to record RSI feedback events.
    # Event types: tool_success, tool_failure, user_correction, provider_error, user_feedback.
    # Dimension: tool name, provider name, or pattern label.
    # Pattern from OpenCrabs: tools self-report outcomes; RSI reads the ledger.
    class FeedbackRecord
      TIER        = :open
      NAME        = "feedback_record".freeze
      DESCRIPTION = "Record a feedback event for RSI self-improvement. " \
                    "Call after tool success/failure or when user corrects output.".freeze

      VALID_EVENTS = %w[tool_success tool_failure user_correction provider_error user_feedback].freeze

      def initialize(learnings:)
        @learnings = learnings
      end

      def call(event_type:, dimension:, value: nil, metadata: nil)
        return Result.err("feedback_record: unknown event_type #{event_type}", 
category: :validation) unless VALID_EVENTS.include?(event_type.to_s)
        return Result.err("feedback_record: dimension required", category: :validation) if dimension.to_s.strip.empty?

        @learnings.record_event(
          event_type: event_type.to_s,
          dimension:  dimension.to_s,
          value:      value&.to_f,
          metadata:   metadata&.to_s
        )
        Result.ok("recorded: #{event_type} / #{dimension}")
      rescue StandardError => e
        Result.err("feedback_record: #{e.message}", category: :unknown)
      end
    end
  end
end
