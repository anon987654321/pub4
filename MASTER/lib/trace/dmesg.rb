# frozen_string_literal: true

module Master
  module Trace
    # OpenBSD dmesg grammar for the terminal: "unit at parent: fact" when a
    # unit attaches, "unit: fact" after it. One fact per line, sentence case,
    # human units, and no key=value: a row of keys is the log's shape, and the
    # log is runtime/events/activity.jsonl.
    #
    # Weight carries the hierarchy, as Bringhurst would have it: a result at
    # normal weight, context dimmed, a failure in red, and nothing else. Off a
    # terminal, or under NO_COLOR, there is no colour at all, so a pipe and a
    # saved transcript read as plain text.
    #
    # Config: data/limits.yml#dmesg (enabled: true). ENV MASTER_DMESG=0|1 overrides.
    module Dmesg
      module_function

      def enabled?
        env = ENV["MASTER_DMESG"]
        return env != "0" if env && !env.empty?

        cfg.fetch("enabled", true) != false
      end

      def cfg
        @cfg ||= begin
          data = Master.load_yaml(Master.limits_path, default: {}) || {}
          data["dmesg"].is_a?(Hash) ? data["dmesg"] : { "enabled" => true }
        rescue StandardError
          { "enabled" => true }
        end
      end

      def reload!
        @cfg = nil
        cfg
      end

      # The one terminal every unit writes to. Replaceable, so a test can hand
      # it an IO and read back exactly what an operator would see.
      def console = @console ||= Console.new

      def console=(value)
        @console = value
      end

      def attach(unit, parent, detail = nil)
        line = detail.to_s.empty? ? "#{unit} at #{parent}" : "#{unit} at #{parent}: #{detail}"
        emit(line)
      end

      def status(unit, msg) = emit("#{unit}: #{msg}")

      # What a stage found or made, at full weight.
      def result(unit, fact) = emit("#{unit}: #{fact}", tone: :result)

      # What failed, then the next action, so an error never ends in a shrug.
      def failure(unit, what, fix: nil)
        line = emit("#{unit}: #{what}", tone: :failure)
        emit("fix: #{fix}") if fix
        line
      end

      # A tick: the live line on a terminal, and nothing anywhere else. The
      # result line that ends the stage carries the facts the ticks counted.
      def progress(unit, text)
        return unless enabled?

        console.progress("#{unit}: #{text}")
      end

      def emit(line, tone: :context)
        return unless enabled?

        console.emit(line.to_s.gsub(/\s+/, " ").strip, tone:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Trace::Dmesg.emit")
        nil
      end

      def flush = console.flush

      # Human units: "4,432 findings", "58 s", "2.1 GB".
      module Units
        module_function

        BYTE_STEPS = [["GB", 1024**3], ["MB", 1024**2], ["KB", 1024]].freeze

        def number(value)
          whole, fraction = value.to_s.split(".", 2)
          grouped = whole.reverse.scan(/\d{1,3}-?/).join(",").reverse.sub(/\A-,/, "-")
          fraction ? "#{grouped}.#{fraction}" : grouped
        end

        def count(value, noun, plural = "#{noun}s")
          "#{number(value.to_i)} #{value.to_i == 1 ? noun : plural}"
        end

        # Under ten seconds a tenth still means something; past a minute the
        # seconds are the detail.
        def seconds(value)
          secs = value.to_f
          return "#{secs.round(1)} s".sub(".0 s", " s") if secs < 10
          return "#{secs.round} s" if secs < 60

          minutes, rest = secs.round.divmod(60)
          rest.zero? ? "#{minutes} min" : "#{minutes} min #{rest} s"
        end

        def bytes(value)
          size = value.to_i
          unit, step = BYTE_STEPS.find { |_, limit| size >= limit }
          return count(size, "byte") unless unit

          "#{(size.to_f / step).round(1)} #{unit}".sub(".0 ", " ")
        end
      end

      # One terminal's state: the colour decision, the live line and the
      # repeat counter. Lines arrive from the pipeline thread and the spinner
      # at once, so every write holds the lock.
      class Console
        TONE_CODES = { context: "2", failure: "31" }.freeze
        LIVE_INTERVAL = 0.1

        # A painter owns the live line when set: the thinking indicator repaints
        # it on its own tick, and a second painter would flicker against it.
        attr_accessor :live_painter
        attr_reader :live_text

        def initialize(io: nil)
          @io = io
          @lock = Monitor.new
          @last = nil
          @repeats = 0
          @held = nil
          @live_text = nil
          @live_at = 0.0
        end

        def out = @io || $stdout
        def tty? = out.respond_to?(:tty?) && out.tty?

        # NO_COLOR (no-color.org) and TERM=dumb both mean plain text, and so
        # does anything that is not a terminal.
        def color? = tty? && ENV["NO_COLOR"].to_s.empty? && ENV["TERM"] != "dumb"

        def paint(text, tone)
          code = TONE_CODES[tone]
          code && color? ? "\e[#{code}m#{text}\e[0m" : text
        end

        # A repeat prints nothing until the run ends, then once, as syslogd
        # says it: "last message repeated 13 times".
        def emit(line, tone: :context)
          @lock.synchronize do
            next @held << [line, tone] if @held

            write_line(line, tone)
          end
          line
        end

        def progress(text)
          return unless tty?

          @lock.synchronize do
            @live_text = text
            paint_live unless live_painter
          end
        end

        # On a terminal a turn holds its narration until the answer is out, so
        # the reply leads. The live line keeps moving meanwhile.
        def hold!
          @lock.synchronize { @held ||= [] }
        end

        def release!
          @lock.synchronize do
            held = @held.to_a
            @held = nil
            held.each { |line, tone| write_line(line, tone) }
            close_repeats
          end
        end

        def holding? = !@held.nil?

        def flush
          @lock.synchronize do
            close_repeats
            clear_live
            out.flush
          end
        end

        def clear_live
          @live_text = nil
          out.print("\r\e[K") if tty?
        end

        private

        def write_line(line, tone)
          if line == @last
            @repeats += 1
            return
          end

          close_repeats
          @last = line
          out.print("\r\e[K") if tty?
          out.puts(paint(line, tone))
        end

        def close_repeats
          return if @repeats.zero?

          out.print("\r\e[K") if tty?
          out.puts(paint("last message repeated #{Units.count(@repeats, 'time')}", :context))
          @repeats = 0
          @last = nil
        end

        def paint_live
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          return if now - @live_at < LIVE_INTERVAL

          @live_at = now
          out.print("\r\e[K#{paint(@live_text, :context)}")
          out.flush
        end
      end
    end
  end
end
