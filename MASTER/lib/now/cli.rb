# frozen_string_literal: true

require_relative "cli/container"
require_relative "cli/signals"
require_relative "cli/command_ops"
require_relative "cli/thinking_indicator"
require_relative "cli/result_display"
require_relative "cli/background_scan"
require_relative "cli/repl_flow"

require "open3"
require "reline"
require "tty-prompt"
require "tty-screen"
require "fileutils"

module Master
  module Now
    class CLI
      IDLE_SLEEP_DEFAULT = 60
      # Replay only the last few turns so startup context stays readable.
      REPLAY_TURNS = 5
      # Keep enough diagnostic lines for recent failures without flooding the UI.
      DMESG_BUFFER = 80
      MULTILINE_MAX_LINES = 500
      HISTORY_LIMIT = 2_000

      SEVERITY_ICON = {
        error: "!!",
        warning: "!",
        style: ".",
        critical: "!!"
      }.freeze
      SLASH_COMMANDS = %w[
        /help /exit /quit /undo /redo /rollback /history /grep /audit /cost /watch /why /focus /last /cmd /dmesg /chips /propose /principles /restart
        /self /phase /ui-critique /sound-critique /rebuild /context /checkpoint /verify /rails-pwa-audit /rails-pwa-fix /swallow-report
      ].freeze

      attr_reader :container
      attr_reader :exit_code

      def initialize(container:)
        @container = container
        @refs = CLI::Container.from_hash(container)
        Reline::HISTORY.clear
        load_cli_history
        setup_completion
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
        @dmesg_sub = nil
        @exit_code = 0
        set_visitor_mode_if_unauthenticated
      end

      def run(initial_message = nil)
        setup_signals
        @refs.session.load! if @refs.session.exists?
        start_background_loop
        first_boot_bar
        puts @refs.renderer.splash(@refs.agent.model)
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
        run_input(stripped)
      end

      def process(input)
        run_input(input)
      end

      def run_input(input)
        return empty_input(:run_input) if input.strip.empty?

        @user_active = true
        @last_input = input
        paste = paste_like_input?(input)
        state = { streamed: false, thinking_shown: !paste }
        accumulated = +""
        on_chunk = build_stream_handler(accumulated) do |text|
          handle_stream_text(text, state)
        end

        print_thinking_indicator unless paste
        @pipeline_thread = Thread.new do
          Thread.current.report_on_exception = false
          @refs.pipeline.call(Result.ok(user_message: input, on_chunk: on_chunk))
        end
        result = begin
          @pipeline_thread.value
        rescue StandardError => _e
          Result.err("aborted", category: :abort)
        end
        display_result(result:, accumulated:, streamed: state[:streamed])
      ensure
        @pipeline_thread = nil
        stop_thinking_indicator
        @user_active = false
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

    end
  end
end
