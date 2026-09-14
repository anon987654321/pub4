# frozen_string_literal: true

require_relative "repl_io"

module Master
  module CLI
    class Session
      CONTEXT_STEP = 10_000

      private

      def set_visitor_mode_if_unauthenticated
        # Visitor is a web-request flag, set per request on ai.brgen.no.
        # The local CLI is the operator surface: treating a missing web_token
        # as a visitor handed `bin/master "read CLAUDE.md"` AskLlm and
        # WebSearch, no ReadFile, and a 45-cent reply asking for the text.
      end

      # ^D reads nil and ^C at the prompt raises Interrupt; both leave here and
      # close the session. A second ^C while it closes exits at once, so a save
      # stuck on a full disk cannot hold the terminal.
      def repl_loop
        while @running
          line = safe_read_line(prompt_for_mode)
          if line.nil?
            puts
            break
          end
          handle_repl_line(line)
        end
      rescue Interrupt
        puts
      ensure
        trap("INT") { exit!(130) }
        close_session
      end

      def close_session
        stop_background_loop
        save_cli_history
        @refs.session.save!
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.close_session", event_bus: @refs.bus)
      end

      def prompt_for_mode
        refresh_skills!
        @focus_mode ? focus_prompt : normal_prompt
      end

      def focus_prompt
        @refs.renderer.render("#{@refs.renderer.prompt_token} ", mode: :dim)
      end

      # One zsh line, and above it a state line only when the state moved. The
      # state line prints here and the prompt goes to Reline, which redraws
      # the prompt it owns; a prompt printed around it is erased by its
      # cursor probe and leaves the probe glyph behind.
      def normal_prompt
        state, prompt = @refs.renderer.prompt_line(
          @refs.agent.model, @refs.session.phase,
          last_ok: @last_ok, violations: violations_count,
          tokens: @refs.session.token_est, cost: @refs.session.cost
        )
        puts state if state_changed?
        prompt
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

      NL_DISPATCH = [
        [/\A(?:hi|hello|hey|yo|good (?:morning|afternoon|evening))[\s!.?]*\z/i, :run_chitchat],
        [/\bfocus\s+(?:mode|on|off)\b|\btoggle\s+focus\b/i, :toggle_focus],
      ].freeze

      # An empty line does nothing, as in a shell: Enter never runs an action
      # the operator has not read.
      def handle_repl_line(line)
        stripped = line.strip
        return if stripped.empty?
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

      def host_refusal_for(line)
        Master::Ground::HostBudget.refuse_heavy_prompt?(line)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CLI.host_refusal_for")
        nil
      end

    end
  end
end
