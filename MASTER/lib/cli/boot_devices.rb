# frozen_string_literal: true

module Master
  module CLI
    # The radios, as the startup lines an OpenBSD kernel prints for them: net0 for the wifi, bth0 for the
    # bluetooth controller. Read with two quick system commands on macOS; any other host, or a command that
    # fails, prints nothing. The network name is never printed: a boot line lives in scrollback.
    module BootDevices
      WIFI = "en0"

      module_function

      def lines
        return [] unless RUBY_PLATFORM.include?("darwin")

        [net_line(power: run("networksetup", "-getairportpower", WIFI), link: run("ifconfig", WIFI)),
         bth_line(run("system_profiler", "SPBluetoothDataType", "-detailLevel", "mini"))].compact
      end

      def net_line(power:, link:)
        return if power.to_s.strip.empty? && link.to_s.strip.empty?

        state = power.to_s.match?(/\bOn\b/) ? "on" : "off"
        up = link.to_s.match?(/status:\s*active/) ? "link up" : "no link"
        "net0 at mainbus0: wifi #{WIFI}, power #{state}, #{up}"
      end

      def bth_line(profile)
        return if profile.to_s.strip.empty?

        state = profile.match(/State:\s*(On|Off)/)&.captures&.first&.downcase
        return unless state

        "bth0 at mainbus0: #{state}, #{connected(profile)} connected"
      end

      # The names listed under "Connected:", up to "Not Connected:" or the end of the block.
      def connected(profile)
        block = profile[/^\s*Connected:\s*\n(.*?)(?=^\s*Not Connected:|\z)/m, 1].to_s
        rows = block.lines.reject { |line| line.strip.empty? }
        indent = rows.map { |line| line[/\A\s*/].size }.min
        rows.count { |line| line[/\A\s*/].size == indent && line.rstrip.end_with?(":") }
      end

      def run(*argv)
        Master::Io::Exec.capture2e(*argv, timeout: 1).first.to_s
      rescue StandardError
        ""
      end
    end
  end
end
