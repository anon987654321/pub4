# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../../io/atomic_write"

module Master::Core::Routing
  # CapabilityMap — empirical model performance with an optional durable store.
  class CapabilityMap
    include Master::Io::AtomicWrite

    attr_reader :scores, :path

    def initialize(path: nil)
      @path = path
      @scores = load_scores
    end

    def record_outcome(model_id, task_class, success, metrics = {})
      @scores[model_id] ||= {}
      @scores[model_id][task_class] ||= { successes: 0, attempts: 0, metrics: {} }

      stats = @scores[model_id][task_class.to_s]
      stats[:attempts] += 1
      stats[:successes] += 1 if success

      metrics.each do |key, value|
        next unless value.is_a?(Numeric)

        previous = stats[:metrics][key] || 0.0
        attempts = stats[:attempts].to_f
        stats[:metrics][key] = ((previous * (attempts - 1)) + value.to_f) / attempts
      end

      persist
    end

    def success_rate(model_id, task_class)
      stats = @scores.dig(model_id, task_class.to_s)
      return 0.0 unless stats
      return 0.0 if stats[:attempts].to_i.zero?

      stats[:successes].to_f / stats[:attempts].to_i
    end

    def best_model_for(task_class, _constraints = {})
      @scores.each_with_object({ best: nil, rate: -1.0 }) do |(model_id, tasks), result|
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

    private

    def load_scores
      return {} unless @path && File.file?(@path)

      raw = JSON.parse(File.read(@path))
      normalize(raw)
    rescue JSON::ParserError, SystemCallError, TypeError => e
      Master::Ground::Swallow.log(e, context: "CapabilityMap.load_scores", path: @path)
      {}
    end

    def normalize(raw)
      raw.each_with_object({}) do |(model, tasks), scores|
        scores[model] = tasks.each_with_object({}) do |(task, stats), task_scores|
          task_scores[task] = {
            successes: stats["successes"].to_i,
            attempts: stats["attempts"].to_i,
            metrics: stats["metrics"].is_a?(Hash) ? stats["metrics"] : {}
          }
        end
      end
    end

    def persist
      return unless @path

      write_atomic(@path, JSON.pretty_generate(@scores) + "\n")
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "CapabilityMap.persist", path: @path)
      nil
    end
  end
end
