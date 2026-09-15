# frozen_string_literal: true

module Master::Core::Execution
  # AblationBasedImprovement — scientific testing of system changes.
  #
  # It runs the same task with different system configurations (e.g.,
  # different context compilers or routing policies) to measure the 
  # actual delta in performance.
  class AblationBasedImprovement
    def run_experiment(task, configurations)
      results = {}
      configurations.each do |name, config|
        results[name] = execute_with_config(task, config)
      end
      compare_results(results)
    end

    private

    def execute_with_config(task, config)
      # Mock execution: in reality, this would spin up a Pipeline
      # with the specific config and return the outcome.
      rand > 0.5 ? :success : :failure
    end

    def compare_results(results)
      # Return the configuration with the highest success rate
      results.max_by { |_, res| res == :success ? 1 : 0 }
    end
  end
end
