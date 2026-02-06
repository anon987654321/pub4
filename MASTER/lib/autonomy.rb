# frozen_string_literal: true

module MASTER
  # Autonomy - enables MASTER to operate with minimal user intervention
  # 
  # This file consolidates three levels of autonomy implementation:
  # 1. System-level (Autonomy) - auto-approval, retries, fallbacks, budget guards, circuit breakers
  # 2. Prompt-level (PromptAutonomy) - self-improving prompts, A/B testing, caching, contextual adaptation
  # 3. Agent-level (AgentAutonomy) - goal decomposition, self-correction, learning, proactive suggestions
  #
  # Use the LEVELS constant to access different autonomy layers
  module Autonomy
    extend self

    # Configuration defaults
    DEFAULT_CONFIG = {
      auto_approve_tools: true,
      confidence_threshold: 0.7,
      max_retries: 3,
      retry_delay: 1.0,
      budget_limit: 10.0,          # USD
      circuit_breaker_threshold: 5,
      circuit_breaker_reset: 300,  # seconds
      timeout_recovery: true,
      context_prune_threshold: 0.85,  # prune at 85% of token limit
      parallel_tools: true
    }.freeze

    # Circuit breaker state per provider
    @circuit_state = {}
    @total_cost = 0.0
    @tool_successes = Hash.new(0)
    @tool_failures = Hash.new(0)

    class << self
      attr_accessor :config, :total_cost

      def configure
        @config ||= DEFAULT_CONFIG.dup
        yield @config if block_given?
        @config
      end

      # 1. Tool auto-approval - skip confirmation for trusted operations
      def auto_approve?(tool_name, action)
        return false unless config[:auto_approve_tools]

        # Always approve read-only operations
        read_only = %w[scan analyze check lint view read list describe]
        return true if read_only.any? { |op| action.to_s.include?(op) }

        # Check tool success rate (approve if > 90% success)
        total = @tool_successes[tool_name] + @tool_failures[tool_name]
        return true if total > 10 && (@tool_successes[tool_name].to_f / total) > 0.9

        false
      end

      def record_tool_result(tool_name, success)
        if success
          @tool_successes[tool_name] += 1
        else
          @tool_failures[tool_name] += 1
        end
      end

      # 3. Confidence thresholds - retry if result confidence too low
      def meets_confidence?(result, threshold = nil)
        threshold ||= config[:confidence_threshold]
        confidence = extract_confidence(result)
        confidence >= threshold
      end

      def extract_confidence(result)
        return result[:confidence] if result.is_a?(Hash) && result[:confidence]
        return result.confidence if result.respond_to?(:confidence)

        # Heuristic: longer, more detailed responses = higher confidence
        text = result.to_s
        return 0.9 if text.length > 500 && !text.include?('unsure') && !text.include?('maybe')
        return 0.5 if text.include?('I think') || text.include?('possibly')
        return 0.3 if text.include?("I don't know") || text.include?('cannot')

        0.7  # default
      end

      # 4. Fallback strategies - model tier fallback chain
      FALLBACK_CHAIN = %w[
        anthropic/claude-sonnet-4-20250514
        anthropic/claude-3-5-haiku-20241022
        google/gemini-2.0-flash-001
        openai/gpt-4o-mini
      ].freeze

      def fallback_model(current_model)
        idx = FALLBACK_CHAIN.index(current_model)
        return FALLBACK_CHAIN.first unless idx

        FALLBACK_CHAIN[idx + 1] || FALLBACK_CHAIN.last
      end

      # 5. Budget guardrails
      def within_budget?(cost = 0)
        (@total_cost + cost) <= config[:budget_limit]
      end

      def track_cost(cost)
        @total_cost += cost
        Dmesg.budget('spent', cost, remaining_budget) rescue nil
        !exceeded_budget?
      end

      def exceeded_budget?
        @total_cost >= config[:budget_limit]
      end

      def remaining_budget
        [config[:budget_limit] - @total_cost, 0].max
      end

      # Estimate cost for a prompt (rough)
      def estimate_cost(prompt, response_estimate: 500)
        input_tokens = prompt.to_s.length / 4
        output_tokens = response_estimate
        # Default to Sonnet pricing
        (input_tokens * 3.0 / 1_000_000) + (output_tokens * 15.0 / 1_000_000)
      end

      # 6. Retry logic with exponential backoff
      def with_retry(max_retries: nil, &block)
        max_retries ||= config[:max_retries]
        attempt = 0

        loop do
          attempt += 1
          Dmesg.retry_event(attempt, max_retries, 'executing') rescue nil
          result = yield
          return result if result_ok?(result)

          break if attempt >= max_retries

          delay = config[:retry_delay] * (2 ** (attempt - 1))
          sleep(delay)
        end

        Result.err("Failed after #{max_retries} retries")
      end

      def result_ok?(result)
        return result.ok? if result.respond_to?(:ok?)
        return !result.nil? && result != false

        true
      end

      # 7. Circuit breaker - stop calling failing providers
      def circuit_open?(provider)
        state = @circuit_state[provider]
        return false unless state

        if state[:open] && (Time.now - state[:opened_at]) > config[:circuit_breaker_reset]
          # Half-open: allow one request to test
          state[:half_open] = true
          return false
        end

        state[:open]
      end

      def record_provider_result(provider, success)
        @circuit_state[provider] ||= { failures: 0, open: false }
        state = @circuit_state[provider]

        if success
          state[:failures] = 0
          state[:open] = false
          state[:half_open] = false
        else
          state[:failures] += 1
          if state[:failures] >= config[:circuit_breaker_threshold]
            state[:open] = true
            state[:opened_at] = Time.now
            Dmesg.circuit(provider, 'OPEN - too many failures') rescue nil
          end
        end
      end

      def reset_circuit(provider)
        @circuit_state.delete(provider)
      end

      # 8. Timeout recovery - retry with shorter context
      def timeout_recovery_context(messages, reduction: 0.5)
        return messages if messages.size <= 2

        # Keep system prompt + last N messages
        keep_count = [(messages.size * reduction).to_i, 2].max
        [messages.first] + messages.last(keep_count - 1)
      end

      # 9. Context pruning - auto-truncate when approaching limit
      def prune_context(messages, token_limit:, current_tokens:)
        threshold = token_limit * config[:context_prune_threshold]
        return messages if current_tokens < threshold

        # Summarize middle messages, keep first (system) and recent
        keep_recent = 10
        return messages if messages.size <= keep_recent + 1

        system = messages.first
        recent = messages.last(keep_recent)
        middle = messages[1..-(keep_recent + 1)]

        # Compress middle into summary
        summary = {
          role: 'system',
          content: "[Previous #{middle.size} messages summarized: Discussion covered #{extract_topics(middle)}]"
        }

        [system, summary] + recent
      end

      def extract_topics(messages)
        # Simple keyword extraction
        text = messages.map { |m| m[:content].to_s }.join(' ')
        words = text.downcase.scan(/\b[a-z]{4,}\b/)
        words.tally.sort_by { |_, v| -v }.first(5).map(&:first).join(', ')
      end

      # 10. Parallel tool execution
      def execute_parallel(tools, &block)
        return tools.map(&block) unless config[:parallel_tools]

        threads = tools.map do |tool|
          Thread.new { block.call(tool) }
        end

        threads.map(&:value)
      end

      # Reset all state
      def reset!
        @circuit_state = {}
        @total_cost = 0.0
        @tool_successes = Hash.new(0)
        @tool_failures = Hash.new(0)
        @config = DEFAULT_CONFIG.dup
      end
    end

    # Initialize with defaults
    @config = DEFAULT_CONFIG.dup
  end

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

  # AgentAutonomy - higher-level autonomous behaviors
  # Goal decomposition, self-correction, proactive suggestions, learning
  module AgentAutonomy
    extend self

    LEARNING_FILE = File.join(Paths.var, 'agent_learning.yml')
    SKILLS_FILE = File.join(Paths.var, 'agent_skills.yml')

    # 18. Goal decomposition - break complex goals into subtasks
    def decompose_goal(goal, llm)
      prompt = <<~PROMPT
        Break this goal into 3-7 concrete, actionable subtasks.
        Each subtask should be completable in one step.
        
        Goal: #{goal}
        
        Return as numbered list, one task per line.
        No explanations, just the tasks.
      PROMPT

      response = llm.ask(prompt)
      return [] unless response

      response.split("\n")
        .map { |line| line.gsub(/^\d+\.\s*/, '').strip }
        .reject(&:empty?)
    end

    # 19. Progress tracking
    @progress = { completed: [], pending: [], failed: [] }

    class << self
      attr_accessor :progress

      def track_start(task_id, description)
        @progress[:pending] << { id: task_id, desc: description, started: Time.now }
      end

      def track_complete(task_id, result = nil)
        task = @progress[:pending].find { |t| t[:id] == task_id }
        return unless task

        @progress[:pending].delete(task)
        task[:completed] = Time.now
        task[:result] = result
        @progress[:completed] << task
      end

      def track_fail(task_id, error)
        task = @progress[:pending].find { |t| t[:id] == task_id }
        return unless task

        @progress[:pending].delete(task)
        task[:failed] = Time.now
        task[:error] = error
        @progress[:failed] << task
      end

      def completion_rate
        total = @progress[:completed].size + @progress[:failed].size
        return 1.0 if total.zero?

        @progress[:completed].size.to_f / total
      end
    end

    # 20. Self-correction - detect and fix own mistakes
    def self_correct(original_output, error, llm)
      prompt = <<~PROMPT
        Your previous output caused an error. Fix it.
        
        Original output:
        #{original_output[0..1000]}
        
        Error:
        #{error[0..500]}
        
        Provide corrected output only, no explanations.
      PROMPT

      llm.ask(prompt)
    end

    def detect_mistake(output, expected_pattern: nil)
      return :empty if output.nil? || output.strip.empty?
      return :too_short if output.length < 10
      return :error_message if output.match?(/error|exception|failed|undefined/i)
      return :pattern_mismatch if expected_pattern && !output.match?(expected_pattern)

      nil
    end

    # 21. Learning from feedback - improve from user corrections
    def record_correction(original:, corrected:, context:)
      learning = load_learning
      learning[:corrections] ||= []

      learning[:corrections] << {
        original: original[0..500],
        corrected: corrected[0..500],
        context: context[0..200],
        recorded_at: Time.now.to_i
      }

      # Keep last 100
      learning[:corrections] = learning[:corrections].last(100)
      save_learning(learning)
    end

    def apply_learned_corrections(output, context)
      learning = load_learning
      corrections = learning[:corrections] || []

      # Find similar contexts
      relevant = corrections.select do |c|
        similarity(c[:context], context) > 0.5
      end

      return output if relevant.empty?

      # Apply pattern-based corrections
      result = output
      relevant.each do |c|
        if result.include?(c[:original])
          result = result.gsub(c[:original], c[:corrected])
        end
      end

      result
    end

    def similarity(a, b)
      return 0.0 if a.nil? || b.nil?

      words_a = a.downcase.scan(/\w+/).to_set
      words_b = b.downcase.scan(/\w+/).to_set

      return 0.0 if words_a.empty? || words_b.empty?

      intersection = (words_a & words_b).size
      union = (words_a | words_b).size

      intersection.to_f / union
    end

    # 22. Proactive suggestions - anticipate user needs
    def suggest_next_action(history, context)
      return nil if history.empty?

      # Pattern matching on common sequences
      recent = history.last(5).map { |h| h[:command] }

      # After scan, suggest refactor
      return 'refactor' if recent.last == 'scan'

      # After refactor, suggest commit
      return 'commit' if recent.last == 'refactor'

      # After multiple edits, suggest lint
      edit_count = recent.count { |c| c&.start_with?('edit') }
      return 'lint' if edit_count >= 3

      # After goal, suggest plan
      return 'plan' if recent.last&.start_with?('goal')

      nil
    end

    # 23. Context awareness - understand current state
    def analyze_context(root_dir)
      {
        git_status: git_status(root_dir),
        recent_files: recent_files(root_dir),
        current_branch: current_branch(root_dir),
        uncommitted_changes: uncommitted_changes?(root_dir),
        test_status: nil  # Would run tests if available
      }
    end

    def git_status(dir)
      Dir.chdir(dir) { `git status --porcelain 2>/dev/null`.strip }
    rescue
      nil
    end

    def recent_files(dir, count: 5)
      Dir.glob(File.join(dir, '**', '*.rb'))
        .reject { |f| f.include?('/vendor/') }
        .sort_by { |f| File.mtime(f) }
        .last(count)
        .reverse
    rescue
      []
    end

    def current_branch(dir)
      Dir.chdir(dir) { `git branch --show-current 2>/dev/null`.strip }
    rescue
      nil
    end

    def uncommitted_changes?(dir)
      status = git_status(dir)
      status && !status.empty?
    end

    # 24. Memory consolidation - compress long-term memory
    def consolidate_memory(messages, llm, max_size: 50)
      return messages if messages.size <= max_size

      # Keep system prompt and recent messages
      keep_recent = 20
      system = messages.first
      recent = messages.last(keep_recent)
      to_compress = messages[1..-(keep_recent + 1)]

      return messages if to_compress.nil? || to_compress.empty?

      # Summarize compressed section
      summary_prompt = <<~PROMPT
        Summarize this conversation into key points (max 200 words):
        #{to_compress.map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n")[0..3000]}
      PROMPT

      summary = llm.ask(summary_prompt)

      summary_msg = {
        role: 'system',
        content: "[Conversation summary: #{summary}]"
      }

      [system, summary_msg] + recent
    end

    # 25. Skill acquisition - learn new capabilities
    def learn_skill(name:, pattern:, action:, examples: [])
      skills = load_skills
      skills[name] = {
        pattern: pattern,
        action: action,
        examples: examples,
        learned_at: Time.now.to_i,
        success_count: 0
      }
      save_skills(skills)
    end

    def find_skill(input)
      skills = load_skills
      skills.find do |name, skill|
        input.match?(Regexp.new(skill[:pattern], Regexp::IGNORECASE))
      end
    end

    def apply_skill(name)
      skills = load_skills
      skill = skills[name]
      return nil unless skill

      skill[:success_count] += 1
      save_skills(skills)

      skill[:action]
    end

    # 26. Resource optimization
    def optimize_prompt(prompt, max_tokens: 4000)
      return prompt if prompt.length < max_tokens * 4  # ~4 chars per token

      # Remove redundant whitespace
      optimized = prompt.gsub(/\s+/, ' ').strip

      # Truncate if still too long
      if optimized.length > max_tokens * 4
        optimized = optimized[0..(max_tokens * 4)]
        optimized += "\n[truncated]"
      end

      optimized
    end

    def estimate_cost(prompt, response_estimate: 500)
      # Rough token estimation
      input_tokens = prompt.length / 4
      output_tokens = response_estimate

      # Default to Sonnet pricing
      input_cost = input_tokens * 3.0 / 1_000_000
      output_cost = output_tokens * 15.0 / 1_000_000

      input_cost + output_cost
    end

    # 27. Error recovery
    def recover_from_error(error, context, llm)
      error_type = classify_error(error)

      case error_type
      when :rate_limit
        { action: :wait, duration: 60 }
      when :token_limit
        { action: :reduce_context, factor: 0.5 }
      when :invalid_response
        { action: :retry, with_clarification: true }
      when :network
        { action: :retry, delay: 5 }
      else
        { action: :escalate, error: error }
      end
    end

    def classify_error(error)
      msg = error.to_s.downcase

      return :rate_limit if msg.include?('rate limit') || msg.include?('429')
      return :token_limit if msg.include?('token') && msg.include?('limit')
      return :network if msg.include?('connection') || msg.include?('timeout')
      return :invalid_response if msg.include?('parse') || msg.include?('json')

      :unknown
    end

    # 28. State persistence - handled by SessionRecovery

    # 29. Watchdog monitoring
    @health_checks = []

    def register_health_check(name, &block)
      @health_checks << { name: name, check: block }
    end

    def run_health_checks
      results = {}
      @health_checks.each do |hc|
        results[hc[:name]] = begin
          hc[:check].call ? :healthy : :unhealthy
        rescue => e
          { status: :error, message: e.message }
        end
      end
      results
    end

    # 30. Auto-documentation
    def document_change(file:, change_type:, description:, diff: nil)
      changelog = File.join(Paths.var, 'auto_changelog.md')

      entry = <<~ENTRY
        ## #{Time.now.strftime('%Y-%m-%d %H:%M')} - #{change_type}
        **File:** #{file}
        **Change:** #{description}
        #{"```diff\n#{diff[0..500]}\n```" if diff}

      ENTRY

      File.open(changelog, 'a') { |f| f.write(entry) }
    end

    private

    def load_learning
      return {} unless File.exist?(LEARNING_FILE)

      YAML.load_file(LEARNING_FILE, symbolize_names: true) rescue {}
    end

    def save_learning(data)
      FileUtils.mkdir_p(File.dirname(LEARNING_FILE))
      File.write(LEARNING_FILE, data.to_yaml)
    end

    def load_skills
      return {} unless File.exist?(SKILLS_FILE)

      YAML.load_file(SKILLS_FILE, symbolize_names: true) rescue {}
    end

    def save_skills(data)
      FileUtils.mkdir_p(File.dirname(SKILLS_FILE))
      File.write(SKILLS_FILE, data.to_yaml)
    end
  end

  # LEVELS constant for accessing different autonomy layers
  LEVELS = {
    system: Autonomy,
    prompt: PromptAutonomy,
    agent: AgentAutonomy
  }.freeze
end
