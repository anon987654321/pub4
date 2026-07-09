# frozen_string_literal: true

require_relative "command_handlers"

module Master
  module Now
    class CLI
      private

      def set_visitor_mode_if_unauthenticated
        web_token = @refs.config&.dig("web_token")
        Fiber[:master_visitor] = true if web_token.nil? || web_token.empty?
      end

      def repl_loop
        while @running
          print prompt_for_mode
          line = safe_read_line
          break if line.nil?
          handle_repl_line(line)
        end
        stop_background_loop
        save_cli_history
        @refs.session.save!
      end

      def prompt_for_mode
        refresh_skills!
        @focus_mode ? focus_prompt : normal_prompt
      end

      def focus_prompt
        @refs.renderer.render("#{@refs.renderer.prompt_token} ", mode: :dim)
      end

      def normal_prompt
        status = status_row_if_changed
        sugg = suggested_next_prompt
        tokens = @refs.session.token_est
        prompt_lines = @refs.renderer.prompt_line(
          @refs.agent.model, @refs.session.phase,
          last_ok: @last_ok, violations: violations_count, tokens: tokens, cost: @refs.session.cost
        )
        [
          (status if status),
          (@refs.renderer.render("  ↳ #{sugg}", mode: :dim) if sugg),
          prompt_lines.first,
          prompt_lines.last,
        ].compact.join("\n")
      end

      def status_row_if_changed
        state = {
          turns: @refs.session.messages.size,
          violations: violations_count,
          model: @refs.agent.model,
          cost: @refs.session.cost.to_f.round(4),
        }
        return if @last_status_state == state

        @last_status_state = state
        @refs.renderer.status_row(uptime: @refs.renderer.uptime, turns: state[:turns], violations: state[:violations])
      end

      def suggested_next_prompt
        rows = proposer.call.first(3)
        return if rows.empty?

        @last_suggestion = rows.first[:action]
        rows.each_with_index.map { |row, i| "#{i + 1}. #{row[:action]} (#{row[:reason]})" }.join("  ")
      end

      def accept_top_suggestion
        return unless @last_suggestion
        puts @refs.renderer.render("↳ #{@last_suggestion}", mode: :dim)
        proposer.acted(@last_suggestion) if proposer.respond_to?(:acted)
        handle_repl_line(@last_suggestion)
      end

      def proposer
        @proposer ||= Propose.new(container: @container)
        @proposer.violations = violations_count
        @proposer
      end

      NL_DISPATCH = [
        [/\A(?:hi|hello|hey|yo|good (?:morning|afternoon|evening))[\s!.?]*\z/i, :run_chitchat],
        [/\b(?:show|print|list)\s+(?:undo\s+)?histor/i, :run_history],
        [/\b(?:why|how)\s+(?:this|that)\s+(?:fail(?:ed)?|break|broke|error|wrong|happen(?:ed)?)\b/i, :run_why],
        [/\bfocus\s+(?:mode|on|off)\b|\btoggle\s+focus\b/i, :toggle_focus],
        [/\b(?:last|prev(?:ious)?)\s+(?:input|message|prompt)\b/i, :run_last],
        [/\b(?:suggest|what(?:'s|\s+is)\s+next|next\s+steps?)\b/i, :run_propose],
        [/\b(?:show|list)\s+(?:my\s+)?principles\b/i, :run_principles],
        [/\brestart\b|\bhot[\s-]?reload\b/i, :run_restart],
        [/\brebuild\b/i, :run_rebuild],
        [/\bshow\s+context\b|\bcontext\s+window\b/i, :run_context],
        [/\bswallow[\s-]?report\b|\berror\s+ledger\b/i, :run_swallow_report],
        [/\btoggle\s+chips?\b|\bchips?\s+(?:on|off)\b/i, :toggle_chips],
        [/\btoggle\s+dmesg\b|\bdmesg\s+(?:on|off)\b/i, :toggle_dmesg],
      ].freeze

      def handle_repl_line(line)
        stripped = line.strip
        return accept_top_suggestion if stripped.empty?
        NL_DISPATCH.each { |pat, meth| return send(meth) if stripped.match?(pat) }
        case stripped
        when /\A\/(?:help|\?)(?:\s+(.+))?\z/ then run_help(Regexp.last_match(1))
        when "/exit", "/quit" then exit_cli
        when "/undo" then run_undo
        when "/rollback" then run_rollback
        when "/redo" then run_redo
        when "/checkpoint" then run_checkpoint
        when "/history" then run_history
        when /\A\/grep\s+(.+)\z/ then run_grep(Regexp.last_match(1))
        when "/audit" then run_audit
        when "/cost" then run_cost
        when /\A\/watch(?:\s+(on|off|status))?\z/ then run_watch(Regexp.last_match(1) || "status")
        when "/why" then run_why
        when "/focus" then toggle_focus
        when "/last" then run_last
        when "/cmd" then run_cmd
        when /\A\/dmesg\s+(\d+)\z/ then run_dmesg(Regexp.last_match(1).to_i)
        when "/dmesg" then toggle_dmesg
        when "/chips" then toggle_chips
        when /\A\/propose(?:\s+(.+))?\z/ then run_propose(Regexp.last_match(1))
        when "/principles" then run_principles
        when "/restart" then run_restart
        when "/self" then run_self_scan
        when /\A\/phase(?:\s+(.+))?\z/ then run_phase(Regexp.last_match(1).to_s)
        when "/ui-critique" then run_ui_critique
        when "/sound-critique" then run_sound_critique
        when "/rebuild" then run_rebuild
        when "/context" then run_context
        when "/snapshot" then run_snapshot
        when "/reap" then run_reap
        when "/verify" then run_verify
        when "/rails-pwa-audit" then run_rails_pwa_audit
        when "/rails-pwa-fix" then run_rails_pwa_fix
        when "/swallow-report" then run_swallow_report
        when "<<" then run_input(read_multiline)
        else run_agent_turn(line)
        end
      end

      def run_chitchat
        puts @refs.renderer.render("hello. MASTER is awake. describe a goal or use /cmd for operator commands.", mode: :dim)
      end

      def run_agent_turn(line)
        if (refusal = host_refusal_for(line))
          puts @refs.renderer.render(refusal, mode: :warning)
          return
        end

        run_input(line.strip)
      end

      def run_reap
        n = Master::Ground::HostBudget.reap_suspended_ruby!
        msg = n.positive? ? "reap: #{n} suspended ruby process(es) killed" : "reap: no suspended ruby processes"
        puts @refs.renderer.render(msg, mode: :dim)
      end

      def host_refusal_for(line)
        Master::Ground::HostBudget.refuse_heavy_prompt?(line)
      rescue StandardError
        nil
      end

    end
  end
end
