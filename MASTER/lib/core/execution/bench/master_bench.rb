# frozen_string_literal: true

module Master::Core::Execution
  # MasterBench — the system certification suite.
  #
  # A set of validated cases with an Oracle policy that determines
  # not just if the result is correct, but if the process was optimal.
  class MasterBench
    attr_reader :cases

    def initialize
      @cases = [] # [ { task: "...", oracle: ->(res) { ... } } ]
    end


    def add_case(task, oracle)
      @cases << { task: task, oracle: oracle }
    end

    def run_all(pipeline)
      results = @cases.map do |c|
        outcome = pipeline.run(c[:task])
        { task: c[:task], score: c[:oracle].call(outcome) }
      end
      calculate_aggregate(results)
    end

    private

    def calculate_aggregate(results)
      scores = results.map { |r| r[:score] }
      {
        mean: scores.sum / scores.size.to_f,
        pass_rate: scores.count { |s| s == 1.0 } / scores.size.to_f
      }
    end
  end
end
