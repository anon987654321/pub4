# frozen_string_literal: true

module Master
  module Ground
    # OAuth-before-key ordering (OpenCrabs/OpenClaw): prefer subscription/CLI lanes
    # before burning API keys on the same turn's fallback chain.
    module AuthProfileLane
      CONFIG_PATH = File.join(Master::ROOT, "data", "auth_profiles.yml").freeze

      module_function

      def load_lanes
        raw = Master.load_yaml(CONFIG_PATH)
        return [] unless raw.is_a?(Hash)

        Array(raw["lanes"]).select { |row| row.is_a?(Hash) && row["enabled"] != false }
          .sort_by { |row| row.fetch("priority", 99).to_i }
      rescue StandardError => e
        Swallow.log(e, context: "auth_profile_lane.load")
        []
      end

      def lane_available?(lane)
        case lane.fetch("kind", "api_key").to_s
        when "cli"
          cmd = lane.fetch("command", lane["binary"]).to_s
          return false if cmd.empty?
          return false if cmd == "claude" && ENV["MASTER_NO_CLAUDE_CLI"] == "1"

          ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
            exe = File.join(dir, cmd)
            File.file?(exe) && File.executable?(exe)
          end
        when "oauth"
          token_env = Array(lane["env_token"] || lane["env"]).first.to_s
          return false if token_env.empty?

          Master.api_key_present?(token_env) || ENV[token_env].to_s.length >= 8
        when "api_key"
          envs = Array(lane["env"] || lane["env_token"])
          envs.any? { |var| Master.api_key_present?(var.to_s) }
        else
          false
        end
      end

      def models_for_router(router)
        from_lanes = load_lanes.flat_map { |lane| lane_available?(lane) ? Array(lane["models"]) : [] }
        (from_lanes + router.primary_models).map(&:to_s).uniq
      end
    end
  end
end