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
      @git_memory = Memory::GitBacked.new
      @smart_hooks = Git::SmartHooks.new
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
      when "web", "w" then browse_web(args)
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
      # New commands
      when "memory" then handle_memory(args)
      when "hooks" then handle_hooks(args)
      when "voice" then handle_voice(args)
      when "graph" then handle_graph(args)
      when "agent" then handle_agent(args)
      when "meta-evolve" then handle_meta_evolve(args)
      when "test-coverage" then handle_test_coverage
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
          analyze, az <path> LLM analysis of file/dir
          ask, a <prompt>   Send prompt to LLM
          cd <dir>          Change directory
          clean [days]      Purge old cache/sessions (default: 7)
          compress          Compress session memory
          cost, $           Show session cost
          evolve            Self-optimize MASTER code
          fix, f <path>     LLM fix file (with confirmation)
          help, ?           Show this help
          ls [dir]          List directory
          openbsd, bsd <sh> Analyze shell script configs
          persona           Show current persona
          principles, p     List loaded principles
          pwd               Print working directory
          quit, q           Exit
          scan, s <path>    Scan file for basic issues
          serve             Start HTTP API server
          smells, sm <path> Detect code smells (Fowler)
          version, v        Show version
          web, w <url>      Browse URL with headless Chrome
          
        New Features (v50.8):
          memory <cmd>      Git-backed memory (search, patterns, sync)
          hooks <cmd>       Smart pre-commit hooks (install, test, uninstall)
          voice             Voice-to-code interface
          graph [--output]  Generate knowledge graph
          agent <type>      Run principle-specific agents (dry, solid_srp, kiss, perf)
          meta-evolve       Self-improvement: MASTER analyzes own code
          test-coverage     Show test coverage for violations
          
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
      
      # Clean file before processing
      clean_file(full)
      
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
        
        # Show tree if entering a directory with code files
        show_tree(@cwd) if has_code_files?(@cwd)
      else
        puts "err: not a directory: #{path}"
      end
    end

    def show_tree(dir, depth = 0)
      return if depth > 3
      skip = %w[node_modules vendor bundle __pycache__ tmp temp cache .git .svn .hg]
      entries = Dir.entries(dir).reject { |e| e.start_with?(".") || skip.include?(e) }.sort
      
      entries.each do |entry|
        path = File.join(dir, entry)
        if File.directory?(path)
          show_tree(path, depth + 1)
        else
          puts path
        end
      end
    end

    def has_code_files?(dir)
      Dir.glob("#{dir}/*.{rb,py,js,ts,go,rs,sh,yml}").any? ||
      Dir.glob("#{dir}/*/*.{rb,py,js,ts,go,rs,sh,yml}").any?
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

    def browse_web(args)
      return puts "Usage: web <url> [question]" if args.empty?
      
      url = args.shift
      url = "https://#{url}" unless url.start_with?("http")
      question = args.join(" ") if args.any?
      
      puts "web0: loading #{url}"
      
      result = Web.analyze(url, @llm, question)
      if result.ok?
        puts result.value
        puts "\n[#{@llm.cost_summary}]"
      else
        puts "err: #{result.error}"
      end
    end

    def clean_cache(days)
      cutoff = Time.now - (days * 86400)
      cleaned = 0
      
      # Directories to clean
      dirs = [
        File.join(Master::ROOT, "var", "cache"),
        File.join(Master::ROOT, "var", "sessions"),
        File.join(Master::ROOT, "var", "cache", "man"),
        File.join(Master::ROOT, "var", "screenshots")
      ]
      
      dirs.each do |dir|
        next unless Dir.exist?(dir)
        Dir.glob("#{dir}/*").each do |f|
          next unless File.file?(f)
          if File.mtime(f) < cutoff
            File.delete(f)
            cleaned += 1
          end
        end
      end
      
      puts "clean0: removed #{cleaned} files older than #{days} days"
    end

    def clean_file(path)
      content = File.read(path, encoding: "UTF-8")
      original = content.dup
      
      # CRLF → LF
      content.gsub!("\r\n", "\n")
      
      # Trailing whitespace
      content.gsub!(/[ \t]+$/, "")
      
      # Multiple blank lines → single
      content.gsub!(/\n{3,}/, "\n\n")
      
      # Ensure final newline
      content << "\n" unless content.end_with?("\n")
      
      if content != original
        File.write(path, content)
        puts "clean0: sanitized #{File.basename(path)}"
      end
    end

    # New command handlers for v50.8 features

    def handle_memory(args)
      subcommand = args.shift
      
      case subcommand&.downcase
      when "search"
        query = args.join(" ")
        return puts "Usage: memory search <query>" if query.empty?
        
        results = @git_memory.search_similar_violations(principle: query)
        
        if results.empty?
          puts "No matching memories found"
        else
          puts "Found #{results.size} similar decisions:"
          results.each_with_index do |entry, i|
            puts "\n[#{i+1}] #{entry['timestamp']}"
            puts "  File: #{entry['file']}"
            puts "  Violation: #{entry.dig('violation', 'principle')}"
            puts "  Decision: #{entry['decision']}"
          end
        end
        
      when "patterns"
        patterns = @git_memory.get_user_patterns
        
        if patterns.empty?
          puts "No patterns recorded yet"
        else
          puts "User decision patterns:"
          patterns.each do |principle, stats|
            total = stats.values.sum
            puts "\n#{principle}:"
            puts "  Fixed: #{stats[:fixed]} (#{percent(stats[:fixed], total)}%)"
            puts "  Ignored: #{stats[:ignored]} (#{percent(stats[:ignored], total)}%)"
            puts "  Deferred: #{stats[:deferred]} (#{percent(stats[:deferred], total)}%)"
          end
        end
        
      when "sync"
        result = @git_memory.sync_with_remote
        puts result ? "Memory synced with remote" : "Sync failed"
        
      else
        puts "Usage: memory <search|patterns|sync>"
      end
    end

    def handle_hooks(args)
      subcommand = args.shift
      
      case subcommand&.downcase
      when "install"
        result = @smart_hooks.install
        puts result.ok? ? result.value[:message] : "Error: #{result.error}"
        
      when "uninstall"
        result = @smart_hooks.uninstall
        puts result.ok? ? result.value[:message] : "Error: #{result.error}"
        
      when "test"
        result = @smart_hooks.test
        if result.ok?
          puts "Hook test completed:"
          puts "  Files: #{result.value[:files]}"
          puts "  Violations: #{result.value[:violations]}"
          puts "  Cached: #{result.value[:cached]}"
        else
          puts "Error: #{result.error}"
        end
        
      else
        puts "Usage: hooks <install|uninstall|test>"
      end
    end

    def handle_voice(args)
      interface = Voice::Interface.new(llm: @llm)
      
      if args.include?("--transcribe")
        file_index = args.index("--transcribe") + 1
        audio_file = args[file_index]
        
        if audio_file && File.exist?(audio_file)
          result = interface.transcribe_audio(audio_file)
          puts result.ok? ? result.value[:text] : "Error: #{result.error}"
        else
          puts "Error: Audio file not found"
        end
      else
        interface.start_session
      end
    end

    def handle_graph(args)
      output_file = nil
      
      if args.include?("--output")
        output_index = args.index("--output") + 1
        output_file = args[output_index] || "var/graph.json"
      end
      
      # Build graph from current analysis state
      graph = Graph::Knowledge.new
      
      puts "Generating knowledge graph..."
      
      # Scan current directory for Ruby files
      ruby_files = Dir.glob("#{@cwd}/**/*.rb").select { |f| File.file?(f) }
      
      analysis_results = {}
      ruby_files.first(20).each do |file|
        result = @engine.scan(file)
        if result.ok?
          issues = result.value[:issues] || []
          score = [100 - (issues.size * 5), 0].max
          analysis_results[file] = { violations: issues, score: score }
        end
      end
      
      graph.build_from_analysis(analysis_results)
      
      if output_file
        FileUtils.mkdir_p(File.dirname(output_file))
        File.write(output_file, graph.to_json)
        puts "Graph saved to: #{output_file}"
      else
        puts "\nGraph metrics:"
        metrics = graph.calculate_metrics
        metrics.each { |k, v| puts "  #{k}: #{v}" }
      end
    end

    def handle_agent(args)
      agent_type = args.shift
      paths = args
      
      case agent_type&.downcase
      when "dry"
        agent = Agents::PrincipleAgents::DRYAgent.new(llm: @llm)
        files = expand_paths(paths)
        agent.run(files)
        
      when "solid_srp", "srp"
        agent = Agents::PrincipleAgents::SOLIDSRPAgent.new(llm: @llm)
        files = expand_paths(paths)
        agent.run(files)
        
      when "kiss"
        agent = Agents::PrincipleAgents::KISSAgent.new(llm: @llm)
        files = expand_paths(paths)
        agent.run(files)
        
      when "perf", "performance"
        agent = Agents::PrincipleAgents::PerformanceAgent.new(llm: @llm)
        files = expand_paths(paths)
        agent.run(files)
        
      when "list"
        puts "Available agents:"
        puts "  dry         - PRINCIPLE_DRY: Extract duplicate code"
        puts "  solid_srp   - SOLID_SRP: Split god classes"
        puts "  kiss        - PRINCIPLE_KISS: Simplify complex methods"
        puts "  performance - PRINCIPLE_PERFORMANCE: Fix N+1 queries"
        
      when "--all"
        puts "Running all agents..."
        files = expand_paths(paths)
        
        [
          Agents::PrincipleAgents::DRYAgent,
          Agents::PrincipleAgents::SOLIDSRPAgent,
          Agents::PrincipleAgents::KISSAgent,
          Agents::PrincipleAgents::PerformanceAgent
        ].each do |agent_class|
          puts "\n" + "=" * 60
          agent = agent_class.new(llm: @llm)
          agent.run(files)
        end
        
      else
        puts "Usage: agent <dry|solid_srp|kiss|performance|list|--all> [paths]"
      end
    end

    def handle_meta_evolve(args)
      auto_merge = args.include?("--auto-merge")
      
      meta = Evolution::Meta.new(llm: @llm)
      result = meta.evolve(auto_merge: auto_merge)
      
      if result.ok?
        puts result.value[:message]
      else
        puts "Error: #{result.error}"
      end
    end

    def handle_test_coverage
      generator = TestGen::RSpecGenerator.new(llm: @llm)
      coverage = generator.test_coverage
      
      if coverage.empty?
        puts "No test coverage data found"
      else
        puts "Test coverage by principle:"
        coverage.each do |principle, spec_files|
          puts "\n#{principle}:"
          spec_files.each { |f| puts "  - #{f}" }
        end
      end
    end

    def expand_paths(paths)
      return ["."] if paths.empty?
      
      paths.flat_map do |path|
        full = File.expand_path(path, @cwd)
        
        if Dir.exist?(full)
          Dir.glob("#{full}/**/*.rb").select { |f| File.file?(f) }
        elsif File.exist?(full)
          [full]
        else
          []
        end
      end
    end

    def percent(value, total)
      return 0 if total.zero?
      ((value.to_f / total) * 100).round(1)
    end
  end
end
