# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "timeout"
require "yaml"

module Master
  module Plugins
    class AirSuperiority < Master::Plugin::Base
      WIFI_COMMAND_TIMEOUT_S = 12
      BLUETOOTH_SCAN_S = 6
      KNOWN_FILE = File.expand_path("~/.master/plugins/air_superiority/known.yml")
      BLOCKED_OPERATIONS = %w[
        deauth
        disassociate
        packet_injection
        credential_capture
        man_in_the_middle
        exploit
      ].freeze

      Threat = Data.define(:type, :severity, :details, :data)


      def initialize(manifest:)
        super
      end

      def call(action:, **args)
        law_admission!
        case action.to_s
        when "status" then status
        when "scan" then scan(**args)
        when "remember" then remember(**args)
        else
          raise PolicyError, "air_superiority: unknown action #{action}"
        end
      end

      private

      def status
        {
          plugin: manifest.id,
          platform: platform,
          wifi: wifi_available?,
          bluetooth: bluetooth_available?,
          known_file: KNOWN_FILE,
          mode: "defensive_observation_only"
        }
      end

      def scan(**)
        networks = scan_wifi
        devices = scan_bluetooth
        known = load_known
        wifi_threats = analyze_wifi(networks, known.fetch("known_networks", []))
        bluetooth_threats = analyze_bluetooth(devices, known.fetch("known_devices", []))

        {
          plugin: manifest.id,
          platform: platform,
          wifi: networks,
          bluetooth: devices,
          threats: (wifi_threats + bluetooth_threats).map(&:to_h),
          counts: {
            wifi: networks.length,
            bluetooth: devices.length,
            threats: wifi_threats.length + bluetooth_threats.length
          }
        }
      end

      def remember(kind:, **data)
        return remember_network(**data) if kind.to_s == "network"
        return remember_device(**data) if kind.to_s == "device"

        raise PolicyError, "air_superiority: remember kind must be network or device"
      end

      def remember_network(ssid:, bssid:, **)
        write_known("known_networks", "ssid" => ssid.to_s, "bssid" => bssid.to_s)
      end

      def remember_device(address:, name: nil, **)
        write_known(
          "known_devices",
          "address" => address.to_s,
          "name" => name.to_s
        )
      end

      def write_known(key, row)
        require_policy!("write_access", expected: "local_known_list_only")
        data = load_known
        data[key] ||= []
        data[key].reject! { |existing| existing["bssid"].to_s.downcase == row["bssid"].to_s.downcase } if key == "known_networks"
        data[key].reject! { |existing| existing["address"].to_s.downcase == row["address"].to_s.downcase } if key == "known_devices"
        data[key] << row
        FileUtils.mkdir_p(File.dirname(KNOWN_FILE), mode: 0o700)
        File.write(KNOWN_FILE, YAML.dump(data), mode: "w", perm: 0o600)
        row
      end

      def load_known
        return { "known_networks" => [], "known_devices" => [] } unless File.file?(KNOWN_FILE)

        YAML.safe_load_file(KNOWN_FILE) || {}
      rescue Psych::Exception => e
        raise Error, "air_superiority: invalid known list: #{e.message}"
      end

      def platform
        host_os = RbConfig::CONFIG["host_os"].to_s.downcase
        return "openbsd" if host_os.include?("openbsd")
        return "macos" if host_os.include?("darwin")
        return "linux" if host_os.include?("linux")

        "unknown"
      end

      def wifi_available?
        case platform
        when "macos" then File.executable?(airport_path)
        when "linux" then executable?("nmcli")
        when "openbsd" then executable?("ifconfig")
        else false
        end
      end

      def bluetooth_available?
        case platform
        when "macos" then executable?("system_profiler")
        when "linux" then executable?("bluetoothctl")
        else false
        end
      end

      def scan_wifi
        case platform
        when "macos" then scan_wifi_macos
        when "linux" then scan_wifi_linux
        when "openbsd" then scan_wifi_openbsd
        else []
        end
      end

      def scan_wifi_macos
        return [] unless File.executable?(airport_path)
        output = run_command(airport_path, "-s", timeout: WIFI_COMMAND_TIMEOUT_S)
        output.lines.filter_map do |line|
          next if line.strip.empty? || line.match?(/SSID\s+BSSID\s+RSSI/i)

          match = line.match(/^\s*(.*?)\s+([0-9a-f:]{17})\s+(-\d+)\s+(\S+)/i)
          next unless match

          security = line.split(/\s{2,}/).last.to_s.strip
          {
            ssid: match[1].strip,
            bssid: match[2].downcase,
            rssi: match[3].to_i,
            channel: match[4].to_s,
            security: security.empty? ? "Unknown" : security,
            signal: rssi_to_percentage(match[3].to_i)
          }
        end
      rescue Error
        []
      end

      def scan_wifi_linux
        return [] unless executable?("nmcli")
        output = run_command(
          "nmcli", "-t", "-f", "SSID,BSSID,SIGNAL,SECURITY,CHAN", "device", "wifi", "list",
          timeout: WIFI_COMMAND_TIMEOUT_S
        )
        output.lines.filter_map do |line|
          fields = split_nmcli(line.chomp)
          next unless fields.length >= 5

          signal = fields[2].to_i
          {
            ssid: fields[0].empty? ? "<Hidden>" : fields[0],
            bssid: fields[1].downcase,
            signal: signal,
            rssi: percentage_to_rssi(signal),
            security: fields[3].empty? ? "Open" : fields[3],
            channel: fields[4]
          }
        end
      rescue Error
        []
      end

      def scan_wifi_openbsd
        interface = ENV.fetch("AIR_SUPERIORITY_INTERFACE", "").strip
        interface = first_openbsd_wifi_interface if interface.empty?
        return [] if interface.empty?

        output = run_command("ifconfig", interface, "scan", timeout: WIFI_COMMAND_TIMEOUT_S)
        parse_openbsd_scan(output)
      rescue Error
        []
      end

      def parse_openbsd_scan(output)
        output.lines.filter_map do |line|
          ssid = line[/\bnwid\s+["']?(.+?)["']?(?=\s+(?:nwidlen|chan|bssid|rssi)\b)/i, 1]
          bssid = line[/\bbssid\s+([0-9a-f:]{17})/i, 1]
          rssi = line[/\brssi\s+(-\d+)/i, 1]
          channel = line[/\bchan\s+(\d+)/i, 1]
          next unless ssid && bssid

          value = rssi ? rssi.to_i : -100
          {
            ssid: ssid.strip,
            bssid: bssid.downcase,
            rssi: value,
            signal: rssi_to_percentage(value),
            channel: channel.to_s,
            security: "Unknown"
          }
        end
      end

      def scan_bluetooth
        case platform
        when "macos" then scan_bluetooth_macos
        when "linux" then scan_bluetooth_linux
        else []
        end
      end

      def scan_bluetooth_macos
        output = run_command("system_profiler", "SPBluetoothDataType", "-json", timeout: WIFI_COMMAND_TIMEOUT_S)
        data = JSON.parse(output)
        devices = []
        root = data.dig("SPBluetoothDataType", 0) || {}
        root.fetch("device_connected", {}).each do |name, details|
          devices << {
            name: name,
            address: details.fetch("device_address", "Unknown"),
            connected: details.fetch("device_isconnected", "") == "attrib_Yes",
            source: "connected_devices"
          }
        end
        devices
      rescue JSON::ParserError => e
        raise Error, "air_superiority: invalid Bluetooth JSON: #{e.message}"
      rescue Error
        []
      end

      def scan_bluetooth_linux
        return [] unless executable?("bluetoothctl")

        pid = Process.spawn("bluetoothctl", "scan", "on", out: File::NULL, err: File::NULL, pgroup: true)
        begin
          sleep BLUETOOTH_SCAN_S
          output = run_command("bluetoothctl", "devices", timeout: 5)
          parse_linux_bt(output)
        ensure
          Process.kill("TERM", -pid)
          Process.wait(pid)
        rescue Errno::ESRCH, Errno::ECHILD
        ensure
          system("bluetoothctl", "scan", "off", out: File::NULL, err: File::NULL) if executable?("bluetoothctl")
        end
      rescue Error
        []
      end

      def parse_linux_bt(output)
        output.lines.filter_map do |line|
          match = line.match(/^Device\s+([0-9A-F:]{17})\s*(.*)$/i)
          next unless match

          {
            name: match[2].strip,
            address: match[1].upcase,
            connected: false,
            source: "bluetoothctl"
          }
        end
      end

      def split_nmcli(line)
        fields = []
        current = +""
        escaped = false

        line.each_char do |char|
          if escaped
            current << char
            escaped = false
          elsif char == "\\"
            escaped = true
          elsif char == ":"
            fields << current
            current = +""
          else
            current << char
          end
        end

        current << "\\" if escaped
        fields << current
      end

      def first_openbsd_wifi_interface
        output = run_command("ifconfig", "-l", timeout: 3)
        output.split.grep(/\A(?:iwm|iwx|athn|ral|run)\d+\z/).first.to_s
      rescue Error
        ""
      end

      def airport_path
        "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
      end

      def executable?(command)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
          path = File.join(dir, command)
          File.file?(path) && File.executable?(path)
        end
      end

      def run_command(*argv, timeout:)
        stdout = stderr = status = nil
        Timeout.timeout(timeout) do
          stdout, stderr, status = Open3.capture3(*argv)
        end
        return stdout if status.success?

        detail = [stderr, stdout].map(&:to_s).map(&:strip).reject(&:empty?).first
        raise Error, "air_superiority: #{argv.first}: #{detail || "exit #{status.exitstatus}"}"
      rescue Errno::ENOENT
        raise Error, "air_superiority: #{argv.first} unavailable"
      rescue Timeout::Error
        raise Error, "air_superiority: #{argv.first}: timeout after #{timeout}s"
      end

      def analyze_wifi(networks, known)
        networks.filter_map do |network|
          expected = known.find { |item| item["ssid"].to_s == network[:ssid].to_s }
          if expected && expected["bssid"].to_s.downcase != network[:bssid].to_s.downcase
            Threat.new(
              type: "Unexpected Access Point",
              severity: "high",
              details: "Known SSID #{network[:ssid].inspect} appeared with an unrecognized BSSID. This can be benign (mesh/roaming) or an impersonation attempt; verify before trusting it.",
              data: network.merge(expected_bssid: expected["bssid"], confidence: "medium")
            )
          elsif network[:security].to_s.downcase.include?("open") || network[:security].to_s.empty?
            Threat.new(
              type: "Open Network",
              severity: "medium",
              details: "Network #{network[:ssid].inspect} advertises no encryption.",
              data: network
            )
          end
        end
      end

      def analyze_bluetooth(devices, known)
        devices.filter_map do |device|
          next if known.any? { |item| item["address"].to_s.casecmp?(device[:address].to_s) }

          Threat.new(
            type: "Unknown Bluetooth Device",
            severity: "low",
            details: "Bluetooth device #{device[:name].inspect} (#{device[:address]}) is not in the local known-device list.",
            data: device
          )
        end
      end

      def rssi_to_percentage(rssi)
        quality = 2 * (rssi + 100)
        quality.clamp(0, 100)
      end

      def percentage_to_rssi(percentage)
        -100 + (percentage.to_i / 2)
      end
    end
  end
end
