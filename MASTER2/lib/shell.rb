# frozen_string_literal: true

require "shellwords"
require "open3"

module MASTER
  # Shell integration - zsh-native patterns
  module Shell
    extend self

    BUILTINS = %w[cd pwd echo print printf export alias source].freeze

    ZSH_PREFERRED = {
      "ls" => "ls -F",
      "grep" => "grep --color=auto",
      "cat" => "cat -v",
      "rm" => "rm -i",
      "mv" => "mv -i",
      "cp" => "cp -i"
    }.freeze

    FORBIDDEN = {
      "sudo" => "doas",
      "apt" => "pkg_add",
      "apt-get" => "pkg_add",
      "yum" => "pkg_add",
      "systemctl" => "rcctl",
      "journalctl" => "tail -f /var/log/messages"
    }.freeze

    class << self
      def sanitize(cmd)
        parts = cmd.strip.split(/\s+/)
        return cmd if parts.empty?

        base = parts.first

        # Replace forbidden commands
        if FORBIDDEN.key?(base)
          parts[0] = FORBIDDEN[base]
          return parts.join(" ")
        end

        # Apply zsh preferences
        if ZSH_PREFERRED.key?(base) && parts.size == 1
          return ZSH_PREFERRED[base]
        end

        cmd
      end

      def safe?(cmd)
        dangerous = [
          /rm\s+-rf?\s+\//, />\s*\/dev\/[sh]da/, /dd\s+if=/,
          /mkfs/, /fdisk/, /format\s+[a-z]:/i, /del\s+\/[sq]/i
        ]
        !dangerous.any? { |p| cmd.match?(p) }
      end

      def execute(cmd, timeout: 30)
        return Result.err("Dangerous command blocked") unless safe?(cmd)

        sanitized = sanitize(cmd)
        output = nil
        status = nil
        
        Timeout.timeout(timeout) do
          # Use Open3 for safer shell execution
          output, status = Open3.capture2e(sanitized)
        end

        status&.success? ? Result.ok(output) : Result.err(output || "Command failed")
      rescue Timeout::Error
        Result.err("Command timed out after #{timeout}s")
      rescue StandardError => e
        Result.err(e.message)
      end

      def which(cmd)
        # Use Open3 instead of backticks
        stdout, status = Open3.capture2("which", cmd.to_s)
        status.success? ? stdout.strip : nil
      rescue StandardError
        nil
      end

      def zsh?
        ENV["SHELL"]&.include?("zsh")
      end

      def ensure_openbsd_path!
        paths = %w[/usr/local/bin /usr/X11R6/bin /usr/local/sbin]
        current = ENV["PATH"].to_s.split(":")
        missing = paths - current
        ENV["PATH"] = (missing + current).join(":") if missing.any?
      end
    end
  end

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
        UI.warn("Unknown command: #{input}. Type 'help' for available commands.")
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
          ask <question>    Ask LLM a question
          history           Show command history
          
        Control:
          help, ?           Show this help
          exit, quit, q     Exit shell
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
end

