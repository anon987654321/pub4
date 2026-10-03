# frozen_string_literal: true

require "tty-screen"
require_relative "../stream_accumulator"

module Master
  module CLI
    class Session
      TICK_SECONDS = 0.20
      SPINNER_FRAMES = ["*", "+", "x", "+"].freeze
      STAGE_EVENTS = {
        "infer:resolved" => "infer",
        "infer:confidence" => "infer",
        "infer:rejected" => "infer",
        "route:resolved" => "route",
        "llm:routed" => "model",
      }.freeze

      private

      # One line that repaints while a turn runs, and above it the turn as a
      # dmesg: each model call, file, command and request the turn makes, as a
      # unit attached to its parent. Routine bus events stay in the event log;
      # one /review publishes about 28,700 of them.
      def print_thinking_indicator
        init_thinking_state!
        return unless $stdout.tty?

        @spin_thread = Thread.new do
          frame = 0

          until @think_paused
            stage = @think_stage.to_s
            stage = "working" if stage.empty?
            line = one_row("#{SPINNER_FRAMES.fetch(frame % SPINNER_FRAMES.length)} #{stage} #{elapsed_seconds}s")
            $stdout.print("\r\e[K#{line}")
            $stdout.flush
            frame += 1
            sleep TICK_SECONDS
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "cli.spinner", event_bus: @refs.bus)
        end
      end

      def init_thinking_state!
        @think_mutex = Mutex.new
        @think_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @think_paused = false
        @think_stage = "intake"
        @activity&.reset!
        # `**`: a single star is colon-free names only, and every stage event has one.
        @think_sub = @refs.bus&.subscribe("**") { |payload| update_think_stage(payload) }
        @unit_sub = @refs.logging.listen { |line| print_unit_line(line) } if units_console?
      end

      # The fold stops to ask a person about a push, a hard reset or a deploy,
      # and a terminal the operator is typing into is a person. The operator
      # said approval belongs there, so the interactive session answers; the
      # daemon, a pipe and the web face build no asker and still refuse.
      #
      # Carried as a fiber local because the turn runs on its own thread and
      # CoreBridge builds the World deep below it. A thread spawned inside the
      # turn inherits fiber storage, so the asker answers only on the thread
      # the turn owns: a standing order firing mid-turn runs unattended and is
      # refused, as it is everywhere else.
      def terminal_ask(owner)
        return unless $stdin.tty? && $stdout.tty?

        lambda do |prompt:, **|
          next "no: asked off the terminal turn" unless Thread.current == owner

          answer_at_terminal(prompt)
        end
      end

      # y/N, with the spinner held still so the question is not painted over.
      # Anything but a yes is a no, which Core::Fold decides.
      def answer_at_terminal(prompt)
        @think_mutex&.synchronize do
          @think_paused = true
          print "\r\e[K"
        end
        print "#{@refs.renderer.render("ask0 at fold0: #{prompt} [y/N]", mode: :dmesg)} "
        $stdout.flush
        $stdin.gets.to_s.strip
      ensure
        @think_paused = false
      end

      # The spinner stops when a reply starts streaming; the units keep printing
      # until the turn ends, because a tool call can follow the first words.
      def stop_thinking_indicator
        @think_paused = true
        @spin_thread&.join(0.3)
        @spin_thread = nil
        @think_sub&.call
        @think_sub = nil
        print "\r\e[K" if $stdout.isatty
        $stdout.flush
      end

      def verbose_output?
        ENV["MASTER_CLI_VERBOSE"] == "1" || ENV["MASTER_CLI_TRACE"] == "1"
      end

      def units_console?
        @refs.logging.respond_to?(:listen) && Master::Trace::Dmesg.enabled?
      end

      def close_unit_console
        @unit_sub&.call
        @unit_sub = nil
      end

      def update_think_stage(payload)
        event = payload[:event].to_s
        @activity&.record(event, payload)
        @think_stage = stage_for(event, payload) || @think_stage
      end

      def stage_for(event, payload)
        return event.delete_prefix("stage:") if event.start_with?("stage:")
        return payload[:stage].to_s.downcase if event == "pipeline:stage_start"

        STAGE_EVENTS[event]
      end

      # What is worth saying out loud while a pass runs. A pass prints hundreds
      # of unit lines and speaking each would be a torrent; these are the ones a
      # person waiting for it would want called out — a reading finished, a pass
      # of repairs counted, the council's verdict, the pass itself ending.
      # Spoken as they happen, so the reply at the end has only its footer left
      # to say instead of the whole log.
      MILESTONE = /\A(?:obs\d+: done|scan\d+: (?:done|pass \d)|fix\d+: pass \d|crit\d+: |review\d+: (?:complete|incomplete))/

      # A pipe keeps stdout for the reply, so the units go to stderr there.
      def print_unit_line(line)
        return unless Master::Trace::Dmesg.enabled?

        Master::Voice::Playback.speak(line) if line.match?(MILESTONE)
        return unless verbose_output?

        io = $stdout.isatty ? $stdout : $stderr
        @think_mutex&.synchronize do
          @think_stage = line[/\A[^\s:]+/]
          io.print "\r\e[K" if io.isatty
          io.puts @refs.renderer.render(line, mode: :dim)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.print_unit_line", event_bus: @refs.bus)
      end

      # The spinner repaints with \r\e[K, which clears one row. A line wider
      # than the screen wraps onto a second row that nothing clears, and every
      # tick left another copy behind it. Unit lines are printed once and may
      # wrap.
      def one_row(text)
        width = TTY::Screen.width - 1
        text.length > width ? "#{text[0, width - 3]}..." : text
      rescue StandardError
        text
      end

      def elapsed_seconds
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @think_t0.to_f).floor
      end

      def build_stream_handler(buffer, &on_text)
        Master::CLI::StreamAccumulator.new(buffer, &on_text)
      end
    end
  end
end
