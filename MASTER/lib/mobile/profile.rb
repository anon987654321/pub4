# frozen_string_literal: true

require_relative "env"

module Master
  module Mobile
    # Switches MASTER to its phone shape when Termux is detected or
    # MASTER_PROFILE=mobile is set. It sets environment defaults from
    # data/mobile.yml and nothing else; the constitution is unchanged.
    class Profile
      def initialize(config: Mobile.config, env: ENV)
        @config = config
        @env = env
      end

      def active? = Env.mobile?(@env)

      def activate!
        return false unless active?

        @env["MASTER_PROFILE"] = "mobile"
        @config.fetch("env", {}).each { |key, value| @env[key] ||= value.to_s }
        true
      end

      def min_ruby = @config.dig("profile", "min_ruby") || "3.3.0"

      def auto_approve?
        chosen = @env["MASTER_MOBILE_AUTO_APPROVE"].to_s
        chosen.empty? ? @config.dig("packages", "auto_approve") == true : chosen == "1"
      end
    end
  end
end
