# frozen_string_literal: true

module Master
  module CLI
    class ModelBenchmark
      TASKS = {
        reasoning: "Explain why a Ruby hash with a default proc can accidentally share mutable state between unrelated keys, and give one minimal safe pattern.",
        coding: "Write a Ruby method named normalize_name that strips surrounding whitespace, collapses internal whitespace to one space, and returns nil for blank input. State the edge case it handles.",
        architecture: "MASTER routes work across multiple model providers. Name three signals that should affect model selection without hard-coding a permanent leaderboard."
      }.freeze

      DEFAULT_LIMIT = 8

      def initialize(agent:, router:, metrics:, root:)
        @agent = agent
        @router = router
        @metrics = metrics
        @root = root
      end

      def run(argument = "")
        models = candidates(argument)
        return "model benchmark: no reachable models" if models.empty?

        rows = models.map { |model| benchmark_model(model) }
        render(rows)
      rescue StandardError => e
        "model benchmark: #{e.class}: #{e.message}"
      end

      private

      def candidates(argument)
        requested = argument.to_s.strip
        pool = Array(@router&.pool(wait: true))
        return pool if requested == "all"

        names = requested.split(",").map(&:strip).reject(&:empty?)
        return names unless names.empty?

        ollama = pool.select { |id| id.start_with?("ollama:") }
        ollama.empty? ? [@agent.model].compact : ollama.first(DEFAULT_LIMIT)
      end

      def benchmark_model(model)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        passed = 0
        errors = []

        TASKS.each do |name, prompt|
          begin
            answer = @agent.ask_once(prompt, model:, law: false, failover: false)
            passed += 1 unless answer.to_s.strip.empty?
          rescue StandardError => e
            errors << "#{name}: #{e.message}"
          end
        end

        elapsed = elapsed_ms(started)
        result = {
          model: model,
          tasks: TASKS.size,
          passed: passed,
          failed: TASKS.size - passed,
          success_rate: (passed.to_f / TASKS.size).round(3),
          elapsed_ms: elapsed,
          avg_ms: (elapsed.to_f / TASKS.size).round,
          errors: errors
        }
        @metrics&.record_model_benchmark(**result)
        result
      end

      def elapsed_ms(started)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      end

      def render(rows)
        rows.map do |row|
          "#{row[:model]}  #{row[:passed]}/#{row[:tasks]}  #{row[:success_rate]}  #{row[:avg_ms]}ms"
        end.join("\n")
      end
    end
  end
end
