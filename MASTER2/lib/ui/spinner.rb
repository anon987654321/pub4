# frozen_string_literal: true

require "etc"

module MASTER
  module UI
    # Pure ASCII spinner -- speed and color reflect problem depth + system load.
    #
    # Semantics (intentionally opposite to the old behaviour):
    #   Light/fast task   -> fast spin, bright teal      (0.12s interval)
    #   Deep/heavy task   -> slow spin, near-black       (0.80s interval)
    #   High CPU/mem load -> additional slowdown + darkening
    #
    # Depth score (0.0–1.0) is a weighted blend of:
    #   40% elapsed time   (saturates at 30 s)
    #   40% CPU load avg   (saturates at 2× CPU count)
    #   20% memory pressure (Linux /proc/meminfo; 0 elsewhere)

    def self.spinner(message = nil, style: :line)
      SubtleSpinner.new(message)
    end

    class SubtleSpinner
      FRAMES = %w[| / - \\].freeze
      RESET  = "\e[0m".freeze

      # Palette: bright → dim → dark → near-black (index 0 = freshest)
      PALETTE = [
        "\e[38;5;51m",   # bright cyan        depth 0.0–0.1
        "\e[38;5;37m",   # medium teal        depth 0.1–0.2
        "\e[38;5;30m",   # dark teal          depth 0.2–0.3
        "\e[38;5;23m",   # very dark teal     depth 0.3–0.4
        "\e[38;5;22m",   # dark green         depth 0.4–0.5
        "\e[38;5;58m",   # olive              depth 0.5–0.6
        "\e[38;5;94m",   # dark brown/orange  depth 0.6–0.7
        "\e[38;5;88m",   # dark red           depth 0.7–0.8
        "\e[38;5;52m",   # maroon             depth 0.8–0.9
        "\e[38;5;236m",  # near-black gray    depth 0.9–1.0
      ].freeze

      # Interval range: fast (light) → slow (heavy), in seconds
      MIN_INTERVAL = 0.12
      MAX_INTERVAL = 0.80

      # Sample system load every N frames to avoid overhead
      LOAD_SAMPLE_EVERY = 8

      def initialize(message = nil, style: :line)
        @running = false
        @thread  = nil
        @start   = nil
      end

      def auto_spin
        @running = true
        @start   = Time.now
        @thread  = Thread.new do
          i           = 0
          cached_load = 0.0
          cached_mem  = 0.0

          while @running
            elapsed = Time.now - @start

            # Refresh system metrics periodically (not every frame)
            if (i % LOAD_SAMPLE_EVERY).zero?
              cached_load = cpu_load_factor
              cached_mem  = memory_pressure
            end

            score    = depth_score(elapsed, cached_load, cached_mem)
            interval = MIN_INTERVAL + (MAX_INTERVAL - MIN_INTERVAL) * score
            color    = PALETTE[(score * (PALETTE.size - 1)).round]

            $stderr.print "\r  #{color}#{FRAMES[i % 4]}#{RESET}"
            $stderr.flush
            i += 1
            sleep interval
          end
        end
      end

      def success(msg = nil)
        stop
      end

      def error(msg = nil)
        stop
        msg_str = msg && !msg.empty? ? " #{msg}" : ""
        $stderr.puts "!#{msg_str}"
      end

      def update(msg) = nil

      def stop
        @running = false
        @thread&.join(0.3)
        $stderr.print "\r     \r"
        $stderr.flush
      end

      private

      # Blended depth score in 0.0–1.0
      def depth_score(elapsed, load_factor, mem_factor)
        time_factor = [elapsed / 30.0, 1.0].min
        ((time_factor * 0.4) + (load_factor * 0.4) + (mem_factor * 0.2)).clamp(0.0, 1.0)
      end

      # Normalised CPU load: 0.0 = idle, 1.0 = saturated (2× all cores busy)
      def cpu_load_factor
        load1 = Process.loadavg[0]
        cpus  = [Etc.nprocessors, 1].max
        [load1 / (cpus * 2.0), 1.0].min
      rescue StandardError
        0.0
      end

      # Memory pressure from /proc/meminfo (Linux); 0.0 elsewhere
      def memory_pressure
        return 0.0 unless File.exist?("/proc/meminfo")

        lines     = File.read("/proc/meminfo").lines
        total     = lines.find { |l| l.start_with?("MemTotal:") }&.split&.[](1).to_i
        available = lines.find { |l| l.start_with?("MemAvailable:") }&.split&.[](1).to_i
        return 0.0 if total.nil? || total.zero?

        ((total - available).to_f / total).clamp(0.0, 1.0)
      rescue StandardError
        0.0
      end
    end
  end
end
