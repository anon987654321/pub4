# frozen_string_literal: true
require "readline"

module Master
  class CLI
    def initialize
      @principles = Boot.run
      @llm = LLM.new
      @engine = Engine.new(principles: @principles, llm: @llm)
      @cwd = Dir.pwd
    end

    def run
      loop do
        parent = File.basename(File.dirname(@cwd))
        parent = File.basename(@cwd) if parent == "." || parent.empty?
        prompt = "#{parent} main > "
        line = Readline.readline(prompt, true)&.strip
        break if line.nil? || line.empty? && $stdin.eof?
        next if line.empty?
        handle(line)
      end
    end

    private

    def handle(input)
      cmd, *args = input.split
      case cmd&.downcase
      when "quit", "exit", "q" then exit(0)
      when "help", "?" then show_help
      when "principles", "p" then show_principles
      when "scan", "s" then scan_files(args)
      when "cd" then change_dir(args.first)
      when "ls" then list_dir(args.first || ".")
      when "pwd" then puts @cwd
      when "version", "v" then puts "master #{Master::VERSION}"
      when "ask", "a" then ask_llm(args.join(" "))
      else
        puts "Working directory: #{@cwd}\n\n"
        result = @llm.ask(input)
        if result.ok?
          puts result.value
        else
          puts "err: #{result.error}"
        end
      end
    end

    def show_help
      puts <<~HELP
        Commands:
          help, ?          Show this help
          principles, p    List loaded principles
          scan, s <file>   Scan file for issues
          ask, a <prompt>  Send prompt to LLM
          cd <dir>         Change directory
          ls [dir]         List directory
          pwd              Print working directory
          version, v       Show version
          quit, q          Exit
          <anything else>  Chat with LLM
      HELP
    end

    def show_principles
      @principles.each { |p| puts p }
    end

    def scan_files(paths)
      paths.each do |path|
        full = File.expand_path(path, @cwd)
        result = @engine.scan(full)
        if result.ok?
          issues = result.value[:issues]
          if issues.empty?
            puts "  valid: no issues"
          else
            issues.each do |i|
              loc = i[:line] ? "L#{i[:line]}" : "file"
              puts "  warn: #{loc}: #{i[:msg]}"
            end
          end
        else
          puts "  err: #{result.error}"
        end
      end
    end

    def ask_llm(prompt)
      return puts "Usage: ask <prompt>" if prompt.empty?
      result = @llm.ask(prompt)
      puts result.ok? ? result.value : "err: #{result.error}"
    end

    def change_dir(path)
      return puts @cwd unless path
      new_dir = File.expand_path(path, @cwd)
      if Dir.exist?(new_dir)
        @cwd = new_dir
        Dir.chdir(@cwd)
        puts @cwd
      else
        puts "err: not a directory: #{path}"
      end
    end

    def list_dir(path)
      full = File.expand_path(path, @cwd)
      entries = Dir.entries(full).reject { |e| e.start_with?(".") }.sort
      entries.each do |e|
        full_path = File.join(full, e)
        suffix = File.directory?(full_path) ? "/" : ""
        puts "  #{e}#{suffix}"
      end
    rescue => e
      puts "err: #{e.message}"
    end
  end
end
