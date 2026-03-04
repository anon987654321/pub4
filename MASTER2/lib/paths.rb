# frozen_string_literal: true

require "yaml"
require "active_support/core_ext/module/delegation"

module Paths
  DEFAULT_ENV_KEYS = %w[RACK_ENV RAILS_ENV APP_ENV].freeze
  DEFAULT_ENV = "development"

  def self.load_data_file(file_path)
    YAML.safe_load(File.read(file_path), aliases: true) || {}
  rescue Errno::ENOENT, Psych::SyntaxError
    {}
  end

  class Config
    attr_reader :root, :env

    def initialize(root:, env: nil)
      @root = File.expand_path(root)
      @env = env || DEFAULT_ENV_KEYS.filter_map { |k| ENV[k] }.first || DEFAULT_ENV
      @data = nil
    end

    delegate :[], :fetch, to: :data

    def data
      @data ||= load_yaml
    end

    def path(*parts)
      File.join(root, *parts)
    end

    def config_path(name)
      path("config", name)
    end

    def data_path(name)
      path("data", name)
    end

    private

    def load_yaml
      Paths.load_data_file(config_path("paths.yml")).fetch(env, {})
    end
  end
end