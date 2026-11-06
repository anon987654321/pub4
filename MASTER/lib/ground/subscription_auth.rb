# frozen_string_literal: true

module Master
  module Ground
    # Owns subscription authentication by delegating to the provider's official
    # CLI. MASTER never handles passwords, cookies, OAuth codes or session files.
    module SubscriptionAuth
      LOGIN_TIMEOUT = 300
      STATUS_TIMEOUT = 15
      POLL_INTERVAL_S = 0.05
      TERM_GRACE_S = 1.0

      class LoginTimeout < StandardError; end

      module_function

      def profiles
        raw = Master.patterns_config["auth_profiles"]
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
          known = !Array(lane["status_args"]).empty?
          logged_in = available && known && command_ok?(lane, lane["status_args"])
          {
            id: lane["id"], name: lane["name"] || lane["id"], command: lane["command"],
            installed: available, authenticated: logged_in, authentication_known: known
          }
        end
      end

      # Run the provider-owned login flow in the foreground. OAuth and device-code
      # CLIs need the real terminal: capture2e steals their prompt and hides the code.
      def login(name, device_auth: nil)
        lane = find(name)
        return "auth: unknown subscription #{name}" unless lane
        binary = cli_binary(lane["command"])
        return "auth: #{lane["command"]} not installed" unless binary

        device_args = Array(lane["device_login_args"])
        if device_auth == true && device_args.empty?
          return "auth: #{lane["name"] || name} has no device-code login; use its browser login"
        end

        args = login_arguments(lane, device_auth:)
        process = run_interactive(binary, *args, timeout: LOGIN_TIMEOUT)
        if process.success?
          refresh_compute_pool
          "#{connected_message(lane, name)}\n#{pool_message(lane)}"
        else
          "auth: #{lane["name"] || name} login failed (exit #{process.exitstatus || process.termsig})"
        end
      rescue LoginTimeout => e
        "auth: #{lane["name"] || name} login timed out - #{e.message}"
      rescue StandardError => e
        Swallow.log(e, context: "subscription_auth.login", provider: name)
        "auth: #{lane["name"] || name} login failed - #{e.message}"
      end

      # Mobile and headless sessions use device-code authentication where the
      # provider offers it. Desktop sessions keep the provider's normal browser flow.
      def login_arguments(lane, device_auth: nil)
        use_device = device_auth == true || (device_auth.nil? && device_auth_preferred?)
        device_args = Array(lane["device_login_args"])
        use_device && !device_args.empty? ? device_args : Array(lane["login_args"])
      end

      def device_auth_preferred?
        return true if ENV["MASTER_PROFILE"].to_s == "mobile"
        return true if !ENV["TERMUX_VERSION"].to_s.empty?
        return true if ENV["PREFIX"].to_s.include?("com.termux")

        !$stdin.tty? || !$stdout.tty?
      rescue IOError
        true
      end

      # The child inherits stdin/stdout/stderr. Do not capture it: browser sign-in
      # prompts and one-time device codes must be visible and readable in the shell.
      def run_interactive(command, *args, timeout: LOGIN_TIMEOUT)
        pid = Process.spawn(
          Master::Io::ProcessSpawn.environment,
          command, *args,
          **Master::Io::ProcessSpawn.options(in: $stdin, out: $stdout, err: $stderr, pgroup: true),
        )
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout.to_f
        reaped = false

        loop do
          result = Process.waitpid2(pid, Process::WNOHANG)
          if result
            reaped = true
            return result.last
          end

          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if remaining <= 0
            stop_interactive(pid)
            reaped = true
            raise LoginTimeout, "provider CLI exceeded #{timeout}s"
          end
          sleep([remaining, POLL_INTERVAL_S].min)
        end
      ensure
        stop_interactive(pid) if pid && !reaped
      end

      def stop_interactive(pid)
        Process.kill("TERM", -pid)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TERM_GRACE_S
        reaped = false
        loop do
          reaped ||= !!Process.waitpid(pid, Process::WNOHANG)
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep(POLL_INTERVAL_S)
        end
        Process.kill("KILL", -pid)
        Process.waitpid(pid) unless reaped
        true
      rescue Errno::ECHILD
        true
      rescue Errno::ESRCH
        begin
          Process.waitpid(pid) unless reaped
        rescue Errno::ECHILD
          nil
        end
        true
      end

      def refresh_compute_pool
        router = Master::CLI::Routing::ModelRouter.new(config: Master::Ground::Config.new(Master::ROOT))
        router.compute_pool.refresh!
      rescue StandardError => e
        Swallow.log(e, context: "subscription_auth.refresh")
        nil
      end

      def connected_message(lane, name)
        "auth: #{lane["name"] || name} connected"
      end

      def pool_message(lane)
        router = Master::CLI::Routing::ModelRouter.new(config: Master::Ground::Config.new(Master::ROOT))
        ids = router.pool(wait: false)
        prefix = "#{lane["command"]}:"
        discovered = ids.grep(/\A#{Regexp.escape(prefix)}/)
        if discovered.empty?
          "compute: #{lane["name"] || lane["command"]} subscription lane pending discovery"
        else
          "compute: #{discovered.join(", ")} available"
        end
      rescue StandardError => e
        Swallow.log(e, context: "subscription_auth.pool_message")
        "compute: subscription lane refresh failed"
      end

      def find(name)
        key = name.to_s.downcase
        profiles.find { |lane| [lane["id"], lane["name"], lane["command"]].compact.map { |v| v.to_s.downcase }.include?(key) }
      end

      def cli_binary(command) = Master::Io::Exec.cli_binary(command.to_s)

      def executable?(command) = !cli_binary(command).nil?

      def command_ok?(lane, args)
        return false if Array(args).empty?
        binary = cli_binary(lane["command"])
        return false unless binary

        output, status = Master::Io::Exec.capture2e(binary, *Array(args), timeout: STATUS_TIMEOUT)
        return false unless status.success?

        expected = lane["status_match"].to_s
        return false if !expected.empty? && !output.include?(expected)

        refused = lane["status_refuse"].to_s
        return false if !refused.empty? && output.downcase.include?(refused.downcase)

        true
      rescue StandardError => e
        Swallow.log(e, context: "subscription_auth.status")
        false
      end
    end
  end
end
