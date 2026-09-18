# frozen_string_literal: true

module Master::Core::Routing
  # CapabilityMap — an empirical database of model performance.
  #
  # Instead of trusting marketing benchmarks, MASTER records verified
  # outcomes to build a local mapping of model identity to actual
  # capability across different task classes.
  class CapabilityMap
    attr_reader :scores

    def initialize
      @scores = {} # { model_id => { task_class => { success_rate: 0.0, ... } } }
    end

    # Record a verified outcome for a specific model and task.
    def record_outcome(model_id, task_class, success, metrics = {})
      @scores[model_id] ||= {}
      @scores[model_id][task_class] ||= { successes: 0, attempts: 0, metrics: {} }

      stats = @scores[model_id][task_class]
      stats[:attempts] += 1
      stats[:successes] += 1 if success

      # Update average metrics (latency, cost, etc.)
      metrics.each do |k, v|
        stats[:metrics][k] = (stats[:metrics][k] || 0) * (stats[:attempts] - 1) / stats[:attempts] + v / stats[:attempts]
      end
    end

    def success_rate(model_id, task_class)
      stats = @scores.dig(model_id, task_class)
      return 0.0 unless stats
      stats[:successes].to_f / stats[:attempts]
    end

    def best_model_for(task_class, _constraints = {})
      # Simple empirical selection: highest success rate
      @scores.each_with_object({best: nil, rate: -1.0}) do |(model_id, tasks), result|
        rate = success_rate(model_id, task_class)
        if rate > result[:rate]
          result[:best] = model_id
          result[:rate] = rate
        end
      end[:best]
    end

    def to_h
      @scores
    end
  end
end
