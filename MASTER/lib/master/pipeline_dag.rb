# frozen_string_literal: true

module Master
  # Reads data/pipeline.yml and runs stages whose deps are satisfied in parallel.
  # Drop-in replacement for the linear Pipeline. Stages still return Result monads;
  # an Err short-circuits all downstream work, same as the linear version.
  class PipelineDag
    DAG_PATH = File.join(Master::ROOT, "data", "pipeline.yml").freeze

    def initialize(stages:, event_bus: nil)
      @stages = stages.transform_keys(&:to_s)
      @bus    = event_bus
      @plan   = load_plan
    end

    def call(initial_result)
      ctx       = initial_result
      completed = {}
      remaining = @plan.dup

      until remaining.empty?
        ready = remaining.select { |s| s["deps"].all? { |d| completed.key?(d) } }
        break if ready.empty?
        results = run_parallel(ready, ctx)
        results.each do |name, result|
          completed[name] = result
          return result if result.respond_to?(:err?) && result.err?
          ctx = result if result.respond_to?(:value)
        end
        remaining -= ready
      end

      ctx
    end

    private

    def load_plan
      Master.load_yaml(DAG_PATH) || []
    rescue StandardError
      []
    end

    def run_parallel(stages, ctx)
      threads = stages.map do |stage|
        Thread.new do
          klass = @stages[stage["name"]]
          next [stage["name"], ctx] unless klass
          [stage["name"], klass.call(ctx)]
        end
      end
      threads.map(&:value).to_h
    end
  end
end
