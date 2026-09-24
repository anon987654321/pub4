# frozen_string_literal: true

require_relative "session/container"
require_relative "session/signals"
require_relative "session/command_ops"
require_relative "session/thinking_indicator"
require_relative "activity"
require_relative "session/result_display"
require_relative "session/background_scan"
require_relative "session/repl_flow"
require_relative "session/bridge_run"

require "open3"
require "reline"
require "tty-prompt"
require "tty-screen"
require "fileutils"

module Master
  module CLI
    class Session
      CONFIG = (Master.load_yaml(Master.data_path("patterns.yml")) || {}).fetch("cli", {}).freeze
      IDLE_SLEEP_DEFAULT = CONFIG.fetch("idle_sleep_seconds", 60)
      REPLAY_TURNS = CONFIG.fetch("replay_turns", 5)
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
        @refs = Container.from_hash(container)
        Reline::HISTORY.clear
        load_cli_history
        setup_completion
        init_session_state!
        set_visitor_mode_if_unauthenticated
      end

      def run(initial_message = nil)
        setup_signals
        @refs.agent.pin_boot_model! if @refs.agent.respond_to?(:pin_boot_model!)
        @refs.session.load! if @refs.session.exists?
        start_background_loop
        # One vertical rhythm: the dmesg, a blank line, the ready block, then
        # a blank line before each block that follows and before the prompt.
        puts @refs.renderer.splash(@refs.agent.model)
        start_boot_scan unless skip_boot_scan?
        puts @refs.renderer.session_line(@refs.session.name) if @refs.session.name
        print_repo_tree unless booted_before?
        replay_recent_turns if @refs.session.messages.any?
        puts
        run_input(initial_message) if initial_message
        @running = true
        repl_loop
      end

      def pipe(input)
        stripped = input.strip
        return empty_input(:pipe) if stripped.empty?

        handle_repl_line(stripped)
      end

      def run_input(input)
        return empty_input(:run_input) if input.strip.empty?
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
      ensure
        @pipeline_thread = nil
        stop_thinking_indicator
        close_unit_console
        @user_active = false
      end

      private

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
        on_turn = build_on_turn_handler(accumulated, state)
        @pipeline_thread = spawn_pipeline_thread(input, on_turn)
        fetch_pipeline_result
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

      def spawn_pipeline_thread(input, on_turn)
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
          )
        end
      end

      # Thread#value answers nil for a thread that was killed, rather than
      # raising, and signals.rb kills this one on ^C. Interrupt is not a
      # StandardError and a killed thread raises nothing, so the nil is the
      # only sign of a cancel. A turn that raised is a failure, named as one.
      def fetch_pipeline_result
        @pipeline_thread.value || Result.err("interrupted", category: :abort)
      rescue NoMemoryError
        Result.err(host_oom_message, category: :infrastructure)
      rescue StandardError => e
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
          print "\r\e[K"
          state[:thinking_shown] = false
        end
        print wrap_stream(text, state)
        $stdout.flush
        state[:streamed] = true
      end

      # A streamed reply wraps at word boundaries against the measure a printed
      # one gets through Renderer#measure; unwrapped, a phone terminal split
      # words at its edge. The transcript keeps the text as it arrived. Fenced
      # code, table rows and indented lines pass through, and a word split
      # across two chunks is never broken, because the half already printed
      # cannot be taken back.
      def wrap_stream(text, state)
        state[:width] ||= reply_measure
        text.scan(/\n|[^\S\n]+|\S+/).map { |piece| wrap_piece(piece, state) }.join
      end

      def wrap_piece(piece, state)
        return stream_newline(state) if piece == "\n"

        column = state[:column].to_i
        word = !piece.strip.empty?
        mark_raw_line(piece, state) if column.zero?
        breaks = word && column.positive? && state[:after_space] && !state[:fenced] && !state[:raw_line] &&
                 column + piece.length > state[:width]
        state[:column] = breaks ? piece.length : column + piece.length
        state[:after_space] = !word
        breaks ? "\n#{piece}" : piece
      end

      def mark_raw_line(piece, state)
        state[:fenced] = !state[:fenced] if piece.start_with?("```")
        state[:raw_line] = piece.start_with?("|", "```") || piece.match?(/\A[^\S\n]{2,}\z/)
      end

      def stream_newline(state)
        state[:column] = 0
        state[:after_space] = true
        state[:raw_line] = false
        "\n"
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
