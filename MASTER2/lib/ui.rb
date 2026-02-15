# frozen_string_literal: true

# UI - Unified terminal interface using TTY toolkit
# Lazy-loads components for fast startup
# Restored from MASTER v1 with full TTY integration

module MASTER
  module UI
    extend self

    # Boot time for dmesg-style timestamps
    MASTER_BOOT_TIME = Time.now

    # --- Typography Icons (minimal vocabulary per Strunk & White) ---
    ICONS = {
      success: "✓",
      failure: "✗",
      warning: "!",
      bullet: "·",
      arrow: "→",
      thinking: "◐",
      done: "●",
    }.freeze

    # --- Formatting Helpers (DRY) ---
    def currency(n)
      format("$%.2f", n)
    end

    def currency_precise(n)
      format("$%.4f", n)
    end

    def truncate_id(id, len = 8)
      "#{id[0, len]}..."
    end

    def header(title, width: 40)
      puts "\n  #{bold(title)}"
      puts "  #{'-' * width}"
    end

    def icon(name)
      ICONS[name.to_sym] || "·"
    end

    def status(prefix, message, success: true)
      i = success ? icon(:success) : icon(:failure)
      "#{prefix}: #{message} #{i}"
    end

    def progress_line(current, total, message = nil)
      msg = message ? " #{message}" : ""
      "  [#{current}/#{total}]#{msg}"
    end

    # --- TTY Component Lazy Loaders ---
    
    def prompt
      @prompt ||= begin
        require 'tty-prompt'
        TTY::Prompt.new(symbols: { marker: '›' }, active_color: :cyan)
      rescue LoadError
        nil
      end
    end

    def spinner(message = nil, format: :braille)
      require 'tty-spinner'
      TTY::Spinner.new("[:spinner] #{message}", format: format)
    rescue LoadError
      Object.new.tap do |s|
        s.define_singleton_method(:auto_spin) {}
        s.define_singleton_method(:success) { puts "✓" }
        s.define_singleton_method(:error) { puts "✗" }
      end
    end

    def multi_spinner
      require 'tty-spinner'
      TTY::Spinner::Multi.new("[:spinner] Processing", format: :braille)
    rescue LoadError
      Object.new.tap { |s| s.define_singleton_method(:register) { |*| spinner } }
    end

    def table(data, header: nil)
      require 'tty-table'
      opts = header ? { header: header } : {}
      TTY::Table.new(opts) { |t| data.each { |row| t << row } }
    rescue LoadError
      # Fallback to simple text table
      lines = []
      lines << header.join(" | ") if header
      data.each { |row| lines << row.join(" | ") }
      lines.join("\n")
    end

    def box(content, title: nil, **opts)
      require 'tty-box'
      TTY::Box.frame(
        content,
        title: title ? { top_left: " #{title} " } : nil,
        padding: [0, 1],
        border: :round,
        **opts
      )
    rescue LoadError
      # Fallback to indented content
      lines = []
      lines << bold(title) if title
      lines << ""
      content.each_line { |l| lines << "  #{l.rstrip}" }
      lines << ""
      lines.join("\n")
    end

    def markdown(text, width: nil)
      require 'tty-markdown'
      TTY::Markdown.parse(text, width: width || screen_width)
    rescue LoadError
      text
    end

    def progress(total, format: :bar)
      require 'tty-progressbar'
      TTY::ProgressBar.new(
        "[:bar] :percent :eta",
        total: total,
        bar_format: format == :block ? :block : :classic
      )
    rescue LoadError
      Object.new.tap do |p|
        p.instance_variable_set(:@current, 0)
        p.instance_variable_set(:@total, total)
        p.define_singleton_method(:advance) { |n = 1| @current += n; print "\r  [#{@current}/#{@total}]" }
        p.define_singleton_method(:finish) { puts " done" }
      end
    end

    def cursor
      @cursor ||= begin
        require 'tty-cursor'
        TTY::Cursor
      rescue LoadError
        Module.new do
          def self.hide; ""; end
          def self.show; ""; end
          def self.up(n=1); ""; end
          def self.down(n=1); ""; end
          def self.forward(n=1); ""; end
          def self.backward(n=1); ""; end
          def self.column(n); ""; end
          def self.move_to(x, y); ""; end
          def self.clear_line; "\r"; end
          def self.clear_screen; ""; end
        end
      end
    end

    def reader
      @reader ||= begin
        require 'tty-reader'
        TTY::Reader.new
      rescue LoadError
        Object.new.tap do |r|
          r.define_singleton_method(:read_line) { |*| gets }
          r.define_singleton_method(:read_keypress) { $stdin.getch rescue gets }
        end
      end
    end

    def tree(data)
      require 'tty-tree'
      TTY::Tree.new(data)
    rescue LoadError
      # Fallback to simple indented list
      def self.format_tree(data, indent=0)
        return "" unless data.is_a?(Hash) || data.is_a?(Array)
        lines = []
        (data.is_a?(Hash) ? data : data.each_with_index.to_a).each do |k, v|
          lines << "  " * indent + "- #{k}"
          lines << format_tree(v, indent + 1) if v.is_a?(Hash) || v.is_a?(Array)
        end
        lines.join("\n")
      end
      format_tree(data)
    end

    def pie(data)
      require 'tty-pie'
      TTY::Pie.new(data: data, radius: 5)
    rescue LoadError
      # Fallback to simple list
      Object.new.tap do |p|
        p.instance_variable_set(:@data, data)
        p.define_singleton_method(:render) do
          @data.map { |d| "#{d[:name]}: #{d[:value]}" }.join(", ")
        end
      end
    end

    def pager
      @pager ||= begin
        require 'tty-pager'
        TTY::Pager.new
      rescue LoadError
        Object.new.tap do |p|
          p.define_singleton_method(:page) { |text| puts text }
        end
      end
    end

    def link(text, url)
      require 'tty-link'
      TTY::Link.link_to(text, url)
    rescue LoadError
      "#{text} (#{url})"
    end

    def font(text, font_name = :doom)
      require 'tty-font'
      TTY::Font.new(font_name).write(text)
    rescue LoadError
      text
    end

    def edit(path_or_text)
      require 'tty-editor'
      TTY::Editor.open(path_or_text)
    rescue LoadError
      # Fallback to system editor
      editor = ENV['EDITOR'] || 'vi'
      if File.exist?(path_or_text)
        system(editor, path_or_text)
      else
        tmpfile = "/tmp/master_edit_#{Time.now.to_i}.txt"
        File.write(tmpfile, path_or_text)
        system(editor, tmpfile)
        File.read(tmpfile)
      end
    end

    def command(*cmd, **opts)
      require 'tty-command'
      TTY::Command.new(printer: :quiet).run(*cmd, **opts)
    rescue LoadError
      # Fallback to system
      system(*cmd)
    end

    def screen_width
      @screen_width ||= begin
        require 'tty-screen'
        TTY::Screen.width
      rescue LoadError
        80
      end
    end

    def screen_height
      @screen_height ||= begin
        require 'tty-screen'
        TTY::Screen.height
      rescue LoadError
        24
      end
    end

    def platform
      @platform ||= begin
        require 'tty-platform'
        TTY::Platform.new
      rescue LoadError
        Object.new.tap do |p|
          p.define_singleton_method(:os) { RbConfig::CONFIG['host_os'] }
          p.define_singleton_method(:cpu) { RbConfig::CONFIG['host_cpu'] }
          p.define_singleton_method(:arch) { RbConfig::CONFIG['arch'] }
        end
      end
    end

    def which(cmd)
      require 'tty-which'
      TTY::Which.which(cmd)
    rescue LoadError
      # Fallback to simple which
      ENV['PATH'].split(':').each do |dir|
        path = File.join(dir, cmd)
        return path if File.executable?(path)
      end
      nil
    end

    def pastel
      @pastel ||= begin
        require 'pastel'
        Pastel.new(enabled: color_enabled?)
      rescue LoadError
        # Fallback when pastel gem is not available
        Object.new.tap do |p|
          %i[green red yellow cyan dim bold magenta bright_magenta bright_cyan bright_black blue].each do |color|
            p.define_singleton_method(color) { |text = nil| text.nil? ? self : text }
          end
        end
      end
    end

    def color_enabled?
      return false if ENV["NO_COLOR"]
      return false if ENV["TERM"] == "dumb"
      true
    end

    # --- High-level Convenience Methods ---

    def success(msg)
      puts pastel.green("✓ #{msg}")
    end

    def error(msg)
      puts pastel.red("✗ #{msg}")
    end

    def warn(msg)
      puts pastel.yellow("⚠ #{msg}")
    end

    def info(msg)
      puts pastel.cyan("ℹ #{msg}")
    end

    def dim(msg)
      pastel.dim(msg)
    end

    def bold(msg)
      pastel.bold(msg)
    end

    # Color delegate methods - return colored strings without printing
    def yellow(msg)
      pastel.yellow(msg)
    end

    def green(msg)
      pastel.green(msg)
    end

    def red(msg)
      pastel.red(msg)
    end

    def cyan(msg)
      pastel.cyan(msg)
    end

    def magenta(msg)
      pastel.magenta(msg)
    end

    def blue(msg)
      pastel.blue(msg)
    end

    def with_spinner(message, &block)
      s = spinner(message)
      s.auto_spin
      result = yield
      s.success
      result
    rescue => e
      s.error
      raise
    end

    def select(question, choices)
      return nil unless prompt
      prompt.select(question, choices, cycle: true)
    end

    def multi_select(question, choices)
      return [] unless prompt
      prompt.multi_select(question, choices, cycle: true)
    end

    def confirm(question, default: true)
      return default unless prompt
      prompt.yes?(question, default: default)
    end

    def ask(question, default: nil)
      return default unless prompt
      prompt.ask(question, default: default)
    end

    def paginate(text)
      pager.page(text)
    end

    def clear_line
      print cursor.clear_line + cursor.column(0)
    end

    def move_up(n = 1)
      print cursor.up(n)
    end

    def hide_cursor(&block)
      print cursor.hide
      yield
    ensure
      print cursor.show
    end

    # --- Special rendering methods ---

    def render_response(text)
      # Try markdown rendering, fallback to plain
      markdown(text)
    rescue => e
      text
    end

    def token_chart(prompt_tokens:, completion_tokens:, cached: 0)
      total = prompt_tokens + completion_tokens
      data = [
        { name: 'prompt', value: prompt_tokens, color: :blue },
        { name: 'completion', value: completion_tokens, color: :green }
      ]
      data << { name: 'cached', value: cached, color: :cyan } if cached > 0
      
      puts pie(data).render
      puts dim("Total: #{total} tokens")
    end

    def show_tree(path, depth: 3)
      require 'tty-tree'
      tree_obj = TTY::Tree.new(path, level: depth)
      puts tree_obj.render
    rescue LoadError
      # Simple fallback
      Dir.glob(File.join(path, '*')).each do |f|
        puts "  #{File.basename(f)}"
      end
    end

    # --- Colorization for dmesg and system output ---
    
    def dmesg(subsystem, message, level: :info)
      elapsed = (Time.now - MASTER_BOOT_TIME).round(6)
      prefix = format("[%12.6f]", elapsed)
      line = "#{prefix} #{subsystem}: #{message}"
      case level
      when :error, :warn then $stderr.puts line
      else puts line
      end
    end
    
    def colorize(text)
      return text unless color_enabled?
      text
        .gsub(/^(\w+) at (\w+):/) { "#{pastel.blue($1)} at #{pastel.cyan($2)}:" }
        .gsub(/^(MASTER .+)$/) { pastel.bold.magenta($1) }
        .gsub(/(\d+) (axioms|personas|stages)/) { "#{pastel.bright_magenta($1)} #{$2}" }
        .gsub(/(\$[\d.]+)/) { pastel.bright_cyan($1) }
        .gsub(/(armed|available)/) { pastel.green($1) }
        .gsub(/(unavailable|error)/) { pastel.red($1) }
        .gsub(/(\d+ms)$/) { pastel.bright_black($1) }
    end

    # === Help - Command documentation (NN/g compliant) ===
    # Merged from help.rb
    module Help
      extend self

      COMMANDS = {
        # Queries
        ask: { desc: "Ask the LLM a question", usage: "ask <question>", group: :query },
        refactor: { desc: "Refactor a file with 6-phase analysis", usage: "refactor <file>", group: :query },
        chamber: { desc: "Multi-model deliberation", usage: "chamber <file>", group: :query },
        evolve: { desc: "Self-improvement cycle", usage: "evolve [path]", group: :query },
        opportunities: { desc: "Find improvements", usage: "opportunities [path]", group: :query },
        # Analysis
        hunt: { desc: "8-phase bug analysis", usage: "hunt <file>", group: :analysis },
        critique: { desc: "Constitutional validation", usage: "critique <file>", group: :analysis },
        learn: { desc: "Show matching learned patterns", usage: "learn <file>", group: :analysis },
        conflict: { desc: "Detect principle conflicts", usage: "conflict", group: :analysis },
        scan: { desc: "Scan for code smells", usage: "scan [path]", group: :analysis },
        # Session
        session: { desc: "Session management", usage: "session [new|save|load]", group: :session },
        sessions: { desc: "List saved sessions", usage: "sessions", group: :session },
        forget: { desc: "Undo last exchange", usage: "forget", group: :session },
        summary: { desc: "Conversation summary", usage: "summary", group: :session },
        capture: { desc: "Capture session insights", usage: "capture", group: :session },
        'review-captures': { desc: "Review captured insights", usage: "review-captures", group: :session },
        # System
        status: { desc: "System status", usage: "status", group: :system },
        budget: { desc: "Budget remaining", usage: "budget", group: :system },
        context: { desc: "Context window usage", usage: "context", group: :system },
        history: { desc: "Cost history", usage: "history", group: :system },
        health: { desc: "Health check", usage: "health", group: :system },
        # Utility
        help: { desc: "Show this help", usage: "help [command]", group: :util },
        speak: { desc: "Text-to-speech", usage: "speak <text>", group: :util },
        shell: { desc: "Interactive shell", usage: "shell", group: :util },
        clear: { desc: "Clear screen", usage: "clear", group: :util },
        exit: { desc: "Exit MASTER", usage: "exit", group: :util },
      }.freeze

      TIPS = [
        "Tab for autocomplete",
        "Ctrl+C to cancel",
        "!! repeats last command",
      ].freeze

      GROUPS = {
        query: "Queries",
        analysis: "Analysis",
        session: "Session",
        system: "System",
        util: "Utility",
      }.freeze

      def show(command = nil)
        if command == "tips"
          show_tips
        elsif command && COMMANDS[command.to_sym]
          show_command(command.to_sym)
        else
          show_all
        end
      end

      def show_all
        puts
        GROUPS.each do |group, label|
          cmds = COMMANDS.select { |_, v| v[:group] == group }
          puts "  #{label}"
          cmds.each do |cmd, info|
            puts "    #{cmd.to_s.ljust(12)} #{info[:desc]}"
          end
          puts
        end
      end

      def show_tips
        puts
        TIPS.each { |t| puts "  · #{t}" }
        puts
      end

      def show_command(cmd)
        info = COMMANDS[cmd]
        return puts "Unknown command: #{cmd}" unless info

        UI.header(cmd.to_s, width: cmd.to_s.length)
        puts "  #{info[:desc]}"
        puts "  Usage: #{info[:usage]}"
        puts
      end

      def tip
        TIPS.sample
      end

      def autocomplete(partial)
        COMMANDS.keys.map(&:to_s).select { |c| c.start_with?(partial) }
      end
    end

    # === ErrorSuggestions - NN/g: Help users recognize, diagnose, and recover from errors ===
    # Merged from error_suggestions.rb
    module ErrorSuggestions
      extend self

      SUGGESTIONS = {
        # API errors
        /401|unauthorized/i => [
          "Check your OPENROUTER_API_KEY in .env",
          "Verify the API key hasn't expired",
          "Run: echo $OPENROUTER_API_KEY to verify it's set"
        ],
        /429|rate.?limit/i => [
          "Wait a few minutes and retry",
          "Try a cheaper model tier",
          "Check your API quota at openrouter.ai"
        ],
        /timeout|timed?.?out/i => [
          "Check your internet connection",
          "The API might be slow - try again",
          "Try a faster model tier"
        ],
        /connection.?refused/i => [
          "Check if the service is running",
          "Verify the host and port are correct",
          "Check firewall settings"
        ],

        # File errors
        /file.?not.?found|no.?such.?file/i => [
          "Check the file path is correct",
          "Use tab completion to verify the path",
          "Run: ls to see available files"
        ],
        /permission.?denied/i => [
          "Check file permissions",
          "You may need sudo/admin access",
          "Verify you own the file"
        ],

        # Ruby errors
        /undefined.?method/i => [
          "The method doesn't exist on this object",
          "Check for typos in the method name",
          "Verify the object type is what you expect"
        ],
        /undefined.?local.?variable/i => [
          "The variable hasn't been defined yet",
          "Check for typos in the variable name",
          "Verify scope - is it defined in this block?"
        ],
        /syntax.?error/i => [
          "Check for missing 'end' keywords",
          "Look for unclosed strings or brackets",
          "Verify method definitions are complete"
        ],

        # MASTER specific
        /budget.?exceeded|insufficient.?budget/i => [
          "Your session budget is exhausted",
          "Start a new session for fresh budget",
          "Use cheaper model tier"
        ],
        /circuit.?open|circuit.?tripped/i => [
          "That model has too many failures",
          "Wait for circuit cooldown (5 min)",
          "Try a different model"
        ],
        /dangerous.?command|blocked/i => [
          "This command was blocked for safety",
          "Rephrase without destructive operations",
          "Use --force if you're sure (not recommended)"
        ]
      }.freeze

      def suggest(error_message)
        return [] unless error_message

        SUGGESTIONS.each do |pattern, suggestions|
          return suggestions if error_message.match?(pattern)
        end

        # Generic fallback
        ["Check the error message for details", "Try 'help' for available commands"]
      end

      def format_error(error, context: nil)
        suggestions = suggest(error.to_s)

        lines = ["Error: #{error}"]
        lines << "Context: #{context}" if context

        if suggestions.any?
          lines << ""
          lines << "Suggestions:"
          suggestions.each { |s| lines << "  • #{s}" }
        end

        lines.join("\n")
      end

      def wrap(result)
        return result if result.ok?

        suggestions = suggest(result.error.to_s)
        enhanced_error = {
          message: result.error,
          suggestions: suggestions
        }

        Result.err(enhanced_error)
      end
    end

    # === NNGChecklist - Nielsen Norman Group usability heuristics compliance ===
    # Merged from nng_checklist.rb
    module NNGChecklist
      HEURISTICS = {
        visibility: {
          name: "Visibility of System Status",
          checks: [
            { feature: 'progress_indicators', desc: 'Show progress during LLM calls', file: 'progress.rb' },
            { feature: 'prompt_status', desc: 'Prompt shows tier and budget', file: 'pipeline.rb' },
            { feature: 'circuit_indicator', desc: '⚡ shows tripped circuits', file: 'pipeline.rb' }
          ]
        },
        match: {
          name: "Match Between System and Real World",
          checks: [
            { feature: 'natural_commands', desc: 'Commands use natural language', file: 'commands.rb' },
            { feature: 'dmesg_boot', desc: 'Boot messages in familiar format', file: 'boot.rb' }
          ]
        },
        control: {
          name: "User Control and Freedom",
          checks: [
            { feature: 'undo', desc: 'Undo support for file operations', file: 'undo.rb' },
            { feature: 'ctrl_c', desc: 'Ctrl+C cancels operations', file: 'pipeline.rb' },
            { feature: 'exit', desc: 'Clear exit command', file: 'commands.rb' }
          ]
        },
        consistency: {
          name: "Consistency and Standards",
          checks: [
            { feature: 'prompt_format', desc: 'Consistent prompt format', file: 'pipeline.rb' },
            { feature: 'result_monad', desc: 'Consistent Result type', file: 'result.rb' }
          ]
        },
        error_prevention: {
          name: "Error Prevention",
          checks: [
            { feature: 'guard_stage', desc: 'Guard blocks dangerous commands', file: 'stages.rb' },
            { feature: 'confirmations', desc: 'Confirm destructive actions', file: 'confirmations.rb' },
            { feature: 'agent_firewall', desc: 'Filter agent outputs', file: 'agent_firewall.rb' }
          ]
        },
        recognition: {
          name: "Recognition Rather Than Recall",
          checks: [
            { feature: 'autocomplete', desc: 'Tab completion for commands', file: 'autocomplete.rb' },
            { feature: 'help', desc: 'Help shows all commands', file: 'help.rb' }
          ]
        },
        flexibility: {
          name: "Flexibility and Efficiency of Use",
          checks: [
            { feature: 'keybindings', desc: 'Keyboard shortcuts', file: 'keybindings.rb' },
            { feature: 'tiers', desc: 'Multiple model tiers', file: 'llm.rb' },
            { feature: 'pipe_mode', desc: 'Pipe mode for scripting', file: 'pipeline.rb' }
          ]
        },
        aesthetic: {
          name: "Aesthetic and Minimalist Design",
          checks: [
            { feature: 'clean_output', desc: 'Minimal, focused output', file: 'stages.rb' },
            { feature: 'render_stage', desc: 'Typography improvements', file: 'stages.rb' }
          ]
        },
        errors: {
          name: "Help Users Recognize, Diagnose, Recover from Errors",
          checks: [
            { feature: 'error_suggestions', desc: 'Actionable error messages', file: 'error_suggestions.rb' },
            { feature: 'circuit_breaker', desc: 'Auto-recover from API failures', file: 'llm.rb' }
          ]
        },
        documentation: {
          name: "Help and Documentation",
          checks: [
            { feature: 'help_command', desc: 'Built-in help', file: 'help.rb' },
            { feature: 'tips', desc: 'Contextual tips', file: 'help.rb' },
            { feature: 'readme', desc: 'Comprehensive README', file: '../README.md' }
          ]
        }
      }.freeze

      extend self

      def audit
        results = {}

        HEURISTICS.each do |key, heuristic|
          results[key] = {
            name: heuristic[:name],
            checks: heuristic[:checks].map do |check|
              file_exists = File.exist?(File.join(MASTER.root, 'lib', check[:file]))
              { **check, status: file_exists ? :pass : :missing }
            end
          }
        end

        results
      end

      def compliance_score
        total = 0
        passed = 0

        HEURISTICS.each do |_, heuristic|
          heuristic[:checks].each do |check|
            total += 1
            file_path = File.join(MASTER.root, 'lib', check[:file])
            passed += 1 if File.exist?(file_path)
          end
        end

        (passed.to_f / total * 100).round(1)
      end

      def report
        score = compliance_score
        audit_results = audit

        lines = ["NN/g Usability Audit - Score: #{score}%", "=" * 50, ""]

        audit_results.each do |key, result|
          status_count = result[:checks].count { |c| c[:status] == :pass }
          total = result[:checks].size
          lines << "#{result[:name]} (#{status_count}/#{total})"

          result[:checks].each do |check|
            icon = check[:status] == :pass ? "✓" : "✗"
            lines << "  #{icon} #{check[:desc]}"
          end
          lines << ""
        end

        lines.join("\n")
      end

      def lint_html(file_path)
        return { error: "File not found: #{file_path}" } unless File.exist?(file_path)
        
        content = File.read(file_path)
        issues = []
        
        # Check for CSS custom properties usage (no raw hex outside :root)
        if content.include?('<style>')
          style_section = content[/<style>(.*?)<\/style>/m, 1]
          if style_section
            # Extract :root section
            root_section = style_section[/:root\s*\{[^}]*\}/m]
            non_root = style_section.gsub(/:root\s*\{[^}]*\}/m, '')
            
            # Check for hex colors outside :root
            hex_colors = non_root.scan(/#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\b/)
            unless hex_colors.empty?
              issues << "Found #{hex_colors.length} raw hex colors outside :root (should use CSS vars)"
            end
          end
        end
        
        # Check for prefers-reduced-motion media query
        unless content.include?('prefers-reduced-motion')
          issues << "Missing @media (prefers-reduced-motion) support"
        end
        
        # Check for focus styles
        has_focus = content.include?('focus-visible') || content.include?(':focus')
        unless has_focus
          issues << "Missing focus styles (:focus or :focus-visible)"
        end
        
        # Check for dialog element vs custom modal
        if content.include?('modal') && !content.include?('<dialog')
          issues << "Consider using <dialog> element instead of custom modal"
        end
        
        # Check for semantic HTML
        semantic_score = 0
        semantic_score += 1 if content.include?('<nav')
        semantic_score += 1 if content.include?('<header')
        semantic_score += 1 if content.include?('<main')
        semantic_score += 1 if content.include?('<footer')
        semantic_score += 1 if content.include?('<article')
        semantic_score += 1 if content.include?('<section')
        
        if semantic_score == 0 && content.length > 1000
          issues << "Consider using semantic HTML elements (nav, header, main, footer, article, section)"
        end
        
        {
          file: file_path,
          issues: issues,
          pass: issues.empty?
        }
      end

      def lint_views
        views_dir = File.join(MASTER.root, 'lib', 'views')
        return { error: "Views directory not found" } unless Dir.exist?(views_dir)
        
        results = []
        Dir.glob(File.join(views_dir, '*.html')).each do |file|
          results << lint_html(file)
        end
        
        {
          total: results.length,
          passed: results.count { |r| r[:pass] },
          failed: results.count { |r| !r[:pass] },
          results: results
        }
      end

      def check_contrast(fg_hex, bg_hex)
        # Convert hex to RGB
        fg_rgb = [fg_hex[1..2], fg_hex[3..4], fg_hex[5..6]].map { |h| h.to_i(16) / 255.0 }
        bg_rgb = [bg_hex[1..2], bg_hex[3..4], bg_hex[5..6]].map { |h| h.to_i(16) / 255.0 }
        
        # Calculate relative luminance
        fg_lum = relative_luminance(fg_rgb)
        bg_lum = relative_luminance(bg_rgb)
        
        # Calculate contrast ratio
        lighter = [fg_lum, bg_lum].max
        darker = [fg_lum, bg_lum].min
        ratio = (lighter + 0.05) / (darker + 0.05)
        
        {
          ratio: ratio.round(2),
          wcag_aa: ratio >= 4.5,
          wcag_aaa: ratio >= 7.0
        }
      end

      private

      def relative_luminance(rgb)
        rgb.map do |c|
          c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
        end.then do |r, g, b|
          0.2126 * r + 0.7152 * g + 0.0722 * b
        end
      end
    end

    # === Confirmations - NN/g: Prevent errors by confirming destructive actions ===
    # Merged from confirmations.rb
    module Confirmations
      extend self

      DESTRUCTIVE_PATTERNS = [
        /rm\s+-rf/i,
        /delete/i,
        /drop\s+table/i,
        /truncate/i,
        /reset/i,
        /--force/i,
        /overwrite/i
      ].freeze

      @auto_confirm = false

      class << self
        attr_accessor :auto_confirm
      end

      def needs_confirmation?(input)
        DESTRUCTIVE_PATTERNS.any? { |pat| input.match?(pat) }
      end

      def confirm(message, default: false)
        if defined?(TTY::Prompt)
          prompt = TTY::Prompt.new
          prompt.yes?(message)
        else
          default_hint = default ? "[Y/n]" : "[y/N]"
          print "#{message} #{default_hint} "
          response = $stdin.gets&.strip&.downcase

          return default if response.nil? || response.empty?
          %w[y yes].include?(response)
        end
      end

      def confirm_destructive(action, details: nil)
        puts "\n  ⚠️  Destructive Action: #{action}"
        puts "  #{details}" if details
        puts

        confirm("Are you sure you want to proceed?", default: false)
      end

      def confirm_with_options(message, options)
        if defined?(TTY::Prompt)
          prompt = TTY::Prompt.new
          prompt.select(message, options)
        else
          puts message
          options.each_with_index { |opt, i| puts "  #{i + 1}. #{opt}" }
          print "Select (1-#{options.size}): "
          choice = $stdin.gets&.strip&.to_i
          options[choice - 1] if choice.between?(1, options.size)
        end
      end

      def gate(operation_name, description: nil, &block)
        return Result.err("No block provided") unless block

        # Phase 1: Propose
        if description
          puts "\n"
          puts "  ⚠️  Operation: #{operation_name}"
          puts "  📋 Description: #{description}"
          puts "\n"
        else
          puts "\n  ⚠️  Operation: #{operation_name}\n\n"
        end

        # Phase 2: Confirm
        unless @auto_confirm
          confirmed = Confirmations.confirm("Proceed with this operation?")

          unless confirmed
            return Result.err("Cancelled by user")
          end
        end

        # Phase 3: Execute
        begin
          result = block.call
          Result.ok(result: result)
        rescue StandardError => e
          Result.err("Execution failed: #{e.message}")
        end
      end

      class Stage
        def initialize(operation_name, description: nil)
          @operation_name = operation_name
          @description = description
        end

        def call(context)
          Confirmations.gate(@operation_name, description: @description) do
            context
          end
        end
      end
    end
  end

  # === Autocomplete - Tab completion for REPL ===
  # Merged from autocomplete.rb
  module Autocomplete
    extend self

    COMMANDS = %w[help status budget clear history refactor chamber evolve speak exit quit ask scan].freeze

    def complete(partial, context: nil)
      completions = []

      # Command completion
      if partial.match?(/^\w*$/)
        completions += COMMANDS.select { |c| c.start_with?(partial) }
      end

      # File path completion
      if partial.include?('/') || partial.include?('\\') || partial.end_with?('.rb')
        completions += complete_path(partial)
      end

      # After known commands, suggest relevant completions
      if context
        case context
        when 'refactor', 'chamber'
          completions += complete_path(partial).select { |p| p.end_with?('.rb') }
        when 'speak', 'say'
          # No completion for freeform text
        end
      end

      completions.uniq
    end

    def complete_path(partial)
      dir = File.dirname(partial)
      dir = '.' if dir == partial
      base = File.basename(partial)

      return [] unless Dir.exist?(dir)

      Dir.entries(dir)
         .reject { |e| e.start_with?('.') }
         .select { |e| e.start_with?(base) }
         .map { |e| File.join(dir, e) }
    rescue StandardError
      []
    end

    def setup_readline
      return unless defined?(Readline)

      Readline.completion_proc = proc do |input|
        complete(input)
      end
      Readline.completion_append_character = ' '
    end

    def setup_tty(reader)
      return unless reader.respond_to?(:on)

      reader.on(:keypress) do |event|
        if event.key.name == :tab
          word = event.line.text.split.last || ''
          matches = complete(word)
          if matches.size == 1
            # Replace word with completion
            event.line.replace(event.line.text.sub(/#{Regexp.escape(word)}$/, matches.first))
          elsif matches.size > 1
            puts "\n#{matches.join('  ')}"
          end
        end
      end
    end
  end

  # === Dashboard - Terminal status display ===
  # Merged from dashboard.rb
  class Dashboard
    def initialize
      @ui = UI
    end

    def render
      clear
      header
      stats_box
      budget_box
      recent_activity
      footer
    end

    private

    def clear
      print "\e[2J\e[H"
    end

    def header
      puts @ui.bold("\n  MASTER Dashboard v#{VERSION}\n")
      puts "  #{'-' * 40}\n"
    end

    def stats_box
      stats = fetch_stats

      puts "  #{@ui.bold('System Status')}"
      puts "    Model Tier:    #{stats[:tier]}"
      puts "    Budget:        #{UI.currency(stats[:remaining])} / #{UI.currency(stats[:limit])}"
      puts "    Circuit:       #{stats[:circuits_ok]} ok, #{stats[:circuits_tripped]} tripped"
      puts "    Axioms:        #{stats[:axioms]}"
      puts "    Council:       #{stats[:council]} personas"
      puts
    end

    def budget_box
      cap = LLM.spending_cap
      spent = cap - LLM.budget_remaining
      pct = (spent / cap * 100).round(1)

      bar_width = 30
      filled = (pct / 100.0 * bar_width).round
      bar = "[#{'█' * filled}#{'░' * (bar_width - filled)}]"

      puts "  #{@ui.bold('Budget Usage')}"
      puts "    #{bar} #{pct}%"
      puts
    end

    def recent_activity
      puts "  #{@ui.bold('Recent Activity')}"

      costs = DB.recent_costs(limit: 5)

      if costs.empty?
        puts "    (no activity yet)"
      else
        costs.each do |row|
          model = row[:model].split("/").last
          cost = row[:cost]
          created = row[:created_at]
          puts "    #{created[11, 5]} | #{model.ljust(15)} | #{UI.currency_precise(cost)}"
        end
      end
      puts
    end

    def footer
      puts "  #{@ui.dim('Press any key to return...')}"
    end

    def fetch_stats
      {
        tier: LLM.tier,
        remaining: LLM.budget_remaining,
        limit: LLM.spending_cap,
        circuits_ok: LLM.models.count { |m| LLM.circuit_closed?(m.id) },
        circuits_tripped: LLM.models.count { |m| !LLM.circuit_closed?(m.id) },
        axioms: DB.axioms.size,
        council: DB.council.size,
      }
    rescue StandardError
      { tier: :unknown, remaining: 0, limit: 10, circuits_ok: 0, circuits_tripped: 0, axioms: 0, council: 0 }
    end
  end

  # === Keybindings - Keyboard shortcuts for REPL ===
  # Merged from keybindings.rb
  module Keybindings
    BINDINGS = {
      ctrl_c:    { action: :interrupt,   desc: "Cancel current operation" },
      ctrl_d:    { action: :exit,        desc: "Exit MASTER" },
      ctrl_l:    { action: :clear,       desc: "Clear screen" },
      ctrl_r:    { action: :history,     desc: "Search history" },
      ctrl_z:    { action: :undo,        desc: "Undo last operation" },
      ctrl_y:    { action: :redo,        desc: "Redo undone operation" },
      tab:       { action: :autocomplete, desc: "Tab completion" },
      up:        { action: :history_up,  desc: "Previous command" },
      down:      { action: :history_down, desc: "Next command" },
      f1:        { action: :help,        desc: "Show help" },
      f2:        { action: :status,      desc: "Show status" }
    }.freeze

    extend self

    def setup(reader)
      return unless reader.respond_to?(:on)

      reader.on(:keyctrl_l) { print "\e[2J\e[H" }
      reader.on(:keyctrl_z) { Undo.undo if defined?(Undo) }
      reader.on(:keyctrl_y) { Undo.redo if defined?(Undo) }
    end

    def help_text
      lines = ["Keyboard Shortcuts:", ""]
      BINDINGS.each do |key, info|
        key_name = key.to_s.gsub('_', '+').gsub('ctrl', 'Ctrl')
        lines << "  #{key_name.ljust(12)} #{info[:desc]}"
      end
      lines.join("\n")
    end
  end

  # === Progress - Show progress during LLM calls (NN/g: visibility of system status) ===
  # Merged from progress.rb
  module Progress
    extend self

    SPINNERS = {
      dots:    %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏],
      line:    %w[- \\ | /],
      blocks:  %w[▏ ▎ ▍ ▌ ▋ ▊ ▉ █],
      arrows:  %w[← ↖ ↑ ↗ → ↘ ↓ ↙],
      circuit: %w[◯ ◔ ◑ ◕ ●]
    }.freeze

    class Spinner
      def initialize(message = "Processing...", style: :dots)
        @message = message
        @frames = SPINNERS[style] || SPINNERS[:dots]
        @index = 0
        @running = false
        @thread = nil
      end

      def start
        @running = true
        @thread = Thread.new do
          while @running
            print "\r  #{@frames[@index % @frames.size]} #{@message}"
            @index += 1
            sleep 0.1
          end
        end
        self
      end

      def update(message)
        @message = message
      end

      def stop(final_message = nil)
        @running = false
        @thread&.join
        print "\r#{' ' * 60}\r"
        puts "  ✓ #{final_message}" if final_message
      end

      def success(message)
        stop("#{message}")
      end

      def error(message)
        @running = false
        @thread&.join
        print "\r#{' ' * 60}\r"
        puts "  ✗ #{message}"
      end
    end

    class ProgressBar
      def initialize(total:, message: "Progress")
        @total = total
        @current = 0
        @message = message
        @start_time = Time.now
      end

      def advance(by = 1)
        @current += by
        render
      end

      def set(value)
        @current = value
        render
      end

      def finish
        @current = @total
        render
        puts
      end

      private

      def render
        pct = (@current.to_f / @total * 100).round(1)
        bar_width = 30
        filled = (pct / 100.0 * bar_width).round
        bar = "[#{'█' * filled}#{'░' * (bar_width - filled)}]"

        elapsed = Time.now - @start_time
        eta = @current > 0 ? (elapsed / @current * (@total - @current)).round : 0

        print "\r  #{@message}: #{bar} #{pct}% (#{@current}/#{@total}) ETA: #{eta}s"
      end
    end

    def spinner(message = "Processing...", style: :dots, &block)
      s = Spinner.new(message, style: style)
      s.start

      result = yield
      s.success("Done")
      result
    rescue => e
      s.error(e.message)
      raise
    end

    def progress_bar(total:, message: "Progress", &block)
      bar = ProgressBar.new(total: total, message: message)
      yield bar
      bar.finish
    end

    def thinking(duration = nil)
      frames = %w[thinking. thinking.. thinking...]
      spinner = Spinner.new(frames.first, style: :circuit)
      spinner.start

      if block_given?
        result = yield
        spinner.success("Complete")
        result
      else
        # Auto-stop after duration if given
        if duration
          sleep duration
          spinner.stop
        end
        spinner
      end
    end
  end

  # Backward compatibility aliases - map top-level to UI sub-modules
  Help = UI::Help
  ErrorSuggestions = UI::ErrorSuggestions
  NNGChecklist = UI::NNGChecklist
  Confirmations = UI::Confirmations
  ConfirmationGate = UI::Confirmations

  # === DiffView - Generate unified diffs for preview ===
  # Merged from diff_view.rb
  module DiffView
    extend self

    # Generate a unified diff between original and modified content
    # Returns a string in unified diff format
    def unified_diff(original, modified, filename: "file", context_lines: 3)
      original_lines = original.lines.map(&:chomp)
      modified_lines = modified.lines.map(&:chomp)

      output = []
      output << "--- a/#{filename}"
      output << "+++ b/#{filename}"

      # Use a simple line-by-line comparison for now
      hunks = compute_hunks(original_lines, modified_lines, context_lines)
      
      hunks.each do |hunk|
        output << hunk[:header]
        output.concat(hunk[:lines])
      end

      output.join("\n") + "\n"
    end

    private

    def compute_hunks(original, modified, context)
      # Find all differences
      changes = []
      max_len = [original.length, modified.length].max
      
      (0...max_len).each do |i|
        orig_line = original[i]
        mod_line = modified[i]
        
        if orig_line == mod_line
          changes << { type: :same, orig: i, mod: i }
        elsif orig_line.nil?
          changes << { type: :add, orig: i, mod: i }
        elsif mod_line.nil?
          changes << { type: :delete, orig: i, mod: i }
        else
          # Line changed
          changes << { type: :change, orig: i, mod: i }
        end
      end

      # Group into hunks
      hunks = []
      i = 0
      
      while i < changes.length
        # Skip unchanged lines that are far from changes
        while i < changes.length && changes[i][:type] == :same
          # Look ahead to find next change
          next_change = find_next_change(changes, i)
          break if next_change && (next_change - i) <= context * 2
          i += 1
        end
        
        next if i >= changes.length
        
        # Start a new hunk
        hunk_start = [i - context, 0].max
        
        # Find end of hunk (include context after last change)
        hunk_end = i
        while hunk_end < changes.length
          if changes[hunk_end][:type] != :same
            # Found a change, continue
            hunk_end += 1
          else
            # Check if there's another change within context
            next_change = find_next_change(changes, hunk_end)
            if next_change && (next_change - hunk_end) <= context * 2
              hunk_end = next_change
            else
              # No more changes nearby, add context and stop
              hunk_end = [hunk_end + context, changes.length].min
              break
            end
          end
        end
        
        # Build this hunk
        orig_start = changes[hunk_start][:orig]
        mod_start = changes[hunk_start][:mod]
        orig_count = 0
        mod_count = 0
        lines = []
        
        (hunk_start...hunk_end).each do |j|
          change = changes[j]
          case change[:type]
          when :same
            lines << " #{original[change[:orig]]}"
            orig_count += 1
            mod_count += 1
          when :delete
            lines << "-#{original[change[:orig]]}" if change[:orig] < original.length
            orig_count += 1
          when :add
            lines << "+#{modified[change[:mod]]}" if change[:mod] < modified.length
            mod_count += 1
          when :change
            lines << "-#{original[change[:orig]]}" if change[:orig] < original.length
            lines << "+#{modified[change[:mod]]}" if change[:mod] < modified.length
            orig_count += 1
            mod_count += 1
          end
        end
        
        unless lines.empty?
          hunks << {
            header: "@@ -#{orig_start + 1},#{orig_count} +#{mod_start + 1},#{mod_count} @@",
            lines: lines
          }
        end
        
        i = hunk_end
      end

      hunks
    end

    def find_next_change(changes, start)
      (start...changes.length).each do |i|
        return i if changes[i][:type] != :same
      end
      nil
    end
  end
end

# Load ui submodules for backwards compatibility
require_relative "ui/spinner" if File.exist?(File.join(__dir__, "ui/spinner.rb"))
require_relative "ui/table" if File.exist?(File.join(__dir__, "ui/table.rb"))

