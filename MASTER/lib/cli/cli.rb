# frozen_string_literal: true

require_relative "cli/container"
require_relative "cli/signals"
require_relative "cli/command_ops"
require_relative "cli/thinking_indicator"
require_relative "cli/result_display"
require_relative "cli/background_scan"
require_relative "cli/repl_flow"
require_relative "cli/bridge_run"

require "open3"
require "reline"
require "tty-prompt"
require "tty-screen"
require "fileutils"

module Master
  module CLI
    class CLI
      CONFIG = (Master.load_yaml(Master.data_path("patterns.yml")) || {}).fetch("cli", {}).freeze
      IDLE_SLEEP_DEFAULT = CONFIG.fetch("idle_sleep_seconds", 60)
      REPLAY_TURNS = CONFIG.fetch("replay_turns", 5)
      DMESG_BUFFER_LINES = CONFIG.fetch("dmesg_buffer_lines", 80)
      MULTILINE_MAX_LINES = CONFIG.fetch("multiline_max_lines", 500)
      HISTORY_LIMIT = CONFIG.fetch("history_limit", 2_000)
      ERROR_TEXT_MAX_BYTES = 200
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
        @refs = CLI::Container.from_hash(container)
        Reline::HISTORY.clear
        load_cli_history
        setup_completion
        init_session_state!
        set_visitor_mode_if_unauthenticated
      end

      def run(initial_message = nil)
        setup_signals
        @refs.session.load! if @refs.session.exists?
        start_background_loop
        first_boot_bar
        puts @refs.renderer.splash(@refs.agent.model)
        print_boot_wayfinding unless skip_boot_scan?
        puts @refs.renderer.session_line(@refs.session.name) if @refs.session.name
        print_repo_tree unless booted_before?
        replay_recent_turns if @refs.session.messages.any?
        run_input(initial_message) if initial_message
        @running = true
        repl_loop
      end

      def pipe(input)
        stripped = input.strip
        return empty_input(:pipe) if stripped.empty?

        handle_repl_line(stripped)
      end

      def process(input)
        run_input(input)
      end

      def run_input(input)
        return empty_input(:run_input) if input.strip.empty?
        blocked = check_budget_blocks(input)
        return blocked if blocked

        @user_active = true
        @last_input = input
        paste, state, accumulated = init_turn_state(input)

        print_thinking_indicator unless paste
        result = dispatch_turn(input, accumulated, state)
        print_bridge_footer(result.value[:core], state:) if result.ok? && state[:streamed] && result.value[:core]
        display_result(result:, accumulated:, streamed: state[:streamed])
      ensure
        @pipeline_thread = nil
        stop_thinking_indicator
        @user_active = false
      end

      private

      def init_session_state!
        @running = false
        @interrupt_at = Time.now
        @last_ok = true
        @violations = 0
        @prev_violations = 0
        @violations_mutex = Mutex.new
        @bg_thread = nil
        @bg_control = Queue.new
        @seen_violations = {}
        @user_active = false
        @focus_mode = false
        @show_chips = false
        @last_input = nil
        @last_cost = 0.0
        @last_tokens = 0
        @seen_error_categories = {}
        @dmesg_sub = nil
        @exit_code = 0
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

      def dispatch_turn(input, accumulated, state)
        on_turn = build_on_turn_handler(accumulated, state)
        @pipeline_thread = spawn_pipeline_thread(input, on_turn)
        fetch_pipeline_result
      end

      def build_on_turn_handler(accumulated, state)
        lambda do |line|
          accumulated << line << "\n"
          handle_stream_text(line + "\n", state) if $stdout.isatty
        end
      end

      def spawn_pipeline_thread(input, on_turn)
        Thread.new do
          Thread.current.report_on_exception = false
          TurnRouter.call(
            message: input,
            container: @container,
            felt_sense: cli_felt_sense,
            on_turn:,
          )
        end
      end

      def fetch_pipeline_result
        @pipeline_thread.value
      rescue NoMemoryError
        Result.err(host_oom_message, category: :infrastructure)
      rescue StandardError => _e
        Result.err("aborted", category: :abort)
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
        puts @refs.renderer.speaker_tag unless state[:streamed]
        print text
        $stdout.flush
        state[:streamed] = true
      end

      def suggested_next_prompt
        top = proposer.top
        return unless top
        @last_suggestion = top[:action]
        "#{top[:action]}  (#{top[:reason]})"
      end

      def accept_top_suggestion
        return unless @last_suggestion
        puts @refs.renderer.render("↳ #{@last_suggestion}", mode: :dim)
        @repl.handle_line(@last_suggestion)
      end

      def next_action_chips
        base = ["[/undo]", "[/why]", "[/last]"]
        base.unshift("[/fix #{violations_count}v]") if violations_count.positive?
        base
      end

      def stream_chunk_handler(accumulated, state)
        handler = CLI::StreamAccumulator.new(accumulated).handler do |text|
          if state[:thinking_shown] && $stdout.isatty
            stop_thinking_indicator
            print "\r\e[K"
            state[:thinking_shown] = false
          end
          unless state[:streamed]
            puts @refs.renderer.speaker_tag
          end
          print text
          $stdout.flush
          state[:streamed] = true
        end
        handler
      end

      def proposer
        @proposer ||= Propose.new(container: @container)
        @proposer.violations = violations_count
        @proposer
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
        nil
      end

      def host_oom_message
        tip = Master::Ground::HostBudget.heavy_repo_message
        "failed to allocate memory — #{tip}"
      rescue StandardError
        "failed to allocate memory — use /scan lib or bin/cli --fast"
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
