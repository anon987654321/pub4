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
      when "refactor"
        refactor(args)
      when "chamber"
        chamber(args)
      when "evolve"
        evolve(args)
      when "opportunities", "opps"
        opportunities(args)
      when "selftest", "self-test", "selfrun", "self-run"
        SelfTest.run
      when "speak", "say"
        speak(args)
        nil
      when "exit", "quit"
        :exit
      else
        pipeline.call({ text: input })
      end
    end

    class << self
      private

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

      def refactor(file)
        return Result.err("Usage: refactor <file>") unless file

        path = File.expand_path(file)
        return Result.err("File not found: #{file}") unless File.exist?(path)

        code = File.read(path)
        chamber = Chamber.new
        result = chamber.deliberate(code, filename: File.basename(path))

        if result.ok? && result.value[:final]
          puts "\n  Proposals: #{result.value[:proposals].size}"
          puts "  Cost: #{UI.currency_precise(result.value[:cost])}"
          puts "\n#{result.value[:final]}\n"
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

        result = EdgeTTS.speak_and_play(text)
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

        session.history.pop(2)
        session.instance_variable_set(:@dirty, true)
        puts "  Forgot last exchange. Context rolled back."
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
    end
  end
end
