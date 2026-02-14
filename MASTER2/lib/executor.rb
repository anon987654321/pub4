# frozen_string_literal: true

require "json"
require "open3"
require "yaml"
require "rbconfig"

# Load pattern modules
require_relative "executor/react"
require_relative "executor/pre_act"
require_relative "executor/rewoo"
require_relative "executor/reflexion"
require_relative "executor/tools"
require_relative "executor/patterns"
require_relative "executor/context"

module MASTER
  # Executor - Hybrid agent with multiple reasoning patterns
  # Patterns: react, pre_act, rewoo, reflexion
  # Auto-selects best pattern based on task characteristics
  # 
  # NOTE: This file is split across multiple files for readability:
  # - executor/tools.rb - Tool implementations
  # - executor/patterns.rb - Pattern execution methods
  # - executor/context.rb - Context building and response parsing
  class Executor
    include React
    include PreAct
    include ReWOO
    include Reflexion
    include Tools
    include Patterns
    include Context

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
      config = self.class.system_prompt_config
      
      # Build concise system context for direct queries
      identity = if config["identity"]
        config["identity"] % { version: MASTER::VERSION, platform: RUBY_PLATFORM }
      else
        "You are MASTER v#{MASTER::VERSION}, an autonomous coding assistant."
      end
      
      commands = config["commands"] || <<~CMD
        YOUR COMMANDS: model <name>, models, pattern <name>, budget, selftest, help, exit
      CMD
      
      # Tone from config
      tone_rules = config.dig("tone")&.take(2)&.join(" ") || "Be concise and direct."
      
      prompt = <<~PROMPT
        #{identity}
        #{tone_rules}
        
        #{commands.lines.first(8).join}
        
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

    def self.system_prompt_config
      @system_prompt_config ||= if File.exist?(SYSTEM_PROMPT_FILE)
        YAML.safe_load_file(SYSTEM_PROMPT_FILE) rescue {}
      else
        {}
      end
    end

    def build_context(goal)
      config = self.class.system_prompt_config
      history_text = @history.map do |h|
        "Step #{h[:step]}:\nThought: #{h[:thought]}\nAction: #{h[:action]}\nObservation: #{h[:observation]&.[](0..400)}"
      end.join("\n\n")

      tool_list = TOOLS.map { |k, v| "  #{k}: #{v}" }.join("\n")
      
      # Build identity from config or default
      identity = if config["identity"]
        config["identity"] % { version: MASTER::VERSION, platform: RUBY_PLATFORM }
      else
        "You are MASTER v#{MASTER::VERSION}, an autonomous coding assistant running on #{RUBY_PLATFORM}."
      end
      
      # Tone guidelines
      tone = config.dig("tone")&.map { |t| "- #{t}" }&.join("\n") || ""
      
      # Commands from config or inline
      commands = config["commands"] || <<~CMD
        YOUR COMMANDS (what users type at the master> prompt):
          model <name>      Switch LLM model (e.g., model kimi-k2.5)
          models            List available models
          pattern <name>    Switch execution pattern
          budget            Show remaining budget
          selftest          Run self-test
          help              Show all commands
          exit              Exit MASTER (or Ctrl+C twice)
      CMD
      
      # Check for project-specific MASTER.md
      project_context = ""
      master_md = File.join(Dir.pwd, "MASTER.md")
      if File.exist?(master_md)
        project_context = "\nPROJECT CONTEXT (from MASTER.md):\n#{File.read(master_md)[0..2000]}\n"
      end

      <<~CONTEXT
        #{identity}
        
        #{tone.empty? ? "" : "COMMUNICATION STYLE:\n#{tone}\n"}
        #{commands}
        #{project_context}
        TASK: #{goal}
        
        TOOLS AVAILABLE (for autonomous execution):
        #{tool_list}
        
        TOOL FORMAT:
        - ask_llm "your question"
        - web_search "query"
        - browse_page "url"
        - file_read "path"
        - file_write "path" "content"
        - analyze_code "path"
        - fix_code "path"
        - shell_command "command"
        - code_execution ```ruby
          code here
          ```
        - council_review "text to review"
        - memory_search "query"
        - self_test
        
        When complete, respond: ANSWER: your final answer
        
        #{history_text.empty? ? "" : "PREVIOUS STEPS:\n#{history_text}\n"}
        
        Respond with:
        Thought: (brief reasoning)
        Action: (tool invocation or ANSWER: final answer)
      CONTEXT
    end

    def parse_response(text)
      thought = text[/Thought:\s*(.+?)(?=Action:|ANSWER:|DONE:|$)/mi, 1]&.strip || "Continuing"
      action = text[/Action:\s*(.+?)(?=Observation:|Thought:|$)/mi, 1]&.strip ||
               text[/(ANSWER|DONE|COMPLETE):\s*(.+)/mi, 0]&.strip ||
               "ask_llm \"#{text[0..100]}\""

      { thought: thought, action: action }
    end
  end
end
