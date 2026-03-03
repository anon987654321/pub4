# frozen_string_literal: true

%w[
  agent/configuration
  agent/task_registry
  agent/execution_result
].each { |path| require_relative path }

module Agent
  class Runner
    def initialize(configuration: Configuration.new, task_registry: TaskRegistry.new)
      @configuration = configuration
      @task_registry = task_registry
    end

    def execute(task_name:, payload:, context: nil, options: {})
      task = @task_registry.fetch(task_name)

      task.execute(
        payload: payload,
        context: context,
        options: options,
        configuration: @configuration
      )
    rescue TaskRegistry::UnknownTaskError => error
      ExecutionResult.failure(code: :unknown_task, message: error.message)
    rescue StandardError => error
      ExecutionResult.failure(code: :execution_error, message: error.message)
    end

    private

    attr_reader :configuration
  end
end