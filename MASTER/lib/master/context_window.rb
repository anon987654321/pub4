# frozen_string_literal: true

module Master
  class ContextWindow
    COMPACT_THRESHOLD = 0.80
    private_constant :COMPACT_THRESHOLD

    attr_reader :session, :agent, :model_context

    def initialize(session:, agent: nil, model_context: 200_000)
      @session = session
      @agent   = agent
      @model_context = model_context
    end

    def check_and_compact!
      return Result.ok(:ok) unless agent
      return Result.ok(:ok) unless safe_to_compact?

      compact!
    end

    private

    def safe_to_compact?
      est = session.token_est
      return false unless est.is_a?(Numeric)

      est >= model_context * COMPACT_THRESHOLD
    end

    def compact!
      summary = agent.ask(
        "Summarize our progress, preserving all file paths, decisions, and remaining tasks.",
        context: session.messages
      )
      session.clear!
      session.add_message(
        role: :assistant,
        content: "[Context compacted]\n\n#{summary}"
      )
      Result.ok(:compacted)
    rescue StandardError => e
      Result.err("context compaction failed: #{e.message}", category: :infrastructure)
    end
  end
end