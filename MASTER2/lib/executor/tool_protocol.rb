# frozen_string_literal: true

module Executor
  class ToolProtocol
    FAIL_VISIBLY = "FAIL_VISIBLY"

    ALLOWED_STATUSES = %i[success error timeout].freeze

    def initialize(execution:)
      @execution = execution
    end

    def tool_runs
      @tool_runs ||= execution
        .tool_runs
        .includes(:tool)
        .order(:created_at)
    end

    def fail_visibly_payload(message: nil)
      {
        status: FAIL_VISIBLY,
        message: message
      }.compact
    end

    def normalize_status(status)
      return status if ALLOWED_STATUSES.include?(status)

      FAIL_VISIBLY
    end

    private

    attr_reader :execution
  end
end