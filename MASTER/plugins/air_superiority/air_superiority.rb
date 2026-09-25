# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "timeout"
require "yaml"
require_relative "models"
require_relative "analyzer"

module Master
  module Plugins
    class AirSuperiority < Master::Plugin::Base
      Error = Master::Plugin::Error
      PolicyError = Master::Plugin::PolicyError
      KNOWN_FILE = File.expand_path("~/.master/plugins/air_superiority/known.yml")
      COMMAND_TIMEOUT_S = 12

      def call(action:, **args)
        law_admission!
        case action.to_s
        when "status" then status
        when "scan" then scan
        when "remember" then remember(**args)
        else
          raise PolicyError, "air_superiority: unknown action #{action}"
        end
      end

      private

      def status
        {
          plugin: manifest.id,
          runtime:,
          wifi: wifi_backend,
          bluetooth: bluetooth_backend,
          known_file: KNOWN_FILE,
          mode: "defensive_observation_only",
        }
      end

      def scan
        networks, wifi_error = scan_safely { scan_wifi }
        devices, bluetooth_error = scan_safely { scan_bluetooth }
        known = load_known
        observed_at = Time.now.utc
        analyzer = AirSuperioritySupport::Analyzer.new(observed_at:)
        wifi_findings = analyzer.wifi(networks, known.fetch("known_networks", []))
        bluetooth_findings = analyzer.bluetooth(devices, known.fetch("known_devices", []))
        errors = [wifi_error, bluetooth_error].compact
        result = AirSuperioritySupport::ScanResult.new(
          wifi: networks,
          bluetooth: devices,
          errors:,
          complete: errors.empty?,
          observed_at:,
        )

        {
          plugin: manifest.id,
          runtime:,
          wifi: result.wifi,
          bluetooth: result.bluetooth,
          errors: result.errors,
          complete: result.complete,
          observed_at: result.observed_at.iso8601,
          threats: (wifi_findings + bluetooth_findings).map(&:to_h),
          counts: {
            wifi: result.wifi.length,
            bluetooth: result.bluetooth.length,
            threats: wifi_findings.length + bluetooth_findings.length,
          },
        }
      end

      def remember(kind:, **data)
        return remember_network(**data) if kind.to_s == "network"
        return remember_device(**data) if kind.to_s == "device"

        raise PolicyError, "air_superiority: kind must be network or device"
      end

      def remember_network(ssid:, bssid:, **)
        write_known("known_networks", "ssid" => ssid.to_s, "bssid" => bssid.to_s)
      end

      def remember_device(address:, name: nil, **)
        write_known("known_devices", "address" => address.to_s, "name" => name.to_s)
      end

      def write_known(key, row)
        require_policy!("write_access", expected: "local_known_list_only")
        state = load_known
        state[key] ||= []
        field = key == "known_networks" ? "bssid" : "address"
        state[key].reject! { |item| item[field].to_s.casecmp?(row[field].to_s) }
        state[key] << row
        FileUtils.mkdir_p(File.dirname(KNOWN_FILE), mode: 0o700)
        File.write(KNOWN_FILE, YAML.dump(state), mode: "w", perm: 0o600)
        row
      end

      def load_known
        return { "known_networks" => [], "known_devices" => [] } unless File.file?(KNOWN_FILE)

        YAML.safe_load_file(KNOWN_FILE) || {}
      rescue Psych::Exception => e
        raise Error, "air_superiority: invalid known list: #{e.message}"
      end

      def runtime
        return "android_termux" if termux?
        host_os = RbConfig::CONFIG["host_os"].to_s.downcase
        return "openbsd" if host_os.include?("openbsd")
        return "macos" if host_os.include?("darwin")
        return "linux" if host_os.include?("linux")

        "unknown"
      end

      def termux?
        RUBY_PLATFORM.include?("android") || ENV["PREFIX"].to_s.include?("/com.termux/")
      end

      def wifi_backend
        case runtime
        when "android_termux" then command_available?("termux-wifi-scaninfo") ? "termux-api" : "unavailable"
        when "macos" then File.executable?("/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport") ? "airport" : "unavailable"
        when "linux" then command_available?("nmcli") ? "nmcli" : "unavailable"
        when "openbsd" then command_available?("ifconfig") ? "ifconfig" : "unavailable"
        else "unavailable"
        end
      end

      def bluetooth_backend
        case runtime
        when "android_termux" then command_available?("termux-bluetooth-scan") ? "termux-api-optional" : "unavailable"
        when "macos" then command_available?("system_profiler") ? "system_profiler" : "unavailable"
        when "linux" then command_available?("bluetoothctl") ? "bluetoothctl" : "unavailable"
        else "unavailable"
        end
      end

      def scan_wifi
        backend = wifi_backend
        case backend
        when "termux-api" then parse_android_wifi(run("termux-wifi-scaninfo"))
        when "airport" then parse_airport(run("/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport", "-s"))
        when "nmcli" then parse_nmcli(run("nmcli", "-t", "-f", "SSID,BSSID,SIGNAL,CHAN,SECURITY", "device", "wifi", "list"))
        when "ifconfig" then [{ "interface" => run("ifconfig", "-l").to_s.strip }]
        else
          raise Error, "air_superiority: Wi-Fi scan unavailable on #{runtime}"
        end
      end

      def scan_bluetooth
        backend = bluetooth_backend
        case backend
        when "termux-api-optional" then parse_optional_termux_bluetooth(run("termux-bluetooth-scan", "info"))
        when "system_profiler" then parse_system_profiler(run("system_profiler", "SPBluetoothDataType", "-json"))
        when "bluetoothctl" then parse_bluetoothctl(run("bluetoothctl", "devices"))
        else
          raise Error, "air_superiority: Bluetooth scan unavailable on #{runtime}"
        end
      end

      def parse_android_wifi(text)
        Array(JSON.parse(text)).map { |row| normalize_keys(row) }
      rescue JSON::ParserError => e
        raise Error, "air_superiority: Android Wi-Fi JSON invalid: #{e.message}"
      end

      def parse_json_array(text)
        parsed = JSON.parse(text)
        Array(parsed).map { |row| normalize_keys(row) }
      rescue JSON::ParserError => e
        raise Error, "air_superiority: Bluetooth JSON invalid: #{e.message}"
      end

      def parse_nmcli(text)
        text.lines.filter_map do |line|
          ssid, bssid, signal, chan, security = line.chomp.split(":", 5)
          next if bssid.to_s.empty?

          { "ssid" => ssid.to_s, "bssid" => bssid.to_s, "signal" => signal.to_s, "channel" => chan.to_s, "security" => security.to_s }
        end
      end

      def parse_airport(text)
        text.lines.drop(1).filter_map do |line|
          fields = line.split(/\s{2,}/, 7)
          next if fields.length < 2

          { "ssid" => fields[0].strip, "bssid" => fields[1].strip, "signal" => fields[2].to_s.strip }
        end
      end

      def parse_system_profiler(text)
        JSON.parse(text).fetch("SPBluetoothDataType", []).flat_map do |section|
          section.fetch("device_connected", []).map { |row| normalize_keys(row) }
        end
      rescue JSON::ParserError => e
        raise Error, "air_superiority: Bluetooth profile JSON invalid: #{e.message}"
      end

      def parse_bluetoothctl(text)
        text.lines.filter_map do |line|
          match = line.match(/\ADevice\s+([0-9A-Fa-f:]{17})\s+(.+)\z/)
          next unless match

          { "address" => match[1], "name" => match[2].strip }
        end
      end

      def normalize_keys(row)
        row.transform_keys { |key| key.to_s.downcase }
      end

      def command_available?(command)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
          File.executable?(File.join(directory, command))
        end
      end

      def scan_safely
        [yield, nil]
      rescue Error => e
        [[], e.message]
      end

      def parse_optional_termux_bluetooth(text)
        parse_json_array(text)
      rescue Error, JSON::ParserError
        []
      end

      def run(*argv)
        _out, status, body = capture(argv)
        raise Error, "air_superiority: command failed: #{argv.first}" unless status.success?

        body
      end

      def capture(argv)
        stdout = +""
        status = nil
        Timeout.timeout(COMMAND_TIMEOUT_S) do
          Open3.popen3(*argv) do |_stdin, out, err, wait|
            _stdin.close
            stdout = out.read
            stdout << err.read
            status = wait.value
          end
        end
        [argv, status, stdout]
      rescue Timeout::Error
        raise Error, "air_superiority: command timed out: #{argv.first}"
      end
    end
  end
end
