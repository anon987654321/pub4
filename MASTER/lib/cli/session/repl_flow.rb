# frozen_string_literal: true

require_relative "repl_io"

module Master
  module CLI
    class Session
      CONTEXT_STEP = 10_000
      CLOSE_WINDOW_S = 3
      INTERACTIVE_QUEUE_LIMIT = 32
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
        terminal_puts
      ensure
        trap("INT") { exit!(130) }
        close_session
      end

      def read_prompt_line
        @reading_input = true
        @active_prompt = prompt_for_mode
        reserve_activity_row
        line = safe_read_line(@active_prompt)
        terminal_puts if line.nil?
        line
      rescue Interrupt
        terminal_puts
        return if close_requested?

        Master::Trace::Dmesg.status("cli0", "^C again to exit")
        :interrupted
      ensure
        Master::Trace::Dmesg.terminal_write do |_target|
          @reading_input = false
          @activity_row_reserved = false
          @active_prompt = nil
        end
      end

      # Reserve one line above Reline's editable row only while a queued turn is
      # active. The spinner may paint that row, never the line being edited.
      def reserve_activity_row
        return unless $stdin.tty? && $stdout.tty?

        busy = @turn_queue_mutex.synchronize do
          @turn_worker&.alive? && !@turn_queue_paused && !@closed
        end
        return unless busy

        Master::Trace::Dmesg.terminal_write do |target|
          target.puts
          target.flush
          @activity_row_reserved = true
        end
      rescue StandardError => e
        @activity_row_reserved = false
        Master::Ground::Swallow.log(e, context: "cli.activity_row.reserve", event_bus: @refs.bus)
      end

      def close_requested?
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        recent = @interrupted_at && now - @interrupted_at <= CLOSE_WINDOW_S
        @interrupted_at = now
        recent
      end

      def close_session
        return if @closed

        @closed = true
        Master::Voice::Bed.stop
        shutdown_interactive_queue! if $stdin.tty? && $stdout.tty?
        stop_background_loop
        stop_reminder_watch
        save_cli_history
        save_session_on_exit
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.close_session", event_bus: @refs.bus)
      end

      def prompt_for_mode
        refresh_skills!
        @focus_mode ? focus_prompt : normal_prompt
      end

      # The ordinary shell keeps Reline in charge of the prompt. /face opens the
      # dedicated alternate-screen stage when the operator wants the full face.
      def normal_prompt
        state, prompt = @refs.renderer.prompt_line(
          @refs.agent.model, @refs.session.phase,
          last_ok: @last_ok, violations: violations_count,
          tokens: @refs.session.token_est, cost: @refs.session.cost,
          destination: Master::Io::Chat.destination_label
        )
        announce_state(state)
        prompt
      end

      # Focus mode reduces context noise, never hides the working location or
      # the destination that receives the next line of text.
      def focus_prompt
        state, prompt = @refs.renderer.prompt_line(
          @refs.agent.model, @refs.session.phase,
          last_ok: @last_ok, violations: violations_count,
          tokens: @refs.session.token_est, cost: @refs.session.cost,
          destination: Master::Io::Chat.destination_label, focused: true
        )
        announce_state(state)
        prompt
      end

      # The state line prints only when it moves, so the prompt stays one shape.
      def announce_state(state)
        return if state.nil? || state == @announced_state

        @announced_state = state
        terminal_puts(state)
      end

      # An empty line does nothing, as in a shell: Enter never runs an action
      # the operator has not read.
      def handle_repl_line(line)
        stripped = line.strip
        return if stripped.empty?

        if stripped.casecmp("/stop").zero?
          return stop_interactive_queue if queue_control_mode? || @turn_worker&.alive?
          terminal_puts("queue0: no active turn")
          return
        end
        if stripped.casecmp("/resume").zero?
          return resume_interactive_queue if @turn_queue_paused
          terminal_puts("queue0: queue is not paused")
          return
        end
        return exit_cli if queue_control_mode? && %w[/exit /quit].include?(stripped.downcase)
        if Thread.current != @turn_worker && terminal_ask_pending?
          return if answer_pending_terminal_ask(stripped)
          accepted = enqueue_interactive_line(line)
          terminal_puts("ask0: approval pending; enter /approve or /deny, your message is queued") if accepted
          return
        end
        if @turn_worker&.alive? && Thread.current != @turn_worker
          enqueue_interactive_line(line)
          return
        end

        case Master::CLI::OperatorGrammar.parse(stripped)&.kind
        when :repeat then return repeat_last
        when :toggle_focus then return toggle_focus
        when :direct_shell then return run_direct_shell(stripped)
        end

        handled = dispatch_core_slash_command(stripped)
        return handled unless handled == :unhandled

        bang = stripped.match(BANG)
        return run_bang(bang[:command]) if bang
        return run_input(read_multiline) if stripped == "<<"

        run_agent_turn(line)
      end

      def dispatch_core_slash_command(stripped)
        case stripped
        when %r{\A/(?:help|\?)(?:\s+(.+))?\z} then run_help(Regexp.last_match(1))
        when "/exit", "/quit" then exit_cli
        when "/undo" then run_undo
        when "/clear" then run_input("/clear")
        when "/face" then run_face
        else dispatch_registered_slash_command(stripped)
        end
      end

      # Slash commands are already a closed, tested registry. Sending a known
      # slash command through the LLM makes deterministic commands probabilistic:
      # /play can become a model turn, return nil after cancellation, or revive
      # stale natural-language media behavior. Direct registered dispatch keeps
      # the CLI faithful to its command surface.
      def dispatch_registered_slash_command(stripped)
        match = stripped.match(%r{\A/(?<name>[a-z][a-z0-9_-]*)(?:\s+(?<args>.*))?\z}i)
        return :unhandled unless match

        name = match[:name].downcase
        command = @container.fetch(:commands, {})[name]
        return :unhandled unless command

        result = command.call(args: match[:args].to_s)
        text = if result.is_a?(Master::Result)
                 @last_ok = result.ok?
                 result.ok? ? result.value!.to_s : result.message.to_s
               else
                 @last_ok = true
                 result.to_s
               end
        print_terminal_output(text, mode: @last_ok ? :dim : :error) unless text.empty?
        result
      rescue StandardError => e
        @last_ok = false
        text = "cmd0: /#{name} failed — #{e.class}: #{e.message}"
        print_terminal_output(text, mode: :error)
        nil
      end

      def run_face
        was_running = @running
        stop_background_loop
        result = CommandRegistry.dispatch_face
        terminal_puts(result) if result && result != "face0: closed"
        nil
      ensure
        start_background_loop if was_running && @running
      end

      # !command runs one zsh line through the Io::Shell the model's zsh tool
      # uses — its blocklist, sandbox, interactive refusal and governor — and
      # costs no model call. The output joins the transcript so the next prompt
      # can refer to it. Fast mode builds no governor, so it refuses.
      def run_bang(command)
        shell = bang_shell
        return Master::Trace::Dmesg.status("shell0", "governor unavailable") unless shell

        result = shell.call(command:)
        text = result.ok? ? result.value!.to_s : result.message.to_s
        terminal_puts(@refs.renderer.render(text, mode: result.ok? ? :dim : :error))
        @refs.session.add_message(
          role: :user,
          content: "$ #{command}\n#{text}",
          layer: :execution,
        )
      end

      def bang_shell
        governor = @container[:governor]
        return unless governor

        @bang_shell ||= Master::Io::Shell.new(root: @refs.root, governor:, event_bus: @refs.bus)
      end

      def run_direct_shell(command)
        shell = bang_shell
        return Master::Trace::Dmesg.status("shell0", "unavailable") unless shell

        result = shell.call(command:)
        text = result.ok? ? result.value!.to_s : result.message.to_s
        @last_ok = result.ok?
        @exit_code = result.ok? ? 0 : 2
        puts @refs.renderer.render(text, mode: result.ok? ? :dim : :error)
      end

      def repeat_last
        input = @last_repeatable_input.to_s
        return Master::Trace::Dmesg.status("cli0", "nothing to repeat") if input.empty?

        run_input(input)
      end

      def run_agent_turn(line)
        if (refusal = host_refusal_for(line))
          Master::Trace::Dmesg.status("host0", refusal)
          return
        end

        if $stdin.tty? && $stdout.tty? && Thread.current != @turn_worker
          enqueue_interactive_line(line)
        else
          run_input(line.strip)
        end
      end

      def queue_control_mode?
        @turn_queue_paused || (@turn_worker&.alive? && Thread.current != @turn_worker)
      end

      def shutdown_interactive_queue!
        @turn_queue_mutex&.synchronize do
          @turn_queue&.clear
          @turn_queue_paused = true
          @turn_cancel_requested = true
        end
        turn = @pipeline_thread
        if turn&.alive? && Thread.current != @turn_worker
          canceler = Thread.new { request_or_interrupt_turn(turn, @turn_children, reason: "stop") }
          canceler.join(1)
          turn.join(1)
        end
        worker = @turn_worker
        worker.join(1) if worker&.alive? && Thread.current != worker
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.queue.shutdown", event_bus: @refs.bus)
      end

      def interactive_queue_count
        @turn_queue_mutex.synchronize { @turn_queue.length }
      rescue StandardError
        0
      end

      def enqueue_interactive_line(line)
        count = nil
        busy = false
        paused = false
        full = false
        @turn_queue_mutex.synchronize do
          if @turn_queue.length >= INTERACTIVE_QUEUE_LIMIT
            full = true
          else
            busy = !!@turn_worker&.alive?
            @turn_queue << line.to_s
            paused = @turn_queue_paused
            start_interactive_queue_worker_locked unless busy || paused || @closed
            count = @turn_queue.length
          end
        end
        if full
          terminal_puts("queue0: full, #{INTERACTIVE_QUEUE_LIMIT} pending; message not queued")
          false
        else
          terminal_puts("queue0: #{count} queued, paused") if paused && count&.positive?
          terminal_puts("queue0: #{count} queued") if busy && count&.positive?
          true
        end
      end

      # Called with @turn_queue_mutex held. A startup latch replaces a busy
      # Thread.pass loop and makes worker ownership deterministic.
      def start_interactive_queue_worker_locked
        return if @closed || @turn_queue_paused || @turn_worker&.alive?

        ready = Queue.new
        worker = Thread.new do
          ready.pop
          drain_interactive_queue
        end
        worker.report_on_exception = false
        @turn_worker = worker
        ready << true
      end

      def drain_interactive_queue
        worker = Thread.current
        Thread.current.report_on_exception = false
        Fiber[:master_cli_container] = @container

        loop do
          line = take_next_interactive_line(worker)
          break if line.nil?
          next unless begin_interactive_line(line)

          begin
            handle_repl_line(line)
          ensure
            finish_interactive_line(line)
          end
        end
      rescue StandardError => e
        terminal_puts("queue0: worker failed — #{e.class}: #{e.message}", io: $stderr)
      ensure
        restart = false
        @turn_queue_mutex.synchronize do
          if @turn_worker.equal?(worker)
            @turn_worker = nil
            @turn_current_line = nil
            @turn_current_started = false
            restart = !@closed && !@turn_queue_paused && !@turn_queue.empty?
          end
        end
        if restart
          @turn_queue_mutex.synchronize { start_interactive_queue_worker_locked }
        end
      end

      def take_next_interactive_line(worker)
        @turn_queue_mutex.synchronize do
          if @closed || @turn_queue_paused || @turn_queue.empty?
            @turn_worker = nil if @turn_worker.equal?(worker)
            nil
          else
            @turn_current_line = @turn_queue.shift
            @turn_current_started = false
            @turn_current_line
          end
        end
      end

      # Stop can land between dequeue and execution. A line that has not crossed
      # this boundary is returned to the head of the FIFO instead of being lost.
      def begin_interactive_line(line)
        @turn_queue_mutex.synchronize do
          if @closed || @turn_queue_paused
            @turn_queue.unshift(line) if @turn_current_line.equal?(line) && !@turn_current_started && !@closed
            @turn_current_line = nil if @turn_current_line.equal?(line)
            @turn_current_started = false
            false
          else
            @turn_current_started = true if @turn_current_line.equal?(line)
            true
          end
        end
      end

      def finish_interactive_line(line)
        @turn_queue_mutex.synchronize do
          if @turn_current_line.equal?(line)
            @turn_current_line = nil
            @turn_current_started = false
          end
        end
      end

      def stop_interactive_queue
        @turn_queue_mutex.synchronize do
          @turn_queue_paused = true
          @turn_cancel_requested = true
        end
        turn = @pipeline_thread
        if turn&.alive?
          canceler = Thread.new { cancel_turn(turn, @turn_children) }
          canceler.join(2)
          turn.join(1) unless Thread.current == turn
        end
        count = interactive_queue_count
        status = turn&.alive? ? "cancellation requested" : (turn ? "current turn cancelled" : "queue paused; pending turn will not start")
        terminal_puts("queue0: #{status}; #{count} queued, /resume to continue")
        nil
      end

      def resume_interactive_queue
        @turn_queue_mutex.synchronize do
          @turn_queue_paused = false
          @turn_cancel_requested = false
          start_interactive_queue_worker_locked if !@turn_worker&.alive? && @turn_queue.any?
        end
        count = interactive_queue_count
        terminal_puts(count.positive? ? "queue0: resuming, #{count} queued" : "queue0: no queued messages")
        nil
      end

      def host_refusal_for(line)
        Master::Ground::HostBudget.refuse_heavy_prompt?(line)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CLI.host_refusal_for")
        "host budget unavailable, #{e.class}: #{e.message}"
      end

    end
  end
end
