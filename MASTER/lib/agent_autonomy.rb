# frozen_string_literal: true

module MASTER
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
end
