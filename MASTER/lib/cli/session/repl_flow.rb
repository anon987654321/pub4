# frozen_string_literal: true

require_relative "repl_io"

module Master
  module CLI
    class Session
      CONTEXT_STEP = 10_000
      CLOSE_WINDOW_S = 3
      BANG = /\A!(?<command>\S.*)\z/m

      private

      def set_visitor_mode_if_unauthenticated
        # Visitor is a web-request flag, set per request on ai.brgen.no.
        # The local CLI is the operator surface: treating a missing web_token
        # as a visitor handed `bin/master "read CLAUDE.md"` AskLlm and
        # WebSearch, no ReadFile, and a 45-cent reply asking for the text.
      end

      # ^D reads nil and closes the session. ^C at the prompt clears the line, as
      # zsh does, and a second ^C inside CLOSE_WINDOW_S closes it: on a phone
      # keyboard one stray press cost the session. A second ^C while it closes
      # exits at once, so a save stuck on a full disk cannot hold the terminal.
      def repl_loop
        while @running
          line = read_prompt_line
          break if line.nil?

          handle_repl_line(line) unless line == :interrupted
        end
      rescue Interrupt
        puts
      ensure
        trap("INT") { exit!(130) }
        close_session
      end

      def read_prompt_line
        line = safe_read_line(prompt_for_mode)
        puts if line.nil?
        line
      rescue Interrupt
        puts
        return if close_requested?

        puts @refs.renderer.render("^C again within #{CLOSE_WINDOW_S}s to close", mode: :dim)
        :interrupted
      end

      def close_requested?
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        recent = @interrupted_at && now - @interrupted_at <= CLOSE_WINDOW_S
        @interrupted_at = now
        recent
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

        bang = stripped.match(BANG)
        return run_bang(bang[:command]) if bang
        return run_input(read_multiline) if stripped == "<<"

        run_agent_turn(line)
      end

      def open_face
        puts Master::CLI::CommandRegistry.dispatch_face
      end

      def dispatch_core_slash_command(stripped)
        case stripped
        when %r{\A/(?:help|\?)(?:\s+(.+))?\z} then run_help(Regexp.last_match(1))
        when "/exit", "/quit" then exit_cli
        when "/face" then open_face
        when "/undo" then run_undo
        when "/clear" then run_input("/clear")
        else :unhandled
        end
      end

      def run_chitchat
        puts @refs.renderer.render("hello. MASTER is awake. describe a goal.", mode: :dim)
      end

      # !command runs one zsh line through the Io::Shell the model's zsh tool
      # uses — its blocklist, sandbox, interactive refusal and governor — and
      # costs no model call. The output joins the transcript so the next prompt
      # can refer to it. Fast mode builds no governor, so it refuses.
      def run_bang(command)
        shell = bang_shell
        return puts(@refs.renderer.render("!: no governor in this mode", mode: :warning)) unless shell

        result = shell.call(command:)
        text = result.ok? ? result.value!.to_s : result.message.to_s
        puts @refs.renderer.render(text, mode: result.ok? ? :dim : :error)
        @refs.session.add_message(role: :user, content: "$ #{command}\n#{text}")
      end

      def bang_shell
        governor = @container[:governor]
        return unless governor

        @bang_shell ||= Master::Io::Shell.new(root: @refs.root, governor:, event_bus: @refs.bus)
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
        "host budget unavailable: #{e.class}: #{e.message}"
      end

    end
  end
end
