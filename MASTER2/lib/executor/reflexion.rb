# frozen_string_literal: true

module Executor
  class Reflexion
    MAX_REACT_ITERATIONS = 3
    MODEL_TEMPERATURE = 0.2

    def initialize(run_id:, actor:)
      @run = ReflexionRun
             .includes(:conversation, :agent, messages: :tool_calls)
             .find(run_id)
      @actor = actor
    end

    def execute_reflexion
      enforce_executable!

      plan = build_reflexion_plan
      return plan if plan.complete?

      execute_react_inner(plan)
    end

    private

    def enforce_executable!
      raise Reflexion::NotExecutableError, "run already completed" if @run.completed?
      raise Reflexion::NotExecutableError, "conversation missing" if @run.conversation.nil?
    end

    def build_reflexion_plan
      Planner.new(run: @run, actor: @actor).build
    end

    def execute_react_inner(plan)
      iterations = 0

      while iterations < MAX_REACT_ITERATIONS && !plan.complete?
        action = plan.next_action
        break unless action

        perform_plan_action(action)
        plan = build_reflexion_plan
        iterations += 1
      end

      plan
    end

    def perform_plan_action(action)
      case action.type
      when :tool
        ToolRunner.new(run: @run, action: action, actor: @actor).run
      when :message
        MessageRunner.new(
          run: @run,
          action: action,
          actor: @actor,
          temperature: MODEL_TEMPERATURE
        ).run
      else
        raise ArgumentError, "unknown action type: #{action.type.inspect}"
      end
    end
  end
end