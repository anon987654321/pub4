# frozen_string_literal: true
require "readline"

module Master
  class CLI
    def initialize
      @principles = Boot.run
      @llm = LLM.new(principles: @principles)
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
      when "analyze", "az" then analyze_files(args)
      when "smells", "sm" then smell_check(args)
      when "openbsd", "bsd" then openbsd_check(args)
      when "fix", "f" then fix_file(args.first)
      when "evolve" then evolve_self
      when "cd" then change_dir(args.first)
      when "ls" then list_dir(args.first || ".")
      when "pwd" then puts @cwd
      when "version", "v" then puts "master #{Master::VERSION}"
      when "ask", "a" then ask_llm(args.join(" "))
      when "serve" then start_server
      when "compress" then compress_session
      when "clean" then clean_cache(args.first&.to_i || 7)
      when "cost", "$" then puts @llm.cost_summary
      when "persona" then puts "#{PERSONA[:name]}: #{PERSONA[:traits].join(', ')}"
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
          help, ?           Show this help
          principles, p     List loaded principles
          scan, s <path>    Scan file for basic issues
          analyze, az <path> LLM analysis of file/dir
          smells, sm <path> Detect code smells (Fowler)
          openbsd, bsd <sh> Analyze shell script configs
          fix, f <path>     LLM fix file (with confirmation)
          evolve            Self-optimize MASTER code
          ask, a <prompt>   Send prompt to LLM
          cost, $           Show session cost
          clean [days]      Purge cache/sessions older than N days (default: 7)
          persona           Show current persona
          serve             Start HTTP API server
          compress          Compress session memory
          cd <dir>          Change directory
          ls [dir]          List directory
          pwd               Print working directory
          version, v        Show version
          quit, q           Exit
          <anything else>   Chat with LLM
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
      puts "\n[#{@llm.cost_summary}]" if result.ok?
    end

    def analyze_files(paths)
      return puts "Usage: analyze <path>" if paths.empty?
      
      paths.each do |path|
        full = File.expand_path(path, @cwd)
        
        if Dir.exist?(full)
          # Directory - list files and summarize
          files = Dir.glob("#{full}/**/*").select { |f| File.file?(f) }
          puts "proc0: #{full} (directory, #{files.size} files)"
          
          summary = files.first(20).map do |f|
            ext = File.extname(f)
            lines = File.read(f, encoding: "UTF-8").lines.size rescue 0
            "  #{File.basename(f)} (#{lines} lines)"
          end.join("\n")
          
          prompt = <<~PROMPT
            Analyze this directory structure and provide insights:
            
            Directory: #{full}
            Files (#{files.size} total, showing first 20):
            #{summary}
            
            Provide:
            1. What this directory/project appears to be
            2. Key files to examine
            3. Potential issues or improvements
          PROMPT
        elsif File.exist?(full)
          # Single file
          content = File.read(full, encoding: "UTF-8")
          lines = content.lines.size
          bytes = content.bytesize
          ext = File.extname(full).downcase
          lang = { ".rb" => "ruby", ".py" => "python", ".js" => "javascript",
                   ".ts" => "typescript", ".go" => "go", ".rs" => "rust",
                   ".sh" => "shell", ".yml" => "yaml", ".yaml" => "yaml" }[ext] || "text"
          
          puts "proc0: #{full} (#{lang}, #{lines} lines, #{bytes} bytes)"
          
          # Truncate if too large
          if content.size > 50000
            content = content[0..50000] + "\n\n[TRUNCATED - file too large]"
          end
          
          principles_list = @principles.first(10).map(&:name).join(", ")
          
          prompt = <<~PROMPT
            Analyze this #{lang} file against these principles: #{principles_list}
            
            File: #{File.basename(full)}
            ```#{lang}
            #{content}
            ```
            
            Provide:
            1. Summary of what this file does
            2. Principle violations found (with line numbers)
            3. Specific improvement suggestions
            4. Overall quality assessment (1-10)
          PROMPT
        else
          puts "err: not found: #{path}"
          next
        end
        
        result = @llm.ask(prompt, tier: :code)
        if result.ok?
          puts result.value
          puts "\n[#{@llm.cost_summary}]"
        else
          puts "err: #{result.error}"
        end
      end
    end

    def fix_file(path)
      return puts "Usage: fix <path>" unless path
      full = File.expand_path(path, @cwd)
      return puts "err: not found: #{path}" unless File.exist?(full)
      
      content = File.read(full, encoding: "UTF-8")
      ext = File.extname(full).downcase
      lang = { ".rb" => "ruby", ".py" => "python", ".js" => "javascript",
               ".sh" => "shell", ".yml" => "yaml" }[ext] || "text"
      
      puts "proc0: #{full} (#{lang}, #{content.lines.size} lines)"
      puts "Generating fix..."
      
      principles_list = @principles.first(10).map(&:name).join(", ")
      
      prompt = <<~PROMPT
        Refactor this #{lang} file to better follow these principles: #{principles_list}
        
        Current code:
        ```#{lang}
        #{content}
        ```
        
        Return ONLY the complete refactored code, no explanations.
        Preserve all functionality. Improve structure and clarity.
      PROMPT
      
      result = @llm.ask(prompt, tier: :code, cache: false)
      unless result.ok?
        puts "err: #{result.error}"
        return
      end
      
      new_content = extract_code(result.value, lang)
      
      # Show diff
      puts "\n--- Changes ---"
      show_diff(content, new_content)
      puts "\n[#{@llm.cost_summary}]"
      
      # Confirm
      print "\nApply changes? [y/N] "
      answer = $stdin.gets&.strip&.downcase
      if answer == "y"
        # Backup
        backup = "#{full}.bak"
        File.write(backup, content)
        File.write(full, new_content)
        puts "fix0: applied (backup: #{backup})"
        @session&.record(:fix, { file: full, backup: backup })
      else
        puts "fix0: cancelled"
      end
    end

    def evolve_self
      puts "evolve0: self-optimization starting..."
      lib_dir = File.join(Master::ROOT, "lib")
      files = Dir.glob("#{lib_dir}/*.rb").sort
      
      puts "evolve0: analyzing #{files.size} core files"
      
      files.each do |file|
        puts "\n--- #{File.basename(file)} ---"
        analyze_files([file])
      end
      
      puts "\nevolve0: analysis complete"
      puts "Use 'fix lib/<file>.rb' to apply improvements"
    end

    def extract_code(response, lang)
      # Extract code from markdown code blocks
      if response =~ /```#{lang}\n(.*?)```/m
        $1
      elsif response =~ /```\n(.*?)```/m
        $1
      else
        response
      end
    end

    def show_diff(old_content, new_content)
      old_lines = old_content.lines
      new_lines = new_content.lines
      
      max_lines = [old_lines.size, new_lines.size].max
      changes = 0
      
      max_lines.times do |i|
        old_line = old_lines[i]&.chomp || ""
        new_line = new_lines[i]&.chomp || ""
        
        if old_line != new_line
          changes += 1
          puts "L#{i+1}:"
          puts "  - #{old_line[0..78]}" if old_line.size > 0
          puts "  + #{new_line[0..78]}" if new_line.size > 0
        end
        
        break if changes > 20  # Limit output
      end
      
      puts "... (#{changes} changes total)" if changes > 20
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

    def smell_check(paths)
      return puts "Usage: smells <path>" if paths.empty?
      
      paths.each do |path|
        full = File.expand_path(path, @cwd)
        return puts "err: not found: #{path}" unless File.exist?(full)
        
        code = File.read(full, encoding: "UTF-8")
        puts "smell0: analyzing #{File.basename(full)} (#{code.lines.size} lines)"
        
        results = Smells.analyze(code, full)
        puts Smells.report(results)
      end
    end

    def openbsd_check(paths)
      return puts "Usage: openbsd <shell-script.sh>" if paths.empty?
      
      paths.each do |path|
        full = File.expand_path(path, @cwd)
        return puts "err: not found: #{path}" unless File.exist?(full)
        
        puts "bsd0: scanning #{File.basename(full)} for embedded configs"
        results = OpenBSD.analyze_shell_file(full, @llm)
        
        if results.empty?
          puts "bsd0: no OpenBSD configs found"
        else
          puts "bsd0: found #{results.size} config(s) with issues"
        end
      end
    end

    def clean_cache(days)
      cutoff = Time.now - (days * 86400)
      cleaned = 0
      
      # Clean cache
      cache_dir = File.join(Master::ROOT, "var", "cache")
      if Dir.exist?(cache_dir)
        Dir.glob("#{cache_dir}/*").each do |f|
          next unless File.file?(f)
          if File.mtime(f) < cutoff
            File.delete(f)
            cleaned += 1
          end
        end
      end
      
      # Clean sessions
      sessions_dir = File.join(Master::ROOT, "var", "sessions")
      if Dir.exist?(sessions_dir)
        Dir.glob("#{sessions_dir}/*").each do |f|
          next unless File.file?(f)
          if File.mtime(f) < cutoff
            File.delete(f)
            cleaned += 1
          end
        end
      end
      
      # Clean man page cache
      man_dir = File.join(Master::ROOT, "var", "cache", "man")
      if Dir.exist?(man_dir)
        Dir.glob("#{man_dir}/*").each do |f|
          next unless File.file?(f)
          if File.mtime(f) < cutoff
            File.delete(f)
            cleaned += 1
          end
        end
      end
      
      puts "clean0: removed #{cleaned} files older than #{days} days"
    end
  end
end
