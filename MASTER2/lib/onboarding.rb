# frozen_string_literal: true

module MASTER
  # Onboarding - First-run experience and helpful prompts
  module Onboarding
    extend self

    WELCOME = <<~MSG
      Welcome to MASTER v#{VERSION}

      Quick start:
        • Just type a question or request
        • Use 'help' for all commands
        • Use 'status' to see system state

      Examples:
        "Explain this Ruby code: def foo; end"
        "refactor lib/example.rb"
        "chamber lib/complex.rb"

    MSG

    EXAMPLES = [
      "Explain Ruby blocks vs procs",
      "How do I use OpenBSD pledge?",
      "Review this code for bugs",
      "help",
    ].freeze

    EMPTY_HINTS = [
      "Try: 'help' to see available commands",
      "Try: 'status' to see system state",
      "Try: 'budget' to check remaining funds",
      "Just type a question to ask the LLM",
    ].freeze

    class << self
      def first_run?
        !File.exist?(first_run_marker)
      end

      def show_welcome
        return unless first_run?

        puts
        puts UI.bold("MASTER v#{VERSION}")
        puts
        WELCOME.each_line { |l| puts "  #{l}" }
        mark_first_run
      end

      def suggest_on_empty
        hint = EMPTY_HINTS.sample
        puts UI.dim("  #{hint}")
      end

      def did_you_mean(input)
        commands = Help::COMMANDS.keys.map(&:to_s)
        word = input.strip.split.first&.downcase
        return nil unless word

        commands.find { |c| Utils.levenshtein(word, c) <= 2 }
      end

      def show_did_you_mean(input)
        suggestion = did_you_mean(input)
        return false unless suggestion

        puts UI.dim("  Did you mean: #{suggestion}?")
        true
      end

      private

      def first_run_marker
        File.join(Paths.var, ".first_run_complete")
      end

      def mark_first_run
        FileUtils.mkdir_p(File.dirname(first_run_marker))
        File.write(first_run_marker, Time.now.iso8601)
      end
    end
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

    # Gate operation with three phases: propose → confirm → execute
    # Merged from confirmation_gate.rb
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

    # Stage class for pipeline integration
    # Merged from confirmation_gate.rb
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

  # Backward compatibility alias for confirmation_gate.rb
  ConfirmationGate = Confirmations

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

  # === NNgChecklist - Nielsen Norman Group usability heuristics compliance ===
  # Merged from nng_checklist.rb
  module NNgChecklist
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

    # Lint HTML file for web UI best practices
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

    # Lint all view files
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

    # Check color contrast (simplified WCAG check)
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
end
