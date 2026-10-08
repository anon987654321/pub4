# frozen_string_literal: true

require "pathname"
require "yaml"

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

        Shared::Engine.root.join("../../MASTER/data/seed_forge.yml").expand_path
      end
    end
  end
end
