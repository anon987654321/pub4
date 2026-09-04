# frozen_string_literal: true

require_relative "command_handlers"

module Master
  module CLI
    class Session
      CONTEXT_STEP = 10_000

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

      # One zsh line, and above it a state line only when the state moved.
      def normal_prompt
        state, prompt = @refs.renderer.prompt_line(
          @refs.agent.model, @refs.session.phase,
          last_ok: @last_ok, violations: violations_count,
          tokens: @refs.session.token_est, cost: @refs.session.cost
        )
        [(state if state_changed?), prompt].compact.join("\n")
      end

      # Context grows every turn, so it counts as movement only by the step —
      # otherwise the state line would print on every prompt and be a status bar
      # again.
      def state_changed?
        state = {
          violations: violations_count,
          model: @refs.agent.model,
          phase: @refs.session.phase,
          context: @refs.session.token_est.to_i / CONTEXT_STEP,
          cost: @refs.session.cost.to_f.round(2),
        }
        return false if @last_status_state == state

        @last_status_state = state
        true
      end

      def accept_top_suggestion
        @last_suggestion ||= proposer.call.first&.fetch(:action, nil)
        return unless @last_suggestion
        puts @refs.renderer.render("next: #{@last_suggestion}", mode: :dim)
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
        [/\bfocus\s+(?:mode|on|off)\b|\btoggle\s+focus\b/i, :toggle_focus],
      ].freeze

      def handle_repl_line(line)
        stripped = line.strip
        return accept_top_suggestion if stripped.empty?
        NL_DISPATCH.each { |pat, meth| return send(meth) if stripped.match?(pat) }

        handled = dispatch_core_slash_command(stripped)
        return handled unless handled == :unhandled

        return run_input(read_multiline) if stripped == "<<"

        run_agent_turn(line)
      end

      def dispatch_core_slash_command(stripped)
        case stripped
        when %r{\A/(?:help|\?)(?:\s+(.+))?\z} then run_help(Regexp.last_match(1))
        when "/exit", "/quit" then exit_cli
        when "/undo", "/rollback" then run_undo
        when "/clear" then run_input("/clear")
        else :unhandled
        end
      end

      def run_chitchat
        puts @refs.renderer.render("hello. MASTER is awake. describe a goal.", mode: :dim)
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
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CLI.host_refusal_for")
        nil
      end

    end
  end
end
