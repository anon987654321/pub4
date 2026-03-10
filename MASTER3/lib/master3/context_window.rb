# frozen_string_literal: true

module Master3
  class ContextWindow
    COMPACT_THRESHOLD = 0.80

    def initialize(session:, agent: nil, model_context: 200_000)
      @session       = session
      @agent         = agent
      @model_context = model_context
    end

    def check_and_compact!
      return Result.ok(:ok) if @agent.nil?
      est = @session.token_est
      return Result.ok(:ok) if est < @model_context * COMPACT_THRESHOLD

      compact!
    end

    private

    def compact!
      summary = @agent.ask(
        "Summarize our progress, preserving all file paths, decisions, and remaining tasks.",
        context: @session.messages
      )
      @session.clear!
      @session.add_message(role: :assistant, content: "[Context compacted]\n\n#{summary}")
      Result.ok(:compacted)
    rescue => e
      Result.err("context compaction failed: #{e.message}", category: :infrastructure)
    end
  end
end
