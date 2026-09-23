# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "timeout"

module Master
  module Device
    Capability = Data.define(:name, :state, :detail, :data)

    API_COMMANDS = {
      battery: "termux-battery-status",
      camera: "termux-camera-info",
      microphone: "termux-microphone-record",
      location: "termux-location",
      sensors: "termux-sensor",
      audio: "termux-audio-info",
      wifi: "termux-wifi-connectioninfo",
      volume: "termux-volume",
      torch: "termux-torch",
    }.freeze

    COMMAND_TIMEOUT = 3

    class Error < StandardError; end

    class << self
      def android?
        host = RbConfig::CONFIG["host_os"].to_s.downcase
        host.include?("android") ||
          ENV["TERMUX_VERSION"].to_s != "" ||
          ENV["PREFIX"].to_s.start_with?("/data/data/com.termux/")
      end

      def termux?
        android? && API_COMMANDS.values.any? { |command| executable?(command) }
      end

      def capabilities
        return [Capability.new(:platform, :unavailable, "not Android/Termux", {})] unless android?

        API_COMMANDS.map do |name, command|
          if executable?(command)
            Capability.new(name, :available, "Termux:API command present; permission not probed", { command: command })
          else
            Capability.new(name, :unavailable, "install Termux:API and the termux-api package", { command: command })
          end
        end
      end

      def status_lines
        lines = ["device0: #{android? ? "android" : "non-android"} #{RbConfig::CONFIG["host_cpu"]}"]
        lines << "termux0: #{termux? ? "api available" : "api unavailable"}" if android?
        capabilities.each do |cap|
          lines << "#{cap.name}0: #{cap.state}#{cap.detail ? " — #{cap.detail}" : ""}"
        end
        lines
      end

      def battery
        json("termux-battery-status")
      end

      def camera_info
        json("termux-camera-info")
      end

      def sensors
        json("termux-sensor", "-l")
      end

      def audio_info
        json("termux-audio-info")
      end

      def wifi_info
        json("termux-wifi-connectioninfo")
      end

      def volume
        json("termux-volume")
      end

      def torch(enabled = true)
        require_android_command!("termux-torch")
        run!("termux-torch", enabled ? "on" : "off")
      end

      def location(provider: nil, request: "once")
        args = ["termux-location"]
        args.concat(["-p", provider.to_s]) if provider
        args.concat(["-r", request.to_s])
        json(*args)
      end

      def camera_photo(path, camera: 0)
        require_android_command!("termux-camera-photo")
        run!("termux-camera-photo", "-c", Integer(camera).to_s, File.expand_path(path))
      end

      def microphone_record(path, limit: nil, encoder: nil, bitrate: nil, rate: nil, channels: nil)
        require_android_command!("termux-microphone-record")
        args = ["termux-microphone-record", "-f", File.expand_path(path)]
        args.concat(["-l", Integer(limit).to_s]) if limit
        args.concat(["-e", encoder.to_s]) if encoder
        args.concat(["-b", Integer(bitrate).to_s]) if bitrate
        args.concat(["-r", Integer(rate).to_s]) if rate
        args.concat(["-c", Integer(channels).to_s]) if channels
        run!(*args)
      end

      def microphone_stop
        require_android_command!("termux-microphone-record")
        run!("termux-microphone-record", "-q")
      end

      def sensor_once(name: nil)
        require_android_command!("termux-sensor")
        args = ["termux-sensor"]
        args.concat(["-s", name.to_s]) if name
        args.concat(["-n", "1"])
        json(*args)
      end

      private

      def require_android_command!(command)
        raise Error, "device: not Android/Termux" unless android?
        raise Error, "device: #{command} unavailable — install Termux:API and termux-api" unless executable?(command)
      end

      def executable?(command)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
          path = File.join(dir, command)
          File.file?(path) && File.executable?(path)
        end
      end

      def json(*argv)
        output = run!(*argv)
        JSON.parse(output)
      rescue JSON::ParserError => e
        raise Error, "device: #{argv.first} returned invalid JSON: #{e.message}"
      end

      def run!(*argv)
        raise Error, "device: unavailable outside Android/Termux" unless android?
        raise Error, "device: #{argv.first} unavailable" unless executable?(argv.first)

        stdout = stderr = status = nil
        Timeout.timeout(COMMAND_TIMEOUT) do
          stdout, stderr, status = Open3.capture3(*argv)
        end
        return stdout.strip if status.success?

        detail = [stderr, stdout].map(&:to_s).map(&:strip).reject(&:empty?).first
        raise Error, "device: #{argv.first}: #{detail || "exit #{status.exitstatus}"}"
      rescue Errno::ENOENT
        raise Error, "device: #{argv.first} unavailable"
      rescue Timeout::Error
        raise Error, "device: #{argv.first}: timeout after #{COMMAND_TIMEOUT}s"
      end
    end
  end
end
