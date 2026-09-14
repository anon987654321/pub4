# frozen_string_literal: true

require_relative "../stream_accumulator"

module Master
  module CLI
    class Session
      TICK_SECONDS = 0.25
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
        @spin_thread = spawn_spinner_thread if $stdout.isatty
      end

      def init_thinking_state!
        @think_mutex = Mutex.new
        @think_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @think_stage = "intake"
        # `**`: a single star is colon-free names only, and every stage event has one.
        @think_sub = @refs.bus&.subscribe("**") { |payload| update_think_stage(payload) }
        @unit_sub = @refs.logging.listen { |line| print_unit_line(line) } if units_console?
      end

      def spawn_spinner_thread
        Thread.new do
          loop do
            @think_mutex.synchronize do
              print "\r\e[K#{@refs.renderer.render("thinking #{elapsed_seconds}s, #{@think_stage}", mode: :dim)}"
              $stdout.flush
            end
            sleep TICK_SECONDS
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "cli.spinner", event_bus: @refs.bus)
        end
      end

      # The spinner stops when a reply starts streaming; the units keep printing
      # until the turn ends, because a tool call can follow the first words.
      def stop_thinking_indicator
        @spin_thread&.kill
        @spin_thread = nil
        @think_sub&.call
        @think_sub = nil
        print "\r\e[K" if $stdout.isatty
        $stdout.flush
      end

      def units_console?
    @refs.logging.respond_to?(:listen) && Master::Trace::Dmesg.enabled?
  end

  def close_unit_console
        @unit_sub&.call
        @unit_sub = nil
      end

      def update_think_stage(payload)
        ev = payload[:event].to_s
        stage = if ev.start_with?("stage:") then ev.delete_prefix("stage:")
                elsif ev == "pipeline:stage_start" then payload[:stage]&.to_s&.downcase
                else STAGE_EVENTS[ev]
                end
        @think_stage = stage if stage
      end

      # A pipe keeps stdout for the reply, so the units go to stderr there.
      def print_unit_line(line)
        return unless Master::Trace::Dmesg.enabled?

        io = $stdout.isatty ? $stdout : $stderr
        @think_mutex&.synchronize do
          @think_stage = line[/\A[^\s:]+/]
          io.print "\r\e[K" if io.isatty
          io.puts @refs.renderer.render(line, mode: :dim)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.print_unit_line", event_bus: @refs.bus)
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
