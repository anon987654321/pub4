# frozen_string_literal: true

require_relative "../ground/redactor"

module Master
  module Io
    # LLM-callable tool; tools self-report outcomes so RSI reads the ledger.
    class FeedbackRecord
      TIER = :open
      NAME = "feedback_record".freeze
      DESCRIPTION = "Record a feedback event for RSI self-improvement. " \
                    "Call after tool success/failure or when user corrects output.".freeze

      VALID_EVENTS = %w[tool_success tool_failure user_correction provider_error user_feedback].freeze

      def initialize(learnings:)
        @learnings = learnings
      end

      def call(event_type:, dimension:, value: nil, metadata: nil)
        return Result.err("feedback_record: unknown event_type #{event_type}",
                          category: :validation) unless VALID_EVENTS.include?(event_type.to_s)
        dim_str = dimension.to_s.strip
        return Result.err("feedback_record: dimension required", category: :validation) if dim_str.empty?

        @learnings.record_event(
          event_type: event_type.to_s,
          dimension: dimension.to_s,
          value: value&.to_f,
          # Model-written, and it quoted users verbatim into a table nothing pruned.
          metadata: metadata && Master::Ground::Redactor.text(metadata.to_s).byteslice(0, 500).scrub(""),
        )
        Result.ok("recorded: #{event_type} / #{dimension}")
      rescue StandardError => e
        Result.err("feedback_record: #{e.message}", category: :unknown)
      end
    end
  end
end
