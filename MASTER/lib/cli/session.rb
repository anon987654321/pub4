# frozen_string_literal: true

require_relative "session/container"
require_relative "session/signals"
require_relative "session/command_ops"
require_relative "session/thinking_indicator"
require_relative "activity"
require_relative "session/result_display"
require_relative "session/background_scan"
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
        # The optional face paints the live Reline prompt, never a second shell-style prompt.
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
        terminal_puts(@refs.renderer.splash(@refs.agent.model))
        start_boot_scan if background_scan_enabled?
        # One line for a resumed session. Replaying its last turns printed an old
        # reply above the prompt, which read as a canned answer to a message not
        # yet typed.
        terminal_puts(@refs.renderer.session_line(@refs.session.name, @refs.session.messages.size)) if @refs.session.name
        print_repo_tree unless booted_before?
        terminal_puts
        run_input(initial_message) if initial_message
        greet_from_model unless initial_message
        @running = true
        play_boot_sound
        start_bed
        if face_on_start?(initial_message)
          @face_open = true
          run_face
          @face_open = false
        end
        repl_loop
      end

      # Interactive sessions open on the original prompt. The face opens at start only when
      # face_on_start is enabled by the data or MASTER_FACE_ON_START=1; /face opens it any time.
      # Command-line messages and non-TTY pipes stay plain so automation never receives terminal animation.
      def face_on_start?(initial_message)
        return false if initial_message || ENV["MASTER_FACE_ON_START"] == "0"
        return false unless $stdin.tty? && $stdout.tty?

        ENV["MASTER_FACE_ON_START"] == "1" || Master.patterns_config.fetch("cli", {})["face_on_start"] == true
      end

      def pipe(input)
        stripped = input.strip
        return empty_input(:pipe) if stripped.empty?

        handle_repl_line(stripped)
      end

      def run_input(input)
        return empty_input(:run_input) if input.strip.empty?
        @turn_queue_mutex.synchronize { @turn_cancel_requested = false unless @turn_queue_paused }
        return Master::Result.err("turn cancelled before start", category: :abort) if turn_cancel_requested?
        blocked = check_budget_blocks(input)
        return blocked if blocked

        @user_active = true
        @last_input = input
        Master::Trace::WriteTracker.current&.reset!
        paste, state, accumulated = init_turn_state(input)

        print_thinking_indicator unless paste
        result = dispatch_turn(input, accumulated:, state:)
        stop_thinking_indicator
        print_bridge_footer(result.value[:core], state:) if result.ok? && state[:streamed] && result.value[:core]
        display_result(result:, accumulated:, streamed: state[:streamed])
        @last_repeatable_input = input if result.ok? && Master::Io::MediaIntent.repeatable?(input)
      ensure
        @pipeline_thread = nil
        @turn_cancellation = nil
        stop_thinking_indicator
        close_unit_console
        @user_active = false
      end

      private

      # All operator-facing writes share Dmesg's mutex. If an async turn writes
      # while Reline is editing the next prompt, repaint the editable line after
      # the output rather than leaving tokens inside the draft.
      def terminal_write(io: $stdout, &block)
        Master::Trace::Dmesg.terminal_write(io:) do |target|
          clear_reserved_activity_row(target) if io.equal?($stdout)
          block.call(target)
          redraw_active_input if io.equal?($stdout) && @reading_input
        end
      end

      def redraw_active_input
        Reline.redisplay if Reline.respond_to?(:redisplay)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.reline.redisplay", event_bus: @refs.bus)
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

      # The Dilla chord bed starts with the session whether or not the bard speaks; closing the session stops
      # it, and MASTER_BED=0 keeps it silent.
      def start_bed
        return unless $stdout.tty?

        Master::Voice::Bed.boot(Master::Voice::Narrator.load_config(:bard)["bed"])
        Master::Trace::Dmesg.status("bed0", "Dilla chord bed on") if Master::Voice::Bed.held?
      rescue StandardError => e
        Master::Trace::Dmesg.status("bed0", "ambient failed, #{e.class}: #{e.message}")
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

      def check_budget_blocks(input)
        if (host_err = host_budget_block(input))
          return display_result(result: host_err, accumulated: "", streamed: false)
        end
        budget_err = budget_block_if_exceeded
        return display_result(result: budget_err, accumulated: "", streamed: false) if budget_err

        nil
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
        "failed to allocate memory — #{tip}"
      rescue StandardError
        "failed to allocate memory — use /fix lib or bin/cli --fast"
      end

      def budget_block_if_exceeded
        max = @refs.session.budget_max.to_f
        return if max <= 0
        return if @refs.session.cost.to_f < max

        Master::Result.err(
          "budget exceeded: ¢#{( @refs.session.cost * 100).round(2)} / ¢#{(max * 100).round(2)} — use /cost or raise budget",
          category: :budget,
        )
      end

    end
  end
end
