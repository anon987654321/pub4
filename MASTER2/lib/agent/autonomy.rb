# frozen_string_literal: true

module Agent
  class Autonomy
    BLANK_STRINGS = [nil, "", " "].freeze

    def initialize(agent_scope: ::Agent, logger: nil)
      @agent_scope = agent_scope
      @logger = logger
    end

    def next_task_for(agent_id)
      agent = load_agent(agent_id)
      return nil unless agent

      open_tasks = agent.tasks.select { |t| t.status == "open" }
      open_tasks.min_by { |t| t.priority.to_i }
    end

    def train!(agent_id, skill_name:, task_text:)
      agent = load_agent(agent_id)
      return false unless agent
      return false if blank_string?(skill_name) || blank_string?(task_text)

      skill = agent.skills.find { |s| normalize(s.name) == normalize(skill_name) } ||
              agent.skills.build(name: skill_name.to_s.strip)

      task = agent.tasks.build(text: task_text.to_s.strip, status: "open", priority: 0)

      agent.transaction do
        skill.level = skill.level.to_i + 1
        skill.save!
        task.save!
      end

      true
    rescue ActiveRecord::RecordInvalid => e
      log_error(e)
      false
    end

    def eligible_skill?(agent_id, skill_name, min_level: 1)
      agent = load_agent(agent_id)
      return false unless agent
      return false if blank_string?(skill_name)

      skill = agent.skills.find { |s| normalize(s.name) == normalize(skill_name) }
      return false unless skill

      skill.level.to_i >= min_level.to_i
    end

    def parse_keywords(text)
      return [] if blank_string?(text)

      normalize_words(text)
    end

    private

    def load_agent(agent_id)
      return nil if agent_id.nil?

      @agent_scope
        .includes(:skills, :tasks)
        .find_by(id: agent_id)
    rescue ActiveRecord::StatementInvalid => e
      log_error(e)
      nil
    end

    def blank_string?(value)
      value = value.to_s
      value = value.strip unless value.empty?
      BLANK_STRINGS.include?(value) || value.empty?
    end

    def normalize(value)
      value.to_s.strip.downcase
    end

    def normalize_words(text)
      normalize(text).split(/[^\p{Alnum}_]+/).reject(&:empty?).uniq
    end

    def log_error(error)
      return unless @logger

      @logger.error(error)
    end
  end
end