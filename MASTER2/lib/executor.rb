# frozen_string_literal: true

require "json"
require "open3"
require "yaml"
require "rbconfig"
require "fileutils"
require "uri"
require_relative "executor/step_loop"
require_relative "executor/plan"
require_relative "executor/convention_extractor"
require_relative "executor/react"
require_relative "executor/preact"
require_relative "executor/rewoo"
require_relative "executor/reflexion"
require_relative "executor/tools"
require_relative "executor/context"
require_relative "executor/grounded_context"

module MASTER
  class Executor
    MAX_STEPS = 15
    MAX_HISTORY_SIZE = 100
    WALL_CLOCK_LIMIT_SECONDS = 120 # seconds

    # Magic number constants extracted for clarity (Phase 5 - Style compliance)
    MAX_BROWSE_CONTENT = 5000
    MAX_FILE_CONTENT = 3000
    MAX_CURL_CONTENT = 2000
    MAX_LLM_RESPONSE_PREVIEW = 1000
    MAX_SHELL_OUTPUT = 1000
    MAX_PARSE_FALLBACK_LENGTH = 100

    COMPLETION_PATTERN = /^(ANSWER|DONE|COMPLETE):\s*/i

    PATTERNS = %i[react pre_act rewoo reflexion].freeze
    SYSTEM_PROMPT_FILE = File.join(__dir__, "..", "data", "system_prompt.yml")

    # Protected paths that cannot be written to
    PROTECTED_WRITE_PATHS = %w[
      data/constitution.yml
      /etc/
      /usr/
      /dev/
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
      self_test: { desc: "Run self-test on MASTER", usage: "self_test" },
    }.freeze

    attr_reader :history, :step, :pattern, :plan, :reflections, :max_steps

    # Class method entry point
    def self.call(goal, **)
      new.call(goal, **)
    end

    # Build formatted tool list for prompts (ONE_SOURCE)
    def self.tool_list_text
      TOOLS.map { |k, v| "  #{k}: #{v[:desc]}" }.join("\n")
    end

    def initialize(max_steps: MAX_STEPS)
      @max_steps = max_steps
      @pattern = :react
    end

    include StepLoop
    include ExecutionContext
    include ToolDispatch
    include React
    include PreAct
    include ReWOO
    include Reflexion

    def call(goal, pattern: :auto, tier: nil)
      Logging.dmesg_log("executor", message: "ENTER executor.call")
      @history = []
      @reflections = []
      @plan = []
      @step = 0
      @pattern = pattern == :auto ? select_pattern(goal) : pattern

      # Quick path: simple queries
      return direct_ask(goal, tier: tier) if simple_query?(goal)

      UI.dim("   Pattern: #{@pattern}") if ENV["DEBUG"]

      result = execute_pattern(@pattern, goal, tier: tier || :strong)

      # Fallback to simpler patterns if primary fails (use retriable? for smart fallback)
      if result.err? && result.retriable? && @pattern != :react
        UI.warn("Pattern #{@pattern} failed, falling back to :react")
        @step = 0
        @history = []
        result = execute_pattern(:react, goal, tier: tier || :strong)
      end

      # Final fallback to direct if all else fails
      unless result.ok?
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
        raise Result::Error,
              "Timed out after #{elapsed.round}s (#{@step} steps). Last observation: #{best_answer[0..200]}"
      end
    end

    # Pattern selection heuristics - local regex first, LLM only for ambiguous cases
    def select_pattern(goal)
      g = goal.to_s.strip.downcase

      # Direct: greetings, chitchat, simple one-word queries — no LLM cost
      if g.match?(/\A(hi|hello|hey|thanks|thank you|bye|quit|exit|help|version|clear|what is master|what are you)\b.{0,60}\z/i)
        return :direct
      end
      if g.length < 20 && !g.match?(/\b(fix|refactor|scan|analyze|build|create|update|debug|write|read|find)\b/)
        return :direct
      end

      # Reflexion: correctness-critical keywords
      return :reflexion if g.match?(/\b(fix|debug|repair|refactor|correct|safe|security|validate|test)\b/)

      # PreAct: clear multi-step plans
      return :pre_act if g.match?(/\b(then|step \d|phase \d|first.*then|build.*deploy|create.*and then)\b/)

      # ReWOO: pure research/comparison (no tools needed)
      if g.match?(/\b(compare|explain|summarize|research|what is|how does|why is|difference between)\b/) && !g.match?(/\b(file|code|write|fix)\b/)
        return :rewoo
      end

      # Sanitize for LLM call — prevent prompt injection
      sanitized_goal = goal.to_s.gsub(/[\r\n]+/, " ").strip.slice(0, 500)

      prompt = <<~CLASSIFY
        You are a task router. Given a user's goal, pick the best execution pattern.

        PATTERNS:
        - react: General exploration, unknown tasks, tool use with observation loops
        - pre_act: Multi-step plans with clear sequential phases (build X then Y then Z)
        - rewoo: Pure reasoning, research, comparison — minimal tool use, cost-efficient
        - reflexion: Tasks requiring correctness — fixing, debugging, refactoring, safety-critical work

        SPECIAL:
        - direct: Simple questions, chitchat, greetings, no tools needed

        USER GOAL: "#{sanitized_goal}"

        Respond with ONLY one word: #{(PATTERNS + [:direct]).join(', ')}
      CLASSIFY

      result = LLM.ask(prompt, tier: :cheap)

      if result.ok?
        chosen = result.value[:content]&.strip&.downcase&.to_sym
        return chosen if chosen && (PATTERNS.include?(chosen) || chosen == :direct)
      end

      :react
    rescue StandardError
      :react
    end

    private

    # Record a step into history, bounding size to MAX_HISTORY_SIZE
    def record_history(entry)
      @history << entry
      @history.shift if @history.size > MAX_HISTORY_SIZE
    end

    # Basic completion verification: response has substance and echoes goal keywords
    def verify_completion(goal, response)
      return true if response.length > 50 # basic sanity

      keywords = goal.scan(/\b\w{4,}\b/).first(5)
      keywords.any? { |kw| response.downcase.include?(kw.downcase) }
    end

    # Self-verify by running test files related to modified files
    def self_verify(modified_files)
      test_files = modified_files.grep(/test_|_spec\.rb/)
      test_files += Dir.glob("test/test_*.rb").first(3) if test_files.empty?
      return if test_files.empty?

      UI.dim("self-verify: running #{test_files.size} test(s)")
      result = defined?(Shell) ? Shell.run("ruby -Itest #{test_files.first}") : nil
      UI.warn("self-verify: tests failed") if result && !result.ok?
    end

    def simple_query?(_goal)
      @pattern == :direct
    end

    def direct_ask(goal, tier: nil)
      system_msg = ExecutionContext.build_system_message(include_commands: false)

      result = LLM.ask(goal, messages: [
                         { role: "system", content: system_msg },
                       ], stream: true)

      if result.ok?
        Result.ok(
          answer: result.value[:content],
          steps: 0,
          mode: :direct,
          pattern: :direct,
          cost: result.value[:cost],
          streamed: result.value[:streamed],
        )
      else
        result
      end
    end
  end
end
