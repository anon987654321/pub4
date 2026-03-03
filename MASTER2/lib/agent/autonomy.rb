# frozen_string_literal: true

module Agent
  module Autonomy
    module_function

    DEFAULT_AUTONOMY_LEVEL = 0
    MIN_AUTONOMY_LEVEL = 0
    MAX_AUTONOMY_LEVEL = 5

    RECENT_SESSION_LIMIT = 20
    SKILL_SUCCESS_WEIGHT = 1
    SKILL_FAILURE_WEIGHT = -2
    CONFIDENCE_FLOOR = 0.0
    CONFIDENCE_CEILING = 1.0

    TASK_PREFIX_START = 0
    TASK_PREFIX_LENGTH = 24
    TASK_TOKEN_SEPARATOR = /\s+/

    AUTONOMY_TRIGGERS = %w[
      run
      execute
      deploy
      delete
      drop
      migrate
      production
    ].freeze

    def autonomy_level(agent, context: {})
      return DEFAULT_AUTONOMY_LEVEL unless agent

      confidence = clamp_confidence(context.fetch(:confidence, nil))
      base_level = context.fetch(:base_level, DEFAULT_AUTONOMY_LEVEL)
      level = base_level + confidence_adjustment(confidence)

      risky = context.fetch(:risky, nil)
      risky = task_risky?(context.fetch(:task, "")) if risky.nil?

      level -= 1 if risky
      clamp_level(level)
    end

    def apply_learned_corrections(agent, task_text, corrections:)
      return task_text.to_s if task_text.to_s.empty?
      return task_text.to_s unless agent
      return task_text.to_s unless corrections.is_a?(Hash) && corrections.any?

      corrected_text = task_text.to_s.dup
      corrections.each do |pattern, replacement|
        corrected_text = corrected_text.gsub(pattern, replacement.to_s)
      rescue RegexpError
        next
      end

      corrected_text
    end

    def record_skill(agent, skill_name, outcome:, metadata: {})
      return nil unless agent
      return nil if skill_name.to_s.strip.empty?

      normalized_outcome = normalize_outcome(outcome)
      attributes = {
        name: skill_name.to_s,
        outcome: normalized_outcome,
        task_prefix: task_prefix(metadata.fetch(:task, "")),
        details: metadata.fetch(:details, {}),
        occurred_at: metadata.fetch(:occurred_at, Time.current)
      }

      persist_skill_record(agent, attributes)
    end

    def eligible_for_autonomy?(agent, task_text, context: {})
      return false unless agent
      return false if task_text.to_s.strip.empty?

      required_level = context.fetch(:required_level, DEFAULT_AUTONOMY_LEVEL)
      current_level = autonomy_level(agent, context: context.merge(task: task_text))

      current_level >= required_level
    end

    def recent_sessions(agent, limit: RECENT_SESSION_LIMIT)
      return [] unless agent
      return [] unless defined?(AgentSession)

      AgentSession
        .where(agent_id: agent.id)
        .includes(:skill_records)
        .order(created_at: :desc)
        .limit(limit)
    end

    private

    def confidence_adjustment(confidence)
      return 0 if confidence.nil?

      (confidence * MAX_AUTONOMY_LEVEL).round - 2
    end

    def clamp_level(level)
      [[level, MIN_AUTONOMY_LEVEL].max, MAX_AUTONOMY_LEVEL].min
    end

    def clamp_confidence(confidence)
      return nil if confidence.nil?

      numeric = Float(confidence)
      [[numeric, CONFIDENCE_FLOOR].max, CONFIDENCE_CEILING].min
    rescue ArgumentError, TypeError
      nil
    end

    def task_risky?(task_text)
      tokens = normalize_tokens(task_text)
      AUTONOMY_TRIGGERS.any? { |trigger| tokens.include?(trigger) }
    end

    def normalize_tokens(text)
      text.to_s.downcase.split(TASK_TOKEN_SEPARATOR).reject(&:empty?)
    end

    def task_prefix(task_text)
      task_text.to_s[TASK_PREFIX_START, TASK_PREFIX_LENGTH].to_s
    end

    def normalize_outcome(outcome)
      value = outcome.to_s.downcase
      return "success" if value == "success" || value == "ok" || value == "passed"
      return "failure" if value == "failure" || value == "fail" || value == "error"

      "unknown"
    end

    def persist_skill_record(agent, attributes)
      return nil unless agent.respond_to?(:skill_records)

      agent.skill_records.create!(attributes)
    rescue ActiveRecord::RecordInvalid
      nil
    end
  end
end