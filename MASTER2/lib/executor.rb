# frozen_string_literal: true

require "json"
require "open3"
require "yaml"
require "rbconfig"
require "fileutils"
require "uri"

module MASTER

  class Executor

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
    SIMPLE_QUERY_LENGTH_THRESHOLD = 200
    MAX_PARSE_FALLBACK_LENGTH = 100

    COMPLETION_PATTERN = /^(ANSWER|DONE|COMPLETE):\s*/i.freeze

    PATTERNS = %i[react pre_act rewoo reflexion].freeze
    SYSTEM_PROMPT_FILE = File.join(__dir__, "..", "data", "system_prompt.yml")

    # Dangerous patterns to block (injection prevention)
    # Synchronized with Stages::Guard::DANGEROUS_PATTERNS
    DANGEROUS_PATTERNS = [
      /rm\s+-r[f]?\s+\//,
      />\s*\/dev\/[sh]da/,
      /DROP\s+TABLE/i,
      /FORMAT\s+[A-Z]:/i,
      /mkfs\./,
      /dd\s+if=/,
    ].freeze

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
      ask_llm: "Ask the LLM a question directly",
      web_search: "Search the web for information",
      browse_page: "Browse a URL and extract content",
      memory_search: "Search past interactions and learnings",
      file_read: "Read a file's contents",
      file_write: "Write content to a file",
      analyze_code: "Analyze code for issues and opportunities",
      fix_code: "Auto-fix code violations",
      shell_command: "Run a shell command",
      code_execution: "Execute Ruby code",
      council_review: "Run adversarial council review",
      self_test: "Run self-test on MASTER",
    }.freeze

    attr_reader :history, :step, :pattern, :plan, :reflections, :max_steps

    def initialize(max_steps: MAX_STEPS)
      @max_steps = max_steps
      @history = []
      @reflections = []
      @plan = []
      @step = 0
    end

    # Main entry - auto-selects pattern or uses specified
    def call(goal, pattern: :auto, tier: nil)
      @history = []
      @reflections = []
      @plan = []
      @step = 0
      @pattern = pattern == :auto ? select_pattern(goal) : pattern

      # Quick path: simple queries
      return direct_ask(goal, tier: tier) if simple_query?(goal)

      UI.dim("  ⚡ Pattern: #{@pattern}") if ENV["DEBUG"]

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

    def self.call(goal, **opts)
      new.call(goal, **opts)
    end

    # Pattern selection heuristics
    def select_pattern(goal)
      # Pre-Act: explicit multi-step tasks
      return :pre_act if goal.match?(/\b(then|after that|next|finally|step\s*\d|first.*then)\b/i)
      return :pre_act if goal.match?(/\b(build|create|implement|develop)\b.*\b(and|with)\b/i)

      # ReWOO: cost-sensitive or pure reasoning
      return :rewoo if goal.match?(/\b(explain|describe|summarize|compare|analyze)\b/i) &&
                       !goal.match?(/\b(file|code|execute|run)\b/i)

      # Reflexion: learning/fixing tasks
      return :reflexion if goal.match?(/\b(fix|debug|correct|improve|refactor)\b/i)
      return :reflexion if goal.match?(/\b(don't break|carefully|safely)\b/i)

      # Default: ReAct for exploratory/unknown
      :react
    end

    private

    def simple_query?(goal)
      goal.length < SIMPLE_QUERY_LENGTH_THRESHOLD &&
        !goal.match?(/\b(file|read|write|analyze|fix|search|browse|run|execute|test|review)\b/i) &&
        !goal.match?(/\b(create|update|modify|delete|install|build)\b/i)
    end

    def direct_ask(goal, tier: nil)
      # Use shared system message builder (no commands for brevity)
      system_msg = Context.build_system_message(include_commands: false)

      prompt = <<~PROMPT
        #{system_msg}

        User question: #{goal}
      PROMPT

      result = LLM.ask(prompt, tier: tier || :fast, stream: true)

      if result.ok?
        Result.ok(
          answer: result.value[:content],
          steps: 0,
          mode: :direct,
          pattern: :direct,
          cost: result.value[:cost]
        )
      else
        result
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # ReAct pattern implementation
    # Tight thought-action-observation loop
    # Best for: exploratory tasks, dynamic adaptation, unknown territory
    # ═══════════════════════════════════════════════════════════════════════════
  end
end

require_relative "executor/momentum"
require_relative "executor/react"
require_relative "executor/preact"
require_relative "executor/rewoo"
require_relative "executor/reflexion"
require_relative "executor/tools"
require_relative "executor/context"
