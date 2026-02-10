# frozen_string_literal: true

module MASTER
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

    # Merged from planner_helper.rb - Parse numbered steps from text into an array
    def self.parse_plan(text)
      return [] if text.nil? || text.empty?
      
      # Extract lines that start with numbers followed by period or parenthesis
      steps = text.scan(/^\s*(\d+)[.)]\s*(.+?)$/m).map { |_num, step| step.strip }
      
      # Remove empty steps
      steps.reject(&:empty?)
    end

    # Merged from planner_helper.rb - Generate a numbered step plan from a goal string
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

      YAML.load_file(PLAN_FILE)
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

      YAML.load_file(PLAN_HISTORY) || []
    rescue StandardError
      []
    end
  end

  # Backward compatibility alias for planner_helper.rb
  module PlannerHelper
    extend self
    
    def parse_plan(text)
      Planner.parse_plan(text)
    end
    
    def generate_plan(goal, max_steps: 10)
      Planner.generate_plan(goal, max_steps: max_steps)
    end
  end
end
