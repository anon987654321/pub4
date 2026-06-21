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
        return handle_repl_line(stripped) if stripped.start_with?("/")

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

      def suggested_next_prompt
        top = proposer.top
        return nil unless top
        @last_suggestion = top[:action]
        "#{top[:action]}  (#{top[:reason]})"
      end

      def accept_top_suggestion
        return unless @last_suggestion
        puts @refs.renderer.render("↳ #{@last_suggestion}", mode: :dim)
        @repl.handle_line(@last_suggestion)
      end

      def run_help(line = "/help")
        arg = line.to_s.strip.sub(%r{\A/\??help\s*}i, "").strip
        text = arg.empty? ? CommandRegistry.help_summary : CommandRegistry.help_text(arg)
        puts @refs.renderer.render(text, mode: :dim)
        puts @refs.renderer.render("<< for multiline. anything else is a prompt.", mode: :dim) if arg.empty?
      end

      def unknown_command(stripped)
        name = stripped.split(/\s/).first
        detail = CommandRegistry.help_text(name.delete_prefix("/"))
        puts @refs.renderer.render("unknown command: #{name}.", mode: :dim)
        puts @refs.renderer.render(detail, mode: :dim) if detail && !detail.start_with?("help: no detail")
      end

      def exit_cli
        @refs.session&.save!
        line = @refs.renderer&.closing
        puts line if line
        @running = false
      end

      def next_action_chips
        base = ["[/undo]", "[/why]", "[/last]"]
        base.unshift("[/fix #{violations}v]") if violations.positive?
        base
      end

      private

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
        @proposer.violations = violations
        @proposer
      end

      def replay_recent_turns
        tail = @refs.session.messages.last(REPLAY_TURNS * 2)
        return if tail.empty?
        puts @refs.renderer.render("resume0: replaying last #{tail.size} messages", mode: :dim)
        tail.each do |msg|
          tag = msg[:role] == :user ? "you" : "master"
          content = msg[:content].to_s
          first_line = content.lines.first.to_s
          snippet = first_line.strip[0, 100]
          puts @refs.renderer.render("  #{tag}: #{snippet}", mode: :dim)
        end
        puts
      end

      def print_repo_tree
        lines = Master::CommandRegistry.tree_lines(@refs.root)
        return if lines.empty?
        puts @refs.renderer.render("tree0: #{File.basename(@refs.root)} (#{lines.size} entries)", mode: :dim)
        lines.each { |l| puts @refs.renderer.render(l, mode: :dim) }
        puts
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.print_repo_tree", event_bus: @refs.bus)
      end

      def booted_before?
        flag = File.join(@refs.root, ".master", "booted_once")
        File.exist?(flag)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.booted_before?", event_bus: @refs.bus)
        false
      end

      def first_boot_bar
        return unless $stdout.isatty
        flag = File.join(@refs.root, ".master", "booted_once")
        return if File.exist?(flag)
        INIT_FRAMES.times do |i|
          bar = ("\u25B0" * (i + 1)) + ("\u25B1" * (INIT_FRAMES - i - 1))
          pct = ((i + 1) * 100 / INIT_FRAMES).to_s.rjust(3)
          print "\rinit0: #{bar} #{pct}%"
          $stdout.flush
          sleep INIT_FRAME_MS
        end
        puts
        FileUtils.mkdir_p(File.dirname(flag))
        File.write(flag, Time.now.to_s)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.mark_booted", event_bus: @refs.bus)
      end
    end
  end
end
