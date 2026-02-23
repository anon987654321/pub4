# frozen_string_literal: true

module MASTER
  module UI
    # Canonical spinner — one implementation, three style variants.
    # style: :dots (default) | :line | :braille
    # Replaces SubtleSpinner, Progress::Spinner, and the Components inline stub.
    SPIN_FRAMES = {
      dots:    %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze,
      line:    %w[— \\ | /].freeze,
      braille: %w[⣾ ⣽ ⣻ ⢿ ⡿ ⣟ ⣯ ⣷].freeze,
    }.freeze

    def self.spinner(message = nil, style: :dots)
      require "tty-spinner"
      TTY::Spinner.new(
        "  :spinner #{message}",
        format:       style == :line ? :classic : :dots,
        success_mark: MASTER::UI::ICONS[:success],
        error_mark:   MASTER::UI::ICONS[:failure],
      )
    rescue LoadError
      SubtleSpinner.new(message, style: style)
    end

    class SubtleSpinner
      CLEAR_WIDTH = 80

      def initialize(message, style: :dots)
        @message = message.to_s
        @frames  = SPIN_FRAMES[style] || SPIN_FRAMES[:dots]
        @running = false
        @thread  = nil
        @start   = nil
      end

      def auto_spin
        @running = true
        @start   = Time.now
        @thread  = Thread.new do
          frame_idx = 0
          while @running
            elapsed  = (Time.now - @start).round
            time_str = elapsed > 5 ? " (#{elapsed}s)" : ""
            print "\r  #{@frames[frame_idx % @frames.size]} #{@message}#{time_str}  "
            $stdout.flush
            frame_idx += 1
            sleep 0.1
          end
        end
      end

      def success(msg = nil)
        stop
        suffix = msg ? " — #{msg}" : ""
        puts MASTER::UI.pastel.white("  #{MASTER::UI::ICONS[:success]} #{@message}#{suffix}")
        puts
      end

      def error(msg = nil)
        stop
        suffix = msg ? " — #{msg}" : ""
        puts MASTER::UI.pastel.red("  #{MASTER::UI::ICONS[:failure]} #{@message}#{suffix}")
        puts
      end

      def update(msg)
        @message = msg.to_s
      end

      def stop
        @running = false
        @thread&.join(0.2)
        print "\r#{' ' * CLEAR_WIDTH}\r"
        $stdout.flush
      end
    end
  end
end
