# frozen_string_literal: true

module Master
  module Ground
    # OAuth-before-key ordering (OpenCrabs/OpenClaw): prefer subscription/CLI lanes
    # before burning API keys on the same turn's fallback chain.
    module AuthProfileLane
      CONFIG_PATH = File.join(Master::ROOT, "data", "patterns.yml").freeze

      module_function

      def load_lanes
        raw = (Master.load_yaml(CONFIG_PATH) || {})["auth_profiles"]
        return [] unless raw.is_a?(Hash)

        Array(raw["lanes"]).select { |row| row.is_a?(Hash) && row["enabled"] != false }
          .sort_by { |row| row.fetch("priority", 99).to_i }
      rescue StandardError => e
        Swallow.log(e, context: "auth_profile_lane.load")
        []
      end

      def lane_available?(lane)
        case lane.fetch("kind", "api_key").to_s
        when "cli" then cli_lane_available?(lane)
        when "oauth" then oauth_lane_available?(lane)
        when "api_key" then api_key_lane_available?(lane)
        else false
        end
      end

      def cli_lane_available?(lane)
        cmd = lane.fetch("command", lane["binary"]).to_s
        return false if cmd.empty?
        return false if cmd == "claude" && ENV["MASTER_NO_CLAUDE_CLI"] == "1"
        return false if cmd == "agy" && ENV["MASTER_NO_AGY_CLI"] == "1"

        if cmd == "agy"
          return true if ENV["AGY_BIN"] && File.file?(ENV["AGY_BIN"]) && File.executable?(ENV["AGY_BIN"])
          home_agy = File.expand_path("~/.local/bin/agy")
          return true if File.file?(home_agy) && File.executable?(home_agy)
        end

        ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
          exe = File.join(dir, cmd)
          File.file?(exe) && File.executable?(exe)
        end
      end

      def oauth_lane_available?(lane)
        token_env = Array(lane["env_token"] || lane["env"]).first.to_s
        return false if token_env.empty?

        Master.api_key_present?(token_env) || ENV[token_env].to_s.length >= 8
      end

      def api_key_lane_available?(lane)
        envs = Array(lane["env"] || lane["env_token"])
        envs.any? { |var| Master.api_key_present?(var.to_s) }
      end

      API_KEY_LANES = %w[
        OPENROUTER_API_KEY XAI_API_KEY DEEPSEEK_API_KEY GOOGLE_API_KEY
        GEMINI_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY MISTRAL_API_KEY
      ].freeze

      def api_key_lane_present?
        API_KEY_LANES.any? { |var| Master.api_key_present?(var) }
      end

      def models_for_router(router)
        from_lanes = load_lanes.flat_map { |lane| lane_available?(lane) ? Array(lane["models"]) : [] }
        primary = router.primary_models
        # OAuth/CLI-before-key ordering saves paid tokens only while the CLI lane
        # can actually answer. agy answers "quota reached" when its subscription
        # is spent, and a dead CLI lane at the head of the chain stalls every
        # LLM-backed rule. With a real API key present, lead with those models;
        # with no key, keep the subscription-before-key order.
        ordered = api_key_lane_present? ? (primary + from_lanes) : (from_lanes + primary)
        ordered.map(&:to_s).uniq
      end
    end
  end
end
