# frozen_string_literal: true

module Master
  module Ground
    # Owns subscription authentication by delegating to the provider's official
    # CLI. MASTER never handles passwords, cookies, OAuth codes or session files.
    module SubscriptionAuth
      CONFIG_PATH = File.join(Master::ROOT, "data", "patterns.yml").freeze
      LOGIN_TIMEOUT = 300

      module_function

      def profiles
        raw = (Master.load_yaml(CONFIG_PATH) || {})["auth_profiles"]
        Array(raw.is_a?(Hash) ? raw["lanes"] : nil).select do |lane|
          lane.is_a?(Hash) && lane["auth"] == "subscription"
        end
      rescue StandardError => e
        Swallow.log(e, context: "subscription_auth.profiles")
        []
      end

      def status
        profiles.map do |lane|
          available = executable?(lane["command"])
          logged_in = available && command_ok?(lane, lane["status_args"])
          {
            id: lane["id"], name: lane["name"] || lane["id"], command: lane["command"],
            installed: available, authenticated: logged_in, authentication_known: !Array(lane["status_args"]).empty?
          }
        end
      end

      def login(name)
        lane = find(name)
        return "auth: unknown subscription #{name}" unless lane
        return "auth: #{lane["command"]} not installed" unless executable?(lane["command"])

        args = Array(lane["login_args"])
        _output, process = Master::Io::Exec.capture2e(lane["command"], *args, timeout: LOGIN_TIMEOUT)
        if process.success?
          "auth: #{lane["name"] || name} connected; compute pool refreshes on next route"
        else
          "auth: #{lane["name"] || name} login failed"
        end
      end

      def find(name)
        key = name.to_s.downcase
        profiles.find { |lane| [lane["id"], lane["name"], lane["command"]].compact.map { |v| v.to_s.downcase }.include?(key) }
      end

      def executable?(command)
        cmd = command.to_s
        return false if cmd.empty?
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
          path = File.join(dir, cmd)
          File.file?(path) && File.executable?(path)
        end
      end

      def command_ok?(lane, args)
        return false if Array(args).empty?
        _output, status = Master::Io::Exec.capture2e(lane["command"], *Array(args), timeout: 15)
        status.success?
      rescue StandardError => e
        Swallow.log(e, context: "subscription_auth.status")
        false
      end
    end
  end
end
