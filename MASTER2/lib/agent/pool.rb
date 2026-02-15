# frozen_string_literal: true

require "timeout"

module MASTER
  class AgentPool
    MAX_CONCURRENT = 4
    AGENT_TIMEOUT = 300

    attr_reader :agents

    def initialize(parent_budget:)
      @agents = []
      @parent_budget = parent_budget
      @mutex = Mutex.new
    end

    def spawn(task:, scope: "general", budget_fraction: 0.25, axiom_filter: nil, parent_id: nil)
      agent_budget = @parent_budget * budget_fraction

      agent = Agent.new(
        task: task,
        budget: agent_budget,
        scope: scope,
        axiom_filter: axiom_filter,
        parent_id: parent_id,
      )

      @mutex.synchronize { @agents << agent }
      agent
    end

    def run_all
      results = {}

      @agents.each_slice(MAX_CONCURRENT) do |batch|
        threads = batch.map do |agent|
          Thread.new do
            Timeout.timeout(AGENT_TIMEOUT) { agent.run }
          rescue Timeout::Error
            agent.instance_variable_set(:@status, :timeout)
            agent.instance_variable_set(
              :@result,
              Result.err("Agent #{agent.id} timed out after #{AGENT_TIMEOUT}s"),
            )
          end
        end

        threads.each(&:join)
      end

      @agents.each { |a| results[a.id] = a }
      results
    end

    def completed
      @agents.select { |a| a.status == :completed }
    end

    def failed
      @agents.reject { |a| a.status == :completed }
    end

    def total_budget_used
      @agents.sum(&:budget)
    end
  end
end
