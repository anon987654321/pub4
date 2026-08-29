# frozen_string_literal: true

require_relative "../stream_accumulator"

module Master
  module CLI
    class Session
      SPIN_FRAMES = ["\u00B7", "\u2219", "\u2022", "\u25CF"].freeze
      SPIN_INTERVAL = 0.25
      DMESG_IGNORE = %w[bus:subscribe bus:unsubscribe ring:write].freeze
      STAGE_EVENTS = {
        "infer:resolved" => "infer",
        "infer:confidence" => "infer",
        "infer:rejected" => "infer-skip",
        "route:resolved" => "route",
        "llm:routed" => "model",
      }.freeze
      VERDICT_GLYPH = { ok: "\u2713", fail: "\u00D7", warn: "!", info: "\u00B7" }.freeze
      MUTATING_TOOLS = %w[WriteFile Edit StrReplace BatchReplace AstEdit FilePatch].freeze

      private

      def print_thinking_indicator
        return unless $stdout.isatty

        init_thinking_state!
        @spin_thread = spawn_spinner_thread
      end

      def init_thinking_state!
        @think_mutex = Mutex.new
        @think_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @think_stage = "intake"
        @think_sub = @refs.bus&.subscribe("*") do |payload|
          update_think_stage(payload)
          emit_dmesg_line(payload)
        end
      end

      def spawn_spinner_thread
        Thread.new do
          i = 0
          loop do
            @think_mutex.synchronize do
              frame = SPIN_FRAMES[i % SPIN_FRAMES.size]
              print "\r\e[K#{@refs.renderer.render("#{frame} thinking #{elapsed_seconds}s #{@think_stage}", mode: :dim)}"
              $stdout.flush
            end
            sleep SPIN_INTERVAL
            i += 1
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
        if ev.start_with?("stage:")
          @think_stage = ev.delete_prefix("stage:")
          return
        end
        if ev == "pipeline:stage_start" && payload[:stage]
          @think_stage = payload[:stage].to_s.downcase
          return
        end
        return unless STAGE_EVENTS.key?(ev)
          @think_stage = STAGE_EVENTS[ev]

      end

      def glyph_for_event(ev)
        case ev
        when /:(done|ok|success|rendered|synthesis)\b/ then VERDICT_GLYPH[:ok]
        when /:(error|fail|timeout|veto)\b/ then VERDICT_GLYPH[:fail]
        when /:(warn|warning|escalat)\b/ then VERDICT_GLYPH[:warn]
        else VERDICT_GLYPH[:info]
        end
      end

      def emit_dmesg_line(payload)
        ev = payload[:event].to_s
        return if ev.empty? || DMESG_IGNORE.include?(ev)
        file_line = format_file_dmesg(ev, payload)
        kv = payload.reject { |k, _| %i[event ts topic path op bytes tool].include?(k) }
                    .map { |k, v| "#{k}=#{v.to_s[0, 60]}" }.join(" ")
        diff = ev == "tool:after" && MUTATING_TOOLS.include?(payload[:tool].to_s) ? diff_stat(payload[:path]) : nil
        tail = diff ? " #{diff}" : ""
        body = file_line || ev
        extras = [kv, tail].reject(&:empty?).join(" ")
        line = "  %s [%7d] %s%s" % [glyph_for_event(ev), elapsed_ms, body, extras.empty? ? "" : " #{extras}"]
        @think_mutex&.synchronize do
          print "\r\e[K"
          $stdout.puts @refs.renderer.render(line, mode: :dim)
          $stdout.flush
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.print_event", event_bus: @refs.bus)
      end

      def format_file_dmesg(ev, payload)
        return unless ev.start_with?("tool:")
        path = payload[:path].to_s
        return if path.empty?

        op = payload[:op].to_s
        op = ev == "tool:before" ? "touch" : "done" if op.empty?
        bytes = payload[:bytes]
        size = bytes ? " #{bytes}B" : ""
        rel = path.delete_prefix("#{@refs.root}/")
        rel = path if rel == path
        "#{op} #{rel}#{size}"
      end

      def diff_stat(path)
        return unless path && !path.empty?
        out, = Master::Io::Exec.capture2e("git", "-C", @refs.root, "diff", "--numstat", "--", path)
        m = out.lines.first&.match(/^(\d+)\s+(\d+)/)
        m ? "+#{m[1]}/-#{m[2]}" : nil
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.diff_stat", event_bus: @refs.bus)
      end

      def elapsed_ms
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @think_t0.to_f) * 1000).round
      end

      def elapsed_seconds
        (elapsed_ms / 1000.0).floor
      end

      def build_stream_handler(buffer, &on_text)
        Master::CLI::StreamAccumulator.new(buffer, &on_text)
      end
    end
  end
end
