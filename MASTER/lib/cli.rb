# frozen_string_literal: true
require "readline"

module Master
  class CLI
    def initialize
      @principles = Boot.run
      @llm = LLM.new
      @engine = Engine.new(principles: @principles, llm: @llm)
      @cwd = Dir.pwd
      @session = Memory::Session.new
    end

    def run
      # Inject previous session context if available
      context = Memory::Session.load_latest_context
      puts "boot> memory: previous session loaded" unless context.empty?
      
      loop do
        parent = File.basename(File.dirname(@cwd))
        parent = File.basename(@cwd) if parent == "." || parent.empty?
        prompt = "#{parent} main > "
        line = Readline.readline(prompt, true)&.strip
        break if line.nil? || line.empty? && $stdin.eof?
        next if line.empty?
        handle(line)
      end
      
      # Save session on exit
      @session.save
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
      when "serve" then start_server
      when "compress" then compress_session
      when "cost", "$" then puts @llm.cost_summary
      else
        @session&.record(:chat, { input: input })
        puts "Working directory: #{@cwd}\n\n"
        result = @llm.ask(input)
        if result.ok?
          puts result.value
          puts "\n[#{@llm.cost_summary}]"
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
          cost, $          Show session cost
          serve            Start HTTP API server
          compress         Compress session memory
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

    def start_server
      puts "Starting HTTP server..."
      Server.start
    end

    def compress_session
      puts "Compressing session..."
      result = @session.compress!
      if result
        puts "Session compressed (#{@session.events.size} events)"
      else
        puts "No events to compress"
      end
    end
  end
end
