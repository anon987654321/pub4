# frozen_string_literal: true
#
# PATCH: add load_yaml to lib/paths.rb inside the Paths module class << self block,
# after the existing data_path / var_file methods.
#

module MASTER
  module Paths
    class << self
      # Load and parse a YAML file from the data/ directory by name (without extension).
      # Returns symbolized hash/array on success, nil on any error.
      # Centralises YAML loading so callers never repeat the find-then-parse pattern.
      # (ONE_SOURCE: one place to handle missing/malformed data files)
      def load_yaml(name)
        path = data_path(name)
        unless path
          Logging.warn("paths: data file not found: #{name}.yml", subsystem: "paths") if defined?(Logging)
          return nil
        end

        YAML.safe_load_file(path, symbolize_names: true)
      rescue Errno::ENOENT
        Logging.warn("paths: file disappeared: #{path}", subsystem: "paths") if defined?(Logging)
        nil
      rescue Psych::SyntaxError => e
        Logging.error("paths: YAML syntax error in #{name}.yml: #{e.message}", subsystem: "paths") if defined?(Logging)
        nil
      rescue StandardError => e
        Logging.error("paths: failed to load #{name}.yml: #{e.message}", subsystem: "paths") if defined?(Logging)
        nil
      end
    end
  end
end
