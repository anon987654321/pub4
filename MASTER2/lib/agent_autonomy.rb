# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module MASTER
  # AgentAutonomy - Higher-level autonomous behaviors for intelligent agents
  # Features: goal decomposition, progress tracking, self-correction, learning from feedback
  # Ported from MASTER v1, adapted for MASTER2's architecture
  module AgentAutonomy
    extend self

    LEARNING_FILE = File.join(Paths.data, 'agent_learning.yml')
    
    # Goal decomposition - break complex goals into subtasks via LLM
    def decompose_goal(goal)
      prompt = <<~PROMPT
        Break this goal into 3-7 concrete, actionable subtasks.
        Each subtask should be completable in one step.
        
        Goal: #{goal}
        
        Return as numbered list, one task per line.
        No explanations, just the tasks.
      PROMPT

      result = LLM.ask(prompt, tier: :fast)
      return Result.err("Goal decomposition failed") unless result.ok?

      tasks = result.value[:content].split("\n")
        .map { |line| line.gsub(/^\d+\.\s*/, '').strip }
        .reject(&:empty?)

      Result.ok(tasks: tasks)
    end

    # Progress tracking - track started/completed/failed tasks
    @progress = { pending: [], completed: [], failed: [] }

    class << self
      attr_accessor :progress

      def track_start(task_id, description)
        @progress[:pending] << { 
          id: task_id, 
          description: description, 
          started_at: Time.now 
        }
      end

      def track_complete(task_id, result: nil)
        task = @progress[:pending].find { |t| t[:id] == task_id }
        return unless task

        @progress[:pending].delete(task)
        task[:completed_at] = Time.now
        task[:duration] = (task[:completed_at] - task[:started_at]).round(2)
        task[:result] = result
        @progress[:completed] << task
      end

      def track_fail(task_id, error)
        task = @progress[:pending].find { |t| t[:id] == task_id }
        return unless task

        @progress[:pending].delete(task)
        task[:failed_at] = Time.now
        task[:duration] = (task[:failed_at] - task[:started_at]).round(2)
        task[:error] = error.to_s
        @progress[:failed] << task
      end

      def completion_rate
        total = @progress[:completed].size + @progress[:failed].size
        return 1.0 if total.zero?

        (@progress[:completed].size.to_f / total).round(3)
      end

      def progress_summary
        {
          pending: @progress[:pending].size,
          completed: @progress[:completed].size,
          failed: @progress[:failed].size,
          completion_rate: completion_rate,
          total: @progress[:pending].size + @progress[:completed].size + @progress[:failed].size
        }
      end

      def reset_progress
        @progress = { pending: [], completed: [], failed: [] }
      end
    end

    # Self-correction - detect own mistakes and auto-fix via LLM
    def self_correct(original_output, error)
      prompt = <<~PROMPT
        Your previous output caused an error. Fix it.
        
        Original output:
        #{original_output[0..1000]}
        
        Error:
        #{error[0..500]}
        
        Provide corrected output only, no explanations.
      PROMPT

      result = LLM.ask(prompt, tier: :strong)
      return Result.err("Self-correction failed") unless result.ok?

      Result.ok(corrected: result.value[:content])
    end

    # Mistake detection - pattern-based output validation
    def detect_mistake(output, expected_pattern: nil)
      return :empty if output.nil? || output.strip.empty?
      return :too_short if output.length < 10
      return :error_message if output.match?(/\b(error|exception|failed|undefined)\b/i)
      return :pattern_mismatch if expected_pattern && !output.match?(expected_pattern)

      nil
    end

    # Learning from feedback - record user corrections
    def record_correction(original:, corrected:, context: nil)
      learning = load_learning
      learning[:corrections] ||= []

      learning[:corrections] << {
        original: original[0..500],
        corrected: corrected[0..500],
        context: context&.[](0..200),
        recorded_at: Time.now.to_i
      }

      # Keep last 100 corrections
      learning[:corrections] = learning[:corrections].last(100)
      save_learning(learning)
      Result.ok("Correction recorded")
    end

    # Apply learned corrections to new output
    def apply_learned_corrections(output, context: nil)
      learning = load_learning
      corrections = learning[:corrections] || []

      return output if corrections.empty?

      # Find similar contexts if context provided
      relevant = if context
        corrections.select do |c|
          c[:context] && similarity(c[:context], context) > 0.5
        end
      else
        corrections.last(10) # Use recent corrections if no context
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

    # Context awareness - check if task requires specific context
    def requires_context?(task)
      context_keywords = %w[
        understand explain describe analyze
        current recent previous existing
        this that these those
      ]
      
      task.downcase.split.any? { |word| context_keywords.include?(word) }
    end

    # Skill acquisition - track learned capabilities
    def record_skill(name, description: nil, examples: [])
      learning = load_learning
      learning[:skills] ||= []

      skill = {
        name: name,
        description: description,
        examples: examples.map { |e| e[0..200] },
        learned_at: Time.now.to_i,
        use_count: 0
      }

      # Update if exists, add if new
      existing = learning[:skills].find { |s| s[:name] == name }
      if existing
        existing[:examples] = (existing[:examples] + skill[:examples]).last(5)
        existing[:description] = description if description
      else
        learning[:skills] << skill
      end

      save_learning(learning)
      Result.ok("Skill recorded: #{name}")
    end

    def increment_skill_usage(name)
      learning = load_learning
      learning[:skills] ||= []

      skill = learning[:skills].find { |s| s[:name] == name }
      if skill
        skill[:use_count] = (skill[:use_count] || 0) + 1
        skill[:last_used] = Time.now.to_i
        save_learning(learning)
      end
    end

    def list_skills
      learning = load_learning
      (learning[:skills] || []).sort_by { |s| -(s[:use_count] || 0) }
    end

    # Error recovery - suggest recovery actions based on error type
    def suggest_recovery(error_message)
      case error_message
      when /file not found|no such file/i
        "Check file path and ensure file exists"
      when /permission denied/i
        "Verify file permissions or run with appropriate privileges"
      when /timeout|timed out/i
        "Increase timeout duration or check network connectivity"
      when /connection refused|unreachable/i
        "Verify service is running and network is accessible"
      when /syntax error/i
        "Review code syntax and formatting"
      when /undefined method|no method/i
        "Check method name and ensure required modules are loaded"
      when /api key|authentication|unauthorized/i
        "Verify API credentials are set correctly"
      else
        "Review error details and consult documentation"
      end
    end

    private

    # Text similarity using Jaccard index
    def similarity(text_a, text_b)
      return 0.0 if text_a.nil? || text_b.nil?

      words_a = text_a.downcase.scan(/\w+/).to_set
      words_b = text_b.downcase.scan(/\w+/).to_set

      return 0.0 if words_a.empty? || words_b.empty?

      intersection = (words_a & words_b).size
      union = (words_a | words_b).size

      (intersection.to_f / union).round(3)
    end

    def load_learning
      return {} unless File.exist?(LEARNING_FILE)
      YAML.safe_load_file(LEARNING_FILE, symbolize_names: true) || {}
    rescue StandardError
      {}
    end

    def save_learning(data)
      FileUtils.mkdir_p(File.dirname(LEARNING_FILE))
      File.write(LEARNING_FILE, YAML.dump(data))
    end
  end
end
