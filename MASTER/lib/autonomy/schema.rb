# frozen_string_literal: true

require "date"
require "psych"

module Master
  module Autonomy
    # Small, dependency-free YAML contract checker.
    #
    # YAML is configuration, not executable code. Psych's safe loader gives us
    # the parser boundary; this class gives important files an explicit shape
    # before the autonomous loop trusts them.
    module Schema
      module_function

      def load_yaml(path, required: {})
        raw = File.read(path, encoding: "UTF-8")
        raise "YAML document too large: #{path}" if raw.bytesize > 10 * 1024 * 1024

        data = Psych.safe_load(raw, aliases: true, permitted_classes: [Date, Time])
        validate_hash!(data, path)
        required.each { |key, type| require_type!(data, key, type, path) }
        data
      rescue Psych::Exception => e
        raise "invalid YAML #{path}: #{e.message}"
      end

      def validate_hash!(data, path)
        raise "YAML root must be a mapping: #{path}" unless data.is_a?(Hash)
      end

      def require_type!(data, key, type, path)
        value = data[key.to_s] || data[key.to_sym]
        return value if value.is_a?(type)

        raise "YAML #{path}: #{key} must be #{type}, got #{value.class}"
      end

      def validate_boot!(data_dir)
        rules = load_yaml(File.join(data_dir, "rules.yml"), required: { "schema" => Integer, "laws" => Hash })
        raise "data/rules.yml: schema must be >= 1" if rules["schema"].to_i < 1
        raise "data/rules.yml: laws cannot be empty" if rules["laws"].empty?

        autoload = load_yaml(File.join(data_dir, "autoload.yml"), required: { "autoload" => Hash })
        autoload["autoload"].each do |reason, paths|
          raise "data/autoload.yml: #{reason} must be an array" unless paths.is_a?(Array)
        end

        %w[soul.yml runtime.yml project_context.yml].each do |name|
          path = File.join(data_dir, name)
          load_yaml(path) if File.file?(path)
        end

        true
      end
    end
  end
end
