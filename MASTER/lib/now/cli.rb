# frozen_string_literal: true

require_relative "cli/signal_handler"
require "fileutils"
require_relative "cli/command_ops"
require_relative "cli/thinking_indicator"
require_relative "cli/repl"
require_relative "cli/renderer_delegate"
require_relative "cli/background_scan"
require_relative "cli/stream_accumulator"

require "open3"
require "fileutils"

module Master
  module Now
    class CLI
      REPLAY_TURNS = 5
      DMESG_BUFFER = 80

      SEVERITY_ICON = {
        error: "!!",
        warning: "!",
        style: ".",
        critical: "!!"
      }.freeze
      SLASH_COMMANDS = %w[
        /help /exit /quit /undo /redo /history /why /focus /last /cmd /dmesg /chips /propose /principles /restart
        /self /ui-critique /sound-critique /rebuild /context /checkpoint /verify /rails-pwa-audit /rails-pwa-fix /swallow-report
      ].freeze

      attr_reader :container, :session, :agent, :renderer, :bus, :scanner, :root
      attr_accessor :running, :last_ok, :violations, :focus_mode, :show_chips, :last_cost, :last_input

      def initialize(container:)
        @container = container
        assign_container_refs!(container)
        @display = CLI::RendererDelegate.new(cli: self, voice_renderer: @renderer)
        @repl = CLI::Repl.new(cli: self)
        @background_scan = CLI::BackgroundScan.new(cli: self)
        @signal_handler = CLI::SignalHandler.new(cli: self)
        @violations_mutex = Mutex.new
        @running = false
        @interrupt_at = Time.now
        @last_ok = true
        @violations = 0
        @prev_violations = 0
        @bg_thread = nil
        @seen_violations = {}
        @user_active = false
        @focus_mode = false
        @show_chips = false
        @last_input = nil
        @last_cost = 0.0
        @dmesg_sub = nil
        set_visitor_mode_if_unauthenticated
      end

      def run(initial_message = nil)
        @signal_handler.install!
        @session.load! if @session.exists?
        @background_scan.start!
        first_boot_bar
        puts @display.splash(@agent.model)
        puts @display.session_line(@session.name) if @session.name
        print_repo_tree unless booted_before?
        replay_recent_turns if @session.messages.any?
        run_input(initial_message) if initial_message
        @running = true
        @repl.loop
      end

      def pipe(input)
        stripped = input.strip
        if stripped.empty?
          @bus&.publish("cli:empty_input", source: "pipe")
          return
        end
        run_input(stripped)
      end

      def process(input) = run_input(input)

      def run_input(input)
        return if input.strip.empty?

        @user_active = true
        @last_input = input
        state = { streamed: false, thinking_shown: true }
        accumulated = +""
        on_chunk = stream_chunk_handler(accumulated, state)

        print_thinking_indicator
        @pipeline_thread = Thread.new do
          Thread.current.report_on_exception = false
          @pipeline.call(Result.ok(user_message: input, on_chunk: on_chunk))
        end
        result = begin
          @pipeline_thread.value
        rescue StandardError => _e
          Result.err("aborted", category: :abort)
        end
        @display.display_result(result, accumulated, state[:streamed])
      ensure
        @pipeline_thread = nil
        stop_thinking_indicator
        @user_active = false
      end

      def update_violations(n)
        @violations_mutex.synchronize do
          @prev_violations = @violations
          @violations = n
        end
      end

      def suggested_next_prompt
        top = proposer.top
        return nil unless top
        @last_suggestion = top[:action]
        "#{top[:action]}  (#{top[:reason]})"
      end

      def accept_top_suggestion
        return unless @last_suggestion
        puts @display.render("↳ #{@last_suggestion}", mode: :dim)
        @repl.handle_line(@last_suggestion)
      end

      def run_help(line = "/help")
        arg = line.to_s.strip.sub(%r{\A/\??help\s*}i, "").strip
        text = arg.empty? ? CommandRegistry::HelpTopics.summary : CommandRegistry::HelpTopics.detail(arg)
        puts @display.render(text, mode: :dim)
        puts @display.render("<< for multiline. anything else is a prompt.", mode: :dim) if arg.empty?
      end

      def unknown_command(stripped)
        name = stripped.split(/\s/).first
        detail = CommandRegistry::HelpTopics.detail(name.delete_prefix("/"))
        puts @display.render("unknown command: #{name}.", mode: :dim)
        puts @display.render(detail, mode: :dim) if detail && !detail.start_with?("help: no detail")
      end

      def exit_cli
        @session.save!
        line = @display.closing
        puts line if line
        @running = false
      end

      def run_self_scan
        result = Master::Judge::Scan::SelfScan.new(scanner: @scanner, root: @root, event_bus: @bus).call(stream: true, autofix: true)
        if result.ok?
          summary = result.value!
          return if summary.violation_count.zero?
          puts @display.render(summary.line, mode: :dim)
        else
          puts @display.render(result.message, mode: :warning)
        end
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
            puts @display.speaker_tag
          end
          print text
          $stdout.flush
          state[:streamed] = true
        end
        handler
      end

      def set_visitor_mode_if_unauthenticated
        web_token = @config&.dig("web_token")
        Fiber[:master_visitor] = true if web_token.nil? || web_token.empty?
      end

      def assign_container_refs!(deps)
        @session = deps[:session]
        @agent = deps[:agent]
        @renderer = deps[:renderer]
        @logging = deps[:logging]
        @undo = deps[:undo]
        @config = deps[:config]
        @pipeline = deps[:pipeline]
        @scanner = deps[:scanner]
        @root = deps.fetch(:root, Dir.pwd)
        @diff_stager = deps[:diff_stager]
        @bus = deps[:bus]
      end

      def proposer
        @proposer ||= Propose.new(container: @container)
        @proposer.violations = violations
        @proposer
      end

      def replay_recent_turns
        tail = @session.messages.last(REPLAY_TURNS * 2)
        return if tail.empty?
        puts @display.render("resume0: replaying last #{tail.size} messages", mode: :dim)
        tail.each do |msg|
          tag = msg[:role] == :user ? "you" : "master"
          content = msg[:content].to_s
          first_line = content.lines.first.to_s
          snippet = first_line.strip[0, 100]
          puts @display.render("  #{tag}: #{snippet}", mode: :dim)
        end
        puts
      end

      def print_repo_tree
        lines = Master::CommandRegistry.tree_lines(@root)
        return if lines.empty?
        puts @display.render("tree0: #{File.basename(@root)} (#{lines.size} entries)", mode: :dim)
        lines.each { |l| puts @display.render(l, mode: :dim) }
        puts
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.print_repo_tree", event_bus: @bus)
      end

      def booted_before?
        flag = File.join(@root, ".master", "booted_once")
        File.exist?(flag)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.booted_before?", event_bus: @bus)
        false
      end

      INIT_FRAMES = 20
      INIT_FRAME_MS = 0.04

      def first_boot_bar
        return unless $stdout.isatty
        flag = File.join(@root, ".master", "booted_once")
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
        Master::Ground::Swallow.log(e, context: "cli.mark_booted", event_bus: @bus)
      end
    end
  end
end