# frozen_string_literal: true

require "json"

module Master::CLI::Routing
  # CapabilityMap — empirical model performance with an optional durable store.
  #
  # The store is written by the caller's `write`, (path, content) -> any: the
  # fold spine requires nothing from the rest of lib/, so the atomic writer
  # arrives from outside. Without one the map
  # reads its file and keeps what it learns in memory.
  class CapabilityMap
    MIN_SAMPLES = 3

    attr_reader :scores, :path

    def initialize(path: nil, write: nil)
      @path = path
      @write = write
      @scores = load_scores
    end

    def record_outcome(model_id, task_class, success, metrics = {})
      @scores[model_id] ||= {}
      @scores[model_id][task_class.to_s] ||= { successes: 0, attempts: 0, metrics: {} }

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

    def confidence(model_id, task_class, min_samples: MIN_SAMPLES)
      attempts = @scores.dig(model_id, task_class.to_s, :attempts).to_i
      return 0.0 if attempts.zero?

      [attempts.fdiv([min_samples.to_i, 1].max), 1.0].min
    end

    def score_for(model_id, task_class, min_samples: MIN_SAMPLES)
      rate = success_rate(model_id, task_class)
      confidence = confidence(model_id, task_class, min_samples:)
      0.5 + ((rate - 0.5) * confidence)
    end

    def best_model_for(task_class, _constraints = {})
      @scores.each_with_object({ best: nil, score: -1.0 }) do |(model_id, tasks), result|
        next unless tasks[task_class.to_s].to_h.fetch(:attempts, 0).to_i >= MIN_SAMPLES

        score = score_for(model_id, task_class)
        if score > result[:score]
          result[:best] = model_id
          result[:score] = score
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
            metrics: stats["metrics"].is_a?(Hash) ? stats["metrics"] : {},
          }
        end
      end
    end

    def persist
      return unless @path && @write

      @write.call(@path, JSON.pretty_generate(@scores) + "\n")
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "CapabilityMap.persist", path: @path)
      nil
    end
  end
end
