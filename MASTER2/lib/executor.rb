# frozen_string_literal: true

require "json"
require "open3"
require "yaml"
require "rbconfig"

require_relative "executor/react"
require_relative "executor/pre_act"
require_relative "executor/rewoo"
require_relative "executor/reflexion"
require_relative "executor/tools"
require_relative "executor/patterns"
require_relative "executor/context"

module MASTER
  class Executor
    include React
    include PreAct
    include ReWOO
    include Reflexion
    include Tools

    MAX_STEPS = 15
    WALL_CLOCK_LIMIT_SECONDS = 120  # seconds
    MAX_HISTORY_ENTRIES = 50
    MAX_LINTER_RETRIES = 3  # Don't loop more than 3 times on same error
    
    MAX_BROWSE_CONTENT = 5000
    MAX_FILE_CONTENT = 3000
    MAX_CURL_CONTENT = 2000
    MAX_LLM_RESPONSE_PREVIEW = 1000
    MAX_SHELL_OUTPUT = 1000
    SIMPLE_QUERY_LENGTH_THRESHOLD = 200
    MAX_PARSE_FALLBACK_LENGTH = 100
    
    PATTERNS = %i[react pre_act rewoo reflexion].freeze
    SYSTEM_PROMPT_FILE = File.join(__dir__, "..", "data", "system_prompt.yml")
    
    DANGEROUS_PATTERNS = [
      /rm\s+-r[f]?\s+\//,
      />\s*\/dev\/[sh]da/,
      /DROP\s+TABLE/i,
      /FORMAT\s+[A-Z]:/i,
      /mkfs\./,
      /dd\s+if=/,
    ].freeze
    
    PROTECTED_WRITE_PATHS = %w[
      data/constitution.yml
      /etc/
      /usr/
      /sys/
      /proc/
      /dev/
      /boot/
    ].freeze
    
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

    include Tools
    include Patterns
    include Context

    def initialize(max_steps: MAX_STEPS)
      @max_steps = max_steps
      @history = []
      @reflections = []
      @plan = []
      @step = 0
    end

    def call(goal, pattern: :auto, tier: nil)
      @history = []
      @reflections = []
      @plan = []
      @step = 0
      @pattern = pattern == :auto ? select_pattern(goal) : pattern
      
      return direct_ask(goal, tier: tier) if simple_query?(goal)

      UI.dim("  ⚡ Pattern: #{@pattern}") if ENV["DEBUG"]
      
      result = execute_pattern(@pattern, goal, tier: tier || :strong)
      
      if !result.ok? && @pattern != :react
        UI.warn("Pattern #{@pattern} failed, falling back to :react")
        @step = 0
        @history = []
        result = execute_pattern(:react, goal, tier: tier || :strong)
      end
      
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

    def select_pattern(goal)
      return :pre_act if goal.match?(/\b(then|after that|next|finally|step\s*\d|first.*then)\b/i)
      return :pre_act if goal.match?(/\b(build|create|implement|develop)\b.*\b(and|with)\b/i)
      
      return :rewoo if goal.match?(/\b(explain|describe|summarize|compare|analyze)\b/i) &&
                       !goal.match?(/\b(file|code|execute|run)\b/i)
      
      return :reflexion if goal.match?(/\b(fix|debug|correct|improve|refactor)\b/i)
      return :reflexion if goal.match?(/\b(don't break|carefully|safely)\b/i)
      
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
      
      identity = if config["identity"]
        config["identity"] % { version: MASTER::VERSION, platform: RUBY_PLATFORM }
      else
        "You are MASTER v#{MASTER::VERSION}, an autonomous coding assistant."
      end
      
      commands = config["commands"] || <<~CMD
        YOUR COMMANDS: model <name>, models, pattern <name>, budget, selftest, help, exit
      CMD
      
      tone_rules = config.dig("tone")&.take(2)&.join(" ") || "Be concise and direct."
      
      prompt = <<~PROMPT
        
        
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
      
      identity = if config["identity"]
        config["identity"] % { version: MASTER::VERSION, platform: RUBY_PLATFORM }
      else
        "You are MASTER v#{MASTER::VERSION}, an autonomous coding assistant running on #{RUBY_PLATFORM}."
      end
      
      tone = config.dig("tone")&.map { |t| "- #{t}" }&.join("\n") || ""
      
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
      
      project_context = ""
      master_md = File.join(Dir.pwd, "MASTER.md")
      if File.exist?(master_md)
        project_context = "\nPROJECT CONTEXT (from MASTER.md):\n#{File.read(master_md)[0..2000]}\n"
      end

      <<~CONTEXT
        
        TASK: #{goal}
        
        TOOLS AVAILABLE (for autonomous execution):
        
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

  module Prescan
    extend self

    def run(path = MASTER.root)
      puts UI.bold("\n🔍 Prescan")
      puts UI.dim("Understanding codebase state before proceeding...\n")

      results = {
        tree: show_tree(path),
        sprawl: detect_sprawl(path),
        git_status: check_git_status(path),
        recent_commits: show_recent_commits(path)
      }

      warn_if_issues(results)
      results
    end

    private

    def show_tree(path)
      puts UI.dim("Structure:")
      
      if system("which tree > /dev/null 2>&1")
        system("tree -L 3 -I 'node_modules|.git|tmp|vendor' #{path}")
        true
      else
        puts `find #{path} -maxdepth 3 -type d | head -20`
        false
      end
    end

    def detect_sprawl(path)
      large_files = []
      
      Dir.glob(File.join(path, "**", "*.rb")).each do |file|
        lines = File.readlines(file).size
        if lines > 500
          large_files << { file: file, lines: lines }
        end
      end

      if large_files.any?
        puts UI.yellow("\n⚠️  Sprawl detected (#{large_files.size} files > 500 lines):")
        large_files.first(5).each do |f|
          puts "  #{File.basename(f[:file])}: #{f[:lines]} lines"
        end
      end

      large_files
    end

    def check_git_status(path)
      return nil unless system("git -C #{path} rev-parse --git-dir > /dev/null 2>&1")

      status = `git -C #{path} status --porcelain`.strip
      
      if status.empty?
        puts UI.green("\n✓ Git: Clean working tree")
      else
        puts UI.yellow("\n⚠️  Git: Uncommitted changes:")
        puts status.lines.first(5).map { |l| "  #{l}" }
      end

      status
    end

    def show_recent_commits(path)
      return nil unless system("git -C #{path} rev-parse --git-dir > /dev/null 2>&1")

      puts UI.dim("\nRecent commits:")
      system("git -C #{path} log --oneline --decorate -5")
      
      true
    end

    def warn_if_issues(results)
      warnings = []
      
      warnings << "Large files detected" if results[:sprawl]&.any?
      warnings << "Uncommitted changes" if results[:git_status] && !results[:git_status].empty?

      if warnings.any?
        puts UI.yellow("\n⚠️  Issues: #{warnings.join(', ')}")
        puts UI.dim("Consider addressing these before proceeding.\n")
      else
        puts UI.green("\n✓ All clear\n")
      end
    end
  end
end
