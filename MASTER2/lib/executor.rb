# frozen_string_literal: true

require "json"
require "open3"
require "yaml"
require "rbconfig"
require "fileutils"
require "uri"
require_relative "executor/react"
require_relative "executor/preact"
require_relative "executor/rewoo"
require_relative "executor/reflexion"
require_relative "executor/tools"
require_relative "executor/context"

module MASTER

  class Executor
    # Include pattern modules
    include Context
    include Tools
    include React
    include PreAct
    include ReWOO
    include Reflexion

    MAX_STEPS = 15
    WALL_CLOCK_LIMIT_SECONDS = 120  # seconds
    MAX_HISTORY_ENTRIES = 50
    MAX_LINTER_RETRIES = 3  # Don't loop more than 3 times on same error

    # Magic number constants extracted for clarity (Phase 5 - Style compliance)
    MAX_BROWSE_CONTENT = 5000
    MAX_FILE_CONTENT = 3000
    MAX_CURL_CONTENT = 2000
    MAX_LLM_RESPONSE_PREVIEW = 1000
    MAX_SHELL_OUTPUT = 1000
    MAX_PARSE_FALLBACK_LENGTH = 100

    COMPLETION_PATTERN = /^(ANSWER|DONE|COMPLETE):\s*/i.freeze

    PATTERNS = %i[react pre_act rewoo reflexion].freeze
    SYSTEM_PROMPT_FILE = File.join(__dir__, "..", "data", "system_prompt.yml")

    # Reference to dangerous patterns defined in Stages::Guard
    DANGEROUS_PATTERNS = Stages::Guard::DANGEROUS_PATTERNS

    # Protected paths that cannot be written to
    PROTECTED_WRITE_PATHS = %w[
      data/constitution.yml
      /etc/
      /usr/
      /sys/
      /proc/
      /dev/
      /boot/
    ].freeze

    # All available tools
    TOOLS = {
      ask_llm: { desc: "Ask the LLM a question directly", usage: 'ask_llm "your question"' },
      web_search: { desc: "Search the web for information", usage: 'web_search "query"' },
      browse_page: { desc: "Browse a URL and extract content", usage: 'browse_page "url"' },
      memory_search: { desc: "Search past interactions and learnings", usage: 'memory_search "query"' },
      file_read: { desc: "Read a file's contents", usage: 'file_read "path"' },
      file_write: { desc: "Write content to a file", usage: 'file_write "path" "content"' },
      analyze_code: { desc: "Analyze code for issues and opportunities", usage: 'analyze_code "path"' },
      fix_code: { desc: "Auto-fix code violations", usage: 'fix_code "path"' },
      shell_command: { desc: "Run a shell command", usage: 'shell_command "command"' },
      code_execution: { desc: "Execute Ruby code", usage: "code_execution ```ruby\n  code here\n  ```" },
      council_review: { desc: "Run adversarial council review", usage: 'council_review "text to review"' },
      self_test: { desc: "Run self-test on MASTER", usage: 'self_test' },
    }.freeze

    attr_reader :history, :step, :pattern, :plan, :reflections, :max_steps

    # Class method entry point
    def self.call(goal, **opts)
      new.call(goal, **opts)
    end

    def initialize(max_steps: MAX_STEPS)
      @max_steps = max_steps
      @history = []
      @reflections = []
      @plan = []
      @step = 0
      @pattern = :react  # Default pattern, set properly in call()
    end

    include ExecutionContext
    include ToolDispatch
    include React
    include PreAct
    include ReWOO
    include Reflexion

    def call(goal, pattern: :auto, tier: nil)
      Logging.dmesg_log('executor', message: 'ENTER executor.call')
      @history = []
      @reflections = []
      @plan = []
      @step = 0
      @pattern = pattern == :auto ? select_pattern(goal) : pattern

      # Quick path: simple queries
      return direct_ask(goal, tier: tier) if simple_query?(goal)

      UI.dim("   Pattern: #{@pattern}") if ENV["DEBUG"]

      result = execute_pattern(@pattern, goal, tier: tier || :strong)

      # Fallback to simpler patterns if primary fails
      if !result.ok? && @pattern != :react
        UI.warn("Pattern #{@pattern} failed, falling back to :react")
        @step = 0
        @history = []
        result = execute_pattern(:react, goal, tier: tier || :strong)
      end

      # Final fallback to direct if all else fails
      if !result.ok? && @step > 0
        UI.warn("All patterns failed, attempting direct response")
        result = direct_ask("Given this context, provide the best answer you can:\n\n#{goal}", tier: :fast)
      end

      result
    end

    def execute_pattern(pattern, goal, tier:)
      case pattern
      when :react     then execute_react(goal, tier: tier)
      when :pre_act   then execute_pre_act(goal, tier: tier)
      when :rewoo     then execute_rewoo(goal, tier: tier)
      when :reflexion then execute_reflexion(goal, tier: tier)
      else execute_react(goal, tier: tier)
      end
    end

    def check_timeout!(start_time)
      elapsed = MASTER::Utils.monotonic_now - start_time
      if elapsed > WALL_CLOCK_LIMIT_SECONDS
        best_answer = @history.last&.[](:observation) || "Timed out"
        raise Result::Error.new("Timed out after #{elapsed.round}s (#{@step} steps). Last observation: #{best_answer[0..200]}")
      end
    end

    # Pattern selection heuristics - moved before private
    def select_pattern(goal)
      # Sanitize goal to prevent prompt injection
      sanitized_goal = goal.to_s.gsub(/[\r\n]+/, ' ').strip.slice(0, 500)
      
      prompt = <<~CLASSIFY
        You are a task router. Given a user's goal, pick the best execution pattern.

        PATTERNS:
        - react: General exploration, unknown tasks, tool use with observation loops
        - pre_act: Multi-step plans with clear sequential phases (build X then Y then Z)
        - rewoo: Pure reasoning, research, comparison — minimal tool use, cost-efficient
        - reflexion: Tasks requiring correctness — fixing, debugging, refactoring, safety-critical work

        SPECIAL:
        - direct: Simple questions, chitchat, greetings, no tools needed

        USER GOAL: #{sanitized_goal}

        Respond with ONLY one word: react, pre_act, rewoo, reflexion, or direct
      CLASSIFY

      result = LLM.ask(prompt, tier: :cheap)

      if result.ok?
        chosen = result.value[:content]&.strip&.downcase&.to_sym
        return chosen if chosen && (PATTERNS.include?(chosen) || chosen == :direct)
      end

      # Fallback: if LLM fails or returns garbage, use react
      :react
    rescue StandardError
      :react
    end

    private

    def simple_query?(goal)
      @pattern == :direct
    end

    def direct_ask(goal, tier: nil)
      system_msg = ExecutionContext.build_system_message(include_commands: false)

      result = LLM.ask(goal, messages: [
        { role: "system", content: system_msg }
      ], stream: true)

      if result.ok?
        Result.ok(
          answer: result.value[:content],
          steps: 0,
          mode: :direct,
          pattern: :direct,
          cost: result.value[:cost],
          streamed: result.value[:streamed]
        )
      else
        result
      end
    end
  end
end
