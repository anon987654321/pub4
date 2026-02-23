# frozen_string_literal: true

module MASTER
  module UI
    # Pure ASCII spinner -- no gems, single line, dynamic speed + animated color.
    # Color shifts from cool->warm->hot as elapsed time grows (ANSI 256-color).
    # Speed ramps up from 120ms -> 30ms over the first 15s.

    def self.spinner(message = nil, style: :line)
      SubtleSpinner.new(message)
    end

    class SubtleSpinner
      FRAMES = %w[| / - \\].freeze
      RESET  = "\e[0m".freeze

      # 256-color palette bands: cool (cyan/teal) -> warm (green/yellow) -> hot (orange/red)
      PALETTE = [
        "\e[38;5;51m",   # bright cyan       0-2s
        "\e[38;5;45m",   # cyan-blue         0-2s
        "\e[38;5;82m",   # bright green      3-5s
        "\e[38;5;118m",  # lime              3-5s
        "\e[38;5;154m",  # yellow-green      6-9s
        "\e[38;5;226m",  # bright yellow     6-9s
        "\e[38;5;214m",  # orange           10-14s
        "\e[38;5;208m",  # deep orange      10-14s
        "\e[38;5;196m",  # bright red       15s+
        "\e[38;5;197m",  # red-pink         15s+
      ].freeze

      def initialize(message = nil, style: :line)
        @running = false
        @thread  = nil
        @start   = nil
      end

      def auto_spin
        @running = true
        @start   = Time.now
        @thread  = Thread.new do
          i = 0
          while @running
            elapsed = Time.now - @start

            interval = case elapsed
                       when (0...3)  then 0.12
                       when (3...8)  then 0.08
                       when (8...15) then 0.05
                       else               0.03
                       end

            # Two palette entries per time band; cycle between them with frame index
            band  = case elapsed
                    when (0...3)  then 0
                    when (3...6)  then 2
                    when (6...10) then 4
                    when (10...15) then 6
                    else               8
                    end
            color = PALETTE[band + (i % 2)]

            print "\r  #{color}#{FRAMES[i % 4]}#{RESET}"
            $stdout.flush
            i += 1
            sleep interval
          end
        end
      end

      def success(msg = nil)
        stop
        # dmesg style: silent success -- just clear the spinner line
      end

      def error(msg = nil)
        stop
        msg_str = msg && !msg.empty? ? " #{msg}" : ""
        $stderr.puts "!#{msg_str}"
      end

      def update(msg) = nil  # no-op: spinner is frameless

      def stop
        @running = false
        @thread&.join(0.2)
        print "\r     \r"
        $stdout.flush
      end
    end
  end
end

