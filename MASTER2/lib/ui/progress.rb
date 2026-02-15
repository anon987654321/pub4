# frozen_string_literal: true

module MASTER
  module Progress
    extend self

    SPINNERS = {
      dots:    %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏],
      line:    %w[- \\ | /],
      blocks:  %w[▏ ▎ ▍ ▌ ▋ ▊ ▉ █],
      arrows:  %w[← ↖ ↑ ↗ → ↘ ↓ ↙],
      circuit: %w[◯ ◔ ◑ ◕ ●]
    }.freeze

    class Spinner
      def initialize(message = "Processing...", style: :dots)
        @message = message
        @frames = SPINNERS[style] || SPINNERS[:dots]
        @index = 0
        @running = false
        @thread = nil
      end

      def start
        @running = true
        @thread = Thread.new do
          while @running
            print "\r  #{@frames[@index % @frames.size]} #{@message}"
            @index += 1
            sleep 0.1
          end
        end
        self
      end

      def update(message)
        @message = message
      end

      def stop(final_message = nil)
        @running = false
        @thread&.join
        print "\r#{' ' * 60}\r"
        puts "  ✓ #{final_message}" if final_message
      end

      def success(message)
        stop("#{message}")
      end

      def error(message)
        @running = false
        @thread&.join
        print "\r#{' ' * 60}\r"
        puts "  ✗ #{message}"
      end
    end

    class ProgressBar
      def initialize(total:, message: "Progress")
        @total = total
        @current = 0
        @message = message
        @start_time = Time.now
      end

      def advance(by = 1)
        @current += by
        render
      end

      def set(value)
        @current = value
        render
      end

      def finish
        @current = @total
        render
        puts
      end

      private

      def render
        pct = (@current.to_f / @total * 100).round(1)
        bar = UI.render_bar(pct)

        elapsed = Time.now - @start_time
        eta = @current > 0 ? (elapsed / @current * (@total - @current)).round : 0

        print "\r  #{@message}: #{bar} #{pct}% (#{@current}/#{@total}) ETA: #{eta}s"
      end
    end

    def spinner(message = "Processing...", style: :dots, &block)
      s = Spinner.new(message, style: style)
      s.start

      result = yield
      s.success("Done")
      result
    rescue StandardError => e
      s.error(e.message)
      raise
    end

    def progress_bar(total:, message: "Progress", &block)
      bar = ProgressBar.new(total: total, message: message)
      yield bar
      bar.finish
    end

    def thinking(duration = nil)
      frames = %w[thinking. thinking.. thinking...]
      spinner = Spinner.new(frames.first, style: :circuit)
      spinner.start

      if block_given?
        result = yield
        spinner.success("Complete")
        result
      else
        # Auto-stop after duration if given
        if duration
          sleep duration
          spinner.stop
        end
        spinner
      end
    end
  end

end
