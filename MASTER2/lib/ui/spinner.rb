# frozen_string_literal: true

module MASTER
  module UI
    # Subtle spinner (Shibui - understated elegance)
    SPIN_FRAMES = %w[- \\ | /].freeze

    def self.spinner(message = nil, format: :dots)
      require "tty-spinner"
      TTY::Spinner.new(":spinner #{message}", format: format,
        success_mark: "+", error_mark: "-")
    rescue LoadError
      SubtleSpinner.new(message)
    end

    class SubtleSpinner
      ICONS = {
        success: "+",
        failure: "-",
        pending: "..."
      }.freeze

      def initialize(message)
        @message = message
        @running = false
        @thread = nil
        @start_time = nil
      end

      def auto_spin
        @running = true
        @start_time = Time.now
        @thread = Thread.new do
          i = 0
          while @running
            elapsed = (Time.now - @start_time).round
            time_str = elapsed > 5 ? " (#{elapsed}s)" : ""
            print "\r  #{SPIN_FRAMES[i % 4]} #{@message}#{time_str}  "
            i += 1
            sleep 0.15
          end
        end
      end

      def success(msg = nil)
        stop
        suffix = msg ? " #{msg}" : ""
        puts "\r  #{ICONS[:success]} #{@message}#{suffix}"
      end

      def error(msg = nil)
        stop
        suffix = msg ? " #{msg}" : ""
        puts "\r  #{ICONS[:failure]} #{@message}#{suffix}"
      end

      def stop
        @running = false
        @thread&.join(0.2)
        print "\r#{' ' * 70}\r"
      end
    end
  end
end
