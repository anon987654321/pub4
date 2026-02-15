# frozen_string_literal: true

module MASTER
  # Merged from progress.rb
  module Progress
    extend self

    SPINNERS = {
      dots:    %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏],
      line:    %w[- \\ | /],
      blocks:  %w[▏ ▎ ▍ ▌ ▋ ▊ ▉ █],
      arrows:  %w[← ↖ ↑ ↗ → ↘ ↓ ↙],
      circuit: %w[◯ ◔ ◑ ◕ ●]
    }.freeze



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
        bar_width = 30
        filled = (pct / 100.0 * bar_width).round
        bar = "[#{'█' * filled}#{'░' * (bar_width - filled)}]"

        elapsed = Time.now - @start_time
        eta = @current > 0 ? (elapsed / @current * (@total - @current)).round : 0

        print "\r  #{@message}: #{bar} #{pct}% (#{@current}/#{@total}) ETA: #{eta}s"
      end
    end

    def spinner(message = "Processing...", style: :dots, &block)
      # Delegate to UI.spinner (class method) for consistency
      require_relative 'spinner'
      s = MASTER::UI.spinner(message, format: :classic)
      s.auto_spin

      result = yield
      s.success("Done")
      result
    rescue => e
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
