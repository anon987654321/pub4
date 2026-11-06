# frozen_string_literal: true

require_relative "session/container"
require_relative "session/signals"
require_relative "session/command_ops"
require_relative "session/thinking_indicator"
require_relative "activity"
require_relative "session/result_display"
require_relative "session/background_scan"
require_relative "session/reminders"
require_relative "session/repl_flow"
require_relative "session/greeting"
require_relative "session/bridge_run"
require_relative "operator_grammar"

require "open3"
require "reline"
require "tty-prompt"
require "tty-screen"
require "fileutils"

module Master
  module CLI
    class Session
      CONFIG = Master.patterns_config.fetch("cli", {}).freeze
      IDLE_SLEEP_DEFAULT = CONFIG.fetch("idle_sleep_seconds", 60)
      DMESG_BUFFER_LINES = CONFIG.fetch("dmesg_buffer_lines", 80)
      MULTILINE_MAX_LINES = CONFIG.fetch("multiline_max_lines", 500)
      HISTORY_LIMIT = CONFIG.fetch("history_limit", 2_000)
      ERROR_TEXT_MAX_CHARS = 200
      ROUTINE_SUCCESS_MAX_LENGTH = 120

      SEVERITY_ICON = {
        error: "!!",
        warning: "!",
        style: ".",
        critical: "!!",
      }.freeze
      SLASH_COMMANDS = CommandRegistry.slash_commands.freeze

      attr_reader :container
      attr_reader :exit_code

      def initialize(container:)
        @container = container
        Fiber[:master_cli_container] = container
        @refs = Container.from_hash(container)
        Reline::HISTORY.clear
        load_cli_history
        setup_completion
        init_session_state!
        # The face is a visual layer above the one live Reline prompt.
        Fiber[:master_cli_prompt] = -> { @focus_mode ? focus_prompt : normal_prompt }
        set_visitor_mode_if_unauthenticated
      end

      def run(initial_message = nil)
        setup_signals
        @refs.agent.pin_boot_model! if @refs.agent.respond_to?(:pin_boot_model!)
        @refs.session.load! if @refs.session.exists?
        start_background_loop if background_scan_enabled?
        # One vertical rhythm: the dmesg, a blank line, the ready block, then
        # a blank line before each block that follows and before the prompt.
        print_splash
        # One line for a resumed session. Replaying its last turns printed an old
        # reply above the prompt, which read as a canned answer to a message not
        # yet typed.
        terminal_puts(@refs.renderer.session_line(@refs.session.name, @refs.session.messages.size)) if @refs.session.name
        print_repo_tree unless booted_before?
        terminal_puts
        face_request = initial_message.to_s.strip.match?(/\A\/face(?:\s|\z)/i)
        if face_request
          run_face
        else
          run_input(initial_message) if initial_message
        end
        greet_from_model unless initial_message
        @running = true
        play_boot_sound
        print_face_overlay unless @face_overlay_rendered
        start_boot_scan if background_scan_enabled?
        start_reminder_watch
        repl_loop
      end

      def pipe(input)
        stripped = input.strip
        return empty_input(:pipe) if stripped.empty?

        handle_repl_line(stripped)
      end

      def run_input(input, presentation: :terminal)
        return empty_input(:run_input) if input.strip.empty?
        @turn_queue_mutex.synchronize { @turn_cancel_requested = false unless @turn_queue_paused }
        return Master::Result.err("turn cancelled before start", category: :abort) if turn_cancel_requested?
        blocked = check_budget_blocks(input, presentation:)
        return blocked if blocked

        @refs.ground_truth&.begin_turn! if @refs.respond_to?(:ground_truth)
        @user_active = true
        @last_input = input
        Master::Trace::WriteTracker.current&.reset!
        paste, state, accumulated = init_turn_state(input)
        state[:presentation] = presentation
        state[:face_output] = +"" if presentation == :face

        print_thinking_indicator unless paste || presentation == :face
        result = presentation == :face ? dispatch_face_turn(input, accumulated:, state:) :
                                          dispatch_turn(input, accumulated:, state:)
        stop_thinking_indicator
        if presentation == :face
          unless result.err? && result.category == :abort
            @last_ok = result.ok?
            @exit_code = result.ok? ? 0 : exit_code_for(result)
          end
        else
          print_bridge_footer(result.value[:core], state:) if result.ok? && state[:streamed] && result.value[:core]
          display_result(result:, accumulated:, streamed: state[:streamed])
        end
        @last_repeatable_input = input if result.ok? && Master::Io::MediaIntent.repeatable?(input)
        return face_reply_text(result, state[:face_output]) if presentation == :face && result.ok? && state[:streamed]

        result
      ensure
        @pipeline_thread = nil
        @turn_cancellation = nil
        @turn_children = nil if presentation == :face
        stop_thinking_indicator
        close_unit_console
        @user_active = false
      end

      # The face is a compact visual projection above the canonical prompt.
      # Reline remains the only keyboard/input owner; no alternate screen,
      # raw-key reader or second prompt is started for ordinary CLI use.
      FACE_INTRO_FRAMES = 6
      # Keep the marker inside portrait Termux widths; the intro's cursor
      # restore depends on it occupying one terminal row.
      FACE_OVERLAY_MARKER = "face0: Reline owns input"
      FACE_OVERLAY_PRESENT = "face0: already visible"

      def face_overlay_text(cols: 32, swarm_budget: nil)
        rows, fitted_cols = Master::CLI::Face::Sizing.fit(12, cols + 4, mode: "#{cols}x12")
        @face_started_at ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @face_motion ||= Master::CLI::Face::Motion.new(seed: Random.new_seed % 1_000_003)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        Master::CLI::Face.frame(
          state: face_state,
          rows:,
          cols: fitted_cols,
          t: now - @face_started_at,
          motion: @face_motion,
          color: false,
          show_laws: nil,
          swarm_budget: swarm_budget || Master::Face::Contract.budget.fetch("terminal_intro_particles", 24),
        )
      end

      def face_state
        return :error if @last_ok == false
        return :thinking if @user_active || @pipeline_thread&.alive?

        :ready
      end

      def print_face_overlay
        return false unless $stdin.tty? && $stdout.tty?

        if @face_overlay_rendered
          terminal_puts(FACE_OVERLAY_PRESENT)
          return true
        end

        terminal_cols = Master::CLI::Face::Sizing.winsize.last.to_i
        face_cols = [terminal_cols - 4, 32].min
        return false if face_cols < 16

        frame = face_overlay_text(cols: face_cols)
        terminal_puts(frame.lines.map { |line| line.chomp.center(terminal_cols) }.join("\n"))
        terminal_puts(FACE_OVERLAY_MARKER)
        @face_overlay_rendered = true
        animate_face_intro(cols: face_cols, terminal_cols:, face_rows: frame.lines.count)
        true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.face.overlay", event_bus: @refs.bus)
        false
      end

      # The short ready-state reveal advances the existing facial springs before
      # Reline starts reading. It never opens a second input loop or screen.
      def animate_face_intro(cols:, terminal_cols:, face_rows:)
        return if ENV["MASTER_REDUCED_MOTION"] == "1"
        return if terminal_cols < FACE_OVERLAY_MARKER.length
        return if TTY::Screen.height.to_i < face_rows + 7

        block_rows = face_rows + 1
        FACE_INTRO_FRAMES.times do
          frame = face_overlay_text(cols:, swarm_budget: Master::Face::Contract.budget.fetch("terminal_intro_particles", 24))
          rendered = frame.lines.map { |line| line.chomp.center(terminal_cols) }.join("\n")
          Master::Trace::Dmesg.terminal_write do |target|
            target.write("\e7\e[?25l\e[#{block_rows}A\r#{rendered}\n#{FACE_OVERLAY_MARKER}\e[?25h\e8")
            target.flush
          end
          sleep(1.0 / Float(Master::Face::Contract.budget.fetch("terminal_intro_fps", 8)).clamp(1.0, 12.0))
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.face.animation", event_bus: @refs.bus)
      end

      # The face renderer can still be used by explicit visual clients, but
      # normal terminal turns never hand keyboard ownership to it.
      def run_face_turn(input)
        text = input.to_s
        return empty_input(:face) if text.strip.empty?

        Reline::HISTORY << text
        return :face_toggle if text.strip.casecmp("/face").zero?

        handle_repl_line(text)
      end

      def face_reply_text(result, streamed)
        final = success_text(result).to_s.strip
        stream = streamed.to_s.strip
        return stream if final.empty? || stream.include?(final[0, 120])
        return final if stream.empty?

        "#{stream}\n#{final}"
      end

      # A cooperative Fold cancellation must finish its bounded transaction
      # and receipt; killing this worker here would break the shared Session
      # cancellation contract. Non-Fold work retains the immediate stop path.
      def cancel_face_turn(worker, children)
        token = @turn_cancellation
        cooperative = token&.active?
        token&.cancel!(reason: "face interrupted")
        @refs.bus&.publish("user:interrupt", reason: "face", source: "cli", children:)
        unless cooperative
          worker.kill if worker&.alive?
          children&.kill_all
        end
        !!cooperative
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.face.cancel", event_bus: @refs.bus)
        false
      end

      private

      # All operator-facing writes share Dmesg's mutex. If an async turn writes
      # while Reline is editing the next prompt, the message lands on a row of
      # its own and the editable line is rebuilt beneath it — zsh's own rule.
      # A write that used to append at the cursor printed its text after the
      # prompt glyphs, so "master$ Welcome back." read as a reply typed into
      # the shell.
      def terminal_write(io: $stdout, &block)
        Master::Trace::Dmesg.terminal_write(io:) do |target|
          clear_reserved_activity_row(target) if io.equal?($stdout)
          clear_prompt_row(target) if io.equal?($stdout)
          block.call(target)
          redraw_active_input if io.equal?($stdout) && @reading_input
        end
      end

      # One clear, not a repaint: Reline owns the draft's pixels and rebuilds
      # them through redisplay. Only a terminal row may be cleared; pipes and
      # logs pass untouched.
      def clear_prompt_row(target)
        return unless @reading_input && target.respond_to?(:tty?) && target.tty?

        target.print("\r\e[K")
        target.flush if target.respond_to?(:flush)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.prompt_row.clear", event_bus: @refs.bus)
      end

      def redraw_active_input
        Reline.redisplay if Reline.respond_to?(:redisplay)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.reline.redisplay", event_bus: @refs.bus)
      end

      # The splash is the last of the boot, so it keeps the boot's console colours.
      def print_splash
        terminal_puts(Master::Trace::Dmesg.console_paint(@refs.renderer.splash(@refs.agent.model), $stdout))
      end

      def terminal_puts(text = "", io: $stdout)
        terminal_write(io:) { |target| target.puts(text); target.flush if target.respond_to?(:flush) }
      end

      def terminal_print(text, io: $stdout)
        terminal_write(io:) { |target| target.print(text); target.flush if target.respond_to?(:flush) }
      end

      def play_boot_sound
        Master::Voice::BootSound.play
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.boot_sound", event_bus: @refs.bus)
      end

      def init_session_state!
        @running = false
        @last_ok = true
        @violations = 0
        @prev_violations = 0
        @violations_mutex = Mutex.new
        @bg_thread = nil
        @bg_control = Queue.new
        @seen_violations = {}
        @user_active = false
        @focus_mode = false
        @last_input = nil
        @exit_code = 0
        @activity = Master::CLI::Activity.new
        @last_repeatable_input = nil
        @turn_queue = []
        @turn_queue_mutex = Mutex.new
        @turn_worker = nil
        @turn_current_line = nil
        @turn_current_started = false
        @turn_queue_paused = false
        @turn_cancel_requested = false
        @turn_cancellation = nil
        @reading_input = false
        @activity_row_reserved = false
        @active_prompt = nil
        @terminal_ask_mutex = Mutex.new
        @terminal_ask_cv = ConditionVariable.new
        @pending_terminal_ask = nil
        @closed = false
      end

      def init_turn_state(input)
        paste = paste_like_input?(input)
        state = { streamed: false, thinking_shown: !paste }
        accumulated = +""
        build_stream_handler(accumulated) { |text| handle_stream_text(text, state) }
        [paste, state, accumulated]
      end

      def check_budget_blocks(input, presentation: :terminal)
        if (host_err = host_budget_block(input))
          return presentation == :face ? host_err : display_result(result: host_err, accumulated: "", streamed: false)
        end
        budget_err = budget_block_if_exceeded
        if budget_err
          return budget_err if presentation == :face

          return display_result(result: budget_err, accumulated: "", streamed: false)
        end

        nil
      end

      def dispatch_face_turn(input, accumulated:, state:)
        return Master::Result.err("turn cancelled before dispatch", category: :abort) if turn_cancel_requested?

        on_turn = build_on_turn_handler(accumulated, state)
        @turn_cancellation = Master::Core::CancellationToken.new
        @turn_children = Fiber[:master_children] || Master::Io::Exec::Children.new
        TurnRouter.call(
          message: input,
          container: @container,
          felt_sense: cli_felt_sense,
          on_turn:,
          on_chunk: build_on_chunk_handler(accumulated, state),
          cancellation: @turn_cancellation,
        )
      end

      def dispatch_turn(input, accumulated:, state:)
        return Master::Result.err("turn cancelled before dispatch", category: :abort) if turn_cancel_requested?

        on_turn = build_on_turn_handler(accumulated, state)
        @turn_cancellation = Master::Core::CancellationToken.new
        @pipeline_thread = spawn_pipeline_thread(
          input, on_turn:, on_chunk: build_on_chunk_handler(accumulated, state),
          cancellation: @turn_cancellation
        )
        request_or_interrupt_turn(@pipeline_thread, @turn_children, reason: "stop") if turn_cancel_requested? && @pipeline_thread&.alive?
        fetch_pipeline_result
      end

      def turn_cancel_requested?
        @turn_queue_mutex&.synchronize { @turn_cancel_requested == true } || false
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.queue.cancel_state", event_bus: @refs.bus)
        true
      end

      def build_on_turn_handler(accumulated, state)
        lambda do |line|
          # The units console printed this turn as it ran; the transcript line
          # would say it twice.
          next state[:streamed] = true if @unit_sub

          accumulated << line << "\n"
          handle_stream_text(line + "\n", state) if $stdout.isatty
        end
      end

      # The reply as the model writes it: the first words reach the terminal seconds before the last.
      def build_on_chunk_handler(accumulated, state)
        lambda do |chunk|
          accumulated << chunk
          handle_stream_text(chunk, state) if $stdout.isatty
        end
      end

      def spawn_pipeline_thread(input, on_turn:, on_chunk:, cancellation: nil)
        @turn_children = Master::Io::Exec::Children.new

        Thread.new do
          Thread.current.report_on_exception = false
          Fiber[:master_children] = @turn_children
          Fiber[:master_terminal_ask] = terminal_ask(Thread.current)
          TurnRouter.call(
            message: input,
            container: @container,
            felt_sense: cli_felt_sense,
            on_turn:,
            on_chunk:,
            cancellation:,
          )
        end
      end

      # Thread#value answers nil for a thread that was killed, rather than
      # raising, and signals.rb kills this one on ^C. Interrupt is not a
      # StandardError and a killed thread raises nothing, so the nil is the
      # only sign of a cancel. A turn that raised is a failure, named as one.
      def fetch_pipeline_result
        value = @pipeline_thread.value
        if value.nil?
          return Result.err("interrupted", category: :abort) if turn_cancel_requested?

          return Result.err("turn returned no result", category: :handler_exception)
        end
        return value if value.is_a?(Result)

        Result.err("turn returned invalid result: #{value.class}", category: :handler_exception)
      rescue NoMemoryError
        Result.err(host_oom_message, category: :infrastructure)
      # ScriptError too: a SyntaxError re-raised from Thread#value inherits
      # ScriptError, not StandardError — StandardError-only let one unparseable
      # file in the preflight abort the whole process instead of failing a turn.
      rescue StandardError, ScriptError => e
        Result.err("turn failed: #{e.class}: #{e.message}", category: :infrastructure)
      end

      def empty_input(source)
        @refs.bus&.publish("cli:empty_input", source:)
        nil
      end

      def paste_like_input?(input)
        text = input.to_s
        text.lines.size > 3 || text.bytesize > 1_500
      end

      def handle_stream_text(text, state)
        if state[:presentation] == :face
          state[:face_output] << text.to_s
          state[:streamed] = true
          return
        end
        if state[:thinking_shown] && $stdout.isatty
          stop_thinking_indicator
          terminal_print("\r\e[K")
          state[:thinking_shown] = false
        end
        terminal_print(wrap_stream(text, state))
        state[:streamed] = true
      end

      # Preserve provider-authored text exactly. Newline insertion here becomes
      # permanent text in logs and copy/paste; the terminal handles visual wrapping.
      def wrap_stream(text, _state)
        text.to_s
      end

      def cli_felt_sense
        mood = @last_ok ? "focused" : "tense"
        mood = "curious" if @refs.session.phase == :discover
        entropy = [violations_count / 20.0, 1.0].min
        confidence = @last_ok ? 0.86 : 0.42
        { mood:, entropy: entropy.round(2), confidence: }
      end

      def host_budget_block(input)
        msg = Master::Ground::HostBudget.refuse_heavy_prompt?(input)
        return unless msg

        Master::Result.err(msg, category: :validation)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CLI.host_budget_block")
        Master::Result.err("host budget unavailable: #{e.class}: #{e.message}", category: :infrastructure)
      end

      def host_oom_message
        tip = Master::Ground::HostBudget.heavy_repo_message
        "failed to allocate memory - #{tip}"
      rescue StandardError
        "failed to allocate memory - use /fix lib or bin/master --fast"
      end

      def budget_block_if_exceeded
        max = @refs.session.budget_max.to_f
        return if max <= 0
        return if @refs.session.cost.to_f < max

        Master::Result.err(
          "budget exceeded: ¢#{( @refs.session.cost * 100).round(2)} / ¢#{(max * 100).round(2)} - use /cost or raise budget",
          category: :budget,
        )
      end

    end
  end
end
