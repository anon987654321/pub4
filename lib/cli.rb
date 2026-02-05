# frozen_string_literal: true

require 'readline'
require 'fileutils'

module MASTER
  class CLI
    attr_reader :llm, :verbosity

    COMMANDS = %w[
      ask audit cat cd chamber clean clear commit converge cost describe diff
      edit exit git help image log ls persona personas principles pull
      push queue quit read refactor refine review scan smells status tree
      version web
    ].freeze

    HISTORY_FILE = Paths.history

    # Verbosity levels
    VERBOSITY = { low: 0, medium: 1, high: 2 }.freeze

    # ANSI colors
    C_RESET  = "\e[0m"
    C_RED    = "\e[31m"
    C_GREEN  = "\e[32m"
    C_YELLOW = "\e[33m"
    C_CYAN   = "\e[36m"
    C_DIM    = "\e[2m"

    def initialize
      @llm = LLM.new
      @server = nil
      @root = Dir.pwd
      @verbosity = :high
      @boot_time = Time.now
      @last_tokens = { input: 0, output: 0 }
      @last_cached = false
      setup_completion
      load_history
    end

    def run
      ask_verbosity
      start_server
      repl
    end

    def trace(msg)
      puts "#{C_DIM}#{msg}#{C_RESET}" if @verbosity == :high
    end

    def info(msg)
      puts "#{C_DIM}#{msg}#{C_RESET}" if VERBOSITY[@verbosity] >= 1
    end

    def process_input(input)
      input = input.to_s.strip
      return nil if input.empty?

      result = handle(input)
      broadcast(result) if result
      result
    end

    private

    def setup_completion
      Readline.completion_proc = proc do |s|
        COMMANDS.grep(/^#{Regexp.escape(s)}/)
      end
      Readline.completion_append_character = ' '
    end

    def load_history
      return unless File.exist?(HISTORY_FILE)

      File.readlines(HISTORY_FILE).last(100).each do |line|
        Readline::HISTORY.push(line.chomp)
      end
    rescue
      # Ignore history errors
    end

    def save_history
      File.open(HISTORY_FILE, 'a') do |f|
        Readline::HISTORY.to_a.last(100).each { |line| f.puts(line) }
      end
    rescue
      # Ignore history errors
    end

    def ask_verbosity
      print "verbosity? [h/m/l] "
      choice = $stdin.gets&.strip&.downcase
      @verbosity = case choice
                   when 'low', 'l' then :low
                   when 'medium', 'med', 'm' then :medium
                   else :high
                   end
    end

    def start_server
      @server = Server.new(self)
      @server.start
    end

    def broadcast(text)
      @server&.push(text)
    end

    def repl
      loop do
        input = Readline.readline(build_prompt, true)
        break unless input

        input = input.strip
        next if input.empty?
        break if %w[exit quit q].include?(input)

        result = with_spinner { process_input(input) }
        puts colorize_output(result) if result
        show_token_info if @last_tokens[:input] > 0 || @last_tokens[:output] > 0
      end

      save_history
      @server&.stop
      show_session_summary
    end

    def show_token_info
      cached = @last_cached ? " [cached]" : ""
      puts "#{C_DIM}#{@last_tokens[:input]} tokens in, #{@last_tokens[:output]} tokens out#{cached}#{C_RESET}"
      @last_tokens = { input: 0, output: 0 }
      @last_cached = false
    end

    def show_session_summary
      duration = Time.now - @boot_time
      mins = (duration / 60).to_i
      secs = (duration % 60).to_i
      cost = @llm.total_cost
      total_in = @llm.total_tokens_in rescue 0
      total_out = @llm.total_tokens_out rescue 0
      requests = @llm.request_count rescue 0

      puts ""
      puts "#{C_DIM}Session Summary#{C_RESET}"
      puts "#{C_DIM}  Duration    #{mins}m #{secs}s#{C_RESET}"
      puts "#{C_DIM}  Requests    #{requests}#{C_RESET}" if requests > 0
      puts "#{C_DIM}  Tokens      #{total_in} in / #{total_out} out#{C_RESET}" if total_in > 0
      puts "#{C_DIM}  Cost        #{colorize_cost(cost)}#{C_RESET}"
      puts ""
    end

    def colorize_cost(cost)
      formatted = "$#{'%.4f' % cost}"
      if cost < 0.01
        "#{C_GREEN}#{formatted}#{C_RESET}"
      elsif cost < 0.10
        "#{C_YELLOW}#{formatted}#{C_RESET}"
      else
        "#{C_RED}#{formatted}#{C_RESET}"
      end
    end

    def colorize_output(text)
      return text unless text.is_a?(String)

      if text.start_with?('Error', 'Not found', 'Usage')
        "#{C_RED}#{text}#{C_RESET}"
      elsif text.start_with?('Switched', 'Cleaned', 'Done', 'Changed', 'Cleared')
        "#{C_GREEN}#{text}#{C_RESET}"
      else
        text
      end
    end

    def build_prompt
      dir = File.basename(@root)
      persona = @llm.persona&.dig(:name)
      cost = @llm.total_cost
      hist = @llm.instance_variable_get(:@history)&.size || 0
      uptime = Time.now - @boot_time

      parts = [dir]
      parts << ":#{persona}" if persona && persona != 'default'
      parts << "(#{hist})" if hist > 0
      parts << format_uptime(uptime) if uptime > 3600
      parts << colorize_cost_inline(cost) if cost > 0

      "#{parts.join('')} $ "
    end

    def format_uptime(seconds)
      hours = (seconds / 3600).to_i
      mins = ((seconds % 3600) / 60).to_i
      "#{hours}h#{mins}m"
    end

    def colorize_cost_inline(cost)
      formatted = "$#{'%.2f' % cost}"
      if cost < 0.01
        "#{C_GREEN}#{formatted}#{C_RESET}"
      elsif cost < 0.10
        "#{C_YELLOW}#{formatted}#{C_RESET}"
      else
        "#{C_RED}#{formatted}#{C_RESET}"
      end
    end

    def with_spinner
      frames = %w[- \\ | /]
      done = false
      result = nil

      spinner = Thread.new do
        i = 0
        until done
          print "\r#{frames[i % 4]} "
          i += 1
          sleep 0.1
        end
        print "\r  \r"
      end

      result = yield
      done = true
      spinner.join
      result
    end

    def confirm_expensive(tier)
      return true unless tier == :premium
      info = LLM::TIERS[:premium]
      puts "#{C_YELLOW}Premium tier costs #{info[:input]}/#{info[:output]} per 1000 tokens#{C_RESET}"
      print "Continue? [y/N] "
      response = $stdin.gets&.strip&.downcase
      response == 'y' || response == 'yes'
    end

    def handle(input)
      cmd, *args = input.split(/\s+/, 2)
      arg = args.first

      case cmd
      when 'help', '?'
        help_text

      when 'cd'
        change_dir(arg)

      when 'ls', 'tree'
        show_tree

      when 'cat', 'view', 'read'
        view_file(arg)

      when 'edit'
        edit_file(arg)

      when 'clean'
        clean_file(arg)

      when 'scan'
        scan_path(arg || '.')

      when 'smells'
        detect_smells(arg || '.')

      when 'ask', 'chat'
        chat(arg)

      when 'clear'
        @llm.clear_history
        'History cleared.'

      when 'cost'
        format('$%.6f', @llm.total_cost)

      when 'persona'
        switch_persona(arg)

      when 'personas'
        list_personas

      when 'principles'
        list_principles

      when 'converge'
        run_converge(arg || '.')

      when 'audit'
        run_audit(arg)

      when 'review'
        run_review(arg || '.')

      when 'refactor'
        run_refactor(arg)

      when 'web'
        browse_web(arg)

      when 'image'
        generate_image(arg)

      when 'describe'
        describe_image(arg)

      when 'version'
        "MASTER v#{VERSION}"

      when 'status'
        status_info

      when 'refine'
        run_refine(arg)

      when 'git'
        run_git(arg)

      when 'diff'
        run_git('diff')

      when 'log'
        run_git('log --oneline -20')

      when 'commit'
        run_git("commit -am \"#{arg || 'update'}\"")

      when 'pull'
        run_git('pull')

      when 'push'
        run_git('push')

      else
        # Default: send to LLM
        chat(input)
      end
    end

    def help_text
      <<~HELP
        Commands:
          ask <msg>      Chat with LLM
          audit [ref]    Compare features vs git history
          cat <file>     View file
          cd <dir>       Change directory
          clean <file>   Clean file (CRLF, whitespace)
          clear          Clear chat history
          converge       Iterate until no changes
          cost           Show LLM cost
          describe <img> Describe image (Replicate)
          diff           Git diff
          edit <file>    Edit file
          git <cmd>      Run git command
          help           Show this help
          image <prompt> Generate image (Replicate)
          log            Git log (last 20)
          ls             List files
          persona <name> Switch persona
          personas       List personas
          principles     List principles
          pull           Git pull
          push           Git push
          commit [msg]   Git commit
          read <file>    View file (alias: cat)
          refactor <path> Auto-refactor with research + iteration
          refine [path]  Suggest 20 micro-refinements, cherry-pick
          review <path>  Multi-agent code review
          scan <path>    Scan for issues
          smells <path>  Detect code smells
          status         Show status
          version        Show version
          web <url>      Browse URL
          exit           Quit
      HELP
    end

    def change_dir(path)
      return 'Usage: cd <path>' unless path

      full = File.expand_path(path, @root)
      if Dir.exist?(full)
        @root = full
        Dir.chdir(full)
        "Changed to #{full}"
      else
        "Not found: #{path}"
      end
    end

    def show_tree
      ignore = %w[. .. .git node_modules vendor tmp .bundle]
      files = []

      Dir.glob(File.join(@root, '**', '*'), File::FNM_DOTMATCH).each do |path|
        next if ignore.any? { |i| path.include?("/#{i}/") || path.end_with?("/#{i}") }
        next if File.basename(path).start_with?('.')
        next unless File.file?(path)

        files << path.sub(@root + '/', '')
      end

      files.sort.join("\n")
    end

    def view_file(path)
      return 'Usage: cat <file>' unless path

      full = File.expand_path(path, @root)
      return "Not found: #{path}" unless File.exist?(full)

      File.read(full)
    end

    def edit_file(path)
      return 'Usage: edit <file>' unless path

      editor = ENV['EDITOR'] || 'vi'
      system("#{editor} #{File.expand_path(path, @root)}")
      'Done.'
    end

    def clean_file(path)
      return 'Usage: clean <file>' unless path

      full = File.expand_path(path, @root)
      return "Not found: #{path}" unless File.exist?(full)

      content = File.read(full)
      original = content.dup

      # CRLF -> LF
      content.gsub!("\r\n", "\n")
      # Trailing whitespace
      content.gsub!(/[ \t]+$/, '')
      # Multiple blank lines -> single
      content.gsub!(/\n{3,}/, "\n\n")
      # Ensure final newline
      content << "\n" unless content.end_with?("\n")

      if content != original
        File.write(full, content)
        'Cleaned.'
      else
        'Already clean.'
      end
    end

    def scan_path(path)
      result = Engine.scan(File.expand_path(path, @root))
      return result.error if result.err?

      issues = result.value
      return 'No issues found.' if issues.empty?

      issues.map { |i| "#{i[:file]}: #{i[:type]} (#{i[:lines] || i[:message]})" }.join("\n")
    end

    def detect_smells(path)
      scan_path(path)
    end

    def chat(message)
      return 'Usage: ask <message>' unless message

      trace "sending: #{message[0..50]}..."
      result = @llm.chat(message)
      @last_tokens = @llm.last_tokens
      @last_cached = @llm.last_cached
      trace "received"
      result.ok? ? result.value : "Error: #{result.error}"
    end

    def switch_persona(name)
      return "Available: #{Persona.list.join(', ')}" unless name

      trace "persona: #{name}"
      result = @llm.switch_persona(name)
      result.ok? ? "Switched to #{name}" : result.error
    end

    def list_personas
      Persona.list.join("\n")
    end

    def list_principles
      Principle.load_all.map { |p| "#{p[:filename]}: #{p[:name]}" }.join("\n")
    end

    def browse_web(url)
      return 'Usage: web <url>' unless url

      begin
        require_relative 'web'
        Web.browse(url)
      rescue LoadError
        'Web module not available'
      end
    end

    def generate_image(prompt)
      return 'Usage: image <prompt>' unless prompt

      begin
        require_relative 'replicate'
        Replicate.generate_image(prompt)
      rescue LoadError
        'Replicate module not available'
      end
    end

    def describe_image(path)
      return 'Usage: describe <image>' unless path

      begin
        require_relative 'replicate'
        Replicate.describe_image(File.expand_path(path, @root))
      rescue LoadError
        'Replicate module not available'
      end
    end

    def run_converge(path)
      require_relative 'converge'

      puts "#{C_CYAN}Starting convergence...#{C_RESET}"
      result = Converge.run(path) do |iteration, issues|
        puts "#{C_DIM}Iteration #{iteration}: #{issues.size} issues#{C_RESET}"
      end

      if result.ok?
        data = result.value
        "#{C_GREEN}Converged#{C_RESET} in #{data[:iterations]} iterations (#{data[:final_issues]} issues)"
      else
        "#{C_RED}#{result.error}#{C_RESET}"
      end
    end

    def run_audit(ref)
      require_relative 'converge'

      ref ||= 'HEAD~10'
      audit = Converge.audit(@root, ref)

      lines = []
      lines << "Comparing current vs #{ref}"
      lines << "Current: #{audit[:current_count]} features"
      lines << "Historical: #{audit[:historical_count]} features"
      lines << "Coverage: #{(audit[:coverage] * 100).round(1)}%"

      if audit[:missing].any?
        lines << ""
        lines << "#{C_RED}Missing (#{audit[:missing].size}):#{C_RESET}"
        audit[:missing].first(10).each { |f| lines << "  - #{f}" }
        lines << "  ..." if audit[:missing].size > 10
      end

      if audit[:added].any?
        lines << ""
        lines << "#{C_GREEN}Added (#{audit[:added].size}):#{C_RESET}"
        audit[:added].first(10).each { |f| lines << "  + #{f}" }
        lines << "  ..." if audit[:added].size > 10
      end

      lines.join("\n")
    end

    def run_review(path)
      begin
        require_relative 'agents/review_crew'

        crew = MASTER::Agents::ReviewCrew.new(llm: @llm, principles: Principle.load_all)
        code = File.read(File.expand_path(path, @root))
        results = crew.review(code, path)

        summary = results[:summary]
        "#{C_CYAN}Review complete:#{C_RESET} #{summary[:total_findings]} findings"
      rescue LoadError, StandardError => e
        "Review agents not available: #{e.message}"
      end
    end

    def run_refactor(path)
      return 'Usage: refactor <file|dir>' unless path

      files = resolve_files(path)
      return "No files found: #{path}" if files.empty?

      trace "refactoring #{files.size} files"
      total_iterations = 0
      total_changes = 0

      files.each do |file|
        result = refactor_file(file)
        total_iterations += result[:iterations]
        total_changes += result[:changes]
      end

      "#{C_GREEN}Refactored#{C_RESET} #{files.size} file(s): #{total_changes} changes in #{total_iterations} iterations"
    end

    def refactor_file(file)
      trace "analyzing: #{file}"

      # Phase 1: Research - understand the domain
      code = File.read(file)
      ext = File.extname(file)
      lang = detect_language(ext)

      research_prompt = <<~PROMPT
        Analyze this #{lang} code and identify:
        1. What libraries/frameworks it uses
        2. Best practices that should apply
        3. Common patterns in this domain
        4. Potential improvements

        Be concise. Return as bullet points.

        ```#{lang}
        #{code[0..2000]}
        ```
      PROMPT

      trace "phase 1: research"
      research = with_spinner("Researching") { @llm.chat(research_prompt, tier: :fast) }
      research_text = research.ok? ? research.value : ""

      # Phase 2: Iterate until convergence
      max_iterations = 5
      min_change_threshold = 0.02
      iteration = 0
      prev_code = code
      changes = 0

      loop do
        iteration += 1
        break if iteration > max_iterations

        trace "phase 2: iteration #{iteration}"

        refactor_prompt = <<~PROMPT
          You are refactoring #{lang} code. Apply these insights:
          #{research_text[0..500]}

          Rules:
          - Make minimal, surgical changes
          - Preserve all functionality
          - Improve clarity, not just style
          - Return ONLY the refactored code, no explanation

          ```#{lang}
          #{prev_code}
          ```
        PROMPT

        result = with_spinner("Iteration #{iteration}") { @llm.chat(refactor_prompt, tier: :code) }
        break unless result.ok?

        new_code = extract_code(result.value, lang)
        break if new_code.nil? || new_code.empty?

        # Calculate change ratio
        ratio = change_ratio(prev_code, new_code)
        trace "change: #{(ratio * 100).round(1)}%"

        if ratio < min_change_threshold
          trace "converged"
          break
        end

        changes += 1
        prev_code = new_code
      end

      # Write final result if changed
      if prev_code != code
        File.write(file, prev_code)
        info "Wrote: #{file}"
      end

      { iterations: iteration, changes: changes }
    end

    def resolve_files(path)
      full = File.expand_path(path, @root)

      if File.file?(full)
        [full]
      elsif Dir.exist?(full)
        Dir.glob(File.join(full, '**', '*.{rb,py,js,ts,go,rs}')).reject { |f| f.include?('/vendor/') || f.include?('/node_modules/') }
      else
        Dir.glob(File.join(@root, path))
      end
    end

    def detect_language(ext)
      {
        '.rb' => 'ruby', '.py' => 'python', '.js' => 'javascript',
        '.ts' => 'typescript', '.go' => 'go', '.rs' => 'rust',
        '.sh' => 'bash', '.yml' => 'yaml', '.yaml' => 'yaml'
      }[ext] || 'text'
    end

    def extract_code(response, lang)
      # Extract code block from LLM response
      if response =~ /```#{lang}\s*(.*?)```/m
        $1.strip
      elsif response =~ /```\s*(.*?)```/m
        $1.strip
      else
        response.strip
      end
    end

    def change_ratio(old_code, new_code)
      return 0.0 if old_code == new_code
      return 1.0 if old_code.empty?

      # Simple line-based diff ratio
      old_lines = old_code.lines
      new_lines = new_code.lines

      common = old_lines & new_lines
      total = [old_lines.size, new_lines.size].max

      1.0 - (common.size.to_f / total)
    end

    def run_refine(target = nil)
      target ||= 'lib'
      files = resolve_files(target)
      return "No files found: #{target}" if files.empty?

      prompt = <<~PROMPT
        Analyze this codebase and suggest 20 micro-refinements.
        Each refinement must be:
        - Minimal (1-3 lines changed)
        - High impact (UX, performance, clarity)
        - Specific (exact file, line, change)

        Format each as:
        [N] file:line - description
        OLD: exact code
        NEW: exact code

        Files:
        #{files.map { |f| "--- #{f} ---\n#{File.read(f)}" }.join("\n\n")}
      PROMPT

      result = with_spinner { @llm.chat(prompt, tier: :strong) }
      return result.error if result.err?

      suggestions = parse_refinements(result.value)
      return "No refinements found" if suggestions.empty?

      puts "\n#{suggestions.size} refinements suggested:\n\n"
      suggestions.each_with_index do |s, i|
        puts "[#{i + 1}] #{s[:file]}:#{s[:line]} - #{s[:desc]}"
      end

      puts "\nApply which? (1,3,5 or 'all' or 'none'): "
      choice = Readline.readline('', false)&.strip

      return "Cancelled" if choice.nil? || choice == 'none' || choice.empty?

      indices = if choice == 'all'
        (0...suggestions.size).to_a
      else
        choice.split(/[,\s]+/).map { |n| n.to_i - 1 }.select { |i| i >= 0 && i < suggestions.size }
      end

      applied = 0
      indices.each do |i|
        s = suggestions[i]
        if apply_refinement(s)
          applied += 1
          puts "Applied: #{s[:desc]}"
        end
      end

      "Applied #{applied}/#{indices.size} refinements"
    end

    def parse_refinements(text)
      refinements = []
      current = nil

      text.lines.each do |line|
        if line =~ /^\[(\d+)\]\s*(\S+):(\d+)\s*-\s*(.+)/
          refinements << current if current
          current = { num: $1.to_i, file: $2, line: $3.to_i, desc: $4.strip, old: '', new: '' }
        elsif current
          if line =~ /^OLD:\s*(.*)/ || line =~ /^old:\s*(.*)/
            current[:old] = $1.strip
          elsif line =~ /^NEW:\s*(.*)/ || line =~ /^new:\s*(.*)/
            current[:new] = $1.strip
          end
        end
      end
      refinements << current if current
      refinements.compact
    end

    def apply_refinement(ref)
      file = File.expand_path(ref[:file], @root)
      return false unless File.exist?(file)

      content = File.read(file)
      return false if ref[:old].empty? || ref[:new].empty?
      return false unless content.include?(ref[:old])

      new_content = content.sub(ref[:old], ref[:new])
      File.write(file, new_content)
      true
    rescue
      false
    end

    def status_info
      <<~STATUS
        MASTER v#{VERSION}
        Root: #{@root}
        Persona: #{@llm.persona&.dig(:name) || 'default'}
        Cost: $#{format('%.6f', @llm.total_cost)}
        Server: #{@server&.url || 'stopped'}
      STATUS
    end

    def run_git(args)
      return 'Usage: git <command>' unless args
      `git --no-pager #{args} 2>&1`.strip
    end
  end
end
