# frozen_string_literal: true

module MASTER
  # Commands - REPL command dispatcher
  module Commands
    extend self

    @last_command = nil

    # Shortcuts for power users
    SHORTCUTS = {
      "!!" => :repeat_last,
      "!r" => "refactor",
      "!c" => "chamber",
      "!e" => "evolve",
      "!s" => "status",
      "!b" => "budget",
      "!h" => "help",
    }.freeze

    def dispatch(input, pipeline:)
      # Handle shortcuts
      if input.strip == "!!"
        return Result.err("No previous command") unless @last_command
        input = @last_command
      elsif (shortcut = SHORTCUTS[input.strip])
        input = shortcut.is_a?(Symbol) ? @last_command : shortcut
      end

      # Guard against nil after shortcut resolution
      return Result.err("No previous command to repeat.") if input.nil?

      @last_command = input unless input.to_s.start_with?("!")

      parts = input.strip.split(/\s+/, 2)
      cmd = parts[0]&.downcase
      args = parts[1]

      case cmd
      when "help", "?"
        Help.show(args)
        nil
      when "status"
        Dashboard.new.render
        nil
      when "budget"
        print_budget
        nil
      when "clear"
        print "\e[2J\e[H"
        nil
      when "history"
        print_cost_history
        nil
      when "context"
        print_context_usage
        nil
      when "session"
        manage_session(args)
        nil
      when "sessions"
        print_saved_sessions
        nil
      when "forget", "undo"
        undo_last_exchange
        nil
      when "summary"
        print_session_summary
        nil
      when "health"
        print_health
        nil
      when "axioms-stats", "stats"
        print_axiom_stats
        nil
      when "refactor"
        refactor(args)
      when "chamber"
        chamber(args)
      when "evolve"
        evolve(args)
      when "opportunities", "opps"
        opportunities(args)
      when "axioms", "language-axioms"
        print_language_axioms(args)
        nil
      when "selftest", "self-test", "selfrun", "self-run"
        SelfTest.run
      when "speak", "say"
        speak(args)
        nil
      when "fix"
        fix_code(args)
        nil
      when "browse"
        browse_url(args)
        nil
      when "ideate", "brainstorm"
        ideate(args)
      when "model", "use"
        select_model(args)
        nil
      when "models"
        list_models
        nil
      when "pattern", "mode"
        select_pattern(args)
        nil
      when "patterns", "modes"
        list_patterns
        nil
      when "exit", "quit"
        :exit
      else
        pipeline.call({ text: input })
      end
    end

    class << self
      private

      def fix_code(args)
        path = args&.strip
        if path.nil? || path.empty?
          path = "."
        end

        if File.directory?(path)
          fixer = AutoFixer.new(mode: :moderate)
          result = fixer.fix_directory(path)
          if result.ok?
            puts "\n  ✓ Fixed #{result.value[:total_fixes]} issues in #{result.value[:files_fixed]} files\n"
          else
            UI.error(result.error)
          end
        elsif File.exist?(path)
          fixer = AutoFixer.new(mode: :moderate)
          result = fixer.fix(path)
          if result.ok?
            puts "\n  ✓ Fixed #{result.value[:fixed]} issues in #{path}\n"
          else
            UI.error(result.error)
          end
        else
          UI.error("Path not found: #{path}")
        end
      end

      def browse_url(args)
        url = args&.strip
        if url.nil? || url.empty?
          puts "\n  Usage: browse <url>\n"
          return
        end

        url = "https://#{url}" unless url.start_with?("http")
        result = Web.browse(url)
        
        if result.ok?
          puts "\n#{result.value[:content]}\n"
        else
          UI.error(result.error)
        end
      end

      def ideate(args)
        prompt = args&.strip
        if prompt.nil? || prompt.empty?
          puts "\n  Usage: ideate <topic or problem>\n"
          return nil
        end

        chamber = Chamber.new(llm: LLM)
        result = chamber.ideate(prompt: prompt)
        
        if result.ok?
          data = result.value
          puts "\n  Ideas:"
          data[:ideas].first(5).each { |i| puts "    • #{i[0..80]}" }
          puts "\n  Synthesis:"
          puts "    #{data[:final][0..500]}..."
          puts "\n  Cost: #{UI.currency(data[:cost])}\n"
        end
        result
      end

      def select_model(args)
        unless args && !args.strip.empty?
          puts "\n  Current model: #{LLM.current_model || 'auto'}"
          puts "  Current tier:  #{LLM.current_tier || LLM.tier}"
          puts "  Use 'model <name>' to switch, 'models' to list.\n"
          return
        end

        query = args.strip.downcase
        found = LLM.models.find { |m| m[:id].downcase.include?(query) || m[:name]&.downcase&.include?(query) }

        if found
          LLM.current_model = LLM.extract_model_name(found[:id])
          LLM.current_tier = found[:tier]&.to_sym || :fast
          puts "\n  ✓ Switched to #{found[:id]} (#{found[:tier]})\n"
        else
          puts "\n  ✗ No model matching '#{args}' found."
          puts "  Use 'models' to list available models.\n"
        end
      end

      def list_models
        UI.header("Available Models")
        LLM::TIER_ORDER.each do |tier|
          models = LLM.model_tiers[tier]
          next if models.nil? || models.empty?
          puts "  #{tier}:"
          models.each do |m|
            status = CircuitBreaker.circuit_closed?(m) ? "✓" : "✗"
            short = m.split("/").last[0, 30]
            puts "    #{status} #{short}"
          end
        end
        puts
      end

      def select_pattern(args)
        unless args && !args.strip.empty?
          current = Pipeline.current_pattern rescue :auto
          puts "\n  Current pattern: #{current}"
          puts "  Available: #{Executor::PATTERNS.join(', ')}, auto"
          puts "  Use 'pattern <name>' to switch.\n"
          return
        end

        pattern = args.strip.downcase.to_sym
        if pattern == :auto || Executor::PATTERNS.include?(pattern)
          Pipeline.current_pattern = pattern
          puts "\n  ✓ Pattern set to: #{pattern}\n"
        else
          puts "\n  ✗ Unknown pattern '#{args}'."
          puts "  Available: #{Executor::PATTERNS.join(', ')}, auto\n"
        end
      end

      def list_patterns
        UI.header("Executor Patterns")
        patterns = {
          react: "Tight thought-action-observation loop. Best for exploration.",
          pre_act: "Plan first, then execute. Best for multi-step tasks (70% better recall).",
          rewoo: "Batch reasoning upfront. Best for cost-sensitive tasks.",
          reflexion: "Self-critique and retry. Best for fixing/debugging.",
          auto: "Auto-select based on task characteristics (default)."
        }
        
        current = Pipeline.current_pattern rescue :auto
        patterns.each do |name, desc|
          marker = name == current ? "▸" : " "
          puts "  #{marker} #{name.to_s.ljust(10)} #{desc}"
        end
        puts
      end

      def print_budget
        tier = LLM.tier
        remaining = LLM.budget_remaining
        spent = LLM::SPENDING_CAP - remaining
        pct = (spent / LLM::SPENDING_CAP * 100).round(1)

        UI.header("Budget Status")
        puts "  Tier:      #{tier}"
        puts "  Remaining: #{UI.currency(remaining)}"
        puts "  Spent:     #{UI.currency(spent)} (#{pct}%)"
        puts
      end

      def print_context_usage
        session = Session.current
        u = ContextWindow.usage(session)

        UI.header("Context Window")
        puts "  #{ContextWindow.bar(session)}"
        puts "  Used:      #{humanize_tokens(u[:used])}"
        puts "  Limit:     #{humanize_tokens(u[:limit])}"
        puts "  Remaining: #{humanize_tokens(u[:remaining])}"
        puts "  Messages:  #{session.message_count}"
        puts
      end

      def humanize_tokens(n)
        n >= 1000 ? "#{(n / 1000.0).round(1)}k" : n.to_s
      end

      def print_cost_history
        costs = DB.recent_costs(limit: 10)

        if costs.empty?
          puts "\n  No history yet.\n"
        else
          UI.header("Recent Queries", width: 50)
          costs.each do |row|
            model = row[:model].split("/").last[0, 12]
            tokens_in = row[:tokens_in]
            tokens_out = row[:tokens_out]
            cost = row[:cost]
            created = row[:created_at]
            puts "  #{created[0, 16]} | #{model.ljust(12)} | #{tokens_in}→#{tokens_out} | #{UI.currency_precise(cost)}"
          end
          puts
        end
      end

      def refactor(args)
        return Result.err("Usage: refactor <file> [--preview|--raw|--apply]") unless args

        parts = args.strip.split(/\s+/)
        return Result.err("Usage: refactor <file> [--preview|--raw|--apply]") if parts.empty?
        
        file = parts.first
        
        # Check if the first argument looks like a flag
        if file&.start_with?("--")
          return Result.err("Usage: refactor <file> [--preview|--raw|--apply]")
        end
        
        mode = extract_mode(parts[1..-1])

        return Result.err("File path cannot be empty") if file.nil? || file.empty?
        
        path = File.expand_path(file)
        return Result.err("File not found: #{file}") unless File.exist?(path)

        original_code = File.read(path)
        chamber = Chamber.new
        result = chamber.deliberate(original_code, filename: File.basename(path))

        return result unless result.ok? && result.value[:final]

        proposed_code = result.value[:final]
        council_info = result.value[:council]

        # Pass through lint + render stages for governance
        linted = lint_output(proposed_code)
        rendered = render_output(linted)

        # Format output based on mode
        case mode
        when :raw
          display_raw_output(result, rendered, council_info)
        when :apply
          apply_refactor(path, original_code, rendered, result, council_info)
        else # :preview (default)
          display_preview(path, original_code, rendered, result, council_info)
        end

        result
      end

      def chamber(file)
        refactor(file)
      end

      def evolve(path)
        path ||= MASTER.root
        evolver = Evolve.new
        result = evolver.run(path: path, dry_run: true)

        UI.header("Evolution Analysis (dry run)")
        puts "  Files processed: #{result[:files_processed]}"
        puts "  Improvements found: #{result[:improvements]}"
        puts "  Cost: #{UI.currency_precise(result[:cost])}"
        puts

        Result.ok(result)
      end

      def speak(text)
        return puts "  Usage: speak <text>" unless text

        result = Speech.speak(text)
        puts "  TTS Error: #{result.error}" if result.err?
      end

      def manage_session(args)
        case args&.split&.first
        when "new"
          Session.start_new
          puts "  New session: #{UI.truncate_id(Session.current.id)}"
        when "save"
          Session.current.save
          puts "  Session saved: #{UI.truncate_id(Session.current.id)}"
        when "load", "resume"
          id = args.split[1]
          if id && Session.resume(id)
            puts "  Resumed session: #{UI.truncate_id(Session.current.id)}"
          else
            puts "  Session not found: #{id}"
          end
        when "info"
          s = Session.current
          UI.header("Session Info")
          puts "  ID:       #{s.id}"
          puts "  Messages: #{s.message_count}"
          puts "  Cost:     #{UI.currency_precise(s.total_cost)}"
          puts "  Created:  #{s.created_at}"
          puts
        else
          puts "  Usage: session [new|save|load <id>|info]"
        end
      end

      def print_saved_sessions
        sessions = Session.list
        if sessions.empty?
          puts "\n  No saved sessions.\n"
        else
          UI.header("Saved Sessions")
          sessions.each do |id|
            data = Memory.load_session(id)
            next unless data

            msgs = data[:history]&.size || 0
            puts "  #{UI.truncate_id(id)} | #{msgs} messages"
          end
          puts
        end
      end

      def undo_last_exchange
        session = Session.current
        if session.history.size < 2
          puts "  Nothing to forget."
          return
        end

        # IMMUTABLE_HISTORY: append tombstone instead of mutating
        session.history << { role: :system, content: "[UNDO: Previous 2 messages hidden]", tombstone: true, undone_at: Time.now.utc.iso8601 }
        session.instance_variable_set(:@undo_count, (session.instance_variable_get(:@undo_count) || 0) + 1)
        session.instance_variable_set(:@dirty, true)
        puts "  Marked last exchange as undone. Context preserved for history."
      end

      def print_session_summary
        session = Session.current
        if session.history.empty?
          puts "  No conversation yet."
          return
        end

        UI.header("Conversation Summary")
        puts "  Messages: #{session.message_count}"
        puts "  Cost:     #{UI.currency_precise(session.total_cost)}"
        puts

        history = session.history
        puts "  First message: #{truncate(history.first[:content], 60)}"
        puts "  Last message:  #{truncate(history.last[:content], 60)}" if history.size > 1
        puts
      end

      def truncate(str, max)
        return str if str.length <= max
        "#{str[0, max - 3]}..."
      end

      def print_health
        UI.header("Health Check")
        checks = []

        # Check API key
        api_key = ENV.fetch("OPENROUTER_API_KEY", nil)
        checks << { name: "API Key", ok: !api_key.nil? && !api_key.empty? }

        # Check var directory writable
        var_ok = File.writable?(Paths.var) rescue false
        checks << { name: "Var writable", ok: var_ok }

        # Check DB initialized
        db_ok = DB.axioms.any? rescue false
        checks << { name: "DB seeded", ok: db_ok }

        # Check models available
        model = LLM.select_available_model
        checks << { name: "Models available", ok: !model.nil? }

        # Check budget
        budget_ok = LLM.budget_remaining > 0
        checks << { name: "Budget remaining", ok: budget_ok }

        checks.each do |c|
          status = c[:ok] ? UI.pastel.green("✓") : UI.pastel.red("✗")
          puts "  #{status} #{c[:name]}"
        end

        all_ok = checks.all? { |c| c[:ok] }
        puts
        puts all_ok ? "  System healthy." : "  Some checks failed."
        puts
      end

      def print_axiom_stats
        summary = AxiomStats.summary
        puts
        puts summary
        puts
      end

      def print_language_axioms(args)
        if defined?(LanguageAxioms)
          puts "\nLanguage Axioms:"
          axioms = LanguageAxioms.all_axioms
          axioms.group_by { |a| a["language"] }.each do |lang, rules|
            puts "  #{lang}: #{rules.size} axiom#{'s' if rules.size != 1}"
          end
          puts
        else
          puts "LanguageAxioms module not available"
        end
      end

      def opportunities(path)
        path ||= MASTER.root
        UI.header("Analyzing for opportunities")
        puts "  Path: #{path}"
        puts "  This may take a moment...\n\n"

        result = CodeReview.opportunities(path)
        if result[:error]
          puts "  Error: #{result[:error]}"
        else
          %i[architectural micro_refinement ui_ux typography].each do |cat|
            items = result[cat] || []
            next if items.empty?

            puts "  #{cat.to_s.gsub('_', ' ').upcase} (#{items.size})"
            items.first(5).each { |item| puts "    • #{item}" }
            puts
          end
        end

        Result.ok(result)
      end

      # Refactor helper methods
      def extract_mode(args)
        mode_arg = args.find { |a| a.start_with?("--") }
        case mode_arg
        when "--raw" then :raw
        when "--apply" then :apply
        when "--preview" then :preview
        else :preview # default
        end
      end

      def lint_output(text)
        lint_stage = Stages::Lint.new
        result = lint_stage.call({ response: text })
        result.ok? ? result.value[:response] : text
      end

      def render_output(text)
        render_stage = Stages::Render.new
        result = render_stage.call({ response: text })
        result.ok? ? result.value[:rendered] : text
      end

      def format_council_summary(council_info)
        return nil unless council_info

        if council_info[:vetoed_by]&.any?
          "  Council: VETOED by #{council_info[:vetoed_by].join(', ')}"
        elsif council_info[:consensus]
          pct = (council_info[:consensus] * 100).round(0)
          verdict = council_info[:verdict] || :unknown
          "  Council: #{verdict.to_s.upcase} (#{pct}% consensus)"
        else
          nil
        end
      end

      def display_raw_output(result, rendered, council_info)
        puts "\n  Proposals: #{result.value[:proposals].size}"
        puts "  Cost: #{UI.currency_precise(result.value[:cost])}"
        if (summary = format_council_summary(council_info))
          puts summary
        end
        puts "\n#{rendered}\n"
      end

      def display_preview(path, original, proposed, result, council_info)
        require_relative "diff_view"
        diff = DiffView.unified_diff(original, proposed, filename: File.basename(path))
        
        puts "\n  Proposals: #{result.value[:proposals].size}"
        puts "  Cost: #{UI.currency_precise(result.value[:cost])}"
        if (summary = format_council_summary(council_info))
          puts summary
        end
        puts "\n#{diff}"
        puts "  Use --apply to write changes, --raw to see full output"
      end

      def apply_refactor(path, original, proposed, result, council_info)
        require_relative "diff_view"
        diff = DiffView.unified_diff(original, proposed, filename: File.basename(path))
        
        puts "\n  Proposals: #{result.value[:proposals].size}"
        puts "  Cost: #{UI.currency_precise(result.value[:cost])}"
        if (summary = format_council_summary(council_info))
          puts summary
        end
        puts "\n#{diff}"
        
        # Prompt for confirmation
        print "\n  Apply these changes? [y/N] "
        response = $stdin.gets&.strip&.downcase
        
        if response == "y" || response == "yes"
          # Track original content for undo
          Undo.track_edit(path, original)
          
          # Write changes to disk
          File.write(path, proposed)
          
          puts "  ✓ Changes applied to #{path}"
          puts "  (Use 'undo' command to revert)"
        else
          puts "  Changes not applied"
        end
      end

      def print_language_axioms(args)
        axioms = DB.axioms
        if axioms.empty?
          puts "\n  No language axioms found.\n"
          return
        end

        UI.header("Language Axioms")
        axioms.each do |axiom|
          name = axiom[:name] || axiom["name"] || "unnamed"
          desc = axiom[:description] || axiom["description"] || ""
          puts "  #{name.ljust(20)} #{desc[0, 50]}"
        end
        puts
      end
    end
  end
end
