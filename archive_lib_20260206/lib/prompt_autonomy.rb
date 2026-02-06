# frozen_string_literal: true

module MASTER
  # PromptAutonomy - self-improving prompts, A/B testing, caching, contextual adaptation
  module PromptAutonomy
    extend self

    PROMPTS_FILE = File.join(Paths.var, 'prompt_versions.yml')
    EXAMPLES_FILE = File.join(Paths.var, 'few_shot_examples.yml')
    METRICS_FILE = File.join(Paths.var, 'prompt_metrics.yml')

    # 11. Self-improving prompts - track success and tune
    def track_execution(prompt_id, success:, latency: nil, tokens: nil)
      metrics = load_metrics
      metrics[prompt_id] ||= { successes: 0, failures: 0, total_latency: 0, executions: 0 }

      if success
        metrics[prompt_id][:successes] += 1
      else
        metrics[prompt_id][:failures] += 1
      end

      metrics[prompt_id][:executions] += 1
      metrics[prompt_id][:total_latency] += latency if latency

      save_metrics(metrics)

      # Auto-tune if success rate drops
      rate = success_rate(prompt_id)
      if rate < 0.7 && metrics[prompt_id][:executions] > 10
        suggest_improvement(prompt_id)
      end
    end

    def success_rate(prompt_id)
      metrics = load_metrics[prompt_id]
      return 1.0 unless metrics && metrics[:executions] > 0

      metrics[:successes].to_f / metrics[:executions]
    end

    def suggest_improvement(prompt_id)
      # Flag for manual review or auto-enhance
      metrics = load_metrics
      metrics[prompt_id][:needs_improvement] = true
      metrics[prompt_id][:suggested_at] = Time.now.to_i
      save_metrics(metrics)
    end

    # 12. Dynamic instructions - add examples based on failures
    def enhance_with_failures(prompt, task_type)
      failures = recent_failures(task_type, limit: 3)
      return prompt if failures.empty?

      additions = failures.map do |f|
        "Avoid: #{f[:mistake]} (caused: #{f[:error]})"
      end.join("\n")

      "#{prompt}\n\nLearned corrections:\n#{additions}"
    end

    def record_failure(task_type:, input:, mistake:, error:)
      examples = load_examples
      examples[:failures] ||= []
      examples[:failures] << {
        task_type: task_type,
        input: input[0..200],
        mistake: mistake,
        error: error[0..100],
        recorded_at: Time.now.to_i
      }

      # Keep last 50 failures
      examples[:failures] = examples[:failures].last(50)
      save_examples(examples)
    end

    def recent_failures(task_type, limit: 5)
      examples = load_examples
      (examples[:failures] || [])
        .select { |f| f[:task_type] == task_type }
        .last(limit)
    end

    # 13. Few-shot learning - store and inject successful examples
    def add_example(task_type:, input:, output:, quality_score: 1.0)
      examples = load_examples
      examples[:successes] ||= {}
      examples[:successes][task_type] ||= []

      examples[:successes][task_type] << {
        input: input[0..500],
        output: output[0..1000],
        quality: quality_score,
        added_at: Time.now.to_i
      }

      # Keep top 10 by quality per task type
      examples[:successes][task_type] = examples[:successes][task_type]
        .sort_by { |e| -e[:quality] }
        .first(10)

      save_examples(examples)
    end

    def few_shot_examples(task_type, count: 3)
      examples = load_examples
      (examples.dig(:successes, task_type) || []).first(count)
    end

    def inject_few_shot(prompt, task_type, count: 2)
      shots = few_shot_examples(task_type, count: count)
      return prompt if shots.empty?

      examples_text = shots.map.with_index do |ex, i|
        "Example #{i + 1}:\nInput: #{ex[:input]}\nOutput: #{ex[:output]}"
      end.join("\n\n")

      "#{prompt}\n\nExamples:\n#{examples_text}\n\nNow handle the current request:"
    end

    # 14. Prompt versioning - track versions, auto-rollback
    def save_version(prompt_id, content, metadata = {})
      versions = load_versions
      versions[prompt_id] ||= []

      version = {
        content: content,
        version: versions[prompt_id].size + 1,
        created_at: Time.now.to_i,
        active: true,
        metadata: metadata
      }

      # Deactivate previous
      versions[prompt_id].each { |v| v[:active] = false }
      versions[prompt_id] << version

      save_versions(versions)
      version[:version]
    end

    def rollback(prompt_id)
      versions = load_versions
      return nil unless versions[prompt_id]&.size&.> 1

      # Deactivate current, activate previous
      versions[prompt_id].last[:active] = false
      versions[prompt_id][-2][:active] = true

      save_versions(versions)
      versions[prompt_id][-2][:version]
    end

    def active_version(prompt_id)
      versions = load_versions
      versions[prompt_id]&.find { |v| v[:active] }
    end

    # 15. A/B testing - run variants, track performance
    @ab_tests = {}

    def start_ab_test(test_id, variant_a:, variant_b:)
      @ab_tests[test_id] = {
        variants: { a: variant_a, b: variant_b },
        results: { a: { successes: 0, total: 0 }, b: { successes: 0, total: 0 } },
        started_at: Time.now.to_i
      }
    end

    def get_variant(test_id)
      test = @ab_tests[test_id]
      return nil unless test

      # Epsilon-greedy: 20% exploration, 80% exploitation
      if rand < 0.2
        [:a, :b].sample
      else
        # Pick variant with higher success rate
        rate_a = test[:results][:a][:total] > 0 ?
          test[:results][:a][:successes].to_f / test[:results][:a][:total] : 0.5
        rate_b = test[:results][:b][:total] > 0 ?
          test[:results][:b][:successes].to_f / test[:results][:b][:total] : 0.5

        rate_a >= rate_b ? :a : :b
      end
    end

    def record_ab_result(test_id, variant, success)
      test = @ab_tests[test_id]
      return unless test

      test[:results][variant][:total] += 1
      test[:results][variant][:successes] += 1 if success
    end

    def ab_winner(test_id, min_samples: 20)
      test = @ab_tests[test_id]
      return nil unless test

      a = test[:results][:a]
      b = test[:results][:b]

      return nil if a[:total] < min_samples || b[:total] < min_samples

      rate_a = a[:successes].to_f / a[:total]
      rate_b = b[:successes].to_f / b[:total]

      # Significant difference (>10%)
      if (rate_a - rate_b).abs > 0.1
        rate_a > rate_b ? :a : :b
      else
        nil  # No significant winner yet
      end
    end

    # 16. Prompt caching hints
    def cacheable_prompt?(prompt, min_length: 1000)
      prompt.to_s.length >= min_length
    end

    def cache_headers(prompt)
      return {} unless cacheable_prompt?(prompt)

      # Anthropic prompt caching
      { 'anthropic-beta' => 'prompt-caching-2024-07-31' }
    end

    # 17. Contextual prompts - detect task type, adjust parameters
    TASK_PROFILES = {
      code: { temperature: 0.2, top_p: 0.95 },
      creative: { temperature: 0.9, top_p: 0.98 },
      analysis: { temperature: 0.3, top_p: 0.9 },
      conversation: { temperature: 0.7, top_p: 0.95 },
      factual: { temperature: 0.1, top_p: 0.9 }
    }.freeze

    def detect_task_type(prompt)
      text = prompt.to_s.downcase

      return :code if text.match?(/\b(code|function|class|def|implement|bug|refactor|debug)\b/)
      return :creative if text.match?(/\b(write|story|poem|creative|imagine|brainstorm)\b/)
      return :analysis if text.match?(/\b(analyze|compare|evaluate|assess|review)\b/)
      return :factual if text.match?(/\b(what is|define|explain|how does|when did)\b/)

      :conversation  # default
    end

    def task_parameters(prompt)
      task_type = detect_task_type(prompt)
      TASK_PROFILES[task_type] || TASK_PROFILES[:conversation]
    end

    private

    def load_versions
      return {} unless File.exist?(PROMPTS_FILE)

      YAML.load_file(PROMPTS_FILE, symbolize_names: true) rescue {}
    end

    def save_versions(versions)
      FileUtils.mkdir_p(File.dirname(PROMPTS_FILE))
      File.write(PROMPTS_FILE, versions.to_yaml)
    end

    def load_examples
      return {} unless File.exist?(EXAMPLES_FILE)

      YAML.load_file(EXAMPLES_FILE, symbolize_names: true) rescue {}
    end

    def save_examples(examples)
      FileUtils.mkdir_p(File.dirname(EXAMPLES_FILE))
      File.write(EXAMPLES_FILE, examples.to_yaml)
    end

    def load_metrics
      return {} unless File.exist?(METRICS_FILE)

      YAML.load_file(METRICS_FILE, symbolize_names: true) rescue {}
    end

    def save_metrics(metrics)
      FileUtils.mkdir_p(File.dirname(METRICS_FILE))
      File.write(METRICS_FILE, metrics.to_yaml)
    end
  end
end
