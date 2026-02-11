# frozen_string_literal: true

require "securerandom"

module MASTER
  class Agent
    attr_reader :id, :parent_id, :scope, :task, :budget, :axiom_filter, :status, :result

    def initialize(task:, budget:, scope: "general", axiom_filter: nil, parent_id: nil)
      @id = SecureRandom.hex(8)
      @parent_id = parent_id || "root"
      @scope = scope
      @task = task
      @budget = budget
      @axiom_filter = axiom_filter
      @status = :pending
      @result = nil
      @started_at = nil
      @finished_at = nil
    end

    def user_agent
      axiom_count = DB.axioms.size
      "MASTER/#{VERSION} (agent:#{@id}; parent:#{@parent_id}; scope:#{@scope}; " \
        "axioms:#{axiom_count}; budget:$#{format('%.2f', @budget)})"
    end

    def run
      @status = :running
      @started_at = Time.now

      puts "agent0 at master0: #{@id} (parent:#{@parent_id}, scope:#{@scope}, " \
           "budget:$#{format('%.2f', @budget)})"

      pipeline = Pipeline.new
      @result = pipeline.call(@task)

      @status = @result.ok? ? :completed : :failed
      @finished_at = Time.now

      @result
    end

    def elapsed
      return nil unless @started_at

      (@finished_at || Time.now) - @started_at
    end

    def to_h
      {
        id: @id,
        parent_id: @parent_id,
        scope: @scope,
        status: @status,
        elapsed: elapsed,
        budget: @budget,
        user_agent: user_agent,
      }
    end
  end
end
