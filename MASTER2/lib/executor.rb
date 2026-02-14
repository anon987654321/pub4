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
  # Momentum - Track task progress and productivity metrics
  module Momentum
    extend self

    TASKS_PER_XP = 5

    XP = {
      chat: 1,
      refactor: 5,
      evolve: 10,
      fix: 3,
      test: 2
    }.freeze

    LEVELS = [
      { xp: 0, title: "Novice" },
      { xp: 50, title: "Apprentice" },
      { xp: 150, title: "Journeyman" },
      { xp: 300, title: "Expert" },
      { xp: 500, title: "Master" }
    ].freeze

    def fresh
      {
        xp: 0,
        level: 1,
        streak: 0,
        achievements: []
      }
    end

    def state
      @state ||= fresh
    end

    def award(action)
      xp_gain = XP[action] || 1
      multiplier = streak_multiplier
      total_gain = (xp_gain * multiplier).to_i
      
      state[:xp] += total_gain
      state[:level] = calculate_level(state[:xp])
      
      { xp_gained: total_gain, total_xp: state[:xp], level: state[:level] }
    end

    def title
      LEVELS.reverse.find { |l| state[:xp] >= l[:xp] }&.[](:title) || "Novice"
    end

    def streak_multiplier
      case state[:streak]
      when 0..2 then 1.0
      when 3..6 then 1.2
      when 7..13 then 1.5
      else 2.0
      end
    end

    def track(action, result: nil)
      # Track action and update streak if successful
      if result&.ok? || result.nil?
        state[:streak] += 1
      else
        state[:streak] = 0
      end
      
      Result.ok(action: action, tracked: true)
    end

    def summary
      { 
        tasks_completed: state[:xp] / TASKS_PER_XP,
        streak: state[:streak],
        level: state[:level],
        title: title
      }
    end

    private

    def calculate_level(xp)
      LEVELS.count { |l| xp >= l[:xp] }
    end
  end

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
        config["identity"] % { version: MASTER::VERSION, platform: RUBY_PLATFORM, ruby_version: RUBY_VERSION }
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
  end
end
