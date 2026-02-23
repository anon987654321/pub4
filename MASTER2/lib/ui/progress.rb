# frozen_string_literal: true

module MASTER
  module Progress
    module_function

    # Progress::Spinner delegates to the canonical UI::SubtleSpinner
    Spinner = MASTER::UI::SubtleSpinner

    class ProgressBar
      def initialize(total:, message: "Progress")
        @total   = total.to_f
        @current = 0
        @message = message
        @start   = Time.now
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
        pct     = [(@current / @total * 100), 100].min
        bar     = UI.render_bar(pct)
        elapsed = Time.now - @start
        eta     = @current > 0 ? (elapsed / @current * (@total - @current)).round : 0
        pct_str = UI.format_percent(pct)
        count   = "#{@current.to_i}/#{@total.to_i}"
        print "\r  #{@message}: #{bar} #{pct_str} (#{count}) ETA: #{eta}s"
        $stdout.flush
      end
    end

    def spinner(message = "Processing...")
      s = Spinner.new(message)
      s.auto_spin
      result = yield
      s.success("Done")
      result
    rescue StandardError => err
      s.error(err.message)
      raise
    end

    def progress_bar(total:, message: "Progress")
      bar = ProgressBar.new(total: total, message: message)
      yield bar
      bar.finish
    end

    def thinking(message = "thinking...")
      s = Spinner.new(message)
      s.auto_spin
      if block_given?
        result = yield
        s.success("done")
        result
      else
        s
      end
    end
  end
end
