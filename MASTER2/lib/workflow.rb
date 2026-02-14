# frozen_string_literal: true

require 'yaml'
require 'time'

module MASTER
  # Workflow - Unified workflow management combining planning, orchestration, and convergence detection
  # Consolidates: Planner + WorkflowEngine + Convergence for DRY and Single Responsibility
  module Workflow
    # Planner - Systematic task breakdown and execution
    class Planner
      PLAN_FILE = File.join(Paths.var, 'current_plan.yml')
      PLAN_HISTORY = File.join(Paths.var, 'plan_history.yml')
      MAX_TASKS = 20
      MAX_RETRIES = 3

      def initialize(llm = nil)
        @llm = llm
        @current_plan = load_plan
      end

      attr_reader :current_plan

      def create_plan(goal)
        prompt = <<~PROMPT
          Break down this goal into concrete, sequential tasks.
          Each task should be a single command or action.
          Number them 1-N. Be specific. Max 10 tasks.

          Goal: #{goal}

          Format:
          1. [command or action]
          2. [command or action]
          ...
        PROMPT

        result = @llm&.ask(prompt, tier: :fast)
        return Result.err('Failed to create plan') unless result&.ok?

        tasks = parse_tasks(result.value)
        return Result.err('No tasks parsed from plan') if tasks.empty?

        @current_plan = {
          goal: goal,
          created_at: Time.now.iso8601,
          status: :pending,
          current_task: 0,
          tasks: tasks,
          results: []
        }

        save_plan
        Dmesg.goal(goal, 'created') if defined?(Dmesg)
        Result.ok(@current_plan)
      end

      def next_task
        return nil unless @current_plan
        return nil if @current_plan[:status] == :complete

        idx = @current_plan[:current_task]
        @current_plan[:tasks][idx]
      end

      def execute_next
        task = next_task
        return Result.err('No tasks remaining') unless task

        task[:status] = :running
        task[:started_at] = Time.now.iso8601
        save_plan

        begin
          result = block_given? ? yield(task[:action]) : task[:action]

          task[:status] = :complete
          task[:completed_at] = Time.now.iso8601
          task[:result] = result.to_s[0..500]

          @current_plan[:results] << {
            task_idx: @current_plan[:current_task],
            action: task[:action],
            result: task[:result],
            success: true
          }

          advance_task
          save_plan

          Result.ok(task)
        rescue StandardError => e
          task[:status] = :failed
          task[:error] = e.message
          task[:retries] = (task[:retries] || 0) + 1

          if task[:retries] < MAX_RETRIES
            task[:status] = :pending
          else
            @current_plan[:status] = :blocked
          end

          save_plan
          Result.err(e.message)
        end
      end

      def advance_task
        @current_plan[:current_task] += 1

        if @current_plan[:current_task] >= @current_plan[:tasks].size
          @current_plan[:status] = :complete
          @current_plan[:completed_at] = Time.now.iso8601
          Dmesg.goal(@current_plan[:goal], 'complete') if defined?(Dmesg)
          archive_plan
        end
      end

      def skip_task
        task = next_task
        return Result.err('No task to skip') unless task

        task[:status] = :skipped
        advance_task
        save_plan

        Result.ok("Skipped: #{task[:action]}")
      end

      def progress
        return nil unless @current_plan

        total = @current_plan[:tasks].size
        done = @current_plan[:tasks].count { |t| t[:status] == :complete }

        {
          goal: @current_plan[:goal],
          status: @current_plan[:status],
          progress: "#{done}/#{total}",
          percent: (done.to_f / total * 100).round,
          current: next_task&.dig(:action),
          completed: @current_plan[:tasks].select { |t| t[:status] == :complete }.map { |t| t[:action] }
        }
      end

      def clear_plan
        archive_plan if @current_plan
        @current_plan = nil
        FileUtils.rm_f(PLAN_FILE)
        Result.ok('Plan cleared')
      end

      def format_plan
        return 'No active plan' unless @current_plan

        lines = ["Plan: #{@current_plan[:goal]}", '']

        @current_plan[:tasks].each_with_index do |task, i|
          marker = case task[:status]
                   when :complete then '✓'
                   when :running then '→'
                   when :failed then '✗'
                   when :skipped then '○'
                   else '·'
                   end

          current = i == @current_plan[:current_task] ? ' ←' : ''
          lines << "  #{marker} #{i + 1}. #{task[:action]}#{current}"
        end

        prog = progress
        lines << ''
        lines << "Progress: #{prog[:progress]} (#{prog[:percent]}%)"
        lines << "Status: #{@current_plan[:status]}"

        lines.join("\n")
      end

      private

      def parse_tasks(text)
        tasks = []

        text.lines.each do |line|
          if line =~ /^\s*(\d+)[.)]\s*(.+)/
            action = ::Regexp.last_match(2).strip
            action = action.sub(/^(run|execute|do):\s*/i, "")

            tasks << {
              action: action,
              status: :pending,
              retries: 0
            }
          end
        end

        tasks.take(MAX_TASKS)
      end

      def self.parse_plan(text)
        return [] if text.nil? || text.empty?
        
        steps = text.scan(/^\s*(\d+)[.)]\s*(.+?)$/m).map { |_num, step| step.strip }
        steps.reject(&:empty?)
      end

      def self.generate_plan(goal, max_steps: 10)
        return Result.err("Goal cannot be empty") if goal.nil? || goal.empty?

        prompt = <<~PROMPT
          Create a step-by-step plan to accomplish this goal:
          
          GOAL: #{goal}
          
          Provide a numbered list of steps (maximum #{max_steps} steps).
          Each step should be clear and actionable.
          
          Format:
          1. First step
          2. Second step
          3. Third step
          ...
          
          PLAN:
        PROMPT

        if defined?(LLM)
          result = LLM.ask(prompt, tier: :fast)
          return result unless result.ok?
          
          steps = parse_plan(result.value[:content])
          Result.ok(steps: steps)
        else
          Result.err("LLM module not available")
        end
      end

      def load_plan
        return nil unless File.exist?(PLAN_FILE)

        YAML.safe_load_file(PLAN_FILE)
      rescue StandardError
        nil
      end

      def save_plan
        return unless @current_plan

        FileUtils.mkdir_p(File.dirname(PLAN_FILE))
        File.write(PLAN_FILE, @current_plan.to_yaml)
      end

      def archive_plan
        return unless @current_plan

        history = load_history
        history << @current_plan.merge(archived_at: Time.now.iso8601)
        history = history.last(50)

        FileUtils.mkdir_p(File.dirname(PLAN_HISTORY))
        File.write(PLAN_HISTORY, history.to_yaml)
      end

      def load_history
        return [] unless File.exist?(PLAN_HISTORY)

        YAML.safe_load_file(PLAN_HISTORY) || []
      rescue StandardError
        []
      end
    end

    # Engine - 8-phase workflow orchestrator
    # Orchestrates: discover → analyze → ideate → design → implement → validate → deliver → reflect
    module Engine
      extend self

      PHASES = %i[discover analyze ideate design implement validate deliver reflect].freeze

      def phases
        @phases ||= begin
          config = load_config
          config['phases'] || default_phases
        end
      end

      def transitions
        @transitions ||= begin
          config = load_config
          config['transitions'] || {}
        end
      end

      def start_workflow(session)
        Result.try do
          session.metadata[:workflow] ||= {}
          session.metadata[:workflow][:current_phase] = :discover
          session.metadata[:workflow][:phase_history] = []
          session.metadata[:workflow][:started_at] = Time.now.iso8601
          session
        end
      end

      def current_phase(session)
        session.metadata.dig(:workflow, :current_phase) || :discover
      end

      def advance_phase(session, outputs: {})
        Result.try do
          current = current_phase(session)
          current_idx = PHASES.index(current)
          
          raise "Already at final phase" if current_idx.nil? || current_idx >= PHASES.size - 1

          next_phase = PHASES[current_idx + 1]
          transition_key = "#{current}_to_#{next_phase}"
          gate = transitions[transition_key] || transitions[transition_key.to_s]

          record_transition(session, current, next_phase, gate: gate, outputs: outputs)
          session.metadata[:workflow][:current_phase] = next_phase
          
          { phase: next_phase, gate: gate, previous: current }
        end
      end

      def phase_questions(phase)
        Result.try do
          questions_config = load_questions
          phase_data = questions_config[phase.to_s] || questions_config[phase]
          
          {
            phase: phase,
            purpose: phase_data&.dig('purpose'),
            questions: phase_data&.dig('questions') || [],
            note: phase_data&.dig('note')
          }
        end
      end

      def execute_phase(session, phase, context: {})
        Result.try do
          raise "Invalid phase: #{phase}" unless PHASES.include?(phase.to_sym)

          phase_data = phases.find { |p| (p['id'] || p[:id]).to_sym == phase.to_sym }
          questions = phase_questions(phase).value_or({})
          
          trigger_hook(:before_phase, phase: phase, session: session, context: context)

          result = {
            phase: phase,
            introspection: phase_data&.dig('introspection') || phase_data&.dig(:introspection),
            questions: questions[:questions],
            purpose: questions[:purpose],
            outputs: phase_data&.dig('outputs') || phase_data&.dig(:outputs) || []
          }

          trigger_hook(:after_phase, phase: phase, session: session, result: result)
          
          result
        end
      end

      def record_transition(session, from, to, gate: nil, outputs: {})
        session.metadata[:workflow][:phase_history] ||= []
        session.metadata[:workflow][:phase_history] << {
          from: from,
          to: to,
          gate: gate,
          outputs: outputs,
          timestamp: Time.now.iso8601
        }
      end

      def phase_history(session)
        session.metadata.dig(:workflow, :phase_history) || []
      end

      def can_advance?(session)
        current = current_phase(session)
        current_idx = PHASES.index(current)
        current_idx && current_idx < PHASES.size - 1
      end

      private

      def load_config
        path = File.join(MASTER.root, 'data', 'phases.yml')
        YAML.safe_load_file(path, permitted_classes: [Symbol])
      rescue Errno::ENOENT
        {}
      end

      def load_questions
        path = File.join(MASTER.root, 'data', 'questions.yml')
        YAML.safe_load_file(path, permitted_classes: [Symbol])
      rescue Errno::ENOENT
        {}
      end

      def default_phases
        [
          { id: :discover, name: 'Discover', gate: 'requirements_clear' },
          { id: :analyze, name: 'Analyze', gate: 'codebase_understood' },
          { id: :ideate, name: 'Ideate', gate: 'options_explored' },
          { id: :design, name: 'Design', gate: 'design_approved' },
          { id: :implement, name: 'Implement', gate: 'code_complete' },
          { id: :validate, name: 'Validate', gate: 'quality_verified' },
          { id: :deliver, name: 'Deliver', gate: 'user_satisfied' },
          { id: :reflect, name: 'Reflect', gate: 'learnings_captured' }
        ]
      end

      def trigger_hook(event, **data)
        return unless defined?(Hooks)
        Hooks.run(event, data)
      rescue StandardError => e
        nil
      end
    end

    # Convergence - Detect plateaus, oscillations, and diminishing returns
    # Prevents infinite loops and wasted compute
    module Convergence
      PLATEAU_WINDOW = 3
      MIN_DELTA = 0.02
      MAX_ITERATIONS = 25
      DIFF_THRESHOLD = 0.02

      class << self
        def track(history, current_metrics)
          history << current_metrics.merge(timestamp: Time.now)
          history.shift if history.size > MAX_ITERATIONS

          {
            iteration: history.size,
            delta: calculate_delta(history),
            plateau: plateau?(history),
            oscillating: oscillating?(history),
            should_stop: should_stop?(history),
            reason: stop_reason(history),
          }
        end

        def calculate_delta(history)
          return 1.0 if history.size < 2

          prev = history[-2]
          curr = history[-1]

          deltas = []
          %i[violations complexity coverage score].each do |metric|
            if prev[metric] && curr[metric] && prev[metric] != 0
              deltas << ((curr[metric] - prev[metric]).abs / prev[metric].to_f)
            end
          end

          deltas.empty? ? 0.0 : deltas.sum / deltas.size
        end

        def plateau?(history)
          return false if history.size < PLATEAU_WINDOW

          recent = history.last(PLATEAU_WINDOW)
          deltas = recent.each_cons(2).map do |a, b|
            score_diff(a, b)
          end

          deltas.all? { |d| d.abs < MIN_DELTA }
        end

        def oscillating?(history)
          return false if history.size < 4

          recent = history.last(4)
          scores = recent.map { |h| h[:score] || h[:violations] || 0 }

          (scores[0] - scores[2]).abs < MIN_DELTA &&
            (scores[1] - scores[3]).abs < MIN_DELTA &&
            (scores[0] - scores[1]).abs > MIN_DELTA
        end

        def oscillating_diffs?(history)
          return false if history.size < 4
          return false unless history.last(4).all? { |h| h[:diff] }
          
          recent_diffs = history.last(4).map { |h| h[:diff] }
          
          similarity_03 = diff_similarity(recent_diffs[0], recent_diffs[2])
          similarity_13 = diff_similarity(recent_diffs[1], recent_diffs[3])
          
          similarity_03 > 0.9 && similarity_13 > 0.9
        end

        def diff_similarity(diff1, diff2)
          return 1.0 if diff1 == diff2
          return 0.0 if diff1.nil? || diff2.nil?
          
          max_len = [diff1.length, diff2.length].max
          return 0.0 if max_len == 0
          
          unless defined?(Utils) && Utils.respond_to?(:levenshtein)
            return 0.0
          end
          
          distance = Utils.levenshtein(diff1, diff2)
          1.0 - (distance.to_f / max_len)
        end

        def should_stop?(history)
          return false if history.empty?

          latest = history.last

          return true if latest[:violations]&.zero?
          return true if plateau?(history)
          return true if history.size >= MAX_ITERATIONS
          return true if oscillating?(history)
          return true if oscillating_diffs?(history)

          false
        end

        def stop_reason(history)
          return nil unless should_stop?(history)

          latest = history.last

          if latest[:violations]&.zero?
            :converged
          elsif history.size >= MAX_ITERATIONS
            :max_iterations
          elsif oscillating?(history)
            :oscillation
          elsif oscillating_diffs?(history)
            :oscillation_diff
          elsif plateau?(history)
            :plateau
          end
        end

        def analyze_oscillation(history)
          return nil unless oscillating?(history)

          recent = history.last(4)
          {
            pattern: recent.map { |h| h[:violations] || h[:score] },
            suggestion: "Try different approach or freeze current state",
            cycles_detected: detect_cycle_length(history),
          }
        end

        def summary(history)
          return "No history" if history.empty?

          first = history.first
          last = history.last
          improvement = if first[:violations] && last[:violations] && first[:violations] > 0
                          ((first[:violations] - last[:violations]) / first[:violations].to_f * 100).round(1)
                        else
                          0
                        end

          "#{history.size} iterations, #{improvement}% improvement, " \
            "#{last[:violations] || 'n/a'} violations remaining"
        end

        def content_hash(path)
          require 'digest'
          files = Dir.glob(File.join(path, 'lib', '**', '*.rb'))
          content = files.sort.map { |f| File.read(f) rescue '' }.join
          Digest::SHA256.hexdigest(content)
        end

        def change_ratio(content1, content2)
          return 0.0 if content1 == content2
          
          max_len = 10_000
          str1 = content1[0, max_len]
          str2 = content2[0, max_len]
          
          distance = Utils.levenshtein(str1, str2)
          max_length = [str1.length, str2.length].max
          return 1.0 if max_length == 0
          
          distance.to_f / max_length
        end

        def audit(path, compare_ref: 'HEAD~5')
          features = extract_features(path)
          {
            current_count: features.size,
            features: features
          }
        end

        def extract_features(path)
          files = Dir.glob(File.join(path, 'lib', '**', '*.rb'))
          features = []

          files.each do |file|
            content = File.read(file) rescue next
            content.scan(/(?:class|module)\s+(\w+)/) { |m| features << m[0] }
            content.scan(/def\s+(\w+)/) { |m| features << m[0] }
          end

          features.uniq
        end

        private

        def score_diff(a, b)
          sa = a[:score] || (100 - (a[:violations] || 0))
          sb = b[:score] || (100 - (b[:violations] || 0))
          (sb - sa) / [sa.abs, 1].max.to_f
        end

        def detect_cycle_length(history)
          return nil if history.size < 4

          scores = history.map { |h| h[:score] || h[:violations] || 0 }

          (2..history.size / 2).each do |len|
            cycle = scores.last(len * 2)
            first_half = cycle.first(len)
            second_half = cycle.last(len)

            if first_half.zip(second_half).all? { |a, b| (a - b).abs < MIN_DELTA }
              return len
            end
          end

          nil
        end
      end
    end
  end

  # Backward compatibility aliases
  Planner = Workflow::Planner
  WorkflowEngine = Workflow::Engine
  Convergence = Workflow::Convergence
  Converge = Workflow::Convergence
  
  # Backward compatibility for PlannerHelper module
  module PlannerHelper
    extend self
    
    def parse_plan(text)
      Workflow::Planner.parse_plan(text)
    end
    
    def generate_plan(goal, max_steps: 10)
      Workflow::Planner.generate_plan(goal, max_steps: max_steps)
    end
  end
end
