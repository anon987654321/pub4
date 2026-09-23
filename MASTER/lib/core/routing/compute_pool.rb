# frozen_string_literal: true

module Master
  module Core
    module Routing
      # Live compute economics for model selection.
      #
      # MASTER owns the decision; providers only expose compute. Static model
      # scores remain the baseline while observed outcomes continuously adjust
      # quality and latency. Free/local lanes are not hard-coded winners: they
      # win when their measured utility is actually better.
      class ComputePool
        Candidate = Struct.new(:id, :quality, :speed, :cost, :context_window,
          :availability, :tool_support, :success_rate, :latency_factor, :score,
          keyword_init: true)

        DEFAULTS = {
          quality: 0.5,
          speed: 0.5,
          cost: 0.5,
          context_window: 128_000,
          availability: 1.0,
          tool_support: 0.5,
        }.freeze

        def initialize(router:, root: Master::ROOT)
          @router = router
          @root = root
          @rules = load_rules
          @stats = load_stats
          @mutex = Mutex.new
        end

        def rank(ids, task_type: :exploration, empirical_best: nil)
          candidates = Array(ids).filter_map { |id| candidate(id) }
          candidates.sort_by { |entry| [-utility(entry, task_type:, empirical_best:), entry.id] }
            .map(&:id)
        end

        def select(ids, task_type: :exploration, empirical_best: nil)
          rank(ids, task_type:, empirical_best:).first
        end

        def record(model:, status:, latency_ms: nil, error: nil)
          key = model.to_s
          return if key.empty?

          @mutex.synchronize do
            stat = (@stats[key] ||= { calls: 0, successes: 0, failures: 0, latency_ms: 0.0, last_error: nil })
            stat[:calls] += 1
            if status.to_sym == :success
              stat[:successes] += 1
              stat[:latency_ms] = rolling_average(stat[:latency_ms], latency_ms.to_f, stat[:successes])
            else
              stat[:failures] += 1
              stat[:last_error] = error.to_s unless error.to_s.empty?
            end
            persist_stats
          end
        end

        def snapshot
          @mutex.synchronize { Marshal.load(Marshal.dump(@stats)) }
        end

        private

        def candidate(id)
          row = model_row(id)
          return unless row

          score = row.fetch("score", {})
          stat = @mutex.synchronize { @stats[id.to_s]&.dup }
          calls = stat&.fetch(:calls, 0).to_i
          successes = stat&.fetch(:successes, 0).to_i
          success_rate = calls.zero? ? 1.0 : successes.fdiv(calls)
          latency = stat&.fetch(:latency_ms, 0).to_f
          Candidate.new(
            id: id.to_s,
            quality: score.fetch("quality", DEFAULTS[:quality]).to_f,
            speed: score.fetch("speed", DEFAULTS[:speed]).to_f,
            cost: score.fetch("cost", DEFAULTS[:cost]).to_f,
            context_window: row.fetch("context_window", DEFAULTS[:context_window]).to_i,
            availability: @router.reachable?(id) ? 1.0 : 0.0,
            tool_support: @router.tool_capable?(id) ? 1.0 : DEFAULTS[:tool_support],
            success_rate: success_rate,
            latency_factor: latency.zero? ? 1.0 : [1000.0 / [latency, 1000.0].max, 1.0].min,
            score: score,
          )
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "compute_pool.candidate", model: id)
          nil
        end

        def utility(entry, task_type:, empirical_best:)
          return 0.0 if entry.availability <= 0.0

          quality = entry.quality * entry.success_rate
          speed = entry.speed * entry.latency_factor
          economic_factor = [entry.cost, 0.1].max
          task_factor = task_factor(entry, task_type)
          empirical_factor = entry.id == empirical_best.to_s ? 1.05 : 1.0

          # models.yml normalizes cost as economic value: 1.0 is free/local
          # compute and smaller values represent increasingly scarce spend.
          quality * entry.availability * speed * task_factor * empirical_factor *
            [entry.tool_support, 0.1].max * context_factor(entry.context_window) * economic_factor
        end

        def task_factor(entry, task_type)
          strengths = Array(@rules.dig("task_strengths", task_type.to_s))
          return 1.0 if strengths.empty?

          strength = strengths.count { |name| capability_match?(entry.id, name) }
          1.0 + [strength, 3].min * 0.04
        end

        def capability_match?(id, capability)
          text = "#{id} #{provider_for(id)}".downcase
          case capability.to_s
          when "local", "privacy", "offline" then id.start_with?("ollama:", "local:")
          when "fast" then text.match?(/flash|fast|lightning|small/)
          when "coding", "agentic" then text.match?(/code|coder|qwen|deepseek|claude|grok|glm|gpt/)
          when "reasoning" then text.match?(/reason|thinking|opus|pro|grok|deepseek/)
          when "long_context" then text.match?(/gemini|claude|qwen|agy/)
          else false
          end
        end

        def provider_for(id)
          id.to_s.split(":", 2).first
        end

        def context_factor(window)
          [[window.fdiv(128_000), 1.25].min, 0.5].max
        end

        def model_row(id)
          @rules.fetch("models", {}).values.flatten.find { |row| row.is_a?(Hash) && row["id"].to_s == id.to_s } ||
            @rules.fetch("model_defs", {}).values.find { |row| row.is_a?(Hash) && row["id"].to_s == id.to_s }
        end

        def stats_path
          File.join(@root, "runtime", "telemetry", "compute_pool.yml")
        end

        def load_stats
          return {} unless File.file?(stats_path)
          Master.load_yaml(stats_path) || {}
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "compute_pool.load_stats")
          {}
        end

        def persist_stats
          path = stats_path
          FileUtils.mkdir_p(File.dirname(path))
          Master.write_yaml(path, @stats)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "compute_pool.persist_stats")
        end

        def rolling_average(previous, value, count)
          return value if count <= 1
          previous + ((value - previous) / count)
        end

        def load_rules
          path = File.join(@root, "data", "models.yml")
          Master.load_yaml(path) || {}
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "compute_pool.load_rules")
          {}
        end
      end
    end
  end
end
