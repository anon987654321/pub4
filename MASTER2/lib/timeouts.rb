# frozen_string_literal: true

require "yaml"

module MASTER
  # Central timeout configuration
  # Reads from constitution.yml and provides fallback defaults
  module Timeouts
    DEFAULTS = {
      http_open: 10,
      http_read: 30,
      http_write: 30,
      llm_read: 120,
      browser: 30,
      shell: 30,
      executor_wall_clock: 120,
      replicate_create: 60,
      replicate_poll: 300,
      replicate_poll_interval: 2,
      pipeline: 600,
      download: 60,
      tts_stream: 120,
    }.freeze

    class << self
      def config
        @config ||= load_config
      end

      def method_missing(name, *args)
        key = name.to_sym
        return config[key] if DEFAULTS.key?(key)
        super
      end

      def respond_to_missing?(name, include_private = false)
        DEFAULTS.key?(name.to_sym) || super
      end

      private

      def load_config
        constitution_path = File.join(__dir__, "..", "data", "constitution.yml")
        if File.exist?(constitution_path)
          data = YAML.safe_load_file(constitution_path, symbolize_names: true)
          timeouts = data&.dig(:timeouts) || {}
          DEFAULTS.merge(timeouts)
        else
          DEFAULTS.dup
        end
      end
    end
  end
end
