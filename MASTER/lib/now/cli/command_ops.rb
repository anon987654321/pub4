# frozen_string_literal: true

module Master
  module Now
    class CLI
      def run_restart
        @session.save!
        puts @renderer.render("restart: exec'ing fresh master in place", mode: :dim)
        $stdout.flush
        Kernel.exec(RbConfig.ruby, $PROGRAM_NAME, *ARGV)
      end

      def run_undo
        res = @undo.undo!
        if res.is_a?(Master::Result) && res.ok?
          puts @renderer.render("undo: #{Array(res.value!).join(", ")}", mode: :success)
        else
          puts @renderer.render(res.message, mode: :warning)
        end
      end

      def run_redo
        res = @undo.redo!
        if res.is_a?(Master::Result) && res.ok?
          puts @renderer.render("redo: #{Array(res.value!).join(", ")}", mode: :success)
        else
          puts @renderer.render(res.message, mode: :warning)
        end
      end

      def run_history
        lines = @undo.history(limit: 10)
        if lines.empty?
          puts @renderer.render("no undo history", mode: :dim)
        else
          lines.each { |l| puts @renderer.render(l, mode: :dim) }
        end
      end

      def run_why
        router = Master::Routing::ModelRouter.new(config: @config, root: Master::ROOT)
        task = @session.phase == :implement ? :implement : :exploration
        tier = router.current_tier(task_type: task)
        rows = router.score_breakdown(task_type: task).first(5)
        puts @renderer.render("router: phase=#{@session.phase} task=#{task} tier=#{tier}", mode: :dim)
        rows.each_with_index do |r, i|
          line = format("  %d. %-40s q=%.2f s=%.2f c=%.2f → %.3f",
                        i + 1, r[:id].to_s[0, 40], r[:q], r[:s], r[:c], r[:total])
          puts @renderer.render(line, mode: :dim)
        end
      end

      def toggle_focus
        @focus_mode = !@focus_mode
        puts @renderer.render("focus: #{@focus_mode ? "on" : "off"}", mode: :dim)
      end

      def run_last
        if @last_input
          puts @renderer.render("rerun: #{@last_input[0, 60]}", mode: :dim)
          run_input(@last_input)
        else
          puts @renderer.render("no prior input", mode: :dim)
        end
      end

      def run_cmd
        puts @renderer.render("unified: /run <task description>   (recommended primary interface for most work)", mode: :dim)
        puts @renderer.render("explicit: #{SLASH_COMMANDS.join("  ")}", mode: :dim)
        puts @renderer.render("or just describe what you want — full pipeline intent inference", mode: :dim)
      end

      def toggle_dmesg
        if @dmesg_sub
          @dmesg_sub.call
          @dmesg_sub = nil
          puts @renderer.render("dmesg: off", mode: :dim)
        else
          @dmesg_sub = @bus&.subscribe("*") do |payload|
            ts = payload.fetch(:ts, 0)
            line = "  [#{ts.to_s.rjust(7)}] #{payload[:event]}"
            begin
              $stdout.puts @renderer.render(line, mode: :dim)
            rescue StandardError => e
              Master::Ground::Swallow.log(e, context: "CLI.toggle_dmesg")
            end
          end
          puts @renderer.render("dmesg: on (events stream below)", mode: :dim)
        end
      end

      def toggle_chips
        @show_chips = !@show_chips
        puts @renderer.render("chips: #{@show_chips ? "on" : "off"}", mode: :dim)
      end

      def run_principles
        c = Master::Ground::Constitution.new
        lines = c.list
        if lines.empty?
          puts @renderer.render("no principles loaded (data/principles/*.md)", mode: :dim)
        else
          puts @renderer.render("constitution: #{lines.size} principle(s)", mode: :dim)
          lines.each { |l| puts @renderer.render("  #{l}", mode: :dim) }
        end
      end

      def run_propose
        rows = proposer.call
        if rows.empty?
          puts @renderer.render("propose: nothing pressing — try /history or scan a dir", mode: :dim)
          return
        end
        puts @renderer.render("propose0: top #{rows.size} suggestion(s)", mode: :dim)
        rows.each_with_index do |r, i|
          line = format("  %d. %-22s %s", i + 1, r[:action], r[:reason])
          puts @renderer.render(line, mode: :dim)
        end
      end

      def run_ui_critique    = run_critique(:ui, label: "ui-critique", intro: "assembling panel — brutal honesty mode")
      def run_sound_critique = run_critique(:sound, label: "sound-critique", intro: "assembling audio panel")

      def run_critique(mode, label:, intro:)
        puts @renderer.render("#{label}: #{intro}", mode: :dim)
        critic = Master::Judge::Council::Critique.new(mode: mode, agent: @agent, event_bus: @bus)
        result = critic.run
        unless result.ok?
          puts @renderer.render("#{label}: #{result.message}", mode: :warning)
          return
        end
        data = result.value!
        picks = data[:cherry_picks]
        puts @renderer.render("#{label}: #{picks.size} cherry-pick(s)", mode: :dim)
        picks.each { |p| puts @renderer.render("  cherry: #{p}", mode: :dim) }
        data[:feedback].each do |f|
          puts @renderer.render("  [#{f[:persona]}] #{f[:feedback].to_s.lines.first.to_s.strip}", mode: :dim)
        end
      end

      def run_rebuild
        puts @renderer.render("rebuild: syntax check + session save + hot-restart", mode: :dim)
        lib_dir = File.join(Master::ROOT, "lib")
        errors = []
        changed_lib_files(lib_dir).each do |path|
          ok = system("ruby34 -c #{path} > /dev/null 2>&1")
          errors << path unless ok
        end
        if errors.any?
          errors.each { |p| puts @renderer.render("  syntax error: #{p}", mode: :warning) }
          puts @renderer.render("rebuild: aborted — fix errors first", mode: :warning)
          return
        end
        @session.save!
        puts @renderer.render("rebuild: ok — exec'ing fresh process", mode: :dim)
        $stdout.flush
        Kernel.exec(RbConfig.ruby, $PROGRAM_NAME, *ARGV)
      end

      def run_context
        query = @last_input.to_s
        puts @renderer.render("context: gathering for query=#{query[0, 60]}", mode: :dim)
        provider = Master::Ground::ContextProvider.new
        rows = provider.brief(query, limit: 8)
        if rows.empty?
          puts @renderer.render("context: nothing found", mode: :dim)
        else
          rows.each { |r| puts @renderer.render("  #{r}", mode: :dim) }
        end
        @bus&.publish("attention:context", query: query, rows: rows.size)
      end

      def run_checkpoint
        puts @renderer.render("checkpoint: snapshotting changed files", mode: :dim)
        lib_dir = File.join(Master::ROOT, "lib")
        files = changed_lib_files(lib_dir)
        cp = Master::Ground::Checkpoint.new
        result = cp.create(label: "manual", files: files)
        id = result.respond_to?(:fetch) ? result[:id] : result.to_s
        puts @renderer.render("checkpoint: #{id} (#{files.size} file(s))", mode: :dim)
      end

      def run_verify
        puts @renderer.render("verify: checking recently landed operator symbols", mode: :dim)
        plan = {
          files: %w[lib/ground/intent_router.rb lib/ground/attention_context.rb
                    lib/ground/unfinished_ledger.rb lib/ground/orchestration_policy.rb],
          symbols: %w[Master::Ground::IntentRouter Master::Ground::AttentionContext
                      Master::Ground::UnfinishedLedger Master::Ground::OrchestrationPolicy],
          callers: %w[run_sound_critique run_rebuild run_context run_checkpoint run_verify]
        }
        checker = Master::Ground::DoneChecker.new
        result = checker.call(plan)
        result.each do |key, check_result|
          icon = check_result.is_a?(TrueClass) || check_result == :ok ? "ok" : "!!"
          puts @renderer.render("  #{icon} #{key}", mode: check_result == false ? :warning : :dim)
        end
      end

      def run_swallow_report
        puts @renderer.render("swallow-report: reading SwallowLedger", mode: :dim)
        ledger_path = File.join(@root, "runtime", "swallow_ledger.jsonl")
        unless File.exist?(ledger_path)
          puts @renderer.render("swallow-report: no ledger at #{ledger_path}", mode: :dim)
          return
        end
        lines = File.readlines(ledger_path, chomp: true).last(5)
        last = begin
          lines.last && JSON.parse(lines.last)
        rescue JSON::ParserError, StandardError => e
          Master::Ground::Swallow.log(e, context: "CLI.run_swallow_report")
          nil
        end
        unless last
          puts @renderer.render("swallow-report: ledger empty or unreadable", mode: :dim)
          return
        end
        puts @renderer.render("swallow-report: total=#{last["total"]} contexts=#{last["counts"]&.size}", mode: :dim)
        last["counts"].to_a.sort_by { |_, v| -v }.first(10).each do |ctx, n|
          puts @renderer.render("  #{n.to_s.rjust(4)}x #{ctx}", mode: :warning)
        end
      end

      def run_rails_pwa_audit
        puts @renderer.render("rails-pwa-audit: scanning DEPLOY apps", mode: :dim)
        op = Master::Rails::MobilePwaOperator.new(agent: @agent, event_bus: @bus)
        result = op.audit_all_deploy
        if result.ok?
          result.value!.each do |r|
            next puts @renderer.render("  !! #{r[:app]}: #{r[:error]}", mode: :warning) if r[:error]
            icon = { green: "ok", amber: "--", red: "!!" }.fetch(r[:verdict], "??")
            puts @renderer.render("  #{icon} #{r[:app]}: #{r.dig(:pwa, :findings)&.size || 0} finding(s)", mode: :dim)
            Array(r.dig(:pwa, :recommendations)).first(3).each do |rec|
              puts @renderer.render("     #{rec}", mode: :dim)
            end
          end
        else
          puts @renderer.render("rails-pwa-audit: #{result.message}", mode: :warning)
        end
      end

      def run_rails_pwa_fix
        puts @renderer.render("rails-pwa-fix: applying network-first SW + offline fallback to DEPLOY apps", mode: :dim)
        op = Master::Rails::MobilePwaOperator.new(agent: @agent, event_bus: @bus)
        result = op.audit_all_deploy
        return puts @renderer.render("rails-pwa-fix: #{result.message}", mode: :warning) unless result.ok?
        fixed = 0
        result.value!.each do |r|
          next puts @renderer.render("  !! #{r[:app]}: #{r[:error]}", mode: :warning) if r[:error]
          next if r[:verdict] == :green
          fix_result = op.respond_to?(:fix_app) ? op.fix_app(r[:app]) : Result.err("fix_app not implemented")
          if fix_result.ok?
            fixed += 1
            puts @renderer.render("  ok #{r[:app]}: fixed", mode: :dim)
          else
            puts @renderer.render("  !! #{r[:app]}: #{fix_result.message}", mode: :warning)
          end
        end
        puts @renderer.render("rails-pwa-fix: #{fixed} app(s) patched", mode: :dim)
      end
    end
  end
end
