# frozen_string_literal: true

module MASTER
  # InteractiveShell - Interactive shell mixing Unix commands with MASTER commands
  # Ported from MASTER v1 cli.rb shell_mode
  class InteractiveShell
    UNIX_COMMANDS = %w[ls cd pwd cat grep find wc head tail tree file stat].freeze

    attr_reader :context

    def initialize
      @context = {
        cwd: Dir.pwd,
        history: [],
        last_result: nil
      }
    end

    def run
      puts UI.bold("MASTER Interactive Shell")
      puts UI.dim("Mix Unix commands with MASTER commands. Type 'help' for commands, 'exit' to quit.\n")

      loop do
        print prompt
        input = $stdin.gets&.chomp&.strip
        break if input.nil?

        # Add to history
        @context[:history] << input unless input.empty?

        result = execute(input)
        @context[:last_result] = result

        break if result == :exit
      end

      puts UI.dim("\nShell session ended")
    end

    def execute(input)
      return if input.empty?

      case input
      when "exit", "quit", "q"
        return :exit
      when "help", "?"
        show_help
      when "history"
        show_history
      when /^cd\s+(.+)$/
        change_directory($1)
      when /^(ls|pwd|tree|find|cat|grep|wc|head|tail|file|stat)\b/
        execute_unix_command(input)
      when /^scan\s+(.+)$/
        scan_file($1)
      when /^analyze\s+(.+)$/
        analyze_file($1)
      when /^fix\s+(.+)$/
        fix_file($1)
      when /^session\s+(.+)$/
        session_command($1)
      when /^ask\s+(.+)$/
        ask_llm($1)
      else
        # Treat unmatched input as natural language query for better UX
        ask_llm(input)
      end
    end

    private

    def prompt
      dir = @context[:cwd].sub(ENV['HOME'] || '', '~')
      "master:#{dir}$ "
    end

    def show_help
      puts <<~HELP
        MASTER Interactive Shell - Available Commands:

        Unix Commands:
          ls, pwd, cd, cat, grep, find, wc, head, tail, tree, file, stat

        MASTER Commands:
          scan <file>       Scan file for issues
          analyze <file>    Deep analysis with LLM
          fix <file>        Auto-fix issues in file
          session <cmd>     Session management (info, save, list)
          ask <question>    Ask LLM a question (optional - any text is treated as a question)
          history           Show command history

        Control:
          help, ?           Show this help
          exit, quit, q     Exit shell

        Tip: You can ask questions directly without the 'ask' command.
             Example: Just type "hello, what's up?" instead of "ask hello, what's up?"
      HELP
    end

    def show_history
      @context[:history].each_with_index do |cmd, i|
        puts "  #{i + 1}  #{cmd}"
      end
    end

    def change_directory(path)
      expanded_path = File.expand_path(path, @context[:cwd])
      if Dir.exist?(expanded_path)
        @context[:cwd] = expanded_path
        Dir.chdir(expanded_path)
      else
        puts "Error: Directory not found: #{path}"
      end
    end

    def execute_unix_command(cmd)
      result = Shell.execute(cmd)
      if result.ok?
        puts result.value
      else
        UI.error(result.error)
      end
    end

    def scan_file(path)
      return UI.error("File not found: #{path}") unless File.exist?(path)

      puts UI.dim("Scanning #{path}...")
      if defined?(Engine)
        result = Engine.scan(path)
        if result.ok?
          issues = result.value[:issues]
          if issues.empty?
            puts UI.green("✓ No issues found")
          else
            puts "\nFound #{issues.size} issues:"
            issues.each do |issue|
              puts "  #{UI.icon(:warning)} #{issue[:message]}"
            end
          end
        else
          UI.error(result.error)
        end
      else
        UI.error("Engine module not available")
      end
    end

    def analyze_file(path)
      return UI.error("File not found: #{path}") unless File.exist?(path)

      puts UI.dim("Analyzing #{path}...")
      content = File.read(path)

      prompt = "Analyze this code and provide insights:\n\n#{content[0..2000]}"
      result = LLM.ask(prompt, tier: :smart)

      if result.ok?
        puts "\n#{result.value[:content]}\n"
      else
        UI.error(result.error)
      end
    end

    def fix_file(path)
      return UI.error("File not found: #{path}") unless File.exist?(path)

      puts UI.dim("Fixing #{path}...")
      if defined?(AutoFixer)
        fixer = AutoFixer.new(mode: :moderate)
        result = fixer.fix(path)
        if result.ok?
          UI.success("Fixed: #{path}")
        else
          UI.error(result.error)
        end
      else
        UI.error("AutoFixer not available")
      end
    end

    def session_command(cmd)
      case cmd
      when "info"
        session = Session.current
        puts "\nSession Info:"
        puts "  ID: #{UI.truncate_id(session.id)}"
        puts "  Messages: #{session.message_count}"
        puts "  Cost: #{UI.currency(session.total_cost)}"
      when "save"
        Session.current.save
        UI.success("Session saved")
      when "list"
        sessions = Memory.list_sessions
        puts "\nSaved Sessions (#{sessions.size}):"
        sessions.last(10).each do |id|
          puts "  #{UI.truncate_id(id)}"
        end
      else
        UI.warn("Unknown session command. Use: info, save, list")
      end
    end

    def ask_llm(question)
      puts UI.dim("Asking LLM...")
      result = LLM.ask(question, tier: :fast)

      if result.ok?
        puts "\n#{result.value[:content]}\n"
      else
        UI.error(result.error)
      end
    end
  end

  # GHHelper - GitHub CLI integration for PR creation and git operations
  module GHHelper
    class << self
      def create_pr(title:, body:, draft: true)
        cmd = ["gh", "pr", "create"]
        cmd << "--title" << title
        cmd << "--body" << body
        cmd << "--draft" if draft

        system(*cmd)
      end

      def create_pr_with_context(title, description, files_changed)
        body = <<~BODY
          #{description}

          ## Files Changed
          #{files_changed.map { |f| "- `#{f}`" }.join("\n")}

          ## Automated Tests
          - [ ] Syntax validation passed
          - [ ] No new violations introduced
          - [ ] All existing tests pass

          ---
          *Created by MASTER2 CLI*
        BODY

        create_pr(title: title, body: body)
      end

      def pr_status
        `gh pr status --json number,title,state`
      end

      def current_branch
        `git branch --show-current`.strip
      end

      def has_uncommitted_changes?
        !`git status --porcelain`.strip.empty?
      end

      def commit_and_push(message, files = nil)
        if files
          system("git", "add", *files)
        else
          system("git", "add", "-A")
        end

        system("git", "commit", "-m", message)
        system("git", "push")
      end

      def gh_available?
        system("which gh > /dev/null 2>&1")
      end
    end
  end
end
