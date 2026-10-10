# frozen_string_literal: true

require "pathname"
require "yaml"
require "shared/contracts"

module Shared
  module SeedForge
    DEFAULT_SEED = 20260928

    class << self
      def boot!
        config = YAML.safe_load_file(config_path, permitted_classes: [], aliases: false)
        seed = ENV.fetch(config.fetch("policy").fetch("seed_env"), DEFAULT_SEED).to_i
        Kernel.srand(seed)
        Faker::Config.random = Random.new(seed) if defined?(Faker)
        seed
      end

      def config_path
        configured = ENV["SEED_FORGE_CONFIG"].to_s
        return Pathname(configured).expand_path if configured != ""

        # MASTER is not beside the engine on the box (/home/<app>/__shared), so the
        # engine-relative walk landed on /home/MASTER and the seeds step died.
        Pathname(Shared::Contracts.root).join("MASTER", "data", "seed_forge.yml")
      end
    end
  end
end
