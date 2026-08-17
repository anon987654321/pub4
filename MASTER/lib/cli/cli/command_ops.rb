# frozen_string_literal: true

require_relative "../command_registry/formatter"
require_relative "command_ops/system_ops"

module Master
  module CLI
    class CLI
      private

      def run_restart
        @refs.session.save!
        puts @refs.renderer.render("restart: exec'ing fresh master in place", mode: :dim)
        $stdout.flush
        ::Kernel.exec(RbConfig.ruby, $PROGRAM_NAME, *ARGV)
      end

      def run_undo
        res = @refs.undo.undo!
        if res.is_a?(Master::Result) && res.ok?
          puts @refs.renderer.render("undo: #{Array(res.value!).join(", ")}", mode: :success)
        else
          puts @refs.renderer.render(res.message, mode: :warning)
        end
      end

      def run_rollback
        res = @refs.undo.undo!
        if res.is_a?(Master::Result) && res.ok?
          puts @refs.renderer.render("rollback: #{Array(res.value!).join(", ")}", mode: :success)
        else
          puts @refs.renderer.render(res.message, mode: :warning)
        end
      end

      def run_redo
        res = @refs.undo.redo!
        if res.is_a?(Master::Result) && res.ok?
          puts @refs.renderer.render("redo: #{Array(res.value!).join(", ")}", mode: :success)
        else
          puts @refs.renderer.render(res.message, mode: :warning)
        end
      end

      def run_history
        lines = @refs.undo.history(limit: 10)
        if lines.empty?
          puts @refs.renderer.render("no undo history", mode: :dim)
        else
          lines.each { |l| puts @refs.renderer.render(l, mode: :dim) }
        end
      end

      def run_grep(pattern)
        puts @refs.renderer.render(Master::CLI::CommandRegistry.grep_history(@refs.session, pattern), mode: :dim)
      end

      def run_cost
        puts @refs.renderer.render(Master::CLI::CommandRegistry::Formatter.cost(@refs.session.cost), mode: :dim)
      end

      def run_audit
        puts @refs.renderer.render(Master::CLI::CommandRegistry.audit_changes(@refs.root), mode: :dim)
      end

      def run_watch(mode)
        case mode
        when "on"
          ENV["MASTER_WATCH"] = "1"
          msg = @refs.watch_loop ? "watch: on" : "watch: on after restart"
        when "off"
          ENV["MASTER_WATCH"] = "0"
          msg = "watch: off"
        else
          state = ENV["MASTER_WATCH"] == "1" ? "on" : "off"
          msg = "watch: #{state}"
        end
        @refs.bus&.publish("watch_loop:toggle", mode:, active: ENV["MASTER_WATCH"] == "1")
        puts @refs.renderer.render(msg, mode: :dim)
      end

      def run_why
        router = Master::CLI::Routing::ModelRouter.new(config: @refs.config, root: Master::ROOT)
        task = @refs.session.phase == :implement ? :implement : :exploration
        tier = router.current_tier(task_type: task)
        rows = router.score_breakdown(task_type: task).first(5)
        puts @refs.renderer.render("router: phase=#{@refs.session.phase} task=#{task} tier=#{tier}", mode: :dim)
        rows.each_with_index do |r, i|
          line = format("  %d. %-40s q=%.2f s=%.2f c=%.2f → %.3f",
                        i + 1, r[:id].to_s[0, 40], r[:q], r[:s], r[:c], r[:total])
          puts @refs.renderer.render(line, mode: :dim)
        end
      end

      def toggle_focus
        @focus_mode = !@focus_mode
        puts @refs.renderer.render("focus: #{@focus_mode ? "on" : "off"}", mode: :dim)
      end

      def run_last
        if @last_input
          puts @refs.renderer.render("rerun: #{@last_input[0, 60]}", mode: :dim)
          run_input(@last_input)
        else
          puts @refs.renderer.render("no prior input", mode: :dim)
        end
      end

      def run_cmd
        puts @refs.renderer.render("describe what you want — work is a sentence", mode: :dim)
        puts @refs.renderer.render("ops: #{SLASH_COMMANDS.join("  ")}", mode: :dim)
        puts @refs.renderer.render("work: say the path. /help lists the eight commands.", mode: :dim)
      end

      def run_phase(arg = "")
        gates = @refs.phase_gates || Master::Ground::PhaseGates.new(root: @refs.root, event_bus: @refs.bus)
        cmd, rest = arg.to_s.strip.split(/\s+/, 2)
        result = case cmd
                 when nil, "" then gates.status
                 when "next" then phase_result(gates.advance!)
                 when "force" then phase_result(gates.force!(rest.to_s.strip))
                 when "meet" then gates.meet_gate!(rest.to_s.strip); gates.status
                 else phase_result(gates.advance!(to: cmd))
        end
        puts @refs.renderer.render(result, mode: result.to_s.include?("blocked") ? :warning : :dim)
      end

      def phase_result(result)
        result.ok? ? result.value! : result.message
      end

      def toggle_dmesg
        if @dmesg_sub
          @dmesg_sub.call
          @dmesg_sub = nil
          puts @refs.renderer.render("dmesg: off", mode: :dim)
        else
          @dmesg_sub = @refs.bus&.subscribe("*") do |payload|
            ts = payload.fetch(:ts, 0)
            line = "  [#{ts.to_s.rjust(7)}] #{payload[:event]}"
            begin
              $stdout.puts @refs.renderer.render(line, mode: :dim)
            rescue StandardError => e
              Master::Ground::Swallow.log(e, context: "CLI.toggle_dmesg")
            end
          end
          puts @refs.renderer.render("dmesg: on (events stream below)", mode: :dim)
        end
      end

      def toggle_chips
        @show_chips = !@show_chips
        puts @refs.renderer.render("chips: #{@show_chips ? "on" : "off"}", mode: :dim)
      end

      def run_principles
        c = Master::Ground::Constitution.new
        lines = c.list
        if lines.empty?
          puts @refs.renderer.render("no principles loaded (data/rules.yml#operator_principles)", mode: :dim)
        else
          puts @refs.renderer.render("constitution: #{lines.size} principle(s)", mode: :dim)
          lines.each { |l| puts @refs.renderer.render("  #{l}", mode: :dim) }
        end
      end

      def run_propose(arg = nil)
        if arg.to_s.strip.match?(/\Areject\s+(.+)\z/)
          puts @refs.renderer.render(proposer.reject(Regexp.last_match(1)), mode: :dim)
          return
        end

        rows = proposer.call
        if rows.empty?
          puts @refs.renderer.render("propose: nothing pressing — try /history or scan a dir", mode: :dim)
          return
        end
        proposer.displayed(rows) if proposer.respond_to?(:displayed)
        puts @refs.renderer.render("propose0: top #{rows.size} suggestion(s)", mode: :dim)
        rows.group_by { |r| r[:kind] }.each { |kind, group| render_proposal_group(kind, group) }
      end

      def render_proposal_group(kind, group)
        puts @refs.renderer.render("  #{kind}:", mode: :dim)
        group.each_with_index do |r, i|
          meta = format(
            "because=%s; rank=%.2f*%.2f; est=%dt/$%.4f",
            r[:reason], r[:confidence], r[:impact], r[:estimated_tokens], r[:estimated_cost]
          )
          line = format("    %d. %-22s [%s]", i + 1, r[:action], meta)
          puts @refs.renderer.render(line, mode: :dim)
        end
      end

      def run_ui_critique    = run_critique(:ui, label: "ui-critique", intro: "assembling panel — brutal honesty mode")
      def run_sound_critique = run_critique(:sound, label: "sound-critique", intro: "assembling audio panel")
      def run_dilla_critique = run_critique(:dilla, label: "dilla-critique",
                                                    intro: "assembling dilla engine + mix panel (multi-solution → cherry-pick)")

      def run_critique(mode, label:, intro:)
        puts @refs.renderer.render("#{label}: #{intro}", mode: :dim)
        critic = Master::Review::Council::Critique.new(mode:, agent: @refs.agent, event_bus: @refs.bus)
        result = critic.run
        unless result.ok?
          puts @refs.renderer.render("#{label}: #{result.message}", mode: :warning)
          return
        end
        data = result.value!
        if data[:metrics]
          puts @refs.renderer.render("#{label}: #{data[:metrics].to_s.lines.first}", mode: :dim)
        end
        picks = data[:cherry_picks]
        puts @refs.renderer.render("#{label}: #{picks.size} cherry-pick(s)", mode: :dim)
        picks.each { |p| puts @refs.renderer.render("  cherry: #{p}", mode: :dim) }
        data[:feedback].each do |f|
          puts @refs.renderer.render("  [#{f[:persona]}] #{f[:feedback].to_s.lines.first.to_s.strip}", mode: :dim)
        end
      end
    end
  end
end
