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

      # One line that repaints while a turn runs, and above it one line per file
      # the turn wrote. Every other bus event is routine: the event log already
      # holds it, and silence on success keeps it off the terminal; one /review
      # publishes about 28,700 of them.
      def print_thinking_indicator
        return unless $stdout.isatty

        init_thinking_state!
        @spin_thread = spawn_spinner_thread
      end

      def init_thinking_state!
        @think_mutex = Mutex.new
        @think_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @think_stage = "intake"
        # `**`: a single star is colon-free names only, and every stage event has one.
        @think_sub = @refs.bus&.subscribe("**") do |payload|
          update_think_stage(payload)
          print_write_line(payload)
        end
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

      def stop_thinking_indicator
        @spin_thread&.kill
        @spin_thread = nil
        @think_sub&.call
        @think_sub = nil
        print "\r\e[K" if $stdout.isatty
        $stdout.flush
      end

      def update_think_stage(payload)
        ev = payload[:event].to_s
        stage = if ev.start_with?("stage:") then ev.delete_prefix("stage:")
                elsif ev == "pipeline:stage_start" then payload[:stage]&.to_s&.downcase
                else STAGE_EVENTS[ev]
                end
        @think_stage = stage if stage
      end

      # `write lib/cli/session.rb 2140 bytes, +12 -3`: the effect, then its size.
      def print_write_line(payload)
        return unless payload[:event] == "tool:after"
        return unless Master::Trace::WriteTracker::MUTATING_TOOLS.include?(payload[:tool].to_s)

        path = payload[:path].to_s
        return if path.empty?

        line = [write_label(payload, path), diff_stat(path)].compact.join(", ")
        @think_mutex&.synchronize do
          print "\r\e[K"
          puts @refs.renderer.render(line, mode: :dim)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.print_write_line", event_bus: @refs.bus)
      end

      def write_label(payload, path)
        op = payload[:op].to_s.empty? ? "edit" : payload[:op]
        bytes = payload[:bytes] ? " #{payload[:bytes]} bytes" : ""
        "#{op} #{path.delete_prefix("#{@refs.root}/")}#{bytes}"
      end

      def diff_stat(path)
        out, = Master::Io::Exec.capture2e("git", "-C", @refs.root, "diff", "--numstat", "--", path)
        m = out.lines.first&.match(/^(\d+)\s+(\d+)/)
        m ? "+#{m[1]} -#{m[2]}" : nil
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
